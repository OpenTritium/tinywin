[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',

    [switch]$NoBuild
)

Set-StrictMode -Version Latest
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$projectPath = Join-Path $repositoryRoot 'src/TinyWin.WinUI/TinyWin.WinUI.csproj'
$arguments = @(
    'run',
    '--project',
    $projectPath,
    '--configuration',
    $Configuration,
    '-p:Platform=x64',
    '--no-launch-profile'
)
if ($NoBuild) {
    $arguments += '--no-build'
}

& dotnet @arguments
exit $LASTEXITCODE
