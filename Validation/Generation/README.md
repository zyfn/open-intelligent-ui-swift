# 模型生成评测

这里验证模型能否按 Intelligent UI 当前生成契约完成给定任务。它与 Gallery 固定案例、语言性能基准分别维护。

| 输入/输出 | 职责 |
|---|---|
| `cases.json` | 11 个主任务，包含指定组件和自由组合任务；部分包含后续轮次 |
| `response-schema.json` | 模型输出的 JSON 传输包装，`program` 才是 Lang 源码 |
| `run.py` | 通过指定 Codex CLI 运行真实生成，记录原始输出，再调用独立 ContractExport 工具 |
| `outputs/generation/<model>/<run>/` | 本次请求、输出、日志与结果；不提交到 SDK |

先在受支持的 Mac 上导出当前契约并构建验证器，再按需运行：

```sh
swift run --package-path Tools/ContractExport ContractExport "$PWD/outputs/contracts"
python3 Validation/Generation/run.py --model gpt-6.1-terra --suite guided
python3 Validation/Generation/run.py --model gpt-6.1-terra --suite free --case free-form
```

这是可选的真实模型调用，会使用所选 Codex 账户的额度；普通 SDK 构建、测试和 Gallery 调试都不需要运行它。工具不会静默更换模型；CLI 未提供实际响应模型身份时，报告保留 `actualModel: null`。

运行时检查只验证已实现的契约与交互断言。内容来源、呈现和实际操作审查分别保留 `pending`，不能从解析成功推断它们已通过。

已经纳入回归的六份未改写程序现在位于 [GeneratedPrograms](../../Tests/OpenIntelligentSwiftUITests/Fixtures/GeneratedPrograms/README.md)，由 XCTest 读取；旧人工验收报告不再混入日常示例入口。
