using namespace System.Collections.Generic

function Invoke-TinyWinPackageRemove {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Operation,

        [Parameter(Mandatory)]
        [string]$MountPath,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $patterns = @($Operation.Parameters.packagePatterns)
    if ($patterns.Count -eq 0) {
        throw "Entry '$($Operation.EntryId)' must define at least one package pattern."
    }

    try {
        $packages = @(Get-WindowsPackage -Path $MountPath -ErrorAction Stop)
    } catch {
        $message = [string]$_.Exception.Message
        if ($message -match 'file cannot be used on this computer|该文件当前不能用于此计算机|Package.*not supported|不支持.*Package') {
            Write-TinyWinLog -Context $Context -Level Warning -Message "Skipping package entry '$($Operation.EntryId)': this edition does not expose the CBS package servicing provider."
            return [pscustomobject]@{
                RemovedPackages = @()
                SkippedPackages = @($patterns)
                Skipped         = $true
                Reason          = 'CBS package servicing provider is unavailable for this edition.'
            }
        }

        throw
    }
    $matchingPackages = @($packages | Where-Object {
            $packageName = [string]$_.PackageName
            @($patterns | Where-Object { $packageName -match [string]$_ }).Count -gt 0
        })
    if ($matchingPackages.Count -eq 0) {
        Write-TinyWinLog -Context $Context -Message "No matching CBS package found for entry '$($Operation.EntryId)'."
        return [pscustomobject]@{ RemovedPackages = @(); SkippedPackages = @() }
    }

    $removedPackages = [List[string]]::new()
    $skippedPackages = [List[string]]::new()
    foreach ($package in $matchingPackages) {
        if ([string]$package.PackageState -notin @('Installed', 'Staged', 'InstallPending')) {
            $skippedPackages.Add([string]$package.PackageName)
            Write-TinyWinLog -Context $Context -Message "Skipping non-removable CBS package: $($package.PackageName) [$($package.PackageState)]"
            continue
        }

        Write-TinyWinLog -Context $Context -Message "Removing CBS package: $($package.PackageName)"
        Remove-WindowsPackage -Path $MountPath -PackageName ([string]$package.PackageName) -NoRestart -ErrorAction Stop | Out-Null
        $removedPackages.Add([string]$package.PackageName)
    }

    return [pscustomobject]@{
        RemovedPackages = $removedPackages.ToArray()
        SkippedPackages = $skippedPackages.ToArray()
    }
}
