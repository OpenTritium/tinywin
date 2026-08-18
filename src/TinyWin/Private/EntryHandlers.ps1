function Get-TinyWinEntryHandlerMap {
    return @{
        'Appx.RemoveProvisioned'       = 'Invoke-TinyWinAppxRemove'
        'Registry.SetOfflineValue'     = 'Invoke-TinyWinRegistrySet'
        'Dism.ComponentCleanup'        = 'Invoke-TinyWinComponentCleanup'
        'Dism.RemoveOptionalComponent' = 'Invoke-TinyWinOptionalComponentRemove'
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
    foreach ($operation in @($Plan.Operations)) {
        $handlerName = $handlerMap[$operation.Handler]
        $startedUtc = [DateTime]::UtcNow
        Write-TinyWinLog -Context $Context -Message "Applying entry $($operation.EntryId) with handler $($operation.Handler)"
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
