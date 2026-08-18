using namespace System

Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
$script:IsWindowsPlatform = [OperatingSystem]::IsWindows()
$script:EntryHandlerRoot = Join-Path $PSScriptRoot '../../entry-handlers'

. (Join-Path $PSScriptRoot 'Private/Infrastructure.ps1')
. (Join-Path $script:EntryHandlerRoot 'Appx.ps1')
. (Join-Path $script:EntryHandlerRoot 'Registry.ps1')
. (Join-Path $script:EntryHandlerRoot 'Dism.ps1')
. (Join-Path $PSScriptRoot 'Private/EntryHandlers.ps1')
. (Join-Path $PSScriptRoot 'Private/EntryCatalog.ps1')
. (Join-Path $PSScriptRoot 'Private/Image.ps1')
. (Join-Path $PSScriptRoot 'Public/Get-TinyWinEntry.ps1')
. (Join-Path $PSScriptRoot 'Public/New-TinyWinBuildPlan.ps1')
. (Join-Path $PSScriptRoot 'Public/Get-TinyWinImageInfo.ps1')
. (Join-Path $PSScriptRoot 'Public/Test-TinyWinBuildEnvironment.ps1')
. (Join-Path $PSScriptRoot 'Public/Invoke-TinyWinBuild.ps1')

Export-ModuleMember -Function @(
    'Get-TinyWinEntry',
    'Get-TinyWinImageInfo',
    'Invoke-TinyWinBuild',
    'New-TinyWinBuildPlan',
    'Test-TinyWinBuildEnvironment'
)
