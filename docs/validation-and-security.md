# 验证与依赖安全

文档版本：1.40 · 更新日期：2026-11-23

本文说明当前 SDK 的可复现输入、依赖安全和原生验收范围。具体提交的执行结果以 [Native SDK 流水线](../.github/workflows/native-sdk.yml) 的日志为准。当前生成输入由 [Tools/upstream.json](../Tools/upstream.json) 固定，完整上游许可保存在随 SDK 打包的 [THIRD-PARTY-NOTICES.txt](../Sources/SwiftLang/Resources/THIRD-PARTY-NOTICES.txt)。

历次性能改动及效果见 [性能优化记录](performance.md)。先看[当前验收](#4-内核稳定性审查与当前验收状态)与[客户端未完成项](#客户端仍未关闭的验收)；依赖、复现命令和预算边界在第 1–3 节。

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

Runtime、Streaming、Components、Layout、Visual、Performance 六个领域的测试与验收计划维护在 [SDK 验证矩阵](../Validation/SDK/README.md)，覆盖共享 SwiftLang 底座与 OpenUI、OpenIntelligentUI 两套组件库。矩阵复用根 Tests、Gallery 与性能工具；`existing` 表示已有可复用实现，不表示本提交已执行或全部观测指标已采集。可重复的共享层性能测量由 [Performance](../Validation/Performance/README.md) 承担。固定程序及生成契约回归、双库原生视觉与交互审查、性能结果分别记录。

流水线按当前 SDK 分成三项检查：可复现输入、依赖安全和原生验收，最后由 `Native SDK acceptance` 汇总。汇总仅在三项均为 success 时成功；failure、cancelled、skipped 或缺失结果均不算通过，并在摘要记录实际 checkout SHA 和各项结果。该 job 的存在不自动设置仓库分支保护，合并阻断还需仓库将它配置为 required check。可复现输入检查重建实际打包资源并运行语言、authoring 和组件目录回归；安全审计覆盖 Core、标准富文本、代码高亮、图标和 Intelligent 函数五个生成工具依赖图，使用 `--audit-level=high` 门槛。原生验收构建并测试根 SDK 及其公开产品消费者。

原生验收覆盖 SwiftLang、OpenUI、OpenIntelligentUI 三个独立产品消费者。每个外部包只声明一个产品，验证打包资源、authoring、解析、流式、生成契约、原生宿主和状态读写；不启动窗口，不能代替 UI 视觉验收。模块检查禁止适配层导入两套组件库、任一 UI 导入另一套库；适配层内部 Language 目录不导入 UI 框架，Runtime 目录承接 SwiftUI。

其余原生验收覆盖全部原生测试、Release fitting、Release 挂载流式与呈现/订阅回归、独立 Gallery 测试与双库案例完整/流式验证、完整历史契约、语言 ASan、独立契约/性能工具及 iOS 编译。独立检查在前一个检查失败后仍可收集证据，但任何检查失败都会保留为任务失败。消费者源码生成或语法检查不等于实际 Swift 编译通过；原生编译与测试结果以对应提交的执行日志为准。

Intelligent UI 的原生布局与生成契约在 Debug 构建后提前检查，并纳入 Release 呈现回归。根百分比高度用例保留单独的 `intelligent-ui-root-layout.log`：仅该进程启用已有布局 trace，记录测量、放置的 proposal 与尺寸，不记录源码或业务值。`intelligent-ui-composition.log` 覆盖真实注册组件的 RTL、百分比、编辑状态和示例裁剪；这两份日志随早期 Debug 产物及最终验收产物保留，不替代全量测试。

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

真实流式性能与重复拟合分开验收。当前 `OpenUIState` 在 MainActor 上同步执行每次 push 的解析、根求值和 live-element 索引；`SwiftLangView` 观察完整的原生呈现提交，轻量组件 Host 仍观察最近 State，内部内容使用节点订阅。`RuntimeHostIsolationTests` 与 `HostSizingIsolationTests` 中重复提交相同源码和尺寸拟合的检查，只证明该路径不重复解析、发布或重挂，不能证明真实尾部增量不会刷新无关组件。局部刷新与每帧耗时需要在目标设备的 Release 构建中，另测不同内容规模和分块频率下的解析、桥接、求值、组件 body 与布局成本；没有运行证据时不宣称该观察路径已经收敛。

任一物化、求值或输出预算失败后，OpenUIState 保留最近一次通过预算的已显示内容，停止当前文档的动作、Query 和 Mutation；不能把失败产生的 `null` 继续写入状态或作为工具参数。替换源码或 reset 可以恢复。预算用于限制异常工作量，并非每帧耗时或设备帧率保证；原生不卡顿仍需在目标设备 Release 构建上测量。

原生控件验收还包括：EditableTable 的本地提交不得代表远程持久化；被拒绝的草稿不能随 Store 发布而提交；替换文档建立新草稿生命周期。Slider 的离散选择同时考虑 minimum 和 step 精度，非整除范围允许拖到最大值，连续文本仍按范围校验。对应控件测试与真实窗口检查各自报告。

## 4. 内核稳定性审查与当前验收状态

本节区分当前验收与历史证据，后续列出测量方法和未完成项。历史失败、临时诊断与逐轮修正通过固定提交链接回查；历史结果只属于其标明的版本。当前 SDK 接口与行为边界以[架构](architecture.md)为准。

| 范围 | 已核对状态 |
| --- | --- |
| 清理前产品基线 | `e11f23b` 通过 [CI 44240941058](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44240941058)：全量 XCTest 1,251 项、Release fitting 5 项、SwiftLang ASan 451 项零失败；资源、安全、独立消费者、Gallery 与 iOS 16 Simulator 构建通过。各测试组有重叠，不累加。main `15ffd03` 只在其后更新文档，产品源码相同 |
| 本轮代码与验证整理 | 基于 `15ffd03` 移除无消费者的 lookup 变化集合、无效组件输入及测试薄包装；按既有职责归位组件和桥接代码，收拢测试辅助与 CI 重复。源码 `4e57814` 已通过 [CI 44255160097](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44255160097) 的全部任务和最终验收，实际计数见下文 |
| 实际客户端性能 | Muse 完成长会话滚动、真机 Release 与同进程重复进入/退出的内存验收仍未关闭；SDK 功能测试、JS 计数和无 UI 基准不能替代 |

### 本轮清理验证

生产节点索引只保留当前 membership、候选和呈现变化；相关测试继续验证旧/新对象身份、readiness 歧义、候选顺序、深度边界、释放及真实流式订阅。组件和 Schema 代码按现有职责移动；Query 生命周期转换与预算转换分开。

Query 转换后源码、867,575 bytes 的 `lang-core.js` 及许可文本均与基线逐字一致；manifest 只更新构建来源哈希和两处来源路径。54 个移动声明逐块核对，公开声明行集合保持。执行证据保存于忽略的 `outputs/sdk-cleanup/`。

14 个探针用例归入既有职责测试，独有输入与断言保留；1 个完全重复用例去重，2 个架构约束归入必过模块检查，其余迁移和重命名逐项对应。待测 bundle 统一从 `OPENUI_NATIVE_CORE_JS` 选择，参考向量格式错误明确失败。Node native 套件 173 项、显式 bundle 覆盖入口 14 项及 realm/UTF-8/计时器检查通过。Release 合并保留原筛选的独有覆盖，ASan 选择不变；两项图片尺寸用例移除额外三轮重复采样，仍在完整 Debug 和 Release 中执行。

源码 `4e57814` 的 [CI 44255160097](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44255160097) 全部通过：Debug preflight 128 项、完整 Debug 1,248 项、合并 Release 585 项、Release fitting 5 项、SwiftLang ASan 451 项均零失败。Debug/Release 的发现、筛选和执行标识已逐项核对；源码静态计数比 macOS 发现数多 2 项，来自既有 `#if os(iOS)` 用例，不计入本次 macOS 通过数。各测试组有重叠，不累加。环境为 macOS 15.8.2、Xcode 26.3、Swift 6.2.4。

资源重建、安全与模块检查、三个独立消费者、iOS 16 Simulator 产品与 Gallery 构建均通过。Gallery 测试 16 项、184 个变体的批量与流式验证、61 个历史组件的位置签名及完整 schema 检查通过；独立工具与两种分片的既定 Release 基准完成。最终验收的 checkout 与产物 provenance 均为 `4e57814`。随后的收尾只更新本文和性能记录，源码、测试及工作流与该受测版本一致；基准完成不等于本轮已有设备性能增益对照。

### Query 反馈去重与终态引号回归

Query 反馈的两个读取路径共用一次遍历。引号回归保留未转义的原始输入，验证截短前缀与诊断；正确转义对照验证完整正文，以及批量/逐字符输入一致。现有用例位于 `native-streaming.test.mjs`、`CompletionDeliveryTests`；宿主判定见 [README](../README.md#终态与诊断)。最小重建输入不等于原会话全文回放，转义丢失环节仍未确定。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L109)。

### SDK 正常接入与生命周期审查

同一不可变组件目录按需复用 reader 元数据，文档执行状态独立；字段 owner 随 form/name 切换，初始化使用当前生命周期输入；Slider 写入在实际接受后确认；Markdown 释放已被覆盖的 fallback；响应缓存命中遵守当前字节限额。真实字段、资源、订阅和重入回归保留，接入接口不变。

文档创建测量使用 88 个组件的真实目录，在同一进程交替比较目录复用与每次重新 `toSchema`；预热两轮、每条路径 12 次。计时在解析源码之前停止，首次 reader 准备单独报告。`807d016` 的 [CI 44156376266](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44156376266) 中，重复创建 p50 为 Debug **109.38→13.16 ms**、Release **137.74→14.03 ms**；Release 首次准备仍为 **141.55 ms**。

原始输出为该 CI artifact 的 `visual/library-document-creation-debug.json` / `library-document-creation-release.json`，本地证据位于 `outputs/sdk-runtime-performance-review/ci-44156376266/acceptance/`。此测量未挂载 UI，不代表会话加载总耗时、滚动或真机收益；不同候选的 CI 数值不混算。字段初始化失败、修正及早期测量见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L125)。

### 变化尾部的查询依赖遍历

从 `807d016` 继续对照 200 个稳定文本、一个变化尾部和根容器。先让声明完整，再追加 24 个单位；Node VM 的操作计数显示 parser 仍重新物化稳定行，而 `boundedRoot` 直接使用本轮静态结果，求值 work 为 1。这是工作量与对象身份的证据，不是 Apple 各阶段耗时。公开基准没有挂载组件，因此这组长调用也不能归因于数百个 SwiftUI 订阅或布局。

调用栈计数把 1,011 次 `Object.values` 中的 606 次定位到原生 readiness 的 Query 依赖收集。入口原本会跳过已完成、无引用的语法，但递归通过符号访问同样语法时没有复用该事实。修复仅在内部递归复用已有 `closedLocalDepth`；同一对照的该项枚举由 606 次降至 6 次，总枚举由 1,011 次降至 411 次。解析结果、诊断和 presentation 相同，元素与字面容器仍按原语义创建；没有缓存业务值或增加状态所有者。

新增实际遍历回归在原 bundle 上失败、正式重建后的候选通过；本地随包核心 173 项、Validation 与目录兼容合计 13 项通过，固定官方独立对照无未解释差异。原生耗时对照见下文，不能把枚举数量下降换算为帧率收益。执行材料保存在忽略的 `outputs/runtime-cost-followup/`。

本节的 SDK 源码候选 [`e11f23b`](https://github.com/zyfn/open-intelligent-ui-swift/commit/e11f23bfc335c6f07b30f159b875f62b3d9a5d3b) 已通过 [CI 44240941058](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44240941058) 的全部任务及最终验收：完整原生套件 1,251 项、OpenUI Debug / Release 各 356 项、Release fitting 5 项、SwiftLang ASan 451 项均零失败；这些组有重叠，不累加计数。iOS 16 Simulator 产品与 Gallery 构建、三个独立消费者、Gallery 测试与 fixtures、历史组件契约、资源重建、安全检查及两种分片的 Release 基准均通过。原始验收材料位于 `outputs/runtime-cost-followup/ci-44240941058/`；这不替代实际客户端滚动、真机或泄漏验收。

在上述历史修复的诊断中，语言性能验证工具增加了单次 push 外层 signpost，以 iteration / chunk 关联运行时区间，并分别记录两组负载的元素数。`--rows 200` 的流式末态实际为 202 个元素；此前顶层 `components=201` 属于另一组语言负载，不能直接套用于流式输入。该次加入诊断时，固定负载输入、分片方式和完成断言保持不变。当前采样开关与诊断开销的解释见 [性能验证说明](../Validation/Performance/README.md)。

#### 同机对照与阶段证据

[诊断执行 44241757025](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44241757025) 在同一 macOS 15.8.2 / Xcode 26.3 runner 比较 main `807d016` 与源码候选 `e11f23b`。两者使用同一份候选基准和 Swift 源码，只切换核心 bundle 与 manifest；每次重建后核对实际复制的资源哈希。执行两轮“基线 → 候选 → 候选 → 基线”，每个版本、每种分片得到 4 份报告，每份测量 3 条流；均使用 `--rows 200 --warmup 1 --iterations 1`。所有报告的 `pushSignpostsEnabled` 都为 true；材料中的 `uninstrumented` 仅表示未额外启用 Time Profiler 或阶段缓冲记录，不能解释为完全没有诊断开销。

| UTF-16 分片宽度 | 基线单次 push p95 范围 | 候选单次 push p95 范围 |
| --- | ---: | ---: |
| 24 | 31.88–38.10 ms | 26.30–35.43 ms |
| 128 | 34.64–43.93 ms | 24.60–31.59 ms |

范围由各组 4 份报告的 p95 构成，不是合并样本后的 p95。128 单位组在本次执行中方向一致；24 单位组有重叠和波动，候选最大单次 push 仍为 111.99 ms。数据支持保留这处减少重复遍历的修复，不支持统一提速百分比、长尾消失或 Muse 滚动改善的结论。

同一诊断执行另运行两次阶段记录，均使用候选 `e11f23b`：只在临时 checkout 内为现有运行时区间加入标量缓冲和外层 push 区间，退出时一次写出，补丁随 artifact 保留，不进入 SDK。每次排除 452 次预热，分析 904 次测量 push；按同线程包含关系构造区间树，以父区间减去直接子区间的并集求独占时间，检查无交叉及总量守恒。下表是各阶段独占时间占全部测量 push 总时间的比例：

| 阶段 | 记录 1 | 记录 2 |
| --- | ---: | ---: |
| Parse | 71.44% | 68.97% |
| Native projection | 19.06% | 20.70% |
| Parse projection | 3.05% | 3.47% |
| Live index | 2.55% | 2.67% |
| Root evaluation | 0.284% | 0.281% |

其余为桥接自身、提交、上下文和区间外工作，不能再把包含上述阶段的 `Bridge operation` 总时长相加。两次最慢 push 分别为 165.13 / 69.19 ms，其中 Parse 为 154.01 / 60.61 ms；另一次较慢调用的 Native projection 也占明显份额。阶段记录有额外开销，绝对值不与上面的普通对照直接比较。Parse 包含官方解析/物化及本库适配，不能称为“官方词法耗时”；Root evaluation 的低占比只适用于本次稳定字面值负载，不代表 Query、动态表达式或表单更新的成本。

同次捕获的 Time Profiler 已通过[只读导出执行 44243615962](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44243615962) 取得实际 `time-profile` 数据。16,136 个采样的 XML 引用均可解析，权重均为 1 ms；它包含预热，与阶段统计的样本范围不同。主线程可识别的 `OpenUIState.push` 栈共 13,554 ms 采样权重，其中带 `CoreStreamParser` 的为 9,504 ms，带 `SharedCore.decode` 的为 2,993 ms，两组不重叠。解析栈内可见分配慢路径与 `JSC::Heap::collectInMutatorThread()`；后者为 2,444 ms 采样权重。分配慢路径包含其触发的 GC，二者不能相加，也不能将采样权重写成精确函数耗时。投影栈可见 `JSContext` / `JSWrapperMap` 包装和逐项 `JSValue` 读取。

这些证据把后续工作缩到解析阶段的临时对象构造及原生投影的桥接访问，但没有足够 JS 源码符号把成本进一步分到官方物化、readiness 或预算逻辑。原生投影可从 [SharedCore](../Sources/SwiftLang/Language/SharedCore.swift) 中 `entries` 每个字段的两次 `atIndex`，以及 `items` 的逐项读取开始测量；JS 已批量整理字段，单次投影也已按 JS 身份与呈现 scope 复用结果，不能再把这些机制描述为缺失，或按相同显示文字跨轮缓存业务值。GC 所回收的对象也不一定都在该阶段分配；本次未取得分配字节、对象持有链或与阶段记录中单次长调用的精确关联，不能据此诊断泄漏或声称 GC 解释某一次停顿。材料在 `outputs/runtime-cost-followup/ci-44241757025/` 与 `ci-44243615962/`；真实客户端完成文档的滚动和同进程内存复测仍未验收。

### 完成长文档的滚动与布局

布局优化 `7ed102a` 基于 `2db93675e50ba89579594c5220e935928bea55bd`。对应客户端反馈来自锁定 SDK `7d9b36a` 的模拟器 Debug 长会话：页面约 53,810 pt，观测到的三个视图实例约 14,091–18,034 pt，各实例根求值结果按对象身份去重可达 162–206 个元素。实例未绑定业务标识，不能认定为三个独立文档；可达元素数量不是实际 SwiftUI 视图数。

| 客户端一次隔离实验 | 超过 100 ms 的回调间隔数 | 最大间隔 |
| --- | ---: | ---: |
| 完整 OpenUI | 19 | 约 280 ms |
| 表格等高隔离 | 20 | 约 197 ms |
| Markdown 等高隔离 | 17 | 约 183 ms |
| 整个 OpenUI 根视图等高隔离 | 0 | 约 57 ms |

以上是用户提供的 CADisplayLink 回调间隔，非函数耗时或本环境实测。每组仅一次，操作总时长、位置和机器负载未完全控制，过程中模拟器曾重启，不能换算成优化百分比。表格 `currentColumns` 的临时复用实验消除了对应采样出现，仍有长间隔；单独移除表格或 Markdown 也不足以解释整体问题。内存快照未附有效分配栈或持有链，尚未证明泄漏。临时等高隐藏只用于隔离，没有作为 SDK 的呈现策略。

源码核对确认，`7d9b36a` 至本轮基线的 FlowLayout、标准表格和 Markdown 核心呈现路径没有变化。此次只收敛两处明确重复工作：Flex 的测量与放置共享当前 Layout 有效 proposal 的 frames；表格一次 body 只推导一份当前列及分页值，复用不可变列数组。保持原有布局算法、组件身份、流式推进、表格数据回退和完成后的动态更新，机制说明在 [OpenUI](openui.md#布局与流式)。布局或子视图变化的失效遵循 Apple 的 [Layout.updateCache](https://developer.apple.com/documentation/swiftui/layout/updatecache(_:subviews:)) 契约；缓存仅属于一个布局实例，不能以文档 complete 作为永久有效条件。

共享压力输入使用 [mixed-long-document.openui](../Tests/SwiftOpenUITests/Fixtures/mixed-long-document.openui)，文字为固定合成内容，不含真实会话、账号或网络资源。随包内核与真实目录解析得到 200 个可达元素，批量输入与每 64、512 个 UTF-16 单元分块输入的完整结果一致，错误及未解析引用均为空。它覆盖混合正文、卡片、表格和表单；目标是在同一输入下复测尺寸、更新和交互，尚未证明与客户端真实会话等价。原生测试记录实际元素数量和高度，不把设计目标高度写成测量值。可通过现有 Gallery 直接打开：

~~~sh
swift run --package-path Examples/Gallery -c release OpenUIGallery \
  --library openui \
  --program "$PWD/Tests/SwiftOpenUITests/Fixtures/mixed-long-document.openui" \
  --width 390 --height 844 --zoom 1
~~~

验收分开检查计算复用与正确失效：同一有效 proposal 的 frame 计算可复用；宽度、同数量内容、字体、布局值、子项增删仍更新几何；完成后表格状态修改及行数收缩仍更新可见内容。长文档重复拟合须保持无额外解析、语义发布或重挂，宽度往返仍恢复正确几何。计数和几何测试不代表滚动帧率，最终仍需同一输入、设备、构建和手势下的 App 对照，包括滚动位置、流式尾部、动态高度、表单草稿、链接和会话切换。

字体失效回归在 macOS 上显式切换继承的 font 环境，保留高度必须增长及恢复的断言。Apple 明确说明 [dynamicTypeSize 在 macOS 不改变文字大小](https://developer.apple.com/documentation/swiftui/environmentvalues/dynamictypesize)，因此不能用该环境值下文字等高来判定缓存失效，也不能把 macOS 字体回归写成 iOS 系统 Dynamic Type 的运行结果；后者仍需目标平台验收。

`LayoutMeasurementReductionTests`、长文档 `HostSizingIsolationTests` 及 Release fitting 已进入后续原生验收，具体候选以本页当前状态和 CI 为准。早期材料在 `outputs/long-document-layout-cost/`。无 UI 的语言性能验证不能替代真实滚动；若探索区段呈现，宿主继续拥有可见范围、消息回收和阅读位置，SDK 继续拥有同一文档的节点身份、引用、Store 和交互。当前没有分段 State 或视口管理器。

### 文档资源生命周期

已完成缓存沿用文档所有权，增加跨文档预算与内存压力回收；图片、响应、鉴权和 pending 生命周期保持分离。桥接身份随原生对象释放，共享索引只留弱反查，移除原来的每 32 次调用全表扫描。预算及所有权见[架构](architecture.md#文档与资源的生命周期)。

`ResourceCacheBudgetTests`、`ResourceStoreTests`、`SharedCoreBridgeTests` 覆盖 LRU、零成本条数、弱 owner、压力下 pending、旧快照释放及并发析构。ASan 通过不证明无泄漏；缓存额度也不是进程内存上限，净分配和真实 App 内存效果仍未量化。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L223)。

### 历史修复记录

早期修复覆盖隐式转换预算、共享 readiness、UTF-16 字段整理、当前节点身份查找、同步发布重入、Query 派发资格及编码前预检。宽对象原线性去重改用精确键索引，当前对象使用 membership 快径；旧快照的语义与歧义规则保留。原始失败、工作量推导及独立官方对照有固定记录，不能把这些源码计数当成设备耗时。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L244)。

### 已合入基线的前轮修复与验证

Store 聚合预算、Action 累计额度及取消、底层编码前保护、共享值 readiness、旧 Context、容器身份和 Query 投递收敛均已进入主线。图片预览只挂载当前及相邻页，高清升级、签名快照和 SVG 重试保留原有校验。运行边界见[架构](architecture.md)，早期未获执行的状态不再作为当前验收结论。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L265)。

### 原生文本流中停滞

变化回调必须消费收到的新值，不能重新读取旧闭包捕获；实际 mounted 回归检查 done 前的文字进展、取消、纠正与换源。SDK 的小型文本回归已进入原生验收，真实 Muse 复杂会话仍需原输入回放；不能把所有半句现象统一归因于 Markdown、节流或 Lang 转义。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L298)。

### a4808be 合入时的内核修复与验证

Query 以缓存条目身份和当前消费者拒绝退休请求；共享请求、缓存恢复、dispose 末态及批次清理保持一致。原生返回阶段先检查请求存活，再检查结果或错误预算。消息帧选择保留普通 Lang 的注释/字符串，patch 在清理和拆句前检查原始输入；合法恢复和原回调顺序保留。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L310)。

