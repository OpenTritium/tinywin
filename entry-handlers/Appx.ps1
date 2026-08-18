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
    foreach ($package in @(Get-AppxProvisionedPackage -Path $MountPath -ErrorAction Stop)) {
        if (@($patterns | Where-Object { $package.DisplayName -like $_ }).Count -eq 0) {
            continue
        }

        Write-TinyWinLog -Context $Context -Message "Removing provisioned Appx: $($package.DisplayName)"
        Remove-AppxProvisionedPackage -Path $MountPath -PackageName $package.PackageName -ErrorAction Stop | Out-Null
        $removedApps.Add($package.DisplayName)
    }

    return [pscustomobject]@{ RemovedApps = $removedApps.ToArray() }
}
