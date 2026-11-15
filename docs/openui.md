# OpenUI

OpenUI 提供通用组件目录与原生视觉。包、目录和共享运行机制只见[架构](architecture.md)，安装与状态生命周期见 [README](../README.md)，构建及验收见[验证说明](validation-and-security.md)。本文件统一维护该组件库的用法与呈现约束。

## 接入

在主线程创建并长期持有文档状态：

~~~swift
import SwiftOpenUI

let library: OpenUILibrary = try .openUI()
let state = library.makeState()
state.setSource(#"root = Stack([TextContent("Hello")])"#)
let view = OpenUIView(state: state, library: library)
~~~

向模型提供同一个 library 的 systemPrompt 和 specificationJSON。宿主向 state 输入完整或增量 Lang，并处理 onAction 与 ToolProvider；组件库不负责模型通信或业务结果。

## 组件目录

实际目录由 OpenUIComponents 注册并导出，包括固定上游的 84 个定义，以及原生 Map、MapPoint、SVG，共 87 个定义。其中 72 个是可视定义，15 个是由父组件消费的结构或数据定义；不能把注册数等同于独立可点击控件数量。

Gallery 按 Layout、Content、Controls、DataDisplay、Media 浏览实际注册定义，结构子项标注父组件上下文，组件用法默认展开。签名、位置参数和默认值以 library.specification 为准，不另维护一张手写权威目录。原始参考目录在 [upstream-catalog.json](../Sources/SwiftOpenUI/Resources/upstream-catalog.json)，原生注册在 [Catalog](../Sources/SwiftOpenUI/Catalog/)。

只有实际实现并注册的定义进入生成契约。Swift 包名、文件归属和视觉调整不改变已支持的 Lang 组件名、参数顺序、绑定和枚举。

## 组件定义与扩展

SwiftLang 提供 OpenUIComponent、OpenUIComponentLibrary 和 OpenUIParameter；组件将有序参数与原生 View 放在同一注册定义中。自建目录通过 OpenUILibrary(components:) 接入统一状态和 View。

~~~swift
let components = try OpenUIComponentLibrary(
    components: [
        OpenUIComponent(
            name: "Notice",
            description: "Display supplied text",
            params: [OpenUIParameter.string("text")]
        ) { context in
            Text(context.string("text") ?? "")
        }
    ],
    root: "Notice"
)
let library = OpenUILibrary(components: components)
let state = library.makeState()
let view = OpenUIView(state: state, library: library)
~~~

使用 SwiftUI 的 Text 时显式 import SwiftUI。需要扩展现成 OpenUI 目录时从 OpenUIComponents.library() 开始，使用 OpenUIComponentLibrary.extending(adding:overriding:removing:)；该入口将语言 authoring 交给官方 library.extend，保留 renderer 的实际来源。

参数顺序决定位置调用，不排序 schema 属性。命名 slot 通过 OpenUIParameter.slot 声明，组件使用 Context 渲染对应子项。结构、布局依赖、占位和身份字段通过 component.presentation(...) 元数据表达，不让公共 renderer 按组件名猜测。

只缩小新生成范围时，从实际定义派生 writer；已存消息应使用与自身程序匹配的 reader 和注册表。移除 renderer 后不能靠保留旧 schema 恢复原生组件。人工编写的说明和示例需同步裁剪，不能声称 schema 删除会自动改写说明文字。

## 主题与呈现

OpenUITheme 定义语义 token，OpenUIThemeValues 提供当前解析结果；OpenUIPresentation 管理呈现选择。OpenIntelligentUI 的主题不通过本库配置。

~~~swift
OpenUIView(state: state, library: library)
    .openUITheme { theme in
        theme.spaceM = 20
    }
    .openUIPresentation(OpenUIPresentation())
~~~

主题通过同一个 typed Context storage 传递。context.theme 和 context.presentation 读取 OpenUI 的值；自建组件需要相同规则时使用对应 Context 扩展。子树覆盖保留同层其它 typed values；不要用高频几何或计时状态反复改写全局主题。

颜色使用语义角色与 Apple 平台外观，保持文字、边界、强调和状态的职责。图表序列色不复用为业务状态色。字体、圆角、间距、媒体比例与按钮形状使用所属 token，不让不同类别自行创造一套视觉层级。

紧凑模式和大字号不压缩来源文字、价格或字段标签。卡片与列表的组合由输入程序决定，组件不把完整内容裁成统一摘要，也不为单个 Gallery 场景硬编码布局。

## 状态、字段与动作

组件通过 OpenUIComponentContext 的 value/string、children/slot、binding、field 和 action 方法接入；不直接改写整份 state 或绕过 Context 执行动作。context.string 是显示便利方法，精确字符串与键使用 OpenUIString/Value，不能在协议、身份或资源键上引入 Unicode 归一化。

可写控件区分文档 Store、局部编辑草稿和提交结果。Select、Radio、Checkbox、Switch 的用户选择须在首次操作后反映到当前展示；Store-only 的更新也必须使叶子 View 刷新。无可写绑定的字面值不能被当作可写状态。

字段验证通过共享规则与 Context 执行。被拒绝的草稿不能因其它 Store 发布而提交；源码替换使原草稿、旧动作和旧异步结果失效。EditableTable 的本地交付回执不代表远程持久化。Slider 的离散格点考虑 minimum 与 step 的精度，范围末端、拖动和连续文本按各自已有规则校验。

UI 特有的点击项上下文可以由组件提供；通用状态、动作执行顺序、异步取消和文档就绪检查由适配层负责。表单和资源的精确名称保留 UTF-16 语义。按钮、卡片动作与本地选择在拖动/分页结束时不能误派发激活。

## 布局与流式

父容器拥有分配的可用空间，子组件消费当前位置的 proposal。缩放只影响观看倍率，逻辑宽高控制实际排版。尺寸拟合与旋转不能重新提交源码或清空用户输入。

- 缺失引用、尚未完成的数据和已闭合但为空的数组分开处理；不为未提供内容虚构图文格子。
- 稳定节点、局部状态、选择和资源身份应在增量流中保持。流式追加不能重建整棵文档环境。
- 结构元数据可以保留已声明的槽位，但不承诺所有程序都有“有序就绪前缀”；实际可见性遵循官方解析结果和原生 readiness。
- 已完整的控件可在其它内容继续流式时交互，未完成动作仍须阻止执行。
- 卡片、图片、图表、表格和窄屏行布局按本库规则等待必要尺寸或数据，不靠改写来源内容绕过就绪条件。
- 宽度、主题和 Dynamic Type 变化只改变布局与呈现，不产生新的文档身份。滚动容器和消息列表归宿主。

## 文本、媒体与原生差异

Markdown 与代码使用固定的 typed adapter，不在组件里创建任意 JS 环境或执行来源脚本。公式与代码资源随包分发，许可与安全策略见验证说明；文本组件不得提交源码或写入文档状态。

原生图片读取宿主资源 Context、baseURL、loader 与鉴权作用域，受并发、响应及解码预算约束；作用域变化需同时影响缓存、View task 与已解码内容身份。比例、加载、失败、重试与预览属于组件视觉，不将该保证扩大到 WebKit/Markdown/MapKit 的所有网络请求。

Map 表达来源坐标与选点，不表示真实导航、实时交通或已完成业务操作；MapKit 的增强能力按 iOS 17/macOS 14 门控。SVG 要求有效 viewBox，使用内联内容或 HTTPS src，拒绝活动内容和外部引用。

Charts、原生选择器、滚动与表格采用 Apple 平台实现。确有原生差异时保留输入语义并按实际 View 验收，不能把“来源相同”写成逐像素等价。来源映射以 Catalog 和固定生成输入为准，历史差异在 Git 中，不维护另一份逐文件映射文档。

## 验证入口

~~~sh
swift test --filter SwiftOpenUITests
python3 Tools/check_gallery_catalog.py
./Examples/Gallery/verify.sh
~~~

纯注册与解析不能替代控件交互或视觉验收。涉及文字、选择、草稿、尺寸、主题或媒体时，在对应宽度、外观和字号运行原生场景，记录实际行为；图片、案例和模拟工具继续由 [Gallery](../Examples/Gallery/README.md) 管理。