### 客户端 a4808be 定向复测（2026-11-16）

以下由用户提供，日期采用 Asia/Shanghai。新版固定为 `a4808be333598bb15a6990f47eeb0d23c930c1dd`，旧版为 `c7310054e5a58ecb7e42e9f37e4c77e7fed30ce7`。客户端未修改 SDK/Host 实现或历史 fixture，也未运行全量测试、提交或发布。本文记录报告中的实测值；原始 Mac 日志、JSON、sample 和图像未在本环境取得或重新执行，不能将其写成本环境独立复现。

**功能与原生门禁。** 外部消费者复用上一轮完全相同的 19 项公开 API 探针，仅更换固定 SDK checkout，结果为 **19/19 通过**：

| 检查 | c7310054 | a4808be3 |
| --- | --- | --- |
| 普通注释含 content 标记 | root 消失、无错误 | batch / stream / State 均保留 `kept` |
| 多行字符串含 content 标记 | root 消失、无错误 | batch / stream / State 均保留原文字 |
| 2,097,169 UTF-16 units 的原始 patch | 超过 1,048,576 上限仍提交 `after` | 约 1.78ms 拒绝，保留 `before`，`isInterrupted=true` 并返回预算错误 |
| 其余 16 项 | 通过 | 通过；覆盖 Unicode 分片、重试帧、pristine、重入、预算原子恢复、取消、表单输出及旧 Query / 下游派发隔离 |

