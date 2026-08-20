using namespace System.Collections.Generic
using namespace System.IO

function Invoke-TinyWinBuild {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [ValidateRange(1, 99)]
        [int]$ImageIndex,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$EntryId,

        [string]$EntriesPath = (Join-Path $script:ModuleRoot '../../entries'),

        [string]$OutputPath = (Join-Path $script:ModuleRoot '../../out'),

        [switch]$CreateIso,

        [ValidateSet('Auto', 'Wim', 'Esd')]
        [string]$ImageFormat = 'Auto',

        [switch]$Fast,

        [string]$OscdimgPath,

        [switch]$KeepWorkspace
    )

    if (-not $script:IsWindowsPlatform) {
        throw 'TinyWin image builds are supported only on Windows.'
    }

    $context = @{
        BuildId          = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
        Events           = [List[object]]::new()
        OperationResults = [List[object]]::new()
        UseConsoleOutput = $true
        FastMode         = [bool]$Fast
        VerifyIntegrity  = -not [bool]$Fast
    }
    $compressionType = if ($Fast) { 'Fast' } else { 'Maximum' }
    $integrityMode = if ($Fast) { 'disabled' } else { 'enabled' }
    Write-TinyWinLog -Context $context -Message "Build started for image index $ImageIndex with $($EntryId.Count) requested entries (compression=$compressionType, integrity=$integrityMode)."
    if ($CreateIso) {
        Write-TinyWinLog -Context $context -Message 'Checking ISO creation tools.'
        $OscdimgPath = Resolve-TinyWinOscdimgPath -OscdimgPath $OscdimgPath
        Write-TinyWinLog -Context $context -Message "ISO creation tool found: $OscdimgPath"
    }
    Write-TinyWinLog -Context $context -Message 'Checking administrator privileges and imaging tools.'
    Assert-TinyWinAdministrator
    $environment = Test-TinyWinBuildEnvironment
    if ($environment.MissingCommands.Count -gt 0) {
        Write-TinyWinLog -Context $context -Level Error -Message "Missing imaging commands: $($environment.MissingCommands -join ', ')"
        throw "Required Windows imaging commands are unavailable: $($environment.MissingCommands -join ', ')"
    }
    Write-TinyWinLog -Context $context -Message 'Build environment is ready.'

    $plan = New-TinyWinBuildPlan -EntryId $EntryId -EntriesPath $EntriesPath
    Write-TinyWinLog -Context $context -Message "Build plan resolved to $($plan.EntryIds.Count) entries."
    $outputRoot = [Path]::GetFullPath($OutputPath)
    $buildId = $context.BuildId
    $mediaPath = Join-Path $outputRoot "TinyWin-$buildId"
    $workspacePath = Join-Path $outputRoot "work/$buildId"
    $mountPath = Join-Path $workspacePath 'mount'
    $isoPath = Join-Path $outputRoot "TinyWin-$buildId.iso"

    if (-not $PSCmdlet.ShouldProcess($mediaPath, "Build Windows image with $($plan.EntryIds.Count) selected entries")) {
        return
    }

    $source = $null
    $imageMounted = $false
    $selectedImage = $null

    try {
        New-Item -ItemType Directory -Path $outputRoot, $workspacePath, $mountPath -Force | Out-Null
        Write-TinyWinLog -Context $context -Message "Workspace prepared at $workspacePath"
        $source = Resolve-TinyWinSource -SourcePath $SourcePath -Context $context
        Write-TinyWinLog -Context $context -Message "Validating installation media at $($source.RootPath)"
        Test-TinyWinMedia -RootPath $source.RootPath
        Write-TinyWinLog -Context $context -Message 'Installation media validation completed.'
        Copy-TinyWinMedia -SourceRoot $source.RootPath -DestinationRoot $mediaPath -Context $context

        $installImage = Resolve-TinyWinInstallImage -MediaPath $mediaPath
        $selectedImage = Select-TinyWinImage -ImagePath $installImage -ImageIndex $ImageIndex -CompressionType $compressionType -CheckIntegrity:(-not $Fast) -Context $context
        $installWim = Join-Path $mediaPath 'sources/install.wim'

        Write-TinyWinLog -Context $context -Message "Mounting selected image at $mountPath"
        # Use a regular writable mount. Sparse/optimized mounts expose many
        # directories as WIM reparse points; the DISM PowerShell providers
        # cannot reliably enumerate or service those paths on newer hosts.
        Mount-WindowsImage -ImagePath $installWim -Index 1 -Path $mountPath -ErrorAction Stop | Out-Null
        $imageMounted = $true
        Write-TinyWinLog -Context $context -Message 'Selected image mounted.'

        Invoke-TinyWinEntryPlan -Plan $plan -MountPath $mountPath -Context $context

        Write-TinyWinLog -Context $context -Message 'Saving and dismounting image'
        Dismount-WindowsImage -Path $mountPath -Save -ErrorAction Stop | Out-Null
        $imageMounted = $false
        Write-TinyWinLog -Context $context -Message 'Image changes saved and mount released.'

        $finalImageFormat = if ($ImageFormat -eq 'Auto') {
            if ($CreateIso) { 'Esd' } else { 'Wim' }
        } else {
            $ImageFormat
        }
        $installImagePath = $installWim
        if ($finalImageFormat -eq 'Esd') {
            # ESD export is already the final compression pass; a preceding
            # Maximum WIM export would only compress the same image twice.
            $installImagePath = Convert-TinyWinWimToEsd -WimPath $installWim -CheckIntegrity:(-not $Fast) -Context $context
        } else {
            Optimize-TinyWinWim -WimPath $installWim -CompressionType $compressionType -CheckIntegrity:(-not $Fast) -Context $context
        }
        if ($CreateIso) {
            New-TinyWinIso -MediaPath $mediaPath -IsoPath $isoPath -OscdimgPath $OscdimgPath -Context $context
            Write-TinyWinLog -Context $context -Message "Bootable ISO created: $isoPath"
        }

        Write-TinyWinLog -Context $context -Message "Build complete: $mediaPath"
        $originalImage = [ordered]@{}
        foreach ($propertyName in @('ImageIndex', 'ImageName', 'EditionId', 'Architecture', 'Version')) {
            $property = $selectedImage.PSObject.Properties[$propertyName]
            $originalImage[$propertyName] = if ($property) { $property.Value } else { $null }
        }
        $manifest = [ordered]@{
            SchemaVersion      = 1
            BuildId            = $buildId
            CreatedUtc         = [DateTime]::UtcNow.ToString('O')
            SourcePath         = (Resolve-Path -LiteralPath $SourcePath).Path
            EntriesPath        = (Resolve-Path -LiteralPath $EntriesPath).Path
            EntryIds           = $plan.EntryIds
            Entries            = @($plan.Entries | Select-Object Id, Title, Version, Handler, Risk, Hash)
            OriginalImage      = [ordered]@{
                Index        = $originalImage.ImageIndex
                Name         = $originalImage.ImageName
                EditionId    = $originalImage.EditionId
                Architecture = $originalImage.Architecture
                Version      = $originalImage.Version
            }
            MediaPath          = $mediaPath
            IsoPath            = if ($CreateIso) { $isoPath } else { $null }
            InstallImagePath   = $installImagePath
            InstallImageFormat = $finalImageFormat
            InstallImageSha256 = (Get-FileHash -LiteralPath $installImagePath -Algorithm SHA256).Hash
            Operations         = $context.OperationResults
            Events             = $context.Events
        }
        $manifestPath = Join-Path $mediaPath 'tinywin-manifest.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8
        Write-TinyWinLog -Context $context -Message "Build manifest written: $manifestPath"

        return [pscustomobject]@{
            MediaPath    = $mediaPath
            IsoPath      = if ($CreateIso) { $isoPath } else { $null }
            ManifestPath = $manifestPath
            EntryIds     = $plan.EntryIds
        }
    } catch {
        Write-TinyWinLog -Context $context -Level Error -Message $_.Exception.Message
        throw
    } finally {
        if ($imageMounted) {
            Write-TinyWinLog -Context $context -Level Warning -Message 'Discarding mounted image after an unsuccessful build.'
            Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction SilentlyContinue | Out-Null
        }
        if ($source -and $source.IsMounted) {
            Dismount-DiskImage -ImagePath $source.ImagePath -ErrorAction SilentlyContinue
        }
        if (-not $KeepWorkspace -and (Test-Path -LiteralPath $workspacePath)) {
            Remove-Item -LiteralPath $workspacePath -Recurse -Force
        }
    }
}
