function Resolve-TinyWinOscdimgPath {
    [CmdletBinding()]
    param(
        [string]$OscdimgPath
    )

    if (-not $OscdimgPath) {
        $command = Get-Command 'oscdimg.exe' -ErrorAction SilentlyContinue
        if (-not $command) {
            throw 'oscdimg.exe was not found. Install the Windows ADK Deployment Tools and provide -OscdimgPath, or omit -CreateIso to keep a bootable media folder.'
        }

        $OscdimgPath = $command.Source
    }

    return (Resolve-Path -LiteralPath $OscdimgPath -ErrorAction Stop).Path
}

function Resolve-TinyWinInstallImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MediaPath
    )

    foreach ($imageName in @('install.wim', 'install.esd')) {
        $imagePath = Join-Path $MediaPath "sources/$imageName"
        if (Test-Path -LiteralPath $imagePath -PathType Leaf) {
            return $imagePath
        }
    }

    throw "No install.wim or install.esd exists under '$MediaPath\\sources'."
}

function Select-TinyWinImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ImagePath,

        [Parameter(Mandatory)]
        [int]$ImageIndex,

        [ValidateSet('Fast', 'Maximum')]
        [string]$CompressionType = 'Maximum',

        [switch]$CheckIntegrity,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    Write-TinyWinLog -Context $Context -Message "Reading image metadata from $ImagePath"
    $images = @(Get-WindowsImage -ImagePath $ImagePath)
    $image = $images | Where-Object ImageIndex -EQ $ImageIndex | Select-Object -First 1
    if (-not $image) {
        throw "Image index $ImageIndex does not exist in '$ImagePath'."
    }

    $sourcesPath = Split-Path -Parent $ImagePath
    if ([IO.Path]::GetExtension($ImagePath) -eq '.wim' -and $images.Count -eq 1 -and $images[0].ImageIndex -eq $ImageIndex) {
        Write-TinyWinLog -Context $Context -Message 'Installation WIM already contains one selected index; skipping intermediate export.'
        return $image
    }

    $selectedImage = Join-Path $sourcesPath 'install.selected.wim'
    Write-TinyWinLog -Context $Context -Message "Exporting image index $ImageIndex ($($image.ImageName)) as a single-index WIM"
    $exportArguments = @{
        SourceImagePath      = $ImagePath
        SourceIndex          = $ImageIndex
        DestinationImagePath = $selectedImage
        CompressionType      = $CompressionType
        ErrorAction          = 'Stop'
    }
    if ($CheckIntegrity) {
        $exportArguments['CheckIntegrity'] = $true
    }
    Export-WindowsImage @exportArguments | Out-Null
    Write-TinyWinLog -Context $Context -Message 'Selected image export completed.'

    Remove-Item -LiteralPath $ImagePath -Force
    foreach ($staleImage in @('install.wim', 'install.esd')) {
        $stalePath = Join-Path $sourcesPath $staleImage
        if (Test-Path -LiteralPath $stalePath) {
            Remove-Item -LiteralPath $stalePath -Force
        }
    }
    Move-Item -LiteralPath $selectedImage -Destination (Join-Path $sourcesPath 'install.wim')

    return $image
}

function Optimize-TinyWinWim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WimPath,

        [ValidateSet('Fast', 'Maximum')]
        [string]$CompressionType = 'Maximum',

        [switch]$CheckIntegrity,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $optimizedWim = Join-Path (Split-Path -Parent $WimPath) 'install.optimized.wim'
    Write-TinyWinLog -Context $Context -Message "Exporting final image with $CompressionType compression"
    $exportArguments = @{
        SourceImagePath      = $WimPath
        SourceIndex          = 1
        DestinationImagePath = $optimizedWim
        CompressionType      = $CompressionType
        ErrorAction          = 'Stop'
    }
    if ($CheckIntegrity) {
        $exportArguments['CheckIntegrity'] = $true
    }
    Export-WindowsImage @exportArguments | Out-Null
    Remove-Item -LiteralPath $WimPath -Force
    Move-Item -LiteralPath $optimizedWim -Destination $WimPath
    Write-TinyWinLog -Context $Context -Message 'Final image optimization completed.'
}

function Convert-TinyWinWimToEsd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WimPath,

        [switch]$CheckIntegrity,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $esdPath = [IO.Path]::ChangeExtension($WimPath, '.esd')
    $temporaryEsdPath = Join-Path (Split-Path -Parent $WimPath) 'install.final.esd'
    Write-TinyWinLog -Context $Context -Message 'Exporting final image as ESD for ISO delivery.'
    # The DISM PowerShell cmdlet advertises Recovery compression on some ADK
    # versions but fails internally with a missing compression dictionary key.
    # Use the stable DISM command-line export for ESD output instead.
    $arguments = @(
        '/English',
        '/Export-Image',
        "/SourceImageFile:$WimPath",
        '/SourceIndex:1',
        "/DestinationImageFile:$temporaryEsdPath",
        '/Compress:recovery'
    )
    if ($CheckIntegrity) {
        $arguments += '/CheckIntegrity'
    }
    Invoke-TinyWinNative -FilePath 'dism.exe' -Arguments $arguments -Context $Context
    Remove-Item -LiteralPath $WimPath -Force
    if (Test-Path -LiteralPath $esdPath) {
        Remove-Item -LiteralPath $esdPath -Force
    }
    Move-Item -LiteralPath $temporaryEsdPath -Destination $esdPath | Out-Null
    Write-TinyWinLog -Context $Context -Message "Final image converted to ESD: $esdPath"
    return $esdPath
}

function New-TinyWinIso {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MediaPath,

        [Parameter(Mandatory)]
        [string]$IsoPath,

        [string]$OscdimgPath,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $OscdimgPath = Resolve-TinyWinOscdimgPath -OscdimgPath $OscdimgPath
    Write-TinyWinLog -Context $Context -Message "Creating bootable ISO at $IsoPath"
    $biosBoot = Join-Path $MediaPath 'boot/etfsboot.com'
    # The no-prompt image allows an unattended Generation 2 Hyper-V install.
    # Fall back for installation media that does not include it.
    $uefiBoot = @(
        (Join-Path $MediaPath 'efi/microsoft/boot/efisys_noprompt.bin'),
        (Join-Path $MediaPath 'efi/microsoft/boot/efisys.bin')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    foreach ($bootFile in @($biosBoot, $uefiBoot)) {
        if (-not (Test-Path -LiteralPath $bootFile -PathType Leaf)) {
            throw "Cannot create ISO because boot file '$bootFile' is missing."
        }
    }

    # Invoke-TinyWinNative passes an argument array. Embedded quotes would reach
    # oscdimg literally and make it look for a path beginning with a quote.
    $bootData = "-bootdata:2#p0,e,b$biosBoot#pEF,e,b$uefiBoot"
    Invoke-TinyWinNative -FilePath $OscdimgPath -Arguments @('-m', '-o', '-u2', '-udfver102', $bootData, $MediaPath, $IsoPath) -Context $Context
}
