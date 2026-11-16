# OpenUI

文档版本：1.7 · 更新日期：2026-11-16

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

默认界面保持内容优先。资源失败、辅助阅读模式与控件能力不自动生成一段说明、徽标或额外工具栏；采用安静占位、原生滚动和无障碍语义。作者明确提供的标签、说明及用户可以处理的校验错误继续保留。

- CardHeader 使用章节角色；InlineHeader 与图文对象保留对象标题角色。默认 iOS 使用 20 / 17 pt，macOS 保留 20 / 18 pt；宿主可以完整覆盖字体，具体视觉比例仍需原生对照。
- Steps 的解释属于正文。ListItem 的 subtitle 继续表示辅助信息；需要多段核心解释时，组合 TextContent/Markdown，而不是把正文都放进小号副标题。
- 主 Metric 与行内数字按角色区分；数值和单位保持完整，超长金额不缩字号或截断小数。
- 图片加说明的 OptionCards 优先保证阅读宽度。最小阅读宽度初始采用 200 pt，并按字体尺度增长；宿主仍能覆盖该参数，辅助阅读字号继续单列。列数由当前位置可用宽度决定，不随流式文案字数反复变化。
- Form 默认只组织字段和动作，不自动增加外框与内边距。需要独立面板时由作者组合 Card，或由宿主显式设置 formShowsCardSurface = true；两者复用同一表面配方。渲染器不按嵌套层数擅自改写显式 Card，输入控件仍保留自身边界。
- 默认只显示作者提供的字段标签与 hint，不自动追加 Required、可多选或重复日期范围摘要。必填、选择模式和完整日期范围保留无障碍语义，原始校验规则仍是唯一依据；错误按已有校验时机展示。
- InlineText 主值与辅助说明使用既有 titleDetailGap，空说明不产生额外间距。Chips、Tabs 与 FollowUp 的多行标签限制圆角，避免文字落入高胶囊的弧线区域；不缩字、不隐藏选择状态。

默认值是可覆盖的呈现策略。显式尺寸、布局方向与输入内容继续按契约处理；Form 唯一提交的局部满宽规则见下节。

### 文字角色与 Callout

文字的用途决定字体、字重、行距和前景；容器负责排列、分组与内边距。普通阅读内容不因进入 Card、列布局或深色外观改变含义，不自动获得底色、边框或提示标签。字号小不等于信息次要，字号大或加粗也不自动获得无障碍标题语义；标题由实际标题入口表达。

默认 iOS 阅读层级采用以下关系；点值对应默认字号，实际文字按角色参与 Dynamic Type。macOS 继续沿用桌面密度，不能把手机的点值当作所有平台的硬性规格。

| 用途 | 现有字体 token | iOS 默认 | 缩放参考 |
| --- | --- | --- | --- |
| 文档标题 / Markdown H1 | textHeadingMd | 22 pt semibold | title2 |
| 章节 / CardHeader / Markdown H2 | textHeadingSm | 20 pt semibold | title3 |
| 对象 / InlineHeader / Markdown H3 | textHeadingXs | 17 pt semibold | headline |
| 核心解释与 Callout 正文 | textBodyDefault | 17 pt regular | body |
| 显式 large / lg 正文 | textBodyLg | 20 pt regular | title3 |
| 小号正文、紧凑解释与辅助说明 | textBodySm | 15 pt regular | subheadline |
| 图注与元信息 | textBodyXs | 13 pt regular | footnote |

小号正文与辅助说明复用同一字体，信息优先级由各自的语义前景表达，不额外增加仅相差一号的字体 token。大号正文使用与其默认大小相符的 title3 缩放曲线，仍保持正文语义，不增加标题边距或无障碍标题标记。加重字体仍是独立的完整配置：宿主对 heavy token 的字族、字号、字重、行高与字距覆盖继续生效，不从普通字体偷偷重建。既有 Text 的 sm / md 别名、TextContent 的 small / large 变体以及解析模式保持原契约。

