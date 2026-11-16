# 架构

文档版本：1.0 · 更新日期：2026-11-16

本文是仓库唯一的架构定义，维护包名、目录、职责、依赖和运行链路。接入代码见 [README](../README.md)，组件用法见 [OpenUI](openui.md) 与 [OpenIntelligentUI](openintelligentui.md)，构建和验收见 [验证说明](validation-and-security.md)。其他文档引用本文，不重复维护模块图或职责表。

## 1. 与官方分层对应

官方以 [lang-core](https://github.com/thesysdev/openui/tree/main/packages/lang-core)、[react-lang](https://github.com/thesysdev/openui/tree/main/packages/react-lang) 和 [react-ui](https://github.com/thesysdev/openui/tree/main/packages/react-ui) 分工：通用语言内核、框架适配、组件库。react-lang 包含组件定义、Renderer、Context、字段与动作入口，并公开所需的内核契约；它不只是 TypeScript 类型包装。react/vue 指框架，而不是另一套 DSL。

本 SDK 采用同样的三层职责：

| 层 | 本项目名称 | 职责 |
| --- | --- | --- |
| 官方内核 | 官方 lang-core 1.1.1，随包分发的 lang-core.js | 词法、解析、流式补全、求值、Store、Query 依赖调度、Schema、签名与 Prompt 规则 |
| Swift/SwiftUI 适配 | SwiftLang | 官方内核桥接、Swift 数据契约、文档状态、组件注册、Context、原生递归渲染、绑定、动作与异步生命周期 |
| 组件库 | SwiftOpenUI、SwiftIntelligentUI | OpenUI 与 OpenIntelligentUI 各自的组件目录、设计系统、布局、媒体呈现、特有函数及模型生成契约 |

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
    Engine["官方 lang-core · JavaScriptCore"]
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
| Sources/SwiftLang/Language/ | 官方核心的类型与桥接、解析/求值门面、Store/Query 适配、原生动作执行、UTF-16 与对象身份、序列化和执行预算；此目录不导入 SwiftUI/UIKit/AppKit |
| Sources/SwiftLang/Runtime/ | OpenUILibrary、OpenUIState、OpenUIView、无主题的 SwiftLangView、注册表、递归渲染、Context、绑定、身份与生命周期，以及通用资源/媒体基础设施 |
| Sources/SwiftLang/Resources/ | 固定官方 JS bundle、manifest 和许可；应用运行时不下载代码 |
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

Language 中的文件按调用职责保留，不再镜像一套官方算法：

- ProtocolTypes、OpenUIString、ReferenceValues、ValueConversion、JSSemantics：公开数据契约、顺序、UTF-16、引用身份与类型投影。
- SharedCore、LibraryBridge：串行 JavaScriptCore 环境、JS 对象/回调、资源加载与官方 authoring 传输。
- API、Lexer、Parser、StreamingParser、Evaluator、Store、Library、Prompt、Serialize、Merge、Message、Forms、MCP：对固定官方实现的类型化调用。
- QueryManager、Actions：Swift async 工具、取消与原生动作步骤执行；调度与状态语义继续由官方实现负责。
- NativeSourceReadiness：源数据闭合、依赖、数组位置和占位提示；不进入 Lang 值、AST 字段或持久化协议。
- RuntimeLimits、RegExp：原生输入、深度和正则执行预算。

编译后的 LibrarySchema 是只读快照；结构修改通过官方 Library.extend 后重新编译。Query 只接受声明 AST，由官方管理依赖。JSON 语法和转义使用 JavaScriptCore 的 JSON.parse/stringify。Evaluator 通过 EvaluationContext 读取状态，不额外持有 Store。签名来自实际 LibrarySpec，不维护独立签名生成器、原生 materializer 上下文、可变 schema 编辑器或另一条 Query 请求调度链。

## 3. 唯一的客户端运行链路

1. 宿主选择 OpenUILibrary.openUI() 或 .openIntelligentUI()；自建组件使用 OpenUILibrary(components:)。
2. 同一个 library 提供 systemPrompt、specificationJSON 和 makeState(toolProvider:persistedState:)。
3. 宿主长期持有每份文档的 OpenUIState，输入完整源码或 push 增量，并明确 complete、interrupt、reset 或替换。
4. State 调用官方 parser/Store/evaluator，并同步声明 Query；工具、取消和定时器通过 Swift 桥接。
5. OpenUIView(state:library:) 交给同一适配层 renderer，按选定库的注册表构建原生组件。
6. 组件通过 OpenUIComponentContext 读取值、渲染子项、编辑字段和触发动作；业务结果经宿主回填。

每份文档拥有独立的 parser、Store、查询和 revision/epoch。共享官方代码及 JS 执行环境不代表共享用户状态。旧文档回调、工具结果和资源结果不得写回替换后的文档。

两套库始终使用同一个 OpenUILibrary、OpenUIState、OpenUIView、ActionEvent 和组件 Context。产品特有主题、服务和呈现参数使用 OpenUI / OpenIntelligentUI 前缀；不再提供产品专属 State/Event 别名或旧工厂转发入口。

## 4. 适配层、组件与宿主的边界

- 适配层统一拥有运行机制。组件不另建 parser/Store/state，不重复观察整份文档，不绕过 Context 直接派发动作或写入业务状态。
- OpenUIView 只组合宿主传入的 library/state，不在 body、拟合或测量中创建状态、反复提交源码。当前 SwiftLangView 与各 OpenUIComponentHost 都观察同一个 OpenUIState，尚不能描述为只在公共 host 观察一次。尺寸拟合不得产生新的语义更新；真实流式更新的求值、索引和组件刷新范围需单独验证，不能用相同缓冲区的拟合回归替代。
- 组件注册同时提供有序参数、renderer 和结构/身份元数据；公共 renderer 不根据 TabItem 等名字猜测布局、身份或主题。
- typed OpenUIContextValues 是通用扩展容器。主题、阅读宽度、占位视觉、图表颜色、媒体比例和动画规则由各组件库定义。
- 通用资源 Context 管理地址、宿主 loader、鉴权作用域、预算和文档生命周期。各 UI 的图片缓存/解码、占位、重试、预览和地图交互保持在所属组件库。原生图片通道的保证不扩展到 WebKit、Markdown 或 MapKit 的所有网络请求。
- OpenIntelligentUI 的地图筛选、内部点位卡片、选中、全览与原生展开由 Map 自身管理；场景不补建另一套基本交互，组件不虚构导航或业务结果。
- 宿主负责模型/Agent/工具通信、账号权限、消息列表、滚动、业务数据、交易与真实操作结果。Gallery 的模拟工具与动作记录不代表远程业务成功。

reader 提供读取契约，writer 提供当前生成范围。两者从同一注册来源派生，不能维护第二份手写权威 schema。组件名、参数顺序、枚举与绑定属于输入契约；收敛 Swift 包/API 名称不等于改写已存 Lang 程序。两套产品的组件语法分别维护，不通过替换组件名假定互换。

## 5. 官方来源、原生适配与语言版本

实际来源以 [Tools/upstream.json](../Tools/upstream.json)、[资源 manifest](../Sources/SwiftLang/Resources/core-manifest.json) 和 [适配清单](../Tools/Core/adaptations.json) 为准。构建提取固定官方源码，核对原始源码树、显式补丁及生成指纹；客户端不安装 npm 包或追踪 latest。

Swift 负责 lossless 数据传输、原生 async 与动作执行。当前还保留有来源记录的 readiness 注入、serializer 修复、依赖 schema 表示适配与执行预算。这是官方核心加显式 Apple 适配，不能宣称官方代码零修改或任意输入下完全等价。

### 语言版本与参考规范

运行资源为官方 lang-core 1.1.1。docs/language 下 Overview、Language、Prompt 标注的 1.0 是保留的规范参考，与版本化 fixtures 对应，不是当前运行版本。模型生成使用所选库当前导出的 Prompt/spec。1.1.1 的 Query 依赖、失败重试、表达式默认值和数组数学行为，以及原生预算和对照验证范围，统一记录在 [验证说明](validation-and-security.md#3-语言版本与验证边界)。

## 6. 文档与验证维护

架构、目录、职责和依赖只在本文维护。README 负责安装与公共接入；两套组件指南负责本库 API/视觉规则；验证文档负责命令、资源来源、安全与证据边界。AGENTS.md 仅保存工作规则和这些入口，不复制职责表。生成资源、版本和哈希由工具/锁文件负责，不在多处手填。

架构变化需同步 Package、真实源码、独立消费者、目录检查、工具、Gallery 和文档引用。源码检查、Swift 编译、XCTest、原生交互、性能及真实模型评测分别报告；任一项通过都不能替代其他项。验收命令和依赖审计以 [验证说明](validation-and-security.md) 与 [CI](../.github/workflows/native-sdk.yml) 为入口。
