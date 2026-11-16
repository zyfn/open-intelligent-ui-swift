# OpenUI

文档版本：1.2 · 更新日期：2026-11-16

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

### 阅读层级与可用宽度

默认呈现按内容角色组织：章节标题统领对象，正文承载核心解释，辅助文字用于元信息。使用既有语义 token 调整组件配方，不全局放大字号或增加一套主题。

- CardHeader 使用章节角色；InlineHeader 与图文对象保留对象标题角色。首轮实现以现有 20 / 18 pt token 形成层级，具体视觉比例仍需原生对照。
- Steps 的解释属于正文。ListItem 的 subtitle 继续表示辅助信息；需要多段核心解释时，组合 TextContent/Markdown，而不是把正文都放进小号副标题。
- 主 Metric 与行内数字按角色区分；数值和单位保持完整，超长金额不缩字号或截断小数。
- 图片加说明的 OptionCards 优先保证阅读宽度。最小阅读宽度初始采用 200 pt，并按字体尺度增长；宿主仍能覆盖该参数，辅助阅读字号继续单列。列数由当前位置可用宽度决定，不随流式文案字数反复变化。
- 外层任务面板、内部布局与输入控件各自承担分组职责。利用已有 Stack、clear Card 与 formShowsCardSurface 处理重复 inset；渲染器不按嵌套层数擅自改写显式 Card。
- 选择模式和必填信息应在开始操作时可见；原始校验规则是唯一依据，不要求作者维护另一份必填声明。

默认值是可覆盖的呈现策略。显式尺寸、布局方向与输入内容继续按契约处理；Form 唯一提交的局部满宽规则见下节。

## 状态、字段与动作

组件通过 OpenUIComponentContext 的 value/string、children/slot、binding、field 和 action 方法接入；不直接改写整份 state 或绕过 Context 执行动作。context.string 是显示便利方法，精确字符串与键使用 OpenUIString/Value，不能在协议、身份或资源键上引入 Unicode 归一化。

可写控件区分文档 Store、局部编辑草稿和提交结果。Select、Radio、Checkbox、Switch 的用户选择须在首次操作后反映到当前展示；Store-only 的更新也必须使叶子 View 刷新。无可写绑定的字面值不能被当作可写状态。

字段验证通过共享规则与 Context 执行。被拒绝的草稿不能因其它 Store 发布而提交；源码替换使原草稿、旧动作和旧异步结果失效。EditableTable 的本地交付回执不代表远程持久化。Slider 的离散格点考虑 minimum 与 step 的精度，范围末端、拖动和连续文本按各自已有规则校验。

UI 特有的点击项上下文可以由组件提供；通用状态、动作执行顺序、异步取消和文档就绪检查由适配层负责。表单和资源的精确名称保留 UTF-16 语义。按钮、卡片动作与本地选择在拖动/分页结束时不能误派发激活。

### 表单单提交与继续对话

Form 自己的 buttons 槽总共只有一个稳定声明的标准提交 Button 时，按钮铺满字段列，保留 Form 自身的 inset。提交包括继续对话、mutation 与自定义提交动作；纯导航、Set/Reset 和 Query 不据此自动铺满。

满宽与 variant/role 独立，保留来源声明的 primary、secondary、tertiary 或 destructive 样式。单项 row 与 column 均可满宽；多个动作、Form 外按钮、字段内部动作、商品 footer 与表格单元格继续使用原布局。只有列表和必要参数稳定后才认定“只有一个”，不将流式暂时出现的首项当成唯一项；布局变化保持同一控件子树。

继续对话使用完整文字与前进箭头：

| 场景 | 默认呈现 |
| --- | --- |
| 标准继续对话按钮 | label 与箭头组成居中的内容组，继承原按钮字体、前景和表面 |
| FollowUp | 纵向轻量问题行；全文 leading 对齐，箭头在 trailing 固定槽并对齐首行；常态无胶囊、底色或描边 |
| Performing | 保留文字，在预留附件槽延迟显示进度；测量宽度不变 |
| Pending / Disabled | 区分尚未就绪与宿主禁用，均不冒充已完成；辅助功能说明状态 |
| 校验失败 | 先展示并定位字段错误，不派发继续对话 |

整行或整个按钮都是同一个点击目标，箭头不形成第二个按钮。图标使用 forward 语义并遵循 RTL，只作为装饰朗读；按压、hover 和键盘焦点有轻量反馈。长中文自然换行，触控尺寸与可见外形分开处理。

