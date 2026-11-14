# OpenUI Swift SDK

把模型生成的 OpenUI Lang 渲染为原生 SwiftUI 内容。客户端使用一套接入接口，按需选择标准 UI 或 Intelligent UI；每个组件库负责自己的组件契约、设计系统和生成规则。

## 客户端只添加一个包

通过 Swift Package Manager 添加本仓库 `https://github.com/zyfn/open-intelligent-ui-swift.git`；使用当前开发分支时选择 `refactor/openui-four-module-foundation`。

| 客户端需要 | 给应用 target 添加的库产品 | 自动带入的公共模块 |
|---|---|---|
| 标准 UI | `OpenSwiftUI` | `OpenUICore`、`OpenUILang` |
| Intelligent UI | `OpenIntelligentSwiftUI` | `OpenUICore`、`OpenUILang` |
| 同一应用同时支持两套 UI | `OpenSwiftUI` 和 `OpenIntelligentSwiftUI` | 共享一份 `OpenUICore`、`OpenUILang` |

只使用一套 UI 时，选一个 UI 产品即可。Core 与 Lang 是同包内自动解析的依赖，无需分别安装 SDK。Swift 源文件中的 `import` 用于选择可见模块，与添加几个 Swift Package 是不同的操作。

## 一套客户端接口

根 `Package.swift` 定义四个可选库产品，最低平台为 iOS 16 / macOS 13；下面是包内分层，不要求客户端全部添加。

| 库产品（同名 Swift 模块） | 用途 | 选择组件库 |
|---|---|---|
| `OpenUILang` | 语言解析、求值、Store、动作和查询语义 | 无原生 UI |
| `OpenUICore` | 公共客户端接口、状态、注册、渲染、绑定和资源基础设施 | `OpenUILibrary(components: …)` |
| `OpenSwiftUI` | 标准 OpenUI 组件与设计系统 | `OpenUILibrary.standard()` |
| `OpenIntelligentSwiftUI` | Intelligent UI 组件与设计系统 | `OpenUILibrary.intelligent()` |

两套 UI 产品各自依赖 Core 和 Lang，互不依赖。只选择一套时，只需链接对应的 UI 产品；同一应用也可以链接两套。所有产品来自本仓库的同一个根包。

### 1. 选择库

使用 Intelligent UI：

~~~swift
import OpenIntelligentSwiftUI

let library: OpenUILibrary = try .intelligent()
~~~

使用标准 UI 时，选择：

~~~swift
import OpenSwiftUI

let library: OpenUILibrary = try .standard()
~~~

从这里开始，客户端代码完全相同。模型生成契约、reader schema、函数和原生外观都由选中的 library 提供。

### 2. 创建并持有一条消息的状态

在宿主的 `@MainActor` 初始化流程中创建，随该消息长期持有：

~~~swift
let state = library.makeState()

state.onAction = { event in
    // 交给应用现有的导航、继续对话或业务动作处理。
}

let content = OpenUIView(state: state, library: library)
~~~

同一个工厂也接受宿主的 `toolProvider:` 和 `persistedState:`，两套组件库使用完全相同的参数。持久化数据可以使用 `[OpenUIString: Value]` 或 `[String: Value]`；自定义函数来自所选库的实际 reader。

普通接入只需 `import` 所选 UI 模块，它已经导出 Core 的公共接口。如果源码显式声明 `ToolProvider`、`Value`、`ActionEvent`、`LibrarySpec` 等语言层类型，再加 `import OpenUILang`；这仍然使用同一个包内的模块。

完整源码和流式内容使用同一状态接口：

~~~swift
state.setSource(program)                 // 一次提交完整内容
state.setSource(snapshot, streaming: true) // 或提交增长中的完整快照
~~~

增量传输则使用 `state.push(chunk)`，正常结束调用 `state.complete()`，用户中断调用 `state.interrupt()`。独立文档使用新的 state；复用已有 state 时显式 `reset()`。不要在 SwiftUI `body`、布局测量或尺寸拟合中创建 state、反复提交源码或写业务状态。

`OpenUIView` 只连接宿主状态与所选库。状态观察由内部 Core host 负责；库的视觉包装不会再增加一层状态观察。

### 3. 从同一库导出生成契约

~~~swift
let prompt = library.systemPrompt
let specJSON = library.specificationJSON
~~~

这两个属性在所有库中都相同，内容自动对应选中的组件目录。组件名、位置参数和生成规则继续由各库定义；客户端无需分别拼装 Prompt、schema、函数和 registry。

`readerSpecification` 提供完整读取契约，用于历史数据检查。状态工厂总是使用完整 reader；Intelligent UI 的 `excludingComponents` 只限制新生成内容。默认 Intelligent UI Prompt 不宣告工具查询，宿主需要工具生成时仍须明确其工具策略；传入 ToolProvider 负责执行已经声明的调用。

