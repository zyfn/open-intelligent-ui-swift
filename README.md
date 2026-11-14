# OpenUI Swift SDK

把模型生成的 OpenUI Lang 渲染为原生 SwiftUI 内容。工作区提供一个语言运行时、一个共享的原生运行时，以及两套平级组件库；两套组件库各自维护目录、设计系统与生成契约。

当前结构与接入规则见 [四模块架构](docs/architecture.md)。本次重构在 `refactor/openui-four-module-foundation` 分支推进，现有 Lang 契约保持不变。原生编译、交互和发布状态以具体提交的验证记录为准。

## 选择产品

所有产品由根 [Package.swift](Package.swift) 定义，最低平台为 iOS 16 / macOS 13。

| 产品 / import | 用途 | 原生渲染入口 |
|---|---|---|
| `OpenUILang` | 语言解析、求值、Store、动作与查询语义；不依赖 SwiftUI | 无 |
| `OpenUICore` | 自建组件库；复用状态、注册、上下文、树渲染、绑定与资源基础设施 | `OpenUICoreView` |
| `OpenSwiftUI` | 标准 OpenUI 组件目录与原生主题、布局、媒体呈现 | `OpenUIRenderer` |
| `OpenIntelligentSwiftUI` | Intelligent UI 组件目录、设计系统、reader/writer 生成契约 | `IntelligentUIView` |

应用根据内容选择组件库，并只链接所需产品。两套 UI 库都依赖 `OpenUICore`，互不依赖；它们公开的是同一个 `OpenUIState` 类型。标准库和 Intelligent UI 的组件名、参数含义与生成规则必须分别匹配对应 schema、registry、Prompt 和 spec。

## 快速接入

### Intelligent UI

~~~swift
import SwiftUI
import OpenIntelligentSwiftUI

@MainActor
struct AnswerView: View {
    private let library: IntelligentUILibrary
    @StateObject private var state: OpenUIState

    init() throws {
        let library = try IntelligentUILibrary()
        self.library = library
        _state = StateObject(wrappedValue: library.makeState())
    }

    var body: some View {
        IntelligentUIView(state: state, library: library)
            .task {
                state.setSource(
                    #"root = Col([Title("原生界面"), Text("可组合的内容")])"#
                )
            }
    }
}
~~~

`makeState()` 配置匹配的 reader schema 与函数，生命周期仍由宿主持有。新生成内容使用 `library.systemPrompt` 及同一实例导出的 writer 契约；组件排除只缩小新输出能力，历史 reader 仍保留。

### 标准组件库

在主线程创建一次匹配的 library 与 state，再将 state 保存在宿主的展示模型或 `@StateObject` 中：

~~~swift
import OpenSwiftUI

let library = try OpenUIStandardComponents.library()
let state = OpenUIState(schema: library.library.toSchema())
state.setSource(#"root = Stack([TextContent("共享运行时，标准组件呈现")])"#)
let content = OpenUIRenderer(state: state, registry: library.registry)
~~~

### 自建组件库

只依赖 `OpenUICore` 即可注册自己的组件，Core 不会自动安装任一 UI 库：

~~~swift
import SwiftUI
import OpenUICore

let library = try OpenUIComponentLibrary(
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
let state = OpenUIState(schema: library.library.toSchema())
state.setSource(#"root = Notice("自定义组件")"#)
let content = OpenUICoreView(state: state, registry: library.registry)
~~~

上述状态初始化与更新在主线程执行。不要在 `body`、布局测量或尺寸拟合中反复创建 state、提交源码或写入业务状态。

## 输入、动作与宿主职责

完整内容使用 `setSource(_:streaming:)`；增量内容使用 `push(_:)`，正常结束调用 `complete()`，用户中断调用 `interrupt()`。开启独立文档时使用新 state 或显式 `reset()`。相同流式快照的重复提交不会重新解析或推进文档身份。

组件通过共享 context 读取值、绑定状态、执行动作；宿主通过 `state.onAction` 接收事件。业务数据、会话/消息列表、滚动位置、网络权限与交易结果由宿主管理。资源加载可以通过 `OpenUIResourceContext` 注入；各组件库继续负责自己的图片布局、预览、失败呈现与交互视觉。

## 构建与验证

在带受支持 Xcode 的 Mac 上，从仓库根目录运行：

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

iOS Gallery 工程为 `Examples/Gallery/IntelligentUIGallery.xcodeproj`，scheme 为 `IntelligentUIGallery`，使用同一个根 Swift Package。完整验证流水线见 [native-sdk.yml](.github/workflows/native-sdk.yml)，包含独立产品消费者、原生测试、Release 尺寸拟合、历史契约、资源重建与 iOS 编译；流水线配置本身不构成通过证据。

`ContractExport` 输出 `spec.json`、`prompt.txt`、`manifest.json`。默认 `--validate` 检查新生成契约；历史程序使用：

~~~sh
swift run ContractExport --validate path/to/program.lang --historical
swift run ContractExport --reader-contract --include-search outputs/reader-contract
~~~

## 源码与维护

当前实现均位于根 `Sources/OpenUILang`、`Sources/OpenUICore`、`Sources/OpenSwiftUI`、`Sources/OpenIntelligentSwiftUI`；对应测试位于根 `Tests/`。`OpenUI/Sources`、`OpenUI/Tests` 的历史软链接已移除。

`OpenUI/` 保留导入来源、工具、fixtures、验证器、示例与历史文档。[IMPORT.json](OpenUI/IMPORT.json) 记录原始导入证据，[upstream.json](OpenUI/Tools/upstream.json) 固定重建输入；重构不改写这些来源记录。应用只依赖根包，避免重复引入定义同名模块的旧 fork。

修改前先阅读 [当前架构](docs/architecture.md)。组件参数和生成契约须与实际注册实现同源；视觉规则放在各自 UI 库，布局测量不得触发语义更新，失败验证必须保留。源码组织调整不新增 Lang 参数，不重建另一份 Store，不把聊天外壳纳入 SDK。

Intelligent UI 的组件契约和视觉规则见 [Intelligent UI 设计](docs/swift-intelligent-ui-design.md)。[设计改造状态](docs/design-revamp-status.md)、[集成审查](docs/openui-integration-review.md) 与 [历史记录](docs/swift-intelligent-ui-history.md) 保留用于追溯；其中的旧模块名、旧路径和过去验证结果不作为当前分支的接入依据。
