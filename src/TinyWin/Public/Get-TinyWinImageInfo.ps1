using namespace System
using namespace System.Collections.Generic

function Get-TinyWinImageInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath
    )

    $resolvedPath = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
    $context = @{
        BuildId            = "info-$([Guid]::NewGuid().ToString('N'))"
        Events             = [List[object]]::new()
        SuppressConsoleLog = $true
    }
    $source = $null
    try {
        if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
            $imagePath = Resolve-TinyWinInstallImage -MediaPath $resolvedPath
        } else {
            $source = Resolve-TinyWinSource -SourcePath $resolvedPath -Context $context
            Test-TinyWinMedia -RootPath $source.RootPath
            $imagePath = Resolve-TinyWinInstallImage -MediaPath $source.RootPath
        }

        Get-WindowsImage -ImagePath $imagePath -ErrorAction Stop |
            Select-Object ImageIndex, ImageName, ImageDescription, Architecture, Version, EditionId, InstallationType
    } finally {
        if ($source -and $source.IsMounted) {
            Dismount-DiskImage -ImagePath $source.ImagePath -ErrorAction SilentlyContinue | Out-Null
        }
    }
}
