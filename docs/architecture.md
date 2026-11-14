# OpenUI Swift 四模块架构设计

> 状态：目标设计，供后续重构执行；本次文档提交不表示模块拆分、接口迁移或验收已经完成。
> 设计基线：`f463eb4ac3c88261b736364068e6aaae6818b0e5`。
> 工作分支：`codex/swift-sdk-consolidation-rc21`。不修改 main，不发布 RC21。
> 本文是后续分包、命名与所有权的唯一设计入口。原迁移评审和验收记录保留其历史含义；其中旧目录与三模块结构不是新的目标架构。

## 1. 固定决策

一个仓库、一个根 Package.swift、四个主要 Swift target/product：`OpenUILang`、`OpenUICore`、`OpenSwiftUI`、`OpenIntelligentSwiftUI`。保留现有 `COpenUIRegExp` 作为语言层的辅助 target，不单独导出产品。示例、工具和测试 target 不算新的 SDK 层。

`OpenUILang/Runtime` 表示语言运行机制。`OpenUICore` 表示共享原生 UI 基础设施。二者不得混称为同一种 Core；不新增顶层 OpenUIRuntime、RenderKit、Primitives 或 Components 模块。

两套 UI 平级，互不依赖。每套 UI 的 Catalog、组件、设计系统与生成合同位于自己的模块。它们共用语言和原生机制，不通过另一套 UI 的具体 View 复用能力。

禁止新增平行 parser、evaluator、Store、DocumentRuntime；禁止把聊天列表、全局滚动、会话持久化、导航和交易执行纳入 SDK。模型可见的 DSL 组件名、参数顺序、Library ID、动作 payload、消息格式和历史读写合同不随 Swift 重命名改变。

默认 Markdown 后端沿用现有实现；本次结构设计不更换 Markdown 库、不新增组件、不提高最低系统版本。针对依赖安全问题的升级应独立提交并重新验证，不与纯目录迁移混为一谈。

## 2. 当前事实与设计依据

基线 manifest 仍导出 OpenUILang、OpenUISwiftUI、SwiftIntelligentUI，后者依赖前两者，并直接引用 MarkdownUI；Swift tools 6.0，iOS 16 / macOS 13，Swift language mode v5。[S1]

现有 OpenUIComponentContext 携带标准主题，组件宿主按 Card/Form/Image 等名称决定部分呈现规则；注册元数据已存在，但尚未覆盖所有这些规则。[S2][S3]

OpenUIState 已经拥有 parser、Store、QueryManager、文档身份与编辑记录，因此继续作为唯一文档状态入口。共享机制需要归位，不能在迁移旁边另建一套权威状态。[S4]

标准库的 NativeMediaCache 与 Intelligent UI 的 ImagePipeline 都承担请求、取消、解码和缓存，不能只移动文件后宣称共享完成。[S5][S6]

现有 IntelligentUILibrary 区分新生成 components 与历史 readerComponents。此区别保留；标准库与 Intelligent UI 的同名组件不能按名称自动合并。[S7]

以上是基线事实。以下模块、接口和目录安排属于本项目的设计决定，不是官方仓库现有结构的复述。

## 3. 模块边界与依赖

```text
OpenSwiftUI ──────────────┐
                         ├──→ OpenUICore ───→ OpenUILang ───→ COpenUIRegExp
OpenIntelligentSwiftUI ───┘
```

两套 UI 构造 Schema 时可以直接 import OpenUILang；图中省略该直接边。不允许下层反向 import UI 模块，也不允许两套 UI 互相 import。

