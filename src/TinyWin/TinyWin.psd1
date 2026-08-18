@{
    RootModule        = 'TinyWin.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'd4bc1d83-00dc-4478-9f89-30ed5aeaf5f9'
    Author            = 'TinyWin contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) TinyWin contributors. All rights reserved.'
    Description       = 'Entry-driven offline Windows image slimming workflow.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Get-TinyWinEntry',
        'Get-TinyWinImageInfo',
        'Invoke-TinyWinBuild',
        'New-TinyWinBuildPlan',
        'Test-TinyWinBuildEnvironment'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Windows', 'DISM', 'WIM', 'Image', 'Slimming')
            ProjectUri = 'https://github.com/ntdevlabs/tiny11builder'
        }
    }
}
