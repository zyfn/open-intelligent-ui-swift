# OpenUI Gallery

文档版本：1.18 · 更新日期：2026-11-23

SDK 的统一原生调试入口。相同场景分别使用 OpenUI 和 OpenIntelligentUI 的真实组件契约，由公共 `OpenUILibrary` / `OpenUIView` 接口展示。Gallery 是独立示例应用，不属于客户端 SDK 的库产品。

## 启动

需要 macOS、Xcode 与 Swift 6 工具链。运行时保持 macOS 13 / iOS 16 最低版本。

在仓库根目录运行：

```sh
swift run --package-path Examples/Gallery OpenUIGallery
```

也可以打开 `Examples/Gallery/OpenUIGallery.xcodeproj`，选择 `OpenUIGallery` scheme，再选择 My Mac、iPhone 或 iPad 模拟器运行。命令行构建可直接打开的 Mac 应用：

```sh
./Examples/Gallery/build-app.sh
open Examples/Gallery/.build/app/Build/Products/Debug/OpenUIGallery.app
```

App 打包由 Xcode 处理，包括 Gallery 与依赖 SDK 的资源，不依靠复制 SwiftPM 可执行文件后的绝对构建目录回退。

## 浏览

1. 在左侧选择 **OpenUI / OpenIntelligentUI**，整体切换场景、组件目录与文档。每套产品记住本窗口内上次浏览的位置；第一次切换优先保留同一场景。
2. **Design System** 用色卡、字样和尺寸示意展示 OpenUI 组件主题。颜色按表面、文字、语义状态、按钮和表格组织，下方是字阶、间距、圆角、阴影和图表配色。Muse 默认与 Liquid Sphere 都支持浅色和深色。打开「用于 OpenUI 预览」可把当前主题应用到 OpenUI 画布。OpenIntelligentUI 使用自己的主题。
3. **组件库**按所选库的目录分组。OpenUI 从 SDK 的 [Lang 组件目录](../../docs/openui.md#组件目录) 读取分组和组件顺序，侧栏合并显示表格与图表、表单与按钮。OpenIntelligentUI 使用布局、内容、控件、媒体和数据展示五组。Card 等可直接比较的形态一起展示。其他用法可从组件页顶部切换，选中后可运行、操作或回放流式。
4. `StepsItem` 等从属项缩进到父组件下，共用当前用法和编辑状态。右键组件项（iOS 长按）可划线或取消划线，团队通过仓库内的 [marks.json](Resources/Components/marks.json) 同步。Gallery 从源码仓库启动会自动连接，其他启动位置可通过组件菜单选择标记仓库。
5. 工具栏 **源码**按需打开编辑器；组件的签名、说明和结构节点用法收在默认展开的“组件用法”中。编辑区占据面板主体，顶部导出，底部“应用源码”或“恢复原稿”。macOS 使用可收起的右侧面板，iOS 使用 sheet。
6. 画布尺寸、设备预设、旋转、缩放、外观、字号、locale 和导入集中在按需打开的预览设置中；macOS 使用 popover，iOS 使用 sheet，不在预览上方堆叠横向工具条。场景说明也在设置内查看。
7. **流式播放**位于顶部工具栏，与画布同屏。直接点按即可播放、暂停、继续或追加已捕获的后缀；菜单提供当前状态、从头播放、中断和完整渲染，不必打开预览设置。
8. **场景**提供十个完整任务案例，按旅行出行、家居设计、购物选购、学习理解、账单分析、信息填写等用户任务类型分组。各产品使用自己的 Lang 程序。组件分组的展开状态按产品保存。

画布在可用区域水平居中，超出空间时仍可滚动查看。宽高是实际逻辑尺寸，内容左右各留 20 pt，缩放只改变观看倍率。尺寸、主题和倍率保留当前文档和输入。切换到其他组件、用法或产品会创建对应的新文档。

[Muse token 快照](Resources/DesignSystem/muse.tokens.json) 记录来源修订，从 `base.tokens.json` 与 `liquid-sphere.overrides.json` 取客户端传给 SDK 的配色、文字与尺寸。Gallery 通过同一份 `OpenUITheme` 映射预览组件并生成色卡，SDK 的默认值补齐其余主题项。刷新快照时沿用 Muse 的浅深色覆盖、字体属性合并和尺寸别名解析结果。

经 SDK action 回调派发的外部动作和链接只在 Gallery 本地记录，不连接 Agent、不上传表单或执行交易。原专项诊断资源保留给回归验证及 CLI，不出现在浏览入口。组件示例存于 `Resources/Components/`，不进入 SDK 产品。

## 导入现有源码

预览设置中的“导入源码”读取 `.openui` 或含 `program` 的 JSON。先在左侧选择目标产品；JSON 可增加 `"library": "openui"` 或 `"library": "openintelligentui"`，与当前选择不符时会报错。

```json
{
  "library": "openintelligentui",
  "program": "root = Col([Text(\"本地调试\")])"
}
```

命令行导入必须明确组件库。以下命令从仓库根启动，并为文件使用绝对路径：

```sh
swift run --package-path Examples/Gallery OpenUIGallery \
  --library openui \
  --program "$PWD/Examples/Gallery/Resources/Cases/openui/behavior-form.openui" \
  --width 390 --height 844 --zoom 1
```

也可以通过稳定案例 ID 直接定位：

```sh
swift run --package-path Examples/Gallery OpenUIGallery \
  --library openintelligentui --case monthly-spending --dark --accessibility
```

重现一次已捕获的流式分割时，使用 `--program /absolute/prefix.openui --stream-suffix /absolute/suffix.openui --library openintelligentui`。前缀以未完成状态展示，点击顶部播放控件的“追加流式后缀”完成。后缀按原始文本读取，可从对象项或字符串中间开始；编辑器保留完整的前缀加后缀，因此恢复、中断后完整渲染及重新播放都不会把半个程序误当成完整文档。

`--library` 与 JSON 的 library 字段均使用 `openui|openintelligentui`。`--case` 也接受 `DesignSystem` 和 `Components/Button` 这样的组件 ID。

在 `Components/ImageGallery` 示例中用「1 张」到「6 张」切换同一组照片的张数。用「手机」和「平板」设备预设可对照五图的上下排和左右排。Gallery 按画布模拟系统尺寸类并传入画布高度，缩放只改变显示倍率。

`Components/Card` 用同一份标题和正文对照 `card`、`sunk`、`clear`。在「用法」中选「图文卡片与分隔线」可查看图文行与 EntityList 的组合。

`Components/EntityList` 展示上游的两列排版、两种尺寸和数字字样。`Components/Stack` 的「两端对齐 · 键值行」可用流式播放查看先给布局、再给文案的组合。

`OpenIntelligentUI / Components/Map` 的「预选地点与绑定」直接显示选中 label，可核对筛选和全览不改写绑定、展开后点选标记会关闭展开；「初始地点与后续选择」检查字面量初值后的交互。「同名标记」在两个既有坐标使用明确的演示名称，检查两点都保留且按同一 label 高亮。切换窄宽画布与大字号核对地图高度、标记名称和控件可访问性；道路示例检查加载及失败时的直连概览与成功后的道路。参数与平台边界见[地图说明](../../docs/openintelligentui.md#25-地图与平台桥接)。

可选参数还有 `--locale system|en|zh-Hans|ar`。`--help` 列出全部参数。外部文件限制为 1 MiB 以内的 UTF-8 文本。

## 图片与本地模拟工具

[图片清单](Resources/Images/catalog.json) 为原 Gallery 的六张照片保留原始 URL、署名与许可。公共 `OpenUIResourceContext` 只在来源 URL 精确匹配时返回对应的 Bundle 字节，两套 UI 使用相同的资源接口。其他案例图片保持原来的远程地址，不用本地图冒充其他景点或商品；远程图片、地图底图等仍需网络。

图片用法中的加载与失败状态用 Gallery 私有的 `gallery.invalid` 诊断地址触发。延迟请求在 6 秒后返回同一张打包相机照片，失败请求在本地结束。

图片搜索状态使用明确的本地模拟适配器；`image-search-states` 命令行案例可检查等待 15 秒后成功、首次失败后重试恢复、缺少来源。成功返回精确来源的已打包相机照片，不模拟外网已恢复或真实图片搜索。本地 Query 诊断只允许 `gallery.seed` / `gallery.details`，通过两级依赖与刷新按钮展示语言运行时行为。两者均不连接 Agent 后端。日期函数的参考日固定为 2026-11-01，便于重复观察。

## 目录职责

| 目录 | 职责 |
|---|---|
| `Sources` | Gallery 应用、目录加载、文档 session、预览画布和调试工具 |
| `Resources/Cases` | 精选用户场景、每套库独立的 `.openui`、来源与选择说明 |
| `Resources/Components` | 组件分组与用法程序，名称、签名和描述取自真实注册契约 |
| `Resources/DesignSystem` | Muse 两套主题的 Gallery token 快照 |
| `Resources/Diagnostics` | 测试与 CLI 使用的边界回归程序，不出现在浏览入口 |
| `Resources/Images` | 本地照片及精确来源映射 |
| `Tests` | Gallery 本身的目录、CLI、导入、状态隔离、流式和真实预览状态测试 |
| `OpenUIGallery.xcodeproj` | 同一份源代码的 Apple App 构建入口 |

增加场景时更新相应 `catalog.json`，不要往 Swift View 中塞大段 DSL。每个核心场景必须提供两套程序。诊断可只支持一套库，但必须如实声明。新图片必须保留真实来源；只增加到对应 URL 的映射。

未来的 Agent 后端与 iOS 客户端示例应放在独立的集成示例目录，负责网络、会话和服务端配置，并消费 SDK 公共接口。Gallery 继续负责本地可重复的组件、布局和运行时调试，不承接业务后端代码。

## 验证

OpenUI 的设计规则与实施状态统一见 [OpenUI 组件指南](../../docs/openui.md)，此处只记录使用现有场景的原生验证入口。阅读解释用 `heat-pump`，图片选项用 `bedroom-style`，表单用 `contact-form`，地图用 `scene-discovery`，数据分析用 `monthly-spending`；商品卡和宽表分别用 `desk-lamp`、`code-isolation`。这些案例保留原始来源内容，不为视觉对照缩短文案。

进入案例后在预览设置中切换宽度、外观、字号与 locale，实际操作完整查看入口、表格阅读模式、字段和继续对话。涉及加载失败或流式边界时使用已有诊断和流式工具。执行环境、实际内容宽度、输入、截图及结果保存在根目录忽略的 `outputs/`，不另存设计规范副本；未执行的场景不能标为验收通过。

```sh
./Examples/Gallery/verify.sh
```

该脚本运行独立包的 XCTest，再用**实际两套库的 reader**逐案例创建新状态，执行完整求值与三种流式分片：原有 47 个 Character、不等长 `1/7/24/128` 个 Unicode scalar，以及每块最多 128 个 scalar 的语法边界分片。每种分片使用独立 Store 和 parser，完成后检查错误、解析完整性、未解析引用和完成/中断状态，并与完整求值逐值比较内容、组件属性、动作、绑定及默认状态；节点身份与原生缓存元数据不参与语义比较。现有 226 份场景、诊断和组件用法对应 226 次完整检查与 678 次流式检查。最后导出两份 reader 契约：

```sh
swift run --package-path Examples/Gallery OpenUIGallery \
  --export-contracts "$PWD/outputs/verification/gallery-contracts"
```

输出文件为 `openui.json` 和 `openintelligentui.json`。导出使用实际 SDK 的 `readerSpecification`，不是手写的 schema 子集。CLI 校验覆盖解析和宿主求值，不代表界面截图或真实交互已经通过。XCTest 另覆盖状态隔离、流式取消、查询链、Mac 预览尺寸变化，以及小型双库程序在每个 Unicode scalar 边界下的内容保全；比较器的反例会实际更换正文、绑定、动作或未显示的默认值，确保无报错的语义漂移仍会失败。原生执行结果应以对应提交的日志为准。

### 两库完整阅读场景截图

在 macOS 上执行完整场景的渲染检查并保留截图：

```sh
OPENUI_SNAPSHOT_DIR="$PWD/outputs/verification/visual" \
  swift test --package-path Examples/Gallery --filter GalleryEditorialRenderingTests
```

检查直接读取两库各自的 `heat-pump`、`code-isolation` 完整程序，以及 OpenIntelligentUI 既有的 `Row/image-reading` 图片用法。两库阅读场景和图文行均覆盖 320 / 390 pt、Light / Dark；两库热泵场景另覆盖 390 pt 的辅助字号 `accessibility3`，共 22 种组合。正文保留自然高度，Disclosure / Accordion 保持默认开合状态；图片通过精确来源映射使用已有打包资源，截图资源加载器拒绝其他 URL。SVG 等待实际 WebKit 内容就绪，正文等待原生可访问性树中出现开头、中部和结尾的阅读章节后捕获。

输出保存在 `gallery-editorial/` 子目录；未设置 `OPENUI_SNAPSHOT_DIR` 时，使用当前工作目录下的 `outputs/verification/visual`。文件名以 `openui-` 或 `openintelligentui-` 区分库，包含 PNG、对应完整 `.openui`、实际观察到的正文 `.txt`，以及记录库、宽高、平台、外观、字号和捕获状态的 JSON。布局或加载失败时仍保存可捕获的挂载画面和错误信息。断言检查解析、渲染、章节内容、尺寸、图形边界和非空图像；主次、图注归属、留白及深色可读性仍需查看截图。它们是 macOS 在手机宽度下的证据，不代表 iPhone / iPad 已验收，也不计作模型生成质量分数。[统一验证入口](../../Validation/SDK/README.md)的 macos profile 会随对应 check 收集这些产物，路径为 `profile/visual/gallery-tests/gallery-editorial/`；只有对应测试实际成功执行，才能记录为本提交的渲染结果。