这些是有限场景，不代表所有竞争组合。App Debug 构建通过；SDK 官方定向 XCTest 在执行前编译失败：`Tests/SwiftLangTests/FramedStreamingTests.swift:127` 将原始 parser 的 `ElementNode` 传给只接受 `EvaluatedElement` 的 `PropValue.string`。上一轮 `ActionWorkBudgetTests.swift:97` 的错误已修复，但此次选中的剥帧、patch 预算、单次发布和挂载文字进度用例均未执行，19 项外部探针不能替代原生门禁。报告引用 `public-probe-results.json`、`PublicProbe/Sources/PublicProbe/main.swift` 和 `targeted-sdk-tests.log`。

**独立 Release 性能验证。** 同一机器、工具链和同一份性能工具源码，节点、分片、预热与测量配置保持一致；61 节点流式测量 3 次，201 节点 2 次。以下节点标签沿用客户端报告。消费者没有 SwiftUI 视图或网络等待，数值表示同步计算，不是帧率或模型延迟。

| 节点 / 每块 UTF-16 units | push p95（ms）旧 → 新 | 整条流计算 p50（ms）旧 → 新 | 每条流发布次数旧 → 新 |
| --- | ---: | ---: | ---: |
| 61 / 24 | 5.60 → 4.51 | 490.67 → 376.72 | 385 → 195 |
| 61 / 128 | 5.81 → 3.84 | 119.97 → 79.79 | 75 → 38 |
| 201 / 24 | 35.06 → 20.60 | 4628.50 → 3412.48 | 915 → 462 |
| 201 / 128 | 15.31 → 10.19 | 608.54 → 455.18 | 177 → 91 |

