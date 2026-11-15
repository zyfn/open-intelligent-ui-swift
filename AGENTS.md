# OpenUI Swift SDK — Agent 工作约定

本文件适用于整个仓库。目标是维护稳定、原生体验良好、职责清晰的 SDK，避免后续任务重新引入重复实现、跨层耦合和无关工程。

用户当前的明确要求优先于本文。已经授权的工作直接推进；不要把本文解释为每一步都要重新征求确认。普通修复沿用现有边界；任务确实需要改变架构或契约时，明确变更理由、兼容影响和验证方式，并同步更新相关说明。

## 1. 项目定位与阅读入口

本项目将模型生成的 OpenUI Lang 渲染为 Apple 平台的原生 SwiftUI 内容，采用**一套语言运行机制、一套公共原生宿主、两套独立组件库**，通过同一个根 Swift Package 分发。

- SDK 负责语言执行、原生渲染及组件交互机制。
- 宿主负责 Agent、模型和工具通信、账号权限、消息列表、滚动、业务数据与真实业务结果。
- Standard UI 与 Intelligent UI 是并存的产品选择；不将其中一套视为待删除的旧版，不强行合并其语法或设计系统。

开始前查看当前分支、`git status` 与已有差异，保留他人未提交的工作。以当前源码和实际提交为准，不依据旧会话重新执行已经完成的迁移。

按任务读取对应说明，不必每次加载全部文档：

| 任务 | 主要入口 |
| --- | --- |
| 客户端接入与产品选择 | [README.md](README.md) |
| 模块、运行机制与资源边界 | [docs/architecture.md](docs/architecture.md) |
| Intelligent UI 组件与设计 | [docs/swift-intelligent-ui-design.md](docs/swift-intelligent-ui-design.md) |
| 标准 UI 组件与契约 | [docs/standard-ui/README.md](docs/standard-ui/README.md) |
| 语言语义与兼容性 | [docs/language/README.md](docs/language/README.md)、[compatibility.md](docs/language/compatibility.md) |
| 示例、调试与后续集成 | [Examples/README.md](Examples/README.md)、[Gallery 指南](Examples/Gallery/README.md) |
| 资源构建、安全与原生验收 | [docs/validation-and-security.md](docs/validation-and-security.md)、[CI](.github/workflows/native-sdk.yml) |

本文保存长期约定，不保存某一轮任务的进度、失败日志或临时待办；具体实现细节归上述文档。

## 2. 模块边界

| 模块 | 职责 | 允许的 SDK 内部依赖 |
| --- | --- | --- |
| `OpenUILang` | 语言核心桥接、AST/Value、解析与求值、Store、动作/查询语义、序列化与执行预算 | `COpenUIRegExp` |
| `OpenUICore` | 公共 library/view/state、组件注册、context/host、渲染身份、绑定、生命周期与通用资源通道 | `OpenUILang` |
| `OpenSwiftUI` | 标准组件目录、契约、主题、布局和媒体呈现 | `OpenUICore`、`OpenUILang` |
| `OpenIntelligentSwiftUI` | Intelligent UI 组件、设计系统、媒体呈现、函数及 reader/writer 生成契约 | `OpenUICore`、`OpenUILang` |

- 根 `Package.swift` 维护四个公开库产品；`COpenUIRegExp` 是语言层内部实现，不是第五个公开产品。
- Lang 不导入 SwiftUI、UIKit 或 AppKit。语言客户端可以只依赖 Lang。
- Core 不导入任一 UI 库，不按具体组件名硬编码行为，不持有任一库的主题 token 或视觉布局、占位策略。组件差异通过注册元数据和既有扩展点表达。
- 两套 UI 互不依赖，也不得通过中间模块形成间接依赖。宿主可以只选择其中一套。
- 将真正通用的运行机制放入 Core；各库的视觉、设计系统和特有媒体呈现留在本库。不要只因代码相似就把视觉策略搬进 Core。
- 复用已有语言核心和公共宿主，不另行实现解析、状态语义或平行渲染引擎；通过既有公开 API 创建 parser、Store 或 state 是正常用法。

当前平台与工具链要求以 [Package.swift](Package.swift) 为准。调整最低平台、Swift 语言模式或工具链时同步处理可用性门控、示例和 CI，不通过提高最低版本来掩盖普通编译问题。

## 3. 客户端接口、状态与流式

统一接入链路是：选择 `OpenUILibrary.standard()` / `.intelligent()`，通过 `library.makeState(...)` 创建状态，使用 `OpenUIView(state:library:)` 展示。自建组件库通过 Core 的同一组接口接入。