| 模块 | 唯一职责 | 可直接依赖 | 不得包含 |
| --- | --- | --- | --- |
| OpenUILang | 官方语言核心的 Swift 桥接、协议值、解析、求值、Schema、语言状态机制 | Foundation、JavaScriptCore、现有 C 辅助实现 | SwiftUI、AppKit/UIKit 呈现、主题、图片、Markdown 排版 |
| OpenUICore | 文档 UI 生命周期、组件装配、视图映射、通用交互、共用文本与资源机制 | OpenUILang、SwiftUI、必要的平台框架、当前文本后端 | 标准 Catalog、Intelligent Catalog、某套主题默认配方、业务组件 |
| OpenSwiftUI | 标准 OpenUI 组件体系 | OpenUICore、OpenUILang、组件需要的平台框架 | 第二套运行状态、通用下载/取消实现、Intelligent 组件 |
| OpenIntelligentSwiftUI | Intelligent UI 组件体系及生成合同 | OpenUICore、OpenUILang、组件需要的平台框架 | 标准 UI 组件依赖、第二套运行状态、复制的通用资源管线 |

资源和文本后端集中到 Core 后，两套 UI 不再直接使用其第三方 API。Core 不承诺完全没有风格中立的 View：图片表面、富文本基础视图等可以存在，但只接受具体样式/行为配置，不读取某套 UI 的完整 Theme。

一个产品只导出对应 target，不用同一源文件列表编译出第二份实现。使用某套 UI 会依赖 Core 和 Lang，但不会在 target 依赖图中引入另一套 UI。整个 Package 的依赖解析仍可能解析声明的外部包；模块解耦不等于承诺最终二进制大小或解析时完全不访问其他依赖。

## 4. 最终目录

下列为归属结构，文件名是主要所有者，不要求一类型一文件。没有实际代码的细分目录不创建。

```text
Package.swift
Package.resolved
Sources/
├── COpenUIRegExp/                     # 现有私有辅助 target
├── OpenUILang/
│   ├── Bridge/                       # JSC、UTF-16、值与回调转换
│   ├── Parsing/                      # 单次/流式解析接口及相关类型
│   ├── Runtime/                      # Store、求值、Query、Action 的语言接口
│   ├── Schema/                       # 组件/函数/动作定义、Library、参数构造
│   └── Resources/                    # lang-core.js、manifest、notices
├── OpenUICore/
│   ├── State/
│   │   ├── OpenUIState.swift          # 文档门面与生命周期
│   │   ├── ElementIndex.swift         # 当前节点索引与受限匹配
│   │   └── EditingRecords.swift       # 文档作用域的未提交编辑记录
│   ├── Registration/
│   │   ├── OpenUIComponent.swift      # 定义、builder、呈现描述
│   │   ├── OpenUIComponentLibrary.swift
│   │   └── OpenUIComponentRegistry.swift
│   ├── Rendering/
│   │   ├── OpenUIRenderer.swift
│   │   ├── OpenUIComponentContext.swift
│   │   ├── ElementView.swift          # 递归呈现与紧密相关的私有视图
│   │   ├── RenderIdentity.swift
│   │   └── StreamingPresentation.swift
│   ├── Interaction/
│   │   ├── FieldBinding.swift
│   │   ├── FormSession.swift
│   │   └── ActionDispatch.swift
│   ├── Text/                         # 处理、准备调度、代码/公式、基础视图
│   ├── Media/                        # 请求作用域、图片管线、图标/矢量基础能力
│   └── Resources/                    # 共享脚本、图标数据、本地化与许可文件
├── OpenSwiftUI/
│   ├── OpenSwiftUIView.swift
│   ├── Catalog/                      # OpenSwiftUILibrary 与标准集合
│   ├── Components/
│   │   ├── Layout/
│   │   ├── Content/
│   │   ├── Controls/
│   │   ├── DataDisplay/
│   │   └── Media/
│   ├── DesignSystem/                 # OpenSwiftUITheme、tokens、recipes
│   └── Resources/
└── OpenIntelligentSwiftUI/
    ├── OpenIntelligentSwiftUIView.swift
    ├── Catalog/                      # Library、reader/writer 投影
    ├── Components/                   # 与标准库采用相同类别，但独立实现
    ├── DesignSystem/                 # OpenIntelligentSwiftUITheme
    ├── Functions/
    ├── Generation/
    └── Resources/
Tests/
├── OpenUILangTests/
├── OpenUICoreTests/
├── OpenSwiftUITests/
└── OpenIntelligentSwiftUITests/
Examples/                             # 标准接入、Intelligent Gallery、纯自定义库
Tools/                                # 上游锁定/补丁、生成、contract 导出与检查
docs/
└── architecture.md                   # 本设计的唯一入口
```