额外一次紧邻的旧/新 201 节点、24-unit 对照，push p95 为 32.95 → 19.15ms，整流计算 p50 为 4348.30 → 3095.48ms，方向一致；样本仍少，未做显著性推断。**长尾未收敛：** 主测和紧邻对照的新版本最大单次 push 分别约 102.35ms、79.89ms，对应旧版为 63.06ms、46.38ms。不能只报告 p95 改善，也不能仅凭最大值归因于 GC 或某个缓存。201 / 24 的 p95 仍约 20ms，尚未计入 UI 布局绘制。

发布次数接近减半与 readiness 不再单独 Published 的机制一致，但不等于 SwiftUI body 或 App CPU 减半。报告引用 `comparison.json`、`benchmark-*.json`、`paired-c731005-200rows-chunk24.json` 和 `paired-a4808be-200rows-chunk24.json`；测量期间没有并行编译或运行其他本任务性能测量。

**实际 App 被动流。** 使用同一独立模拟器 `5ACEAD69-A401-4DD3-BBD0-0D8D9C04BD9C`、正常动画、Debug 包，以及原行程源码 SHA-256 `d6728e6104c9a218a20c1511eff72852f155bd9c269c34f2d6efc314dd3856be`，按 24 字符 / 80ms 回放。新版 PID 为 4621；发送后至采样结束没有 UI 查询、截图、手势、录屏或 LLDB。服务器流约 39.10 秒，CPU 计数覆盖完整流；55 秒 sample 包含流前空闲、完整流和少量流后时间，采样自身有开销。

