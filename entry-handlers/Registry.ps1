function Invoke-TinyWinRegistrySet {
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
    if (-not $parameters.ContainsKey('hive')) {
        throw "Entry '$($Operation.EntryId)' is missing registry parameter 'hive'."
    }

    $values = if ($parameters.ContainsKey('values')) { @($parameters.values) } else { @($parameters) }
    if ($values.Count -eq 0) {
        throw "Entry '$($Operation.EntryId)' must define at least one registry value."
    }

    foreach ($valueDefinition in $values) {
        if ($valueDefinition -isnot [System.Collections.IDictionary]) {
            throw "Entry '$($Operation.EntryId)' must define registry values as objects."
        }
        foreach ($requiredProperty in @('key', 'name', 'type', 'value')) {
            if (-not $valueDefinition.ContainsKey($requiredProperty)) {
                throw "Entry '$($Operation.EntryId)' is missing registry parameter '$requiredProperty'."
            }
        }
    }

    $hiveFiles = @{
        SOFTWARE = 'Windows/System32/config/SOFTWARE'
        SYSTEM   = 'Windows/System32/config/SYSTEM'
        DEFAULT  = 'Windows/System32/config/default'
        NTUSER   = 'Users/Default/NTUSER.DAT'
    }
    $hiveName = [string]$parameters.hive
    if (-not $hiveFiles.ContainsKey($hiveName)) {
        throw "Entry '$($Operation.EntryId)' uses unsupported registry hive '$hiveName'."
    }

    $hivePath = Join-Path $MountPath $hiveFiles[$hiveName]
    if (-not (Test-Path -LiteralPath $hivePath -PathType Leaf)) {
        throw "Offline registry hive '$hiveName' was not found at '$hivePath'."
    }

    $hivePrefix = "TinyWin_$($Context.BuildId)"
    $loadedHive = "$hivePrefix`_$hiveName"
    $isHiveLoaded = $false
    $registryValues = [System.Collections.Generic.List[string]]::new()
    try {
        Invoke-TinyWinNative -FilePath 'reg.exe' -Arguments @('load', "HKLM\$loadedHive", $hivePath) -Context $Context
        $isHiveLoaded = $true
        foreach ($valueDefinition in $values) {
            $registryKeyPath = ([string]$valueDefinition.key).Trim('\')
            $registryKey = "HKLM\$loadedHive\$registryKeyPath"
            $propertyType = [string]$valueDefinition.type
            $regValue = switch ($propertyType) {
                'DWord' {
                    [pscustomobject]@{ Type = 'REG_DWORD'; Data = [string][int]$valueDefinition.value }
                    break
                }
                'QWord' {
                    [pscustomobject]@{ Type = 'REG_QWORD'; Data = [string][long]$valueDefinition.value }
                    break
                }
                'MultiString' {
                    [pscustomobject]@{ Type = 'REG_MULTI_SZ'; Data = (@([string[]]$valueDefinition.value) -join '\0') }
                    break
                }
                'String' {
                    [pscustomobject]@{ Type = 'REG_SZ'; Data = [string]$valueDefinition.value }
                    break
                }
                'ExpandString' {
                    [pscustomobject]@{ Type = 'REG_EXPAND_SZ'; Data = [string]$valueDefinition.value }
                    break
                }
                default {
                    throw "Entry '$($Operation.EntryId)' uses unsupported registry value type '$propertyType'."
                }
            }
            Invoke-TinyWinNative -FilePath 'reg.exe' -Arguments @(
                'add',
                $registryKey,
                '/v', [string]$valueDefinition.name,
                '/t', $regValue.Type,
                '/d', $regValue.Data,
                '/f'
            ) -Context $Context
            $registryValue = "$hiveName\$($valueDefinition.key)\$($valueDefinition.name)"
            $registryValues.Add($registryValue)
            Write-TinyWinLog -Context $Context -Message "Set offline registry value $registryValue"
        }

        return [pscustomobject]@{
            RegistryValue  = $registryValues[0]
            RegistryValues = $registryValues.ToArray()
        }
    } finally {
        if ($isHiveLoaded) {
            & reg.exe unload "HKLM\$loadedHive" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-TinyWinLog -Context $Context -Level Warning -Message "Could not unload offline registry hive '$hiveName'."
            }
        }
    }
}