NativeTextStyle 与 NativeTextRole 统一原生文字和 Markdown 的字体配方；Markdown 内部字体需要显式接入配方，不能只依赖外层 SwiftUI font。段内行距由文本 renderer 管理，兄弟内容的 gap 由父布局管理，组件内边距由其表面管理，页面左右边距由宿主管理。避免用多层 padding 弥补不一致的文字度量。

Callout 表达与当前内容相关的独立提示或反馈。普通解释继续使用 TextContent/Markdown；Callout 不自动补写“提示”“注意”或“信息”标题，也不根据文案关键词推测状态。可见标题和正文只来自输入，完整换行，不按固定行数裁切。

- 默认采用中性的 sunk 表面、radiusXl 连续圆角与 objectInset 内边距，标题到正文使用 titleDetailGap；当前默认分别为 12、12、4 pt。标题与正文使用主文字色，没有默认左竖线、整段状态色或额外阴影。
- neutral 不显示状态图标；显式 info、success、warning、error / danger 使用小图标和局部语义颜色。辅助功能保留状态含义，颜色不是唯一辨识方式。
- TextCallout 保持持久展示。Callout 保持原有 reactive 契约：只有可写 visible 绑定参与自动隐藏，在可交互且可见时等待 3 秒写入 false；没有绑定时不凭空隐藏。换源、不可交互和取消仍遵循原有生命周期。

这里的组件 Callout 与 SwiftUI 的 Font.callout 是不同概念；不会仅因为内容是提示就套用一个固定字体或改变其业务生命周期。

## 状态、字段与动作

组件通过 OpenUIComponentContext 的 value/string、children/slot、binding、field 和 action 方法接入；不直接改写整份 state 或绕过 Context 执行动作。context.string 是显示便利方法，精确字符串与键使用 OpenUIString/Value，不能在协议、身份或资源键上引入 Unicode 归一化。

可写控件区分文档 Store、局部编辑草稿和提交结果。Select、Radio、Checkbox、Switch 的用户选择须在首次操作后反映到当前展示；Store-only 的更新也必须使叶子 View 刷新。无可写绑定的字面值不能被当作可写状态。

字段验证通过共享规则与 Context 执行。被拒绝的草稿不能因其它 Store 发布而提交；源码替换使原草稿、旧动作和旧异步结果失效。EditableTable 的本地交付回执不代表远程持久化。Slider 的离散格点考虑 minimum 与 step 的精度，范围末端、拖动和连续文本按各自已有规则校验。

UI 特有的点击项上下文可以由组件提供；通用状态、动作执行顺序、异步取消和文档就绪检查由适配层负责。表单和资源的精确名称保留 UTF-16 语义。按钮、卡片动作与本地选择在拖动/分页结束时不能误派发激活。

### 表单单提交与继续对话

Form 自己的 buttons 槽总共只有一个稳定声明的标准提交 Button 时，按钮铺满字段列，遵循所在容器的 inset；默认 Form 不另加一层 inset。提交包括继续对话、mutation 与自定义提交动作；纯导航、Set/Reset 和 Query 不据此自动铺满。

满宽与 variant/role 独立，保留来源声明的 primary、secondary、tertiary 或 destructive 样式。单项 row 与 column 均可满宽；多个动作、Form 外按钮、字段内部动作、商品 footer 与表格单元格继续使用原布局。只有列表和必要参数稳定后才认定“只有一个”，不将流式暂时出现的首项当成唯一项；布局变化保持同一控件子树。

继续对话保留完整文字，标准按钮与 FollowUp 分别采用适合其场景的呈现：

