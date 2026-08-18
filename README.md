# TinyWin

一个工程化的 Windows 离线镜像精简器。项目参考 `ntdevlabs/tiny11builder` 的 DISM 工作流，但以独立 Entry 作为最小可选单元，将条目数据、执行处理器和 WinUI 展示层分离。

详细设计见 [架构说明](docs/architecture.md)。

## 前置条件

- Windows 上以管理员身份运行 PowerShell 7.4+。
- 系统自带 DISM PowerShell 模块和 Windows 映像工具。
- 若需要 ISO 输出，安装 Windows ADK Deployment Tools，并让 `oscdimg.exe` 在 `PATH` 中，或显式传入其路径。
- 使用合法获得的 Windows 安装 ISO，并将它放入被 Git 忽略的 `raw/`。

## 条目模型

`entries/*.json` 中的每个文件就是一个可选精简条目。条目只描述元数据、风险、处理器和参数，不包含 PowerShell 代码。多个条目通过 `EntryId` 组合成一次构建。

简单精简项复用已有处理器即可只增加 JSON；复杂精简项在 `entry-handlers/` 中实现受控处理器，再由条目的 `handler` 字段引用。处理器不会从 JSON 动态加载任意路径。

```powershell
Import-Module ./src/TinyWin/TinyWin.psd1
Get-TinyWinEntry | Format-Table Id, Category, Risk, Title
New-TinyWinBuildPlan -EntryId appx.remove-xbox,registry.disable-chat
```

## 命令行使用

先查看 ISO/安装介质中的可用索引：

```powershell
Get-TinyWinImageInfo -SourcePath ./raw/windows.iso
```

明确选择要执行的条目：

```powershell
pwsh ./scripts/build.ps1 `
  -SourcePath ./raw/windows.iso `
  -ImageIndex 1 `
  -EntryId appx.remove-xbox,registry.disable-chat,dism.cleanup-components `
  -CreateIso
```

也可由 .NET 11 入口调用同一 PowerShell 工作流：

```powershell
dotnet run --project ./src/TinyWin.Host -- `
  -SourcePath ./raw/windows.iso `
  -ImageIndex 1 `
  -EntryId appx.remove-xbox,registry.disable-chat
```

由 PowerShell 启动 WinUI 展示层（开发环境）：

```powershell
pwsh ./scripts/start-ui.ps1
```

先使用 `-WhatIf` 检查选中的构建目标。成功后，`out/TinyWin-*/tinywin-manifest.json` 会记录 Entry 版本和哈希、每个处理器的执行状态、事件日志以及最终 WIM 的 SHA-256。

## PowerShell LSP、格式化与 lint

PowerShell 的 LSP 由 VS Code 的 `ms-vscode.powershell` 扩展通过 PowerShell Editor Services 提供。仓库已提供 `.vscode/settings.json` 和扩展推荐。

命令行工具使用仓库本地 `.tools/`，首次运行会从 PSGallery 下载 PSScriptAnalyzer：

```powershell
pwsh ./scripts/ensure-pwsh-tools.ps1
pwsh ./scripts/format.ps1
pwsh ./scripts/format.ps1 -Check
pwsh ./scripts/lint.ps1
```

## 目录

```text
entries/            Entry 元数据和声明式参数
entry-handlers/     复杂 Entry 的受控执行代码
schemas/            Entry JSON Schema
src/TinyWin/        PowerShell 领域模块、目录加载和计划执行
src/TinyWin.Host/   .NET 11 命令行转发器
src/TinyWin.WinUI/  WinUI 3 条目选择界面
raw/                用户输入，已忽略
out/                构建输出，已忽略
.reference/         浅克隆的参考实现，已忽略
```