function Invoke-TinyWinOfflineServiceDisable {
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
    if (-not $parameters.ContainsKey('services') -and -not $parameters.ContainsKey('servicePatterns')) {
        throw "Entry '$($Operation.EntryId)' must define 'services' or 'servicePatterns'."
    }

    $serviceNames = if ($parameters.ContainsKey('services')) { @($parameters.services) } else { @() }
    $servicePatterns = if ($parameters.ContainsKey('servicePatterns')) { @($parameters.servicePatterns) } else { @() }
    if (@($serviceNames).Length -eq 0 -and @($servicePatterns).Length -eq 0) {
        throw "Entry '$($Operation.EntryId)' must define at least one service or service pattern."
    }

    foreach ($serviceName in $serviceNames) {
        if ([string]::IsNullOrWhiteSpace([string]$serviceName) -or [string]$serviceName -notmatch '^[A-Za-z0-9_.-]+$') {
            throw "Entry '$($Operation.EntryId)' has an invalid service name '$serviceName'."
        }
    }
    foreach ($servicePattern in $servicePatterns) {
        if ([string]::IsNullOrWhiteSpace([string]$servicePattern) -or [string]$servicePattern -notmatch '^[A-Za-z0-9_.?*-]+$') {
            throw "Entry '$($Operation.EntryId)' has an invalid service pattern '$servicePattern'."
        }
    }

    $hivePath = Join-Path $MountPath 'Windows/System32/config/SYSTEM'
    if (-not (Test-Path -LiteralPath $hivePath -PathType Leaf)) {
        throw "Offline registry hive 'SYSTEM' was not found at '$hivePath'."
    }

    $loadedHive = "TinyWin_$($Context.BuildId)_SYSTEM"
    $isHiveLoaded = $false
    $disabledServices = [System.Collections.Generic.List[string]]::new()
    $skippedServices = [System.Collections.Generic.List[string]]::new()
    try {
        Invoke-TinyWinNative -FilePath 'reg.exe' -Arguments @('load', "HKLM\$loadedHive", $hivePath) -Context $Context
        $isHiveLoaded = $true

        $selectOutput = & reg.exe query "HKLM\$loadedHive\Select" /v Current 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Could not resolve the active control set for entry '$($Operation.EntryId)'."
        }

        $currentControlSet = 1
        foreach ($line in $selectOutput) {
            $match = [regex]::Match([string]$line, '0x([0-9A-Fa-f]+)')
            if ($match.Success) {
                $currentControlSet = [Convert]::ToInt32($match.Groups[1].Value, 16)
                break
            }
        }
        $controlSetName = 'ControlSet{0:D3}' -f $currentControlSet

        $servicesRoot = "HKLM\$loadedHive\$controlSetName\Services"
        $serviceQueryOutput = @(& reg.exe query $servicesRoot 2>$null)
        foreach ($servicePattern in $servicePatterns) {
            $patternMatches = [System.Collections.Generic.List[string]]::new()
            $prefix = "$servicesRoot\"
            foreach ($queryLine in $serviceQueryOutput) {
                $candidateKey = ([string]$queryLine).Trim()
                if (-not $candidateKey.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                $candidateName = $candidateKey.Substring($prefix.Length)
                if ($candidateName -notmatch '\\' -and $candidateName -like [string]$servicePattern) {
                    [void]$patternMatches.Add($candidateName)
                }
            }
            if (@($patternMatches).Length -eq 0) {
                $skippedServices.Add([string]$servicePattern)
                Write-TinyWinLog -Context $Context -Level Warning -Message "No services matched pattern '$servicePattern' in $controlSetName; skipping."
                continue
            }
            foreach ($patternMatch in $patternMatches) {
                $serviceNames += [string]$patternMatch
            }
        }

        foreach ($serviceName in ($serviceNames | Select-Object -Unique)) {
            $serviceKey = "HKLM\$loadedHive\$controlSetName\Services\$serviceName"
            & reg.exe query $serviceKey *> $null
            if ($LASTEXITCODE -ne 0) {
                $skippedServices.Add([string]$serviceName)
                Write-TinyWinLog -Context $Context -Level Warning -Message "Service '$serviceName' was not present in $controlSetName; skipping."
                continue
            }

            try {
                Invoke-TinyWinNative -FilePath 'reg.exe' -Arguments @(
                    'add',
                    $serviceKey,
                    '/v', 'Start',
                    '/t', 'REG_DWORD',
                    '/d', '4',
                    '/f'
                ) -Context $Context
                [void]$disabledServices.Add([string]$serviceName)
                Write-TinyWinLog -Context $Context -Message "Disabled offline service $serviceName."
            } catch {
                [void]$skippedServices.Add([string]$serviceName)
                Write-TinyWinLog -Context $Context -Level Warning -Message "Could not modify offline service '$serviceName'; skipping: $($_.Exception.Message)"
            }
        }

        return [pscustomobject]@{
            ControlSet       = $controlSetName
            DisabledServices = $disabledServices.ToArray()
            SkippedServices  = $skippedServices.ToArray()
        }
    } finally {
        if ($isHiveLoaded) {
            & reg.exe unload "HKLM\$loadedHive" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-TinyWinLog -Context $Context -Level Warning -Message "Could not unload offline registry hive 'SYSTEM'."
            }
        }
    }
}