| 指标 | c7310054 前轮 | a4808be3 本轮 |
| --- | ---: | ---: |
| 流中平均进程 CPU（单核心 = 100%） | 94.13% | 92.79% |
| CPU p95 | 117.16% | 112.94% |
| 250ms 峰值 | 146.01% | 145.11% |
| App footprint 峰值 | 189.39 MiB | 189.64 MiB |

每版仅一次被动流，差异很小，未建立 App CPU 有实质降低的结论。进程 CPU 包含后台线程；footprint 不含独立 WebKit，不能据此判断泄漏。新版包含同期组件视觉与排版改动，CPU 差异不能全部归因于内核。符号化样本仍见 SwiftUI/AttributeGraph、类型元数据和 ARC 工作；两次同步发布可能被 SwiftUI 合并在同一更新周期内，实际视图失效与布局成本仍需独立计数。部分 PLCrashReporter DWARF 解析有警告，报告称第一方 Swift 源路径可定位。该复测不是 Release App、真机、持续滚动或 FPS 验收，也没有新发真实模型请求。

报告引用 `passive-metrics.json`、`passive-process.jsonl`、`passive.sample.txt`、`passive-sample-analysis.json` 和 `final-ui.png`。App 构建沿用命令行 iOS 18 编译目标覆盖以处理本地 Network 模块最低版本冲突，未修改源码最低系统配置；不能把这次构建解释成所有最低部署目标均已验证。Muse 不直接调用已改为 `throws` 的 `mergeStatements`，本次无需修改其调用代码；其他直接使用该 helper 的消费者需处理异常，现有 `push / complete / interrupt` 接入继续使用。收尾恢复真实本地 3002/3003，只停止本次拥有的回放服务。