- 保持两套库在状态创建、流式输入、动作回调和契约导出上的公共用法一致，不增加并行的专用宿主接入流程。
- 每条独立文档持有自己的 state。切换库时创建匹配的新 state；历史消息保留原来的 library/state 配对，不对旧 state 原地替换 schema 或 registry。
- 不在 SwiftUI `body`、尺寸拟合或布局测量中创建 state、反复提交源码或写入业务状态。布局和缩放改变不能触发重新解析或清空用户编辑。
- 文档语义观察由 Core host 承担；不要在 `OpenUIView` 或纯视觉包装层重复观察整个 state，导致每个流式 chunk 重建整棵展示。
- 保持节点身份、流式槽位、完成/中断/重置/替换的语义。异步查询和资源回调必须保留文档 revision/epoch 隔离，旧文档结果不能写回新文档。
- 通用资源加载、鉴权作用域和预算通过 Core 的资源 context 注入；缓存、View task 和已解码内容的身份都要考虑资源上下文变化。不要绕过已有资源限制。
- 图片比例、占位、加载视觉、预览和主题属于具体 UI 库。不要把原生图片通道的保证扩展宣称为 WebKit、Markdown 或 MapKit 所有请求的保证。

## 4. 语言、组件契约与生成资源

- 组件名、位置参数顺序、枚举、绑定、动作及历史 reader 都是兼容边界。UI 美化、目录整理或性能优化不得顺带修改这些契约。
- 新增或变更组件能力须服务于当前任务，并在所属库的真实注册定义中实现；不要为某个示例临时加私有 Lang 参数，或让 Core 按组件名特殊分支。
- Standard 与 Intelligent 使用各自真实的组件目录。相同用户场景可以有两份独立程序，不能只替换组件名称来假定语法兼容。
- reader 负责读取已支持的内容，writer 负责当前生成能力。限制新生成组件时保留历史读取路径；不要将 writer 的裁剪直接用于历史 state 的解析。
- Prompt、spec、schema、参数顺序与 renderer 必须保持一致。优先从实际注册库导出，不另维护一套手写权威 schema；不要排序 schema 属性或位置参数，也不通过放宽校验掩盖漂移。
- 语言来源以 [Tools/upstream.json](Tools/upstream.json)、[Core 适配清单](Tools/Core/adaptations.json) 和资源 manifest 为准。上游升级要核对真实来源、适配及语义变化，不能只改版本号或复制未经核对的产物。
- SDK 随包分发固定的运行资源，不在运行时下载脚本或跟随 `latest`。保留历史版本语言文档时明确其适用范围，模型输入使用当前库导出的契约。
- 生成的 JS、组件目录、公式/字体等资源应通过对应 `Tools` 生成流程维护，并同步锁文件、manifest、哈希和许可。不要只改生成结果或预期哈希来制造验证通过。
- 不为让测试变绿而重写历史 fixture 或契约快照；确有语义变更时记录依据，并验证新的预期。原始模型输出保留原样，新评测追加独立记录。
- 视觉修改遵循所属库的设计系统与现有 token。共享机制不要求两套 UI 使用相同外观；新增主题、组件或全局视觉重构应属于当前任务范围。

## 5. 目录归属

| 位置 | 放什么 |
| --- | --- |
| `Sources/` | 唯一一份 SDK 模块源码及其运行资源 |
| `Tests/` | 原生行为回归、历史契约及测试所需 fixtures |
| `Examples/Gallery/` | 独立的双库原生调试应用 |
| `Examples/Gallery/Resources/Cases/` | 精选完整任务场景与两套库各自的 Lang 程序 |
| `Examples/Gallery/Resources/Diagnostics/` | 布局、输入、资源、流式等专项复现程序 |
| `Tools/` | 契约导出、资源生成和维护检查 |
| `Benchmarks/LanguageRuntime/` | 可重复的语言耗时与内存测量 |
| `Validation/`、`Validation/Generation/` | 程序静态校验、可选真实模型生成评测 |
| `Fixtures/` | 公共语言兼容验证数据 |
| `docs/` | 当前有效的架构、语言、组件与设计说明 |
| `outputs/` | 已忽略的本地生成结果、评测及验收材料 |

