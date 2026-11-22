# SDK Benchmarks

文档版本：2.0 · 更新日期：2026-11-22

本目录维护 SDK 的标准化工作负载。确定性正确性断言继续由根仓库 Tests 中的 XCTest 执行；Benchmark 复用这些测试与固定 fixtures，补充跨设备、截图、性能和资源测量，不复制第二套测试框架。

| 领域 | 验证目标 | 主要观测 |
|---|---|---|
| Runtime | 解析、求值、状态、依赖与契约正确性 | 解析结果、状态快照、执行耗时 |
| Streaming | 增量输入、发布、取消、换源与恢复 | 内容完整性、Push 分布、发布次数 |
| Components | 组件契约、原生渲染、交互、媒体与生命周期 | 契约通过率、交互结果、资源状态 |
| Layout | 几何分配、嵌套组合、响应式与 Dynamic Type | frame、溢出、遮挡、截图 |
| Visual | DesignSystem、字体、颜色、间距、构图与一致性 | 截图基线、视觉问题清单、人工审查 |
| Performance | 端到端延迟、CPU、内存、布局与滚动成本 | P50/P95/Max、CPU、RSS、帧耗时 |

每个领域的固定工作负载定义在对应目录的 cases.json 中。Reliability 是六个领域共同的验收属性，不重复建立第七类用例。

## 执行规则

- Tests 是确定性测试的执行实现；Benchmarks 描述标准负载、测量维度和证据要求。
- Gallery 用于人工查看与截图采集；Instruments 用于真机性能归因。
- 每份报告记录 SDK commit、Spec hash、设备、OS、Xcode/Swift、Release 配置、参数、预热和样本量。
- 未执行案例标记 planned；没有测量依据的阈值不预设为通过。
- 现有 Benchmarks/LanguageRuntime 继续复用，不重复开发解析和公开 State 流式 runner。
- Agent 指令、模型和生成质量属于后续 Agent Instruction Benchmark，不属于 SDK Bench。