箭头按真实且已就绪的 action 分类，不按中文 label 猜测：FollowUp、明确的 continue_conversation、最终 nil/null 的默认继续对话，以及本地 Set/Reset 配合单个 ToAssistant 可以采用；混合 mutation/custom/open_url 等外发意图时保守保留原动作表达。分类不执行消息 AST 或触发工具。

可见 label、实际 message、params/context、formName 与派发时 formState 完整保留。ToAssistant 的 message 可与 label 不同；legacy 对象继续使用原 dispatcher 的消息来源。提交仍先刷新草稿、再校验、再派发。SDK 的 performing 只覆盖本次 await，不承担整轮 Agent 回复状态，也不自动宣告远端保存成功。

### 控件完成度

- 范围 Slider 的两个端点使用明确的上下限语义；空间不足时内部数值布局转为纵向，保留草稿与焦点。
- Tabs 的溢出提示应与实际剩余空间一致；单个标签宽度包含水平内边距。RTL、末端位置与键盘激活按原生行为验收。
- DateRange 的清空操作明确为“清空日期范围”，保留整个范围清空的既有数据语义；自动调整另一端后显示完整最终范围。Cancel 不保存草稿，Done 才确认。
- 选择卡、Tabs、FollowUp 具备一致的最低按压和焦点反馈，禁用说明与错误信息保持可辨。适用文本字段从已有声明顺序获得下一项/完成流程。

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

图片的稳定身份包含精确来源、baseURL、loader、授权作用域、资源限制和重试次数；实际请求在一次加载尝试内冻结。不能在布局、状态回调或完成校验中重新调用可能生成新 nonce 的签名器。请求快照继续依附既有文档媒体缓存并有容量上限，重试与作用域变化建立新请求，文档重置清理快照；图库选中/状态及背景图状态使用同一稳定身份。

Map 表达来源坐标与选点，不表示真实导航、实时交通或已完成业务操作；当前 Map 组件整体要求 iOS 17/macOS 14，较旧的受支持系统显示版本要求占位。SVG 要求有效 viewBox，使用内联内容或 HTTPS src，拒绝活动内容和外部引用。

### 地图与媒体

- 地图保留现有大小和 320–360 pt 高度策略。本轮不统一缩小地图、工具或编号图钉。
- 缺图在原透明缩略图槽中央显示 mappin.and.ellipse。没有额外色块、圆盘、描边或阴影；地点卡片自身的表面继续保留。无 URL、等待、失败、恢复与成功淡入遵守同一占位规则，照片加载不挤动相邻文字。
- 紧凑地点卡保留稳定摘要，同时提供组件内完整详情。没有外部 URL 也能阅读完整名称与说明；外部页面入口与地图展开各有明确用途。
- 主内容图失败保留说明和恢复入口；普通缩略图、图文卡与图库图片缺失或失败时保留可见的 photo 占位，不静默变成空白。有有效地址的加载失败允许手动重试，无地址或无效地址不发起空请求；地图继续使用无底色的 POI。所有状态保留声明的几何与资源身份，重试只由用户操作或来源变化触发，不由尺寸测量触发。照片封面与信息图片的完整查看按用途处理。
- 图库的总数/查看全部入口独立于某张缩略图加载成功，前五张失败也能进入完整集合。
- SVG 提供完整查看路径，保留 viewBox 与安全边界；作者提供替代描述和主题友好的图形颜色，renderer 不自动反色或虚构图意。

### 图表、表格与图文对象

- 常规图表暂保留 250 pt 绘图区基线，饼图/径向图与单条比例图继续各自的高度策略；按类型、标签、字体和数据量调整密度，保留合法的显式高度。
- 比例条的绘制与命中共享几何。合法全零数据有明确表达；选中图形与检查详情对应。Line/Area 的图形与图例增加按源序列身份分配的线型，隐藏系列后保留颜色和线型；其他类型继续通过现有图例与检查详情辨识。
- 普通检查使用轻量浮层，尺寸受图面与图例的实际可用区域约束；放不下时使用提示或隐藏浮层，不挤压和截断完整值。独立的“查看图表数据”入口始终位于浮层区域之外，详情可滚动阅读全部系列，包括暂时隐藏的系列。
- 表格保留完整换行、数值对齐、溢出提示和自定义单元格。宽表提供“按行阅读/表格视图”切换，按原列标题逐项阅读，不默认把任意第一列当作主键。两种排列复用同一 cell 子树；编辑默认列宽考虑字号，显式列宽与修改/保存/冲突状态继续保留。
- 背景图卡保留长文移到图外的策略，轮播保留稳定高度；遮罩强度与内容密度以真实样张对照，不在流式中反复改变照片比例或推挤下方内容。

