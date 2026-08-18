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

        [string]$OscdimgPath,

        [switch]$KeepWorkspace
    )

    if (-not $script:IsWindowsPlatform) {
        throw 'TinyWin image builds are supported only on Windows.'
    }

    Assert-TinyWinAdministrator
    $environment = Test-TinyWinBuildEnvironment
    if ($environment.MissingCommands.Count -gt 0) {
        throw "Required Windows imaging commands are unavailable: $($environment.MissingCommands -join ', ')"
    }

    $plan = New-TinyWinBuildPlan -EntryId $EntryId -EntriesPath $EntriesPath
    $outputRoot = [Path]::GetFullPath($OutputPath)
    $buildId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $mediaPath = Join-Path $outputRoot "TinyWin-$buildId"
    $workspacePath = Join-Path $outputRoot "work/$buildId"
    $mountPath = Join-Path $workspacePath 'mount'
    $isoPath = Join-Path $outputRoot "TinyWin-$buildId.iso"

    if (-not $PSCmdlet.ShouldProcess($mediaPath, "Build Windows image with $($plan.EntryIds.Count) selected entries")) {
        return
    }

    $context = @{
        BuildId          = $buildId
        Events           = [List[object]]::new()
        OperationResults = [List[object]]::new()
    }
    $source = $null
    $imageMounted = $false
    $selectedImage = $null

    try {
        New-Item -ItemType Directory -Path $outputRoot, $workspacePath, $mountPath -Force | Out-Null
        $source = Resolve-TinyWinSource -SourcePath $SourcePath -Context $context
        Test-TinyWinMedia -RootPath $source.RootPath
        Copy-TinyWinMedia -SourceRoot $source.RootPath -DestinationRoot $mediaPath -Context $context

        $installImage = Resolve-TinyWinInstallImage -MediaPath $mediaPath
        $selectedImage = Select-TinyWinImage -ImagePath $installImage -ImageIndex $ImageIndex -Context $context
        $installWim = Join-Path $mediaPath 'sources/install.wim'

        Write-TinyWinLog -Context $context -Message "Mounting selected image at $mountPath"
        Mount-WindowsImage -ImagePath $installWim -Index 1 -Path $mountPath -ErrorAction Stop | Out-Null
        $imageMounted = $true

        Invoke-TinyWinEntryPlan -Plan $plan -MountPath $mountPath -Context $context

        Write-TinyWinLog -Context $context -Message 'Saving and dismounting image'
        Dismount-WindowsImage -Path $mountPath -Save -ErrorAction Stop | Out-Null
        $imageMounted = $false

        Optimize-TinyWinWim -WimPath $installWim -Context $context
        if ($CreateIso) {
            New-TinyWinIso -MediaPath $mediaPath -IsoPath $isoPath -OscdimgPath $OscdimgPath -Context $context
        }

        Write-TinyWinLog -Context $context -Message "Build complete: $mediaPath"
        $manifest = [ordered]@{
            SchemaVersion    = 1
            BuildId          = $buildId
            CreatedUtc       = [DateTime]::UtcNow.ToString('O')
            SourcePath       = (Resolve-Path -LiteralPath $SourcePath).Path
            EntriesPath      = (Resolve-Path -LiteralPath $EntriesPath).Path
            EntryIds         = $plan.EntryIds
            Entries          = @($plan.Entries | Select-Object Id, Title, Version, Handler, Risk, Hash)
            OriginalImage    = [ordered]@{
                Index        = $selectedImage.ImageIndex
                Name         = $selectedImage.ImageName
                EditionId    = $selectedImage.EditionId
                Architecture = $selectedImage.Architecture
                Version      = $selectedImage.Version
            }
            MediaPath        = $mediaPath
            IsoPath          = if ($CreateIso) { $isoPath } else { $null }
            InstallWimSha256 = (Get-FileHash -LiteralPath $installWim -Algorithm SHA256).Hash
            Operations       = $context.OperationResults
            Events           = $context.Events
        }
        $manifestPath = Join-Path $mediaPath 'tinywin-manifest.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8

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
