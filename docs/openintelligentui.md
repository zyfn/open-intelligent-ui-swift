# Swift Intelligent UI 设计

文档版本：1.12 · 更新日期：2026-11-22

本文描述 `OpenIntelligentUI` 的组件契约、视觉规则、状态与资源、生成及交付方式，以及后续迭代必须遵守的边界。跨模块所有权与共享运行时以[架构](architecture.md)为准；接入与修改规则概览见 [README](../README.md)。

## 1. 定位与基线

`OpenIntelligentUI` 是基于 `SwiftLang` 的 Apple 平台组件库，提供 DesignSystem、组件、交互绑定和生成规范。布局、文字、图片、输入、商品、交通和图表遵循同一套组件机制。

调用方持有 SwiftLang 定义的 `OpenUIState`、提供内容与资源、接收动作事件。组件通过同一适配层的 Context 与原生宿主接入。可选模型生成评测位于 `Validation/Generation`。

库不负责模型服务、业务资料检索、消息生命周期、订单交易或购买结果。模型、工具和宿主提供事实；组件按来源呈现，不补造价格、库存、坐标、路线、来源或执行结果。

组件库的包、目录、依赖和共享状态边界统一见 [架构](architecture.md)。公共接入只使用 OpenUILibrary.openIntelligentUI()、makeState() 和 OpenUIView，示例见 [README](../README.md)。本指南只维护本库的组件、视觉与特有能力。

## 2. 组件与契约

默认组件目录包含 59 个组件：54 个上游入口与本库 ProductCard、JourneyLine、Citation、Disclosure、Progress；注入图片搜索服务后加入 SearchImage，总计 60 个。writer 与运行时组件目录使用相同的组件集合。具体参数和平台行为以导出的 spec、manifest 为准。

下表列出新生成可用的组件：

| 分类 | 组件 |
|---|---|
| Layout | Col、Row、Box、Grid、Card、Carousel、Popover、Divider、Spacer、Form、Disclosure |
| Content | Text、Title、Caption、Label、Badge、Link、List、ListItem、Markdown、Quote、Code、Flashcard、Celebration、Citation |
| Controls | Button、IconButton、Pressable、Input、TextArea、Select、SegmentedControl、RadioGroup、Slider、Checkbox、DatePicker、Timer |
| Media | Image、Icon、SearchImage、Math、Map、MapMarker、YouTube、HtmlView、Svg、Circle、Ellipse、Rect、Line、Path、Polyline、Polygon、G、SvgText |
| DataDisplay | Table、Chart、ProductCard、Progress、JourneyLine |

