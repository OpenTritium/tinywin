using namespace System.Collections.Generic

[CmdletBinding()]
param(
    [string[]]$Path = @('src', 'scripts', 'entry-handlers')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'ensure-pwsh-tools.ps1') | Out-Null
Import-Module PSScriptAnalyzer -Force -ErrorAction Stop

$settingsPath = Join-Path $repositoryRoot 'PSScriptAnalyzerSettings.psd1'
$files = @($Path | ForEach-Object {
        $pathRoot = Join-Path $repositoryRoot $_
        if (Test-Path -LiteralPath $pathRoot -PathType Leaf) {
            Get-Item -LiteralPath $pathRoot
        } else {
            Get-ChildItem -LiteralPath $pathRoot -Filter *.ps1 -File -Recurse
        }
    }) | Where-Object FullName -NotMatch '[\\/](bin|obj|artifacts)[\\/]'
$results = [List[object]]::new()
foreach ($file in $files) {
    foreach ($result in @(Invoke-ScriptAnalyzer -Path $file.FullName -Settings $settingsPath)) {
        $results.Add($result)
    }
}
if ($results.Count -eq 0) {
    Write-Output 'PSScriptAnalyzer: no findings.'
    exit 0
}

$results | Sort-Object ScriptName, Line, Column | ForEach-Object {
    $location = "{0}:{1}:{2}" -f $_.ScriptName, $_.Line, $_.Column
    Write-Output ("{0} [{1}] {2}: {3}" -f $location, $_.Severity, $_.RuleName, $_.Message)
}

$errorCount = @($results | Where-Object Severity -EQ 'Error').Count
$warningCount = @($results | Where-Object Severity -EQ 'Warning').Count
Write-Output "PSScriptAnalyzer: $errorCount error(s), $warningCount warning(s)."
if ($errorCount -gt 0) {
    exit 1
}
exit 0
