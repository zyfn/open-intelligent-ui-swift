# Performance benchmarks

文档版本：2.1 · 更新日期：2026-11-23

本目录维护可重复运行的 SDK 性能基准。固定工作负载通过预热、重复测量和明确指标比较执行成本；这类 benchmark 不需要调用模型。

| 入口 | 工作负载 | 实际输出 |
|---|---|---|
| [LanguageRuntime](LanguageRuntime/README.md) | 语言解析与求值、公开 State 流式输入、宽对象构建 | P50/P95/Max、解析回调与发布次数、语言负载的 RSS 样本 |

LanguageRuntime 使用 Release 构建，结果写入 `outputs/benchmarks`。参数、预热、样本量、计时范围和复现命令见其说明。该负载不创建 SwiftUI 视图，不能据此判断布局、滚动帧率或生成页面的视觉质量。

## 执行规则

- 对比保留 SDK commit、设备、OS、Xcode/Swift、Release 配置、参数、预热和样本量；使用导出契约的负载另记录 Spec hash。
- 保留真实测量结果与失败，没有测量依据的阈值不预设为通过。
- 原生呈现、滚动与资源压力的后续验收通过 Gallery 和 Instruments 采集独立证据，不能由语言基准推断。

六个领域的测试与验收计划见 [SDK 验证矩阵](../Validation/SDK/README.md)，确定性断言由根 [Tests](../Tests) 执行。真实模型生成评测使用既有 [Validation/Generation](../Validation/Generation/README.md)。