### a4808be 复测后的流式成本修复

Query 呈现按批读取一次快照和错误数组。实际 manager 的 40 个 Query 探针中，错误项读取从 1,600 降到 40，状态一致；它未消除 JS 侧完整快照比较。桥接成组读取元数据和属性，保留 UTF-16、顺序、对象身份和呈现 scope，原生耗时需另测。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L390)。

### cf8d2ad 基线的呈现提交与节点订阅

内部 `NativePresentationCommit` 在同步工作及重入稳定后交付，节点订阅记录实际字段依赖；公开通知、Store 和业务回调保持原合同。呈现提交是只读快照，不能替代可写 Store，也不能据此声称语言求值已经按依赖增量化。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L421)。

### 内核职责与失败边界清理

预算失败与运行异常按所属执行入口交付，停止后续副作用并保留最近有效呈现；正常可恢复诊断继续遵守官方语义。单一状态、请求生命周期、Action 累计预算及边界覆盖统一见[架构](architecture.md#失败与正常诊断的区别)，不另建状态所有者或客户端协议。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L448)。

### 流式重复工作收敛

增量预处理消费完整行，保留尾行、引号、注释和围栏语义。200 个稳定叶子追加 50 次的固定探针中，该步骤完整前缀切分从 50 降到 0，扫描从 244,325 降到 0 UTF-16 units；未完成长行仍可能重复处理。

稳定呈现和实际字段订阅减少重复节点工作：40 个稳定标量叶子、4 次真实尾部 push 的订阅通知为 0。身份、readiness、引用属性、最近 State、注册表及父闭包变化仍须交付。此计数不是全部 body/布局次数，也不是滚动帧率。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L486)。

