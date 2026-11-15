# OpenUI Gallery

SDK 的统一原生调试入口。相同场景分别使用 Standard UI 和 Intelligent UI 的真实组件契约，由公共 `OpenUILibrary` / `OpenUIView` 接口展示。Gallery 是独立示例应用，不属于客户端 SDK 的库产品。

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

## 调试流程

1. 从左侧“核心场景”选择案例。默认提供从 [openui-case-lab](https://github.com/zyfn/openui-case-lab) 整理的 10 个场景，每个都有两份独立程序。
2. 在工具栏选择 **Standard UI / Intelligent UI**。同一场景自动切换到对应的 DSL；组件名与参数不跨库转换。
3. 选择手机、平板或阅读画布，调整宽高或横竖方向。这里的 `pt` 表示画布逻辑尺寸，包含内容左右各 20 pt 的留白；例如 390 pt 画布扣除这层留白后提供 350 pt 内容宽度。画布宽度范围为 240–1600 pt，高度为 320–1600 pt，与命令行一致；横竖切换后高度也保持至少 320 pt。
4. 用 **50%–150% 缩放**调整观看大小。缩放不改变布局宽度；宽高、主题、字号和 locale 都不重新解析源码、不清空已编辑的状态。
5. 在“调试面板”中打开源码或诊断。Mac 显示侧栏，iPhone/iPad 使用面板。编辑后点“应用源码”；“恢复原稿”回到该案例原始程序。
6. 用“流式播放 / 暂停 / 继续 / 中断 / 完整渲染”检查生成过程。切案例或切库会终止旧任务，并创建全新的文档状态；两份文档不会串用同名变量。

诊断面板显示解析/运行时错误、可刷新的状态快照，以及最多 30 条动作的参数和提交时 `formState`。所有外部动作和链接只记录在 Gallery 中，不执行导航、交易、表单上传或 Agent 请求。

“组件诊断”另保留 9 个聚焦案例：布局、输入、图片、空数据、长文流式、本地查询链，以及 Intelligent 的结构化图示、函数和图片搜索状态。只存在于一套库的诊断会明确标记，不自动套用另一套 schema。

## 导入现有源码

工具栏“导入程序”读取 `.openui` 或含 `program` 的 JSON。先选择目标组件库；JSON 可增加 `"library": "standard"` 或 `"intelligent"`，与当前选择不符时会报错。

```json
{
  "library": "intelligent",
  "program": "root = Col([Text(\"本地调试\")])"
}
```

命令行导入必须明确组件库。以下命令从仓库根启动，并为文件使用绝对路径：

```sh
swift run --package-path Examples/Gallery OpenUIGallery \
  --library standard \
  --program "$PWD/Examples/Gallery/Resources/Cases/standard/behavior-form.openui" \
  --width 390 --height 844 --zoom 1
```

也可以通过稳定案例 ID 直接定位：

```sh
swift run --package-path Examples/Gallery OpenUIGallery \
  --library intelligent --case monthly-spending --dark --accessibility
```

重现一次已捕获的流式分割时，使用 `--program /absolute/prefix.openui --stream-suffix /absolute/suffix.openui --library intelligent`。前缀以未完成状态展示，点击“追加流式后缀”完成。后缀按原始文本读取，可从对象项或字符串中间开始；编辑器保留完整的前缀加后缀，因此恢复、中断后完整渲染及重新播放都不会把半个程序误当成完整文档。

可选参数还有 `--locale system|en|zh-Hans|ar`。`--help` 列出全部参数。外部文件限制为 1 MiB 以内的 UTF-8 文本。

## 图片与本地模拟工具

[图片清单](Resources/Images/catalog.json) 为原 Gallery 的六张照片保留原始 URL、署名与许可。公共 `OpenUIResourceContext` 只在来源 URL 精确匹配时返回对应的 Bundle 字节，两套 UI 使用相同的资源接口。其他案例图片保持原来的远程地址，不用本地图冒充其他景点或商品；远程图片、地图底图等仍需网络。

图片搜索状态使用明确的本地模拟适配器；成功返回已打包相机照片，加载延迟 15 秒，失败直接抛错。本地 Query 诊断只允许 `gallery.seed` / `gallery.details`，通过两级依赖与刷新按钮展示语言运行时行为。两者均不连接 Agent 后端。日期函数的参考日固定为 2026-11-01，便于重复观察。

## 目录职责

| 目录 | 职责 |
|---|---|
| `Sources` | Gallery 应用、目录加载、文档 session、预览画布和调试工具 |
| `Resources/Cases` | 精选用户场景、每套库独立的 `.openui`、来源与选择说明 |
| `Resources/Diagnostics` | SDK 边界和生命周期的小型诊断，不混入用户案例 |
| `Resources/Images` | 本地照片及精确来源映射 |
| `Tests` | Gallery 本身的目录、CLI、导入、状态隔离、流式和真实预览状态测试 |
| `OpenUIGallery.xcodeproj` | 同一份源代码的 Apple App 构建入口 |

增加场景时更新相应 `catalog.json`，不要往 Swift View 中塞大段 DSL。每个核心场景必须提供两套程序。诊断可只支持一套库，但必须如实声明。新图片必须保留真实来源；只增加到对应 URL 的映射。

未来的 Agent 后端与 iOS 客户端示例应放在独立的集成示例目录，负责网络、会话和服务端配置，并消费 SDK 公共接口。Gallery 继续负责本地可重复的组件、布局和运行时调试，不承接业务后端代码。

## 验证

```sh
./Examples/Gallery/verify.sh
```

该脚本运行独立包的 XCTest，再用**实际两套库的 reader**逐案例创建新状态，分别完整渲染求值和按 47 字符分块流式求值，检查最终 root、完成状态与错误；最后导出两份 reader 契约：

```sh
swift run --package-path Examples/Gallery OpenUIGallery \
  --export-contracts "$PWD/outputs/verification/gallery-contracts"
```

输出文件为 `standard.json` 和 `intelligent.json`。导出使用实际 SDK 的 `readerSpecification`，不是手写的 schema 子集。CLI 校验覆盖解析和宿主求值，不代表界面截图或真实交互已经通过。XCTest 另覆盖状态隔离、流式取消、查询链和 Mac 预览尺寸变化；原生执行结果应以对应提交的日志为准。
