# 验证与依赖安全

文档版本：1.9 · 更新日期：2026-11-16

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

readiness 通过 parser-owned Symbols、基础 WeakMaps、单次求值的 snapshot WeakMaps 和 Each 输出位置的私有 scope 记录源边界和依赖；这些元数据不进入 Lang 值和序列化 AST。共享原生容器的临时未就绪标记和 Query 归属不能污染另一次求值，也不能污染同一次求值中直接复用该值的兄弟位置。Swift 投影按 JS 值身份与 scope 缓存，必要时重建带元数据的不可变路径，并保留原 JS 身份、SameValue 与反向编码关系。Action 的 opaque capture 保持业务值身份，不继承展示位置的 pending 约束。仅具名的原生元数据可在官方协议比较中排除。必须用原生交互测试验证完整控件可用、未完成动作不可执行、文档替换后旧回调失效。

未闭合 `Each` 的失效约束现在随输出位置传递，不再遍历共享后代写入 metadata；模板求值本身的写入也留在该 Each 的局部 snapshot。Core 已有的 prop-array 映射携带这一约束，不为附加 metadata 无差别复制 Lang 值。输出预算仍按每次出现累计。对应回归直接计数数组访问：500 个结果共享同一个 500 项数组时，readiness 失效遍历为 0 次，最终展开输出仍被原预算拒绝。这个计数只证明该遍历被移除，不是设备性能测量。

早期修正曾执行 33 项 native JavaScript 回归、独立官方内核对照，以及 480 组普通分块、24 组封包分块的终态比较；历史证据保存在忽略的 `outputs/audit-lang-2ae6ced/`。本轮生成资源的执行计数以第 4 节为准。JS 结果不覆盖所有中间帧，也不能替代 Swift 桥接、原生交互和设备帧率验收。

原生数据桥接使用私有对象身份区分真实 ActionPlan 与含 `steps` 字段的业务对象。静态和动态业务对象保留其字段；宿主显式构造的原生 plan 可直接用作 action prop，显式 `Action(...)` 组合仍保留官方 `ownSteps` 对自定义动作的来源检查。此数据修复、表单校验器仅查自身键的修复以及下列预算均列在适配清单中，不通过修改历史 fixture 隐藏与固定官方核心的边缘差异。单键 Store 读取仅检查该键并读取其值，保留键不存在与显式 `undefined` 的区别。

完整消息的 `push`、`set` 和批量解析使用同一官方消息提取规则；重试帧选择最后一个 content。普通 Lang 分块保留增量路径，协议标记跨分块时由原生输入适配保留边界，不引入另一份语言 parser。替换 Mutation 时，原生 Task 与等待中的 Promise 按声明实例一起取消；即使宿主 provider 忽略取消，等待动作也能结束，其他 Query 不受该局部取消影响。

serializer 修复后的程序须由未修改的官方 parser 接受，并保留求值意义；不能将其输出拼写变化描述为逐字等价。standalone patch 必须与实际构建变换一致。

| 原生预算 | 边界及超限结果 |
| --- | --- |
| 源码 | 1,048,576 UTF-16 units；100,000 tokens；4,096 statements；单表达式 128 层嵌套或 256 个运算符；超限为 parse-exception，最后有效前缀只读 |
| Materialization | 256 层 / 100,000 工作单位；整批状态默认值共用余额，超限为 parse-exception，并在投影状态默认值和根节点前将私有失败标记传给 Swift |
| 动态求值 | 每个同步求值范围 100,000 工作单位、256 层；涵盖递归求值、Each 展开和内建函数工作量；Query 批次共用余额，超限立即停止 |
| 整条 Action | 一次计划累计 100,000 工作单位，覆盖步骤、原生输入/输出、表达式、逐步 root 更新与同步 Query 工作；私有 JS 入口接收剩余额度，嵌套求值不重置或重复消费同一 JS 工作量。超限停止剩余步骤；已完成步骤的 Store 可见性和回调顺序保留 |
| 输出与渲染 | 展开后的值最多 100,000 节点、256 层、4,096 个组件实例及 1,048,576 UTF-16 units；共享子树每次出现都累计成本，以缓存和饱和计数避免检查本身指数展开 |
| Store 写入与初始化 | 对提交后的整份状态统一检查上述图预算，增量写入用字段成本账本计算替换后的总量；initialize 在编码和提交前检查输入与最终候选，拒绝时保留原状态，不留下部分初始化 |
| 有序 JSON 解码 | 128 层；超限为原生 JSON 错误，JSON 语法仍由 JavaScriptCore 校验 |
| 正则 | 65,536 pattern units、1,048,576 input units，限制内存、栈与 VM；资源耗尽阻止表单提交，普通不匹配与非法表达式保持各自语义 |
| 原生值转换 | 保留 256 层防御检查；更深传输不在已验证的等价范围内 |

预算之外不宣称与 stock core 等价。有限 fixtures 通过也不证明任意程序、后续版本、所有设备或网络时序正确。新差异必须解释或修复，再决定是否有依据增加新的版本预期。

真实流式性能与重复拟合分开验收。当前 `OpenUIState` 在 MainActor 上同步执行每次 push 的解析、根求值和 live-element 索引；公共 host 与组件 host 订阅同一个状态。`RuntimeHostIsolationTests` 与 `HostSizingIsolationTests` 中重复提交相同源码和尺寸拟合的检查，只证明该路径不重复解析、发布或重挂，不能证明真实尾部增量不会刷新无关组件。局部刷新与每帧耗时需要在目标设备的 Release 构建中，另测不同内容规模和分块频率下的解析、桥接、求值、组件 body 与布局成本；没有运行证据时不宣称该观察路径已经收敛。

任一物化、求值或输出预算失败后，OpenUIState 保留最近一次通过预算的已显示内容，停止当前文档的动作、Query 和 Mutation；不能把失败产生的 `null` 继续写入状态或作为工具参数。替换源码或 reset 可以恢复。预算用于限制异常工作量，并非每帧耗时或设备帧率保证；原生不卡顿仍需在目标设备 Release 构建上测量。