### OpenUI 图片与首次正文准备

图片按实际画幅、倍率、fit/fill 与 EXIF 请求解码，复用足够清晰的结果；自动暂时失败恢复、签名、取消与预算仍属于原请求生命周期。SDK 仍下载原 URL，没有减少传输字节的证据。

Markdown 首次后台等待期间，同配置追加复用可读 fallback；受控回归中 100 次追加只产生 1 次首次备用解析，中间结果继续交付。有效后台结果覆盖后释放旧源码与解析树，纠正及 generation 保留。规则见 [OpenUI](openui.md#文本媒体与原生差异)。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L524)。

### 基线原生失败的逐项核实

历史失败通过独立官方 oracle、纯 SwiftUI 对照、像素回读、真实挂载身份和访问树区分实现缺陷与测试前提。涉及深层预算栈、闭合 readiness、图片尺寸回调、字段存活、SVG 语义、Mutation patch 与中间尾空格。修正有独立依据，原始 Lang 和有效行为断言保留；后续正式原生验收结果不能反向改写当时失败。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L549)。

### 客户端仍未关闭的验收

| 范围 | 当前仍需的证据 |
| --- | --- |
| Muse 长文档滚动 | 同一授权输入、设备、构建、手势的前后对照；关联宿主挂载、SDK body/布局和阅读位置。等高隔离实验只缩小范围，不能认定某个组件独自负责 |
| 真机与内存 | Profile/Release 帧耗时及输入响应；同进程多次进入/退出的稳定值、有效 Allocations 或 Memory Graph 和持有链。ASan、RSS 单点和缓存上限均不等于无泄漏 |
| 真实文本与交互回放 | 目标正文已完整、其他节点继续生成时，done 前实际可见内容持续更新；复杂表单流中选择跨完成保持、signed media、SVG 拖动和会话切换需客户端原场景复验 |
| Xcode 26.6 | 历史 `NativeValueBudgetTests.testSyntheticMetadataAndActionLeavesShareTheInspectionAllowance` 的 Release 优化器崩溃未在该工具链复验。Xcode 26.3 的成功不能代替 |
| App / 后端阻塞 | 用户报告的 `TaskBrowserSession.performRefresh` Release 编译器内部错误与 `fixed_sandbox_missing` 分别跟进，不能据此归因 SDK parser |

