# OpenUI Swift SDK

文档版本：1.8 · 更新日期：2026-11-23

把模型生成的 OpenUI Lang 渲染为原生 SwiftUI 内容。客户端使用一套接入接口，按需选择OpenUI 或 OpenIntelligentUI；每个组件库负责自己的组件契约、设计系统和生成规则。

## Lang 与 UI 独立引入

通过 Swift Package Manager 添加本仓库 `https://github.com/zyfn/open-intelligent-ui-swift.git`；主线接入选择 `main`，需要可复现构建时固定已经验证的提交 revision。适配层和两套 UI 是独立的库产品与 Swift 模块，在同一个包中共同发布。

构建需要 Swift 6 工具链，使用 Swift 5 语言模式；最低运行平台为 iOS 16 / macOS 13。

| 客户端需要 | 给应用 target 添加的库产品 | 自动带入的公共模块 |
|---|---|---|
| 解析、执行、校验语言或自建组件库 | `swift-lang` | `SwiftLang`，包含 SwiftUI 适配，无内置组件库 |
| OpenUI | `swift-ui` | `SwiftOpenUI`、`SwiftLang` |
| OpenIntelligentUI | `swift-intelligent-ui` | `SwiftIntelligentUI`、`SwiftLang` |
| 同一应用同时支持两套 UI | `swift-ui` 和 `swift-intelligent-ui` | 两套 UI 模块共享一份 `SwiftLang` |

SwiftLang 是公共 Swift/SwiftUI 适配层，不依赖任一组件库。只使用一套 UI 时，添加一个 UI 库产品即可，SwiftLang 会作为依赖带入；独立使用适配层时添加 swift-lang。短横线名称用于 SwiftPM 产品，驼峰名称用于 import。它们属于同一个 openui-swift-sdk Package，不是多份语言运行时。

例如，两个不同用途的消费者 target 可以分别只选择自己的产品：

~~~swift
.target(name: "LanguageClient", dependencies: [
    .product(name: "swift-lang", package: "open-intelligent-ui-swift")
]),
.target(name: "UIClient", dependencies: [
    .product(name: "swift-intelligent-ui", package: "open-intelligent-ui-swift")
])
~~~

### 只使用 Lang