- 根包只维护 SDK 库与测试。Gallery、ContractExport 和 LanguageRuntime 使用各自独立开发包，通过根 SDK 的公开产品接入。
- 不恢复嵌套 SDK、同名模块的第二份源码、旧目录软链接、重复 Demo 入口、过时迁移脚本或历史报告集合。迁移历史保留在 Git 中。
- 不将 Gallery 的图片、案例、导航、调试状态或模型服务代码打入 SDK 产品。
- 可复用案例完整源码只维护一份，测试可以引用该来源并保留明确的历史摘要/契约；不要为了目录整齐复制多份会漂移的程序。
- 删除或移动文件时检查源码、测试、包资源、脚本、文档和 CI 引用。许可与来源信息随所属内容保留，不能当作杂项删除。
- 真正需要 Agent 后端与 iOS 端到端示例时，在 `Examples/AgentClient/` 建独立集成项目并维护自己的依赖、配置和说明。任务未要求时不创建空工程；已有外部客户端继续通过公开 SDK 接口集成。

## 6. Gallery 与评测规则

- 日常视觉调试统一使用 Gallery。核心场景按稳定 ID 提供两套程序；仅适用于一套库的诊断如实标记。
- 案例通过资源文件与 catalog 维护，不往 Swift View 塞大量 Lang。保留真实来源和图片对应关系；演示数据、模拟工具与真实调用明确区分。
- 逻辑宽高控制布局空间，zoom 只控制观看倍率。切换案例/库时退役旧 session；调整尺寸、主题和倍率时保留当前文档状态。
- Gallery 的本地动作记录不代表已调用真实 Agent、提交表单或完成交易。
- Gallery 看效果，Tests 验证行为，Benchmarks 测性能，Validation 校验程序及生成结果；不把这些结果相互替代。
- 性能结果记录机器、系统、构建配置、输入与测量条件；模型评测记录真实请求、原始输出和人工审查状态。无实际数据不宣称性能提升、通过率或 Token 优势。

## 7. 按改动范围验证

使用现有检查入口，验证实际受影响的边界。不要为纯说明修改新增测试或启动无关的完整评测；不要删除断言、放宽阈值或跳过失败任务来掩盖问题。

| 改动范围 | 验证入口 |
| --- | --- |
| 文档、目录或资源引用 | `git diff --check`，检查本地链接、路径与调用方；涉及目录所有权时运行 `python3 Tools/check_openui_integration.py` |
| 模块依赖或公开接入接口 | `python3 Tools/check_module_boundaries.py`；`python3 Tools/check_product_consumers.py --scratch-root /tmp/openui-consumers` |
| SDK 行为 | 运行对应 XCTest；提交验收按 CI 执行 `swift test` |
| 宿主观察、流式与尺寸拟合 | 对应运行时回归；`swift test -c release --filter 'HostSizingIsolationTests|CoreHostIsolationTests'` |
| Gallery 案例、宿主或资源 | `python3 Tools/check_gallery_catalog.py`；`./Examples/Gallery/verify.sh`；涉及视觉/交互时打开原生 App 复现 |
| 组件契约 | `python3 Tools/check_lang_compatibility.py`，对应原生契约与历史输入回归；标准库同时检查其目录/契约测试 |
| 本地化 | `python3 Tools/check_localization.py` |
| 语言、生成器或依赖 | 按 CI 重建对应资源，检查产物差异，并执行相关兼容回归和依赖安全审计 |

原生入口：macOS 使用 `swift run --package-path Examples/Gallery OpenUIGallery`；iOS 使用 `Examples/Gallery/OpenUIGallery.xcodeproj` 的 `OpenUIGallery` scheme。涉及窄屏、字号、主题或平台差异时，验证相应场景，不只查看默认画布。

SwiftPM 图、独立消费者、XCTest 和 Apple 平台构建需要相应的 Swift/Xcode 环境。缺少工具链或 CI 未真正启动时，明确记录未执行及阻塞原因，不用替代脚本输出冒充原生结果。

汇报时区分：源码/静态检查、辅助语法检查、Node 回归、Swift 编译/XCTest、原生截图/交互、性能测量、真实模型评测。结论绑定实际提交和日志；解析成功不代表渲染、交互、事实或视觉质量通过。

## 8. 交付与维护

- 围绕当前任务做完整且必要的修改，不顺手引入与任务无关的组件、依赖、目录层级或架构重写。
- 新行为及 bug 修复补充有意义的回归；可逆的低影响文档/样式修改使用相称的检查。
- 保持代码、契约、文档和开发入口一致。长期边界变化时同步更新本文；版本号、提交号和阶段性结果留给实际配置、提交与验证记录。
- 沿用当前任务已经授权的分支、提交和推送方式，避免覆盖并行工作。提交、推送、合并、打 tag 和发布分别处理；不能把分支交付当作已获合并或发布授权。
- 最终说明改了什么、为什么、实际验证了什么及仍未验证的部分，给出对应文件/提交入口。不要把“没有发现问题”写成“全部验收通过”。
