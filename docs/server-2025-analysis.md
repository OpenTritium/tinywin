# Windows Server 2025 镜像盘点

本报告基于 `26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_zh-cn.iso` 的索引 2（Windows Server 2025 Standard Evaluation，桌面体验）进行只读挂载盘点。该 ISO 还包含 Standard / Datacenter 的 Server Core 与桌面体验索引；选择其他索引构建前应重新盘点其实际功能状态。

## 保留边界

TinyWin 的新增 Entry 不会移除 UAC 或 Windows 防火墙。`Dism.RemoveOptionalComponent` 处理器拒绝任何名称匹配 UAC、UserAccountControl 或 Firewall 的功能。`dism.remove-windows-defender` 只处理 Defender 与 Sense；如需连同安全中心界面移除，请额外选择 `appx.remove-security-health-ui`。

## 实际发现

镜像中已启用 Defender、媒体播放、打印客户端和 Print to PDF、Windows Search、Work Folders、无线网络、Windows Server Backup 管理单元、XPS Viewer、Windows Admin Center Setup 与 Azure Arc Setup。它还预装了 OpenSSH Client/Server、Internet Explorer 兼容组件、PowerShell ISE、WMIC、VBScript、画图、记事本、截图工具和中文 OCR / 语音 / 手写能力。

Hyper-V、WSL、VirtualMachinePlatform、Windows Containers、IIS、SMB1、Telnet、TFTP、SNMP 等在原始映像中处于禁用状态，但其 payload 仍可存在。选中相应 Entry 时会删除 payload；功能已被删除的版本则记录跳过而不会失败。

## 新增选择

| 目标 | Entry |
| --- | --- |
| 移除 Defender 与 Endpoint Sense | `dism.remove-windows-defender` |
| 移除安全中心界面 | `appx.remove-security-health-ui` |
| 移除 Hyper-V / WSL / Containers | `dism.remove-hyper-v`、`dism.remove-wsl`、`dism.remove-containers` |
| 移除打印、媒体、搜索、无线和 Work Folders | `dism.remove-printing`、`dism.remove-media`、`dism.remove-search`、`dism.remove-wireless-networking`、`dism.remove-workfolders` |
| 移除远程与管理工具 | `dism.remove-openssh-client`、`dism.remove-openssh-server`、`dism.remove-windows-admin-center`、`dism.remove-server-backup` |
| 移除遗留与桌面工具 | `dism.remove-internet-explorer`、`dism.remove-powershell-ise`、`dism.remove-wmic`、`dism.remove-vbscript`、`dism.remove-paint`、`dism.remove-notepad`、`dism.remove-snipping-tool`、`dism.remove-steps-recorder` |
| 移除中文可选语言能力 | `dism.remove-chinese-handwriting`、`dism.remove-chinese-ocr`、`dism.remove-chinese-speech`、`dism.remove-chinese-text-to-speech` |

所有条目默认不勾选。极致精简应先在虚拟机中验证工作负载，并保留构建生成的 `tinywin-manifest.json`，以便精确复现选择。
