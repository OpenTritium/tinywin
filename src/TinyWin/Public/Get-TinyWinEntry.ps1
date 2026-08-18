function Get-TinyWinEntry {
    [CmdletBinding()]
    param(
        [string]$EntriesPath = (Join-Path $script:ModuleRoot '../../entries'),

        [string[]]$Id
    )

    $entries = @(Get-TinyWinEntryCatalog -EntriesPath $EntriesPath)
    if (-not $PSBoundParameters.ContainsKey('Id')) {
        return $entries
    }

    $entryMap = @{}
    foreach ($entry in $entries) {
        $entryMap[$entry.Id] = $entry
    }

    foreach ($entryId in $Id) {
        if (-not $entryMap.ContainsKey($entryId)) {
            throw "Entry '$entryId' was not found under '$EntriesPath'."
        }

        $entryMap[$entryId]
    }
}