| 场景 | 默认呈现 |
| --- | --- |
| 标准继续对话按钮 | label 与箭头组成居中的内容组，继承原按钮字体、前景和表面 |
| FollowUp | 按内容宽度排列的紧凑浅色胶囊；空间不足时自动换行，长问题在胶囊内自然折行；默认无箭头，保留独立触控目标 |
| Performing | 文字和触控尺寸保持稳定；标准按钮在原附件槽显示延迟进度，FollowUp 保留问题及执行中的无障碍状态 |
| Pending / Disabled | 区分尚未就绪与宿主禁用，均不冒充已完成；辅助功能说明状态 |
| 校验失败 | 先展示并定位字段错误，不派发继续对话 |

整行或整个按钮都是同一个点击目标，箭头不形成第二个按钮。图标使用 forward 语义并遵循 RTL，只作为装饰朗读；按压、hover 和键盘焦点有轻量反馈。长中文自然换行，触控尺寸与可见外形分开处理。

标准按钮的箭头按真实且已就绪的 action 分类，不按中文 label 猜测：明确的 continue_conversation、最终 nil/null 的默认继续对话，以及本地 Set/Reset 配合单个 ToAssistant 可以采用；混合 mutation/custom/open_url 等外发意图时保守保留原动作表达。分类不执行消息 AST 或触发工具。

可见 label、实际 message、params/context、formName 与派发时 formState 完整保留。ToAssistant 的 message 可与 label 不同；legacy 对象继续使用原 dispatcher 的消息来源。提交仍先刷新草稿、再校验、再派发。SDK 的 performing 只覆盖本次 await，不承担整轮 Agent 回复状态，也不自动宣告远端保存成功。

### 控件完成度

- 范围 Slider 的两个端点使用明确的上下限语义；空间不足时内部数值布局转为纵向，保留草稿与焦点。
- Tabs 的溢出提示应与实际剩余空间一致；单个标签宽度包含水平内边距，长标签在既定宽度内完整换行，不限制为两行。RTL、末端位置与键盘激活按原生行为验收。
- DateRange 的清空操作明确为“清空日期范围”，保留整个范围清空的既有数据语义；自动调整另一端后，两个端点同步显示最终日期，组的无障碍值提供完整范围，不追加第三行日期。Cancel 不保存草稿，Done 才确认。
- 选择卡、Tabs、FollowUp 具备一致的最低按压和焦点反馈，禁用说明与错误信息保持可辨。适用文本字段从已有声明顺序获得下一项/完成流程。

## 布局与流式

父容器拥有分配的可用空间，子组件消费当前位置的 proposal。缩放只影响观看倍率，逻辑宽高控制实际排版。尺寸拟合与旋转不能重新提交源码或清空用户输入。

- 缺失引用、尚未完成的数据和已闭合但为空的数组分开处理；不为未提供内容虚构图文格子。
- 稳定节点、局部状态、选择和资源身份应在增量流中保持。流式追加不能重建整棵文档环境。
- 结构元数据可以保留已声明的槽位，但不承诺所有程序都有“有序就绪前缀”；实际可见性遵循官方解析结果和原生 readiness。
- 已完整的控件可在其它内容继续流式时交互，未完成动作仍须阻止执行。
- 文本字段收到最后一段后，即使只有其它节点继续生成，也须继续推进到原生文本缓冲及 Markdown 准备链路。文字与流式状态使用同一次更新的值；48ms 呈现合并只降低重排频率，不能让字段等待 `complete` 才补全。读取与尺寸拟合仍不创建任务或发布状态。
- 卡片、图片、图表、表格和窄屏行布局按本库规则等待必要尺寸或数据，不靠改写来源内容绕过就绪条件。
- 宽度、主题和 Dynamic Type 变化只改变布局与呈现，不产生新的文档身份。滚动容器和消息列表归宿主。

## 文本、媒体与原生差异

Markdown 与代码使用固定的 typed adapter，不在组件里创建任意 JS 环境或执行来源脚本。公式与代码资源随包分发，许可与安全策略见验证说明；文本组件不得提交源码或写入文档状态。

