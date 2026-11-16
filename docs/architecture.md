# 架构

文档版本：1.5 · 更新日期：2026-11-16

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

### Swift 适配层的内部职责

Language 中的文件按调用职责组织，语言语义由单一内核维护：

- ProtocolTypes、OpenUIString、ReferenceValues、ValueConversion、JSSemantics：公开数据契约、顺序、UTF-16、引用身份与类型投影。
- SharedCore、LibraryBridge：串行 JavaScriptCore 环境、JS 对象/回调、资源加载与 authoring 传输。
- API、Lexer、Parser、StreamingParser、Evaluator、Store、Library、Prompt、Serialize、Merge、Message、Forms、MCP：对内核实现的类型化调用。
- QueryManager、Actions：Swift async 工具、取消与原生动作步骤执行；依赖调度与状态语义由内核管理器负责。
- NativeSourceReadiness：源数据闭合、依赖、数组位置和占位提示；不进入 Lang 值、AST 字段或持久化协议。
- RuntimeLimits、RegExp：原生输入、深度和正则执行预算。

编译后的 LibrarySchema 是只读快照；结构修改通过 Library.extend 后重新编译。Query 只接受声明 AST，由内核管理依赖。JSON 语法和转义使用 JavaScriptCore 的 JSON.parse/stringify。Evaluator 通过 EvaluationContext 读取状态，不额外持有 Store。签名来自实际 LibrarySpec，不维护独立签名生成器、原生 materializer 上下文、可变 schema 编辑器或另一条 Query 请求调度链。

## 3. 唯一的客户端运行链路

1. 宿主选择 OpenUILibrary.openUI() 或 .openIntelligentUI()；自建组件使用 OpenUILibrary(components:)。
2. 同一个 library 提供 systemPrompt、specificationJSON 和 makeState(toolProvider:persistedState:)。
3. 宿主长期持有每份文档的 OpenUIState，输入完整源码或 push 增量，并明确 complete、interrupt、reset 或替换。
4. State 调用 parser/Store/evaluator，并同步声明 Query；工具、取消和定时器通过 Swift 桥接。
5. OpenUIView(state:library:) 交给同一适配层 renderer，按选定库的注册表构建原生组件。
6. 组件通过 OpenUIComponentContext 读取值、渲染子项、编辑字段和触发动作；业务结果经宿主回填。

客户端入口、调用顺序和业务回调以锁定的 SDK 契约为准。稳定性和性能修复在现有 `push / complete / interrupt` 链路内部完成；不引入另一套流句柄、会话或调度器要求宿主迁移。当前 `push` 保持同步提交语义。

每份文档拥有独立的 parser、Store、查询和 revision/epoch。共享代码及 JS 执行环境不代表共享用户状态。旧文档回调、工具结果和资源结果不得写回替换后的文档。

### 求值、发布与外部副作用

`OpenUIState` 最外层同步调用在返回前排空本次重入请求。宿主在同步发布回调中再次调用换源、reset 或状态写入时，重入调用先入队，等当前 setter 完成后顺序执行，防止 `@Published` 的旧赋值覆盖新文档。过期轮次不能继续派发工具或投递解析回调；组件捕获的 revision 在实际执行排队写入时再次验证。这个短队列只处理同步重入，不是分块节流器，也不使解析后台化；宿主不得在每次状态通知中无条件再写入同一状态，队列不替代回声循环的终止条件。

Query 依赖排序由内核管理器拥有。原生首次同步 Query 批次先暂缓 provider，再检查呈现预算；所有 Query 进入 provider 前等待当前同步发布及重入队列完成，已检查批次只复核存活状态，异步结果触发的自动下游派发还要重验 root。请求有效性以已有缓存条目的身份及当前消费者为准；派发前和结果返回后共用同一私有检查。全部消费者移除后，即使出现同名、同 key 的新请求，旧 success、error 和 finally 也不能影响新条目；原发起声明移除但仍有其他消费者时，共享请求继续有效。共享消费者一起更新 loading、错误与刷新状态，成功缓存命中和请求成功使用同一清理规则。dispose 自身建立停止加载的末态快照，不依赖迟到请求收尾。整批声明更新及结果引发的 reader 重算结束后，原生层整批移除过期 pending，先结束全部旧 Promise，再取消对应 Task；这样 provider 的同步取消回调重新请求旧 key 时不会采用仍在途的旧条目，也不依赖 provider 自行返回。缓存 key 的释放也在整批节点更新后按实际引用决定，防止提前取消同批接手的消费者，并清掉连续改参留下的孤儿缓存。它不新增请求调度器，也不能撤回已经进入外部 provider 的工作。

