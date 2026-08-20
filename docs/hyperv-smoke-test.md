# Hyper-V 冒烟测试

`scripts/test-hyperv.ps1` 会用构建得到的 ISO 创建一个临时的 Hyper-V Generation 2 虚拟机，并以无人值守方式安装 Windows。脚本通过 PowerShell Direct 等待首次登录命令写入完成标记，再读取来宾系统版本、构建号和系统盘状态；这验证映像至少能完成安装、启动和 OOBE。

测试需要以管理员身份运行 PowerShell，并启用 Hyper-V 角色与管理工具。默认不连接网络；只有传入 `-VmSwitchName` 才会为测试 VM 连接指定虚拟交换机。

```powershell
pwsh ./scripts/build.ps1 `
  -SourcePath ./raw/windows.iso `
  -ImageIndex 2 `
  -EntryId dism.remove-hyper-v,dism.remove-wcf `
  -CreateIso

pwsh ./scripts/test-hyperv.ps1 `
  -IsoPath ./out/TinyWin-20260819T000000Z.iso
```

TinyWin 构建的 ISO 只保留一个安装映像，因此测试脚本默认使用 `-ImageIndex 1`。如果传入的是未重新导出的原始安装 ISO，请改为对应的索引。

默认分配 4 GB 内存、2 个 vCPU、64 GB 动态 VHDX，最长等待 45 分钟。可按需调整：

```powershell
pwsh ./scripts/test-hyperv.ps1 `
  -IsoPath ./out/TinyWin-20260819T000000Z.iso `
  -MemoryStartupGB 6 `
  -ProcessorCount 4 `
  -VmSwitchName 'Default Switch'
```

成功后默认会关闭并删除测试 VM、VHDX 与临时应答 ISO，避免累积资源。安装失败、超时或传入 `-KeepVm` 时会保留现场；`-KeepVm` 同时保留工件，并在结果对象中返回临时管理员用户名和密码，方便用 `vmconnect.exe` 继续检查。

```powershell
pwsh ./scripts/test-hyperv.ps1 `
  -IsoPath ./out/TinyWin-20260819T000000Z.iso `
  -VmName TinyWin-ManualCheck `
  -KeepVm
```

测试会格式化该临时 VM 的第一个虚拟磁盘；它从不挂载或修改输入 ISO。所有临时文件位于被 Git 忽略的 `out/hyperv-smoke/`。
