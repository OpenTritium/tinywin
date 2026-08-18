using namespace System.IO

[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$moduleRoot = Join-Path $repositoryRoot '.tools/pwsh-modules'
New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null

$pathSeparator = [Path]::PathSeparator
$env:PSModulePath = "$moduleRoot$pathSeparator$env:PSModulePath"
$localModulePath = Join-Path $moduleRoot 'PSScriptAnalyzer'
$localModule = Get-ChildItem -LiteralPath $localModulePath -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $localModule -or $Force) {
    Save-Module -Name PSScriptAnalyzer -Path $moduleRoot -Repository PSGallery -Force -ErrorAction Stop
}

Import-Module PSScriptAnalyzer -Force -ErrorAction Stop
Get-Module PSScriptAnalyzer | Select-Object -First 1