原生图片读取宿主资源 Context、baseURL、loader 与鉴权作用域，受并发、响应及解码预算约束；作用域变化需同时影响缓存、View task 与已解码内容身份。比例、加载、失败、重试与预览属于组件视觉，不将该保证扩大到 WebKit/Markdown/MapKit 的所有网络请求。

图片的稳定身份包含精确来源、baseURL、loader、授权作用域、资源限制和重试次数；实际请求在一次加载尝试内冻结。不能在布局、状态回调或完成校验中重新调用可能生成新 nonce 的签名器。请求快照继续依附既有文档媒体缓存并有容量上限，重试与作用域变化建立新请求，文档重置清理快照；图库选中/状态及背景图状态使用同一稳定身份。

单图与图库预览根据实际视口、显示缩放和已确认的放大比例申请解码尺寸，先应用资源像素上限再决定是否加载。已有缩略图可作为临时画面，高清结果到达后替换；同一资源的尺寸升级复用冻结请求，等待期间保留已有像素，缩小视口不降低已接受的清晰度。来源或授权作用域改变后不得继续显示旧资源。

图库大图仅挂载当前页和相邻页，缩略图条惰性创建，离屏缩略图释放自身持有的解码结果。图库父视图只保存状态与选中项，不再另存全部图片绕过有界媒体缓存。远距离选图直接切换到目标页，避免沿未挂载页面播放空轨道；普通卡片及表单轮播保持原有子树身份策略。

Map 表达来源坐标与选点，不表示真实导航、实时交通或已完成业务操作；当前 Map 组件整体要求 iOS 17/macOS 14。空坐标、准备中和较旧的受支持系统使用稳定地图区域的安静占位，状态与版本要求通过无障碍语义提供，不塌成一行技术说明。SVG 要求有效 viewBox，使用内联内容或 HTTPS src，拒绝活动内容和外部引用。

### 地图与媒体

- 地图保留现有大小和 320–360 pt 高度策略。本轮不统一缩小地图、工具或编号图钉。
- 缺图在原透明缩略图槽中央显示 mappin.and.ellipse。没有额外色块、圆盘、描边或阴影；地点卡片自身的表面继续保留。无 URL、等待、失败、恢复与成功淡入遵守同一占位规则，照片加载不挤动相邻文字。
- 紧凑地点卡保留稳定摘要，同时提供组件内完整详情。没有外部 URL 也能阅读完整名称与说明；外部页面入口与地图展开各有明确用途。
- 内容图、缩略图、图文卡与图库的失败态都只保留原尺寸的安静 photo 占位；内容图使用现有浅色媒体表面，缩略图沿用所属容器。不显示错误段落、alt 正文、警告标识或独立 Retry 按钮；替代描述、状态和操作提示供无障碍朗读。有有效请求的加载失败点击整个占位重试，无地址或无效地址不发起空请求；地图继续使用无底色的 POI。所有状态保留声明的几何与资源身份，重试只由用户操作或来源变化触发，不由尺寸测量触发。照片封面与信息图片的完整查看按用途处理。
- 图库的总数/查看全部入口独立于某张缩略图加载成功，前五张失败也能进入完整集合。
- SVG 提供完整查看路径，保留 viewBox 与安全边界。展开图标位于图形之外并保留完整触达与无障碍名称；缩放和平移说明放入无障碍提示，不常驻教程段落。加载或失败保留安静的图形区域，详细错误和 alt 不成为可见说明段；远程加载失败点击占位重试，创建新的签名请求并跳过失败的本地缓存。有效文档的 WebKit 呈现失败也可点击占位重新加载。只有 View 任务本身取消时才静默退休，传输层意外返回 CancellationError 仍进入可恢复失败状态。作者提供替代描述和主题友好的图形颜色，renderer 不自动反色或虚构图意。

### 图表、表格与图文对象