组件回调除了核对文档 revision，还必须解析到当前 live tree 中的目标。同一文档的条件分支或 Query 更新移除控件后，旧 Context 不能继续派发动作或写字段；排队写入在真正执行时再次检查。呈现开关只要求目标仍存在，保留流中关闭的能力；公开 Host 状态写入不要求对应可见控件。已经开始的有效动作可以更新状态并移除自身控件，随后仍按原有动作事务与取消规则执行。

同一 Query 订阅同时最多排队一次 MainActor 呈现更新；执行时读取当前管理器快照，退休订阅的通知失效。这仅合并原生呈现通知，不改变 Query 的依赖执行、provider 请求或动作步骤的业务回调。

工具输入/返回、错误负载、Evaluator 上下文及原生 AST、State 写入/恢复在对应桥接入口检查图大小与深度；不能等整份数据编码或下游派发完成后才拒绝。已失效工具请求在扫描数据或读取错误描述之前退出，不能用旧超限结果停止当前文档。MCP 提取先检查原始 JSON，再检查文本块展开后的值；超限通过既有错误渠道拒绝，允许的最大深度标量必须完整保留。Store 写入先检查替换后的整份快照，初始化也先检查最终候选，超限不提交半份状态。内部成本账本只保存规模和 pristine 标记，业务值与通知仍由同一内核 Store 拥有。失败传播到文档的只读末次有效呈现，不能把预算失败产生的 `null` 当业务结果提交。原生 AST、捕获及 readiness 成本比最终 JS 数据图更保守，具体边界见[验证说明](validation-and-security.md#性能证据与未完成项)。

运行期 readiness 是一次求值及具体输出位置的上下文，不属于可共享 Lang 对象的永久状态。parser/native 基础元数据与单次求值覆盖分开；Each 的未闭合状态和 Query 依赖沿自身输出位置传递，不污染其他位置共享的值。投影显式携带本次 snapshot 与位置上下文，缓存同时区分值身份和上下文。原生旧快照不可原地改写；组件外壳闭合也不能跳过其嵌套动作的最新就绪状态。重投影沿用同一 JS 对象的语义身份，不能因为显示就绪状态改变而让 `SameValue`、Store 或 Query 误判为新数据。

动作计划在现有逐步执行链路内累计表达式、原生输入/投影和同步 root 工作，私有 JS 预算入口接收剩余额度，嵌套求值不能重置预算。状态写入仍立即供下一步读取，`onStateUpdate` 与外部事件仍按步骤交付；让步只发生在已完成步骤边界。调用任务取消后不继续下一步；Mutation 的原生等待者独立响应取消和文档退休，不依赖外部 provider 自觉结束。已完成的合法写入和外部效果不伪装成回滚。

两套库始终使用同一个 OpenUILibrary、OpenUIState、OpenUIView、ActionEvent 和组件 Context。产品特有主题、服务和呈现参数使用 OpenUI / OpenIntelligentUI 前缀；不再提供产品专属 State/Event 别名或旧工厂转发入口。

### 现有入口的性能边界与后续验证

readiness 与 root 由同一次 root 发布交付，避免普通分片先后触发两次整 State 广播；公开 `$root` 保留，仅闭合符号造成的 readiness 变化仍会发布。Query、Mutation、错误和完成状态继续使用各自现有通知。当前仍为 MainActor 同步求值和共享 State 观察，不能把这项收敛描述为所有通道已原子化或稳定兄弟已完全隔离。

原始输入先受 UTF-16 上限约束。语句/token/嵌套/操作符检查直接使用同一解析器已产生的 token，在 Pratt 递归前执行；流式已完成语句持有累计账目，重复声明也计入，pending 只检查当前尾部。前缀失效、set 或 reset 按解析器自身的缓存生命周期清账。旧的整份源码二次 preprocess/tokenize/split 预检已删除，没有保留并行保护路径或放宽额度。多行三元式的换行前瞻在同次 split 内复用终点。

patch 在去空白、拆句或合并前检查每项原始 existing、patch 和 rootId 输入；合并中的词法分配、拆句、表达式递归、引用遍历、删除扫描和输出共用一次工作预算。底层 `mergeStatements` 使用标准 Swift `throws` 报告 `MergeStatementsError.budgetExceeded`，不返回旧文本或部分结果冒充成功；高层 `applyPatch` 的签名及失败/恢复合同不变。失败保留最后有效 root 与 Store，换源或 reset 恢复。

桥接只共享冻结且无依赖的 open/closed readiness 描述，Swift 直接识别这些常量；含 Query、占位、数组位置或输出 scope 的元数据仍完整投影。没有跨更新复用可能被引用位置修改的 Lang 物化对象。重入队列、预算、缓存及通知收敛不等于流畅度已验收；实际效果仍由相同输入的 Release 及 App 回放验证。

**输入与完成。** `push` 接收内容后仍同步更新。Lang 入口使用一次增量传输探测，仅将原始 Lang 引号/转义/行注释之外的首次标记视作封包边界；此前的源码作为数据保留。进入封包后，同一个消息解析器继续处理部分消息头和截断重试。公开 `parseMessage` 保留完整协议语义及 context；Lang 入口只投影选中的 content。普通注释和多行字符串内的 marker 不得静默删掉 root。任何内部优化都必须保留精确 UTF-16 内容、到达顺序、已闭合节点可交互以及末尾分块的处理语义。

`complete`、`interrupt` 和换源继续通过现有入口处理。现有 `push` 只有内容参数，完成后再次调用可以开启新流；调用方沿用自身网络请求生命周期，过滤已取消或被替换请求的晚到分块。SDK 内部已退休的工具与资源回调不能借用新文档恢复执行，不为区分网络来源新增流句柄。

| 事件 | 调度与提交要求 |
| --- | --- |
| 普通增量 | 保留同步更新、内容和顺序；优化不能悄悄延迟公开调用的可观察结果 |
| complete | 处理此前接收的全部内容后完成解析，不丢最后一个 token |
| interrupt | 停止自动/延迟工具派发，保留此前已接收内容的未完成语义；已闭合节点的操作继续按 readiness 判断。不能隐式 complete，也不能靠等待外部 provider 返回才结束 |
| 替换或 reset | 退休旧计算及异步回调。reset 清理业务状态及草稿；换源按现有 Store 保留/初始化规则处理业务状态，并建立新的呈现草稿生命周期 |
| 输入或计算超限 | 停止该轮排队与执行，保留最后有效呈现，向调用方报告失败并结束等待 |

**计算所有权与提交。** parser、Store、Query 和 JS 值由一个串行执行域拥有，UI 只读不可变原生投影；这是同一权威状态的读模型。每份候选投影关联文档身份和更新序号，提交前检查当前有效性，过期结果直接退休。root、readiness、字段、Query/Mutation 状态及错误应形成一致的可见提交，再发出外部通知；不能让订阅者组合出不同更新的字段。现有分散 Published 的兼容迁移和同步调用的返回语义必须一起落实，不能只把计算包进后台 Task。

**节点与交互更新。** 节点身份、业务值相等和呈现状态分开判断。变化尾部只使实际依赖它的节点失效；readiness、错误、Query 加载和动作可用性即使不改变 Lang 值也必须送达。输入草稿和焦点按文档及字段身份保留，不从无关的 root 发布反复初始化。视图 body 和布局测量只读取已提交投影，不调用 parser、写 Store 或触发工具。已有同源码重放/尺寸拟合回归不足以证明稳定兄弟隔离，必须增加 body 与投影计数。

**动作计划。** 累计工作预算和步骤间让步已经进入实现，但不能据此推断复杂表单或长计划已无卡顿。后续优化应记录每步求值、Store 变化、root 工作和发布数量，保持状态立即可读、业务回调顺序及取消后的停止语义；不可通过合并掉公开回调来降低计数。

**资源与失败边界。** 执行预算、输入队列、投影缓存和工具等待分别受到约束；保留数据身份不能演变成永久强引用。文档退休、预算失败和请求取消时释放对应任务与回调；正常 complete 只结束输入，有效文档的 Query、刷新、控件及资源回调继续工作。已失效结果只能被丢弃，不能借用新文档恢复执行。直接底层写入及手工构造解析结果的未覆盖入口，要补齐与高层一致的显式失败契约后才能宣称完整保护。用户未提交草稿按生命周期管理，不以任意 LRU 淘汰代替设计。宿主代码自身的计算和忽略取消的外部工作仍不具备抢占保证。

**验证次序。** 先完成修复候选的原生正确性验收，再定位真实 App 的显示更新延迟；使用节点级计数和相同 Release 工作负载确认重复投影、发布与输入扫描的实际成本。执行域调整必须有测量依据，并保留现有宿主函数、回调与读取 API 的契约，不能仅把计算包进后台 Task。验收条件见[内核目标验收](validation-and-security.md#内核目标验收)。

## 4. 适配层、组件与宿主的边界

- 适配层统一拥有运行机制。组件不另建 parser/Store/state，不重复观察整份文档，不绕过 Context 直接派发动作或写入业务状态。
- OpenUIView 只组合宿主传入的 library/state，不在 body、拟合或测量中创建状态、反复提交源码。当前 SwiftLangView 与各 OpenUIComponentHost 都观察同一个 OpenUIState，尚不能描述为只在公共 host 观察一次。尺寸拟合不得产生新的语义更新；真实流式更新的求值、索引和组件刷新范围需单独验证，不能用相同缓冲区的拟合回归替代。
- 组件注册同时提供有序参数、renderer 和结构/身份元数据；公共 renderer 不根据 TabItem 等名字猜测布局、身份或主题。
- typed OpenUIContextValues 是通用扩展容器。主题、阅读宽度、占位视觉、图表颜色、媒体比例和动画规则由各组件库定义。
- 通用资源 Context 管理地址、宿主 loader、鉴权作用域、预算和文档生命周期。各 UI 的图片缓存/解码、占位、重试、预览和地图交互保持在所属组件库。原生图片通道的保证不扩展到 WebKit、Markdown 或 MapKit 的所有网络请求。
- OpenIntelligentUI 的地图筛选、内部点位卡片、选中、全览与原生展开由 Map 自身管理；场景不补建另一套基本交互，组件不虚构导航或业务结果。
- 宿主负责模型/Agent/工具通信、账号权限、消息列表、滚动、业务数据、交易与真实操作结果。Gallery 的模拟工具与动作记录不代表远程业务成功。

reader 提供读取契约，writer 提供当前生成范围。两者从同一注册来源派生，不能维护第二份手写权威 schema。组件名、参数顺序、枚举与绑定属于输入契约；收敛 Swift 包/API 名称不等于改写已存 Lang 程序。两套产品的组件语法分别维护，不通过替换组件名假定互换。

## 5. 依赖来源、原生适配与语言版本

实际来源以 [Tools/upstream.json](../Tools/upstream.json)、[资源 manifest](../Sources/SwiftLang/Resources/core-manifest.json) 和 [适配清单](../Tools/Core/adaptations.json) 为准。构建提取锁定来源的源码，核对原始源码树、显式补丁及生成指纹；客户端不安装 npm 包或追踪 latest。

Swift 负责 lossless 数据传输、原生 async 与动作执行。当前还保留有来源记录的 readiness 注入、serializer 修复、依赖 schema 表示适配与执行预算。这些 Apple 适配随依赖升级逐项复核，使用固定回归和独立语义检查验证兼容性。

### 语言版本与参考规范

运行资源为 lang-core 1.1.1。docs/language 下 Overview、Language、Prompt 标注的 1.0 是保留的规范参考，与版本化 fixtures 对应，不是当前运行版本。模型生成使用所选库当前导出的 Prompt/spec。1.1.1 的 Query 依赖、失败重试、表达式默认值和数组数学行为，以及原生预算和对照验证范围，统一记录在 [验证说明](validation-and-security.md#3-语言版本与验证边界)。

## 6. 文档与验证维护

架构、目录、职责和依赖只在本文维护。README 负责安装与公共接入；两套组件指南负责本库 API/视觉规则；验证文档负责命令、资源来源、安全与证据边界。AGENTS.md 仅保存工作规则和这些入口，不复制职责表。生成资源、版本和哈希由工具/锁文件负责，不在多处手填。

架构变化需同步 Package、真实源码、独立消费者、目录检查、工具、Gallery 和文档引用。源码检查、Swift 编译、XCTest、原生交互、性能及真实模型评测分别报告；任一项通过都不能替代其他项。验收命令和依赖审计以 [验证说明](validation-and-security.md) 与 [CI](../.github/workflows/native-sdk.yml) 为入口。
