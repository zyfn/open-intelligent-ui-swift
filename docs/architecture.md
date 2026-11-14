# 四模块架构

本文描述当前 `refactor/openui-four-module-foundation` 分支的实际源码边界。根 `Package.swift` 导出四个库产品；两个 UI 库共享运行时，各自保留组件与视觉体系。接入示例见 [README](../README.md)。

## 1. 依赖关系

~~~mermaid
flowchart TB
    Host["宿主应用"]
    Standard["OpenSwiftUI"]
    Intelligent["OpenIntelligentSwiftUI"]
    Core["OpenUICore"]
    Lang["OpenUILang"]
    Host --> Standard
    Host --> Intelligent
    Host --> Core
    Standard --> Core
    Intelligent --> Core
    Core --> Lang
    Standard --> Lang
    Intelligent --> Lang
~~~

图中箭头表示源码/产品使用方向。`OpenSwiftUI` 与 `OpenIntelligentSwiftUI` 不相互引用，也不通过对方取得状态或动作实现。SwiftUI、MapKit、WebKit 等 Apple 框架由需要它们的模块直接使用；与 UI 无关的语言层不导入 SwiftUI。

| 模块 | 源码目录 | 所有权 |
|---|---|---|
| `OpenUILang` | `Sources/OpenUILang` | 固定语言核心的桥接、AST/Value、解析与求值、Store、动作与查询语义、协议/序列化与运行预算 |
| `OpenUICore` | `Sources/OpenUICore` | 原生 state/session、组件注册与 schema 对接、context/host、递归渲染与身份、绑定和生命周期、通用资源通道 |
| `OpenSwiftUI` | `Sources/OpenSwiftUI` | 标准目录、标准主题与 presentation、布局就绪策略、表单与控件视觉、标准文本/媒体呈现 |
| `OpenIntelligentSwiftUI` | `Sources/OpenIntelligentSwiftUI` | Intelligent UI 目录、设计系统、组件/交互视觉、媒体呈现、函数及 reader/writer 生成契约 |

`COpenUIRegExp` 是语言层内部使用的 C target，不是新增的公开 UI 产品。两个 UI 库均可单独链接；不要求宿主安装另一套组件库。

## 2. 一个状态实例，一条语义更新链

`OpenUIState` 定义在 Core。它围绕 Lang 的 parser、Store、QueryManager 与动作执行能力，持有一份文档的运行状态：

- 接收完整源码或增量流，区分完成、中断、替换与 patch。
- 保存求值树、诊断、查询与 mutation 状态，执行绑定和用户状态写入。
- 维护 source revision 与 presentation revision，拒绝被替换文档的旧回调。
- 保留同一展示中的编辑草稿、资源通道与媒体缓存；独立重置/替换时清理相应生命周期。

组件库通过匹配的 schema 和注册函数创建 state，不再自建 parser 或 Store。两套 UI 库所暴露的 state 是同一个类型，但同一 state 的 schema 与用于渲染的 registry 必须匹配；共享类型不使两套组件契约互换。

`OpenUICoreView` 观察 state，并渲染显式传入的 registry。`OpenUIRenderer`、`IntelligentUIView` 分别添加各自的外观与阅读宽度规则；文档语义变化由 Core 观察，视觉包装层不重复观察同一 state 来重建整棵环境。

宿主长期持有 state，负责消息列表、模型/工具通信、账号权限、滚动和业务结果。尺寸拟合与布局测量只读取展示输入，不向 state 再次提交源码。

## 3. 注册、context 与 host

`OpenUIComponent` 将有序语言定义与原生 renderer 配对，`OpenUIComponentLibrary` 从实际注册内容产生 Library/schema、registry 和 Prompt。Core 不自带标准组件的默认注册。

`OpenUIComponentContext` 提供：

- 当前 element、资源、form/exact-form 名称与流式状态；
- 值读取、slot/child 渲染、绑定、字段和动作入口；
- 元素就绪与文档 epoch 检查；
- 供组件库扩展的 `values`。

Context 不包含标准主题、标准布局规则或具体组件名判断。标准表格单元格策略、布局参数就绪、文本/图片占位和 atomic card/form 行为留在 `OpenSwiftUI`。

`OpenUIComponentHost` 负责把 context 接到当前 state 和环境：解析保留节点的最新 readiness，绑定资源/form/交互环境，并在文档入口建立一次 program identity。后代不会重复安装相同显式 identity，流式追加也不会主动重置整棵展示。

标准库的 `NativeComponentHost` 包装 Core 提供的 context，应用标准组件的主题、布局、占位和媒体/流式视觉规则。当前节点的 stretch/fill proposal 在该边界消费，通过既有环境重置后不向下一层泄漏。Intelligent UI 组件与动作表面使用同一 Core context，继续读取自己的设计系统。

## 4. typed context values 与主题

Core 的扩展点只有 typed key/value 容器：

~~~swift
import SwiftUI
import OpenUICore

private enum ReadingInsetKey: OpenUIContextKey {
    static let defaultValue: CGFloat = 16
}