- 常规图表暂保留 250 pt 绘图区基线，饼图/径向图与单条比例图继续各自的高度策略；按类型、标签、字体和数据量调整密度，保留合法的显式高度。
- 比例条的绘制与命中共享几何。合法全零数据有明确表达；选中图形与检查详情对应。Line/Area 的图形与图例增加按源序列身份分配的线型，隐藏系列后保留颜色和线型；其他类型继续通过现有图例与检查详情辨识。
- 普通检查使用轻量浮层，尺寸受图面与图例的实际可用区域约束；放不下时使用提示或隐藏浮层，不挤压和截断完整值。独立的“查看图表数据”入口始终位于浮层区域之外，详情可滚动阅读全部系列，包括暂时隐藏的系列。
- 表格保留完整换行、数值对齐、原生横向滚动和自定义单元格，不默认附加“按行阅读/表格视图”按钮或横滑说明。辅助阅读字号自动使用按原列标题逐项阅读的排列，不默认把任意第一列当作主键。两种排列复用同一 cell 子树；编辑默认列宽考虑字号，显式列宽与修改/保存/冲突状态继续保留。
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

普通图片曾同时存在透明失败回退和重试交互关闭的问题；后续加入的内容图错误说明又挤占了阅读界面。现统一收敛为原尺寸的安静图片占位，保留有效请求失败后的整区点击重试和地图 POI 的独立规则。对应回归验证缺失/失败/恢复、替代描述不改变失败画面、原尺寸以及测量不触发请求；原生测试仍须在 Swift/Xcode 环境执行。

本次另修正签名请求被反复重建导致成功图片/图库状态被丢弃的问题，并补充签名加载、重试、换源、换授权作用域及旧响应晚到的挂载回归。远程 SVG 也按稳定来源启动请求；停止流式时，尚未闭合的 src 不再保持无限加载提示。上述原生行为不能仅凭源码和 JavaScript 检查认定验收通过。

