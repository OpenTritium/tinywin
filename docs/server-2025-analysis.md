# Windows Server 2025 镜像盘点

本报告基于 `26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_zh-cn.iso` 的索引 2（Windows Server 2025 Standard Evaluation，桌面体验）进行只读挂载盘点。该 ISO 还包含 Standard / Datacenter 的 Server Core 与桌面体验索引；选择其他索引构建前应重新盘点其实际功能状态。

## 风险边界

所有 Entry 均默认不勾选。UAC 与 Windows 防火墙可通过高风险 Entry 禁用：`registry.disable-uac` 和 `registry.disable-windows-firewall`。前者会破坏 Microsoft Store 应用及依赖 UAC 的功能，后者会使设备暴露在网络攻击面中；只有明确了解后果时才应选择。`dism.remove-windows-defender` 只处理 Defender 与 Sense；如需连同安全中心界面移除，请额外选择 `appx.remove-security-health-ui`。

## 实际发现

镜像中已启用 Defender、媒体播放、打印客户端和 Print to PDF、Windows Search、Work Folders、无线网络、Windows Server Backup 管理单元、XPS Viewer、Windows Admin Center Setup 与 Azure Arc Setup。它还预装了 OpenSSH Client/Server、Internet Explorer 兼容组件、PowerShell ISE、WMIC、VBScript、画图、记事本、截图工具和中文 OCR / 语音 / 手写能力。

Hyper-V、WSL、VirtualMachinePlatform、Windows Containers、IIS、SMB1、Telnet、TFTP、SNMP、NFS、MSMQ、Failover Clustering、Storage Replica 等在原始映像中处于禁用状态，但其 payload 仍可存在。`NetFx4`、WCF、SMB Direct、文件和存储服务、打印、媒体和搜索则处于启用状态。选中相应 Entry 时会删除 payload；功能已被删除的版本则记录跳过而不会失败。

原始介质通常会带有中文手写、OCR、语音和文本转语音 payload；本次最终 WIM 的实测 Capability 则只保留了中文 Basic/字体等基础项。日语和韩语语言/输入能力不在当前索引中，跨 Edition 选择对应 Entry 时会安全跳过。Driver Store 则包含大量 Inbox 厂商驱动，包括 Adaptec、Broadcom/LSI/Avago、Dell PERC、HP、Intel、QLogic、VMware、AMD 和移动平台驱动。驱动条目只删除明确声明的 `FileRepository` 包；误删启动存储或当前硬件所需驱动会造成系统无法启动。

## 当前最终 WIM 的实测状态

对最近生成的 `install.wim` 索引 1 做了只读 DISM 盘点。仍处于 Enabled 的 Feature 包括 `Server-Gui-Mgmt`、`Server-Shell`、`RSAT`、`MicrosoftWindowsPowerShell`、`NetFx4`、`NetFx4ServerFeatures`、`FileAndStorage-Services`、`Storage-Services`、打印驱动和 Server Core 基础包。已安装 Capability 只有中文基础语言/字体、排序版本、DirectX 配置数据库、MathRecognizer、Sense Client 与 LA57 内核能力；日语、韩语和大多数按需语言能力不在该索引中。

大量服务器角色在该 WIM 中是 `Disabled` 但仍保留 payload，例如 AD DS/AD CS、DHCP、DNS、DFS Replication、Dedup、MPIO、NPS、Remote Access、WSUS、SMB1、BitLocker 工具和 System Insights。它们现在都有独立 Entry，勾选后才从组件存储中移除；如果某个 Edition 没有该组件，处理器会记录跳过而不会伪造成功。

## 新增选择