Charts、原生选择器、滚动与表格采用 Apple 平台实现。确有原生差异时保留输入语义并按实际 View 验收，不能把“来源相同”写成逐像素等价。来源映射以 Catalog 和固定生成输入为准，历史差异在 Git 中，不维护另一份逐文件映射文档。

## 验证入口

~~~sh
swift test --filter SwiftOpenUITests
python3 Tools/check_gallery_catalog.py
./Examples/Gallery/verify.sh
~~~

纯注册与解析不能替代控件交互或视觉验收。涉及文字、选择、草稿、尺寸、主题或媒体时，在对应宽度、外观和字号运行原生场景，记录实际行为；图片、案例和模拟工具继续由 [Gallery](../Examples/Gallery/README.md) 管理。

### 本轮实施与验收状态

上述设计在本轮原位维护；实现状态在这里更新，不另建版本后缀文档或执行报告。

当前状态：首版 UI 改造及下述已确认缺陷的源码修正已完成，原生验收待执行。没有改变 Lang 参数、消息与字段契约；共享内核的流式预算修正及性能验证边界见[验证说明](validation-and-security.md)。

原生验证反馈暴露出普通图片失败回退的遗漏：`2ae6ced` 之前已有的透明回退仍用于多数缩略图、图文卡与 Markdown 图片，且普通图片自身的重试交互被一并关闭。本次修正为可见的图片占位，并恢复有效请求失败后的手动重试；保留主内容图的完整失败说明和地图 POI 的独立规则。对应回归继续验证缺失/失败/恢复、原尺寸以及测量不触发请求；新增原生测试仍须在 Swift/Xcode 环境执行。

本次另修正签名请求被反复重建导致成功图片/图库状态被丢弃的问题，并补充签名加载、重试、换源、换授权作用域及旧响应晚到的挂载回归。远程 SVG 也按稳定来源启动请求；停止流式时，尚未闭合的 src 不再保持无限加载提示。上述原生行为不能仅凭源码和 JavaScript 检查认定验收通过。

| 范围 | 已实现的首版 | 尚需确认 |
| --- | --- | --- |
| 地图与动作 | 透明 POI、原尺寸、地点完整详情；单提交满宽；语义箭头、FollowUp 纵向行与附件进度 | 实际点击、地图内嵌/展开、焦点、RTL、流式和进度切换 |
| 阅读与控件 | 章节/对象标题、Steps 正文、主指标层级、选项阅读宽度；必填/多选提示、Slider 端点、Tabs 滚动操作、日期范围、文本字段下一项 | 长中文、窄列、辅助阅读字号、禁用状态和键盘操作 |
| 媒体与数据 | 内容图失败说明/重试、独立图库入口、图片/SVG 完整查看；比例条几何、全零状态、图表详情与线型；表格按行阅读和编辑宽度 | 真实资源失败/恢复、缩放与关闭、长数据读取、自定义 cell 状态保持 |
| 回归与来源 | 修正视觉矩阵中错误的 Button 参数槽，新增针对性行为/布局回归；沿用现有完整 Gallery 场景和原始 fixtures | XCTest、Gallery 原生交互、截图对照与 Release 尺寸隔离 |

已执行的 `git diff --check`、OpenUI 源码/所有权检查、Gallery 目录/资源完整性检查通过；OpenUI 的中英文资源键与格式参数检查通过。本轮执行环境没有 Swift/Xcode，`swift test` 启动即报告 `swift: command not found`；依赖 Swift 的模块/消费者检查、原生构建、XCTest 与性能测试均不能据此认定通过。检查日志保存在忽略的 `outputs/verification/openui-design/`。

2026-11-16 发布前复核同时检查了远端基线 `a88dd28` 的 [GitHub Actions](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/43788659666)：账户计费或支出限额阻止前置任务启动，任务没有执行任何步骤，`native-sdk` 随之跳过。这是验收环境阻塞，不是代码测试通过或失败的证据；恢复可用的 macOS 执行环境后，仍须运行上述原生验收。

标题 20/18 pt、OptionCards 最小阅读宽度 200 pt 是当前首版的可覆盖默认值，仍需整页原生对照。标题—说明间距、按图表类型进一步调整密度、照片卡遮罩和轮播留白暂保留原值；待真实样张和实际内容确认后在本文件继续修订，不提前把候选值写成已验收结论。

验收使用同一来源内容和有限的代表场景：阅读解释、图片选项、联系表单、旅行地图、数据分析，另补商品卡和宽表。记录实际内容区宽度、字号、外观、RTL、输入与结果；覆盖流式列表闭合、长中文、动作状态、媒体加载/失败/恢复。候选参数的最终收口需要原生对照，静态检查或图片生成成功不等于视觉验收。
