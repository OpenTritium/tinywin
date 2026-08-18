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
    foreach ($requiredProperty in @('hive', 'key', 'name', 'type', 'value')) {
        if (-not $parameters.ContainsKey($requiredProperty)) {
            throw "Entry '$($Operation.EntryId)' is missing registry parameter '$requiredProperty'."
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
    try {
        Invoke-TinyWinNative -FilePath 'reg.exe' -Arguments @('load', "HKLM\$loadedHive", $hivePath) -Context $Context
        $isHiveLoaded = $true
        $registryKeyPath = ([string]$parameters.key).Trim('\')
        $registryKey = "HKEY_LOCAL_MACHINE\$loadedHive\$registryKeyPath"
        New-Item -Path "Registry::$registryKey" -Force | Out-Null
        $propertyType = [string]$parameters.type
        $propertyValue = switch ($propertyType) {
            'DWord' { [int]$parameters.value; break }
            'QWord' { [long]$parameters.value; break }
            'MultiString' { [string[]]$parameters.value; break }
            default { [string]$parameters.value; break }
        }
        New-ItemProperty -Path "Registry::$registryKey" -Name ([string]$parameters.name) -PropertyType $propertyType -Value $propertyValue -Force | Out-Null
        Write-TinyWinLog -Context $Context -Message "Set offline registry value $hiveName\$($parameters.key)\$($parameters.name)"
        return [pscustomobject]@{ RegistryValue = "$hiveName\$($parameters.key)\$($parameters.name)" }
    } finally {
        if ($isHiveLoaded) {
            & reg.exe unload "HKLM\$loadedHive" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-TinyWinLog -Context $Context -Level Warning -Message "Could not unload offline registry hive '$hiveName'."
            }
        }
    }
}
