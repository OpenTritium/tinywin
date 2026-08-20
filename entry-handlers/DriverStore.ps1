using namespace System.Collections.Generic

function Grant-TinyWinDriverStoreDeleteAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DriverDirectory,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $takeOwnPath = (Get-Command -Name 'takeown.exe' -CommandType Application -ErrorAction Stop).Source
    $icaclsPath = (Get-Command -Name 'icacls.exe' -CommandType Application -ErrorAction Stop).Source

    Write-TinyWinLog -Context $Context -Message "Taking ownership of Driver Store package: $DriverDirectory"
    & $takeOwnPath '/F' $DriverDirectory '/A' '/R' '/D' 'Y' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw [UnauthorizedAccessException]::new("Unable to take ownership of Driver Store package '$DriverDirectory' (takeown.exe exit code $LASTEXITCODE).")
    }

    Write-TinyWinLog -Context $Context -Message "Granting Administrators delete access to Driver Store package: $DriverDirectory"
    # Protected Driver Store files do not inherit an (OI)(CI) rule from the package directory.
    # Grant each traversed file and directory directly so the final Remove-Item has DELETE access.
    & $icaclsPath $DriverDirectory '/grant' '*S-1-5-32-544:F' '/T' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw [UnauthorizedAccessException]::new("Unable to grant delete access to Driver Store package '$DriverDirectory' (icacls.exe exit code $LASTEXITCODE).")
    }
}

function Invoke-TinyWinDriverStoreRemoveInbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Operation,

        [Parameter(Mandatory)]
        [string]$MountPath,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $parameters = $Operation.Parameters
    if (-not $parameters.ContainsKey('infNames')) {
        throw "Entry '$($Operation.EntryId)' must define driver parameter 'infNames'."
    }

    $infNames = @($parameters.infNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($infNames.Count -eq 0) {
        throw "Entry '$($Operation.EntryId)' must define at least one driver INF name."
    }

    $driverStoreRoot = Join-Path $MountPath 'Windows/System32/DriverStore/FileRepository'
    if (-not (Test-Path -LiteralPath $driverStoreRoot -PathType Container)) {
        throw "Driver Store was not found at '$driverStoreRoot'."
    }
    $driverStoreRoot = (Resolve-Path -LiteralPath $driverStoreRoot -ErrorAction Stop).Path.TrimEnd('\')

    if (-not $Context.ContainsKey('TinyWinDriverStoreMap')) {
        Write-TinyWinLog -Context $Context -Message 'Building offline Driver Store index.'
        $driverMap = @{}
        foreach ($driver in @(Get-WindowsDriver -Path $MountPath -All -ErrorAction Stop)) {
            $driverName = [IO.Path]::GetFileName([string]$driver.Driver)
            if (-not [string]::IsNullOrWhiteSpace($driverName)) {
                $driverMap[$driverName.ToUpperInvariant()] = $driver
            }
        }
        $Context['TinyWinDriverStoreMap'] = $driverMap
        Write-TinyWinLog -Context $Context -Message "Offline Driver Store index contains $($driverMap.Count) packages."
    }

    $driverMap = $Context['TinyWinDriverStoreMap']
    $removedDrivers = [List[string]]::new()
    $skippedDrivers = [List[string]]::new()
    $removedDirectories = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $skippedDirectories = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($infName in $infNames) {
        $requestedInfName = [string]$infName
        $normalizedInfName = [IO.Path]::GetFileName($requestedInfName)
        if ($normalizedInfName -ne $requestedInfName -or -not $normalizedInfName.EndsWith('.inf', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Entry '$($Operation.EntryId)' uses invalid driver INF name '$requestedInfName'."
        }

        $driver = $driverMap[$normalizedInfName.ToUpperInvariant()]
        if (-not $driver) {
            Write-TinyWinLog -Context $Context -Message "Skipping unavailable Driver Store package: $normalizedInfName"
            $skippedDrivers.Add($normalizedInfName)
            continue
        }

        $driverInfPath = (Resolve-Path -LiteralPath ([string]$driver.OriginalFileName) -ErrorAction Stop).Path
        if (-not [string]::Equals([IO.Path]::GetFileName($driverInfPath), $normalizedInfName, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Driver Store package '$normalizedInfName' resolved to an unexpected INF path."
        }

        $driverDirectory = Split-Path -Parent $driverInfPath
        if (-not $driverDirectory.StartsWith("$driverStoreRoot\", [StringComparison]::OrdinalIgnoreCase)) {
            throw "Driver Store package '$normalizedInfName' resolved outside FileRepository."
        }

        if ($skippedDirectories.Contains($driverDirectory)) {
            $skippedDrivers.Add($normalizedInfName)
            continue
        }

        if ($removedDirectories.Add($driverDirectory)) {
            Write-TinyWinLog -Context $Context -Level Warning -Message "Removing Driver Store package: $normalizedInfName"
            try {
                Grant-TinyWinDriverStoreDeleteAccess -DriverDirectory $driverDirectory -Context $Context
                Remove-Item -LiteralPath $driverDirectory -Recurse -Force -ErrorAction Stop
            } catch [UnauthorizedAccessException] {
                Write-TinyWinLog -Context $Context -Level Warning -Message "Skipping protected Driver Store package: $normalizedInfName ($($_.Exception.Message))"
                $skippedDirectories.Add($driverDirectory) | Out-Null
                $skippedDrivers.Add($normalizedInfName)
                continue
            }
        }
        $removedDrivers.Add($normalizedInfName)
    }

    return [pscustomobject]@{
        RemovedDrivers = $removedDrivers.ToArray()
        SkippedDrivers = $skippedDrivers.ToArray()
    }
}
