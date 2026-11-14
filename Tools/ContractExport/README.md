# ContractExport

独立的 macOS 开发工具包，依赖仓库根 SDK 的公开产品。它导出 Intelligent UI 的生成契约，或校验已有程序；不会成为客户端安装的 SDK executable。

初始 `Package.resolved` 原字节沿用根 SDK 的已固定依赖 pins；这次目录调整没有在无 Swift 的环境中重新解析依赖。

从仓库根目录运行：

```sh
swift run --package-path Tools/ContractExport ContractExport "$PWD/outputs/contracts"
swift run --package-path Tools/ContractExport ContractExport --validate "$PWD/path/to/program.openui"
swift run --package-path Tools/ContractExport ContractExport --reader-contract --include-search "$PWD/outputs/reader-contract"
swift run --package-path Tools/ContractExport ContractExport --validate "$PWD/path/to/historical.openui" --historical
```

默认导出 `spec.json`、`prompt.txt` 和 `manifest.json`。`--validate` 接受原始 Lang 源码或包含 `program` 的 JSON，默认按当前生成契约验证；`--historical` 使用历史读取契约。`--case` 保留生成评测使用的明确行为检查。

检查使用本地工具桩，不发起真实业务调用。解析、契约与行为检查通过不等于视觉或事实审查通过。双库人工调试使用 [Gallery](../../Examples/Gallery/README.md)，模型生成评测见 [Validation/Generation](../../Validation/Generation/README.md)。
