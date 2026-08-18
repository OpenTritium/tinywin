using namespace System.Collections.Generic

function New-TinyWinBuildPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$EntryId,

        [string]$EntriesPath = (Join-Path $script:ModuleRoot '../../entries')
    )

    $catalog = @(Get-TinyWinEntryCatalog -EntriesPath $EntriesPath)
    $entryMap = @{}
    foreach ($entry in $catalog) {
        $entryMap[$entry.Id] = $entry
    }

    $resolvedEntries = [List[object]]::new()
    $visited = @{}
    $visiting = @{}
    function Add-ResolvedEntry {
        param([string]$RequestedId)

        if ($visited.ContainsKey($RequestedId)) {
            return
        }
        if ($visiting.ContainsKey($RequestedId)) {
            throw "Entry dependency cycle detected at '$RequestedId'."
        }
        if (-not $entryMap.ContainsKey($RequestedId)) {
            throw "Entry '$RequestedId' was not found under '$EntriesPath'."
        }

        $visiting[$RequestedId] = $true
        $entry = $entryMap[$RequestedId]
        foreach ($dependencyId in @($entry.Requires)) {
            Add-ResolvedEntry -RequestedId ([string]$dependencyId)
        }
        $visiting.Remove($RequestedId)
        $visited[$RequestedId] = $true
        $resolvedEntries.Add($entry)
    }

    foreach ($requestedId in @($EntryId | Sort-Object -Unique)) {
        Add-ResolvedEntry -RequestedId $requestedId
    }

    $resolvedIds = [List[string]]::new()
    foreach ($resolvedEntry in $resolvedEntries) {
        $resolvedIds.Add($resolvedEntry.Id)
    }
    $resolvedIds = $resolvedIds.ToArray()
    foreach ($entry in $resolvedEntries) {
        foreach ($conflictId in @($entry.Conflicts)) {
            if ($resolvedIds -contains [string]$conflictId) {
                throw "Entry '$($entry.Id)' conflicts with selected entry '$conflictId'."
            }
        }
    }

    $operations = [List[object]]::new()
    foreach ($resolvedEntry in $resolvedEntries) {
        $operations.Add([pscustomobject]@{
                Id         = $resolvedEntry.Id
                EntryId    = $resolvedEntry.Id
                Handler    = $resolvedEntry.Handler
                Phase      = $resolvedEntry.Phase
                Risk       = $resolvedEntry.Risk
                Parameters = $resolvedEntry.Parameters
            })
    }

    return [pscustomobject]@{
        SchemaVersion = 1
        EntryIds      = $resolvedIds
        Entries       = $resolvedEntries.ToArray()
        Operations    = $operations.ToArray()
    }
}
