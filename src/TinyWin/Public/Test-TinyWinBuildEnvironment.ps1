using namespace System.Security.Principal

function Test-TinyWinBuildEnvironment {
    [CmdletBinding()]
    param()

    $savedWhatIfPreference = $WhatIfPreference
    $savedGlobalWhatIfPreference = $global:WhatIfPreference
    $WhatIfPreference = $false
    $global:WhatIfPreference = $false
    try {
        if ($script:IsWindowsPlatform) {
            Import-Module Dism -ErrorAction SilentlyContinue
        }
        $requiredCommands = @(
            'dism.exe',
            'Mount-WindowsImage',
            'Dismount-WindowsImage',
            'Get-WindowsImage',
            'Export-WindowsImage',
            'Get-AppxProvisionedPackage',
            'Remove-AppxProvisionedPackage',
            'Get-WindowsPackage',
            'Remove-WindowsPackage',
            'reg.exe'
        )
        $missingCommands = @($requiredCommands | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        $isElevated = $false
        if ($script:IsWindowsPlatform) {
            $identity = [WindowsIdentity]::GetCurrent()
            $principal = [WindowsPrincipal]::new($identity)
            $isElevated = $principal.IsInRole([WindowsBuiltInRole]::Administrator)
        }

        return [pscustomobject]@{
            IsWindows       = $script:IsWindowsPlatform
            IsElevated      = $isElevated
            MissingCommands = $missingCommands
            Ready           = $script:IsWindowsPlatform -and $isElevated -and $missingCommands.Count -eq 0
        }
    } finally {
        $WhatIfPreference = $savedWhatIfPreference
        $global:WhatIfPreference = $savedGlobalWhatIfPreference
    }
}