| 目标 | Entry |
| --- | --- |
| 移除 Defender 与 Endpoint Sense | `dism.remove-windows-defender` |
| 移除安全中心界面 | `appx.remove-security-health-ui` |
| 禁用 UAC 或 Windows 防火墙 | `registry.disable-uac`、`registry.disable-windows-firewall` |
| 移除 Hyper-V / WSL / Containers | `dism.remove-hyper-v`、`dism.remove-wsl`、`dism.remove-containers` |
| 移除打印、媒体、搜索、无线和 Work Folders | `dism.remove-printing`、`dism.remove-media`、`dism.remove-search`、`dism.remove-wireless-networking`、`dism.remove-workfolders` |
| 移除远程与管理工具 | `dism.remove-openssh-client`、`dism.remove-openssh-server`、`dism.remove-windows-admin-center`、`dism.remove-server-backup` |
| 移除遗留与桌面工具 | `dism.remove-internet-explorer`、`dism.remove-powershell-ise`、`dism.remove-wmic`、`dism.remove-vbscript`、`dism.remove-paint`、`dism.remove-notepad`、`dism.remove-snipping-tool`、`dism.remove-steps-recorder` |
| 移除中文可选语言能力 | `dism.remove-chinese-handwriting`、`dism.remove-chinese-ocr`、`dism.remove-chinese-speech`、`dism.remove-chinese-text-to-speech` |
| 移除日语或韩语输入/语言能力 | `dism.remove-japanese-language`、`dism.remove-korean-language` |
| 移除 .NET、WCF 与旧版组件 | `dism.remove-dotnet-framework-3.5`、`dism.remove-dotnet-framework-4`、`dism.remove-wcf`、`dism.remove-legacy-components` |
| 移除服务器角色与协议 payload | `dism.remove-iis`、`dism.remove-message-queue`、`dism.remove-nfs`、`dism.remove-failover-clustering`、`dism.remove-storage-replica`、`dism.remove-snmp` 等 |
| 移除按厂商分组的 Inbox 驱动 | `driverstore.remove-vendor-raid-controllers`、`driverstore.remove-fibre-channel-drivers`、`driverstore.remove-mobile-platform-drivers` |
| 移除浏览器和桌面 Appx | `dism.remove-edge`、`appx.remove-calculator`、`appx.remove-photos`、`appx.remove-mail-calendar` |
| 移除管理/服务器组件 | `dism.remove-adfs`、`dism.remove-rds-management-tools`、`dism.remove-powershell-v2`、`registry.disable-iscsi-initiator` |
| 移除域、网络和更新服务器角色 | `dism.remove-active-directory`、`dism.remove-ad-certificate-services`、`dism.remove-dhcp-server`、`dism.remove-dns-server`、`dism.remove-network-policy-server`、`dism.remove-remote-access`、`dism.remove-wsus` |
| 移除存储和旧协议角色 | `dism.remove-dfs-replication`、`dism.remove-data-deduplication`、`dism.remove-multipath-io`、`dism.remove-smb1`、`dism.remove-bitlocker`、`dism.remove-system-insights`、`dism.remove-fax` |
| 清理镜像残留目录 | `filesystem.remove-inetpub`、`filesystem.remove-windows-old`、`filesystem.remove-prefetch`、`filesystem.remove-windows-mail` |
| 移除按需辅助功能 | `dism.remove-braille-support` |

## 服务级精简候选

以下条目只修改离线 SYSTEM hive 中的服务启动类型，不移除 Server Manager、Windows Update 核心、RPC、WMI、UAC 或 Windows 防火墙。它们适合在确认工作负载不需要对应能力后单独勾选：

| 目标 | Entry | 影响 |
| --- | --- | --- |
| SysMain 预取 | `registry.disable-sysmain` | 减少后台预取活动，应用冷启动可能变慢 |
| Delivery Optimization | `registry.disable-delivery-optimization` | 更新共享关闭，Windows Update 改用传统下载 |
| 跨设备体验 | `registry.disable-connected-devices-platform` | 附近共享和跨设备活动不可用 |
| Phone Link/移动集成 | `registry.disable-phone-service` | Phone Link 和部分移动宽带功能不可用 |
| 推送通知 | `registry.disable-push-notifications` | Toast 和实时应用通知不可用 |
| 分布式链接跟踪 | `registry.disable-distributed-link-tracking` | NTFS 移动跟踪及部分域环境链接维护不可用 |
| 生物识别 | `registry.disable-biometric-service` | 指纹、人脸等 Windows 生物识别登录不可用 |
| 数据使用量统计 | `registry.disable-data-usage-service` | 系统流量统计不可用 |
| Edge 自动更新 | `registry.disable-edge-update` | Edge/WebView 不再自动更新 |
| 蓝牙 | `registry.disable-bluetooth` | 蓝牙键鼠、耳机和其他蓝牙设备不可用 |
| 音频 | `registry.disable-audio` | 音频输出、录音和音频会话不可用 |
| 智能卡 | `registry.disable-smart-card` | 智能卡登录和证书读卡器不可用 |
| 传统电话/TAPI | `registry.disable-telephony` | 调制解调器和传统电话应用不可用 |
| 性能日志 | `registry.disable-performance-logs` | PLA Data Collector Set 不可用 |
| 自动故障诊断 | `registry.disable-windows-diagnostics` | 网络和系统诊断向导不可用 |
| 设备自动关联 | `registry.disable-device-association` | USB、蓝牙等设备配对可能失败 |
| User Access Logging | `registry.disable-user-access-logging` | 服务器角色使用统计不再记录 |
| 程序兼容性助手 | `registry.disable-compatibility-assistant` | 旧程序兼容性提示不可用 |
| 清单与兼容性评估 | `registry.disable-inventory-service` | 硬件/软件清单和兼容性评估任务不可用 |
| 剪贴板用户服务 | `registry.disable-clipboard-user-service` | 剪贴板历史和跨设备同步不可用 |
| 用户数据服务 | `registry.disable-user-data-services` | Mail/Calendar/Contacts 和用户数据 API 可能不可用 |
| MSDTC | `registry.disable-distributed-transaction-coordinator` | 分布式事务不可用 |

