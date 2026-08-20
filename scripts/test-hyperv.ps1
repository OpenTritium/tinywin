using namespace System.IO
using namespace System.Security.Principal

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$IsoPath,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._ -]{0,79}$')]
    [string]$VmName = "TinyWin-Smoke-$(Get-Date -Format 'yyyyMMdd-HHmmss')",

    [ValidateRange(1, 99)]
    [int]$ImageIndex = 1,

    [ValidateRange(2, 32)]
    [int]$MemoryStartupGB = 4,

    [ValidateRange(1, 16)]
    [int]$ProcessorCount = 2,

    [ValidateRange(40, 512)]
    [int]$VhdSizeGB = 64,

    [ValidateRange(5, 120)]
    [int]$TimeoutMinutes = 45,

    [ValidateRange(5, 120)]
    [int]$BootDeviceHandoffDelaySeconds = 15,

    [ValidatePattern('^[A-Za-z]{2,3}-[A-Za-z]{2,4}$')]
    [string]$UiLanguage = 'zh-CN',

    [ValidatePattern('^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{8}$')]
    [string]$InputLocale = '0804:00000804',

    [string]$VmSwitchName,

    [string]$OutputPath = (Join-Path $PSScriptRoot '../out/hyperv-smoke'),

    [switch]$KeepVm,

    [switch]$KeepArtifacts,

    [switch]$SkipGuestProbe,

    [switch]$EnableSecureBoot
)

Set-StrictMode -Version Latest

function Assert-TinyWinHyperVEnvironment {
    [CmdletBinding()]
    param()

    if (-not [OperatingSystem]::IsWindows()) {
        throw 'The Hyper-V smoke test runs only on Windows.'
    }

    $identity = [WindowsIdentity]::GetCurrent()
    $principal = [WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([WindowsBuiltInRole]::Administrator)) {
        throw 'Run the Hyper-V smoke test from an elevated PowerShell session.'
    }

    $savedWhatIfPreference = $WhatIfPreference
    $savedGlobalWhatIfPreference = $global:WhatIfPreference
    $WhatIfPreference = $false
    $global:WhatIfPreference = $false
    try {
        Import-Module Hyper-V -ErrorAction Stop
    } catch {
        throw "Hyper-V PowerShell module is unavailable: $($_.Exception.Message)"
    } finally {
        $WhatIfPreference = $savedWhatIfPreference
        $global:WhatIfPreference = $savedGlobalWhatIfPreference
    }

    $requiredCommands = @(
        'Add-VMDvdDrive',
        'Add-VMHardDiskDrive',
        'Get-VM',
        'Get-VMIntegrationService',
        'Get-VMSwitch',
        'New-VHD',
        'New-VM',
        'Remove-VM',
        'Set-VMFirmware',
        'Set-VMProcessor',
        'Start-VM',
        'Stop-VM'
    )
    $missingCommands = @($requiredCommands | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    if ($missingCommands.Count -gt 0) {
        throw "Hyper-V PowerShell commands are unavailable: $($missingCommands -join ', '). Enable the Hyper-V role and management tools."
    }

    try {
        Get-VMHost -ErrorAction Stop | Out-Null
    } catch {
        throw "Hyper-V is not ready: $($_.Exception.Message)"
    }
}

function New-TinyWinTestPassword {
    [CmdletBinding()]
    param()

    return "TinyWin!$(Get-Random -Minimum 10000000 -Maximum 99999999)Aa"
}

function New-TinyWinUnattendContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscredential]$Credential,

        [Parameter(Mandatory)]
        [int]$ImageIndex,

        [Parameter(Mandatory)]
        [string]$UiLanguage,

        [Parameter(Mandatory)]
        [string]$InputLocale
    )

    $escapedUserName = [Security.SecurityElement]::Escape($Credential.UserName)
    $plainTextPassword = [System.Net.NetworkCredential]::new('', $Credential.Password).Password
    $escapedPassword = [Security.SecurityElement]::Escape($plainTextPassword)
    return @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage>
        <UILanguage>$UiLanguage</UILanguage>
      </SetupUILanguage>
      <InputLocale>$InputLocale</InputLocale>
      <SystemLocale>$UiLanguage</SystemLocale>
      <UILanguage>$UiLanguage</UILanguage>
      <UILanguageFallback>$UiLanguage</UILanguageFallback>
      <UserLocale>$UiLanguage</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Size>100</Size>
              <Type>EFI</Type>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Size>16</Size>
              <Type>MSR</Type>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>3</Order>
              <Extend>true</Extend>
              <Type>Primary</Type>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Format>FAT32</Format>
              <Label>System</Label>
              <Order>1</Order>
              <PartitionID>1</PartitionID>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Format>NTFS</Format>
              <Label>Windows</Label>
              <Letter>C</Letter>
              <Order>2</Order>
              <PartitionID>3</PartitionID>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
        <WillShowUI>OnError</WillShowUI>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add">
              <Key>/IMAGE/INDEX</Key>
              <Value>$ImageIndex</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>3</PartitionID>
          </InstallTo>
          <WillShowUI>OnError</WillShowUI>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
        <FullName>TinyWin</FullName>
        <Organization>TinyWin Smoke Test</Organization>
      </UserData>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <AutoLogon>
        <Password>
          <Value>$escapedPassword</Value>
          <PlainText>true</PlainText>
        </Password>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
        <Username>$escapedUserName</Username>
        <Domain>.</Domain>
      </AutoLogon>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <AdministratorPassword>
          <Value>$escapedPassword</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <CommandLine>cmd.exe /c echo ready&gt;C:\TinyWinSmokeReady.txt</CommandLine>
          <Description>Mark TinyWin smoke-test completion</Description>
          <Order>1</Order>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@
}