### 4. 切换组件库

同一个 `OpenUILibrary` 类型可以存储任一组件库。选择新库后，用它创建对应的新 state，再交给同一个 `OpenUIView`；消息流与动作回调代码保持不变。

已有消息保留它创建时的 library/state 配对。共享客户端接口不转换历史程序：标准库的 `Stack/TextContent` 与 Intelligent UI 的 `Col/Text` 分别由匹配的 reader 解释。不要把旧 state 的 schema 当作可原地替换的设置。

## 宿主资源与视觉定制

两套库使用相同的 `OpenUIResourceContext` 注入宿主的资源地址、鉴权 loader 和传输/解码限制：

~~~swift
OpenUIView(state: state, library: library)
    .openUIResourceContext(resources)
~~~

Intelligent UI 的原生图片、内联图片与预览也遵循这份资源 context；仍可通过 `intelligentUIImages` 按精确 source key 提供已加载的 SwiftUI 图片。库各自管理裁剪、布局、预览与加载视觉。Markdown/WebKit/MapKit 内部请求有其各自的实现边界，不把它们宣称为原生图片通道的一部分。

标准主题使用 `openUITheme`；Intelligent UI 使用 `intelligentUITheme`。这些是各设计系统的可选定制，普通客户端接入不需要分别处理它们。

业务数据、消息列表、滚动位置、模型通信、网络权限和真实交易结果由宿主负责。SDK 将动作事件交给 `state.onAction`，组件支持哪些动作由所选库的生成契约说明。

## 自建组件库

只依赖 `OpenUICore` 即可使用相同接入接口：

~~~swift
import SwiftUI
import OpenUICore

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

Core 不自动安装标准库或 Intelligent UI 的组件、主题和生成规则。自建库也可以明确提供不同的 reader/writer 与自己的原生展示。

## 构建与验证

在带受支持 Xcode 的 Mac 上，从仓库根目录执行：

~~~sh
swift test
python3 Tools/check_module_boundaries.py
python3 Tools/check_product_consumers.py --scratch-root /tmp/openui-consumers
swift test -c release --filter 'HostSizingIsolationTests|CoreHostIsolationTests'
swift run IntelligentUIGallery --validate-fixtures
swift run ContractExport outputs/contracts
python3 Tools/check_localization.py
python3 Tools/check_lang_compatibility.py
~~~

iOS Gallery 工程为 `Examples/Gallery/IntelligentUIGallery.xcodeproj`，scheme 为 `IntelligentUIGallery`，使用同一个根 Swift Package。独立消费者检查使用同一段客户端代码接入两套 UI，并验证只选择其中一个产品时不会链接另一套库。

`ContractExport` 默认输出 Intelligent UI 新生成所用的 `spec.json`、`prompt.txt` 和 `manifest.json`。历史读取契约使用 `--reader-contract`，历史程序验证使用 `--historical`。

完整流水线见 [native-sdk.yml](.github/workflows/native-sdk.yml)。源码检查与测试配置不等同于 Apple 平台编译、交互或发布已经通过；验收证据绑定具体提交。

## 仓库结构

| 目录 | 内容 |
|---|---|
| `Sources/` | 四个公开模块及语言层内部的 C 正则实现 |
| `Tests/` | 各模块的原生测试与其打包 fixtures |
| `Examples/` | Gallery、独立 macOS 示例和 agent cases |
| `Tools/` | 契约导出、资源生成与维护检查 |
| `Benchmarks/` | 模型生成和交互评测 |
| `Fixtures/` | 语言兼容验证数据 |
| `Validation/` | 验收说明、源码修复候选与核验材料 |
| `docs/` | 当前架构、组件、语言与设计文档 |

源码只在根 `Sources/` 维护，没有嵌套 SDK 或旧目录软链接。客户端只依赖根包，避免同时解析另外一个定义同名模块的旧 fork。

本仓库直接维护整合后的 Swift 源码，未通过 SwiftPM 再依赖旧 OpenUI Swift SDK。历史迁移记录保留在 Git 历史；当前生成输入由 [upstream.json](Tools/upstream.json) 固定，上游许可保留在根 [第三方声明](THIRD-PARTY-NOTICES.txt) 和随 SDK 打包的 [语言层第三方声明](Sources/OpenUILang/Resources/THIRD-PARTY-NOTICES.txt) 中。

维护入口：[当前架构](docs/architecture.md)、[Intelligent UI 设计](docs/swift-intelligent-ui-design.md)、[验证与安全修复](docs/validation-and-security.md)。
