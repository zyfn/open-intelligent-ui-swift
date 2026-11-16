# Agent 工作约定

文档版本：1.1 · 更新日期：2026-11-16

本文件适用于整个仓库。用户当前明确要求优先。保留已有未提交工作，先检查当前分支与 git status；不要依据旧会话重复迁移或覆盖已有项目。

## 阅读入口

- [架构](docs/architecture.md)：唯一的包名、目录、职责、依赖与运行链路定义。开始跨模块任务前读取；不要在本文件或其他文档复制一套架构。
- [README](README.md)：安装与公共接入。
- [OpenUI](docs/openui.md)、[OpenIntelligentUI](docs/openintelligentui.md)：组件、契约与本库设计。
- [验证说明](docs/validation-and-security.md)、[CI](.github/workflows/native-sdk.yml)：构建、资源、安全和验收。
- [Gallery](Examples/Gallery/README.md)：双库原生调试、案例与命令行。

## 文档维护

- 设计以本 SDK 的目标、职责、行为契约、实现状态和验收标准组织。外部实现用于借鉴，设计正文不展开外部框架对比；依赖来源、版本、许可和兼容性证据仍维护在既有来源清单与验证说明中。
- 同一主题只维护已有的权威文档。OpenUI 的设计、组件呈现和实现状态直接更新 `docs/openui.md`；先查现有入口，再原位编辑，不另建设计方案、执行说明或摘要副本。
- 修改已有文档时更新文件头的文档版本和日期；未标版本的文件首次维护时建立版本字段。文档版本独立于 SDK 包版本和 Lang 协议版本，不为文档修订修改产品版本。
- 不生成带 `v2`、`new`、`final`、日期或“最终版”等后缀的并行文档。历史修订由 Git 保存；已有外部计划被并入仓库后只保留指向权威文件的入口，不再独立维护正文。
- 工作规则写在本文件，具体设计写在所属组件指南，目录职责写在架构文档；通过链接关联，避免复制多份规范。实现状态、未完成项与验收限制在所属文档原位更新，实际日志与截图放 `outputs/`。

## 实现约束

- 唯一公开模块为 SwiftLang、SwiftOpenUI、SwiftIntelligentUI；库产品为 swift-lang、swift-ui、swift-intelligent-ui。新代码遵守架构中的能力边界；不新增旧名兼容壳、状态别名、平行运行引擎或另一份权威 schema。
- 两套 UI 的状态、Context、渲染和通用机制使用 SwiftLang。组件视觉与特有行为留在对应 UI；模型、工具通信及业务结果由宿主负责。
- 不在 body、拟合或布局测量中创建 state、重复提交源码或写业务状态。保留节点身份、用户编辑与文档 epoch，拒绝旧异步结果回填。
- 组件名、参数顺序、枚举和绑定属于输入契约。调整 Swift API 或视觉时不顺手修改 Lang 契约；reader/writer 与实际注册源保持一致。
- 原始模型输出和历史 fixture 保留原样。不得通过删断言、改预期、跳过检查或放宽校验来掩盖差异；上游语义变化必须有独立依据。
- JS、目录、公式、字体等生成资源通过所属工具维护，同步 manifest、锁文件、哈希和许可。运行时不下载脚本。
- 不恢复嵌套 SDK、旧目录软链接、重复 Demo、过时迁移脚本或历史报告集合。新增源码/资源/测试按架构归属，不把 Gallery 素材和模拟服务放进 SDK。
- Gallery 使用 OpenUI / OpenIntelligentUI 名称，左侧整体切换，场景与组件库分开。组件用法默认展开，场景保留完整内容与阅读层次。
- 地图的筛选、内部点位卡片、选点、全览和展开属于组件；不能靠场景补齐组件能力。视觉遵循所属库 token，不为单个案例增加私有 Lang 参数。
- 需要真实 Agent 后端与客户端示例时建立独立集成项目；任务未要求时不创建空工程。凭据、用户状态和真实业务数据不进入 fixtures。

## 按范围验证

| 改动 | 入口 |
| --- | --- |
| 文档、路径 | git diff --check；检查本地链接、目录引用与消费者 |
| 包、模块或公开 API | python3 Tools/check_module_boundaries.py；python3 Tools/check_openui_integration.py；python3 Tools/check_product_consumers.py --scratch-root /tmp/openui-consumers |
| SDK 行为 | 对应 XCTest；交付前 swift test |
| 宿主观察、流式、尺寸拟合 | 对应运行时回归；Release 的 HostSizingIsolationTests 与 RuntimeHostIsolationTests |
| Gallery、组件契约、本地化或语言资源 | 使用验证说明和 CI 中对应的现有入口；涉及交互时打开原生 App 实测 |

不要为纯文档改动新增无关测试或启动全量评测。检查失败先定位原因，保留真实失败与未执行项，不用静态脚本冒充 Swift 构建或界面验收。

## 交付

- 已授权且必要的工作直接完成；保持最小可解释范围，不顺手添加无关功能、架构或配置框架。
- 只维护一份架构。变更长期边界时同步该文档与真实检查，不新增需求/设计/迁移报告来重复描述；具体执行证据放忽略的 outputs。
- 性能、真实模型与网络行为只报告实际测得的结果。Gallery 本地动作不等于提交、交易或远程业务成功。
- 提交、推送、合并、打 tag、发布分别取得相应授权；本地完成不表示获准发布。
- 最终说明实际变化、验证结果与限制，绑定真实目录和日志，不将测试配置写成已验收结果。