当前语言核心固定为官方 `@openuidev/lang-core` **1.1.1**，源码提交为 [`39a4e3f`](https://github.com/thesysdev/openui/tree/39a4e3f6493673fdf2de04681240374c8d6f6be8/packages/lang-core)。它经过明确记录的 Apple 平台桥接与兼容适配，构建为随 SDK 分发的 JavaScriptCore 资源。实际版本、源码树与资源哈希由 [upstream.json](Tools/upstream.json) 和 [资源清单](Sources/SwiftLang/Resources/core-manifest.json) 固定；客户端不在运行时下载脚本，也不会自动跟随上游 `latest`。

语言客户端自行提供组件的语言契约，无需提供 SwiftUI renderer：

~~~swift
import SwiftLang

let library = try createLibrary(
    components: [
        defineComponent(
            name: "Notice",
            description: "Text supplied by the caller",
            params: [ParamDef(
                name: "text", required: true,
                schema: .object([JSONField(key: "type", value: .string("string"))])
            )]
        )
    ],
    root: "Notice"
)
let parser = createParser(schema: library.toSchema())
let result = parser.parse(#"root = Notice("只解析，不展示")"#)
~~~

需要展示时，再使用下面的 UI 接口；同一份语言实现支持不同组件目录。

## 一套 UI 客户端接口

按上表选择 UI 产品后，使用对应的 library 工厂。状态、流式输入、动作回调和文档 View 都使用下面的同一套接口。

### 1. 选择库

使用 OpenIntelligentUI：

~~~swift
import SwiftIntelligentUI

let library: OpenUILibrary = try .openIntelligentUI()
~~~

使用OpenUI 时，选择：

~~~swift
import SwiftOpenUI

let library: OpenUILibrary = try .openUI()
~~~

从这里开始，客户端代码完全相同。模型生成契约、reader schema、函数和原生外观都由选中的 library 提供。

### 2. 创建并持有一条消息的状态

在宿主的 `@MainActor` 初始化流程中创建；同一份活跃文档持续使用同一个 state：

~~~swift
let state = library.makeState()

state.onAction = { event in
    // 交给应用现有的导航、继续对话或业务动作处理。
}

let content = OpenUIView(state: state, library: library)
~~~

同一个工厂也接受宿主的 `toolProvider:` 和 `persistedState:`，两套组件库使用完全相同的参数。持久化数据可以使用 `[OpenUIString: Value]` 或 `[String: Value]`；自定义函数来自所选库的实际 reader。

`snapshotState()` 是可选的 Store 业务值快照，普通渲染不需要调用；它不包含完整文档、Query 执行状态、未提交输入草稿或焦点，也不会释放 state。消息离屏和 `complete()` 均不表示文档退休。长会话的历史分页与活跃 state 持有范围由宿主管理，不能将销毁后重新解析等同于完整恢复；具体边界见[文档与资源的生命周期](docs/architecture.md#文档与资源的生命周期)。

普通接入只需 `import` 所选 UI 模块，它已导出 SwiftLang 的公共适配接口。需要独立使用解析、组件注册或文档状态时直接 `import SwiftLang`。

完整源码和流式内容使用同一状态接口：

~~~swift
state.setSource(program)                 // 一次提交完整内容
state.setSource(snapshot, streaming: true) // 或提交增长中的完整快照
~~~

增量传输则使用 `state.push(chunk)`，正常结束调用 `state.complete()`，用户中断调用 `state.interrupt()`。独立文档使用新的 state；复用已有 state 时显式 `reset()`。不要在 SwiftUI `body`、布局测量或尺寸拟合中创建 state、反复提交源码或写业务状态。

`OpenUIView` 只连接宿主状态与所选库。状态观察由 SwiftLang 的公共 host 负责；库的视觉包装不会再增加一层状态观察。

#### 终态与诊断

`complete()` 表示本轮源码输入结束。解析器可能同时返回可渲染的 `root` 和诊断；`meta.incomplete == false` 仅表示没有检测到未闭合输入，不能证明正文完整。例如字符串内未转义的双引号可能使正文成为后续位置参数，产生 `type-mismatch`、`excess-args`，同时保留第一个字符串作为可读前缀。诊断的 `severity` 可以缺省；标为 warning 的参数丢弃也可能损失正文。

宿主需要控制最终消息的展示时，使用现有入口即可：

1. 在 `onParseResult` 中只保存当前文档最新的 `ParseMeta`、`nativeLimitExceeded` 和 `sourceRevision`。覆盖旧值，不累积流式过程中的暂时性诊断，也不逐块读取解析树、重新解析或扫描源码。
2. 正常传输结束后调用 `complete()`，在调用返回后确认仍是同一请求和 `sourceRevision`，再读取最新元数据与 `state.root`、`state.errors`。保守验收要求有 root、未中断、没有检测到未闭合输入或未解析引用、没有解析/运行时诊断且未超限。`onError` 会去重，终态不一定再次上报流式阶段已经出现的相同错误，不能把等待新错误回调作为验收触发点。
3. 终态验收失败时，由宿主将消息标为生成失败，隐藏异常正文并使用既有的消息级重试入口；原始 Lang 保留用于排查。SDK 的容错 root 仍可供调试，不应把它直接标记为完整答案。替换或 reset 时清理所保存的元数据，旧请求的晚到数据继续由宿主原有请求生命周期拦截。

这是基于已报告诊断的保守验收，SDK 当前没有通用的严格语法校验入口；空诊断也不能证明容错解析没有遗漏内容。Query、Mutation、资源加载和实际业务成功仍按各自状态判断。消息级处理不需要猜测正文、补写引号或改写原始 Lang。

### 3. 从同一库导出生成契约

~~~swift
let prompt = library.systemPrompt
let specJSON = library.specificationJSON
~~~

这两个属性在所有库中都相同，内容自动对应选中的组件目录。组件名、位置参数和生成规则继续由各库定义；客户端无需分别拼装 Prompt、schema、函数和 registry。

`readerSpecification` 提供运行时完整契约，状态工厂使用同一组件集合创建执行状态；`excludingComponents` 控制新生成目录。普通图文直接用 `Row([Image(...), Col([...])])` 组合，图片尺寸和对齐由 Row 的媒体布局处理。需要响应式多列时给 Grid 提供 `minChildWidth`，Agent 无需计算设备宽度。具体用法见 [OpenIntelligentUI 组件指南](docs/openintelligentui.md)。默认 OpenIntelligentUI Prompt 不宣告工具查询，宿主需要工具生成时仍须明确其工具策略；传入 ToolProvider 负责执行已经声明的调用。

### 4. 切换组件库

同一个 `OpenUILibrary` 类型可以存储任一组件库。选择新库后，用它创建对应的新 state，再交给同一个 `OpenUIView`；消息流与动作回调代码保持不变。

已有消息保留它创建时的 library/state 配对。共享客户端接口不转换历史程序：标准库的 `Stack/TextContent` 与 OpenIntelligentUI 的 `Col/Text` 分别由匹配的 reader 解释。不要把旧 state 的 schema 当作可原地替换的设置。

## 宿主资源与视觉定制

两套库使用相同的 `OpenUIResourceContext` 注入宿主的资源地址、鉴权 loader 和传输/解码限制：

~~~swift
OpenUIView(state: state, library: library)
    .openUIResourceContext(resources)
~~~

OpenIntelligentUI 的原生图片、内联图片与预览也遵循这份资源 context；仍可通过 `openIntelligentUIImages` 按精确 source key 提供已加载的 SwiftUI 图片。库各自管理裁剪、布局、预览与加载视觉。Markdown/WebKit/MapKit 内部请求有其各自的实现边界，不把它们宣称为原生图片通道的一部分。

OpenIntelligentUI 的地图使用 `Map` / `MapMarker` 表达地点坐标、分类、顺序和可选 label 绑定，组件管理筛选、全览与展开，并使用 MapKit 绘制底图及驾车道路概览。地点名称和坐标由宿主提供；尺寸适配与地图交互由组件完成。参数、选中规则及平台边界见[地图与平台桥接](docs/openintelligentui.md#25-地图与平台桥接)。

标准主题使用 `openUITheme`；OpenIntelligentUI 使用 `openIntelligentUITheme`。这些是各设计系统的可选定制，普通客户端接入不需要分别处理它们。

业务数据、消息列表、滚动位置、模型通信、网络权限和真实交易结果由宿主负责。SDK 将动作事件交给 `state.onAction`，组件支持哪些动作由所选库的生成契约说明。

## 自建组件库

只依赖 `SwiftLang` 即可使用相同接入接口：

~~~swift
import SwiftUI
import SwiftLang

let components = try OpenUIComponentLibrary(
    components: [
        OpenUIComponent(
            name: "Notice",
            description: "Application-owned notice",
            params: [OpenUIParameter.string("text")]
        ) { context in
            Text(context.string("text") ?? "").padding()
        }
    ],
    root: "Notice"
)
let library = OpenUILibrary(components: components)

// 在 @MainActor 中创建并保留：
let state = library.makeState()
state.setSource(#"root = Notice("自定义组件")"#)
let content = OpenUIView(state: state, library: library)
~~~

SwiftLang 不自动安装任一 UI 库的组件、主题或生成规则。自建库也可以明确提供不同的 reader/writer 与自己的原生展示。

## 构建与验证

在带受支持 Xcode 的 Mac 上，从仓库根目录执行：

~~~sh
swift test
python3 Tools/check_module_boundaries.py
python3 Tools/check_product_consumers.py --scratch-root /tmp/openui-consumers
swift test -c release --filter 'HostSizingIsolationTests|CoreHostIsolationTests'
python3 Tools/check_gallery_catalog.py
swift test --package-path Examples/Gallery
swift run --package-path Examples/Gallery OpenUIGallery --validate-fixtures
swift run --package-path Tools/ContractExport ContractExport "$PWD/outputs/contracts"
python3 Tools/check_localization.py
python3 Tools/check_lang_compatibility.py
~~~

日常调试使用独立的 [OpenUI Gallery](Examples/Gallery/README.md)，在同一入口浏览两套 UI 的精选案例、调整预览尺寸和倍率、编辑源码与回放流式内容。macOS 启动命令为 `swift run --package-path Examples/Gallery OpenUIGallery`；iOS 工程为 `Examples/Gallery/OpenUIGallery.xcodeproj`，scheme 为 `OpenUIGallery`。Gallery 依赖本地根 SDK，根包仅导出三个库产品。

独立消费者检查为 SwiftLang、OpenUI、OpenIntelligentUI 分别创建并运行一个单产品外部包，验证解析、流式、生成契约、原生宿主和状态读写。适配层消费者不链接两套组件库，两套 UI 也不链接对方。该检查不启动窗口，不能代替 UI 视觉验收。内部 Language 目录与 Runtime 目录的职责边界由源码检查验证，详见架构。

独立的 [ContractExport 工具包](Tools/ContractExport/README.md) 默认输出 OpenIntelligentUI 新生成所用的 `spec.json`、`prompt.txt` 和 `manifest.json`。历史读取契约使用 `--reader-contract`，历史程序验证使用 `--historical`。六个领域的测试与验收计划见 [SDK 验证矩阵](Validation/SDK/README.md)，可重复的性能测量见 [Benchmarks](Benchmarks/README.md)，可选真实模型评测见 [Validation/Generation](Validation/Generation/README.md)。

完整流水线见 [native-sdk.yml](.github/workflows/native-sdk.yml)。源码检查与测试配置不等同于 Apple 平台编译、交互或发布已经通过；验收证据绑定具体提交。

## 维护入口

包、目录与职责只维护在 [架构](docs/architecture.md)。组件用法见 [OpenUI](docs/openui.md) 与 [OpenIntelligentUI](docs/openintelligentui.md)，构建及验收见 [验证说明](docs/validation-and-security.md)，历次改动及效果见 [性能优化记录](docs/performance.md)。