Core 可以提供通用几何测量辅助，但 Stack/Grid/Card 的布局算法和配方归各自 Components/Layout。地图和图表仍归各自组件库；不因两边使用 MapKit 或 Canvas 就强行合并 View。

迁移完成后不再长期保留 OpenUI/Sources 与根 Sources 两套生产结构。原始来源与 hash 留在 import manifest、Git 历史和评审记录，不靠嵌套旧仓库目录表达来源。现有历史文档不删除验收事实；其中架构部分标注对应旧提交，并链接本文。

## 5. 命名与可见性

### 5.1 公开接口

| 名称 | 所属模块 | 定义 |
| --- | --- | --- |
| OpenUIState | OpenUICore | 一份文档的原生状态门面；不是另一个语言 Store |
| OpenUIRenderer | OpenUICore | 对给定状态与注册库进行风格中立的原生渲染 |
| OpenUIComponent / OpenUIComponentContext | OpenUICore | 注册定义与组件所需上下文 |
| OpenUIComponentRegistry / OpenUIComponentLibrary | OpenUICore | 原生映射及其与语言 Library 的配对 |
| OpenUIResourceLoading / OpenUIResourceLimits | OpenUICore | 宿主资源注入与预算边界；沿用已有接口的语义 |
| OpenUIParameter | OpenUILang | 参数 Schema 构造，不要求使用 SwiftUI |
| OpenSwiftUIView / OpenSwiftUILibrary / OpenSwiftUITheme | OpenSwiftUI | 标准库的接入、装配和视觉入口 |
| OpenIntelligentSwiftUIView / OpenIntelligentSwiftUILibrary / OpenIntelligentSwiftUITheme | OpenIntelligentSwiftUI | Intelligent 的对应入口 |

共享类型保留 OpenUI 前缀，不改成 OpenSwiftUIState 或 OpenIntelligentSwiftUIRenderer。语言的 Value、ActionPlan、Store 等保留语言术语，不机械加产品前缀。不建立第二个 State 类；不主动增加多个品牌状态别名。

内部类型使用职责名：ImagePipeline、ImageMemoryCache、ImageDecoder、RichTextProcessor、FieldDraft、FormSession、RetainedElementView。只有真实区分平台后端时才使用 Native/Web 前缀；不使用 Manager/Engine/Helper 作为无法归类的兜底。

公开入口使用 product 前缀；私有 MapView、SliderFieldView 等使用模块命名空间，不复制长前缀。Markdown、URL、SVG、UTF16 等术语拼写统一。相关小型私有类型可与主体同文件，独立职责不能为减少文件数硬合并。[A1]

### 5.2 访问级别与导入

外部宿主/自定义组件作者真正需要的接口使用 public。同一 Package 的两套 UI 共用但不支持外部直接调用的能力使用 package；单模块实现用 internal；局部实现用 private。不得用 public 暴露所有内部缓存或通过 @_spi 绕过设计边界。[A2]

文档示例明确 import 使用的模块，不依赖隐式传递导入或 @_exported 的隐藏行为。例如需要直接声明 OpenUIState 的宿主 import OpenUICore，加上选择的一个 UI 模块。普通库工厂负责提供 schema/registry，宿主不必手工拼两份可能不匹配的配置。

## 6. 注册、上下文和主题解耦

### 6.1 注册描述是唯一装配点

保留“一个 OpenUIComponent 配对语言 DefinedComponent 与原生 builder”的模式。OpenUIComponentLibrary 从同一组组件生成语言 Library 和原生 Registry，禁止维护互不校验的两份组件清单。

