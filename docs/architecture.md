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
| 输入完整 | 分块合并保留全部 UTF-16 内容与顺序，完成和停止分别处理尾部，换源后旧缓冲失效 |
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
| Examples/ReactNative/ | 私有 RN 验证工程；共享官方 JS 运行时与现有 OpenUI 目录的派生契约，范围与平台边界见第 7 节 |
| Tools/ | 契约导出、资源生成、来源锁定和边界检查 |
| Benchmarks/、Validation/、Fixtures/ | 性能工作负载、静态/模型评测、固定语言输入与参考预期 |
| docs/、outputs/ | 文档；已忽略的本地生成及验收材料 |

Swift SDK 源码只有根 Sources 中的一份，不增加嵌套 SDK、旧模块软链接或同名源码副本。Gallery、ContractExport、LanguageRuntime 各自持有开发包，通过根 SDK 的公开产品接入。

### Swift 适配层的内部职责

Language 中的文件按调用职责组织，语言语义由单一内核维护：

- ProtocolTypes、OpenUIString、ReferenceValues、ValueConversion、JSSemantics：公开数据契约、顺序、UTF-16、引用身份与类型投影。
- SharedCore、LibraryBridge：串行 JavaScriptCore 环境、JS 对象/回调、资源加载与 authoring 传输。
- API、Lexer、Parser、StreamingParser、Evaluator、Store、Library、Prompt、Serialize、Merge、Message、Forms、MCP：对内核实现的类型化调用。
- QueryManager、Actions：Swift async 工具、取消与原生动作步骤执行；依赖调度与状态语义由内核管理器负责。
- NativeSourceReadiness：源数据闭合、依赖、数组位置和占位提示；不进入 Lang 值、AST 字段或持久化协议。
- RuntimeLimits、RegExp：原生输入、深度和正则执行预算。

编译后的 LibrarySchema 是只读快照；结构修改通过 Library.extend 后重新编译。Query 只接受声明 AST，由内核管理依赖。JSON 语法和转义使用 JavaScriptCore 的 JSON.parse/stringify。Evaluator 通过 EvaluationContext 读取状态，不额外持有 Store。签名来自实际 LibrarySpec，不维护独立签名生成器、原生 materializer 上下文、可变 schema 编辑器或另一条 Query 请求调度链。

## 3. Swift 客户端运行链路

1. 宿主选择 OpenUILibrary.openUI() 或 .openIntelligentUI()；自建组件使用 OpenUILibrary(components:)。
2. 同一个 library 提供 systemPrompt、specificationJSON 和 makeState(toolProvider:persistedState:)。
3. 宿主长期持有每份文档的 OpenUIState，输入完整源码或 push 增量，并明确 complete、interrupt、reset 或替换。
4. State 调用 parser/Store/evaluator，并同步声明 Query；工具、取消和定时器通过 Swift 桥接。
5. OpenUIView(state:library:) 交给同一适配层 renderer，按选定库的注册表构建原生组件。
6. 组件通过 OpenUIComponentContext 读取值、渲染子项、编辑字段和触发动作；业务结果经宿主回填。

每份文档拥有独立的 parser、Store、查询和 revision/epoch。共享代码及 JS 执行环境不代表共享用户状态。旧文档回调、工具结果和资源结果不得写回替换后的文档。

### 求值、发布与外部副作用

`OpenUIState` 最外层同步调用在返回前排空本次重入请求。宿主在同步发布回调中再次调用换源、reset 或状态写入时，重入调用先入队，等当前 setter 完成后顺序执行，防止 `@Published` 的旧赋值覆盖新文档。过期轮次不能继续派发工具或投递解析回调；组件捕获的 revision 在实际执行排队写入时再次验证。这个短队列只处理同步重入，不是分块节流器，也不使解析后台化；宿主不得在每次状态通知中无条件再写入同一状态，队列不替代回声循环的终止条件。

Query 依赖排序由内核管理器拥有。原生首次同步 Query 批次先暂缓 provider，再检查呈现预算；所有 Query 进入 provider 前等待当前同步发布及重入队列完成，已检查批次只复核存活状态，异步结果触发的自动下游派发还要重验 root。Query 实例和请求 key 的私有有效性回调拒绝改参、删除与重建后的旧请求，同 key 的有效请求可跨 patch 保留。它不新增请求调度器，也不能撤回已经进入外部 provider 的工作。