原生控件验收还包括：EditableTable 的本地提交不得代表远程持久化；被拒绝的草稿不能随 Store 发布而提交；替换文档建立新草稿生命周期。Slider 的离散选择同时考虑 minimum 和 step 精度，非整除范围允许拖到最大值，连续文本仍按范围校验。对应控件测试与真实窗口检查各自报告。

## 4. 内核稳定性审查与当前验收状态

本节保留各轮修复的执行证据。早期以 `9e05d888ef31cfff6eb8c75f3ca01ed089ec3e78` 为基线完成下表修复，经 `bdac1bfd03bf19df527681517b2f3c3aee19a368` 合入 main，随后继续处理原生执行及文本同步；`c7310054e5a58ecb7e42e9f37e4c77e7fed30ce7` 是后续客户端审查的历史基线，不是本节所记录的最新修复。

最近一轮内核修复提交为 [`1063d9f2`](https://github.com/zyfn/open-intelligent-ui-swift/commit/1063d9f21466ffa9da2d53f1bb8e33ef1c3af4bd)，已通过 [`a4808be3`](https://github.com/zyfn/open-intelligent-ui-swift/commit/a4808be333598bb15a6990f47eeb0d23c930c1dd) 与同期 main 合并。当前状态是修复已合入、JS 回归通过、原生验收未完成；尚无该版本的 Apple Release / App CPU 对照，不能宣称高 CPU 已解决。具体执行结果见本节“当前内核修复与验证”，剩余工作见[性能证据与未完成项](#性能证据与未完成项)。设计约束见[架构](architecture.md#内核必须保持的约束)，依赖版本及兼容性检查仍按第 3 节记录。组件视觉由独立任务负责。

| 问题 | 触发与依据 | 前轮处理及验证层级 |
| --- | --- | --- |
| 隐式转换逃逸工作量预算 | 约 6 KB 程序用共享数组做 `==` 或动作字符串参数，最终值很小但中间发生大规模遍历；500 项探针实际读取 250,500 次，旧预算仅报告 1,506 工作单位 | 转换前测量并累计成本，覆盖比较、索引、拼接、动作及 Filter/Sort 内重复转换；新增回归中 8 项在旧资源失败，修复后通过；1,053 个小输入与独立官方核心对照无差异 |
| readiness 跨文档污染与容器缓存过期 | 不完整 Each 在共享对象上留下未就绪/Query 标记；完整文档仍读到旧标记，而 Swift 命中父容器缓存又可能跳过后代变化 | 改为单次求值 snapshot 与显式原生投影；保留旧快照和 JS 身份。3 项新 JS 回归旧资源全失败、修复后全通过；真实 Swift 缓存/交互回归已加入，待原生运行 |
| 原生对象字段整理为平方级 | 每插入一个键线性扫描已存在字段，10,000 个不同字段固定发生 49,995,000 次键比较；这在 JS 求值预算之外 | 以精确 UTF-16 哈希键保存首次位置/最后值，整数键只解析一次后排序；新增顺序、重复键、Unicode、JS own-property 对照及宽对象回归，待原生运行 |
| 当前匿名节点重复搜索整个桶 | 不完整 Each 生成同类型、无 statementId 的控件，当前树的 1,000 个节点按旧逻辑需 1,000,000 次候选比较 | 当前对象身份 membership 直接返回，旧快照仍保留原有消歧；JS 输出及工作量计数可复现，原生快径与消歧回归待运行。旧快照的大桶搜索风险仍需测量 |
| 同步发布回调重入造成旧轮覆盖或重复通知 | `@Published` 在 willSet 同步调用订阅者；订阅者换源后旧 setter 和后续渠道仍可继续写入。onError 恢复也可能使外层再通知内层的解析结果 | 同步重入顺序执行、过期轮终止，并在执行排队的控件写入时再检查 revision；新增替换、同代状态写入、no-op 重放、连续命令和旧 Context 回归，待原生运行 |
| 异步 Query 返回后先派发再验根预算 | 现有依赖调度先从 rows 自动派发参数很小的下游工具，随后 root 的多层 Each 才超限；不能只检查 Query 参数 | 在原生自动派发进入 provider 前复检当前文档、完整性与呈现预算；增加原生时序回归，待运行。JS 探针证明调度次序，不冒称已执行 Swift Task race |
| 排队的旧 Query 仍可进入 provider | 等待 MainActor 检查期间 patch 改变或删除 Query，此前只在结果回来后判断旧 key；首次批次还可能在同步发布回调换源前开始调用 | 所有 Query 等待当前同步发布结束，已检查批次只复核存活状态，不再次算 root；进入 provider 前核对 Query 实例及请求 key，保留同 key 请求，拒绝删除后同名同 key 重建的旧请求。私有 hook 与原生时序回归分别验证 |
| 原生输入先编码后检查 | 工具返回值、纯函数返回、宿主状态/引用和原生 AST capture 可在进入 JS 预算之前递归编码；初始/恢复状态也可先进入 Store | 加入 Value、AST 与整批状态图预检，按共享子树每次出现累计成本，用 memo 和共享检查额度限制预检本身；上下文使用有限弱引用缓存避免重复扫描。失败中止当前 JS 预算、结束工具等待，并保留旧 Store/呈现，不能提交 `null` 或部分恢复。原生回归待运行 |

前轮正式生成资源执行过 **84/84** 项 `Tools/Core/native-*.test.mjs`，覆盖 26 个分块不变量案例的 **2,123 个中间前缀**及其末态；比较公开值、声明、诊断与私有 readiness。增量 push 与同前缀 fresh set 一致，这是分片不变量检查，不是独立官方 oracle。该轮独立官方检查执行 51 项 parser、5 项动作、4 项 Query、6 项 round-trip、21 项 Lang 1.1 专项，未发现未解释差异；额外 1,053 项隐式转换对照也无差异。6 项原生输入失败 JS 回归在旧资源均失败，修正后通过；5 项 Query 请求有效性回归覆盖变参、删除、保留、删除后重建与 dispose。历史 fixture 预期未修改；84 项是前轮计数，不是本轮最终结果。

前轮修复新增 54 项 XCTest，但本审查环境缺少 Swift/Xcode，`swift test` 曾实际返回 `swift: command not found`；完整 SwiftPM 模块图检查也受阻。已回读前轮合并提交的 [CI run 43809174570](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/43809174570)：reproducible-inputs 与 dependency-security 为 failure，runner 与 steps 为空；native-sdk 为 skipped。该记录既不是前轮原生通过证据，也不是本轮候选的 CI 结果。本轮 Swift/XCTest 同样未编译、未执行，Release 宿主测试和设备基准未运行。前轮日志保存在忽略的 `outputs/kernel-audit-9e05d88/`，不另建并行设计或审查文档。

### 已合入基线的前轮修复与验证

该轮已修改下列生产实现并补充回归，状态是“代码已实现，原生验收待执行”。客户端继续使用现有 `push`、`complete`、`interrupt` 及既有回调；没有新增流句柄、`beginStream` 或替代接入方式。公开 Lang 值、参数及业务回调顺序保留。裸 `push(String)` 本身没有请求来源信息；过滤已退休请求的迟到分块仍属于宿主现有请求生命周期管理，不能把这一限制包装成新的 SDK 用法。

| 该轮修复 | 实际处理 | 已执行证据与待验收范围 |
| --- | --- | --- |
| Store 总量与原子初始化 | `CoreStore` 在编码前检查写入后的整份状态，用字段成本账本计算替换后的总量；initialize 分别预检 defaults/persisted 输入并检查最终候选，确认后一次提交。失败保留旧值，合法后续写入可恢复，原 JS Store 仍持有业务值和通知 | 已补增量写入后的 snapshot 往返、替换、pristine/undefined 与失败不部分提交回归；Swift 未运行，不能声称真实 Store 往返已验收 |
| Action 调用方取消与 Mutation 等待退出 | 步骤前后及 await 返回后检查 `Task.isCancelled`；Mutation waiter 处理取消、完成、退休和 dispose 的竞争，并只恢复一次 continuation。取消对应请求后可重新操作，其他 Query/Mutation 不随之退休 | 已补已取消入口、等待中取消、忽略取消的 provider、迟到结果和后续步骤停止等原生回归；尚未执行。SDK 结束等待不代表可以抢占宿主 provider 的外部工作 |
| 整条 Action 的累计预算 | 一次计划共享工作额度，覆盖 plan/输入输出/步骤/事件、表达式、逐步 root 更新和同步 Query 工作。私有 JS bounded 入口接收剩余额度，嵌套沿用同一 scope，Swift 只在外层消费 JS work。完整步骤之后可让步，已有逐步 Store 可见性和回调次序保留 | JS 验证单独允许的两个 Query defaults 同批超限、剩余 1000 时在 1001 拒绝、嵌套不重置，以及同步 invalidation 通知内的求值计入额度；整条原生 action、取消/换源与 provider gate 尚待 XCTest。未实现多 Set 的 root 合并，也未宣称消除卡顿 |
| 公开底层入口的编码前预检 | 覆盖 `CoreStore.set/initialize`、被宿主改写后失去 parser snapshot 的 ParseResult、手工 Query AST 和 Mutation 声明/参数；在递归编码前拒绝深、宽或累计超限数据。OpenUIState 通过已有错误渠道退休执行，不能继续提交失败后的 null | 对应低层与高层原生回归已加入，未编译/执行；自定义 Store 与宿主函数返回前的自身计算仍由宿主负责 |
| 同次求值的共享 native graph readiness | Each 的模板求值和输出位置持有局部 scope；父子展示约束不再回写共享 Button/ActionPlan。Swift 按值身份与 scope 投影，保留旧快照、SameValue、重复子图复用和 opaque capture | 共享 getState/native function、两种兄弟顺序、Each 闭合恢复、query scope 隔离的 JS 回归通过；bridge 与实际 `canInteract` 回归已加但未运行。纯 Lang Button/Action 别名负对照没有复现旧问题，不能泛化为所有变量复用错误 |
| complete 父节点的旧 Action metadata | `ComponentHost` 与 `isElementReady` 按当前 projection membership 刷新旧父快照；不再因父节点自身 complete 而跳过内部 Action 更新。语义匹配存在不同 readiness 候选时继续保守处理 | 已补同一文档中保留旧 Context、依赖完成后恢复交互的回归，原生待运行；不依赖重挂载来修正旧快照 |
| Stack/Card 的扩展组件身份 | 标准容器将实际 `context.registry` 传给 children/identity 解析，使扩展组件的 `identityFields` 生效 | 已补真正挂入 Stack/Card 的重排与身份回归，原生待运行；不将 helper 单测视为 mounted 通过 |
| Query 通知的内部投递合并 | 每个订阅至多保留一个等待 MainActor 执行的更新任务，执行时读取最新 manager snapshot；退休订阅使排队更新失效。Query 调度、工具完成和对外业务回调仍由原路径负责 | 已补队列与 State 发布回归，原生待运行；只合并该内部呈现投递，不改同步 push 契约，也不保证不同时间到达的所有通知只产生一次 root 更新 |
| Gallery 预览挂载与持有范围 | 预览 pager 只挂载当前页及相邻各一页，缩略条使用 LazyHStack，离屏缩略图释放本地 phase；移除父层持有全图库图片的字典，页面持有随挂载窗口变化 | 已补窗口、请求与资源回归；实际 mounted 请求数、关闭释放和内存峰值均待原生测量。共享缓存上限仍不能代表整个 App 的图片内存上限 |
| OpenUI 大图像素升级 | 内联图可作为打开预览的初始像素，按 viewport、scale、zoom 与宿主 cap 请求后续尺寸；保留更高像素结果，尺寸升级期间可继续显示已接受图像，并验证资源/授权/重试归属 | 高清升级、低清先到/高清后到与资源变化回归已加入；尚无原生像素、清晰度或请求测量结果 |
| IntelligentUI 预览签名快照 | 稳定 source/owner/retry 沿用解析后的 request snapshot；以宿主 cap 后的有效像素决定尺寸档，避免等效尺寸因重复签名产生不同请求 | nonce 签名及 cap 回归已加入，尚未运行；不能以源码变化关闭用户报告的三项 signed media 失败 |
| 同源远程 SVG 重试 | 可重试的网络/内容失败显示重试操作，增加 attempt 并重新请求同一 source；保留 readiness、授权和目标存活检查，无效请求不绕过既有校验 | 首次失败、同节点重试恢复的原生回归已加入，未执行；此修复与用户 SVG 拖动像素失败属于不同验收 |

最终生成资源已执行 **96/96** 项 `node --test Tools/Core/native-*.test.mjs`，**0 failed、0 skipped**。其中包含该轮 49 项定向集合；49 是全量的子集，不能相加。独立 `verify-compatibility` 另执行 **51 parser、5 action、4 Query、6 serializer round-trip、21 Lang 1.1**，`unexplainedDifferences=0`。对照使用未应用原生补丁的固定官方源码；没有修改历史业务 fixture 来接受漂移。日志位于忽略的 `outputs/kernel-repair-native-tests.log` 与 `outputs/kernel-repair-compatibility.log`。

| 其他该轮检查 | 结果与边界 |
| --- | --- |
| Validation 与 catalog compatibility | 13/13 PASS，0 failed、0 skipped；覆盖契约、输入验证及目录兼容性。日志为 `outputs/kernel-repair-contract-tests.log`，不代表原生界面通过 |
| 源码与所有权检查 | PASS；确认源码职责/归属约束，属于静态检查，不是 Swift 编译或并发时序测试 |
| Gallery 目录完整性检查 | PASS；确认目录完整性，不代表 Gallery 的窗口、拖动、图片升级或内存已通过原生验收 |
| 本地化与文档链接 | PASS；检查既有资源键、调用位置与修改文档的本地链接 |
| 该轮 GitHub Actions 原生流水线 | BLOCKED；已对代码提交 `5f4ed69b0eb7815e07704fc36f12449c6caa4db9` 的新分支手动触发 [run 43815639524](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/43815639524)。两个前置任务的 runner/steps 均为空，页面明确提示账户付款或支出限额阻止启动；`native-sdk` 为 skipped，未进入 Swift 编译/XCTest，不能视为源码测试失败或通过 |

该轮 `lang-core.js` SHA-256 为 `ebabf51a466bc64aa250579397ffa635332ac8153d0867b28f26fb6528b293a8`，`core-manifest.json` SHA-256 为 `4cd06294b0bd03e903848cf1d9bcc62407f2751fd5e3adfbf2813468376f1fb8`。bundle、manifest 与适配清单由固定输入重新生成。预算新增参数和 readiness scope 仅存在于私有 SwiftCore bridge，不要求客户端采用新的 Lang 语法、公开参数或调用方式。

**该轮全部 Swift/XCTest 均未编译、未执行，所有媒体原生测试待验收。** 新增 `MountedStreamingTextProgressTests` 挂载真实 NSHostingView/OpenUIContentView，先显示半句 plain heading 与 Markdown，补全字段后继续用现有 push 追加无关节点约三秒，并从 AppKit accessibility 控件断言 done 前已出现完整文本。这只是已写入的回归，不是本环境的运行结果，更不是 Muse 回放、像素或 FPS 验收。旧 Slider 的 `testDraftFeedbackRefreshDoesNotFlushWritesOrRequestFocus` 已迁入现有测试文件，同样待执行。

### 原生文本流中停滞

2026-11-16 依据客户端提供的调试记录继续检查原有 `fix/kernel-stability-20261116` 分支（修正前为 `2a0201b`，文本代码与 `bdac1bf` 一致）：`source` 已是 `SHANGHAI → SUZHOU · 2 DAYS`，而 `NativeStreamingTextBuffer.received/displayed` 仍为 `SHANGHAI → SUZH`。记录来自客户端，本次未重新运行该 App 或原始回放。

确定的源码缺陷位于 `NativeMarkdownText`：单参数 `onChange(of:perform:)` 忽略传入的新值，改读闭包捕获的旧 `text`。该 API 的[闭包语义](https://developer.apple.com/documentation/swiftui/view/onchange(of:perform:))使 A → AB 的更新再次交付 A；若该字段不再变化，即使其它节点继续生成，也不会补交 AB，直到停止流式时才绕过旧显示值。这条路径与记录相符；单次断点本身不足以证明全部实际时序。

修正将文字的精确 UTF-16 值与流式状态组成私有输入，并由一个变化回调消费新参数，避免同帧变化时两个回调混用新旧值。保留 iOS 16 / macOS 13 支持、48ms 呈现合并、只读尺寸拟合和现有 Markdown 工作队列；不修改 parser、公共状态入口或客户端调用方式。

`MountedStreamingTextProgressTests` 在既有挂载回归上扩展为 4 项 XCTest、6 个场景，使用实际挂载的文本和标准 `OpenUIState.push` 路径，覆盖目标字段完成后其它节点继续生成、文字与流式状态同帧变化，以及最终分片紧接 `complete` / `interrupt`。验收必须确认缓冲和 Markdown 准备都收到完整文字、界面在 `complete` 之前更新；一次性输入完整程序或仅在流结束后检查正确文字不能替代该项。既有 `StreamingTextPresentationTests` 的无副作用读取和合并约束保留。

本次源码/所有权检查与 `git diff --check` 通过；`swift test` 实际因环境找不到 `swift` 返回 127，原生 XCTest 与客户端分块回放尚未执行，不能将源码修正称为 App 验收通过。执行结果与环境阻塞记录在忽略的 `outputs/verification/native-text-sync/`，不另建并行报告。

### 当前内核修复与验证

前轮内核修复已通过 `3310e3d8` 合入当时最新 main，并保留同期 UI 改动。本轮继续修复客户端 `c7310054` 定向审查中的问题：生产改动限于 SwiftLang 语言/运行时及 Core 适配，未修改组件库视觉、历史 fixture、`push / complete / interrupt` 或业务回调协议。本轮新增 19 个 XCTest 方法，前轮 29 个与这些新增项均仍待 Apple 环境编译运行。

| 问题 | 实际修复及回归边界 |
| --- | --- |
| 旧 Query 结果污染同名同 key 的新请求 | 以已有 cache entry 身份及当前消费者判定有效性；success、error、finally 和原生 provider 入口/返回统一遵守。受控 Promise 回归在旧 `c7310054` 资源中复现旧失败清掉新 loading、带入旧 error 等问题；修复后通过 |
| 共享请求状态与缓存恢复不一致 | 原声明移除或改参后，其他消费者仍接收有效共享结果；loading、refetching、错误与旧缓存引用一起更新。成功缓存命中也清理旧错误；多消费者 invalidate 只形成一个待刷新请求，dispose 自身生成停止加载的末态快照。清理统一在完整节点批次之后决定，保留同批接手和有效 fallback，移除连续改参后无消费者的旧缓存 |
| 旧请求长期不返回时持续积压 | 声明完整评估以及工具结果触发的 reader 重算结束后，整批移除已经失效的原生 pending，先 reject 全部旧 Promise，再向 Task 发取消，避免同步取消处理器重新消费未退休的旧条目；不在节点更新中途通知时清理。新增连续改参/删除、共享消费者、跨 ID key 交换、自动 reader 更新及双请求取消重入 5 项回归；原生未运行。库不能强制停止 provider 自身不响应取消的工作 |
| 旧超大结果或错误停止新文档 | Swift 返回阶段先复核请求，再扫描 Value、读取 Error 描述或编码。旧结果直接结束原 Promise；当前请求仍受完整预算约束。新增改参、删除再建立、共享消费者和旧错误描述零读取回归；原生未运行 |
| 错误负载和 MCP 提取绕过预算 | MCP 文本、普通 Error 描述、ToolNotFound 名称及名单在 JS 分配前检查总量；MCP 原始 JSON 先预检，文本展开后再验图预算。沿用既有错误渠道，正常错误类型/文本不变，Mutation 等待者能结束。当前超限及普通错误的原生回归未运行；MCP 展开拒绝在 JS 中已执行 |
| 合法深度边界静默截断 | 256 层容器后的标量在 JS 预算内，原 Swift guard 却先返回 null。现在先解标量，再限制继续展开的容器；新增 256 层 number/bool/string/null 保值与 257 层拒绝回归。JS 接受边界已验证，Swift 保值回归未运行 |
| 同代已移除组件的旧写入与动作 | revision 不变时也必须属于当前 live tree；绑定、字段及初始化在实际排队执行时复核目标。保留 partial 呈现开关、公开 Host 写入、相同 props 的最新 readiness 和有效动作自移除后的后续步骤；对应 7 项原生回归待运行 |
| 直接绑定往返后改变内部类型 | ReactiveAssign 缓存命中使用与首次解码相同的分类；直接 `$value` 仍为 binding，真实表达式仍为 reactiveBinding。新增首次/缓存及 Store 往返的类型、值和身份回归，原生未运行 |
| 取消任务中的 legacy 动作仍派发 | triggerAction 的公共执行入口检查 Task 取消，覆盖 legacy、plan 和默认动作；取消后的外部事件不能继续发送，正常动作不变，原生回归未运行 |
| Lang 解析重复投影未使用的消息 context | Parser 和 StreamParser 只读取共享消息解析器选中的 content，避免逐块创建无用 Swift JSONValue。公开 parseMessage 保留完整 context；新增桥接枚举计数回归，原生未运行。未改消息协议，也未移除 JS 对 context 的解析 |
| 普通 Lang 注释/字符串被误认成帧 | batch/set/push 共用增量 UTF-16 边界探测，首次真实帧前的引号、转义及行注释受保护；同一个消息算法继续处理真实封包与重试。新增 5 项实际 bundle 回归通过，4 项 Swift 回归待运行。原始 raw marker fixture 保留，纠正了用协议选帧器吞掉 raw 字符串再作为预期的旧 oracle；framed oracle 不变 |
| applyPatch 原始输入与合并成本无上限 | 原始 existing/patch/rootId 在合并前各自检查，合并共用累计 work 及输出预算；原始 2,097,169 UTF-16 patch 从接受 after 改为 `limitExceeded=true,value=null,work=0`。底层 mergeStatements 原位 throws，不保留静默兼容入口；applyPatch 保留原签名、最后有效 root/Store 与恢复行为。8 项 merge/split JS 回归通过，9 项新增 Swift 回归待运行 |
| 平铺大程序逐分片重扫整份源码 | 使用解析器已产生的 tokens 和 completed 声明计数，在递归前检查原有限额。旧全前缀预检已删除；重复 ID、pending 重读、fence/reset、精确 token 上限及恢复有回归。新增 5 项 source-budget JS 回归通过，相关 Swift 项待运行 |
| 多行三元式换行扫描为平方级 | 同次 split 复用下一非换行位置；2000 换行的 token 索引读取从 2,007,023 降到 10,022，结果仍是同一合法表达式。线性访问上界及两个独立上游语义对照通过 |
| 稳定 readiness 重复分配与跨桥属性读取 | 只共享冻结、无依赖的 open/closed 描述，Swift 直接识别；含 Query、observed、scope、slots、placeholder 的元数据仍完整投影。移除重复 identity 桥接调用并缓存只读 exports。4 项 JS 计数/语义回归通过；没有跨 push 缓存可能变化的 Lang 物化对象 |
| 一次普通 push 两次整 State 通知 | presentationRoot 随 root 同次发布，保留公开 `$root`；尾部文字即时更新及 delimiter-only readiness 均有新增原生回归。两个 Swift 测试尚未执行，不能把源码次数推导当原生计数；共享 ComponentHost 订阅仍存在 |
| 原生测试目标 String/OpenUIString 错误 | ActionWorkBudgetTests 的多字段 formState 显式构造 OpenUIString，保留全部事件/预算断言。源码类型修正已完成，原生 target 是否还有其他编译问题仍须 Swift 构建确认 |

本次实际执行结果：

| 检查 | 结果与限制 |
| --- | --- |
| 正式 Core 生成 | PASS；固定上游、锁文件及生成器生成 bundle/manifest，新增适配来源同步。对最终正式资源重新运行全套 JS 回归 |
| Core 全套 JS 回归 | **141/141 PASS，0 failed、0 skipped**；包含前轮 119 项与本轮 22 项，子集数字不相加。覆盖 Query、MCP、真实分片、预算、readiness、原始消息边界与 merge |
| 旧资源反证 | 旧 `c7310054` 的 Query 定向 **5 pass / 10 fail**；MCP 原 5 项 **1 pass / 4 fail**。相同用例在修复资源均通过。追加缓存清理回归在本轮前一候选 `39df813e…` 上为 22 项中的 4 项失败，最终资源已通过；新增合法深度对照不是旧失败案例 |
| 独立兼容性 | PASS：51 parser、5 action、4 Query、6 serializer round-trip、21 Lang 1.1，另有 2 个独立 split/merge 对照，`unexplainedDifferences=0`。固定对照源码与历史 fixture 预期未改 |
| 源码/所有权与 diff | `check_openui_integration.py` 和 `git diff --check` PASS；仅说明静态范围和格式 |
| Swift 与完整模块图 | BLOCKED；本机 `swift test` 返回 127（找不到 swift），`check_module_boundaries.py` 同样无法取得 SwiftPM 模块图。新增/既有 XCTest 均未在本次运行 |
| GitHub 原生门禁 | 合并版本 `a4808be3` 的 [run 43830544843](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/43830544843) 两个前置任务均失败且 steps 为空，native-sdk 为 skipped；未进入原生构建，不能当测试通过。本条只记录该版本的实际结果，不将其他历史流水线的阻塞原因归到本次 |
| App、Release、设备性能 | 未执行；不能据此关闭用户的实际分块回放、半句显示、帧率或长期内存验收 |

最终 `lang-core.js` SHA-256 为 `842e71ddeee6d73a7c04df90f9c80f01ca43f504de2495e448047b7a75004e16`；`core-manifest.json` SHA-256 为 `0f6cb4bfc02b8442ae1e9f1c7d61678a4ecaaa75b0dc5ffeb19b2c023cfc8335`。本轮正式构建/全量/独立对照在忽略的 `outputs/client-audit/`；前后工作计数在 `outputs/kernel-client-performance/`，原始 patch 与 split 反证在 `outputs/client-patch-budget-build/`，前轮证据仍保留在 `outputs/kernel-followup/`。Swift 未执行的项目仍是验收缺口，不以 JS 或静态检查替代。

### 客户端仍未关闭的验收

用户提供的 2026-11-16 记录使用 SDK `9e05d888`，不是前轮 main `bdac1bfd` 或本轮候选；原始 Mac 日志、录像和 xcresult 尚未取得。以下保留用户报告的结果，不冒称在本环境复现，也不以源码修复、JS 通过或合并自动关闭这些失败。

| 验收项 | 已有证据与当前结论 |
| --- | --- |
| 流中文字长期停在半句 | 行程文字在输入早期及数据层已完整，画面约 18–54 秒仍显示截断，约 57 秒才补齐；酒店、表单也有类似观察。后续客户端断点显示 SDK source 已完整、received/displayed 仍旧前缀；本分支已修正文本 onChange 回调交付旧值的缺陷，原始客户端回放仍未重验。必须在 done 之前验证真实可见文本 |
| SDK 原生回归 | 用户报告 870 项中 10 个失败用例、24 条失败断言；涉及选项列宽、按钮身份、物化预算、Gallery 高度、mutation 退休、焦点、紧凑图表及三项 signed media。需要完整 testcase 和第一条 expected/actual；不能全部解释为生产缺陷或测试过时 |
| signed media 与 SVG | 三项 signed media 测试使用内存 PNG 和确定性 loader，不能用 App proxy HTTPError 解释。SVG 打开/缩放通过，拖动像素断言失败且归因未定；图像预览正常不等于 SVG 拖动通过 |
| 流中表单选择 | 复杂表单的自动点击实际发生在 done 后，流中选择跨完成状态保留仍未验收；小型状态测试不能替代此场景 |
| 性能 | 同一行程的一次 Debug 样本由旧版本平均 98.81% CPU / 峰值 220.58 MiB，变为 9e05 的 89.95% / 226.96 MiB；分片配置相同、实际传输时长不同。单样本不能证明改善或泄漏，未取得当前 main 的 Release、真机、FPS、有效 Instruments 或 memgraph 证据 |
| App 与后端阻塞 | Release 在 App 的 TaskBrowserSession.performRefresh 遇 Swift 编译器内部错误；真实模型链路受 sandbox initialize 的 fixed_sandbox_missing 阻塞。两项应独立跟进，不据此归因 SDK parser |

“Mutation 参数函数同步换源后可能派发旧调用”没有列为正常输入缺陷：现行语言契约要求自定义函数纯且同步，不得修改状态。违反该契约的宿主重入可以另做防御核验，不能与普通纯函数执行混淆。

**原生复验顺序。** 固定候选 revision，先编译并运行新增与既有 XCTest，保留每项失败的第一条 expected/actual。随后复跑用户的 10 项原生失败、signed media 和 SVG 拖动；稳定性补测包括 Store 往返与原子拒绝、Action 取消/累计预算、共享原生值 readiness、旧 Context 刷新、标准容器身份，以及 Gallery 窗口、高清升级和签名复用。不能因本轮实现覆盖相近模块就修改旧断言压绿。

实际 Muse 半句停滞仍需取得原始输入与客户端回放，逐段关联输入、投影、发布、text buffer、Markdown prepared 与可见文本版本，检查“目标字段已完整，其他节点继续生成时，done 前画面必须更新”。新增 mounted 回归覆盖直接 Text 与 Markdown 的持续输入场景，但没有运行，且小型 SDK 用例不能替代复杂客户端回放。

现有 `testCanonicalMarkdownPreparationCoalescesWithoutStarvingContinuousInput` 在 MainActor 同步循环投喂后才等待最终结果，未证明持续分片时的中间可见进展。文本 buffer 的 48 ms 逻辑是 throttle，追加不重置计时器；不能把真实停滞直接解释成普通 debounce。两个允许旧前缀的展示阶段和共享 Markdown worker 的等待需测量；如果直接 Text 也停滞，还要检查更上游的宿主、投影和发布。后续客户端断点与源码复核将一个确定缺陷收敛到变化回调交付旧捕获文本，修正见上节；没有把共享 native Value 的特殊触发当作该 App 事故的根因。共享 worker 的等待和其它性能成本仍需另测。

早期只读探针保留在忽略的 `outputs/text-audit/`、`outputs/remaining-action-budget-probe.*`、`outputs/remaining-state-aggregate-probe.*` 与 `outputs/main-assessment-20261116/`；本轮执行日志以前述 `outputs/kernel-repair-*.log` 为准。只维护本文这份验收记录，不新增并行审查报告。

### 性能证据与未完成项

保留前期审查的成本证据：同一台运行器、Node v24.22.1、同一旧资源、160 个稳定节点加文字尾部（8,439 UTF-16 units），各测三次；每块执行实际增量 parser、Store 初始化和 boundedRoot，末态相同。下表不是本轮候选的前后性能比较：

| 每块 UTF-16 units | 每条流更新次数 | 整条流累计耗时中位数 |
| --- | ---: | ---: |
| 16 | 528 | 1,273.9 ms |
| 128 | 66 | 133.9 ms |
| 512 | 17 | 37.7 ms |

这只量化 JS/V8 下更新频率的成本，不包含 Swift 预检、JavaScriptCore、原生桥接、live index 或布局，也不是用户设备帧率。不能据此宣称 SwiftUI 已有某个固定倍数的提速。

前期另一个独立探针使用当时已修正资源预算的 bundle 和原生 `NativeExpressionGuard` 相同的判定，对实际 preprocess/tokenize/split 单独计时。在同样 8,439 UTF-16 units 的文档中，16-unit 分块触发 209 次完整前缀检查，累计扫描 1,417,847 UTF-16 units，检查本身三轮中位耗时 138.7 ms；128-unit 分块为 27 次、183,159 units、15.5 ms。它定位的是快速包络超过保守阈值后的额外前缀扫描，而非 parser 已完成语句缓存失效。本轮已删除这条额外扫描路径，改用同一 parser 已有 tokens；上述时间仅作为历史 Node/V8 证据保留，未包含 Swift/JavaScriptCore/设备 UI，不作新版本设备提速结论。

客户端提供的 `c7310054` Apple Release 公开 API 记录显示：201 节点、24-unit 分片的 push p95 为 35.06ms、最大 63.06ms，整流同步计算 p50 为 4628.50ms；相同程序 128-unit 分片为 15.31ms、20.21ms 和 608.54ms。该消费者未挂载 SwiftUI。另一次实际 App Debug 被动回放报告平均进程 CPU 94.13%（100%=一个核心）、p95 117.16%，包含后台线程。这里保留用户报告，原始 Mac 产物未在本环境重新执行；不能把全部 CPU 归给 parser，也不能把 Debug CPU 换算为 FPS。

本轮用仓库 benchmark 相同生成规则进行了工作量对照：基线 bundle `52011d56…` 与当前 `842e71dd…`。200 rows 流式程序为 10,841 UTF-16 units；24/128 units 分别为 452/85 块。这里沿用客户端的 rows 参数；流式生成器还包含变化尾部及容器，不将参数直接当成最终总节点数。旧额外检查按删除前 Swift 包络的完全相同条件调用实际固定 core 重放；新计数来自临时资源在真实 `checkSourceStatements` 循环内的两个计数器。元数据按实际 JS 对象身份计数，不是 Swift 分配或设备时间。

| 200 rows 流式指标 | 24-unit 基线 → 当前 | 128-unit 基线 → 当前 |
| --- | ---: | ---: |
| 额外全前缀预检次数 | 201 → 0 | 38 → 0 |
| 额外扫描 UTF-16 总量 | 1,698,041 → 0 | 323,417 → 0 |
| 源预算 token 访问 | 225,110 → 13,688 | 42,688 → 3,659 |
| 全部独立 readiness 对象 | 98,334 → 1,774 | 18,702 → 334 |
| 元素投影访问 | 48,937 → 48,937 | 9,307 → 9,307 |

源预算 token 访问减少 93.9% / 91.4%，但整树元素访问仍在。61 节点的小负载原本无需额外预检；新检查分别访问 1,872 / 595 个现有 tokens，同时独立 readiness 对象从 16,170 / 3,148 降到 866 / 161。不能只引用大负载计数就宣称全部规模的耗时均下降。证据为 `outputs/kernel-client-performance/work-counts.json`，计数资源只增加统计，不作为发布资源；本轮尚无新版本 Apple CPU、Swift push p95 或 App FPS 数字。

计划累计预算的修复依据也保留为历史证据：修复前，128 个 Set 与 128 行 Each 的合法程序按原生控制流会产生 129 次 root 求值，Node 单次 root 为 1,549 work；另一份 100 个 Set 的程序逐步调用 boundedEvaluate 并写入 JS Store，每步 19,315 work、合计 1,931,500 work，仍无单步超限。前者是源码次数推导，后者是 JS 单步预算探针，都不是设备阻塞时长。本轮已加整条 action 额度与步骤间取消检查，原生累计拒绝的实际运行和响应效果仍待验收，不能继续将“完全没有计划预算”列为当前实现状态。

本次还对 Query 快照序列化做了计数探针：共享一个 1,000 项默认数组，分别建立 10、20、40 个合法独立 Query；输入长 2,292 / 2,582 / 3,162 UTF-16 units，均无解析错误。整个初始化分别发生 12 / 22 / 42 次全快照 JSON.stringify，累计序列化 131,597 / 464,387 / 1,734,167 UTF-16 units，而已记录求值 work 仅 40 / 80 / 160。它证明快照比较中的重复工作接近平方增长，现有求值 work 不能代表该路径成本。记录在 `outputs/kernel-followup/query-snapshot-cost.jsonl`；不是 Apple CPU、帧率或本轮前后提速结论。另用实际 manager 验证：provider 同步入口、同步 listener 或两次求值之间可原地修改共享默认对象；现有快照会正确通知变化，未变时保持 snapshot identity。因此不能直接省掉收尾比较或按对象 identity 复用序列化；本次未通过削减通知、改变快照相等语义或假定任意工具对象不可变来掩盖该项。

以下仍是开放项，不能标为本次已解决：

- `OpenUIState.push` 仍在 MainActor 同步解析、整 root 求值/投影并建立 live index。持续细分块仍会增加整轮工作次数；本轮没有自动按显示帧合并输入，也没有改客户端的 push/complete/interrupt 使用方式。
- 多步 Action 的累计额度已经加入，但逐步 Set/Reset 引发的 root 更新及计划结束后的更新仍保留。尚未实现渲染合并或节点级依赖计算；必须保留每步 Store 可见性、Mutation 失败即停止和事件次序，不可直接删中间通知。
- Query 快照比较仍重复序列化完整数据，上述计数已确认其规模增长；优化需保持 snapshot 值、正常通知及共享对象语义。Query 的内部通知投递已合并，实际原生执行次数和整 root 工作量尚未测量。旧 JS manager 探针中 100 个独立请求产生 100 次初始通知和 100 次完成通知；该计数不能直接换算成新实现的 MainActor 任务数，也不能宣称已测得“200 次变成 1 次”。不同执行时刻仍可能各产生一次呈现更新。
- 普通 push 的 readiness/root 双重通知已收敛到一次 root 发布；SwiftLangView 与各 ComponentHost 仍广泛订阅同一个 ObservableObject，尚未获得真实“尾部更新而稳定兄弟不重算”的 body 计数。字段 Store 读取、Query、readiness 和父环境均须正确更新，不能仅加 `equatable()` 或删掉订阅就假定依赖已被隔离。
- SharedCore 用锁串行化共享 JavaScriptCore。锁保护线程安全，不会自动把工作移到后台；多个文档可能相互等待。迁移到 worker 需要同步定义不可变输入/输出、回调线程、取消和提交代次，不能用 `Task.detached` 直接包住当前 MainActor State。
- 当前节点的 identity 快径不消除所有旧快照的语义搜索；规模较大的匿名桶需原生计数与耗时证明，再决定索引粒度。
- 尚无本轮真机 Release 的帧耗时、输入响应和长期内存数据。文档拥有的编辑记录保留离屏草稿，不能为压低缓存数字随意淘汰用户未提交内容；动态字段的长期留存需要专项测量。

编码前保护的范围以适配清单为准：高层 OpenUIState、Query/Mutation 输入输出、Evaluator 上下文和 AST，以及本轮补齐的 SDK CoreStore、手工 Query AST 与 ParseResult fallback 都在相应编码边界预检。底层 Store 保留原有 void 写入/初始化签名，拒绝时保留旧值，并通过内部失败状态供 OpenUIState 走已有错误渠道；没有新增客户端写入 API。自定义 Store 的策略、宿主函数返回前的自身计算，以及 provider 忽略取消后仍在进行的外部工作不能被库抢占。不能将这些限制解释为任意宿主代码的隔离沙箱。

现有 [LanguageRuntime 基准](../Benchmarks/LanguageRuntime/README.md) 使用公开 MainActor State 的真实流式路径及宽对象构造，报告逐次 push、complete、整流、发布次数与耗时分位数；CI 分片调整为客户端对照的 24/128 units 并保存 JSON，README 给出同样 201 节点参数。配置完成不等于测量已执行。原生验收还必须同时检查 terminal flush、停止/换源后旧结果失效、超限前无工具派发、完整控件可用、未完整控件不可执行，以及 Release UI 的 body/布局/挂载和滚动交互。

前轮纠正了旧基准调用与公共 API 的漂移：`Evaluator(context:store:schema:)` 的 `store` 实参已没有对应初始化器，基准改为当前 `Evaluator(context:schema:)`，状态仍由传入的 EvaluationContext 回调读取。YAML 及 workflow 内 shell 语法曾单独检查；这些检查不构成 Swift 编译通过的证明。

### 内核目标验收

下表是本轮原生复验及后续性能工作的验收要求，不是当前通过结果。每项实现时补对应验证，执行日志放 outputs；边界只在[架构](architecture.md#现有入口的性能边界与后续验证)维护，保持既有客户端入口和调用语义。

| 范围 | 验收场景与通过条件 |
| --- | --- |
| 现有输入与终止 | 连续用 push 送入细分块，检查每次同步返回的状态及终态 UTF-16 内容与既有契约一致。complete 提交完整尾部；interrupt 不补全截断 token，已闭合操作仍按 readiness 判断。reset/替换后 SDK 自己持有的旧异步任务不能回填；宿主用现有请求生命周期过滤旧请求的迟到 push 回调 |
| 排队与过载 | Query burst 的每个订阅至多一个待执行呈现投递，退休后不能回填，工具状态、错误与完成信息仍正确。持续细分块输入检查当前源码上限与实际主线程成本，不能丢内容或修改同步契约来压低次数 |
| 提交一致性 | 在 root/字段/readiness/错误发布和回调中制造重入、换源及乱序完成；每个可见提交内部一致，较旧更新不能覆盖较新结果，旧组件写入被拒绝 |
| 节点隔离 | 在稳定兄弟后持续修改文本尾部，并分别改变 readiness、Query 状态和字段值；无关节点的投影/body 计数不随分块等比例增长，实际依赖变化必须生效，焦点和未提交草稿保持 |
| 动作执行 | 多 Set 后发送事件，事件读取正确的逐步状态和既有回调顺序；完整计划的原生与 JS 工作累计，临近上限时不能再运行一个全额 JS 循环。Task 取消、累计超限、Mutation 失败或让步期间换源后，剩余步骤停止且 SDK 等待结束；provider 不配合取消的情况单独覆盖 |
| 原生输入与恢复 | 深/宽/共享图、整批状态恢复、直接底层入口均在大规模投影或写入之前明确拒绝；失败不提交部分无效数据，合法替换/reset 后可重新工作 |
| 设备响应与资源 | 同一设备、Release 构建、同一工作负载记录分阶段 p50/p95/max、主线程连续占用、提交/body 次数、输入与滚动响应；重复创建/退休文档检查任务和引用是否释放。JS 耗时、进程 RSS 或一次截图不能单独作为通过依据 |

帧耗时和响应阈值随目标设备及刷新率记录，并在前后比较前固定测试条件；当前尚未取得设备基线，不填写未经测量的达标数值。行为不变量必须通过，性能优化还需证明目标工作量减少且正常交互无退化。
