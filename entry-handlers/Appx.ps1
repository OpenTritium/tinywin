using namespace System.Collections.Generic

function Invoke-TinyWinAppxRemove {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Operation,

        [Parameter(Mandatory)]
        [string]$MountPath,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $patterns = @($Operation.Parameters.patterns)
    if ($patterns.Count -eq 0) {
        throw "Entry '$($Operation.EntryId)' must define at least one Appx pattern."
    }

    $removedApps = [List[string]]::new()
    $packages = @()
    try {
        $packages = @(Get-AppxProvisionedPackage -Path $MountPath -ErrorAction Stop)
    } catch {
        # Server editions may not expose the AppX servicing provider at all.
        # Treat that known capability gap as a skipped optional entry, while
        # preserving unrelated DISM failures as build errors.
        $message = [string]$_.Exception.Message
        $unsupportedAppx = $message -match 'file cannot be used on this computer|该文件当前不能用于此计算机|AppX.*not supported|不支持.*AppX'
        if (-not $unsupportedAppx) {
            throw
        }

        Write-TinyWinLog -Context $Context -Level Warning -Message "Skipping AppX entry '$($Operation.EntryId)': the mounted edition does not expose an AppX servicing provider."
        return [pscustomobject]@{
            RemovedApps = @()
            Skipped     = $true
            Reason      = 'AppX servicing provider is unavailable for this edition.'
        }
    }

    foreach ($package in $packages) {
        if (@($patterns | Where-Object { $package.DisplayName -like $_ }).Count -eq 0) {
            continue
        }

        Write-TinyWinLog -Context $Context -Message "Removing provisioned Appx: $($package.DisplayName)"
        Remove-AppxProvisionedPackage -Path $MountPath -PackageName $package.PackageName -ErrorAction Stop | Out-Null
        $removedApps.Add($package.DisplayName)
    }

    return [pscustomobject]@{ RemovedApps = $removedApps.ToArray() }
}
