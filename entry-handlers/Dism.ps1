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
