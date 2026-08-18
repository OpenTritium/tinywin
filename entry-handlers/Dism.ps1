using namespace System.Collections.Generic

function Invoke-TinyWinComponentCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Operation,

        [Parameter(Mandatory)]
        [string]$MountPath,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $arguments = @("/Image:$MountPath", '/Cleanup-Image', '/StartComponentCleanup')
    if ([bool]$Operation.Parameters.resetBase) {
        $arguments += '/ResetBase'
        Write-TinyWinLog -Context $Context -Level Warning -Message 'ResetBase is enabled; installed updates cannot be uninstalled from the resulting image.'
    }

    Invoke-TinyWinNative -FilePath 'dism.exe' -Arguments $arguments -Context $Context
    return [pscustomobject]@{ Arguments = $arguments }
}

function Invoke-TinyWinOptionalComponentRemove {
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
    $features = @($parameters.features | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $capabilities = @($parameters.capabilities | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($features.Count -eq 0 -and $capabilities.Count -eq 0) {
        throw "Entry '$($Operation.EntryId)' must define features or capabilities."
    }

    $protectedFeaturePattern = 'Firewall|UserAccountControl|UAC'
    $removePayload = -not $parameters.ContainsKey('removePayload') -or [bool]$parameters.removePayload
    $removedFeatures = [List[string]]::new()
    foreach ($featureName in $features) {
        if ([string]$featureName -match $protectedFeaturePattern) {
            throw "Entry '$($Operation.EntryId)' cannot disable protected UAC or firewall functionality."
        }

        $feature = Get-WindowsOptionalFeature -Path $MountPath -FeatureName ([string]$featureName) -ErrorAction SilentlyContinue
        if (-not $feature -or $feature.State -eq 'DisabledWithPayloadRemoved' -or ($feature.State -eq 'Disabled' -and -not $removePayload)) {
            Write-TinyWinLog -Context $Context -Message "Skipping unavailable optional feature: $featureName"
            continue
        }

        Write-TinyWinLog -Context $Context -Message "Disabling optional feature: $featureName"
        $disableArguments = @{
            Path        = $MountPath
            FeatureName = [string]$featureName
            NoRestart   = $true
            ErrorAction = 'Stop'
        }
        if ($removePayload) {
            $disableArguments['Remove'] = $true
        }
        Disable-WindowsOptionalFeature @disableArguments | Out-Null
        $removedFeatures.Add([string]$featureName)
    }

    $removedCapabilities = [List[string]]::new()
    foreach ($capabilityName in $capabilities) {
        $capability = Get-WindowsCapability -Path $MountPath -Name ([string]$capabilityName) -ErrorAction SilentlyContinue
        if (-not $capability -or $capability.State -ne 'Installed') {
            Write-TinyWinLog -Context $Context -Message "Skipping unavailable capability: $capabilityName"
            continue
        }

        Write-TinyWinLog -Context $Context -Message "Removing capability: $capabilityName"
        Remove-WindowsCapability -Path $MountPath -Name ([string]$capabilityName) -ErrorAction Stop | Out-Null
        $removedCapabilities.Add([string]$capabilityName)
    }

    return [pscustomobject]@{
        RemovedFeatures     = $removedFeatures.ToArray()
        RemovedCapabilities = $removedCapabilities.ToArray()
    }
}