function New-TinyWinAnswerIso {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UnattendPath,

        [Parameter(Mandatory)]
        [string]$AnswerIsoPath
    )

    $sourceStream = $null
    $fileSystemImage = $null
    $resultImage = $null
    try {
        $sourceStream = New-Object -ComObject ADODB.Stream
        $sourceStream.Type = 1
        $sourceStream.Open()
        $sourceStream.LoadFromFile($UnattendPath)

        $fileSystemImage = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
        $fileSystemImage.FileSystemsToCreate = 3
        $fileSystemImage.VolumeName = 'TINYWIN_ANSWER'
        [void]$fileSystemImage.Root.AddFile('Autounattend.xml', $sourceStream)
        $resultImage = $fileSystemImage.CreateResultImage()
        if (-not ('TinyWin.HyperV.IsoStreamWriter' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;

namespace TinyWin.HyperV
{
    [ComImport]
    [Guid("0000000C-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IComStream
    {
        [PreserveSig]
        int Read([Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] byte[] buffer, int count, IntPtr bytesRead);

        [PreserveSig]
        int Write([In, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] byte[] buffer, int count, IntPtr bytesWritten);

        [PreserveSig]
        int Seek(long offset, int origin, IntPtr newPosition);

        [PreserveSig]
        int SetSize(long size);

        [PreserveSig]
        int CopyTo(IComStream stream, long count, IntPtr bytesRead, IntPtr bytesWritten);

        [PreserveSig]
        int Commit(int flags);

        [PreserveSig]
        int Revert();

        [PreserveSig]
        int LockRegion(long offset, long count, int lockType);

        [PreserveSig]
        int UnlockRegion(long offset, long count, int lockType);

        [PreserveSig]
        int Stat(IntPtr stat, int flags);

        [PreserveSig]
        int Clone(out IComStream stream);
    }

    public static class IsoStreamWriter
    {
        public static void WriteToFile(object comStream, string destinationPath)
        {
            IntPtr unknown = Marshal.GetIUnknownForObject(comStream);
            IntPtr streamPointer = IntPtr.Zero;
            IntPtr bytesReadPointer = IntPtr.Zero;
            try
            {
                Guid streamInterfaceId = typeof(IComStream).GUID;
                Marshal.ThrowExceptionForHR(Marshal.QueryInterface(unknown, in streamInterfaceId, out streamPointer));
                IComStream stream = (IComStream)Marshal.GetTypedObjectForIUnknown(streamPointer, typeof(IComStream));
                bytesReadPointer = Marshal.AllocCoTaskMem(sizeof(int));
                byte[] buffer = new byte[65536];
                using (FileStream output = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    while (true)
                    {
                        Marshal.WriteInt32(bytesReadPointer, 0);
                        Marshal.ThrowExceptionForHR(stream.Read(buffer, buffer.Length, bytesReadPointer));
                        int bytesRead = Marshal.ReadInt32(bytesReadPointer);
                        if (bytesRead == 0)
                        {
                            break;
                        }

                        output.Write(buffer, 0, bytesRead);
                    }
                }
            }
            finally
            {
                if (bytesReadPointer != IntPtr.Zero)
                {
                    Marshal.FreeCoTaskMem(bytesReadPointer);
                }

                if (streamPointer != IntPtr.Zero)
                {
                    Marshal.Release(streamPointer);
                }

                Marshal.Release(unknown);
            }
        }
    }
}
'@
        }

        [TinyWin.HyperV.IsoStreamWriter]::WriteToFile($resultImage.ImageStream, $AnswerIsoPath)
    } finally {
        foreach ($comObject in @($resultImage, $fileSystemImage, $sourceStream)) {
            if ($null -ne $comObject -and [Runtime.InteropServices.Marshal]::IsComObject($comObject)) {
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject)
            }
        }
    }
}

function Wait-TinyWinVmInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [pscredential]$Credential,

        [Parameter(Mandatory)]
        [int]$TimeoutMinutes
    )

    $deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
    $lastError = $null
    $reportedHeartbeat = $false
    $probe = {
        if (-not (Test-Path -LiteralPath 'C:\TinyWinSmokeReady.txt' -PathType Leaf)) {
            throw 'Windows setup has not finished the TinyWin smoke-test first-logon command.'
        }

        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
        $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
        Start-Sleep -Seconds 20

        $runtimeBaseline = $null
        try {
            $processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)
            $services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop)
            $totalHandles = [long]0
            $totalThreads = [long]0
            $totalWorkingSet = [long]0
            foreach ($process in $processes) {
                if ($null -ne $process.HandleCount) {
                    $totalHandles += [long]$process.HandleCount
                }
                if ($null -ne $process.ThreadCount) {
                    $totalThreads += [long]$process.ThreadCount
                }
                if ($null -ne $process.WorkingSetSize) {
                    $totalWorkingSet += [long]$process.WorkingSetSize
                }
            }

            $runningServices = @($services | Where-Object State -EQ 'Running' | Sort-Object Name)
            $runtimeBaseline = [pscustomobject]@{
                CollectedUtc          = [DateTime]::UtcNow.ToString('O')
                BootMinutes           = [Math]::Round(([DateTime]::Now - $operatingSystem.LastBootUpTime).TotalMinutes, 1)
                ProcessCount          = $processes.Count
                ProcessHandles        = $totalHandles
                ProcessThreads        = $totalThreads
                ProcessWorkingSetMB   = [Math]::Round($totalWorkingSet / 1MB, 1)
                RunningServiceCount   = $runningServices.Count
                AutoStartServiceCount = @($services | Where-Object StartMode -EQ 'Auto').Count
                RunningServiceNames   = @($runningServices | ForEach-Object Name)
                TopProcessesByMemory  = @($processes | Sort-Object WorkingSetSize -Descending | Select-Object -First 10 @{ Name = 'Name'; Expression = { $_.Name } }, @{ Name = 'ProcessId'; Expression = { $_.ProcessId } }, @{ Name = 'HandleCount'; Expression = { $_.HandleCount } }, @{ Name = 'ThreadCount'; Expression = { $_.ThreadCount } }, @{ Name = 'WorkingSetMB'; Expression = { [Math]::Round(([long]$_.WorkingSetSize) / 1MB, 1) } })
            }
        } catch {
            $runtimeBaseline = [pscustomobject]@{
                CollectedUtc    = [DateTime]::UtcNow.ToString('O')
                CollectionError = $_.Exception.Message
            }
        }

        [pscustomobject]@{
            ComputerName    = $env:COMPUTERNAME
            Caption         = $operatingSystem.Caption
            Version         = $operatingSystem.Version
            BuildNumber     = $operatingSystem.BuildNumber
            SystemDrive     = $systemDrive.DeviceID
            FreeSpaceGB     = [Math]::Round($systemDrive.FreeSpace / 1GB, 2)
            RuntimeBaseline = $runtimeBaseline
        }
    }

    while ([DateTime]::UtcNow -lt $deadline) {
        $heartbeat = Get-VMIntegrationService -VMName $VmName -ErrorAction SilentlyContinue |
            Where-Object Id -Match '84EAAE65-2F2E-45F5-9BB5-0E857DC8EB47'
        if (-not $reportedHeartbeat -and $heartbeat -and $heartbeat.PrimaryStatusDescription -eq 'OK') {
            Write-Host 'Guest heartbeat is available; waiting for unattended setup to finish.'
            $reportedHeartbeat = $true
        }

        try {
            return Invoke-Command -VMName $VmName -Credential $Credential -ScriptBlock $probe -ErrorAction Stop
        } catch {
            $lastError = $_.Exception.Message
        }

        Start-Sleep -Seconds 10
    }

    throw "Timed out after $TimeoutMinutes minutes waiting for PowerShell Direct and the setup completion marker. Last error: $lastError"
}

