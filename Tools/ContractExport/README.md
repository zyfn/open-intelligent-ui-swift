# ContractExport

文档版本：1.0 · 更新日期：2026-11-23

独立的 macOS 开发工具包，依赖仓库根 SDK 的公开产品。它导出 OpenIntelligentUI 的生成契约，或校验该库的已有程序；不会成为客户端安装的 SDK executable。

初始 `Package.resolved` 原字节沿用根 SDK 的已固定依赖 pins；这次目录调整没有在无 Swift 的环境中重新解析依赖。

从仓库根目录运行：

```sh
swift run --package-path Tools/ContractExport ContractExport "$PWD/outputs/contracts"
swift run --package-path Tools/ContractExport ContractExport --validate "$PWD/path/to/program.openui"
swift run --package-path Tools/ContractExport ContractExport --reader-contract --include-search "$PWD/outputs/reader-contract"
swift run --package-path Tools/ContractExport ContractExport --validate "$PWD/path/to/historical.openui" --historical
```

默认导出 `spec.json`、`prompt.txt` 和 `manifest.json`。`--validate` 接受原始 Lang 源码或包含 `program` 的 JSON，默认按当前生成契约验证；`--historical` 使用历史读取契约。`--reader-contract` 导出 reader，`--include-search` 包含条件注册的 SearchImage，`--exclude-components` 接受逗号分隔的生成目录排除列表。

CLI 拒绝未知选项和多余位置参数。验证结果覆盖源码、运行时与组件契约诊断；视觉、事实与真实交互仍需独立审查。[Gallery](../../Examples/Gallery/README.md) 提供两库的 reader JSON 导出和人工调试；其 reader JSON 不等于 [Validation](../../Validation/README.md) 文件校验入口要求的四文件契约包，各入口按自己的契约工作。
