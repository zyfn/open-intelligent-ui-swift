# 架构

文档版本：1.17 · 更新日期：2026-11-21

本文是仓库唯一的架构定义，维护包名、目录、职责、依赖和运行链路。接入代码见 [README](../README.md)，组件用法见 [OpenUI](openui.md) 与 [OpenIntelligentUI](openintelligentui.md)，构建和验收见 [验证说明](validation-and-security.md)。其他文档引用本文，不重复维护模块图或职责表。

## 1. SDK 目标与职责

SDK 为持续生成的内容提供稳定的原生呈现：输入不能丢失，状态不能串代，异常能停止并恢复，计算与内存有边界，用户输入和滚动保持响应。设计取舍以这些目标和本项目的实测结果为依据。

每层只拥有一类权威数据和行为：

| 层 | 本项目名称 | 职责 |
| --- | --- | --- |
| 语言执行 | 固定版本 lang-core，随包分发的 lang-core.js | 词法、解析、流式补全、求值、Store、Query 依赖调度、Schema、签名与 Prompt 规则 |
| 原生运行时 | SwiftLang | 内核桥接、Swift 数据契约、文档状态、输入调度边界、快照投影与发布、组件注册、Context、原生渲染、绑定、动作与异步生命周期 |
| 组件库 | SwiftOpenUI、SwiftIntelligentUI | OpenUI 与 OpenIntelligentUI 各自的组件目录、设计系统、布局、媒体呈现、特有函数及模型生成契约 |

### 内核必须保持的约束

| 约束 | 要求 |
| --- | --- |
| 输入完整 | 现有输入入口保留全部 UTF-16 内容与顺序，完成和停止分别处理尾部，换源后旧解析状态失效 |
| 单一状态所有者 | 每份文档只有一个可写 Store；UI 快照是只读投影，组件通过 Context 发出写入与动作 |
| 提交一致 | 同一可见提交的 root、readiness、字段与执行状态来自同一有效更新；旧计算不能覆盖较新的提交 |
| 局部更新 | 数据或交互状态没有变化的稳定节点应避免重复投影和 body 工作；字段编辑不能因无关更新重置 |
| 副作用有效 | 工具调用和外部动作在有效状态及预算检查之后发生；等待结束后重新核对所属文档和请求 |
| 工作有界 | 输入、计算、原生投影、排队和整条动作计划分别有边界；正常合法输入也要控制累计工作量 |
| 恢复确定 | 失败保留最后一次有效呈现并停止该轮执行；替换或 reset 能恢复，等待者能结束 |

