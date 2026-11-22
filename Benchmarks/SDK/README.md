# SDK Benchmark

SDK Benchmark 衡量 SwiftLang、SwiftOpenUI 与 SwiftIntelligentUI 的原生执行和呈现质量。它不调用模型；Agent 指令与模型变量属于后续独立基准。

## 六个领域

| 领域 | 测试对象 | 主要结果 |
|---|---|---|
| Runtime | Parser、Evaluator、Store、Query、Schema、执行预算 | 语义正确性、状态一致性 |
| Streaming | 增量解析、readiness、发布、取消、换源 | 内容完整性、状态隔离、Push 分布 |
| Components | 两套组件库的注册、参数、默认值、交互、媒体和生命周期 | 契约与交互正确性 |
| Layout | Row/Col/Grid/Box/Card、测量、组合、Dynamic Type、RTL | 几何断言、溢出与遮挡 |
| Visual | DesignSystem、字体、颜色、间距、组件视觉、截图和人工审查 | 视觉回归与审查记录 |
| Performance | 语言、流式、原生呈现、布局、滚动、CPU、内存 | P50/P95/Max 与资源曲线 |

Reliability 横跨六个领域：异常、取消、资源释放、长会话和恢复分别放在所属工作负载中，不重复建立独立目录。

## 案例格式

每个 cases.json 条目包含 id、objective、workload、environment、assertions、metrics、evidence、status。status 为 existing、planned 或 blocked。只有真实执行并保存结果后，才可在报告中记录 pass/fail。

## 执行边界

- XCTest 位于根 Tests，负责确定性断言。
- 本目录描述标准工作负载、环境和量化指标。
- Examples/Gallery 用于人工查看与视觉采集。
- Benchmarks/LanguageRuntime 是已有性能 runner，优先复用。
- 报告写入本地 outputs/benchmarks，不提交临时结果。