function Remove-TinyWinTestArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TestRoot,

        [Parameter(Mandatory)]
        [string]$OutputRoot
    )

    if (-not (Test-Path -LiteralPath $TestRoot)) {
        return
    }

    $resolvedOutputRoot = [Path]::GetFullPath($OutputRoot).TrimEnd('\')
    $resolvedTestRoot = [Path]::GetFullPath($TestRoot)
    if (-not $resolvedTestRoot.StartsWith("$resolvedOutputRoot\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove test artifacts outside '$resolvedOutputRoot'."
    }

    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction Stop
}

Assert-TinyWinHyperVEnvironment

$resolvedIsoPath = (Resolve-Path -LiteralPath $IsoPath -ErrorAction Stop).Path
$outputRoot = [Path]::GetFullPath($OutputPath)
$safeVmName = [regex]::Replace($VmName, '[^A-Za-z0-9._-]', '_')
$testRoot = Join-Path $outputRoot $safeVmName
$unattendPath = Join-Path $testRoot 'Autounattend.xml'
$answerIsoPath = Join-Path $testRoot 'TinyWin-Answer.iso'
$vhdPath = Join-Path $testRoot "$safeVmName.vhdx"
$runtimeBaselinePath = Join-Path $outputRoot "$safeVmName.runtime-baseline.json"
$testUserName = 'Administrator'
$testPassword = New-TinyWinTestPassword
$secureTestPassword = [Security.SecureString]::new()
foreach ($character in $testPassword.ToCharArray()) {
    $secureTestPassword.AppendChar($character)
}
$secureTestPassword.MakeReadOnly()
$unattendCredential = [pscredential]::new($testUserName, $secureTestPassword)
$createdVm = $false
$succeeded = $false

if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) {
    throw "Hyper-V VM '$VmName' already exists. Choose a unique -VmName."
}
if (Test-Path -LiteralPath $testRoot) {
    throw "Test artifact directory '$testRoot' already exists. Choose a unique -VmName or remove it after inspection."
}
if ($KeepVm) {
    $KeepArtifacts = $true
}