工具输入/返回、Evaluator 上下文及原生 AST、State 写入/恢复在对应桥接入口检查图大小与深度；不能等整份数据编码或下游派发完成后才拒绝。失败传播到文档的只读末次有效呈现，不能把预算失败产生的 `null` 当业务结果提交。原生 AST、捕获及 readiness 成本比最终 JS 数据图更保守，边界与仍未统一防护的底层入口见[验证说明](validation-and-security.md#性能证据与未完成项)。

运行期 readiness 是一次求值的上下文，不属于可共享 Lang 对象的永久状态。parser/native 基础元数据与单次求值覆盖分开；投影显式携带本次 snapshot。原生旧快照不可原地改写，带元数据的容器在必要路径上重投影，普通数据保留缓存快径。重投影必须沿用同一 JS 对象的语义身份，不能因为显示就绪状态改变而让 `SameValue`、Store 或 Query 误判为新数据。

两套库始终使用同一个 OpenUILibrary、OpenUIState、OpenUIView、ActionEvent 和组件 Context。产品特有主题、服务和呈现参数使用 OpenUI / OpenIntelligentUI 前缀；不再提供产品专属 State/Event 别名或旧工厂转发入口。

### 执行与呈现的目标设计

以下定义待实现的性能收敛方案。当前仍为 MainActor 同步求值、多个 Published 渠道和共享 State 观察；重入队列及派发前检查已经落到修复候选，但不等于完成了本节的调度、提交与订阅设计。

**输入调度。** 保留现有同步 `push` 契约，合并调度通过显式入口接入。每个显示周期至多提交一次合并后的普通流式呈现；运行中只保留一个计算批次和有上限的待处理输入，避免每个 token 创建一个任务。增量逐块连接，完整缓冲仅在同一文档内且确认为前缀扩展时合并；非前缀替换建立新的文档有效性边界。累计输入包括尚未解析的缓冲，达到上限要明确拒绝，不静默丢块。

complete、interrupt 和换源等边界可立即提交，不受普通帧合并延迟。调度入口必须绑定流的文档句柄，停止或替换后拒绝该句柄的晚到分块。现有裸 `push` 在完成后可以自动开启新流；拒绝旧流迟到输入的保证由带句柄的入口提供，不能靠一个无来源的字符串判断。

| 事件 | 调度与提交要求 |
| --- | --- |
| 普通增量 | 合并未处理内容，保持输入顺序；不因网络分块更细就重复提交完整呈现 |
| complete | 作为顺序屏障，处理该文档此前接收的全部内容后完成解析；不等待下一次显示回调，不丢最后一个 token |
| interrupt | 停止该流的接收与自动/延迟工具派发，保留此前已接收内容的未完成语义；已闭合节点的操作继续按 readiness 判断。不能隐式 complete，也不能靠等待外部 provider 返回才结束 |
| 替换或 reset | 退休旧缓冲、待提交结果和异步回调。reset 清理业务状态及草稿；换源按现有 Store 保留/初始化规则处理业务状态，并建立新的呈现草稿生命周期 |
| 输入或计算超限 | 停止该轮排队与执行，保留最后有效呈现，向调用方报告失败并结束等待 |

**计算所有权与提交。** parser、Store、Query 和 JS 值由一个串行执行域拥有，UI 只读不可变原生投影；这是同一权威状态的读模型。每份候选投影关联文档身份和更新序号，提交前检查当前有效性，过期结果直接退休。root、readiness、字段、Query/Mutation 状态及错误应形成一致的可见提交，再发出外部通知；不能让订阅者组合出不同更新的字段。现有分散 Published 的兼容迁移和同步调用的返回语义必须一起落实，不能只把计算包进后台 Task。

**节点与交互更新。** 节点身份、业务值相等和呈现状态分开判断。变化尾部只使实际依赖它的节点失效；readiness、错误、Query 加载和动作可用性即使不改变 Lang 值也必须送达。输入草稿和焦点按文档及字段身份保留，不从无关的 root 发布反复初始化。视图 body 和布局测量只读取已提交投影，不调用 parser、写 Store 或触发工具。已有同源码重放/尺寸拟合回归不足以证明稳定兄弟隔离，必须增加 body 与投影计数。

**动作计划。** Set/Reset 的业务状态按步骤立即对后续表达式可见，纯写入连续段的 UI 呈现可以合并。Query 同步、外部事件、Mutation 等待和影响后续步骤的宿主回调是需要明确处理的观察边界；边界前检查当前状态与预算。整条计划累计表达式、转换和重复 root 工作，主动调度让步只能发生在合法边界，并在恢复后重查文档有效性。预算失败或 Mutation 失败停止剩余步骤，已完成的合法步骤和已发生的外部效果不被假称为回滚。现有逐步 onStateUpdate 的交付时机不能被悄悄合并，业务回调与 UI 发布的兼容策略需要显式定义和测试。

**资源与失败边界。** 执行预算、输入队列、投影缓存和工具等待分别受到约束；保留数据身份不能演变成永久强引用。文档退休、预算失败和请求取消时释放对应任务与回调；正常 complete 只结束输入，有效文档的 Query、刷新、控件及资源回调继续工作。已失效结果只能被丢弃，不能借用新文档恢复执行。直接底层写入及手工构造解析结果的未覆盖入口，要补齐与高层一致的显式失败契约后才能宣称完整保护。用户未提交草稿按生命周期管理，不以任意 LRU 淘汰代替设计。宿主代码自身的计算和忽略取消的外部工作仍不具备抢占保证。

**落地次序。** 先完成修复候选的原生正确性验收；随后实现有界输入合并与动作呈现合并，保留同步接入和必要观察边界；再用节点级计数验证发布范围收敛。执行域迁移最后实施，基于前面的实测选择调度方式，并同步明确宿主函数、回调与读取 API 的执行域。每一步使用相同 Release 工作负载比较，验收条件见[内核目标验收](validation-and-security.md#内核目标验收)。

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

## 7. React Native 基础验证分支

RN 路线复用官方 React 适配承担跨端 OpenUI 呈现。当前 `Examples/ReactNative/` 私有 Expo 工程已接入完整 OpenUI 的 87 个定义（含数据子项），OpenIntelligentUI 暂不接入；根 Swift Package 仍只有原有三个公开产品，不发布新 SDK。同步 main 时只选取 RN 实际依赖的 OpenUI 契约、资源和示例，不整条合入 Swift 运行时。组件外观、字段行为和性能的完成程度以 [OpenUI](openui.md#react-native-openui-组件) 与[验证说明](validation-and-security.md#5-react-native-基础验证)为准。

### 运行链路与所有权

~~~mermaid
flowchart TB
    Host["宿主：传输、历史、业务动作"] --> Message["消息适配：输入、epoch、恢复快照"]
    Message --> Runtime["官方 react-lang / lang-core"]
    Catalog["现有 OpenUI 组件目录"] --> Registry["派生契约 + RN renderer 注册"]
    Registry --> Runtime
    Runtime --> Shared["共享 RN 组件与视觉 token"]
    Shared --> IOS["iOS 平台组件"]
    Shared --> Android["Android 平台组件"]
~~~

| 代码位置 | 唯一职责 |
| --- | --- |
| `src/runtime/message.ts` | 宿主消息记录、完整源码、输入合并、流句柄与 epoch、可序列化字段快照；不解析、不求值、不建立 Store |
| `src/runtime/OpenUIDocument.tsx`、`interaction.tsx` | 连接消息记录与官方 Renderer，按实际文档句柄及 library 身份隔离挂载，恢复字段，在回调执行时拒绝退休文档的交互；根错误边界保留宿主页面 |
| `@openuidev/lang-core` / `@openuidev/react-lang` | 同一份 JS 环境中的语言语义、parser、Store、React 绑定与组件分发；每个挂载文档的 Store 由官方 Renderer 拥有 |
| `scripts/catalog.mjs`、`src/library/schema.ts`、`contract.ts`、`catalogPrompt.ts` | 从已有 OpenUI catalog 与完整导出契约派生 87 定义，恢复 Zod 参数、递归组件引用和绑定标记；保留源目录的位置签名并使用官方 prompt generator。同一 authoring 路径支持 RN 注册及无 React Native 依赖的宿主契约导出 |
| `src/library/components.tsx`、`components/`、`theme.ts` | 注册与实现布局、完整表单、内容/卡片、图表/表格、地图和 SVG；使用官方状态/动作 hooks，不维护第二个 Lang Store。资源、地图样式与主题通过 Provider 由宿主覆盖 |
| `src/platform/*.ios.tsx`、`*.android.tsx` | 同一组件契约的不同平台呈现；当前用 Button 验证平台文件选择 |
| `App.tsx`、`src/demo/`、`src/fixture.ts` | 离线 Gallery、有限消息历史、传输回放与生命周期检查；FlatList 的宿主记录拥有 controller，滚动离屏不取消传输。原固定 fixture 保留 |
| `scripts/export-contract.ts` | 在普通 Node 进程导出当前启用组件的 schema、prompt 与来源/内容哈希；不初始化 React Native 或运行文档 |
| `src/index.ts` | 私有工程的接入入口，不建立新发布包或另一层运行引擎 |

两端共用组件名、参数顺序、枚举、绑定和动作含义。平台差异只改变 renderer；模型无需输出 `IOSButton` 或 `AndroidButton`。当前平台文件仍是 TypeScript / RN 组件，不是 SwiftUI 或 Compose。后续需要现有原生效果时，可通过 Expo 原生模块或 RN Native Component 包装特定 SwiftUI/UIKit、Compose/View 能力；这些包装尚未实现。

### 文档与流生命周期

1. 宿主按消息持有 controller；`begin` 退休旧 epoch 与旧字段，返回只属于该轮的句柄。普通 `append` 保留完整 UTF-16 输入，按显示帧合并发布。完成、中断和超限立即排空此前已接受输入。
2. `OpenUIDocument` 以实际句柄对象及 library 对象的身份作为 React key，避免两个 controller 使用同名消息 ID/epoch 时错误复用 Store。追加输入不换 key；文档、controller 或 library 变更才重建官方 Renderer。一个消息不能同时由 SwiftLang 的 JSC Store 与 RN Store 驱动。
3. 挂载期间官方 Renderer 的 Store 是唯一可写业务状态；`onStateUpdate` 只保存恢复快照，不再建立一套运行时或把快照反复反馈给 `initialState`。wrapper 只对官方重复发送的同一成功快照去重；controller 接收宿主可变对象时仍重新复制。持久化诊断在失败转成功时通过原回调发送 null，与解析诊断独立。
4. `complete` 以 `isStreaming=false` 提交完整尾部。`interrupt` 保留未完成解析模式并冻结预览交互；宿主显示停止状态。该策略尚不具备 Swift readiness 的已闭合节点继续交互语义。
5. 卸载组件不删除宿主记录，重挂载恢复字段值。parser cache、查询状态、焦点、选区、IME 草稿和组件临时状态不在该保证中；不把字段恢复描述成完整运行会话永驻。
6. 原生事件、动作完成和资源回调在执行时检查挂载及当前 epoch，覆盖 `begin` / `interrupt` 已发生但 React 尚未提交新界面的窗口。字段另核对已提交的 form/name/binding 身份与日期面板会话，避免同 epoch 内旧字段回调写进新字段；动作以名称、表单、表达式与条目上下文的语义 key 识别提交会话，A→B→A 不会复活旧回调，旧异步收尾不覆盖当前 pending/error。此检查不取消官方已经执行中的整段 action plan。订阅通知允许同步重入，退订及 dispose 立即使旧订阅失效。
7. fatal Renderer 错误进入 `error`，保留已接收源码及已保存字段；宿主发起新的 `begin` 才恢复。单组件错误仍由官方组件边界负责。永久删除宿主记录时才调用 `dispose`，释放输入、字段、错误和定时发布任务。

当前输入上限为每条消息 256 Ki 个 UTF-16 code unit，包含待发布输入；字段快照限制为 JSON 数据、8192 节点、32 层、64 Ki 文本单位。超限明确失败，不丢弃已经接受的输入，也不把失败等同正常完成。这些是宿主输入/快照边界，不是官方语言运行时的 CPU、深度或动作总预算。

当前只连接本地字段操作与宿主动作，不提供真实 Query/Mutation provider。组件按钮会等待官方 trigger Promise，显示 pending 并拒绝重复触发；上游不会等待宿主 `onAction` 返回的任意 Promise，宿主必须自行处理业务异步失败、取消与幂等。多步骤工具操作的完整会话语义仍需独立接入与验证。

Markdown 语法由固定版本的 marked 提供，RN 层只呈现原生 Text/View/Image；代码 token 由 Prism 提供。静态 Markdown 原生子树隔离无关字段编辑，主题和真实文本更新仍正常生效。组件渲染前检查文本、token 结构与深度上限，超限保留完整纯文本。这个检查不提供 lexer 的抢占式 CPU 预算。JS 解析仍可能占用 JS 执行线程，帧合并只减少提交次数，不代表后台计算或严格的增量复杂度。

图表和 SVG 使用 react-native-svg；地图使用 MapLibre Native，生产样式/瓦片服务由宿主提供。SVG 只接收受限、已验证的 XML，通过原生网络流逐块限制响应，并拒绝活动内容和外部 XML 引用。图表、地图与表格的呈现预算和完整数据访问方式见组件指南，不作为语言引擎预算。

Gallery 最多保留 8 条消息，只有订阅叶子观察源码变化；添加消息、切换主题与视图装卸不重新创建既有 controller。它用 FlatList 虚拟化消息，单条消息内部仍完整呈现其组件树，不承诺无限长文档的内部分块虚拟化。已有 Gallery 照片通过宿主 resolver 和静态 require 复用，Metro 额外观察 Gallery 资源与已有 OpenUI 图标目录，不改官方模块解析入口。

### 接入与后续范围

第一步以完整 RN 页面验证，让该页面拥有内部滚动、键盘与消息布局。现有 iOS App 可随后接入一个 RN 功能页面；逐消息嵌入大量独立 RN 根视图的尺寸与生命周期成本尚未评估。

OpenUI 与 OpenIntelligentUI 保持平级组件库，各自拥有契约与设计系统。当前 RN 只覆盖 OpenUI；未来 OpenIntelligentUI 接入应由它现有的注册/导出来源派生，并复用同一消息适配和官方 Renderer，不合并两套语言契约。完成两端真机验证后，再决定是否抽取可发布的 RN 包；此分支不预先建立多层空包。
