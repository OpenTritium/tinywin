using namespace System.Collections.Generic
using namespace System.IO

function Grant-TinyWinPathDeleteAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TargetPath,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $takeOwnPath = (Get-Command -Name 'takeown.exe' -CommandType Application -ErrorAction Stop).Source
    $icaclsPath = (Get-Command -Name 'icacls.exe' -CommandType Application -ErrorAction Stop).Source
    Write-TinyWinLog -Context $Context -Message "Taking ownership of image path: $TargetPath"
    & $takeOwnPath '/F' $TargetPath '/A' '/R' '/D' 'Y' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to take ownership of '$TargetPath' (takeown.exe exit code $LASTEXITCODE)."
    }

    Write-TinyWinLog -Context $Context -Message "Granting Administrators delete access to image path: $TargetPath"
    & $icaclsPath $TargetPath '/grant' '*S-1-5-32-544:F' '/T' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to grant delete access to '$TargetPath' (icacls.exe exit code $LASTEXITCODE)."
    }
}

function Invoke-TinyWinPathRemove {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Operation,

        [Parameter(Mandatory)]
        [string]$MountPath,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $paths = @($Operation.Parameters.paths)
    if ($paths.Count -eq 0) {
        throw "Entry '$($Operation.EntryId)' must define at least one relative path."
    }

    $mountRoot = [Path]::GetFullPath($MountPath).TrimEnd('\') + '\'
    $removedPaths = [List[string]]::new()
    $skippedPaths = [List[string]]::new()
    foreach ($relativePath in $paths) {
        $normalizedPath = ([string]$relativePath).Replace('/', '\').TrimStart('\')
        if ([string]::IsNullOrWhiteSpace($normalizedPath) -or [Path]::IsPathRooted($normalizedPath) -or $normalizedPath -match '(^|\\)\.\.?(\\|$)') {
            throw "Entry '$($Operation.EntryId)' contains an unsafe relative path '$relativePath'."
        }

        $targetPath = [Path]::GetFullPath((Join-Path $MountPath $normalizedPath))
        if (-not $targetPath.StartsWith($mountRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Entry '$($Operation.EntryId)' resolved outside the mounted image: '$relativePath'."
        }
        if (-not (Test-Path -LiteralPath $targetPath)) {
            $skippedPaths.Add($normalizedPath)
            Write-TinyWinLog -Context $Context -Message "Skipping unavailable image path: $normalizedPath"
            continue
        }

        Write-TinyWinLog -Context $Context -Message "Removing image path: $normalizedPath"
        try {
            Remove-Item -LiteralPath $targetPath -Recurse -Force -ErrorAction Stop
        } catch [UnauthorizedAccessException] {
            Grant-TinyWinPathDeleteAccess -TargetPath $targetPath -Context $Context
            Remove-Item -LiteralPath $targetPath -Recurse -Force -ErrorAction Stop
        }
        $removedPaths.Add($normalizedPath)
    }

    return [pscustomobject]@{
        RemovedPaths = $removedPaths.ToArray()
        SkippedPaths = $skippedPaths.ToArray()
    }
}
