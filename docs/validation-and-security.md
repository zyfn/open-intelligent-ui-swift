# 验证与依赖安全

文档版本：1.0 · 更新日期：2026-11-16

本文说明当前 SDK 的可复现输入、依赖安全和原生验收范围。具体提交的执行结果以 [Native SDK 流水线](../.github/workflows/native-sdk.yml) 的日志为准。当前生成输入由 [Tools/upstream.json](../Tools/upstream.json) 固定，完整上游许可保存在随 SDK 打包的 [THIRD-PARTY-NOTICES.txt](../Sources/SwiftLang/Resources/THIRD-PARTY-NOTICES.txt)。

## 1. 实际打包依赖与可复现生成

| 依赖 | 当前固定版本 | 修复与验证 |
|---|---|---|
| 官方语言核心 `@openuidev/lang-core` | `1.1.1` | 固定官方源码提交、原始/适配后源码树及实际 JavaScriptCore bundle；执行新版本语言行为与原生桥接回归 |
| Zod | `4.6.7` | 修复约束集合校验的内存耗尽问题；保留既有 schema 导出与原生 record 契约，重新生成语言 bundle、manifest 与 oracle 构建指纹 |
| KaTeX | `0.18.2` | 修复从原型继承信任选项的问题；更新标准富文本与 Intelligent UI 实际使用的公式资源 |

