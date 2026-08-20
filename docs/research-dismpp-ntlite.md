# DISM++ 与 NTLite 调研

本调研用于指导 TinyWin 的后续架构演进，而不是复刻任一工具的界面、预设或闭源实现。参考资料：

- [Dism++ 多语言数据文件](https://github.com/Chuyu-Team/Dism-Multi-language/blob/master/Data.xml)
- [NTLite Components 文档](https://ntlite.com/docs/components/)
- [NTLite Features 文档](https://ntlite.com/docs/features/)
- [NTLite Updates 文档](https://ntlite.com/docs/updates/)
- [NTLite Drivers 文档](https://ntlite.com/docs/drivers/)
- [NTLite Registry 文档](https://ntlite.com/docs/registry/)
- [NTLite Unattended 文档](https://ntlite.com/docs/unattended/)
- [NTLite Post-Setup 文档](https://ntlite.com/docs/post-setup/)
- [NTLite Apply 文档](https://ntlite.com/docs/apply/)

## DISM++：规则驱动的清理与设置

其开源 `Data.xml` 将规则分成清理和系统优化两部分：`CleanCollection4` 有 73 个清理项，覆盖组件存储、更新残留、日志、临时文件、缓存和应用数据；`SystemOptimization` 有 21 个设置组，涵盖安全、服务、网络、Windows Update、资源管理器和应用设置。

每个清理规则都将以下信息放在一起：

1. 面向用户的名称、分组、说明、风险等级与警告。
2. `Applicable`：OS 版本、在线/离线映像、文件或注册表是否存在等适用条件。
3. `Scan`：扫描成本或工作量。
4. `Activate`：清理或设置操作，例如 DISM 组件清理、注册表写入或目录清理。

这个模型最有价值的部分是将“何时可执行”和“执行会造成什么后果”作为规则的一等信息，而不是让 UI 猜测条目是否可用。

### 不直接沿用的部分

- 其中有大量在线系统调校与双向复选框设置；TinyWin 的边界是离线映像构建，应避免将在线优化逻辑混入精简条目。
- 某些安全与网络规则会关闭 UAC、Defender 或防火墙。TinyWin 可将它们提供为默认不选的高风险 Entry，必须在执行前清楚展示影响和恢复方式。
- XML 将扫描、适用性和执行逻辑混在一个数据文件中；TinyWin 应保持 JSON 元数据与受控 PowerShell Handler 的代码分离。

## NTLite：先分析，再形成可审查队列

NTLite 的核心工作流是：加载目标映像，集成更新/驱动/注册表，移除组件与计划任务，配置 Features/FOD 与设置，配置无人值守与 Post-Setup，最后在 Apply 页复核变更队列并保存为 WIM、ESD 或 ISO。

其中最值得 TinyWin 借鉴的能力如下。

| 能力 | NTLite 的做法 | TinyWin 应采用的形式 |
| --- | --- | --- |
| 组件移除 | 检测可移除组件，展示依赖与安全警告 | 对 Entry 的目标包、Feature、Capability 在执行前解析并给出影响 |
| 兼容性 | 通过 Compatibility 选项锁定关联组件，避免误删 | 提供 Compatibility Analysis；展示受影响能力与风险，但不替用户阻止明确选择的 Entry |
| 映像状态 | 展示组件、Feature、FOD、更新包的当前状态 | 引入只读 Inspection，Entry 仅根据它显示适用性与预计影响 |
| 变更队列 | Apply 前集中展示所有待执行操作和最终格式 | 将 BuildPlan 扩展为可序列化的 Preview/Impact Report，确认后才挂载并修改映像 |
| 更新与驱动 | 在队列中提示更新前置条件和兼容性，按 INF 集成驱动 | 将 `Update.Integrate`、`Driver.Integrate` 作为未来独立 Handler，不混入精简项 |
| 多映像输出 | 可处理多个 Edition，且可输出 WIM、ESD、ISO | 继续以单索引构建保证可复现；多索引应是显式批处理能力，而非隐式副作用 |

NTLite 也有 Privacy、Gaming、Lite 等模板。这些是批量选中组件的快捷方式，不应成为 TinyWin 的领域模型。TinyWin 的最小选择单位始终是独立 Entry；将来若提供快捷选择，也只能是 UI 层的可见筛选或用户保存的 Entry ID 列表，不能影响核心计划和执行语义。

## 对 TinyWin 的设计决定

当前架构已经正确地把 `entries/` 的数据模型、`entry-handlers/` 的执行代码和 WinUI 展示层分开。需要补上的不是 Profile，而是映像事实模型与保护机制。

### 1. 引入独立的 Inspection 阶段

在任何变更前，以只读方式收集一个 `TinyWinImageInspection`：

- Image index、Edition、架构、Windows 版本；
- Optional Features 与状态；
- Capabilities / Features on Demand；
- 已安装 Packages、Provisioned Appx；
- 相关服务、计划任务与离线注册表事实；
- 每个候选目标是否存在及可取得的大小信息。

Inspection 是输入快照，不应由 Handler 在运行时隐式重新推断。它应同时供 PowerShell 计划器和 WinUI 使用，避免两个层面对“可用”得出不同结论。

### 2. 将 Entry 从静态说明扩展为可评估契约

不保留旧契约的兼容层时，可将 `schemaVersion` 直接升级为 `2`，增加下列可选字段：

```text
applicability          # 需要存在的 Feature、Capability、Package、Appx 或注册表事实
operationKind          # Feature.Remove / Capability.Remove / Service.Configure 等规范操作类别
estimatedImpact        # 功能影响与人工可读说明
estimatedSize          # 已知估算值；运行时事实优先
reversible             # 是否可通过原始介质恢复
protects               # 选择此项时必须保留的能力
verification           # 执行后的只读断言
```

`requires` 与 `conflicts` 继续只表示 Entry 间的选择关系；映像中的存在性、依赖和版本条件属于 `applicability`，两者不可混用。

### 3. 先评估，再构建计划

将计划生命周期改为：

```text
Source media -> Inspection -> Entry evaluation -> Compatibility Guard
             -> Preview / Impact Report -> confirmed BuildPlan -> mutation -> verification -> manifest
```

每个 Entry 的评估结果应至少为：`Available`、`AlreadyAbsent`、`NotApplicable`、`Blocked` 或 `Conflict`。WinUI 只渲染该结果并选择 Entry，不能重复实现适用性、依赖或保护规则。

### 4. Compatibility Analysis 提供建议，不实施硬锁

分析器在生成计划时运行，独立于 Handler。它至少需要：

- 将工作负载声明的保护能力反向解析为受影响的 Package、Feature 与 Capability；
- 对每个高风险条目给出被影响能力与恢复方式；
- 在 Handler 前验证实际目标仍与 Inspection 一致，防止计划过期。

分析结果用于警告和预览，不应阻止用户明确选择的 Entry。Handler 不应通过 UAC 或 Firewall 的名称黑名单覆盖用户选择。

### 5. 规范 Handler，而不是把 PowerShell 写进 JSON

优先形成小而稳定的受控 Handler 集合：

```text
Appx.RemoveProvisioned
Package.Remove
Capability.Remove
Feature.Disable
Feature.RemovePayload
Service.Configure
ScheduledTask.Disable
Registry.SetOfflineValue
File.Cleanup
Dism.ComponentCleanup
Update.Integrate
Driver.Integrate
DriverStore.RemoveInbox
Unattended.Write
PostSetup.Copy
```

每个 Handler 接受已经规范化的 Operation，返回结构化结果，并以 `verification` 验证结果。复杂且无法安全声明化的行为仍放在 `entry-handlers/`，但由固定名称 allowlist 调度，绝不让 Entry 指向任意脚本路径。

## 推荐实施顺序

1. 先实现 `Get-TinyWinImageInspection` 和稳定的序列化模型。
2. 扩展 Entry schema 与目录加载器，新增 `applicability`、影响与验证字段。
3. 在 `New-TinyWinBuildPlan` 中执行 Entry evaluation 和 Compatibility Guard，输出 Preview/Impact Report。
4. 将 WinUI 改为消费同一份 Inspection/Evaluation 结果，而非仅凭 JSON 直接勾选。
5. 再逐步增加 `Capability`、`Feature`、`Service`、`ScheduledTask` 和 `File.Cleanup` Handler 及对应 Entry。

这样新增一个普通精简项仍只需添加 JSON；只有出现新的底层 Windows 操作语义时才新增一个可测试 Handler。选择模型保持归一化，复杂度集中在可复用的 Inspection、Guard 和 Handler 层。
