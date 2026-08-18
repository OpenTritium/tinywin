using namespace System.Collections.Generic

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,

    [Parameter(Mandatory)]
    [ValidateRange(1, 99)]
    [int]$ImageIndex,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EntryId,

    [string]$EntriesPath = (Join-Path $PSScriptRoot '../entries'),

    [string]$OutputPath = (Join-Path $PSScriptRoot '../out'),

    [switch]$CreateIso,

    [string]$OscdimgPath,

    [switch]$KeepWorkspace
)

Set-StrictMode -Version Latest
$moduleManifest = Join-Path $PSScriptRoot '../src/TinyWin/TinyWin.psd1'
Import-Module $moduleManifest -Force -ErrorAction Stop

$entryIds = [List[string]]::new()
foreach ($candidateId in $EntryId.Split(',')) {
    $normalizedId = $candidateId.Trim()
    if ($normalizedId) {
        $entryIds.Add($normalizedId)
    }
}
if ($entryIds.Count -eq 0) {
    throw 'EntryId must contain at least one comma-separated entry id.'
}

$PSBoundParameters['EntryId'] = $entryIds.ToArray()
Invoke-TinyWinBuild @PSBoundParameters
