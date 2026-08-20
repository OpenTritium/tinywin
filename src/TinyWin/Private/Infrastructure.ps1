using namespace System.IO
using namespace System.Security.Principal

function Write-TinyWinLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Level = 'Information'
    )

    $entry = [pscustomobject]@{
        Timestamp = [DateTime]::UtcNow.ToString('O')
        Level     = $Level
        Message   = $Message
    }

    [void]$Context.Events.Add($entry)
    if ($Context.ContainsKey('SuppressConsoleLog') -and $Context.SuppressConsoleLog) {
        return
    }

    $consoleLine = "[$($entry.Timestamp)] [$Level] $Message"
    if ($Context.ContainsKey('UseConsoleOutput') -and $Context.UseConsoleOutput) {
        [Console]::Out.WriteLine($consoleLine)
    } else {
        Write-Host $consoleLine
    }
}

function Invoke-TinyWinNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    Write-TinyWinLog -Context $Context -Message "Running: $FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments 2>&1 | ForEach-Object {
        $nativeLine = $_.ToString().Trim()
        if ($nativeLine) {
            Write-TinyWinLog -Context $Context -Message "  $nativeLine"
        }
    }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Command failed with exit code ${exitCode}: $FilePath"
    }
}

function Assert-TinyWinAdministrator {
    [CmdletBinding()]
    param()

    $identity = [WindowsIdentity]::GetCurrent()
    $principal = [WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([WindowsBuiltInRole]::Administrator)) {
        throw 'Run TinyWin from an elevated PowerShell session.'
    }
}

function Resolve-TinyWinSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $resolvedPath = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
    if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
        return [pscustomobject]@{
            RootPath  = $resolvedPath
            IsMounted = $false
            ImagePath = $null
        }
    }

    if ([Path]::GetExtension($resolvedPath) -ne '.iso') {
        throw 'SourcePath must be a Windows installation-media directory or an ISO file.'
    }

    Write-TinyWinLog -Context $Context -Message "Mounting source ISO: $resolvedPath"
    $diskImage = Mount-DiskImage -ImagePath $resolvedPath -PassThru -ErrorAction Stop
    $volume = $diskImage | Get-Volume -ErrorAction Stop | Where-Object DriveLetter | Select-Object -First 1
    if (-not $volume) {
        Dismount-DiskImage -ImagePath $resolvedPath -ErrorAction SilentlyContinue | Out-Null
        throw "No drive letter was assigned when mounting '$resolvedPath'."
    }

    return [pscustomobject]@{
        RootPath  = "$($volume.DriveLetter):\"
        IsMounted = $true
        ImagePath = $resolvedPath
    }
}

function Test-TinyWinMedia {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $sourcesPath = Join-Path $RootPath 'sources'
    $hasBootWim = Test-Path -LiteralPath (Join-Path $sourcesPath 'boot.wim') -PathType Leaf
    $hasInstallImage = @('install.wim', 'install.esd') |
        ForEach-Object { Test-Path -LiteralPath (Join-Path $sourcesPath $_) -PathType Leaf } |
        Where-Object { $_ } |
        Select-Object -First 1

    if (-not $hasBootWim -or -not $hasInstallImage) {
        throw "'$RootPath' is not supported Windows installation media. Expected sources\boot.wim and sources\install.wim or install.esd."
    }
}

function Copy-TinyWinMedia {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$DestinationRoot,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    Write-TinyWinLog -Context $Context -Message "Copying installation media to $DestinationRoot with 16 workers"
    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    & robocopy.exe $SourceRoot $DestinationRoot /E /MT:16 /R:1 /W:1 /COPY:DAT /DCOPY:DAT /NFL /NDL /NP 2>&1 |
        ForEach-Object {
            $nativeLine = $_.ToString().Trim()
            if ($nativeLine) {
                Write-TinyWinLog -Context $Context -Message "  $nativeLine"
            }
        }
    $exitCode = $LASTEXITCODE
    if ($exitCode -gt 7) {
        throw "Media copy failed with robocopy exit code ${exitCode}."
    }
    Write-TinyWinLog -Context $Context -Message 'Installation media copy completed.'
}
