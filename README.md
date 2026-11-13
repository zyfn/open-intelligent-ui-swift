# Swift Intelligent UI

基于 OpenUI Swift 的 Apple 平台组件库：把模型生成的 OpenUI Lang 渲染为 SwiftUI 内容，并从实际组件目录导出 spec、Prompt 和 manifest。

## 开始之前

**修改代码、组件、主题、生成契约或文档前，必须先阅读 `docs/swift-intelligent-ui-design.md`。**

本项目有两条基线，不能混用：

- **运行时**：OpenUI Swift 固定远程 revision，负责 DSL 语法、解析、求值、状态、绑定和流式。
- **组件契约**：`thesysdev/open-intelligent-ui` 固定提交 `16ef26475999e3a021a50b1607a03717c0721255` 的 **55 组件参考库**。

OpenUI 运行时自带的 **ReferenceCatalog 不是本项目的组件基线**，不要用它替换或“修正”现有组件。

## 体系

```text
宿主：业务数据、消息生命周期、资源、动作结果
                 ↓
Swift Intelligent UI：组件、设计规则、语义 token、生成契约、诊断
                 ↓
OpenUI Swift：解析、求值、状态、绑定、流式、渲染遍历
                 ↓
SwiftUI / MapKit / WebKit / JavaScriptCore
```

| 层 | 职责 |
|---|---|
| Catalog | 注册组件、创建状态、维护读取目录与生成目录 |
| Components | 官方组件的原始参数与语义、少量独立业务组件 |
| DesignSystem | 阅读节奏、图注与卡片关系、控件状态、平台行为 |
| IntelligentUITheme | 可复用的语义颜色、字体、间距、圆角和通用默认值 |
| 组件 Metrics | 表格、商品、地图、图表等组件内部规格 |
| Generation | 从真实 writer 目录生成 spec、Prompt、manifest 和诊断 |
| Functions | 固定计算函数与 JSON 数据桥接 |

**公共主题不是组件参数仓库。** 表格列宽、商品缩略图、地图高度等留在组件内部；共享图文尺寸归 `EditorialMetrics`。间距与圆角独立，`chartColors` 不复用业务状态色。

## 构建与验证

```sh
swift test
swift run IntelligentUIGallery
swift run IntelligentUIGallery --validate-fixtures
swift run ContractExport outputs/contracts
```

iOS Gallery 使用 `Examples/Gallery/IntelligentUIGallery.xcodeproj`，scheme 为 `IntelligentUIGallery`。在 Xcode 中选择模拟器并运行即可，修改 Swift 代码或资源后需要重新构建、安装并启动。

`outputs/contracts` 包含：

- `spec.json`：组件签名、函数与 schema。
- `prompt.txt`：供模型使用的生成约束。
- `manifest.json`：组件、函数、动作及运行要求。

## 修改时必须遵守

1. **官方组件不追加私有 DSL 参数。** 先证明官方变量、绑定、Each 和布局组合无法表达，再讨论是否需要独立业务组件。
2. **视觉差异不要进入 DSL。** 图片预览、滚动、地图展开、图表内部选择等原生行为由 SDK 内部决定。
3. **Map 只负责地图。** 不接收任意卡片投影，不增加私有身份、筛选或路线协议；地点卡片放 Map 外组合。
4. **DesignSystem 管规则，token 管参数。** 不要让父容器隐式改变子组件业务语义，也不要把所有组件尺寸都塞入公共主题。
5. **生成契约必须与实现同源。** 不得用 Prompt 正则补丁或长段说明掩盖签名和运行时差异。
6. **OpenUI 只用远程固定依赖。** 禁止本机 path 依赖、未提交工作区和本地候选 SDK。
7. **不要改偏测试来制造通过。** 失败必须保留并解释；构建通过不等于真实界面通过。
8. **文档只写当前体系。** `docs/swift-intelligent-ui-design.md` 不记录版本流水或变更过程；历史证据另存，不在主文档展开。

## 给 Agent 的修改流程

1. 先阅读设计文档，确认修改属于 **DSL、组件行为、设计规则、token、组件规格还是宿主职责**。
2. 检查是否已有官方机制可完成，避免新增私有协议或隐式分支。
3. 同步修改实现、测试、生成契约和当前设计文档，不能只改其中一层。
4. 运行构建、测试、固定 Gallery 程序及必要的真实界面操作，保留失败证据。
5. 不自动提交、推送或发布；需要这些动作时按用户明确指令执行。
