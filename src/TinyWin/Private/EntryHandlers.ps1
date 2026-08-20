function Get-TinyWinEntryHandlerMap {
    return @{
        'Appx.RemoveProvisioned'           = 'Invoke-TinyWinAppxRemove'
        'Registry.SetOfflineValue'         = 'Invoke-TinyWinRegistrySet'
        'Registry.DisableOfflineService'   = 'Invoke-TinyWinOfflineServiceDisable'
        'Registry.ConfigureOfflineService' = 'Invoke-TinyWinOfflineServiceConfigure'
        'Dism.ComponentCleanup'            = 'Invoke-TinyWinComponentCleanup'
        'Dism.RemoveOptionalComponent'     = 'Invoke-TinyWinOptionalComponentRemove'
        'Dism.RemovePackage'               = 'Invoke-TinyWinPackageRemove'
        'DriverStore.RemoveInbox'          = 'Invoke-TinyWinDriverStoreRemoveInbox'
        'Filesystem.RemovePath'            = 'Invoke-TinyWinPathRemove'
    }
}

function Invoke-TinyWinEntryPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Plan,

        [Parameter(Mandatory)]
        [string]$MountPath,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $handlerMap = Get-TinyWinEntryHandlerMap
    $operations = @($Plan.Operations)
    $operationNumber = 0
    foreach ($operation in $operations) {
        $operationNumber++
        $handlerName = $handlerMap[$operation.Handler]
        $startedUtc = [DateTime]::UtcNow
        Write-TinyWinLog -Context $Context -Message "[$operationNumber/$($operations.Count)] Applying entry $($operation.EntryId) with handler $($operation.Handler)"
        try {
            $details = & $handlerName -Operation $operation -MountPath $MountPath -Context $Context
            [void]$Context.OperationResults.Add([pscustomobject]@{
                    EntryId      = $operation.EntryId
                    Handler      = $operation.Handler
                    Status       = 'Applied'
                    StartedUtc   = $startedUtc.ToString('O')
                    CompletedUtc = [DateTime]::UtcNow.ToString('O')
                    Details      = $details
                })
            $elapsed = [Math]::Round(([DateTime]::UtcNow - $startedUtc).TotalSeconds, 1)
            Write-TinyWinLog -Context $Context -Message "[$operationNumber/$($operations.Count)] Completed entry $($operation.EntryId) in ${elapsed}s"
        } catch {
            [void]$Context.OperationResults.Add([pscustomobject]@{
                    EntryId      = $operation.EntryId
                    Handler      = $operation.Handler
                    Status       = 'Failed'
                    StartedUtc   = $startedUtc.ToString('O')
                    CompletedUtc = [DateTime]::UtcNow.ToString('O')
                    Error        = $_.Exception.Message
                })
            throw
        }
    }
}
