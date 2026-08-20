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

    try {
        Invoke-TinyWinNative -FilePath 'dism.exe' -Arguments $arguments -Context $Context
    } catch {
        # Some Server 2025 images reject offline StartComponentCleanup with
        # DISM error 4350 even though normal feature/package servicing works.
        # Component cleanup is an optional size optimization, so preserve the
        # build and record the limitation; unrelated DISM failures remain fatal.
        if ([string]$_.Exception.Message -match 'exit code 4350') {
            Write-TinyWinLog -Context $Context -Level Warning -Message 'Skipping component cleanup: this mounted image returned DISM error 4350 during StartComponentCleanup.'
            return [pscustomobject]@{
                Arguments = $arguments
                Skipped   = $true
                Reason    = 'DISM error 4350'
            }
        }

        throw
    }

    return [pscustomobject]@{ Arguments = $arguments; Skipped = $false }
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
    # An entry may target optional features, capabilities, or both. Parameters are
    # loaded as hashtables, so absent optional fields must be normalized explicitly.
    $features = @()
    if ($parameters.ContainsKey('features')) {
        $features = @($parameters['features'] | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    $capabilities = @()
    if ($parameters.ContainsKey('capabilities')) {
        $capabilities = @($parameters['capabilities'] | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    if ($features.Count -eq 0 -and $capabilities.Count -eq 0) {
        throw "Entry '$($Operation.EntryId)' must define features or capabilities."
    }

    $removePayload = -not $parameters.ContainsKey('removePayload') -or [bool]$parameters.removePayload
    $removedFeatures = [List[string]]::new()
    $skippedFeatures = [List[string]]::new()
    foreach ($featureName in $features) {
        try {
            $feature = Get-WindowsOptionalFeature -Path $MountPath -FeatureName ([string]$featureName) -ErrorAction Stop
        } catch {
            $message = [string]$_.Exception.Message
            if ($message -match 'file cannot be used on this computer|该文件当前不能用于此计算机|OptionalFeature.*not supported|不支持.*Feature') {
                Write-TinyWinLog -Context $Context -Level Warning -Message "Skipping optional component entry '$($Operation.EntryId)': this edition does not expose the Optional Feature servicing provider."
                return [pscustomobject]@{
                    RemovedFeatures     = @()
                    SkippedFeatures     = @($features)
                    RemovedCapabilities = @()
                    SkippedCapabilities = @($capabilities)
                    Skipped              = $true
                    Reason              = 'Optional Feature servicing provider is unavailable for this edition.'
                }
            }

            throw
        }
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
        try {
            Disable-WindowsOptionalFeature @disableArguments | Out-Null
        } catch {
            # CBS_E_INVALID_INSTALL_STATE: the feature is exposed by DISM but is
            # permanent for this edition and cannot be disabled offline.
            if ($_.Exception.HResult -eq -2146498541) {
                Write-TinyWinLog -Context $Context -Level Warning -Message "Skipping unselectable optional feature: $featureName (CBS_E_INVALID_INSTALL_STATE)"
                $skippedFeatures.Add([string]$featureName)
                continue
            }

            throw
        }
        $removedFeatures.Add([string]$featureName)
    }

    $removedCapabilities = [List[string]]::new()
    $skippedCapabilities = [List[string]]::new()
    foreach ($capabilityName in $capabilities) {
        try {
            $capability = Get-WindowsCapability -Path $MountPath -Name ([string]$capabilityName) -ErrorAction Stop
        } catch {
            $message = [string]$_.Exception.Message
            if ($message -match 'file cannot be used on this computer|该文件当前不能用于此计算机|Capability.*not supported|不支持.*Capability') {
                Write-TinyWinLog -Context $Context -Level Warning -Message "Skipping capability entry '$($Operation.EntryId)': this edition does not expose the Capability servicing provider."
                return [pscustomobject]@{
                    RemovedFeatures     = $removedFeatures.ToArray()
                    SkippedFeatures     = $skippedFeatures.ToArray()
                    RemovedCapabilities = @()
                    SkippedCapabilities = @($capabilities)
                    Skipped              = $true
                    Reason              = 'Capability servicing provider is unavailable for this edition.'
                }
            }

            throw
        }
        if (-not $capability -or $capability.State -ne 'Installed') {
            Write-TinyWinLog -Context $Context -Message "Skipping unavailable capability: $capabilityName"
            continue
        }

        Write-TinyWinLog -Context $Context -Message "Removing capability: $capabilityName"
        try {
            Remove-WindowsCapability -Path $MountPath -Name ([string]$capabilityName) -ErrorAction Stop | Out-Null
        } catch {
            # CBS_E_CANNOT_UNINSTALL: a feature-on-demand is permanent in this
            # edition. It remains in the image, but must not abort other entries.
            if ($_.Exception.HResult -eq -2146498523) {
                Write-TinyWinLog -Context $Context -Level Warning -Message "Skipping permanent capability: $capabilityName (CBS_E_CANNOT_UNINSTALL)"
                $skippedCapabilities.Add([string]$capabilityName)
                continue
            }

            throw
        }
        $removedCapabilities.Add([string]$capabilityName)
    }

    return [pscustomobject]@{
        RemovedFeatures     = $removedFeatures.ToArray()
        SkippedFeatures     = $skippedFeatures.ToArray()
        RemovedCapabilities = $removedCapabilities.ToArray()
        SkippedCapabilities = $skippedCapabilities.ToArray()
    }
}