较早 `9e05d888` 的 870 项中 10 个失败报告与后续 SDK 原生完整通过属于不同版本。已有逐项定位与修复记录，不再把旧数量列为当前失败；客户端未提供的完整 testcase、首条 expected/actual 和原始会话回放也不能视为已经取得。历史报告与观测限制见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L572)。

### 性能证据与未完成项

下表保留 `3828c3c→a4808be3` 的实际 bundle 工作量对照：200 rows、10,841 UTF-16 units，24/128 单位分别 452/85 块；元数据按 JS 对象身份计数。源码、统计方式、Node/V8 旧扫描耗时和 Action 探针见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L595)，不作为 Swift/设备耗时。

| 指标 | 24 单位基线 → a4808be3 | 128 单位基线 → a4808be3 |
| --- | ---: | ---: |
| 额外全前缀预检次数 | 201 → 0 | 38 → 0 |
| 额外扫描 UTF-16 总量 | 1,698,041 → 0 | 323,417 → 0 |
| 源预算 token 访问 | 225,110 → 13,688 | 42,688 → 3,659 |
| 独立 readiness 对象 | 98,334 → 1,774 | 18,702 → 334 |
| 元素投影访问 | 48,937 → 48,937 | 9,307 → 9,307 |

原始计数在 `outputs/kernel-client-performance/work-counts.json`。该流式负载末态为 202 个元素；旧报告的 201 标签与另一组语言负载混用，不能作为实际流式节点数。

仍需分别测量的路径：同步 push 的解析及原生投影长尾、整树索引与挂载订阅检查、多步 Action 的逐步更新、跨文档共享 JSC 等待，以及 Query 完整快照比较。既有局部更新、预算和身份机制不等于消除这些工作。

Query 探针中，10/20/40 个独立 Query 共享 1,000 项默认数组，初始化完整快照序列化分别 12/22/42 次、累计 131,597/464,387/1,734,167 UTF-16 units，求值 work 仅 40/80/160；证据在 `outputs/kernel-followup/query-snapshot-cost.jsonl`。正常 provider/listener 可修改共享对象，不能只凭 identity 跳过比较或削减通知。当前未量化其 Apple CPU 成本。

公开性能验证工具与命令见 [Performance](../Validation/Performance/README.md)，功能边界见[架构](architecture.md#现有入口的性能边界与后续验证)。计时、工作量和实际 App 体验分别验收。

### 客户端复测收尾候选

节点输入比较与动态属性内容分开，焦点和字段回调使用新值；卡片 layout value 由直接子边界交付。访问树和几何采集按实际挂载实例读取；测试资源 owner 显式保活。字体与 Query 定时器用独立原生/官方对照校正观测前提。修正后 `315cd4e` 的 [CI 44073952191](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44073952191) 全部通过，包括 1,217 项全量 XCTest、444 项 ASan、三个消费者及 iOS 构建。更后的产品基线见本页当前状态。

逐轮诊断、原始证据路径与当时验收状态见[固定历史记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L643)。

#### 正式候选的执行结果

`315cd4e` 的完整分组计数、环境及产物核对见[固定验收记录](https://github.com/zyfn/open-intelligent-ui-swift/blob/15ffd0387bde0d2b648ecec052e3eec0cf0a9266/docs/validation-and-security.md#L681)。本页顶部记录后续候选，历史通过不替代新提交验收。

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

帧耗时和响应阈值随目标设备及刷新率记录，并在前后比较前固定测试条件；当前尚未取得设备帧耗时与持续滚动基线，不填写未经测量的达标数值。行为不变量必须通过，性能优化还需证明目标工作量减少且正常交互无退化。
