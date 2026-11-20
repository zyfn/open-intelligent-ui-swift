# OpenUI Gallery

文档版本：1.5 · 更新日期：2026-11-20

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
2. **场景**提供十个完整任务案例，按旅行出行、家居设计、购物选购、学习理解、账单分析、信息填写等用户任务类型分组。目录只保留分组与条目，不叠加数量统计或结构徽标；各产品使用自己的 Lang 程序。
3. 不提供侧栏搜索。组件分组的展开状态按产品保存，折叠和重展开保留当前文档与选中状态。
4. **组件库**按类别列出当前产品真实注册的全部组件。`StepsItem` 等从属项缩进到对应父组件下。点击父项或从属项，复用同一示例和当前编辑状态，源码面板显示所选定义的签名。名称、签名与描述从实际库读取。
   右键组件项（iOS 长按）可划线或取消划线。标记按产品和组件写入仓库的 [marks.json](Resources/Components/marks.json)，团队用 Git 提交和拉取同步。Gallery 从源码仓库启动时自动连接；其他位置启动可在组件菜单中选择标记仓库。
5. 工具栏 **源码**按需打开编辑器；组件的签名、说明和结构节点用法收在默认展开的“组件用法”中。编辑区占据面板主体，顶部导出，底部“应用源码”或“恢复原稿”。macOS 使用可收起的右侧面板，iOS 使用 sheet。
6. 画布尺寸、设备预设、旋转、缩放、外观、字号、locale 和导入集中在按需打开的预览设置中；macOS 使用 popover，iOS 使用 sheet，不在预览上方堆叠横向工具条。场景说明也在设置内查看。
7. **流式播放**位于顶部工具栏，与画布同屏。直接点按即可播放、暂停、继续或追加已捕获的后缀；菜单提供当前状态、从头播放、中断和完整渲染，不必打开预览设置。

画布在可用区域水平居中，超出空间时仍可滚动查看。宽高是实际逻辑尺寸，内容左右各留 20 pt；缩放仅改变观看倍率。Gallery 的导航、工具和画布边界使用系统语义样式，SDK 主题值不随外层美化改变。尺寸、主题和倍率不重建文档、不清空输入；切换条目或产品会退役旧 session，创建匹配的新文档。

所有外部动作和链接仅在 Gallery 本地记录，不连接 Agent、不导航、不上传表单或执行交易。原专项诊断资源保留给回归验证及 CLI，不出现在浏览入口。组件示例存于 `Resources/Components/`，不进入 SDK 产品。

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

`--library` 与 JSON 的 library 字段均使用 `openui|openintelligentui`。`--case` 也接受 `Components/Button` 这样的组件 ID。

在 `Components/ImageGallery` 示例中用「1 张」到「6 张」切换同一组照片的张数。用「手机」和「平板」设备预设可对照五图的上下排和左右排。Gallery 按画布模拟系统尺寸类并传入画布高度，缩放只改变显示倍率。

`Components/Card` 在一张卡片里展示两行图文和分隔线，下方用 EntityList 展示同一行程的键值信息。

可选参数还有 `--locale system|en|zh-Hans|ar`。`--help` 列出全部参数。外部文件限制为 1 MiB 以内的 UTF-8 文本。

## 图片与本地模拟工具

[图片清单](Resources/Images/catalog.json) 为原 Gallery 的六张照片保留原始 URL、署名与许可。公共 `OpenUIResourceContext` 只在来源 URL 精确匹配时返回对应的 Bundle 字节，两套 UI 使用相同的资源接口。其他案例图片保持原来的远程地址，不用本地图冒充其他景点或商品；远程图片、地图底图等仍需网络。

图片搜索状态使用明确的本地模拟适配器；`image-search-states` 命令行案例可检查等待 15 秒后成功、首次失败后重试恢复、缺少来源。成功返回精确来源的已打包相机照片，不模拟外网已恢复或真实图片搜索。本地 Query 诊断只允许 `gallery.seed` / `gallery.details`，通过两级依赖与刷新按钮展示语言运行时行为。两者均不连接 Agent 后端。日期函数的参考日固定为 2026-11-01，便于重复观察。

## 目录职责

| 目录 | 职责 |
|---|---|
| `Sources` | Gallery 应用、目录加载、文档 session、预览画布和调试工具 |
| `Resources/Cases` | 精选用户场景、每套库独立的 `.openui`、来源与选择说明 |
| `Resources/Components` | 逐组件展示程序；名称、签名和描述取自真实注册契约 |
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

该脚本运行独立包的 XCTest，再用**实际两套库的 reader**逐案例创建新状态，分别完整渲染求值和按 47 字符分块流式求值，检查最终 root、完成状态与错误（同时覆盖全部组件示例）；最后导出两份 reader 契约：

```sh
swift run --package-path Examples/Gallery OpenUIGallery \
  --export-contracts "$PWD/outputs/verification/gallery-contracts"
```

输出文件为 `openui.json` 和 `openintelligentui.json`。导出使用实际 SDK 的 `readerSpecification`，不是手写的 schema 子集。CLI 校验覆盖解析和宿主求值，不代表界面截图或真实交互已经通过。XCTest 另覆盖状态隔离、流式取消、查询链和 Mac 预览尺寸变化；原生执行结果应以对应提交的日志为准。

2026-11-16 的外层呈现调整通过目录和资源完整性检查，保留 10 个场景、9 个诊断、35 个程序、148 个组件示例及 6 张图片。当前执行环境没有 Swift/Xcode，`swift build --package-path Examples/Gallery` 返回 127；macOS/iOS 原生编译、设置与导入交互、画布及源码面板视觉仍待验收。