每个组件记录有序参数、类型、默认行为、绑定与限制。本库以官方提交 [`53df45b`](https://github.com/thesysdev/open-intelligent-ui/tree/53df45b4231aabab1a0e932733e117937ff2b41c) 导出的 55 个基础组件为位置签名基线；本轮布局与属性行为依据该 demo 锁定的 `@openuidev/intelligent-ui-library@0.0.1` 源码 [`c531b0d`](https://github.com/thesysdev/openui/tree/c531b0dfe83dc828241f71dbe77e689ebdbf05f7/packages/libraries/intelligent-ui/src)：Image / SearchImage 的 aspectRatio、radius、fit 参数重新进入 writer；Card 参数为 children、variant、gap、padding；六类输入新增 rules；Chart、Svg、Polyline、G 使用新签名。商品与交通自有扩展仍排除旧 priceText。完整 reader 保留尚未删除的历史扩展字段。SearchImage 仅在调用方提供图片服务时注册；普通客户端无该服务时不向 Agent 宣告。

### 2.1 布局与排版

Agent 表达内容、顺序、分组与交互，布局组件根据宿主实际提供的空间排版。普通生成不需要设备型号、屏幕像素、断点计算或预先算好的文字宽度。尺寸和布局规则留在已有的 Row、Col、Grid、Box 等组件中，公开参数用于表达确有需要的约束。

- Col 默认沿横轴 stretch；未指定 gap 时，直接相邻块使用阅读间距：根部 24 点、嵌套 flow 或 Card 内 12 点、Title 后普通块 12 点、Text 后 Text 12 点、Title 后 Text / Caption / 直接含 Badge 的 Row 为 8 点、Caption 后 Title 为 4 点。包装节点保持自己的块边界，不再穿透包装猜测媒体或正文关系。显式 gap 使用主题单位并关闭该容器的自动 flow 间距。
- Row 默认 gap=2 个主题单位、align=center、justify=start、wrap=false。直接 Image / SearchImage 触发媒体行：整行 align=start、gap=16 点；直接图片和唯一直接子项为图片的 Box 使用 `clamp(120, 行内容宽 × 33%, 200)` 点宽，图片为 4:3。媒体行的这些尺寸规则优先于图片 aspectRatio 和该 Box 的 width/flex。只有图片包装 Box 的行仍保留原有行间距与对齐；它只触发该图片项的宽度与比例规则。
- Box 默认为纵向弹性容器。显式 flex（包括 0）采用零基准分配，优先于同一轴的 width / height；省略 flex 且 width 为数字时保留固定宽度、不参与收缩。字符串 `"96px"` 仍作为首选宽度参与普通 flex 收缩。Row 换行后按每行的可用宽度分别分配 flex；Col / 纵向 Box 在父级提供确定高度时沿纵轴分配，内容自然高度不被当成整屏高度。纵向 Box 的 wrap 在有确定高度时分列，每列独立分配；无确定高度时保持自然纵向流。
- Box 的 justify 沿主轴，align 沿交叉轴。显式宽高包含 padding 与 border；默认没有 padding、背景或边框。直属布局组件消费伸展或 flex 分配后重建子项策略；Card、Form 等包装组件不会把祖先分配穿透到内部 Box。百分比按相应父布局的确定尺寸计算，测量与放置使用同一份尺寸基准，避免重复折算。根 Box 可使用宿主真实的有限 proposal 解析百分比高度，普通 auto 根布局仍保持自然高度。Row 的 wrap 不改变百分比高度基准；跨行剩余高度按行伸展，显式超高子项可溢出但不改写其他子项的基准。
- Grid 的 columns 默认 2，运行时取整并限制为 1–12。只有提供非零 minChildWidth 时才按可用宽度减少列数，且不超过 columns；宽度小于单项最小宽度时保留一列以容纳当前空间。需要适应窄容器的多列内容使用现有 minChildWidth，普通生成不自己计算列数。辅助阅读字号继续使用原生单列适配。
- gap / padding 的数字按主题单位换算，默认 1 单位=4 点，负数归零，不再附加 24 的私有上限。数字宽高负数归零；长度支持数字字符串、px、%、em/rem、vw/vh 与 auto。% 使用直接父布局 proposal；em/rem 使用原生动态字号；vw/vh 使用渲染器所在的可见容器，iOS 17 / macOS 14 起从 SwiftUI 容器取得，旧系统读取实际所属滚动视口或窗口；旧系统没有滚动视口时以所属窗口为基准，不宣称可识别任意自定义子面板。没有可测视口时保留自然尺寸，不拿全局屏幕或内容高度替代。pt、负数单位字符串、calc 等表达式不参与尺寸解析；fr 不是有效 width/height 的使用值，不伪造网格轨道能力。
- 颜色字段保持 string 契约，支持语义 token、HEX、RGB(A)、HSL(A) 与 CSS 命名色。canvas、surface-strong、border 等背景角色按主题解释，muted / faint 保持其原角色，不再统一换成 surface。原生解析器拒绝资源或表达式；lab/lch/oklab/oklch、color()/color-mix()、相对颜色和 CSS 继承关键字仍不支持，不能把该范围描述成完整浏览器 CSS 色彩实现。受官方 onColor 规则支持的显式背景会提供默认可读前景，子项显式颜色仍优先；该规则不扩大到所有 CSS 颜色语法。具体色值与字体由宿主原生主题决定。
- Card 表示真实对象或连贯分组，不为每个段落增加表面。使用画布背景、连续圆角与轻边框；iOS 默认 16 点内边距，macOS 20 点，嵌套 16 点。单个 ProductCard 沿用自己的表面，透明的单子 Col/Box 不重新触发外层边框与内距；有背景、边框或内距的 Box 继续表示真实分组。
- Card、Grid、Carousel 和透明 Col/Box 保留原生稳定文字角色，不根据层级或子项位置改变默认 Text/Title 的字号与字重；显式字号始终优先。系统字体、Dynamic Type、RTL、原生焦点与 MapKit 等属于平台实现，布局规则对齐不表示浏览器像素级还原。
- Carousel 的首选项宽默认 240 点、运行时限制 80–640 点，正常字号不超过视口的 85%。同类实体卡保留可比较的高度，普通内容按自然高度显示；横滑容器由最高内容决定。末尾补足停靠空间，使最后一项可与当前索引一致。iOS 17/macOS 14 起使用原生停靠，旧系统同步偏移位置；桌面和无障碍提供前后操作。子项使用 child.id，方向按宿主 RTL 环境处理。
- Divider、Spacer 分别负责分隔与剩余空间，不增加额外交互。

#### 基础组合与适配

| 需求 | 常规组合 | 组件负责的行为 |
|---|---|---|
| 上图下文 | `Col([Image(...), Title(...), Text(...), Caption(...)])` | 图片画幅、内容换行、相邻块间距 |
| 左图右文 | `Row([Image(...), Col([Title(...), Text(...)])])` | 图片宽度与 4:3 比例、行对齐、正文宽度与换行 |
| 适应宽窄的多列内容 | `Grid([Col(...), Col(...)], 2, 160)` | 最多两列，根据实际可用宽度和最小列宽减少列数 |
| 横向浏览 | `Carousel([Col(...), Col(...)])` | 项宽收敛、横滑与停靠 |
| 透明底、带边框 | Box 留空 background、设置 border=true | 表面、边框、内边距与圆角独立选择 |

左图右文直接通过 Row、Image 与 Col 组合，不需要专用复合组件：

```text
root = Col([Row([
  Image("https://example.com/detail.jpg", "建筑细节"),
  Col([Title("观察建筑形制"), Text("从来源提供的屋檐与门窗细节理解这座建筑。")])
])])
```

以上图片 URL 仅为语法示例，真实生成保留宿主提供的图片、正文、来源与动作。Gallery 的 Row 提供 Image 与 SearchImage 的并排内容，Grid 提供固定列数和最小列宽的对照。

响应式依据是父容器实际提供的空间：同一台设备的侧栏、分屏和整页可以有不同宽度，简单尺寸变化由组件重新计算，模型无需重新生成。Row 的媒体规则不包含普遍的窄屏转竖排断点；`wrap=true` 允许换行，Grid 的 minChildWidth 控制减少列数。不能宣称任何固定宽度、任意数量的非换行子项都不会溢出。辅助阅读字号的现有原生重排继续生效。

ProductCard 的价格与购买入口、Map 的点位与选中行为由对应组件管理；交通通过 JourneyLine 与通用组件组合。图文可组合不等于所有业务控件都应拆成没有行为约束的基础元素。

Box 的可选裁剪仍有独立验收边界：从未提供 radius 切换到提供 radius，或反向切换，会进入不同的 SwiftUI 结构分支，内部局部状态与焦点的连续性尚未验收。已提供 radius 后修改圆角值不切换这两个分支。不能用始终矩形裁剪代替“无裁剪”，否则会改变未设置圆角时的溢出语义。

### 2.2 文本、列表与内容

- Text 支持内联 Markdown 和混排组件；字符串与 TextKit 共享字号角色、字重和行距决策。省略 size/weight 与显式 md/normal 等价，深浅外观都使用 regular 正文；显式 medium/semibold 继续生效。小号文字不自动变成次级颜色，加粗不自动变成标题。附件按 child.id 保留原生 host，Markdown 解析、同宽测量与附件适配分别缓存；异步尺寸变化使测量失效。maxLines 截断后不可见附件不能继续接受操作。桥接转发 locale、方向、字号、对比度、displayScale 及图片环境。
- Title、Caption 支持行内 Markdown 和链接；Title 由显式尺寸选择稳定角色，默认/md 为对象标题、lg 为章节、xl 为页面标题，2xl/3xl 保留大标题层级。Caption 靠近所属图片或内容，不自动变成独立来源区块。
- Label、Badge 表示字段标签与静态事实。Badge 的 info 为中性，状态背景为浅色；Link 使用正文继承色、下划线和行内尺寸，通过宿主动作打开原 URL。
- List/ListItem 支持 bullet、数字圆标、自定义短步骤标、时间标记列及连线。none 且无时间标记时不绘制悬空线；description 是次级摘要，主要阅读内容放 children。节点身份由运行时维护，不追加私有 id 参数。
- Markdown 提供完整文档块排版，默认正文与 Text 共用阅读角色，H1/H2/H3 对应页面、章节、对象标题；宿主显式 markdownHeadingScales 仍优先。列表、Quote、Flashcard 等紧凑上下文只缩短段距至 innerSpacing，保留多个段落的区分，不把段距归零或自动缩小正文。Quote 仍表示引文，浅底、圆角、侧线和内边距使用同一表面。Code 与 Markdown 代码块共用原文、着色和复制操作；长代码先显示有界预览，可展开，复制始终派发完整原文。
- Citation 在混排段落中使用紧凑内联尺寸，不把完整按钮触达高度带入正文行；独立来源块和多来源 Popover 保留完整触达与导航能力。图片署名和来源可在同一小段 Text 中组合，不额外添加重复的图片链接。

普通 Text/Title 直接应用宿主 Font；Markdown 通过固定 MarkdownUI 的字体属性入口应用已解析字体，并抵消其内部 body 缩放，避免把原生字号再次放大。macOS 的默认语义系统标题使用同一 SwiftUI 文本引擎取得语义字体与重建固定字体的行间基线差，恢复额外行距并保留宿主已有行距；度量按字体及实际环境有界复用，不靠固定高度或 padding 对齐。宿主任何显式 `markdownHeadingScales` 赋值都继续表示原来的前三层相对比例，包括数值与默认数组相同时；未覆盖时才采用语义标题角色。旧系统仍需使用既有 nativeFont 配对，不能自动反解任意 SwiftUI Font；无法按名称回读的私有字体设计回退到系统字体，不猜测私有字族名称。本库没有 Callout 组件：Quote 保持引文语义，Badge 表示短状态，Box 只提供作者明确选择的表面。

### 2.3 控件、输入与选择

已注册控件沿用 SwiftLang 的组件 Context 订阅实际绑定和就绪状态，不额外观察未使用的整份文档。动作表面也使用同一个 Context 观察机制：独立使用时跟随传入 Context 的原文档，保留其 source revision，不会被更近的无关环境 State 重绑。移除冗余订阅不改变数值草稿、交互启用、原生焦点或动作派发规则；具体挂载验收见[验证说明](validation-and-security.md#sdk-正常接入与生命周期审查)。

- Button、IconButton、Pressable 使用原生按钮语义、胶囊/圆形/轻量表面及选中提示；没有动作时禁用，不自动发送助手消息。Pressable 和 Popover 的触发内容用于展示，避免嵌套交互控件。
- 输入绑定到显式变量，字面量只读。容器的显式背景可改变默认文字色；原生不透明输入框和 outline / soft 按钮仍使用自身表面的文字、光标与操作色，避免外层白色文字在内部白色画布上失去可读性。数值草稿保留中间输入，空值写入 null；未失焦时也显示尚未生效的草稿与当前有效值，失焦后提供错误反馈与明确恢复/采用操作。外部状态更新不静默丢弃草稿。最新版 rules 支持 required、email、url、numeric、min/max、minLength/maxLength、pattern；Form 收集已挂载的字段并在 @ToAssistant 提交前校验，失败时显示字段错误并阻止提交，其余局部动作不被误拦截。
- Input 和 TextArea 共享 FieldSurface，使用原生编辑控件、统一边框、内边距、焦点与错误状态。Input/Select 使用胶囊形字段，TextArea 使用连续 18 点圆角；边框为主题 fieldBorder 的固定 1 点描边。
- Select 和选择组使用首个同值选项，未知值保持未选择。短选项使用原生分段 Picker，窄屏或大字号时重排。RadioGroup pills 使用胶囊互斥选择，选中实色底上的说明继承操作前景；cards 使用有轻边界的说明型自适应选项，选中通过既有主题表面和边框表达。普通单选保留圆形指示与字重，不强制所有控件绘成同一种胶囊。
- Slider 显示来源原值，越界时只将滑块投影到安全位置；实际调整或明确采用才写回。密集 marks 分行避让，保留每个标记。Checkbox 保留勾选框与整行触达。DatePicker 在空值、已有值和错误状态保持同一字段外壳与标签位置，进入既有日期面板后经确认才写回；有效日期按 locale、Gregorian 与 UTC 显示，非法值与越界值保留来源和错误反馈。取消不写入，协议编解码继续使用 Gregorian、UTC、POSIX 和 YYYY-MM-DD。
- Timer 使用单调经过时间递减，取消隐式一年截值，提供运行、暂停、完成和无效状态。Flashcard 只挂载可见一面，避免隐藏媒体继续执行；仅显示作者提供的 hint，翻面说明保留为无障碍提示。Celebration 保留原有 false→true 与减少动态效果规则。
- Form 只负责字段分组和动作作用域，不追加 status/message 参数，也不自动绘制卡片边框。独立表单需要可见分组时使用 Card 包裹 Form；Box 不承担默认卡片边框，内联筛选和短操作区不强制包卡。校验、结果与进度反馈使用普通 Text 和显式状态组合，结果不由库推断。

### 2.4 数据、图表与表格

- Table 保持 columns/rows 接口，按内容与容器计算列宽：描述列弹性伸展，金额/数字列保留内容宽并右对齐；少列填满，多列或过长最小宽度才横滑，不自动附加横滑说明行。保留单元格留白、表头层级、等行高顶部多行对齐和细行分隔。
- Table 按行顺序保持 UI 身份，数字列使用等宽数字，常见缺值标记不单独改变整列数字对齐；无障碍大字号改为带字段名的纵向条目。
- Chart 提供柱、线、面积、散点、饼和环形。明细和读屏保留当前 Value/Double 可表达的精度，坐标轴可使用紧凑格式；不声称恢复来源已经丢失的小数精度。缺值保留类别并中断对应系列连线，不补零、不跨缺口连接。点选/拖动/悬停的选择只属于图表，浮层有界且保留可访问入口。
- 饼/环形按点身份选择，图例可访问全部类别；来源负值不绘制为正占比并在明细中保留。完整数据可展开核对，大字号直接呈现明细。

### 2.5 地图与平台桥接

- Map 使用 MapKit 展示调用方提供的地点，保留分类筛选、全览、地图说明、选点高亮和展开。分类按首次出现顺序显示，仅在有两种以上分类时提供筛选菜单。窄容器中的控件按实际可用宽度重排，极窄时收拢为原生操作菜单；控件实测高度用于保留地图可见区域。地图直接显示标记及名称，不额外附加地点卡片、侧栏列表或地点详情页。
- `Map(markers, route?, selected?, height?)` 与 `MapMarker(label, lat, lng, category?, icon?)` 保持固定参数顺序；`selected` 可绑定字符串。高度和经纬度在输入 schema 中均为 number，不附加私有范围；坐标在渲染时检查有限值和有效经纬度范围。空 markers 可呈现空地图状态，不被额外的生成规则拒绝。
- 内嵌地图的高度先以 `height`（省略时 400 点）限制在 200–720 点，再取其与 `max(280, 视口宽度 × 0.82)` 的较小值。视口来自 SDK 的当前可见容器，未取得视口时使用当前布局提案，避免读取全局屏幕。父容器变化后重新计算，模型无需感知设备尺寸。
- 选中值始终是地点 label，没有显式选择时不自动选中首个地点。绑定是选中状态来源；字面量提供初值，后续可交互选点。筛选、全览和点位列表变化不清空选中变量；未知或暂时不可见的 label 只是不产生可见高亮，不从渲染或生命周期回写业务状态。
- 同名地点全部保留，内部渲染身份与 label 分离；同一个 label 的可见标记共同高亮，当前契约不表示同名地点的独立选择。未给有效 emoji 时使用原始 marker 顺序编号，分类筛选不重新编号；提供 icon 时读取第一个字素，只有它符合 emoji 要求才使用。
- 点选只更新 label 高亮，不自动切换为地点聚焦视角。首次流式锚点、自动取景和主动全览分别使用归一化 zoom 10.5、最高 13、最高 14 的尺度，避免单个地点被过度放大；相机与路线暂采用原生即时更新，不复刻 Web 的飞行和描线动效。在展开视图中点选标记后关闭展开；iOS 使用全屏呈现，macOS 使用原生 sheet。全览重新适配当前分类的点位，用户手动改变视野后，普通流式追加和异步路线完成不强制覆盖视角。相机根据实际容器和宿主 contentInsets 留出可见区域。
- `route=true` 使用当前可见 marker 的输入顺序请求 Apple MKDirections 驾车路线，支持 2–25 个地点。全部路段成功后显示道路；加载、失败、超限或不可用时显示按顺序连接地点的概览。直连不代表沿路可达；地图说明区分道路与概览，不提供逐步导航、步行或公交承诺。内嵌和展开共享组件内的路线生命周期，点位变化取消旧请求，旧结果不能覆盖新路线；原生实现保留 700ms 防抖、整条路线 10 秒超时及 8 组成功结果缓存。
- 地图不搜索地点、不请求位置权限、不补造商户资料，也不提供按名称注入 Apple 地点对象的另一套详情接口。搜索、资料、定位授权、预订及业务操作由宿主负责。MapKit 的底图、道路几何、系统字体和展开方式属于平台实现，不作浏览器像素或道路几何相同的保证。

Map 的输入与选中语义固定于 [demo 53df45b 的组件定义](https://github.com/thesysdev/open-intelligent-ui/blob/53df45b4231aabab1a0e932733e117937ff2b41c/src/lib/components/map/map.tsx)，路线点数上限见同版本的 [street-route 服务](https://github.com/thesysdev/open-intelligent-ui/blob/53df45b4231aabab1a0e932733e117937ff2b41c/src/app/api/street-route/route.ts)。

以下平台桥接能力继续沿用各自边界：

- Math 使用固定 KaTeX 在本地生成 MathML，通过可取消的串行工作队列与有界缓存避免重复任务；等待时保留无文字进度，失败时保留可选取的原始 TeX，不追加自动错误标题，状态通过无障碍语义表达。SVG 保持本地无内容脚本的 WebKit，整图预算限制节点、路径、点数、深度和字节；语义颜色读取主题，显式颜色保持来源指定。未完成或无效的图形维持原尺寸占位，状态通过无障碍语义提供，不插入警告与解析错误段落。
- HtmlView 使用独立非持久 WebKit，没有原生消息桥。仅完整内容开始运行，允许内联脚本，限制网络及导航；默认高度 360 point，可内部滚动。切换外观不重载页面状态。
- WebKit 的加载、尺寸测量和销毁按内容版本处理；旧回调不覆盖新内容，外观修改通过样式更新，宽度变化触发重新测量。加载与失败使用安静占位，失败点击整个占位区域重试。离开时停止加载和播放。
- YouTube 使用隐私增强播放器，需要网络与用户播放操作，保持 16:9 容器；无效地址保持占位，可用的原始链接通过上下文菜单和无障碍操作提供。父页面加载完成不构成外部播放器已就绪或可播放的保证，需独立进行网络与播放验收。

固定上游组件语义是基础，Apple 原生适配包括 Dynamic Type、系统控件、可读重排、原生滚动、可访问操作和 WebKit 隔离，不意味着逐像素复制 CSS。状态颜色按用途解析：info/success/warning/danger/purple/pink 作为 Box/Pressable 背景使用浅色，文字保留前景色；chart 颜色仍是明确绘图颜色。

## 3. DesignSystem 与视觉

DesignSystem 决定组件在哪些场景按什么规则使用 token 和平台行为。它不是组件参数仓库，也不只等于一组颜色变量。

- **语义 token**：OpenIntelligentUITheme 只提供可复用的颜色、字体角色、间距、圆角、阅读宽度、图片默认比例与主操作前景/背景。间距与圆角独立定义，不通过 spacingUnit 派生圆角；chart1...chart6 使用独立图表序列色，不复用业务状态色。
- **组件规格**：表格列宽、商品缩略图、地图高度等留在组件内部；Row 为通用布局，文字和图片只按显式尺寸和主题默认语义排版，不内置媒体配方。
- **字体层级**：默认使用系统字族与 Dynamic Type：页面 title2、章节 title3、对象 headline 使用 semibold，正文 body 使用 regular，辅助说明 subheadline、图注 footnote。省略参数保持稳定角色，深色外观不额外加粗；显式 weight 与字号优先。宿主在旧系统需要自定义字体与原生混排一致时，使用 theme.setTextFont(UIFont/NSFont, for:) 配对；所提供的具体字号保持不变，动态缩放由宿主提供。支持 Font.resolve 的系统可解析 SwiftUI 字体，不能宣称所有旧系统能自动反解任意自定义 Font。
- **阅读节奏**：开篇眉题紧接标题，标题靠近正文，连续段落保持阅读间距，图注靠近图片，章节之间增加留白。正文到随后图片使用组间距，图片/图表/表格/SVG 后的 Caption 使用较小内间距；显式 gap 仍由调用方决定。
- **操作层级**：主按钮与业务卡导航共用胶囊动作样式，原生 Button 保留激活、焦点和可访问语义，label 内包含完整触达区域。outline 使用 fieldBorder；低强调控件共用按下、焦点和禁用反馈。Pressable 自己显示选中状态，不依赖父 Row。静态 Badge 不伪装成可点击控件；短选择优先原生 segmented Picker。
- **平台密度**：iOS 和 macOS 采用不同的控件高度初值；间距与圆角是项目 token，不宣称为 Apple 的统一硬性数值。iOS 的主要操作保留 44 点触达。
- **颜色与边界**：采用系统背景、分隔色、主次文字和动态外观。控件与卡片描边统一使用 fieldBorder，不再分别叠乘 separator 透明度；separator 只用于分隔线、路线和节点连接。优先对齐、留白和轻分隔；卡片表示真实对象或分组。
- **数据表达**：Cartesian 图表使用 Swift Charts；图例、轴和明细协同表达。饼/环形以原生绘图实现并提供图例与明细。
- **导航**：Gallery 使用 NavigationSplitView、NavigationLink 和原生工具栏菜单；手机按系统规则折叠导航。SDK 不接管宿主页面导航。
- **适配**：大字号通过重排、增高和展开明细保持可读，不整体缩小内容。主要操作有可访问名称，状态同时使用文字或形状提示。
- **反馈**：绑定修改直接影响结果；动作通过 SDK 派发。加载、缺图、错误、禁用和处理中状态与真实状态对应。

通用 Image 默认采用 3:2 画幅、lg 圆角和 cover，Agent 可以按内容需要显式传入 aspectRatio、radius、fit；Row 的媒体规则再应用 4:3 排版。有效 aspectRatio 为大于 0.2 且小于 5，其他数值按默认比例处理，不把无效值截到边界；加载、成功和失败状态维持同一媒体区域，原图预览与 Markdown 插图保留完整原图。ProductCard 使用自己的商品媒体比例，不直接套用通用 Image 默认值。

设计依据：[Apple Design Principles](https://developer.apple.com/design/human-interface-guidelines/design-principles/)、[Fonts](https://developer.apple.com/documentation/technologyoverviews/fonts)、[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)。具体效果以运行画面与操作验收为准。

### 3.1 本地化与来源保真

SDK 自有提示、错误和可访问名称来自包内英文、简体中文、阿拉伯文资源，按宿主 `.environment(\.locale, ...)` 选择，未支持语言回退英文；RTL 布局由宿主 layoutDirection 决定。业务标题、alt、来源署名、金额文本和 URL 原样保留，不作为本地化键。数值明细先保证当前表示值精度；数值输入采用明确的十进制点与规范千位逗号规则，不能按另一 locale 静默重解释已有金额。日期协议继续固定 Gregorian UTC/POSIX，界面语言不改变日期含义。

Gallery 的“SDK 文案与方向”菜单可切换语言和 RTL，`--locale en|zh-Hans|ar`、`--accessibility`、`--dark` 可复现测试环境。资源覆盖检查不等于翻译、排版或 VoiceOver 已完整验收。

## 4. 资源与计算

### 4.1 函数与动作

59 个扩展函数复用固定上游的计算实现，通过 JavaScriptCore 执行。仅运行随包固定代码，输入按 JSON 数据传递；OpenUI 的解析和求值继续由 SDK 提供。桥接限制输入大小与嵌套深度，异常返回 null。原生组件和动作值不作为这些计算函数的数据输入。

函数参数来自固定上游生成规范，计算源码经过 Git blob 校验；每个扩展函数都有 golden case。时间测试可以注入 referenceDate，随机函数验证类型与边界。资源中保留上游、Zod 和 KaTeX 许可。

扩展动作 CopyToClipboard 以及 SDK 的 Set、OpenUrl、ToAssistant 交给调用方处理。相对链接保持原值，组件不自行进行交易。OpenUrl 只负责导航，不代表购买、库存确认或预订成功。

### 4.2 图片与内容资源

Image、ProductCard 与 SearchImage 共用稳定媒体区：等待、缺失与失败只显示原尺寸的浅色静态占位和低对比图片图标。alt、查找/载入阶段、失败状态与重试说明仅用于无障碍，不生成可见状态段落、警告徽标或独立 Retry 按钮。有可恢复请求时点击整个占位重试；缺少来源不提供无效重试。成功后在原媒体区恢复图片。预览高清升级失败时保留已显示的图片，通过上下文菜单或无障碍操作重试。

ImagePipeline 按注入的资源加载器、鉴权作用域、来源与解析后的请求、资源 revision 和目标像素档位区分请求与缓存。内嵌按实际尺寸/displayScale 下采样，预览按视口与缩放升级，像素尺寸同时服从宿主资源预算及最高 4096 档位。缓存采用 40 项/64 MiB 的 LRU 保留上限，共享原图和派生背景预算；该上限不包含仍由可见视图持有的图片。并发与响应大小服从注入加载器的限制，最后一个消费者取消时取消底层任务。占位状态不引入额外动画任务。

`.openUIResourceContext(resources)` 覆盖本库的原生图片、混排原生附件和原图预览；`.openIntelligentUIImages` 的显式图片覆盖仍优先。该注入范围不包括 swift-markdown-ui 自行请求的文档图片、WebKit 页面子资源或 MapKit 地图数据，不能把它作为这些独立实现的统一网络拦截器。

宿主可用 `.openIntelligentUIImageRevisions` 标记同一 URL 的资源更新，用 `.openIntelligentUIImagePresentations` 提供比例和 fit；Lang 中显式参数优先于宿主覆盖；Row 媒体规则的 4:3 排版再覆盖两者。SearchImage 合并相同查询的同时请求，下载失败后的恢复会重新检索，结果可带 revision、署名和来源 URL；这些是 Swift 服务接口能力，不增加 Lang 参数。Map 的宿主覆盖区域通过 `.openIntelligentUIMapContentInsets` 提供。

商品图与搜索结果图可点开原比例大图，支持缩放按钮、双击、捏合与滚动，关闭后回到原内容。Grid/Carousel 从原始 Image 节点归集同组照片，可在大图中前后浏览，不显示数字分页。通用 Image 的原生预览由 SDK 内部提供，不暴露 preview 参数；Pressable、Popover 触发器和 Flashcard 内抑制嵌套预览按钮。大图查看不执行外部业务动作。

预览在同一来源、授权作用域、revision 和重试次数内冻结实际请求；缩放和视口变化复用该请求，不重复调用签名器。加载任务按应用资源像素上限后的有效尺寸区分，已到上限的继续缩放不反复触发相同解码。换源、换资源所有者或重试仍建立新的请求。相关原生回归及未完成的验收见[验证说明](validation-and-security.md#4-内核稳定性审查与当前验收状态)。

Code 与 Markdown 代码块共用着色和复制操作：Swift、JS/TS、Python、JSON 与 shell 使用轻量词法着色，未知语言或超过 200 KB 的内容保留纯文本。复制派发原始 CopyToClipboard 事件，宿主负责系统剪贴板写入；事件发送不等于未知宿主复制成功。

## 5. 独立业务组件

### 5.1 ProductCard

ProductCard 接受一个 product 对象和 layout，每张卡对应一个商品或可预订服务，价格与购买地址直接属于该对象。

- 必填：id、title、images；图片项包含 url、alt。
- 价格：price 为来源非负金额，可配合 ISO currency 或货币/金额字符串；priceNote 保存单位、条件和范围说明。priceText 仅用于历史读取，不在新生成契约中推荐。
- 可选：specification、merchant、condition、availability、observedAt、purchaseURL、sourceURL、actionLabel、tags。
- 布局：vertical、horizontal 或 compact；compact 用于紧凑摘要或列表位置，缩略图在左、内容在右。窄屏横排和无障碍大字号重排为纵向。

商品大图默认采用组件内部的 3:2 比例，horizontal/compact 缩略图保持 1:1。imageFit 默认为 cover；contain 在固定区域保留完整原图，背景由边缘低频取色并柔和过渡，不复制商品轮廓，也不承诺任意素材无缝。预览仍展示原图。

规格完整可见，condition/availability 简洁显示，不自动附加“商品详情”底栏或来源入口。主金额与动作优先同一行，空间不足时可读回退，不缩字或截掉主金额。缺少有效购买地址时没有购买操作，未知价格明确显示，未提供的可选信息不补占位文案。

多个商品直接组合 Carousel 或 Grid。每个商品拥有自己的完整图集，横排、compact 与竖排均可切换和预览，不借用父容器的其他商品图片。金额展示区分来源币种，例如 CNY 与 JPY；原始金额字符串、分组异常和币种冲突保留并提供提示。长标题、长价格和按钮通过重排保持可读。Gallery 使用有来源与许可的演示照片，演示价格与购买路径不属于库产品。

### 5.2 交通组合与 JourneyLine

`JourneyLine(mode)` 是横向交通连接原语，只负责两个端点之间的虚线与交通方式图标。出发/抵达时间、站点、航段说明、中转事实、价格与操作由 Row、Col、Text、Title、Caption、Link、Button 等普通组件组织。多段行程可纵向排列多个 Row；List timeline 表达纵向时间事件，不替代 JourneyLine。

### 5.3 地图组合

```text
Map(markers, route, $selected, height)
MapMarker(label, lat, lng, category, icon)
```

Map 接收来源地点并管理分类筛选、全览、标记高亮与展开。`selected` 保持可选 label 绑定，正文可直接读取它表达联动；筛选和视野操作不改变该值。模型通常省略 height，让组件根据当前容器适配。图片、简介与其他来源内容使用普通内容组件组织，不从 marker 名称或坐标推断；地图本身不接收卡片投影、详情资料或额外布局参数。

## 6. 生成与验证

实际注册契约、当前能力配置与组合规则共同生成 `spec.json`、`prompt.txt` 和 `manifest.json`。

在项目根目录运行：

```sh
swift test
swift run --package-path Examples/Gallery OpenUIGallery
swift run --package-path Tools/ContractExport ContractExport "$PWD/outputs/contracts"
python3 Tools/check_localization.py
python3 Tools/check_lang_compatibility.py
```

iOS Gallery 工程为 `Examples/Gallery/OpenUIGallery.xcodeproj`，scheme 为 OpenUIGallery；支持 iPhone/iPad。Gallery 是独立开发包，通过本地 Swift Package 引用当前根 SDK，并同时展示标准 UI 与 Intelligent UI。精选案例、专项诊断、源码编辑和预览尺寸在同一个入口管理，见 [Gallery 指南](../Examples/Gallery/README.md)。消费者只选择根包的 SDK 库产品。

Agent 契约位于 `outputs/contracts/prompt.txt`，由 `library.systemPrompt` 直接导出。默认内容包括官方语言模板、59 个组件的签名与行为、内置及注册函数、动作、本库 35 条追加规则和 11 个完整示例；注入图片搜索服务后增加 SearchImage 及其规则。示例覆盖同日记录、稳定任务、消费确认、封面图文、图文 Row、网格与表面分离、普通内容横滑、已知联程、独立去返、地图联动与表单计算。排除相关组件时只移除依赖它的规则与示例。示例数据与链接仅用于解释语法，不作为真实推荐。

生成原则：

1. 输出纯 openui-lang，不添加 Markdown fence；宿主若用 JSON program 字段包装，应在传输层解包。
2. 使用已注册组件、位置参数与显式状态；响应式派生数据放普通变量。状态声明里的表达式只计算初值，不会替代后续 Store 状态。
3. 保留来源字段名、事实、原始 URL、实体 id、价格范围和不确定性，不将解析成功当作事实正确。用户要求预算、合计或分摊时，使用币种和范围相容的已知输入，将计算结果或估算与原始报价分开展示；不补造缺失价格、费用或汇率。
4. 用基础组件组合内容；卡片只表达真实对象或分组，不生成页面模板。图片由布局负责尺寸与比例，署名在相邻紧凑 Text 中保留来源和 Citation。
5. 交互控件必须有明确动作或状态结果，不生成装饰性按钮、虚构进度或无来源表单反馈。不依赖流式中间帧的固定显示顺序。

导出验证器接受 Lang 文件或包含 program 字段的 JSON：

```sh
swift run --package-path Tools/ContractExport ContractExport --validate "$PWD/path/to/program.lang"
swift run --package-path Tools/ContractExport ContractExport --validate "$PWD/path/to/historical.lang" --historical
swift run --package-path Tools/ContractExport ContractExport --reader-contract --include-search "$PWD/outputs/reader-contract"
```

`sourceIssues(in:)` 检查源码标识符等问题；`validationIssues(in:source:)` 汇总源码、运行时和组件契约问题；`validationIssues(in:)` 检查求值树。原有 Swift 调用默认使用 historical，profile: .generation 显式按 writer 检查排除组件与兼容字段；CLI 的 --validate 默认使用 generation，--historical 用于旧记录。普通渲染入口不自动执行 writer 校验或模型纠错；调用方按任务使用诊断。`presentationWarnings(in:)` 是独立的非阻断语义提示，不是实测对比度审计。诊断不替代事实审查或真实 UI 验收。

生成规则按显式组件依赖组织，全局事实/URL/动作约束不随单个组件排除而丢失。writer spec、签名与 Prompt 同源；共享语言生成器的 Prompt 中关于无动作按钮的通用默认说明，仍保留一处精确的策略文字替换，以符合本库“无动作禁用”的既有实现，不再用文字替换修改组件签名或 schema。默认 bindings=true、toolCalls=false 控制生成说明，不是运行时语法的禁用开关。

可选模型验证使用 `python3 Validation/Generation/run.py --model gpt-6.1-terra`，通过指定 Codex 账户执行真实调用。保存请求、原始输出、解析与运行时结果，不静默换型；结果写入 `outputs/generation`。已纳入回归的六份未改写程序保存在 `Tests/SwiftIntelligentUITests/Fixtures/GeneratedPrograms`，由 XCTest 检查当前运行时兼容性，不与 Gallery 的人工视觉验收混用。性能工作负载另归 `Benchmarks/LanguageRuntime`。

`--suite guided|free|all` 区分指定组件的回归与不点名组件的自由组合任务。free 套件包含解释、商品、数据、表单和地图任务，以及商品/表单跟进更新；来源、交互、呈现审查单独记录 pending，解析成功不推断为任务成功。跟进使用前次生成程序和原始来源事实，不能把模型前次输出升级为新事实。

CLI 保留导出、--validate 与 --case 命令结构，并提供历史验证和 reader 导出入口。官方组件参数与新版基线对齐；Image 等原有 framing 字段已进入生成签名。原生主题、图像缓存和地图选点等实现细节仍不成为私有 Lang 参数。ProductCard 不提供 offers 或其他旧数据契约的适配。

## 7. 验证与流式边界

| 层次 | 验证职责 |
|---|---|
| 构建 | macOS Swift Package 与 iOS Simulator Gallery，证明目标平台可编译 |
| 自动测试 | 计算函数、解析、绑定、流式、图片、字段、布局与组件数据；失败必须保留并解释 |
| 契约 | spec、Prompt、manifest 与 writer 同源；对比 2026-11-19 官方 main 的 55 个基础组件签名（SearchImage 仅在注入时参加），验证 59 个函数、动作、绑定及 Swift 原生偏差 |
| Gallery | 固定程序的 UI 演示和离线检查，不代替真实模型输出或真实操作 |
| 真实界面 | 指定设备、原程序与原图片的实际显示和操作，不能由编译或单元测试推断 |

makeState() 使用 `SwiftLang` 中 `OpenUIState` 的默认创建方式，不另建解析器、Store 或运行时。调用方必须接受以下运行时边界：

- 后生成的兄弟内容可能先于尚未就绪的前序区块显示，不能假设中间帧按源码顺序只追加。
- isSourceComplete 描述源码就绪，不是运行时分支可达性；未选中的条件分支中，被解析的未定义引用也会影响它与 SDK 诊断。
- 尚未闭合的组件可以出现在渲染树中，交互必须通过 context.canInteract 和 canDispatch 判断，不能假设 children 只包含完整组件。

这些行为不构成有序流式保证，生成契约不得要求模型依赖“有序就绪前缀”。若产品需要不同语义，应先修改实际运行时并验证真实场景，不得只调整提示词、文档或测试断言。

自动检查通过不等于所有设备、全部模型任务或所有流式时序已接受。外部视频、完整 VoiceOver 听读、真实业务动作和物理设备覆盖需要独立验证。

当前回归覆盖 writer / reader 分离、官方 flex 与宽度优先级、数字宽度不收缩与字符串宽度收缩、Row / column Box 换行分配、Col 的确定高度与内容最小高度、直接照片与纯照片 Box 的作用范围、百分比高度在换行 / stretch / RTL 下的稳定基准、Card 包装中的尺寸作用域、根视图百分比高度，以及颜色、间距、圆角和原生表面可读性。几何测试包裹实际注册的 Box / Image renderer，不用替身布局代替生产组件；这些 XCTest（包括像素检查）尚未编译或执行。

源码归属、Gallery 目录与资源、本地化及 `git diff --check` 已实际通过。11 个生成示例的组件依赖已静态核对；新增普通 Row、Grid 固定/自适应与 SearchImage Row 等程序已用固定官方 schema 和随包 JS parser 解析，均没有解析错误。该解析不代替 Swift writer 导出、原生渲染或真实 Agent 生成验收。

当前环境没有 Swift / Xcode，实际尝试的 `swift test`、SwiftPM 模块检查及独立消费者构建检查均因工具链缺失而未完成。Chromium 参考几何脚本也在启动时受环境 socket 权限限制阻止，没有取得浏览器实测结果。原生 Gallery、布局截图、焦点与交互仍待 Mac / iOS 验收。实际日志、固定官方源码与解析证据位于忽略的 `outputs/verification/intelligent-ui-primitives/`；这些限制不能被写成“全部官方实现或全部设备已验收”。

2026-11-22 的地图对齐候选覆盖固定输入 schema、同名标记保留、label 绑定、筛选和全览不写选中值、响应式高度，以及路线复用、取消和整条路线降级。已移除自定义地点卡片、详情和地点对象注入路径，其专用回归不再作为当前能力。五个 Gallery 用法和五个边界程序均已通过固定官方 schema 与随包 JS parser 的语法检查，没有解析错误或未完成标记。三个产品的源码归属检查、Gallery 目录与资源检查（35 个场景程序，OpenIntelligentUI 60 个组件／80 个用法，OpenUI 88 个组件／109 个用法）、三语言本地化检查（170 个键、150 个字面量调用键）及 `git diff --check` 实际通过；源码归属检查不代表 Swift 构建通过。实际运行 `swift test` 返回 127，因为环境没有 Swift；SwiftPM 模块检查和独立消费者构建也因工具链缺失而阻塞。地图 XCTest、Swift 构建、MapKit 网络响应、VoiceOver、窗口调整和原生画面尚未验收。实际日志与解析证据位于忽略的 `outputs/verification/intelligent-ui-map-alignment/`。

2026-11-16 的组件呈现审查在既有安静媒体占位基础上，继续修正紧凑 Markdown 段距、透明包装后的重复商品卡外框、Flashcard 自动说明、选项卡边界和实色选项说明的前景，以及日期字段选中前后的外壳切换；地图与公式移除常驻技术状态文案。日期回归覆盖重新编辑已有值、上下界、UTC 日界与本地化显示，并增加特定英文场景下字段尺寸和渲染不写值的检查。差异、源码/所有权、Gallery 完整性与本地化检查通过；`swift test` 因缺少 Swift 无法启动，原生构建、日期面板取消/确认、选项状态、VoiceOver 与实际截图尚未验收；检查日志在忽略的 `outputs/verification/component-presentation-audit/`。

2026-11-16 的文字调整基于 `3310e3d`，移除容器对默认字号的隐式降级与深色正文加重。Text、混排、Markdown、Title、图注和列表说明采用稳定角色；旧系统 TextKit 的图注同步使用 footnote，现有宿主字体配对继续生效。回归覆盖省略/显式默认值、根与 Card/透明包装/Grid/Carousel、深浅外观、辅助字号、Markdown 比例覆盖，以及挂载混排在主题更新时保留身份与文档 revision。差异、源码/所有权、Gallery 完整性与本地化检查通过；`swift test` 因缺少 Swift 无法启动，原生字体解析、XCTest 与实际界面待验收，日志在忽略的 `outputs/verification/semantic-typography/`。

2026-11-17 的客户端复测进一步定位默认 H1 的 macOS 行距差异，并将原字体组纳入收尾候选的 Debug/Release 门禁；不沿用此前“未运行”的阶段记录作为当前状态。具体输入、独立字体对照、修正范围与逐提交结果见[客户端复测收尾候选](validation-and-security.md#客户端复测收尾候选)。

仍需原生画面对照的设计判断包括内容卡与业务卡圆角角色、短代码工具栏及价格币种的视觉权重。SegmentedControl 当前按是否已有有效选择切换原生 Picker 与换行选项，首次选择的外观稳定性仍待修正和挂载验收；不能通过默认选中首项或给 nil 强配非法 tag 来掩盖未选择语义。图表完整数据入口、价格异常、分开出票说明、来源引用和真实输入错误具有信息作用，不因减少装饰而删除。

`OpenIntelligentUIPerformance.isEnabled` 默认关闭。调试时可 reset()/snapshot() 获取本库局部解析、测量、附件适配、地图、媒体、公式与 WebKit 的计数/耗时，不记录业务内容，也不代表底座运行时或整机性能。完整同内容重复测量、流式变更与取消测试应分别记录真实调用成本。

验证入口统一见[验证说明](validation-and-security.md)与[原生流水线](../.github/workflows/native-sdk.yml)。组件契约、构建、固定案例和实际交互分别报告，不将检查配置写成已通过的验收结果。

## 8. 迭代规则

后续新增、修改或删除能力，必须先判断它属于哪一层，再放在对应位置，不得用另一层的便利绕过边界。

1. **官方 DSL 优先**：先使用固定 55 组件、变量、绑定、Each 和基础布局证明缺口。官方组件不得追加私有参数，不得把 OpenUI 运行时自带的 ReferenceCatalog 当成这里的官方基线。
2. **组件只承担组件语义**：布局负责组合，控件负责交互，媒体负责资源与平台桥接，业务组件只保留独立业务语义。不得为单个页面或宿主场景新增隐式行为。
3. **DesignSystem 管呈现规则**：图注关系、阅读节奏、卡片层级、控件状态、大字号与平台适配由设计规则决定，不进入 DSL 参数，也不由父容器随意改变子组件语义。
4. **公共主题只放语义 token**：颜色、字体角色、间距、圆角、阅读宽度和通用媒体默认值可以共享。间距与圆角独立定义，chartColors 只表示图表序列色，不复用业务状态色。
5. **组件规格归组件**：表格列宽、商品缩略图、地图高度、图表字体等留在组件内部；通用 Row 媒体规则与组件自身的尺寸策略分开，不重新塞进公共主题。
6. **状态归适配层与调用方**：解析、求值、Store、原生状态、绑定和流式生命周期统一由 SwiftLang 接入；业务数据、消息生命周期、资源与动作结果由宿主负责，组件库不另建业务状态系统。
7. **Map 只表达地图**：点位、label 选择、分类过滤、fit 与展开由明确规则处理，不接收任意卡片投影，不为地图联动新增身份、筛选或路线方言。
8. **契约同源**：spec、Prompt、manifest 必须从实际 writer 组件目录生成，不用字符串补丁掩盖实现差异，不让模型学习 SDK 内部运行时细节。
9. **依赖可复现**：通用底座与组件库在同一提交验收；上游源码、构建工具和本地兼容补丁分别锁定。不得引入本机未提交 SDK、重复远端同名产品或浮动上游分支。
10. **验收真实行为**：组件契约、构建、测试、Gallery 和真实界面分别验证。不得通过修改文档、删除断言或隐藏失败把未接受的行为写成通过。
11. **文档只写当前体系**：本文维护当前组件库设计和约束，跨模块所有权以[架构](architecture.md)为准，不写版本流水、变更说明或试验过程。后续修改必须同步更新对应文档，不得另起一套互相冲突的架构说明。