在现有 presentation 元数据上收敛一个有类型的呈现描述，表达经过验证的身份字段、布局就绪字段、渐进文本字段、资源来源字段、交互范围和占位策略。仅加入现有行为或真实自定义组件场景需要的字段，不做任意行为脚本系统。

Card/Form 的交互范围、TabItem 的身份字段、图片 src 的就绪条件等由所在 Catalog/组件声明。核心不得继续使用 typeName == "TabItem" 或组件名称数组决定这些规则。错误声明须在装配/校验时得到诊断，不能静默丢失后让宿主猜测。

元数据不是授权机制：不能绕过资源权限、过期文档检测、语言预算、ActionPlan 的语义就绪或非法草稿拦截。占位内容不可执行动作；展示用的临时值不自动成为提交值。安全默认应保守，预览不完整内容与允许执行动作必须分开。

### 6.2 Context 不再携带标准 Theme

OpenUIComponentContext 保留元素、值读取、绑定、动作、子项渲染、文档/表单范围和必要就绪信息。移出标准 Theme、表格单元格风格和具体卡片配方。

两套 UI 的具体 View 通过各自 Environment 读取自己的 Theme。Core 的共用文本/图片视图接收已经解析的 Font、Color、边距或具体行为配置，不要求认识整个产品 Theme。可使用小型 package 样式值组合，禁止建立一套覆盖两套产品的第三份巨型 token 表。

OpenSwiftUIView 和 OpenIntelligentSwiftUIView 是薄装配入口，分别选择本库 Catalog、默认主题及行为，再调用共同 OpenUIRenderer。Core 仅使用平台中立默认或调用方传入的样式，不主动注入标准组件主题。

### 6.3 Catalog 与生成合同

两个 Catalog 独立构造、独立测试，不自动 union。相同 DSL 名称可以有不同组件合同；同一文档必须携带其匹配的 Library，不能看到名称相同就复用另一个 builder。

Intelligent 的 reader 保留历史兼容，writer/Generation 由当前 Catalog 投影得到，不能重新手写第二份参数规范。移目录不更改历史 Library ID；改合同必须作为单独、显式的协议变更。

## 7. 状态所有权与生命周期

| 数据/工作 | 所有者 | 清理与一致性 |
| --- | --- | --- |
| 已提交字段、绑定值、语言求值 | OpenUILang 的既有 Store，实例由 OpenUIState 持有 | 一份文档一个权威 Store，不双写 Swift 字典真值 |
| parser、QueryManager 生命周期及订阅 | OpenUIState | 按文档替换/中断语义取消或失效，继续复用语言机制 |
| 未提交、暂时非法的字段草稿 | Core 中文档/表单/字段作用域的编辑记录 | 临时卸载保留；文档替换清理；字段真正移除时按策略释放 |
| 焦点、按下效果、选中动画 | 组件局部状态 | 不写入语言 Store，也不因持久化草稿而全部全局化 |
| 图片/公式任务、结果缓存 | Core 资源作用域 | 与宿主授权和文档身份绑定；释放时取消独立订阅 |
| 对话列表、会话存储、支付/导航 | 宿主 App | SDK 只发事件，不接管业务 |

保持 sourceRevision 与 presentationRevision 已有、不同的含义，不借结构迁移把其含义改成新的 token 计数。新增统计编号只能用于诊断，不能替代文档身份。追加不得重置整个文档的 .id；真正替换不得保留旧文档的任务回写权限。Patch 和 source replacement 不能无差别当成 reset。

OpenUIState 继续协调处理顺序，可委托 ElementIndex、EditingRecords 和 ResourceScope 等已有职责的内部实现。它不实现图片解码算法，也不扩展成任意服务定位器。不为每个属性创建 Manager。

OpenUIState 与 UI 发布保持 MainActor 约束。JSContext 按既有隔离规则访问，不因一个 Task.detached 就假定可以并行调用。纯内容准备、解码等可按后端的线程合同离开 UI 关键路径。现有同步 push/setSource 调用不能在本次重构中悄悄变成返回未处理结果的异步 API。