### 按需/延迟启动

这些条目不会删除服务文件。`Manual` 依赖 Windows 服务触发器按需启动，通常比 `DelayedAuto` 更节省常驻内存；`DelayedAuto` 仍会在开机后启动，只是避开启动高峰。它们适合与同名的禁用条目二选一：

| 目标 | Entry | 模式 |
| --- | --- | --- |
| 诊断服务按需启动 | `registry.manual-diagnostic-policy` | `Manual` |
| 字体缓存延迟启动 | `registry.delay-font-cache` | `DelayedAuto` |
| User Access Logging 延迟启动 | `registry.delay-user-access-logging` | `DelayedAuto` |

用户服务名称通常带随机实例后缀，例如 `WpnUserService_486b3`、`cbdhsvc_486b3`。服务 Entry 支持 `servicePatterns`，会在离线 SYSTEM hive 中枚举并匹配这些实例，不会把某台虚拟机的后缀硬编码到镜像。

## Hyper-V 虚拟机服务实测

当前 `TinyWin-Extreme-20260820` 启动后，较适合做内存优化验证的进程私有工作集如下。数值来自一次采样，仅用于排序，不作为固定容量承诺：

| 服务/进程 | 私有工作集约 | 备注 |
| --- | ---: | --- |
| `DPS` (`svchost`) | 12.8 MB | 可改手动或禁用，分别对应 `registry.manual-diagnostic-policy` / `registry.disable-windows-diagnostics` |
| `WpnUserService_*` | 6.1 MB | 推送通知用户服务，可禁用模板实例 |
| `CDPUserSvc_*` | 4.1 MB | 跨设备用户服务，可与 `CDPSvc` 一起禁用 |
| `PcaSvc` | 2.9 MB | 程序兼容性助手，可选禁用 |
| `MSDTC` | 共享 `svchost` | 禁用主要减少事务触发，不保证立刻回收整个进程 |

多个服务经常共享同一个 `svchost.exe`，因此“禁用一个服务 = 释放一个完整进程”是不成立的。验证镜像时应同时记录启动后总内存、服务状态和工作负载，而不是只看条目数量。RPC、WMI、事件日志、网络栈和防火墙所在的共享宿主进程不要为了追求工作集而关闭。

这些条目默认不勾选。它们不会因为目标服务在某个 Edition 中不存在而使构建失败；构建日志会记录跳过的服务。

## 不建议伪装成可删除项的基础组件

Windows PowerShell 5.1、ODBC/MDAC/ADO、RPC、WMI、Windows Update 基础服务、Windows Filtering Platform、UAC 和防火墙属于系统管理或应用兼容基础。它们没有稳定的独立可选 Feature；强行删除 CBS 文件会导致 Server Manager、安装程序、驱动安装或普通应用异常。因此项目只提供 PowerShell 2.0、iSCSI Initiator 服务和 RDS 管理工具等边界清晰的条目。

Edge 在不同 Windows Server/Client 版本中的封装方式不一致。`dism.remove-edge` 只匹配明确的 Edge CBS 包；没有匹配包时会记录跳过，绝不通过删除 `Program Files` 目录伪造成功。

所有条目默认不勾选。极致精简应先在虚拟机中验证工作负载，并保留构建生成的 `tinywin-manifest.json`，以便精确复现选择。