上表定义目标契约，不表示全部已经实现。当前实现与后续落地范围在第 3 节分别标明；验收结果只记录在[验证说明](validation-and-security.md#4-内核稳定性审查与当前验收状态)。

### 产品与依赖

根 Swift Package 名为 openui-swift-sdk。库产品使用短横线，Swift 模块使用标识符；名称映射只维护这一份，不提供旧名转发：

| 库产品 | import / target | 源码与测试目录 |
| --- | --- | --- |
| swift-lang | SwiftLang | Sources/SwiftLang、Tests/SwiftLangTests |
| swift-ui | SwiftOpenUI | Sources/SwiftOpenUI、Tests/SwiftOpenUITests |
| swift-intelligent-ui | SwiftIntelligentUI | Sources/SwiftIntelligentUI、Tests/SwiftIntelligentUITests |

SwiftUI 始终指 Apple 系统框架，不能作为本项目模块名。Gallery 中的产品仍称 OpenUI / OpenIntelligentUI；OpenUILibrary、OpenUIState、OpenUIView 是共享的 OpenUI 协议 API，不是另外三个包。COpenUIRegExp 是内部 C target。

~~~mermaid
flowchart TB
    App["宿主 App / Agent 通信"]
    UI["SwiftOpenUI · OpenUI 组件"]
    IUI["SwiftIntelligentUI · OpenIntelligentUI 组件"]
    Lang["SwiftLang · Swift/SwiftUI 适配"]
    Engine["lang-core · JavaScriptCore"]
    App --> UI
    App --> IUI
    App --> Lang
    UI --> Lang
    IUI --> Lang
    Lang --> Engine
~~~

两套 UI 只依赖 SwiftLang，互不依赖。SwiftLang 不导入任一组件库，不按具体组件名选择实现。宿主可以只使用适配层注册自己的组件，也可以只调用解析/契约 API；SwiftLang 本身是 Apple 平台适配产品，包含 SwiftUI 宿主，不承诺无 UI 框架的独立 Swift 模块。

## 2. 源码与目录所有权

| 目录 | 职责与边界 |
| --- | --- |
| Sources/SwiftLang/Language/ | 语言数据类型与桥接、解析/求值门面、Store/Query 适配、原生动作执行、UTF-16 与对象身份、序列化和执行预算；此目录不导入 SwiftUI/UIKit/AppKit |
| Sources/SwiftLang/Runtime/ | OpenUILibrary、OpenUIState、OpenUIView、无主题的 SwiftLangView、注册表、递归渲染、Context、绑定、身份与生命周期，以及通用资源/媒体基础设施 |
| Sources/SwiftLang/Resources/ | 固定版本 JS bundle、manifest 和许可；应用运行时不下载代码 |
| Sources/SwiftOpenUI/Catalog/ | OpenUI 组件注册、固定上游目录与原生绑定，从实际定义导出契约 |
| Sources/SwiftOpenUI/Components/、Theme/、Context/、Internal/ | OpenUI 的视觉、控件、布局、文本/媒体、主题与呈现策略 |
| Sources/SwiftIntelligentUI/Catalog/、Generation/ | OpenIntelligentUIComponents、组件参数、reader/writer、Prompt、manifest 和组件生成诊断 |
| Sources/SwiftIntelligentUI/Components/ | Layout、Content、Controls、DataDisplay、Media 五类组件定义与原生实现 |
| Sources/SwiftIntelligentUI/DesignSystem/、Functions/、Internal/、Resources/ | 该库的设计 token、阅读规则、固定计算函数、媒体/公式适配、本地化与许可 |
| Tests/SwiftLangTests/、SwiftOpenUITests/、SwiftIntelligentUITests/ | 对应公开模块的测试；适配层测试可不链接两套组件库 |
| Examples/Gallery/ | 通过三个公开产品接入的独立原生 App；案例、图片、导航和模拟工具不进入 SDK |
| Tools/ | 契约导出、资源生成、来源锁定和边界检查 |
| Benchmarks/、Validation/、Fixtures/ | 性能工作负载、静态/模型评测、固定语言输入与参考预期 |
| docs/、outputs/ | 文档；已忽略的本地生成及验收材料 |

源码只有根 Sources 中的一份，不增加嵌套 SDK、旧模块软链接或同名源码副本。Gallery、ContractExport、LanguageRuntime 各自持有开发包，通过根 SDK 的公开产品接入。

OpenUI 的文字实现在 `Components/Text`，列表、卡片、Modal 按组件族归位；图表组合、数据解释、几何计算和绘制分别维护，继续共享原组件状态与注册入口。`Internal/NativeValue` 只做通用值读取，控件不借用图表辅助类型。组件拆文件不新增模块或状态所有者。

### Swift 适配层的内部职责

Language 中的文件按调用职责组织，语言语义由单一内核维护：

- ProtocolTypes、OpenUIString、ReferenceValues、ValueConversion、JSSemantics：公开数据契约、顺序、UTF-16、引用身份与类型投影。
- SharedCore：串行 JavaScriptCore 环境、JS 对象/回调、资源加载与值投影；LibraryBridge：authoring、Schema 传输及每份 LibrarySchema 的 JS library 准备。
- Parser、StreamingParser：批量与增量入口，各自的公开工厂与实现在同一文件；Message 只负责传输帧选择，普通 Lang 不进入选帧分支。原始输入与选中内容分别检查，流式适配只保留原始输入、增量包络及是否需要恢复全文的标志。
- Lexer、Evaluator、Store、Library、Prompt、Serialize、Merge、Forms、MCP：对内核实现的类型化调用。运行主线的错误与预算沿所属入口交付；低层工具保留各自公开返回合同，其覆盖边界见验证说明，不将所有公开 helper 都描述为受限执行事务。
- QueryManager、Actions：Swift async 工具、取消与原生动作步骤执行；依赖调度与状态语义由内核管理器负责。
- NativeSourceReadiness：源数据闭合、依赖、数组位置和占位提示；不进入 Lang 值、AST 字段或持久化协议。
- RuntimeLimits、RegExp：原生输入、深度和正则执行预算。

编译后的 LibrarySchema 是只读快照；结构修改通过 Library.extend 后重新编译。文档持有一份不变的函数与动作定义，独立 Evaluator 则持有自己的定义快照；参数描述只准备一次。没有引用默认值的描述可共享 JS 表示，含对象或数组 default 的参数、返回值及动作描述仍每次执行上下文重新编码，保留默认业务值的引用身份。状态读取、函数执行闭包、输入检查、失败观察者及工作预算继续属于各自执行上下文，不缓存函数返回值。Query 只接受声明 AST，由内核管理依赖。JSON 语法和转义使用 JavaScriptCore 的 JSON.parse/stringify。Evaluator 通过 EvaluationContext 读取状态，不额外持有 Store。签名来自实际 LibrarySpec，不维护独立签名生成器、原生 materializer 上下文、可变 schema 编辑器或另一条 Query 请求调度链。

## 3. 唯一的客户端运行链路

1. 宿主选择 OpenUILibrary.openUI() 或 .openIntelligentUI()；自建组件使用 OpenUILibrary(components:)。
2. 同一个 library 提供 systemPrompt、specificationJSON 和 makeState(toolProvider:persistedState:)。
3. 宿主在文档活跃期间稳定持有同一个 OpenUIState，输入完整源码或 push 增量，并明确 complete、interrupt、reset 或替换。
4. State 调用 parser/Store/evaluator，并同步声明 Query；工具、取消和定时器通过 Swift 桥接。
5. OpenUIView(state:library:) 交给同一适配层 renderer，按选定库的注册表构建原生组件。
6. 组件通过 OpenUIComponentContext 读取值、渲染子项、编辑字段和触发动作；业务结果经宿主回填。

不可变的 `OpenUIComponentLibrary` 在首次识别输入或创建文档时编译 reader，随后通过现有内核同步域复用原生 schema 元数据；同一目录创建的多个临时 `OpenUILibrary` 也复用该结果。仅构造 facade、生成提示或读取 spec 不触发这项准备。每份文档仍新建 parser、Store、Query manager，以及保存 prepared JS library 的 `LibrarySchema`；不跨文档共享运行值或执行上下文。扩展库产生新的目录与编译结果，公开可变 `Library.toSchema()` 不做隐式缓存。

客户端入口、调用顺序和业务回调以锁定的 SDK 契约为准。稳定性和性能修复在现有 `push / complete / interrupt` 链路内部完成；不引入另一套流句柄、会话或调度器要求宿主迁移。当前 `push` 保持同步提交语义。

每份文档拥有独立的 parser、Store、查询和 revision/epoch。共享代码及 JS 执行环境不代表共享用户状态。旧文档回调、工具结果和资源结果不得写回替换后的文档。

读代码时按数据所有权跟踪，不把不同用途的对象都当作“状态缓存”：

| 数据 | 唯一所有者 | 交接边界 |
| --- | --- | --- |
| 原始输入与解析进度 | 该文档的 parser / State 输入入口 | 按到达顺序同步处理；只有真实消息帧才能选择 content |
| 可写业务值与 pristine | 内核 Store | 写入先验最终候选；原生规模账本必须反映实际接受的 Store 值 |
| Query 依赖、请求与结果 | 内核 QueryManager 及其原生 Task 适配 | 派发和返回都检查当前请求身份；退休先结束等待，再取消 Task |
| 一次完整的 UI 读取 | NativePresentationCommit | 同步工作及重入队列稳定后交付；只能读取，不能反向覆盖 Store |
| 挂载节点的读取依赖 | NativeComponentSubscription | 每次 render 建立独立作用域，旧作用域不能登记到新 render |
| 资源请求及解码结果 | 请求 Store / 媒体 cache 各自的 owner | 缓存命中和 await 返回都复核取消、generation 与鉴权作用域 |

输入入口负责顺序，执行入口负责值与副作用，呈现入口负责完整快照，组件入口负责实际依赖。任何优化先说明改变哪一条交接边界；没有所有权或失效条件的缓存、revision、广播不进入主线。

### 文档与资源的生命周期

独立的 Lang 文档通常对应独立的 `OpenUIState`，其 parser、Store、Query、源文本、原生呈现和编辑记录随文档存活；所有文档共享一份 JavaScriptCore 执行环境。`OpenUIView` 和 `SwiftLangView` 使用宿主传入的 state，不替宿主分页或淘汰历史消息。离屏不会自动销毁 state，`complete()` 只结束流式输入，已完成文档的 Query、控件和刷新仍可工作。宿主需要控制强持有的活跃文档范围，同时明确历史交互、草稿与恢复策略；SDK 不按可见性擅自暂停工具或清除业务状态。

`snapshotState()` 只读取 Store 的业务值。它可用于 `persistedState:` 或 `restoreState`，并非完整的历史文档 checkpoint，不包含 Query 执行进度、呈现编辑记录、焦点或资源请求，也不提供卸载能力。销毁后用源码和这些值重新创建文档，会重新建立文档执行状态，并可能再次派发 Query；不能用它承诺无副作用的原样恢复。

可重建的已完成资源继续由各文档的资源 Store 和媒体 cache 持有，各自使用一份 `NativeResourceCache` 保存值、成本及访问顺序。共享预算只弱引用非空 cache；不同文档不会因为 URL 相同而共享响应、鉴权状态或请求结果。

| 已完成缓存 | 每份文档上限 | 全 SDK 合计上限 |
| --- | --- | --- |
| 解码图片 | 32 MiB / 8 项 | 64 MiB / 128 项 |
| 原始响应数据 | 2 MiB / 16 项 | 8 MiB / 128 项 |

命中更新访问序号，插入时先满足文档额度，再按所有已登记 cache 中最久未访问的条目满足合计额度。成本与条数同时限制，大于任一允许额度的单项不进入缓存，也不挤掉已有可用条目。全局条数限制同时约束非空 cache 的登记规模，不遍历所有文档或业务对象。

首次使用默认预算时注册一次平台内存压力监听：iOS 接收内存警告，macOS 接收 warning/critical 事件，在 MainActor 上清理这两类已完成缓存。清理不递增文档 generation，不取消 pending 请求，不更换鉴权 scope，不清除已接受的业务值或草稿。正在显示的图片由视图继续持有；后续缓存未命中可重新获取资源，原有高分辨率优先、显式 reload、请求合并和取消规则保持。

原生响应缓存命中与异步完成均按加载器当前的 `maximumResponseBytes` 检查；同一 loader/scope 收紧限额后，旧超限字节通过现有错误通道拒绝。缓存身份、容量与请求合并保持原规则，限额放宽后仍可复用有效条目。

这些上限只覆盖 SDK 已完成缓存中的成本，不覆盖挂载视图保留的图片、在途传输/解码、parser/Store/Query/草稿或 WebKit、MapKit 等系统资源，也不是进程内存上限。清理可能让以后访问旧资源时重新加载。宿主永久保留所有历史 state 的累计成本仍需由消息列表生命周期解决，完整冻结与恢复不是当前接口的能力。

### 求值、发布与外部副作用

`OpenUIState` 最外层同步调用在返回前排空本次重入请求。宿主在同步发布回调中再次调用换源、reset 或状态写入时，重入调用先入队，等当前 setter 完成后顺序执行，防止 `@Published` 的旧赋值覆盖新文档。过期轮次不能继续派发工具或投递解析回调；组件捕获的 revision 在实际执行排队写入时再次验证。这个短队列只处理同步重入，不是分块节流器，也不使解析后台化；宿主不得在每次状态通知中无条件再写入同一状态，队列不替代回声循环的终止条件。

Query 依赖排序由内核管理器拥有。原生首次同步 Query 批次先暂缓 provider，再检查呈现预算；所有 Query 进入 provider 前等待当前同步发布及重入队列完成，已检查批次只复核存活状态，异步结果触发的自动下游派发还要重验 root。请求有效性以已有缓存条目的身份及当前消费者为准；派发前和结果返回后共用同一私有检查。全部消费者移除后，即使出现同名、同 key 的新请求，旧 success、error 和 finally 也不能影响新条目；原发起声明移除但仍有其他消费者时，共享请求继续有效。共享消费者一起更新 loading、错误与刷新状态，成功缓存命中和请求成功使用同一清理规则。dispose 自身建立停止加载的末态快照，不依赖迟到请求收尾。整批声明更新及结果引发的 reader 重算结束后，原生层整批移除过期 pending，先结束全部旧 Promise，再取消对应 Task；这样 provider 的同步取消回调重新请求旧 key 时不会采用仍在途的旧条目，也不依赖 provider 自行返回。缓存 key 的释放也在整批节点更新后按实际引用决定，防止提前取消同批接手的消费者，并清掉连续改参留下的孤儿缓存。它不新增请求调度器，也不能撤回已经进入外部 provider 的工作。

组件回调除了核对文档 revision，还必须解析到当前 live tree 中的目标。同一文档的条件分支或 Query 更新移除控件后，旧 Context 不能继续派发动作或写字段；排队写入在真正执行时再次检查。呈现开关只要求目标仍存在，保留流中关闭的能力；公开 Host 状态写入不要求对应可见控件。已经开始的有效动作可以更新状态并移除自身控件，随后仍按原有动作事务与取消规则执行。

同一 Query 订阅同时最多排队一次 MainActor 呈现更新；执行时读取当前管理器快照，退休订阅的通知失效。这仅合并原生呈现通知，不改变 Query 的依赖执行、provider 请求或动作步骤的业务回调。

工具输入/返回、错误负载、Evaluator 上下文及原生 AST、State 写入/恢复在对应桥接入口检查图大小与深度；不能等整份数据编码或下游派发完成后才拒绝。数组与对象的数据预算检查使用显式帧栈，一次展开一个子值，保留共享图的相对成本缓存与每次出现计费；预算检查本身不依赖异步工作线程能够递归进入全部允许深度。已失效工具请求在扫描数据或读取错误描述之前退出，不能用旧超限结果停止当前文档。MCP 提取先检查原始 JSON，再检查文本块展开后的值；超限通过既有错误渠道拒绝，允许的最大深度标量必须完整保留。Store 写入先检查替换后的整份快照，初始化也先检查最终候选，超限不提交半份状态。内部成本账本只保存规模和 pristine 标记，业务值与通知仍由同一内核 Store 拥有。失败传播到文档的只读末次有效呈现，不能把预算失败产生的 `null` 当业务结果提交。原生 AST、捕获及 readiness 成本比最终 JS 数据图更保守，具体边界见[验证说明](validation-and-security.md#性能证据与未完成项)。

运行期 readiness 是一次求值及具体输出位置的上下文，不属于可共享 Lang 对象的永久状态。parser/native 基础元数据与单次求值覆盖分开；Each 的未闭合状态和 Query 依赖沿自身输出位置传递，不污染其他位置共享的值。投影显式携带本次 snapshot 与位置上下文，缓存同时区分值身份和上下文。原生旧快照不可原地改写；组件外壳闭合也不能跳过其嵌套动作的最新就绪状态。重投影沿用同一 JS 对象的语义身份，不能因为显示就绪状态改变而让 `SameValue`、Store 或 Query 误判为新数据。

动作计划在现有逐步执行链路内累计表达式、原生输入/投影和同步 root 工作，私有 JS 预算入口接收剩余额度，嵌套求值不能重置预算。状态写入仍立即供下一步读取，`onStateUpdate` 与外部事件仍按步骤交付；让步只发生在已完成步骤边界。调用任务取消后不继续下一步；Mutation 的原生等待者独立响应取消和文档退休，不依赖外部 provider 自觉结束。已完成的合法写入和外部效果不伪装成回滚。

两套库始终使用同一个 OpenUILibrary、OpenUIState、OpenUIView、ActionEvent 和组件 Context。产品特有主题、服务和呈现参数使用 OpenUI / OpenIntelligentUI 前缀；不再提供产品专属 State/Event 别名或旧工厂转发入口。

### 失败与正常诊断的区别

执行失败只在所属 parser / evaluator / QueryManager / 文档保存一次原因，以内部 `NativeExecutionFailure` 交接。没有共享 JS realm 的全局“最后错误”，也不靠把所有错误都叫作预算耗尽来阻断后续动作。

| 结果 | 后续行为 |
| --- | --- |
| 正常值 | 按原顺序更新业务值、回调和呈现 |
| 内核已处理的可恢复表达式 / prop 诊断 | 保留官方诊断及替代值语义，例如自定义函数正常抛错后该 prop 为 null；不能一律退休整份文档 |
| 工具业务失败或不存在 | 沿原有 Query / Mutation 错误合同报告；失败的 Mutation 结束其动作计划，不因此退休无关的整份文档 |
| 输入、工作或输出超限 | `.budget` 停止本轮；公开 `nativeLimitExceeded` 为 true |
| 逃出正式运行入口的异常 | `.runtime(OpenUIError)` 停止本轮；明确报告实际运行错误，`nativeLimitExceeded` 仍为 false |

两类停止都关闭后续副作用和控件写入，结束所属等待，保留已经接受的 Store 值及最后有效呈现；不伪装成已回滚已完成步骤。替换或 reset 建立新一轮。初始 Query 批次与异步 reader 重算使用同一失败通道，不能只保护第一次调用。动作表达式失败在写 Store、投递事件及执行下一步之前被检查；普通异常不能被 `undefined` 或 `null` 的桥接返回值掩盖。

运行期错误文本与诊断输出也属于预算边界。宿主自身产生错误描述或执行自定义函数的计算无法被 SDK 抢占；进入 JS/native 投影的负载仍应在所属入口检查。公开 `ActionRuntimeContext.evaluate` 是宿主提供的闭包，其自定义返回值和 `isActive` 语义仍由宿主负责，不能从任意闭包返回的 null 反推出失败。

### 现有入口的性能边界与后续验证

readiness 与 root 由同一次公开 root 发布交付；Query、Mutation、错误和完成状态保留各自现有通知。公开 `$root`、`@Published` 的 willSet 读取语义、逐步 Store 可见性及业务回调顺序均保留。当前仍为 MainActor 同步求值，公开通知没有改成一个新的客户端事务 API。

内部 UI 使用 `NativePresentationCommit`：同步语义工作及公开回调中的重入请求排空后，把 root、readiness、文档 revision、完成/中断/执行状态、Query/Mutation、错误和 Store 的只读原生值一起交付。`SwiftLangView` 只观察该提交。Store 仍只有一个可写所有者；普通数据的只读投影按真实 Store 通知复用，含源元数据的值保守重读。原生发布和节点通知也在同一重入保护内，通知中再次换源会等当前 setter 完成后执行，外层调用返回前继续排空。重入拟合若发生在公开字段的中间 setter 中，内部 lookup 使用仍已提交的树，不借用候选树的 membership。

渲染入口保留公开的 `EnvironmentObject` 解析：每个 `OpenUIComponentHost` 使用离自身最近的 State，允许宿主在嵌套内容中切换文档。轻量 Host 仍接收共享 State 广播，先经过内部输入边界，再做 live lookup、readiness 和 Context 构造；`RenderNode` 也在调用注册 builder 前比较输入。比较检查组件类型、声明身份、partial、完整 readiness 和属性，标量遵守 SameValue，引用属性按原生引用身份判断，不递归比较整棵业务树，不复用或改写 Lang 物化对象。注册表及直接 Host 闭包有内部身份，父级环境、注册闭包及最近 State 的变化仍须到达组件；身份不作为新的视图 `.id`，避免因此重挂载。

每个挂载内容边界持有自己的 `NativeComponentSubscription`，协调器只弱引用它，逐节点发送变化，不再额外发布无人消费的整组广播。读作用域本身就是本次 render 的身份，不再叠加一个仅用于比较的节点 revision；手工构造的 unscoped Context 仍使用原有失效 token。读作用域记录实际读取的表单字段和 Binding 目标；同一次提交只在该节点的呈现输入或已读取值变化时通知它。旧 render 的迟到读取不能把依赖登记到新 render，切换最近 State 时解除旧注册。Store、Query/Mutation、完成/中断、执行资格及文档 revision 变化仍独立影响 readiness；Query/Mutation 比较保留状态、错误全部字段及数据引用/标量的区别。完全相同的已完成 commit 可跳过分发，新挂载节点自行读取当前 commit；发生真实变化时仍需检查已挂载订阅，不承诺消除所有 O(组件数) 工作。ActionSurface、原生字段和 EditableTable 统一通过 Context 记录读取：已有 Host 作用域时直接复用，手工 Context 独立挂载时使用同一个 NativeComponentSubscription 机制。订阅始终属于传入 Context 的原文档，不能被无关的环境 State 重绑；派生 child Context 与再次观察都保留原 sourceRevision。表格通过明确的 form/name 读取登记字段依赖，编辑记录仍由实际挂载的 StateObject 懒创建，未挂载的视图构造不写编辑记录。

Context 的 element 和状态标志是构造时快照；字段与 Binding getter 保留动态读取行为，每次从最新的完整原生提交取值，不读正在提交的 Store。长期持有一个 Context 不等于冻结整个文档。`canInteract`、动作和写入继续在执行时检查当前文档、目标 membership 与 readiness，过期控件不能因旧只读快照仍可交互。若宿主在公开 setter 回调中强制拟合，旧内容仍可显示，而依赖 `canInteract` 的控件/链接可先被安全禁用；不承诺所有交互 gate 与旧显示快照同时切换。公开手工构造的 Context 和 Host 状态读写保留原有即时读取合同；内部只读呈现不是第二个可写 Store，也不新增客户端观察 API。

OpenUI 原生字段的初始化、焦点和校验注册归属于同一个完整的 form/name 身份；换字段时切换字段内容 owner，普通值更新不重建控件。字段的生命周期观察同时交付当前 Context、enabled 与交互就绪快照，初始化和注册使用回调收到的输入，避免沿用上一帧的属性；字段值变化仍由既有验证/镜像路径处理。EditableTable / Slider 按字段身份选择文档已有草稿，未闭合的名字仅有挂载期临时草稿。此边界不修改外层 Context 订阅、RenderNode 或文档身份。Slider 通过弱 Context 使用现有写入路径的内部完成回调：实际 Store 写入通过预算后、公开更新前确认接受值，排队写入仍在执行时复查目标，拒绝明确结束。草稿先更新已提交基线，再仅清理对应编辑，保留绑定转换和同步重入的新输入；原有字段镜像及公开通知顺序不变。字段初始化仍由现有 Store 的缺失检查决定。组件行为与验收见 [OpenUI](openui.md#状态字段与动作) 和[验证说明](validation-and-security.md#sdk-正常接入与生命周期审查)。

live index 继续遍历当前 root，建立 membership 和按当前深度优先顺序排列的候选；相同 root 引用可跳过重复索引。匿名且仅含标量属性的旧节点按属性分桶，具名/复杂节点保留原分组及语义/readiness 歧义检查。索引直接替换当前 membership 和候选，仅累计生产刷新使用的呈现变化键，不维护另一份无人消费的 lookup 变化集合：仅当同键候选唯一、属性全为标量且完整呈现输入相同时，重建的元素包装可以保持呈现不变并跳过该订阅的 lookup/readiness capture。membership 仍立即换成实际新对象；字段、Query、执行资格及文档变化独立触发复核。引用属性和歧义候选继续保守检查，不递归比较业务值，也不保留历史图的引用账本。旧快照查找单次遍历候选并检查语义及歧义，不再创建匹配数组或把首候选的 readiness 与自身递归比较；属性遍历仍保留原深度边界。当前内核在普通文字流中仍重建内容稳定的 JS 节点，不能假设存在可复用的原生子树；没有保留依赖该假设的容器 DAG 缓存。真实流仍可能全量索引和检查全部挂载订阅。全局 partial、引用属性及真实 Store/Query 变化仍可更新多个组件，收益须以原生工作计数和实际挂载结果验证。

原始输入先受 UTF-16 上限约束。语句/token/嵌套/操作符检查直接使用同一解析器已产生的 token，在 Pratt 递归前执行；流式已完成语句持有累计账目，重复声明也计入，pending 只检查当前尾部。前缀失效、set 或 reset 按解析器自身的缓存生命周期清账。旧的整份源码二次 preprocess/tokenize/split 预检已删除，没有保留并行保护路径或放宽额度。多行三元式的换行前瞻在同次 split 内复用终点。

源码清理也属于同一个 parser 的进度。批量 preprocess、流式 preprocess 和公开 stripFences 共用一套行级规则；已消费的完整行不在下一分片重扫，只预览尚未完成的行，并保留原始输入 trim、引号、转义、注释及围栏选择语义。输出返回精确的变化起点，围栏选择或尾行变化触及已完成语句时才使该前缀缓存失效；set/reset 同时重建清理状态。无围栏的公开 stripFences 继续直接返回输入。待完成长行仍可能反复扫描，这不是整条 push 已变成仅与新分片大小有关的保证。

已完成且完全不含符号、State、运行时引用或占位符的 AST，只弱缓存其闭合事实与树高，用于省略重复 readiness 和空 Query 依赖检查；深别名路径仍检查原有深度边界。物化值、诊断、默认值和自定义函数结果不跨分片复用；同轮别名共享、跨轮新对象、全局 partial 和每轮诊断仍保持原语义。

patch 在去空白、拆句或合并前检查每项原始 existing、patch 和 rootId 输入；合并中的词法分配、拆句、表达式递归、引用遍历、删除扫描和输出共用一次工作预算。底层 `mergeStatements` 使用标准 Swift `throws` 报告 `MergeStatementsError.budgetExceeded`，不返回旧文本或部分结果冒充成功；高层 `applyPatch` 的签名及失败/恢复合同不变。失败保留最后有效 root 与 Store，换源或 reset 恢复。

ElementErrorBoundary 以不可变元素快照的身份观察输入，保留同值但 readiness 已改变的最新成功快照；不再调用 Lang 元素的递归值相等。上次成功内容由视图生命周期内的单个引用记录持有，更新该记录不发布第二次视图变化。当前内容和保留内容仍走同一个视图分支，保持挂载身份。

桥接只共享冻结且无依赖的 open/closed readiness 描述，Swift 直接识别这些常量；含 Query、占位、数组位置或输出 scope 的元数据仍完整投影。投影先按对象身份和父 scope 查询本次缓存；跨调用已缓存且不含源元数据的普通对象/数组也直接返回，不请求它们不需要的 metadata。其余值按需一次读取类型、子 scope 身份及元素/动作完整性与 readiness；同一投影内重复边继续复用，带元数据的快照替换不重复标记同一 JS 对象的类型。有序属性键值继续成组读取；键值仍按原始 UTF-16、枚举顺序及引用身份传递，不通过 JSON 往返。最外层串行桥接调用结束时释放临时 autorelease 对象，返回快照持有自身引用；跨调用保留值必须由原生生命周期测试覆盖。没有跨更新复用可能被引用位置修改的 Lang 物化对象。

同次原生呈现批量读取 Query 状态，仅提取一次管理器快照并建立本次错误索引；缺失声明直接退出，批次之外不缓存结果或错误。管理器内部完整 JSON 快照比较仍保留，因为共享默认值可在 provider/listener 或两次调用之间改变。该批量读取处理 Query 呈现成本，不能据此解释无已派发 Query 的持续文本流 CPU。

原生引用值各自持有一枚私有桥接身份记录；SharedCore 只保存 JS 身份到原生对象的弱反查。原生值销毁时按自身记录身份撤销对应反查，不再依赖每 32 次调用扫描全部记录。不同 readiness 快照可继续共享同一 JS 语义身份，旧快照销毁不能删除新快照的映射。JS 操作及记录更新仍由原有串行执行域保护；析构只使用一把保护弱反查字典的短锁，解锁后才释放 JSValue，避免从 JavaScriptCore 回收线程反向等待执行域锁。原生值编码为 JS 数据，不把拥有 JSValue 的原生对象直接导出为 JS 包装对象。未桥接的值不触发 JS 环境初始化，但每个引用值会多持有一枚空记录；净分配与释放成本仍需原生测量。

解析、解析投影、求值上下文、root 求值、原生投影、live index、呈现提交和桥接调用通过内部 Instruments interval 分开记录；OpenUI 的图片解码、后台 Markdown 准备及同步 fallback 解析沿用同一个 package tracing 工具。tracing 关闭时不创建 interval，也不记录源码或用户值。原来的 `Bridge cleanup` 全表扫描区间已随该路径删除。基准同时保留 p95、最大值和最慢分片位置，以识别整树增长与长调用。整 root 求值/投影仍存在，没有认定 80–100ms 长尾来自 GC，也没有宣布长尾已修复。重入队列、预算、缓存及通知收敛不等于流畅度已验收；实际效果仍由相同输入的 Release 及 App 回放验证。

**输入与完成。** `push` 接收内容后仍同步更新。Lang 入口使用一次增量传输探测，仅将原始 Lang 引号/转义/行注释之外的首次标记视作封包边界；此前的源码作为数据保留。进入封包后，同一个消息解析器继续处理部分消息头和截断重试。公开 `parseMessage` 保留完整协议语义及 context；Lang 入口只投影选中的 content。普通注释和多行字符串内的 marker 不得静默删掉 root。任何内部优化都必须保留精确 UTF-16 内容、到达顺序、已闭合节点可交互以及末尾分块的处理语义。

`complete`、`interrupt` 和换源继续通过现有入口处理。现有 `push` 只有内容参数，完成后再次调用可以开启新流；调用方沿用自身网络请求生命周期，过滤已取消或被替换请求的晚到分块。SDK 内部已退休的工具与资源回调不能借用新文档恢复执行，不为区分网络来源新增流句柄。

| 事件 | 调度与提交要求 |
| --- | --- |
| 普通增量 | 保留同步更新、内容和顺序；优化不能悄悄延迟公开调用的可观察结果 |
| complete | 处理此前接收的全部内容后完成解析，不丢最后一个 token |
| interrupt | 停止自动/延迟工具派发，保留此前已接收内容的未完成语义；已闭合节点的操作继续按 readiness 判断。不能隐式 complete，也不能靠等待外部 provider 返回才结束 |
| 替换或 reset | 退休旧计算及异步回调。reset 清理业务状态及草稿；换源按现有 Store 保留/初始化规则处理业务状态，并建立新的呈现草稿生命周期 |
| 输入或计算超限 | 停止该轮排队与执行，保留最后有效呈现，向调用方报告失败并结束等待 |

**计算所有权与提交。** parser、Store、Query 和 JS 值由一个串行执行域拥有，UI 只读不可变原生投影；这是同一权威状态的读模型。每份候选关联文档身份及当前同步更新，过期工作不能覆盖新结果。公开 Published 与业务回调保持既有顺序；内部呈现提交在这些同步工作稳定后形成，root、readiness、字段、Query/Mutation 状态及错误来自同一已完成状态。普通 UI 读取不组合不同中间 setter 的值，交互安全检查仍以当前权威状态为准。执行域的后续调整必须一起落实同步返回、回调线程与代次验证，不能只把计算包进后台 Task。

**节点与交互更新。** 节点身份、业务值相等和呈现状态分开判断。变化尾部只使实际依赖它的节点失效；readiness、错误、Query 加载和动作可用性即使不改变 Lang 值也必须送达。输入草稿和焦点按文档及字段身份保留，不从无关的 root 发布反复初始化。视图 body 和布局测量只读取已提交投影，不调用 parser、写 Store 或触发工具。已有同源码重放/尺寸拟合回归不足以证明稳定兄弟隔离，必须增加 body 与投影计数。

**动作计划。** 累计工作预算和步骤间让步已经进入实现，但不能据此推断复杂表单或长计划已无卡顿。后续优化应记录每步求值、Store 变化、root 工作和发布数量，保持状态立即可读、业务回调顺序及取消后的停止语义；不可通过合并掉公开回调来降低计数。

**资源与失败边界。** 执行预算、输入队列、投影缓存和工具等待分别受到约束；保留数据身份不能演变成永久强引用。文档退休、预算失败和请求取消时释放对应任务与回调；正常 complete 只结束输入，有效文档的 Query、刷新、控件及资源回调继续工作。已失效结果只能被丢弃，不能借用新文档恢复执行。直接底层写入及手工构造解析结果的未覆盖入口，要补齐与高层一致的显式失败契约后才能宣称完整保护。用户未提交草稿按生命周期管理，不以任意 LRU 淘汰代替设计。宿主代码自身的计算和忽略取消的外部工作仍不具备抢占保证。

**验证次序。** 先完成修复候选的原生正确性验收，再定位真实 App 的显示更新延迟；使用节点级计数和相同 Release 工作负载确认重复投影、发布与输入扫描的实际成本。执行域调整必须有测量依据，并保留现有宿主函数、回调与读取 API 的契约，不能仅把计算包进后台 Task。验收条件见[内核目标验收](validation-and-security.md#内核目标验收)。

## 4. 适配层、组件与宿主的边界

- 适配层统一拥有运行机制。组件不另建 parser/Store/state，不重复观察整份文档，不绕过 Context 直接派发动作或写入业务状态。
- OpenUIView 只组合宿主传入的 library/state，不在 body、拟合或测量中创建状态、反复提交源码。SwiftLangView 观察完整的只读呈现提交；轻量 OpenUIComponentHost 仍解析并观察最近 OpenUIState，内部内容边界持有节点订阅。两套 UI 的动作表面通过 Context 的现有作用域或独立挂载订阅读取；OpenUI 原生字段及 EditableTable、Intelligent UI 已注册的输入/选择/日期/计时/图表/折叠组件不再额外订阅未使用的整份 State。Intelligent UI 的 Column 阅读锚点与 InlineParagraph 附件宿主仍使用所需的环境 State；轻量注册 Host 与宿主观察也仍存在，不能描述为整棵树只观察一次。尺寸拟合不得产生新的语义更新；真实流式更新的求值、索引和组件刷新范围需单独验证，不能用相同缓冲区的拟合回归替代。
- 组件注册同时提供有序参数、renderer 和结构/身份元数据；公共 renderer 不根据 TabItem 等名字猜测布局、身份或主题。
- 组件库的包内呈现元信息复用类型化存储，随 renderer 保存在注册表中，与 Context 继承值和 Lang schema 分开。替换或删除 renderer 同时清除其元信息；保留 renderer 的定义扩展保留元信息；注册变更继续使用既有 renderRevision。SwiftLang 只负责存取和生命周期，具体尺寸约定、策略与算法属于组件库。
- typed OpenUIContextValues 是通用扩展容器。主题、阅读宽度、占位视觉、图表颜色、媒体比例和动画规则由各组件库定义。
- 通用资源 Context 管理地址、宿主 loader、鉴权作用域和文档生命周期；SwiftLang 的共享基础设施负责原生资源请求、图片解码和缓存预算。占位、裁剪、重试、预览和地图交互由所属组件库决定。原生图片通道的保证不扩展到 WebKit、Markdown 或 MapKit 的所有网络请求。
- OpenIntelligentUI 的地图筛选、内部点位卡片、选中、全览与原生展开由 Map 自身管理；场景不补建另一套基本交互，组件不虚构导航或业务结果。
- 宿主负责模型/Agent/工具通信、账号权限、消息列表、滚动、业务数据、交易与真实操作结果。Gallery 的模拟工具与动作记录不代表远程业务成功。

OpenUI 的 `NativeRemoteImage` 只提交布局完成后的显示像素需求；它不构造新的资源调度器，也不从测量路径请求图片。加载占位和成功图片共用挂载边界外层的同一个尺寸观察，避免退休内容分支的延迟出现回调覆盖最新画幅。既有 `NativeMediaCache` 持有合并中的加载、取消、有限暂时失败恢复和解码结果，通用 ImageIO 解码根据源比例与 EXIF 决定 fit/fill 需要的最长边。已解码结果和在途键核对冻结的资源策略，不能在限制变化后借用旧预算。显示尺寸改变不改变宿主已经冻结的签名请求；自动恢复在同一个合并工作内进行，显式用户重试才建立新请求。资源预算和 HTTP 状态沿既有 URLError 附加诊断数据，不保留完整响应、地址或凭据。组件占位、预览、实际尺寸及失败后的交互规则仍由 OpenUI 定义，详见其[媒体说明](openui.md#文本媒体与原生差异)。本轮不调整 SwiftIntelligentUI 的独立图片通道。

OpenUI 的 Markdown document 继续只有一个正在准备的请求和一个可替换的最新输入。首次后台结果未返回时，追加输入复用可读同步前缀，已完成的后台中间结果仍持续交付；纠正、配置变化和退休使用同一 generation 失效。同步 fallback 仍负责首次及不能复用既有内容的读取，不引入新的文本状态所有者、Markdown worker 或延迟语言提交的机制。 有效后台结果覆盖现有 fallback 后释放该同步解析树及其源码；若 body 已提前读取另一次纠正，则保留尚未被该结果覆盖的新 fallback。

reader 提供读取契约，writer 提供当前生成范围。两者从同一注册来源派生，不能维护第二份手写权威 schema。组件名、参数顺序、枚举与绑定属于输入契约；收敛 Swift 包/API 名称不等于改写已存 Lang 程序。两套产品的组件语法分别维护，不通过替换组件名假定互换。

## 5. 依赖来源、原生适配与语言版本

实际来源以 [Tools/upstream.json](../Tools/upstream.json)、[资源 manifest](../Sources/SwiftLang/Resources/core-manifest.json) 和 [适配清单](../Tools/Core/adaptations.json) 为准。构建提取锁定来源的源码，核对原始源码树、显式补丁及生成指纹；客户端不安装 npm 包或追踪 latest。

Swift 负责 lossless 数据传输、原生 async 与动作执行。当前还保留有来源记录的 readiness 注入、serializer 修复、依赖 schema 表示适配与执行预算。这些 Apple 适配随依赖升级逐项复核，使用固定回归和独立语义检查验证兼容性。Query 请求身份、共享消费者和退休清理的构建转换归 `bridge-compat.mjs`，预算转换归 `compat.mjs`；`build.mjs` 明确执行顺序。

### 语言版本与参考规范

运行资源为 lang-core 1.1.1。docs/language 下 Overview、Language、Prompt 标注的 1.0 是保留的规范参考，与版本化 fixtures 对应，不是当前运行版本。模型生成使用所选库当前导出的 Prompt/spec。1.1.1 的 Query 依赖、失败重试、表达式默认值和数组数学行为，以及原生预算和对照验证范围，统一记录在 [验证说明](validation-and-security.md#3-语言版本与验证边界)。

## 6. 文档与验证维护

架构、目录、职责和依赖只在本文维护。README 负责安装与公共接入；两套组件指南负责本库 API/视觉规则；验证文档负责命令、资源来源、安全与证据边界。AGENTS.md 仅保存工作规则和这些入口，不复制职责表。生成资源、版本和哈希由工具/锁文件负责，不在多处手填。

架构变化需同步 Package、真实源码、独立消费者、目录检查、工具、Gallery 和文档引用。源码检查、Swift 编译、XCTest、原生交互、性能及真实模型评测分别报告；任一项通过都不能替代其他项。验收命令和依赖审计以 [验证说明](validation-and-security.md) 与 [CI](../.github/workflows/native-sdk.yml) 为入口。