## 8. 流式、更新和测量合同

```text
宿主分片
  → OpenUIState 顺序接收
  → OpenUILang 解析/求值
  → 已有结果与就绪信息
  → OpenUIRenderer / 注册 builder
  → 所选 UI 库的组件
  → Core 的文本/媒体基础能力与原生布局
```

保留 OpenUI 源码与字段 Markdown 是两种语言这一事实。不得通过统一命名消掉必要的 Markdown 处理，也不得重复实现 OpenUI 解析。

源码保持精确顺序与 UTF-16 语义，完成与中断分别处理。显示层允许合并尚未显示的可替代文本快照，但不能丢字段编辑、动作或终止屏障；持续输入不能一直等待空闲才出现关键内容。保留一处主要富文本准备调度，多个视图不得各叠加独立 debounce。

节点身份来自稳定声明/注册身份策略，不能来自不断变化的正文、随机 UUID 或每次 body 重算。没有显式稳定 key 的匿名重排不承诺自动恢复全部状态；对此应诊断或说明，而不是伪造稳定性。

测量只读取当前呈现状态、执行原生布局和必要局部缓存；不得 setSource、写字段、执行工具或重建文本宿主。允许正常父布局发生，性能目标是避免无关语义计算和昂贵重建，不是要求所有祖先 body 永远不执行。

不采用跨文档全局高度缓存。局部缓存的失效至少包含内容版本、宽度、字体/字号、Dynamic Type、主题中实际影响几何的值、方向和资源尺寸状态。尺寸通知去重且不形成测量→状态写回→再次测量的反馈环。

## 9. 表单与动作合同

Core 复用语言层的 validate/规则机制；FormSession 负责字段登记、顺序、未挂载字段、编辑准备、错误和焦点请求，不包含某套输入框的错误颜色或布局。

标准库的 NativeFieldState 中涉及 Chips/OptionCards 默认值等分支留在标准库的字段适配；Intelligent 的不同字段合同使用自己的适配，不并入“万能字段状态”。

需校验的语义动作遵循：确认文档仍有效 → 检查未提交草稿能否表示合法值 → 按声明顺序刷新有效编辑 → 使用最新 Store 校验 → 再确认动作/文档有效 → 派发一次动作。发现非法草稿不得提交旧值或隐式零值。未要求校验的导航等动作沿用其既有合同，不以按钮颜色决定。

字段/session 持有的回调不得强持有整个文档形成环。卸载旧视图不能注销替代它的新 owner。错误数据由 Core 提供；每套 UI 指定单一展示责任，避免重复提示。错误揭示通过字段与容器注册关系完成，不硬编码 Tab 名称。

## 10. 公共文本与资源能力

### 10.1 图片和网络

目标是一套 ResourceScope + ImagePipeline 实现，两套 UI 提供自身的图片 View 与回退样式。仅有一个全局 shared 不算完成共享架构。

作用域由宿主资源配置和文档生命周期确定，普通宿主有合理默认，高级宿主可注入既有 OpenUIResourceLoading。请求键不能仅包含 URL：需要考虑 loader/授权身份、请求差异、内容版本和解码目标；敏感凭据不进入公开日志。切换授权、替换文档或取消后，旧结果不得写回当前作用域。

独立订阅分别响应取消；只取消一个不杀死其他订阅，最后一个退出时结束共享工作。缓存命中和完成竞态也必须检查调用方取消。下载字节、在途压缩数据、源像素、解码并发、解码结果缓存与外部 View 持有成本分别核算，不能用一个 cache cap 声称全进程内存有界。

图片管线返回结果和状态，不决定显示“图片不可用”、折叠高度或 POI 图标。这些决策属于 UI 组件：保持本轮标准库的语义回退与稳定几何，也不静默替换 Intelligent 的现有排版。

