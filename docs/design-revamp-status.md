# IntelligentUI 设计改造状态

分支：`codex/intelligentui-design-revamp`  
基线：`ed3f6f82abf6f7cc9e307e9bb2eb21073a1f7d79`（`codex/sdk-baseline`）  
交付标识：`0.1.0-preview.29-design-revamp`

这是本轮工作与验证记录；当前架构规范仍由 [设计文档](swift-intelligent-ui-design.md) 维护。

## 兼容与职责

- 保留完整历史 reader 的组件名称、位置参数、绑定、字段、类型、枚举和默认值；原来的六个新增入口也保持签名。本轮没有新增 Lang 组件或参数。
- OpenUI RC20 固定 revision、解析器、求值器、Store、流式和动作运行时不变。改动集中在 IntelligentUI 的设计规则、原生组件、媒体生命周期、诊断和评测工具。
- writer 结构化表达原 Prompt 已有的限制：Image 只推荐 src/alt，SearchImage 只推荐 query，ProductCard/TransportCard 新输出不含 priceText；历史 reader 仍接受原字段。
- 原有 Swift validation 方法默认 historical；新 profile: .generation 和 CLI 默认验证 writer。检查旧记录时显式传 --historical。
- 更好的错误反馈不会自动构成跨控件表单事务、业务提交校验或业务成功状态。

## 验证证据

