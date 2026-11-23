# SDK 验证矩阵

文档版本：1.2 · 更新日期：2026-11-23

本目录维护 SwiftLang、SwiftOpenUI 与 SwiftIntelligentUI 的测试与验收计划，记录六个领域的固定输入、断言、观测指标和证据要求。当前共 18 条定义，复用已有 XCTest、Gallery 和性能工具；这些定义本身不是可执行 runner。

## 六个领域

| 领域 | 测试对象 | 主要结果 |
|---|---|---|
| [Runtime](Runtime/cases.json) | Parser、Evaluator、Store、Query、Schema、执行预算 | 语义正确性、状态一致性 |
| [Streaming](Streaming/cases.json) | 增量解析、readiness、发布、取消、换源 | 内容完整性、状态隔离、Push 分布 |
| [Components](Components/cases.json) | 两套组件库的注册、参数、默认值、交互、媒体和生命周期 | 契约与交互正确性 |
| [Layout](Layout/cases.json) | 两套库各自的布局容器、测量、组合、Dynamic Type、RTL | 几何断言、溢出与遮挡 |
| [Visual](Visual/cases.json) | DesignSystem、字体、颜色、间距、组件视觉、截图和人工审查 | 视觉回归与审查记录 |
| [Performance](Performance/cases.json) | 语言、流式、原生呈现、布局、滚动、CPU、内存 | P50/P95/Max 与资源曲线 |

Reliability 横跨六个领域：异常、取消、资源释放、长会话和恢复分别放在所属工作负载中，不重复建立独立目录。

## 产品覆盖

| 层次 / 产品 | 现有入口 | 验证职责 |
|---|---|---|
| 共享 SwiftLang 底座 | [SwiftLangTests](../../Tests/SwiftLangTests) | 语言、Store、Query、流式、状态与宿主生命周期 |
| OpenUI | [SwiftOpenUITests](../../Tests/SwiftOpenUITests) | 标准组件库的契约、呈现、交互与资源行为 |
| OpenIntelligentUI | [SwiftIntelligentUITests](../../Tests/SwiftIntelligentUITests) | 该库的组件、生成契约、布局、交互与固定历史程序 |
| Gallery 双库程序 | [Gallery](../../Examples/Gallery/README.md) | 遍历两库固定程序的完整与流式检查，并提供原生浏览和交互入口 |
| 共享层性能 | [Performance](../Performance/README.md) | 只依赖 SwiftLang，测量语言与公开 State 路径 |

两库的视觉回归分别维护；当前新增的整页 macOS 截图矩阵只覆盖 OpenIntelligentUI 的部分场景，OpenUI 使用自身的原生和视觉测试。两套 UI 的布局、滚动和真机资源成本另行采集。各条目的实际覆盖以 `evidence` 和对应执行日志为准；目录与配置说明覆盖范围，不表示全部设备、字体、主题和交互组合已经完成验收。

## 案例格式

每个 `cases.json` 条目包含 `id`、`objective`、`workload`、`environment`、`assertions`、`metrics`、`evidence`、`status`。`evidence` 中的仓库路径相对仓库根目录，其他条目说明需要采集的证据类型。

`status` 描述实现准备情况：`existing` 表示已有可复用的测试或工具，`planned` 表示仍需补齐执行或审查流程，`blocked` 表示有明确阻碍。`existing` 不等于本提交已经执行，也不表示该条目的全部指标已采集。只有真实执行并保存结果后，才可在验收记录中写入 pass/fail；未执行、未采集和待人工审查分别保留。

## 执行边界

- 根 [Tests](../../Tests) 中的 XCTest 负责确定性断言；用例实现继续归属对应产品，不复制第二套测试框架。
- [Gallery](../../Examples/Gallery/README.md) 用于原生查看、交互和截图采集；构图、主次、留白等视觉目标需要实际画面与人工审查，解析成功不能代替这些结果。
- [Performance](../Performance/README.md) 是已有语言与公开 State 流式性能验证工具；原生布局、滚动和真机资源成本需要单独测量。
- SDK 验收日志、截图和 trace 保存到忽略的 `outputs/verification`，性能结果保存到其下的 `performance/`，默认报告为 `outputs/verification/performance/language-runtime.json`。记录提交、输入、设备、OS、工具链和实际执行范围；性能对比另保留构建配置、参数、预热和样本量。
- SDK 的 spec、Prompt、生成示例与 reader/writer 契约继续通过对应产品的固定回归检查。[静态校验](../README.md) 使用调用方提供的匹配契约；[ContractExport](../../Tools/ContractExport/README.md) 仍专用于 OpenIntelligentUI。Gallery 可以导出两库的 reader JSON，该导出不等于静态校验文件入口要求的四文件契约包。固定程序回归不代表模型的生成成功率。