### 10.2 富文本、代码、公式、图标和 SVG

Core/Text 收敛可复用后端、内容准备与取消机制；两套 UI 映射各自语法模式、引用模型和文字样式。标准库 CardSource 等产品语义在进入共用处理器前转换为中立的引用数据，不让 Core 依赖卡片类型。

不同文本组件是否允许单美元数学、如何换行、如何复制代码、引用如何触发宿主动作，都按已存在的合同参数化。不能因统一后端改变内容含义；无法等价的差异保留明确的适配，而不是假定两个同名 Markdown 组件等价。

公式/向量引擎只处理受限数据，具有预算、超时、取消和身份校验；不执行模型提供的任意脚本。用户主动使用的 HtmlView 等能力与公式通道隔离，不把较宽权限传递给共享渲染器。

图标绘制可共用实现与必要数据；两套 Catalog 的图标名称、别名、默认与缺失回退由各自适配声明。不得把任意 Lucide 名称静默转换为另一含义的 SF Symbol。

## 11. 静态资源与生成工具

资源必须由实际使用它的 target 拥有。语言脚本归 Lang；公共文本/公式/图标资源归 Core；某套组件样例、主题或专属文案归其 UI 模块。复制同一资源到两个 target 不是共享。

各 target 用自己的 Bundle.module/资源访问器，不让 Core 去查标准组件库的 bundle；本地化也按所有者检查。需要同包使用的访问器可以 package，不能把 Bundle.main 或旧 bundle 名硬编码进客户端。资源随 target 打包、Bundle.module 为模块内访问入口是 SwiftPM 的资源机制。[A3]

维护工具统一到根 Tools，并保留固定上游 revision、锁文件、显式补丁、hash、许可证与 notices。App 不在运行时下载官方源码，不运行 npm。当前公共 npm 接口不能直接替代所有原生 helper；这份设计不声称已消除全部原生适配。[S8]

纯搬迁不改变运行资源字节基线；已知跨平台图标几何比较策略保留，不能为了迁移随意放宽。安全依赖升级单独更新 lock、资源和 notices，并重新跑语义对照。

## 12. 现有实现到目标的迁移表

| 当前基线位置/类型 | 目标 | 操作与必须保留的合同 |
| --- | --- | --- |
| OpenUI/Sources/OpenUILang | Sources/OpenUILang | 按 Bridge/Parsing/Runtime/Schema 归位；不重写官方算法 |
| OpenUIState.swift | OpenUICore/State | 保留门面、Store 权威性、完成/中断/替换语义；独立算法移到就近内部实现 |
| Renderer.swift、RenderNode.swift | OpenUICore/Rendering 与 Registration | 注册表独立；拆出产品主题和组件名特例；递归视图与紧密辅助类型可同文件 |
| GenUILib/ComponentLibrary.swift | Core/Registration；OpenUIParameter 到 Lang/Schema | 保留 definition 与 builder 配对；参数构造脱离 SwiftUI |
| GenUILib 标准清单与 ReferenceCatalog | OpenSwiftUI/Catalog | 不混入 Intelligent reader/writer |
| Context/ComponentContext.swift | Core/Rendering + 各自组件适配 | 共享上下文去标准 Theme/表格特例；两套 UI 自己读取 Theme |
| NativeFormValidation | Core/Interaction/FormSession | 通用校验协调与登记，不包含标准组件默认值规则 |
| NativeFieldState 的标准组件分支 | OpenSwiftUI/Components/Controls | 命名 StandardFieldAdapter；不把组件名分支移进 Core |
| NativeMediaCache / ImagePipeline | Core/Media 的统一管线 | 先合同并集与差异测试，再删除重复加载实现；不切换到全局缓存 |
| NativeRichTextEngine、相关准备实现 | Core/Text/RichTextProcessor 等 | 处理与 UI 外观拆开，保留两套语法模式与复制行为 |
| ElementErrorBoundary | Core/Rendering/RetainedElementView | 保留上一次有效节点的行为，不声称捕获 SwiftUI 崩溃 |
| 标准组件与 Theme | OpenSwiftUI/Components、DesignSystem | 具体 View 与配方保留；公开主题改为 OpenSwiftUITheme |
| Sources/SwiftIntelligentUI | Sources/OpenIntelligentSwiftUI | 产品入口统一改名；读写合同、函数与组合规则保留 |
| 两处生成脚本/fixture 路径 | 根 Tools 和对应 Tests | 更新相对路径、bundle 与历史基线读取，不重造 expected |

