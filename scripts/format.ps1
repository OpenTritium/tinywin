using namespace System.Collections.Generic

[CmdletBinding()]
param(
    [string[]]$Path = @('src', 'scripts', 'entry-handlers'),

    [switch]$Check
)

Set-StrictMode -Version Latest
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
$changedFiles = [List[string]]::new()
foreach ($file in $files) {
    $original = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
    $lineEnding = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
    $normalized = [regex]::Replace($original, "`r`n|`r|`n", "`n")
    $formatted = Invoke-Formatter -ScriptDefinition $normalized -Settings $settingsPath
    $formatted = [regex]::Replace($formatted, "`r`n|`r|`n", $lineEnding)
    $formatted = $formatted -replace '(?:\r\n|\r|\n)+$', ''
    $formatted += $lineEnding
    if ($formatted -ne $original) {
        $changedFiles.Add($file.FullName)
        if (-not $Check) {
            Set-Content -LiteralPath $file.FullName -Value $formatted -Encoding utf8NoBOM -NoNewline
        }
    }
}

if ($changedFiles.Count -eq 0) {
    Write-Output 'PowerShell formatting: clean.'
    exit 0
}

if ($Check) {
    $changedFiles | ForEach-Object { Write-Output "Formatting required: $_" }
    exit 1
}

$changedFiles | ForEach-Object { Write-Output "Formatted: $_" }
