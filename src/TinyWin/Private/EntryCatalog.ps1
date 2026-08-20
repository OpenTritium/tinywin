using namespace System.Collections.Generic

function Get-TinyWinEntryCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EntriesPath
    )

    $resolvedPath = (Resolve-Path -LiteralPath $EntriesPath -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
        throw "Entry directory '$resolvedPath' does not exist."
    }

    $handlerMap = Get-TinyWinEntryHandlerMap
    $entries = [List[object]]::new()
    foreach ($entryFile in @(Get-ChildItem -LiteralPath $resolvedPath -Filter '*.json' -File -Recurse | Sort-Object FullName)) {
        try {
            $document = Get-Content -LiteralPath $entryFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        } catch {
            throw "Unable to parse entry '$($entryFile.FullName)': $($_.Exception.Message)"
        }

        foreach ($requiredProperty in @('schemaVersion', 'id', 'version', 'title', 'description', 'category', 'risk', 'handler', 'phase', 'parameters')) {
            if (-not $document.ContainsKey($requiredProperty)) {
                throw "Entry '$($entryFile.FullName)' is missing '$requiredProperty'."
            }
        }

        $entryId = [string]$document.id
        if ($entryId -notmatch '^[a-z0-9]+(?:[.-][a-z0-9]+)*$') {
            throw "Entry '$($entryFile.FullName)' has an invalid id '$entryId'."
        }

        if ([int]$document.schemaVersion -ne 1) {
            throw "Entry '$entryId' uses unsupported schemaVersion '$($document.schemaVersion)'."
        }

        if ([string]$document.version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
            throw "Entry '$entryId' uses invalid version '$($document.version)'."
        }

        $handlerName = [string]$document.handler
        if (-not $handlerMap.ContainsKey($handlerName)) {
            throw "Entry '$entryId' references unknown handler '$handlerName'."
        }

        $risk = [string]$document.risk
        if (@('Low', 'Medium', 'High') -notcontains $risk) {
            throw "Entry '$entryId' uses unsupported risk '$risk'."
        }

        # High-risk operations must never enter the normal bulk selection implicitly.
        $selectionTier = if ($document.ContainsKey('selectionTier')) { [string]$document.selectionTier } elseif ($risk -eq 'High') { 'Expert' } else { 'Standard' }
        if (@('Standard', 'Expert', 'Experimental') -notcontains $selectionTier) {
            throw "Entry '$entryId' uses unsupported selectionTier '$selectionTier'."
        }

        $phase = [string]$document.phase
        if ($phase -ne 'MountedImage') {
            throw "Entry '$entryId' uses unsupported phase '$phase'."
        }

        $parameters = $document.parameters
        if ($parameters -isnot [hashtable]) {
            throw "Entry '$entryId' must define parameters as a JSON object."
        }

        $requires = if ($document.ContainsKey('requires')) { @($document.requires) } else { @() }
        $conflicts = if ($document.ContainsKey('conflicts')) { @($document.conflicts) } else { @() }
        $entries.Add([pscustomobject]@{
                SchemaVersion = [int]$document.schemaVersion
                Id            = $entryId
                Version       = [string]$document.version
                Title         = [string]$document.title
                Description   = [string]$document.description
                Category      = [string]$document.category
                Risk          = $risk
                SelectionTier = $selectionTier
                Handler       = $handlerName
                Parameters    = $parameters
                Requires      = $requires
                Conflicts     = $conflicts
                Phase         = $phase
                FilePath      = $entryFile.FullName
                Hash          = (Get-FileHash -LiteralPath $entryFile.FullName -Algorithm SHA256).Hash
            })
    }

    $duplicate = @($entries | Group-Object Id | Where-Object Count -gt 1)
    if ($duplicate.Count -gt 0) {
        throw "Duplicate entry ids: $($duplicate.Name -join ', ')."
    }

    return $entries.ToArray()
}