该表定义迁移方向，不表示每行已实现；提交日志应逐步说明完成的范围，不能将“已搬文件”当作“已统一机制”。

## 13. Swift API 迁移策略

模块名 OpenUISwiftUI → OpenSwiftUI，SwiftIntelligentUI → OpenIntelligentSwiftUI；共享接口移入 OpenUICore。ComponentRegistry → OpenUIComponentRegistry。IntelligentUIView/IntelligentUILibrary 改为对应 OpenIntelligentSwiftUI 前缀。OpenUIThemeValues 等标准主题入口归标准库，不保留在共享 Context。

这是一次明确的源码级不兼容迁移：import、部分公开类型与 Context 主题读取方式需修改。不得称为二进制兼容或零成本升级。为避免再次出现多套长期命名，本目标不新增旧模块空壳或复制实现；保留已发布 tag，不移动旧 tag，提供精确迁移表并编译迁移后的客户端示例。

宿主使用的 language Value/ActionEvent 等语义不变；新 UI 库仍通过 factory 构造匹配的 OpenUIState。通常只需选择一套 UI；需要直接引用共享类型时显式 import OpenUICore，不假设传递导入自动公开符号。

OpenSwiftUI 的名称按用户决定保留。它与 OpenSwiftUIProject 的外部同名模块存在共存风险；该风险记录在接入文档，不在这次设计中继续换名，也不宣称同 App 同时引入两个同名模块无需处理。

## 14. 实施顺序与完成证据

| 阶段 | 改动 | 必须取得的证据 |
| --- | --- | --- |
| 1. 固定基线 | 导出两套 reader/writer、公开 API 和资源清单；保留现有行为测试 | 明确 SHA，语义字段/参数顺序不归一化掩盖差异 |
| 2. 语言与路径归位 | 移动 Lang/C 辅助源、测试与生成器；不改语义 | 语言测试、ASan、上游 oracle、重建一致性 |
| 3. 提取 Core | 状态/注册/渲染/交互归位，去主题与组件名依赖，最小自定义库可运行 | Core 单独构建/测试，自定义组件无默认库依赖，生命周期/权限不退化 |
| 4. 两套 UI 命名与接入 | 模块/公开入口迁移，Themes 独立，公共文本/媒体接入 | 两套 Catalog 完整回归、历史 reader、资源与外观对照，重复机制删除 |
| 5. 集成交付 | Gallery、Examples、工具、文档路径与 release notes 对齐 | 同一最终 SHA 的工程、原生视觉、流式和资源证据；无放宽断言 |

拆分过程中允许短暂的迁移适配，但最终交付不能留下两份生产管线或长期双模块命名。不要在单次迁移同时更换文本后端、提高部署版本、重写组件外观或改变语言协议。先保证可归因的差异，再做独立优化。

## 15. 验收标准

**依赖**：四个主要 target 的有向图无环；两套 UI 不互相 import；Lang 无 UI 依赖；Core 不引用两套 UI 的类型。校验 manifest 与真实编译，不只 grep。

**扩展**：只依赖 Core/Lang 的外部样例能定义不同名称的组件、稳定 key、字段、动作和资源策略；不修改 Core 名称列表。外部样例只用 public API；package API 由包内测试验证。

**合同**：两套 Catalog 的组件名称、参数顺序、绑定、动作、根组件、reader/writer 差异与基线逐项比较。变更须解释，不自动更新 golden。