if ($WhatIfPreference) {
    Write-Host "WhatIf: Create a Generation 2 VM and install '$resolvedIsoPath' on '$VmName'."
    return
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force -ErrorAction Stop | Out-Null
    New-TinyWinUnattendContent -Credential $unattendCredential -ImageIndex $ImageIndex -UiLanguage $UiLanguage -InputLocale $InputLocale |
        Set-Content -LiteralPath $unattendPath -Encoding utf8 -NoNewline
    New-TinyWinAnswerIso -UnattendPath $unattendPath -AnswerIsoPath $answerIsoPath

    New-VHD -Path $vhdPath -Dynamic -SizeBytes ($VhdSizeGB * 1GB) -ErrorAction Stop | Out-Null
    New-VM -Name $VmName -Generation 2 -NoVHD -MemoryStartupBytes ($MemoryStartupGB * 1GB) -ErrorAction Stop | Out-Null
    $createdVm = $true
    Set-VM -Name $VmName -AutomaticCheckpointsEnabled $false -ErrorAction Stop
    $secureBootState = if ($EnableSecureBoot) { 'On' } else { 'Off' }
    Set-VMFirmware -VMName $VmName -EnableSecureBoot $secureBootState -ErrorAction Stop
    Set-VMProcessor -VMName $VmName -Count $ProcessorCount -ErrorAction Stop
    Add-VMHardDiskDrive -VMName $VmName -Path $vhdPath -ErrorAction Stop
    $installDvd = Add-VMDvdDrive -VMName $VmName -Path $resolvedIsoPath -ErrorAction Stop
    $answerDvd = Add-VMDvdDrive -VMName $VmName -Path $answerIsoPath -ErrorAction Stop
    # Re-query devices before setting firmware. The objects returned by
    # Add-VMDvdDrive are not accepted as boot devices by every Hyper-V build.
    # Set the complete order: FirstBootDevice does not reliably supersede the
    # default network entry on every Hyper-V host.
    $installDvd = Get-VMDvdDrive -VMName $VmName -ErrorAction Stop |
        Where-Object Path -EQ $resolvedIsoPath | Select-Object -First 1
    $answerDvd = Get-VMDvdDrive -VMName $VmName -ErrorAction Stop |
        Where-Object Path -EQ $answerIsoPath | Select-Object -First 1
    $systemDisk = Get-VMHardDiskDrive -VMName $VmName -ErrorAction Stop | Select-Object -First 1
    if (-not $installDvd -or -not $answerDvd -or -not $systemDisk) {
        throw 'Could not resolve the Hyper-V boot devices after attaching installation media.'
    }
    Set-VMFirmware -VMName $VmName -BootOrder @($installDvd, $answerDvd, $systemDisk) -ErrorAction Stop

    if ($VmSwitchName) {
        Get-VMSwitch -Name $VmSwitchName -ErrorAction Stop | Out-Null
        Connect-VMNetworkAdapter -VMName $VmName -SwitchName $VmSwitchName -ErrorAction Stop
    }

    Write-Host "Starting Hyper-V smoke-test VM '$VmName'."
    Start-VM -Name $VmName -ErrorAction Stop | Out-Null

    # The installation media must be first for the initial UEFI boot, but it
    # must not remain first for the post-install reboot. Otherwise Setup starts
    # over from the DVD and the target disk stays under $Windows.~BT\NewOS.
    Start-Sleep -Seconds $BootDeviceHandoffDelaySeconds
    $systemDisk = Get-VMHardDiskDrive -VMName $VmName -ErrorAction Stop | Select-Object -First 1
    $installDvd = Get-VMDvdDrive -VMName $VmName -ErrorAction Stop |
        Where-Object Path -EQ $resolvedIsoPath | Select-Object -First 1
    $answerDvd = Get-VMDvdDrive -VMName $VmName -ErrorAction Stop |
        Where-Object Path -EQ $answerIsoPath | Select-Object -First 1
    if ($systemDisk -and $installDvd -and $answerDvd) {
        Set-VMFirmware -VMName $VmName -BootOrder @($systemDisk, $installDvd, $answerDvd) -ErrorAction Stop
        Write-Host 'System disk is first for the next reboot; installation media remains attached for Setup.'
    } else {
        Write-Warning 'Could not re-query all boot devices after initial boot; the VM may restart from installation media.'
    }
    $credential = [pscredential]::new(".\$testUserName", $secureTestPassword)
    $guestResult = if ($SkipGuestProbe) {
        $null
    } else {
        Wait-TinyWinVmInstall -VmName $VmName -Credential $credential -TimeoutMinutes $TimeoutMinutes
    }
    if ($guestResult) {
        $guestResult.RuntimeBaseline | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $runtimeBaselinePath -Encoding utf8
    }
    $succeeded = $true

    [pscustomobject]@{
        VmName              = $VmName
        IsoPath             = $resolvedIsoPath
        ImageIndex          = $ImageIndex
        Guest               = $guestResult
        RuntimeBaselinePath = if ($guestResult) { $runtimeBaselinePath } else { $null }
        ArtifactsPath       = if ($KeepArtifacts) { $testRoot } else { $null }
        TestUserName        = if ($KeepVm) { $testUserName } else { $null }
        TestPassword        = if ($KeepVm) { $testPassword } else { $null }
        KeptVm              = [bool]$KeepVm
        KeptArtifacts       = [bool]$KeepArtifacts
    }
} finally {
    if ($succeeded -and -not $KeepVm -and $createdVm) {
        $vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
        if ($vm) {
            if ($vm.State -ne 'Off') {
                Stop-VM -Name $VmName -TurnOff -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Remove-VM -Name $VmName -Force -ErrorAction SilentlyContinue
        }
    }

    if ($succeeded -and -not $KeepArtifacts) {
        Remove-TinyWinTestArtifacts -TestRoot $testRoot -OutputRoot $outputRoot
    } elseif (-not $succeeded -and (Test-Path -LiteralPath $testRoot)) {
        Write-Warning "Hyper-V smoke test did not complete. VM and artifacts were retained at '$testRoot' for diagnosis."
    }
}