| 检查 | 当前证据 |
|---|---|
| Python 工具语法 | check_lang_compatibility.py、check_localization.py、Benchmarks/run.py、Tools/package.py 的 py_compile 通过 |
| 本地化资源 | 162 个 key × 3 种语言，键集合与格式参数一致；152 个直接/条件字面调用 key 检查通过 |
| 补丁格式 | git diff --check 通过 |
| 原生首轮 | [运行 43463700580](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/43463700580)：Swift 6.3.3 / Xcode 26.6；新增契约测试缺少 MainActor 导致编译失败，已在后续工作树补标注；该轮未运行完整新组件改动 |
| 集成原生验证 | [PR #1 的 Checks](https://github.com/zyfn/open-intelligent-ui-swift/pull/1/checks) 按提交记录 macOS Swift tests、Gallery fixtures、全 61 reader 导出比较及 iOS Simulator build；必须以对应提交的实际结论判断 |
| 实际界面 / 读屏 / 播放 | 未完成。Gallery 新增“设计改造验收”与 locale/RTL/大字号/深色切换，供原生验收 |
| 真实模型评测 | 新增 5 个自由组合任务与 2 个跟进任务；尚未运行，不提供通过率或 Token 优势 |

下表“已实现”仅表示代码与针对性回归已加入，**不等于原生呈现验收通过**。“部分”列出保留边界；“保留”是兼容决定。

## 59 项处理记录

### 排版与设计规则

| ID | 本轮处理 | 状态 / 剩余验证 |
|---|---|---|
| D01 | 普通/混排 Text 共用角色、权重、行距；增加宿主原生字体配对 API | 部分：旧系统任意 Font 自动反解不承诺；配对与 Dynamic Type 待原生检查 |
| D02 | 默认强调 semibold，与深色正文 medium 区分 | 已实现；深色/增强对比度待验 |
| D03 | 显式文字角色优先，去除 Card 按位置猜副标题 | 已实现；嵌套内容截图待验 |
| D04 | Row 媒体规则尊重显式参数，稳定布局树与大字回退 | 已实现；跨宽度/字号状态待验 |
| D05 | Spacer 权重及自定义布局轴修正 | 已实现；Divider/Spacer 原生几何待验 |
| D06 | 显式 gap 不再改变后代阅读层级 | 已实现；等价包装回归待运行 |
| D07 | 阅读关系统一取 token，识别透明包装和来源段落 | 已实现；复杂嵌套关系待验 |
| D08 | 保留默认 columns=2；既有 minChildWidth 控制自适应，Prompt 增加使用指导 | 保留：没有静默改变原 Lang 默认含义 |
| D09 | Carousel 尾部停靠空间与末项索引修正 | 已实现；原生停靠/旧系统偏移待验 |
| D10 | 普通内容不强制卡片等高，同类实体保留比较规则 | 部分：横滑整体高度仍取最高内容 |
| D11 | Row/Grid/Carousel/Inline/ImageText 转发或计算 RTL | 已实现；真实 RTL 滚动/命中/读屏待验 |
| D12 | List marker 按单行判断，长 marker 独立行，编号进入可访问名称 | 已实现；大字与时间线待验 |
| D13 | Citation 使用有界滚动弹层，保留行内尺寸 | 已实现；行内触达与焦点返回待验 |
| D14 | 长代码 40 行 / 12,000 字符预览，可展开，复制完整原文 | 已实现；超长行与系统复制回调待验 |
| D15 | ImageText 使用稳定内容身份切换布局 | 已实现；footer 编辑/展开状态待验 |
| D16 | 静态 Badge 与动作外观区分，公共控件反馈统一 | 部分：没有宣称完成实测对比度与全部状态组合验收 |
| D17 | Quote 侧线与圆角表面收口 | 已实现；浅/深色画面待验 |

### 控件与表单

| ID | 本轮处理 | 状态 / 剩余验证 |
|---|---|---|
| C01 | 主动作与业务导航共用样式，低强调控件共用反馈，label 内保留命中区 | 已实现；真实命中、键盘和派发状态待验 |
| C02 | Pressable 自己显示 selected，预留勾选空间，禁止触发器内嵌套交互 | 已实现；长内容/读屏待验 |
| C03 | 编辑中即提示尚未生效的草稿和当前有效值；失焦后保留错误与恢复/采用操作 | 部分：没有跨控件 Form 提交拦截或原子提交 |
| C04 | Slider 原值与安全投影分开；DatePicker 真实未选择与候选确认；移除 Timer 一年上限 | 已实现；约束变化、原生选择器交互待验 |
| C05 | Slider marks 按测量分行避让并支持 RTL | 已实现；极端长标记/轨道对齐待验 |
| C06 | 选择状态的颜色、形状、只读与未知值规则一致 | 已实现；分段/回退切换和焦点待验 |
| C07 | 真正输入控件承载 label、焦点、错误与键盘 Done | 部分：未新增自动 Next 字段协调器；IME/Tab/键盘遮挡待验 |
| C08 | Form 使用阅读关系排版，明确只负责分组与现有动作上下文 | 已实现；不承诺自动表单事务/校验 |

### 图表与业务组件

| ID | 本轮处理 | 状态 / 剩余验证 |
|---|---|---|
| B01 | 图表明细/读屏保留当前 Value/Double 最短精确表示，轴可紧凑显示 | 已实现；不能恢复进入 Double 前已丢失的来源精度 |
| B02 | 缺值保留类别，对每条系列单独断线 | 已实现；Swift Charts 面积/折线绘制待验 |
| B03 | 饼图全量图例、点 ID 选择、负值说明、纵向 AX 明细、有界浮层 | 已实现；触摸/拖动/悬停待验 |
| B04 | 多行顶部对齐，缺值标记不单独翻转数字列，保留位置身份 | 已实现；多列/RTL/超长数值待验 |
| B05 | 商品三种布局都拥有完整商品图集 | 已实现；预览切换与商品隔离待验 |
| B06 | 长标题不截断，长价格与动作可重排，大字号纵向页脚 | 已实现；无断点长金额待验 |
| B07 | TransportCard AX 使用字段化纵排，常规三列与缺值槽位保留 | 已实现；长时间/日期偏移/分段展开待验 |
| B08 | 币种身份明确，异常分组/币种冲突有 typed 提示，来源文本与历史 reader 不收窄 | 已实现；价格格式提示为 advisory，不静默修复金额 |
| B09 | Timer 单调时钟与本地阶段，Progress 区分未知/非法 | 已实现；后台/恢复/读屏阶段变化待验 |

### 媒体与桥接

| ID | 本轮处理 | 状态 / 剩余验证 |
|---|---|---|
| M01 | 媒体框统一，显式 Lang 参数优先；Swift 宿主可配置来源比例/fit | 已实现；封面/完整图/占位切换待验 |
| M02 | 资源 revision 与像素档位参与缓存，派生背景缓存独立于布局变化 | 已实现；同 URL 更新与尺寸抖动待验 |
| M03 | 下载流式字节上限、4 并发、消费者取消、共享 LRU 预算 | 部分：缓存预算不等于可见视图或整机总内存硬上限 |
| M04 | 预览按视口/缩放选择高清档位，商品自有图集 | 已实现；缩放清晰度/峰值内存待验 |
| M05 | 并发相同查询合并，下载失败恢复可重新搜索，Swift 结果带 revision/来源 | 已实现；过期链接与取消竞态待验 |
| M06 | 组件保存相机状态，原生视图重建恢复当前视口 | 已实现；MapKit 重建/用户拖动待验 |
| M07 | 空态保持地图框，宿主 insets 与筛选/全览范围明确 | 已实现；实际遮挡区待验 |
| M08 | Map 标记差量更新、渲染 key 缓存、标签真实几何碰撞 | 已实现；地图交互与密集标记性能待验 |
| M09 | 整图节点/字节/路径/点数预算和显式失败；严格 viewBox，保留合法 SVG 路径语法 | 部分：安全检查不冒充完整 SVG parser，绘图语法交 WebKit |
| M10 | SVG 语义颜色取主题，画布随宽度，AX 增加原文标签 | 部分：保持既有 240 默认高度；图形对比度/文字可读性待验 |
| M11 | Math 等待完整源码，可取消串行任务和有界缓存；测量按内容版本 | 已实现；公式异步尺寸/长公式待验 |
| M12 | WebKit 加载/错误/重试、样式更新、宽度测量、销毁取消与暂停 | 部分：未新增全局进程/CPU池，仍挂载的离屏页面可能保留工作；原生验收待完成 |
| M13 | YouTube 16:9、完整源后加载、外部打开和页面失败恢复 | 部分：父页面 didFinish 不证明跨域播放器就绪/可播 |
| M14 | Inline 解析、样式和同宽测量缓存，局部性能计数 | 已实现；真实重复测量成本待验 |
| M15 | 附件按 child.id 复用 host，合并异步 size 失效，隐藏附件移除交互 | 已实现；控件身份/焦点/截断待验 |
| M16 | Popover 仅一棵内容树，滚动视口有界，trigger 纯呈现 | 已实现；键盘/焦点与嵌套内容待验 |
| M17 | Flashcard 仅挂载可见面，内容有界滚动 | 已实现；翻面后隐藏面的本地状态不保证驻留 |
| M18 | Disclosure 禁用状态与交互就绪同步 | 已实现；焦点/读屏待验 |

### 契约、评测与交付

| ID | 本轮处理 | 状态 / 剩余验证 |
|---|---|---|
| G01 | writer 结构化投影，同源 spec/Prompt/manifest | 已实现；保留一处 RC20 无动作按钮说明的精确策略文字替换 |
| G02 | 原子规则 + 显式组件依赖，全局事实规则独立 | 已实现；排除组合列入原生契约测试 |
| G03 | historical / generation 验证 profile，视觉 warning 独立 | 已实现；历史与新生成差异列入原生测试 |
| G04 | 6 guided + 5 free 任务，另含 2 跟进；事实/交互/呈现分别记账 | 部分：真实模型与操作评测尚未运行 |
| G05 | 162 键三语资源、显式 host locale、桥接环境传递 | 部分：译文/RTL/读屏待人审；协议数字与日期保持稳定 |
| G06 | 明确兼容边界、版本同步、全 61 reader 比较工具与组件处置 | 已实现；原生导出对比为 CI 必过门禁 |
| G07 | 新增定向回归、局部计数与耗时、原生 CI、Gallery 验收入口 | 部分：不得用编译/非空截图替代真实交互和性能证据 |

## 61 入口覆盖

| 入口 | 处理 |
|---|---|
| Col、Row、Box、Grid、Card、Carousel、Spacer、Divider | 阅读关系、布局轴、显式参数与 RTL；Grid 默认语义保留 |
| Form、Popover、Disclosure | 分组边界、有界单树内容、触发器与就绪状态 |
| Text、Title、Caption、Label | 角色统一与显式字号；原字段保留 |
| Badge、Link、List、ListItem、Markdown、Quote、Code | 静态/动作区分、marker、表面、长代码 |
| ImageText、Citation、Flashcard | 内容身份、弹层边界、资源生命周期 |
| Celebration、Icon | 保留现有语义，不为改造改写稳定能力 |
| Button、IconButton、Pressable | 动作家族、命中、selected 与嵌套交互 |
| Input、TextArea、Select、SegmentedControl、RadioGroup、Checkbox | 草稿、字段语义、键盘、选择状态 |
| Slider、DatePicker、Timer | 非法/越界原值与局部状态 |
| Table、Chart、ProductCard、TransportCard、Progress | 数值保真、重排、图集与状态 |
| Image、SearchImage、Math、Map、MapMarker、YouTube、HtmlView | 资源、桥接、相机、恢复与可访问信息 |
| Svg、Circle、Ellipse、Rect、Line、Path、Polyline、Polygon、G、SvgText | 整图预算与主题/响应式处理；保留原签名 |

## 复现

```sh
swift test
swift run IntelligentUIGallery --validate-fixtures
python3 Tools/check_lang_compatibility.py
python3 Tools/check_localization.py
swift run IntelligentUIGallery --fixture 设计改造验收 --locale ar --accessibility --dark
xcodebuild -project Examples/Gallery/IntelligentUIGallery.xcodeproj \
  -scheme IntelligentUIGallery -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

人工验收至少包括 320/390 点与桌面宽度、浅/深色、普通/无障碍字号、en/zh-Hans/ar、触摸/键盘/VoiceOver，以及网络加载、失败、取消、来源替换、同 URL revision 更新。先记录失败，再决定能否合并；不把此分支称作已经完成全设备验收的发布版。

