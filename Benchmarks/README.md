# 性能基准

本目录保存 SDK 的可重复性能工作负载，与展示案例和模型生成质量评测分开维护。

| 基准 | 测量内容 | 运行方式 |
|---|---|---|
| [LanguageRuntime](LanguageRuntime/README.md) | 解析、初始求值、状态更新后求值的耗时分布，以及进程驻留内存采样 | `Benchmarks/LanguageRuntime/run.sh` |

结果写入忽略的 `outputs/benchmarks/`。比较结果时保持机器、系统、构建配置和参数一致；基准不设置未经测量依据的性能阈值。

人工查看组件、场景和不同尺寸使用 [Gallery](../Examples/Gallery/README.md)。模型生成任务及原始输出校验位于 [Validation/Generation](../Validation/Generation/README.md)。自动行为回归属于 `Tests/`。
