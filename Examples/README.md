# 示例与调试

本目录目前只有一个可运行应用：[OpenUI Gallery](Gallery/README.md)。它依赖根 Swift Package 的公开产品，用于查看两套 UI、编辑案例和回放流式内容。

Gallery 内分两组内容：**核心场景**展示完整任务回复，**组件诊断**集中复现布局、输入、图片和流式等问题。选择内容后，再选择 Standard UI 或 Intelligent UI；同一场景载入该库对应的程序。

从仓库根目录启动 macOS Gallery：

```sh
swift run --package-path Examples/Gallery OpenUIGallery
```

Xcode 使用 `Gallery/OpenUIGallery.xcodeproj` 的 `OpenUIGallery` scheme，可选择 My Mac、iPhone 或 iPad 模拟器。原生 App 打包和检查命令见 Gallery README。

## 各层放什么

| 位置 | 职责 | 修改原则 |
|---|---|---|
| `Gallery/Sources/` | 案例浏览、库选择、预览尺寸/缩放、源码编辑、流式与诊断工具 | 通过 SDK 公开接口渲染，不建立另一套 parser 或组件实现 |
| `Gallery/Resources/Cases/` | 精选任务案例、两套 UI 各自的 Lang 变体、来源与覆盖说明 | 同一任务共用稳定案例 ID；按真实组件契约分别编写程序 |
| `Gallery/Resources/Diagnostics/` | 边界状态、组件专项和开发诊断程序 | 与精选案例分组，不让人工验收草稿占据默认入口 |
| `Gallery/Resources/Images/` | 展示 App 自己使用的离线图片 | 保留来源与许可，不将图片打进 SDK 产品 |

其他任务从仓库根目录进入：[Tests](../Tests) 保存自动行为回归及固定输入；[Validation](../Validation/README.md) 提供程序静态校验和可选模型生成评测；[Benchmarks](../Benchmarks/README.md) 测量耗时与资源使用。它们各自维护输入和结果。

案例与 Gallery 程序只维护一份源码。标准库原有八个案例的哈希和历史 schema 固定在测试 fixtures，测试直接读取 Gallery 的实际程序；Gallery 自身使用当前所选库导出的 reader，不用历史测试 schema 运行内容。

宽度/高度决定内容实际得到的布局空间，缩放只改变预览画布的显示倍率。这两项分别控制，便于区分窄屏重排问题与观察比例。两套 UI 使用同一宿主接入方式，但保留自己的组件契约和设计系统；切换库时加载相应案例变体，不把一种语法机械改名成另一种。

展示数据是固定材料或明确说明的演示数据。选择、动作和工具反馈用于本地调试；它们不表示已调用真实 Agent、下单或完成业务操作。

## 自动检查与人工查看

```sh
python3 Tools/check_gallery_catalog.py
swift test --package-path Examples/Gallery
swift run --package-path Examples/Gallery OpenUIGallery --validate-fixtures
```

静态检查验证目录、身份、文件引用和双库变体；原生检查使用实际 SDK 解析/执行程序。视觉比例、交互体验和平台行为仍需打开 App 查看。

## 后续 Agent 与 iOS 完整集成

未来接入已有前后端项目时，在 `Examples/AgentClient/` 建独立集成示例，再按真实项目结构组织后端与 iOS 客户端。本次不创建空工程或模拟业务接线。

后端负责 Agent、会话、工具、鉴权与消息流；iOS 客户端通过所选 UI 产品的 `OpenUILibrary`、`OpenUIState`、`OpenUIView` 接收内容和处理动作。集成项目可以引用 Gallery 案例做固定回放，但不应依赖 Gallery 的导航、调试状态或私有类型。项目自己的依赖、密钥配置与运行说明保留在项目目录，不进入 SDK 的 `Sources/`。
