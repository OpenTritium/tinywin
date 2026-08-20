[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath
)

Set-StrictMode -Version Latest
$InformationPreference = 'SilentlyContinue'
$moduleManifest = Join-Path $PSScriptRoot '../src/TinyWin/TinyWin.psd1'
Import-Module $moduleManifest -Force -ErrorAction Stop

@(
    Get-TinyWinImageInfo -SourcePath $SourcePath |
        Select-Object ImageIndex, ImageName, ImageDescription, @{ Name = 'Architecture'; Expression = { [string]$_.Architecture } }, @{ Name = 'Version'; Expression = { [string]$_.Version } }, EditionId, InstallationType
    ) | ConvertTo-Json -Depth 3