extension OpenUIContextValues {
    var readingInset: CGFloat {
        get { self[ReadingInsetKey.self] }
        set { self[ReadingInsetKey.self] = newValue }
    }
}

var values = OpenUIContextValues()
values.readingInset = 20
// 在宿主视图上使用 .openUIContextValues(values)
// 自定义组件读取 context.values.readingInset
~~~

key 由类型身份区分，避免字符串碰撞；默认值保持稳定，未设置与显式 optional nil 可区分。容器按值复制，保留其它组件库/宿主 key。不要把高频几何值、计时器 tick 或业务会话状态放入这个容器。

标准库扩展 `standardTheme` / `standardPresentation`，保留原 `context.theme` / `context.presentation` 与带主题的初始化入口。标准 `EnvironmentValues.openUITheme` / `openUIPresentation` 直接读写同一份 typed storage，因此嵌套主题、直接环境覆盖和自定义 Core 组件读取一致。组件 host 不重复把相同 typed values 下发到整棵子树。

Intelligent UI 的 `IntelligentUITheme`、editorial 规则和媒体视觉继续独立存在。Core 不理解任一套主题 token，也不把标准主题强制套到 Intelligent UI。

## 5. 共享资源机制与独立媒体呈现

Core 拥有 `OpenUIResourceLoading`、`OpenUIResourceLimits`、`OpenUIResourceContext` 及文档作用域内的资源/媒体基础设施：

- 宿主注入相对地址、请求与鉴权范围；
- 传输、并发、重定向、响应大小和解码预算继续受限；
- 同一展示可共享进行中的工作，同时保留订阅者取消与旧 epoch 隔离；
- state 结束或替换时取消相应工作，避免过期内容回填。

这些机制不决定图片比例、fallback、进度、预览、图库、地图、富文本或按钮样式。标准库的 `NativeRemoteImage` 等视觉组件仍属于标准库；Intelligent UI 保留自己的 `ImagePipeline`、图片/地图组件和呈现规则。本次没有把两套视觉图片管线合并成一个组件。

动作同样分层：Core 提供动作计划、context 检查与实际派发；标准 `OpenUIActionSurface` 和 `IntelligentUIActionSurface` 各自管理按钮视觉、进度与组件交互。

## 6. 渲染身份来自注册元数据

Core 不根据 `TabItem` 等组件名字猜测身份字段。组件库在注册时声明已经存在的 identity fields：

~~~swift
let item = OpenUIComponent(
    name: "ResultItem",
    description: "Application result",
    params: [
        OpenUIParameter.string("resultKey"),
        OpenUIParameter.string("title")
    ]
) { context in
    Text(context.string("title") ?? "")
}.presentation(identityFields: ["resultKey"])
~~~

该配置只使用组件已声明的参数，不增加 Lang 字段。注册表向递归 child renderer 提供 identity fields；未配置时沿用通用 `key` / `id` / `resourceId`、声明身份及位置回退。标准库自行注册 `TabItem` 的 `key` / `value` 规则，Core 无需识别这个组件。

layout/placeholder 的结构元数据也由组件注册提供。Core 只按已注册结构保留流式槽位；是否显示骨架、等待提示、何时等待布局参数等视觉策略由相应 UI 库决定。历史 statement identity、UTF-16 key 区分和重复身份处理继续保持原有语义。

## 7. 目录、契约与来源

当前源码和测试只在根 `Sources/` 与 `Tests/` 各自所属模块中维护。`OpenUI/Sources` 与 `OpenUI/Tests` 的历史软链接已移除，生成器和验证工具使用实际目录。

`OpenUI/` 保留 Tools、Validation、Fixtures、Examples、Documentation 和导入来源材料。[IMPORT.json](../OpenUI/IMPORT.json) 仍记录原始导入布局与哈希，[upstream.json](../OpenUI/Tools/upstream.json) 固定上游重建输入。历史来源文档不会因当前文件迁移而改写；当前可执行路径以根 Package 与构建工具为准。

本轮改变 Swift 模块边界与共享能力归属，保留现有 Lang 组件名、位置参数、枚举、绑定和 reader/writer 契约。标准目录与 Intelligent UI 目录继续独立生成各自 Prompt/spec，不混用两套定义或以布局改动为理由新增私有参数。

旧模块名、旧目录与过去验证记录见历史文档；新的 Swift import 使用 `OpenSwiftUI`、`OpenIntelligentSwiftUI` 及按需的 `OpenUICore` / `OpenUILang`。Swift 模块重命名与 Lang 契约变更是不同事项。

## 8. 验证边界

[原生流水线](../.github/workflows/native-sdk.yml) 对当前提交运行模块图/源码边界、独立产品消费者、原生测试、Release fitting、历史契约、固定 Gallery、资源重建和 iOS 编译。独立消费者通过编译器检查只链接一套 UI 产品时不会导入另一套库。

架构检查或源码搬迁完成不代表 Apple SDK 编译、真机界面或全部交互已通过。验收状态绑定实际提交及其流水线结果；安全依赖更新、源码候选修复及验证方式见[验证与安全修复](validation-and-security.md)。重构分支上的提交也不等于发布、打 tag 或合并主分支。