function Invoke-TinyWinOfflineServiceConfigure {
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
    foreach ($requiredName in @('startMode')) {
        if (-not $parameters.ContainsKey($requiredName)) {
            throw "Entry '$($Operation.EntryId)' is missing registry parameter '$requiredName'."
        }
    }
    if (-not $parameters.ContainsKey('services') -and -not $parameters.ContainsKey('servicePatterns')) {
        throw "Entry '$($Operation.EntryId)' must define 'services' or 'servicePatterns'."
    }
    $serviceNames = if ($parameters.ContainsKey('services')) { @($parameters.services) } else { @() }
    $servicePatterns = if ($parameters.ContainsKey('servicePatterns')) { @($parameters.servicePatterns) } else { @() }
    if (@($serviceNames).Length -eq 0 -and @($servicePatterns).Length -eq 0) {
        throw "Entry '$($Operation.EntryId)' must define at least one service or service pattern."
    }
    $startMode = [string]$parameters.startMode
    $startValues = @{
        Disabled    = 4
        Manual      = 3
        Auto        = 2
        DelayedAuto = 2
    }
    if (-not $startValues.ContainsKey($startMode)) {
        throw "Entry '$($Operation.EntryId)' uses unsupported service startMode '$startMode'."
    }
    foreach ($serviceName in $serviceNames) {
        if ([string]::IsNullOrWhiteSpace([string]$serviceName) -or [string]$serviceName -notmatch '^[A-Za-z0-9_.-]+$') {
            throw "Entry '$($Operation.EntryId)' has an invalid service name '$serviceName'."
        }
    }
    foreach ($servicePattern in $servicePatterns) {
        if ([string]::IsNullOrWhiteSpace([string]$servicePattern) -or [string]$servicePattern -notmatch '^[A-Za-z0-9_.?*-]+$') {
            throw "Entry '$($Operation.EntryId)' has an invalid service pattern '$servicePattern'."
        }
    }

    $hivePath = Join-Path $MountPath 'Windows/System32/config/SYSTEM'
    if (-not (Test-Path -LiteralPath $hivePath -PathType Leaf)) {
        throw "Offline registry hive 'SYSTEM' was not found at '$hivePath'."
    }

    $loadedHive = "TinyWin_$($Context.BuildId)_SYSTEM"
    $isHiveLoaded = $false
    $configuredServices = [System.Collections.Generic.List[string]]::new()
    $skippedServices = [System.Collections.Generic.List[string]]::new()
    try {
        Invoke-TinyWinNative -FilePath 'reg.exe' -Arguments @('load', "HKLM\$loadedHive", $hivePath) -Context $Context
        $isHiveLoaded = $true
        $selectOutput = & reg.exe query "HKLM\$loadedHive\Select" /v Current 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Could not resolve the active control set for entry '$($Operation.EntryId)'."
        }
        $currentControlSet = 1
        foreach ($line in $selectOutput) {
            $selectMatch = [regex]::Match([string]$line, '0x([0-9A-Fa-f]+)')
            if ($selectMatch.Success) {
                $currentControlSet = [Convert]::ToInt32($selectMatch.Groups[1].Value, 16)
                break
            }
        }
        $controlSetName = 'ControlSet{0:D3}' -f $currentControlSet
        $servicesRoot = "HKLM\$loadedHive\$controlSetName\Services"
        $serviceQueryOutput = @(& reg.exe query $servicesRoot 2>$null)
        foreach ($servicePattern in $servicePatterns) {
            $patternMatches = [System.Collections.Generic.List[string]]::new()
            $prefix = "$servicesRoot\"
            foreach ($queryLine in $serviceQueryOutput) {
                $candidateKey = ([string]$queryLine).Trim()
                if (-not $candidateKey.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                $candidateName = $candidateKey.Substring($prefix.Length)
                if ($candidateName -notmatch '\\' -and $candidateName -like [string]$servicePattern) {
                    [void]$patternMatches.Add($candidateName)
                }
            }
            if (@($patternMatches).Length -eq 0) {
                $skippedServices.Add([string]$servicePattern)
                Write-TinyWinLog -Context $Context -Level Warning -Message "No services matched pattern '$servicePattern' in $controlSetName; skipping."
                continue
            }
            foreach ($patternMatch in $patternMatches) {
                $serviceNames += [string]$patternMatch
            }
        }
        foreach ($serviceName in ($serviceNames | Select-Object -Unique)) {
            $serviceKey = "HKLM\$loadedHive\$controlSetName\Services\$serviceName"
            & reg.exe query $serviceKey *> $null
            if ($LASTEXITCODE -ne 0) {
                $skippedServices.Add([string]$serviceName)
                Write-TinyWinLog -Context $Context -Level Warning -Message "Service '$serviceName' was not present in $controlSetName; skipping."
                continue
            }
            try {
                Invoke-TinyWinNative -FilePath 'reg.exe' -Arguments @('add', $serviceKey, '/v', 'Start', '/t', 'REG_DWORD', '/d', $startValues[$startMode], '/f') -Context $Context
                $delayedAutoStart = if ($startMode -eq 'DelayedAuto') { 1 } else { 0 }
                Invoke-TinyWinNative -FilePath 'reg.exe' -Arguments @('add', $serviceKey, '/v', 'DelayedAutoStart', '/t', 'REG_DWORD', '/d', $delayedAutoStart, '/f') -Context $Context
                [void]$configuredServices.Add([string]$serviceName)
                Write-TinyWinLog -Context $Context -Message "Configured offline service $serviceName as $startMode."
            } catch {
                [void]$skippedServices.Add([string]$serviceName)
                Write-TinyWinLog -Context $Context -Level Warning -Message "Could not modify offline service '$serviceName'; skipping: $($_.Exception.Message)"
            }
        }
        return [pscustomobject]@{
            ControlSet         = $controlSetName
            StartMode          = $startMode
            ConfiguredServices = $configuredServices.ToArray()
            SkippedServices    = $skippedServices.ToArray()
        }
    } finally {
        if ($isHiveLoaded) {
            & reg.exe unload "HKLM\$loadedHive" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-TinyWinLog -Context $Context -Level Warning -Message "Could not unload offline registry hive '$loadedHive'."
            }
        }
    }
}
