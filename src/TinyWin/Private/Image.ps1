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

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $image = Get-WindowsImage -ImagePath $ImagePath | Where-Object ImageIndex -eq $ImageIndex | Select-Object -First 1
    if (-not $image) {
        throw "Image index $ImageIndex does not exist in '$ImagePath'."
    }

    $sourcesPath = Split-Path -Parent $ImagePath
    $selectedImage = Join-Path $sourcesPath 'install.selected.wim'
    Write-TinyWinLog -Context $Context -Message "Exporting image index $ImageIndex ($($image.ImageName)) as a single-index WIM"
    Export-WindowsImage -SourceImagePath $ImagePath -SourceIndex $ImageIndex -DestinationImagePath $selectedImage -CompressionType Maximum -CheckIntegrity -ErrorAction Stop | Out-Null

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

        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $optimizedWim = Join-Path (Split-Path -Parent $WimPath) 'install.optimized.wim'
    Write-TinyWinLog -Context $Context -Message 'Exporting final image with recovery compression'
    Export-WindowsImage -SourceImagePath $WimPath -SourceIndex 1 -DestinationImagePath $optimizedWim -CompressionType Recovery -CheckIntegrity -ErrorAction Stop | Out-Null
    Remove-Item -LiteralPath $WimPath -Force
    Move-Item -LiteralPath $optimizedWim -Destination $WimPath
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

    if (-not $OscdimgPath) {
        $command = Get-Command 'oscdimg.exe' -ErrorAction SilentlyContinue
        if (-not $command) {
            throw 'oscdimg.exe was not found. Install the Windows ADK Deployment Tools and provide -OscdimgPath, or omit -CreateIso to keep a bootable media folder.'
        }
        $OscdimgPath = $command.Source
    }

    $OscdimgPath = (Resolve-Path -LiteralPath $OscdimgPath -ErrorAction Stop).Path
    $biosBoot = Join-Path $MediaPath 'boot/etfsboot.com'
    $uefiBoot = Join-Path $MediaPath 'efi/microsoft/boot/efisys.bin'
    foreach ($bootFile in @($biosBoot, $uefiBoot)) {
        if (-not (Test-Path -LiteralPath $bootFile -PathType Leaf)) {
            throw "Cannot create ISO because boot file '$bootFile' is missing."
        }
    }

    $bootData = "-bootdata:2#p0,e,b`"$biosBoot`"#pEF,e,b`"$uefiBoot`""
    Invoke-TinyWinNative -FilePath $OscdimgPath -Arguments @('-m', '-o', '-u2', '-udfver102', $bootData, $MediaPath, $IsoPath) -Context $Context
}