官方安全公告分别为 [GHSA-mrhx-c7xc-m3w5](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5) 和 [GHSA-238p-pmpm-9mq7](https://github.com/advisories/GHSA-238p-pmpm-9mq7)。后一个问题依赖于已有原型污染；修复后的依赖不再把继承的选项视为应用主动启用信任。

Zod 与 KaTeX 更新使用 npm 提供的真实 tarball 与 integrity，锁文件固定构建图。标准富文本中直接和传递的 KaTeX 使用相同的精确版本。Intelligent UI 的 MathML 引擎也由受审计的生成工具维护，避免只更新 npm 依赖而遗留旧的运行时文件。

当前 SDK 的语言上游升级为 `@openuidev/lang-core` 1.1.1，固定官方源码提交 `39a4e3f6493673fdf2de04681240374c8d6f6be8`。构建从该版本源码生成随 SDK 打包的 JavaScriptCore 资源，并记录 Apple 平台桥接、兼容补丁与执行预算；客户端不运行时下载脚本，也不自动跟随 `latest`。实际提交、源码树与资源哈希以 [upstream.json](../Tools/upstream.json) 和 [core-manifest.json](../Sources/SwiftLang/Resources/core-manifest.json) 为准。

语言升级的回归需要覆盖新上游的表达式状态、列表/数学函数、查询依赖与重试、流式解析及动作/序列化行为。与官方版本同步产生的语义变化应有对应的上游依据和专门用例，不能仅更新 fixture 来掩盖原生桥接差异。组件目录和设计系统的变更独立于语言版本；原生契约检查仍对照固定的历史 Intelligent UI 基线，完整比较组件顺序、位置参数和 schema。

Zod 4.6.7 的 JSON Schema 导出新增了把纯标量 `anyOf` 合并成 `type` 数组的优化。两种写法表达相同类型集合，但本 SDK 保留既有导出契约，因此在现有构建兼容层中仅禁用该导出压缩步骤。共享适配同时用于原生 bundle 和官方组件目录生成，严格校验 Zod 版本、源文件 SHA-256、唯一匹配的替换片段及变换后 SHA-256；清单中的 `dependencyTransforms` 记录这些证据。Zod 的解析、校验和修复后的集合限制不受此导出适配影响。

Zod 的 JSON Schema 导入也把简单字符串键 record 包装为带校验的 pipe，固定 Lang 核心无法由该表示还原历史 record 签名。现有 authoring 桥接只对没有显式字段、patternProperties、属性数量或键名约束的简单 record 恢复新版 `z.record` 表示，并保留原来的字符串键检查、元数据、默认值和绑定身份。带额外约束的对象继续使用完整的新版 guard.pipe，保留预解析检查。

组件目录继续与原已提交文件逐字一致，不刷新 schema 期望来接受漂移。回归直接执行实际打包的 `nativeAuthoring`，比较全部 84 个组件、304 个参数和完整签名，覆盖联合分支顺序、nullable、类型数组输入、默认值、约束、嵌套、参数顺序及历史 parser 结果。另通过真实桥接的 `props.safeParse` 执行对象大小、键名、固定字段、额外属性类型和 patternProperties 的正反校验，验证安全检查实际生效。

标准富文本生成器继续嵌入字体，运行时不加载外部 CSS 或字体。Intelligent UI 继续输出 MathML，保留原来的 `trust: false`、严格语法、展开次数和输出大小限制。公式安全回归在隔离的 JavaScript 上下文中验证原型污染不能开启受信任渲染，并覆盖有效公式与非法输入。

当前资源版本与内容哈希由各资源 manifest 记录。生成器运行后，CI 要求资源与当前提交逐字一致；它不再要求后续安全修复继续等于原始导入的旧哈希。

## 2. 验收范围

流水线按当前 SDK 分成三项检查：可复现输入、依赖安全和原生验收。可复现输入检查重建实际打包资源并运行语言、authoring 和组件目录回归；安全审计覆盖 Core、标准富文本、代码高亮、图标和 Intelligent 函数五个生成工具依赖图，使用 `--audit-level=high` 门槛。原生验收构建并测试根 SDK 及其公开产品消费者。

原生验收覆盖 SwiftLang、OpenUI、OpenIntelligentUI 三个独立产品消费者。每个外部包只声明一个产品，验证打包资源、authoring、解析、流式、生成契约、原生宿主和状态读写；不启动窗口，不能代替 UI 视觉验收。模块检查禁止适配层导入两套组件库、任一 UI 导入另一套库；适配层内部 Language 目录不导入 UI 框架，Runtime 目录承接 SwiftUI。

其余原生验收覆盖全部原生测试、Release fitting、独立 Gallery 测试与双库案例完整/流式验证、完整历史契约、语言 ASan、独立契约/性能工具及 iOS 编译。独立检查在前一个检查失败后仍可收集证据，但任何检查失败都会保留为任务失败。消费者源码生成或语法检查不等于实际 Swift 编译通过；原生编译与测试结果以对应提交的执行日志为准。

这些记录用于验证当前分支的实现与构建；真机交互、产品发布和合并仍是独立的交付动作。

## 3. 语言版本与验证边界

包、目录与职责只见[架构](architecture.md)。当前运行官方 lang-core 1.1.1；docs/language 的 1.0 规范与 Fixtures/Language/1.0 是保留的参考输入，不是另一条运行路径。模型输入使用所选库当前导出的 Prompt/spec。

| 相对 1.0 参考的差异 | 1.1.1 行为 |
| --- | --- |
| Query 依赖 | 跟踪普通语句和别名中的状态/查询依赖，等待上游查询结果后再执行 |
| Query 失败与环 | 相同输入不自动重试失败；显式 Run 或失效操作可重试；依赖环报告 query-cycle，不派发工具 |
| 状态默认值 | 可由表达式计算初值；初始化后不因被引用状态改变而自动成为派生公式 |
| 数学函数 | Round、Abs、Floor、Ceil 也支持逐元素处理数组 |
| 诊断 | source 可以缺省，Swift 保留其真实存在性，不补造 parser 来源 |

当前 306 例参考由固定的未修改官方源码独立生成，保留原始输入与案例 ID。与旧参考的 33 个输出差异有独立记录；旧文件只用于审计，不作为备用运行实现。严格检查必须比较协议字段、顺序和诊断可选字段，不得通过排序、丢弃错误或覆写历史预期消除差异。

语言与资源修改在 SDK 根目录执行：

~~~sh
npm ci --prefix Tools/Core --ignore-scripts
node Tools/Core/build.mjs
node Tools/Core/verify-compatibility.mjs
node --test Tools/Core/native-*.test.mjs
swift test
~~~

离线构建可用 OPENUI_UPSTREAM_GIT 指向预取仓库；仍校验固定提交和源码树，不信任任意本地修改。生成 JS、manifest 与适配清单必须同源。对照器独立构建未应用 Swift patch/readiness 注入的官方内核，并执行官方 React 动作回调。对照覆盖完整/截断/中间流式快照、动作与工具结果、Query 替换与晚到结果、1.1.1 专项及 serializer round-trip；Swift 测试另外覆盖真实 native callbacks 和文档生命周期。生成 fixture 不能代替运行这些检查。

readiness 通过 parser-owned Symbols 和 evaluated-value WeakMaps 记录源边界与依赖；这些元数据不进入 Lang 值和序列化 AST。仅具名的原生元数据可在官方协议比较中排除。必须用原生交互测试验证完整控件可用、未完成动作不可执行、文档替换后旧回调失效。

未闭合 `Each` 的 readiness 失效标记按对象身份去重，防止同一共享数组在最终输出预算检查前被反复扫描。这一步只减少幂等标记的重复工作，输出预算仍按每次出现累计，不改变值、引用身份、控件就绪规则和超限拒绝。对应回归对实际数组访问次数计数：500 个结果共享同一个 500 项数组时，失效遍历由 250,000 次子项访问降至 500 次，两种情况下最终输出仍被原预算拒绝。

2026-11-16 本轮该修正已通过正式资源重建、33 项 native JavaScript 回归和独立官方内核对照（无未解释差异）；另外 480 组普通分块、24 组封包分块的终态值/声明/公开 meta/预算结果一致。这些结果不覆盖所有中间帧，也不能替代 Swift 桥接、原生交互和设备帧率验收；对应证据保存在忽略的 `outputs/audit-lang-2ae6ced/`。

原生数据桥接使用私有对象身份区分真实 ActionPlan 与含 `steps` 字段的业务对象。静态和动态业务对象保留其字段；宿主显式构造的原生 plan 可直接用作 action prop，显式 `Action(...)` 组合仍保留官方 `ownSteps` 对自定义动作的来源检查。此数据修复、表单校验器仅查自身键的修复以及下列预算均列在适配清单中，不通过修改历史 fixture 隐藏与固定官方核心的边缘差异。单键 Store 读取仅检查该键并读取其值，保留键不存在与显式 `undefined` 的区别。

完整消息的 `push`、`set` 和批量解析使用同一官方消息提取规则；重试帧选择最后一个 content。普通 Lang 分块保留增量路径，协议标记跨分块时由原生输入适配保留边界，不引入另一份语言 parser。替换 Mutation 时，原生 Task 与等待中的 Promise 按声明实例一起取消；即使宿主 provider 忽略取消，等待动作也能结束，其他 Query 不受该局部取消影响。

serializer 修复后的程序须由未修改的官方 parser 接受，并保留求值意义；不能将其输出拼写变化描述为逐字等价。standalone patch 必须与实际构建变换一致。

| 原生预算 | 边界及超限结果 |
| --- | --- |
| 源码 | 1,048,576 UTF-16 units；100,000 tokens；4,096 statements；单表达式 128 层嵌套或 256 个运算符；超限为 parse-exception，最后有效前缀只读 |
| Materialization | 256 层 / 100,000 工作单位；整批状态默认值共用余额，超限为 parse-exception，并在投影状态默认值和根节点前将私有失败标记传给 Swift |
| 动态求值 | 每个同步求值范围 100,000 工作单位、256 层；涵盖递归求值、Each 展开和内建函数工作量；Query 批次共用余额，超限立即停止 |
| 输出与渲染 | 展开后的值最多 100,000 节点、256 层、4,096 个组件实例及 1,048,576 UTF-16 units；共享子树每次出现都累计成本，以缓存和饱和计数避免检查本身指数展开 |
| 有序 JSON 解码 | 128 层；超限为原生 JSON 错误，JSON 语法仍由 JavaScriptCore 校验 |
| 正则 | 65,536 pattern units、1,048,576 input units，限制内存、栈与 VM；资源耗尽阻止表单提交，普通不匹配与非法表达式保持各自语义 |
| 原生值转换 | 保留 256 层防御检查；更深传输不在已验证的等价范围内 |

预算之外不宣称与 stock core 等价。有限 fixtures 通过也不证明任意程序、后续版本、所有设备或网络时序正确。新差异必须解释或修复，再决定是否有依据增加新的版本预期。

真实流式性能与重复拟合分开验收。当前 `OpenUIState` 在 MainActor 上同步执行每次 push 的解析、根求值和 live-element 索引；公共 host 与组件 host 订阅同一个状态。`RuntimeHostIsolationTests` 与 `HostSizingIsolationTests` 中重复提交相同源码和尺寸拟合的检查，只证明该路径不重复解析、发布或重挂，不能证明真实尾部增量不会刷新无关组件。局部刷新与每帧耗时需要在目标设备的 Release 构建中，另测不同内容规模和分块频率下的解析、桥接、求值、组件 body 与布局成本；没有运行证据时不宣称该观察路径已经收敛。

任一物化、求值或输出预算失败后，OpenUIState 保留最近一次通过预算的已显示内容，停止当前文档的动作、Query 和 Mutation；不能把失败产生的 `null` 继续写入状态或作为工具参数。替换源码或 reset 可以恢复。预算用于限制异常工作量，并非每帧耗时或设备帧率保证；原生不卡顿仍需在目标设备 Release 构建上测量。

原生控件验收还包括：EditableTable 的本地提交不得代表远程持久化；被拒绝的草稿不能随 Store 发布而提交；替换文档建立新草稿生命周期。Slider 的离散选择同时考虑 minimum 和 step 精度，非整除范围允许拖到最大值，连续文本仍按范围校验。对应控件测试与真实窗口检查各自报告。