后续内核修复补充了图库挂载范围、缩略图到高清画面替换和 SVG 失败重试；新增测试检查实际挂载、请求次数及画面像素。标准 Stack/Card 同时补齐自定义组件身份元数据的传递。以上原生测试尚未编译执行，原有 signed media 失败与 SVG 拖动像素失败仍须在客户端或 macOS 环境复验。半句停滞的后续定位确认 `NativeMarkdownText` 变化回调忽略新值并交付旧捕获文本，现已改为从回调参数一起交付最新文字与流式状态。公开的 `push / complete / interrupt` 用法不变，保留既有呈现合并与异步 Markdown 准备；实际分块回放仍待原生验收，详见[验证说明](validation-and-security.md#原生文本流中停滞)。

| 范围 | 已实现的首版 | 尚需确认 |
| --- | --- | --- |
| 地图与动作 | 透明 POI、原尺寸、地点完整详情；单提交满宽；标准按钮语义箭头、FollowUp 紧凑换行胶囊 | 实际点击、地图内嵌/展开、焦点、RTL、流式和执行反馈 |
| 阅读与控件 | 章节/对象标题、Steps 正文、主指标层级、选项阅读宽度；默认无外框 Form、必填/多选无障碍语义、Slider 端点、Tabs 完整换行与滚动、日期范围组语义、文本字段下一项 | 长中文、窄列、辅助阅读字号、禁用状态和键盘操作 |
| 媒体与数据 | 安静图片/SVG 占位及点击重试、独立图库入口、完整查看；比例条几何、全零状态、图表详情与线型；表格横滑、辅助字号自动按行阅读和编辑宽度 | 真实资源失败/恢复、缩放与关闭、长数据读取、自定义 cell 状态保持 |
| 回归与来源 | 修正视觉矩阵中错误的 Button 参数槽，新增针对性行为/布局回归；沿用现有完整 Gallery 场景和原始 fixtures | XCTest、Gallery 原生交互、截图对照与 Release 尺寸隔离 |

已执行的 `git diff --check`、OpenUI 源码/所有权检查、Gallery 目录/资源完整性检查通过；OpenUI 的中英文资源键与格式参数检查通过。本轮执行环境没有 Swift/Xcode，`swift test` 启动即报告 `swift: command not found`；依赖 Swift 的模块/消费者检查、原生构建、XCTest 与性能测试均不能据此认定通过。检查日志保存在忽略的 `outputs/verification/openui-design/`。

2026-11-16 根据客户端截图再次收敛默认呈现：内容图错误段落改为整区点击重试的占位，FollowUp 恢复紧凑换行胶囊，表格移除阅读模式按钮/横滑说明，表单自动标识转入无障碍语义。基于 `c731005` 的源码/所有权、Gallery 完整性、本地化和差异检查通过；`swift test` 实际启动失败（环境缺少 Swift）。内容图与 SVG 重试、辅助字号切换保留单元格状态的既有挂载测试已更新，尚未执行原生构建、VoiceOver 或截图验收；本轮日志在忽略的 `outputs/verification/quiet-presentation/`。

同轮全库呈现审查继续修正默认 Form 外框、重复日期摘要、InlineText 说明间距、长 Tabs 截断与 Chips/Tabs 多行圆角，并收敛 SVG 教程和地图状态文字。Form 现有回归改为验证默认无外框、输入边界保留，以及宿主显式启用表面时与作者组合 Card 等价；未将旧默认的断言简单删除。图表精确数据入口、地图筛选/计数、代码复制、真实校验和来源信息仍保留。差异、源码/所有权、Gallery 完整性与本地化检查通过；`swift test` 再次因缺少 Swift 无法启动，原生构建与长中文、VoiceOver、焦点操作验收仍未执行，本轮检查日志在忽略的 `outputs/verification/component-presentation-audit/`。

2026-11-16 发布前复核同时检查了远端基线 `a88dd28` 的 [GitHub Actions](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/43788659666)：账户计费或支出限额阻止前置任务启动，任务没有执行任何步骤，`native-sdk` 随之跳过。这是验收环境阻塞，不是代码测试通过或失败的证据；恢复可用的 macOS 执行环境后，仍须运行上述原生验收。

2026-11-16 的文字与 Callout 调整基于最新 `3310e3d`，统一 iOS 22/20/17 pt 标题与 17/15/13 pt 阅读层级，保留 macOS 的桌面基准；NativeTextRole 同时控制默认行距与 Dynamic Type。MarkdownUI 的内部 body 缩放经过补偿，与原生文字、标题和公式附件使用一致的最终字号。Callout 改为中性表面和局部状态图标，作者文本、可写绑定、三秒隐藏与换源取消规则保持。图表标签、数字指标、文字占位和地图地点卡的预留尺寸同步采用实际字体角色；没有增加场景或文案特判。

新增回归覆盖完整字体覆盖、正文与 Markdown 的字号对应、辅助字号层级、标题独立性及 Callout 的持久/自动隐藏和旧任务退休。差异、源码/所有权、Gallery 完整性与本地化检查通过；`swift test` 已实际尝试，因环境没有 Swift 返回 127。原生构建、XCTest、字号舍入与实际界面尚未验收，检查日志在忽略的 `outputs/verification/semantic-typography/`。

这些字号与 OptionCards 最小阅读宽度 200 pt 是可覆盖的默认值，仍需整页原生对照。标题与说明的整体视觉比例、Tabs 两侧溢出操作的视觉密度、按图表类型进一步调整密度、照片卡遮罩和轮播留白仍待真实样张确认；保留相应操作能力，不提前把候选值写成已验收结论。

验收使用同一来源内容和有限的代表场景：阅读解释、图片选项、联系表单、旅行地图、数据分析，另补商品卡和宽表。记录实际内容区宽度、字号、外观、RTL、输入与结果；覆盖流式列表闭合、长中文、动作状态、媒体加载/失败/恢复。候选参数的最终收口需要原生对照，静态检查或图片生成成功不等于视觉验收。