**状态与流式**：追加、重复全文、同长度修正、回退、正常完成、中断、patch、文档替换、晚到异步回调；稳定控件身份、草稿、焦点和原生输入法组合态保持正确。实测真实 Markdown 增长与重复拟合，不用普通 Text 或固定内容替代增长测试。

**交互与资源**：非法数字不能提交旧值；未挂载字段可揭示；D1–D5 保留为回归；共享图片订阅独立取消、授权隔离、请求/解码预算、公式重入与 SVG 失败均测试；同时报告缓存与活跃持有的区别。

**视觉与适配**：两套 UI 分别检查浅/深色、窄/宽、大字、RTL、加载/失败/缺图、长中文、键盘/VoiceOver；真实宿主截图实际检查，不能以 PNG 生成成功当作视觉通过。测试边界不足的项如实记录，不能以架构整洁覆盖缺陷。

**性能**：同设备、同工具链、同回放和配置做前后对比，测接收/求值/发布、准备、拟合、布局与资源成本；不编造统一 ms 阈值或用 Mac 样本宣称 iOS FPS。拆包本身不构成性能优化证据。

**发布**：安全、构建、原生测试和支持范围在同一个最终 SHA 上确认。设计签收不等于代码签收。历史报告属于 `2308c31367c55cefc4f36bff3bebd11e08537823`，不能签收迁移后的版本；本设计文档也不关闭已有发布阻断、不授权改变仓库可见性或移动标签。[S8]

## 16. 来源与边界

### 基线源码

- [S1 Package.swift](https://github.com/zyfn/open-intelligent-ui-swift/blob/f463eb4ac3c88261b736364068e6aaae6818b0e5/Package.swift)
- [S2 ComponentContext.swift](https://github.com/zyfn/open-intelligent-ui-swift/blob/f463eb4ac3c88261b736364068e6aaae6818b0e5/OpenUI/Sources/OpenUISwiftUI/Context/ComponentContext.swift)
- [S3 ComponentLibrary.swift](https://github.com/zyfn/open-intelligent-ui-swift/blob/f463eb4ac3c88261b736364068e6aaae6818b0e5/OpenUI/Sources/OpenUISwiftUI/GenUILib/ComponentLibrary.swift)
- [S4 OpenUIState.swift](https://github.com/zyfn/open-intelligent-ui-swift/blob/f463eb4ac3c88261b736364068e6aaae6818b0e5/OpenUI/Sources/OpenUISwiftUI/OpenUIState.swift)
- [S5 NativeMedia.swift](https://github.com/zyfn/open-intelligent-ui-swift/blob/f463eb4ac3c88261b736364068e6aaae6818b0e5/OpenUI/Sources/OpenUISwiftUI/Components/NativeMedia.swift)
- [S6 ImagePipeline.swift](https://github.com/zyfn/open-intelligent-ui-swift/blob/f463eb4ac3c88261b736364068e6aaae6818b0e5/Sources/SwiftIntelligentUI/Components/Media/ImagePipeline.swift)
- [S7 IntelligentUILibrary.swift](https://github.com/zyfn/open-intelligent-ui-swift/blob/f463eb4ac3c88261b736364068e6aaae6818b0e5/Sources/SwiftIntelligentUI/Catalog/IntelligentUILibrary.swift)
- [S8 迁移评审历史](https://github.com/zyfn/open-intelligent-ui-swift/blob/f463eb4ac3c88261b736364068e6aaae6818b0e5/docs/openui-integration-review.md)

### Swift 平台依据

- [A1 Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- [A2 Swift Access Control](https://docs.swift.org/latest/documentation/the-swift-programming-language/accesscontrol/)
- [A3 Bundling resources with a Swift package](https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package)
- [SwiftPM Target](https://docs.swift.org/latest/documentation/packagedescription/target/)

平台资料支持 target/访问级别/资源与一般命名原则，不意味着 Swift 官方规定本项目必须采用这四个模块或上述目录。
