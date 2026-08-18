[CmdletBinding()]
param(
    [switch]$NoBuild
)

Set-StrictMode -Version Latest
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$projectPath = Join-Path $repositoryRoot 'src/TinyWin.WinUI/TinyWin.WinUI.csproj'
$arguments = @('run', '--project', $projectPath)
if ($NoBuild) {
    $arguments += '--no-build'
}

& dotnet @arguments
exit $LASTEXITCODE
