# SDK 验证

文档版本：1.9 · 更新日期：2026-11-23

本目录只负责组织验证的执行与证据。SDK 行为断言保留在各产品的 `Tests`，`run.py` 调度这些测试及已有构建、资源、安全和性能工具，CI 调用同一个入口。固定输入验证不调用模型，也不评测 Agent 或 Skill。

## Tests、Validation 与 CI 的职责

| 位置 | 负责什么 | 维护原则 |
| --- | --- | --- |
| `Tests/SwiftLangTests`、`SwiftOpenUITests`、`SwiftIntelligentUITests` | SDK 语义、组件、交互、布局与生命周期的可执行断言 | 对应产品的行为只有一份测试实现 |
| `Examples/Gallery/Tests` | Gallery 集成、双库完整页面与截图回归 | 真实案例和展示资源留在示例包 |
| `Examples/Gallery/NativeTests` | App 打包资源，以及宿主内的 UIKit 事件、焦点、原生身份、布局和图片像素 | 使用现有 Gallery 的 Unit Test Bundle；必须有真实应用 scene，不在无 App 的 framework runner 中派发控件事件 |
| `Examples/Gallery/UITests` | iPhone App 内的真实点击、输入、滚动、系统访问树和动作回执 | 使用现有 Gallery 的 UI Testing Bundle；固定场景通过公开 SDK 入口渲染 |
| `Tests/ValidationTools` | 验证脚本的错误处理、结果识别和报告汇总测试 | 确认验证工具自身不会错误放行 |
| `Validation/SDK` | 选择检查、调用工具、记录结果、收集证据 | 不再维护一套 case schema、断言清单或测试状态机 |
| `Validation/Performance` | 固定性能工作负载与原始测量 | 由统一入口调用，测量仍归该工具 |
| `.github/workflows/native-sdk.yml` | 提供执行环境、触发任务、上传产物和合并门禁 | 不重复定义测试命令 |

`Validation/api.mjs` / `cli.mjs` 仍是交付给调用方的静态程序校验工具，其职责见 [说明](../README.md)。资源生成器的已有 JavaScript 单测继续归各自工具。下面的领域表只是覆盖索引，真实断言以测试代码为准；执行报告以实际命令及产物为准。

## 统一执行入口

在仓库根目录执行，输出目录必须是新目录或空目录，防止旧日志或截图满足本轮检查：

```sh
python3 Validation/SDK/run.py --list
python3 Validation/SDK/run.py --profile portable --output outputs/verification/sdk-validation/portable
python3 Validation/SDK/run.py --profile security --output outputs/verification/sdk-validation/security
python3 Validation/SDK/run.py --profile macos --output outputs/verification/sdk-validation/macos
python3 Validation/SDK/run.py --profile ios --output outputs/verification/sdk-validation/ios
```

| Profile | 执行范围 | 必要环境 |
| --- | --- | --- |
| `portable` | 模块边界、双库目录/本地化、runner 自身回归、官方语言对照、静态校验、三组呈现资源与公式资源重建 | Python 3.11+、Node 22、npm、可读取 Package.swift 的 Swift 6 工具链；依赖下载网络 |
| `security` | Core、富文本、代码高亮、图标、函数五个锁定依赖图的真实安装与 high/critical 审计 | Python 3.11+、Node 22、npm 与 registry 网络 |
| `macos` | Debug/Release、全量三产品 XCTest、fitting、Gallery、独立消费者、官方契约、语言 ASan、工具构建、两组 Release 性能数据 | macOS、Swift 6；CI 固定 Xcode 26.3 |
| `ios` | 三产品的 iPhone Simulator XCTest、Gallery App 宿主单元测试及 XCUITest、两份覆盖率、最低 iOS 16 编译和 Gallery iOS 编译 | macOS、Xcode 与可用的 iPhone Simulator runtime |
| `all` | 顺序执行上述全部检查 | 同时满足四个 profile 的环境要求 |

`--check` 可重复指定精确检查 ID，与 `--profile` 互斥，适合修改后的局部回归。例如：

```sh
python3 Validation/SDK/run.py --check gallery-tests --check gallery-programs \
  --output outputs/verification/sdk-validation/gallery
```

局部检查成功只说明所选检查通过。完整验收需要四个 profile 的全部 27 项检查；`--list` 只显示配置，不执行也不生成成功结果。`ios.py` 选择实际已安装的 iPhone Simulator，记录 runtime、设备名和 UDID；也可用 `--device-id` 指定已有设备。没有设备、测试发现为空、缺少任一产品实际执行、编译失败或结果格式无法验证都会失败，不能降级为编译成功。

## 报告与验收门禁

每次执行输出 `report.json`、`summary.md`、逐命令日志以及相关截图、契约、覆盖率或性能产物。报告记录实际提交、工作区指纹、操作系统、工具链、完整参数、耗时、退出状态和产物 SHA-256。原生筛选测试先发现用例并要求非空，测试执行还须有真实非零结果；失败、阻塞、超时、取消和未执行分别保留，独立检查仍尽量继续收集证据。

macOS 全量 XCTest 使用独立覆盖率构建目录，导出 SwiftPM 原始 JSON；iOS 分别保存 SDK 与 Gallery App 的 `.xcresult`、Apple 工具输出的 summary/tests 和 `xccov` 原始 JSON。两次执行必须使用同一个已记录的 Simulator。三个 SDK target 均须有真实成功执行；Gallery 结果必须同时包含 App 宿主 Unit Test Bundle 和 UI Test Bundle，宿主单元测试的四个类与 UI 测试的三个类均须成功执行，不能以 skipped 或 expected failure 通过。覆盖率用于发现缺口，不设没有依据的百分比门槛，也不把执行行数解释为语义或视觉正确率。

两平台的完整测试还必须保留表头与正文的字体回归截图。iOS 入口通过 Xcode 的 `TEST_RUNNER_` 约定转发 SDK 快照目录及遥测设置，其他宿主变量不自动增加该前缀。缺图仍判失败，不能仅凭测试命令返回成功替代渲染证据。

iOS 的挂载回归由 `OpenUIGalleryNativeTests` 加载到真实 Gallery App 内，在其 `UIWindowScene` 中创建自己的 `UIWindow` / `UIHostingController`，检查 UIKit 输入、焦点、选区、挂载身份、布局与图片加载像素，结束后恢复之前的 key window。测试等待实际 native view update 或资源呈现，不用预期几何作为就绪条件。无 App 的 framework runner 没有 UIKit 控件事件所需的应用派发器；这些用例因此只编译进 App 宿主测试，不再由根 SwiftPM target 重复发现。

SwiftUI 的虚拟访问树、真实点击与拖动由 `OpenUIGalleryUITests` 执行：OpenUI 覆盖卡片阅读、选择、表单、Slider、分页与系统 sheet；OpenIntelligentUI 覆盖商品图比例、大字阅读、换图和精确购买动作。同步 Slider 草稿 flush 另有 App 宿主单元回归，避免把 XCUITest 自动等待误认为无等待提交的证据。分页分别检查真实页面身份和实际拖动；不扫描 `UIView` 树要求识别器常驻，因为 Apple 的 [UIGestureRecognizerRepresentable](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable) 不保证识别器附着在该层级中，其[创建方法](<https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable/makeuigesturerecognizer(context:)>)也明确按事件序列管理生命周期。

所有 iOS 测试都属于同一个 `ios-native` 检查。Gallery 的两个 bundle 在一次 `xcodebuild test` 中按顺序执行；Debug 使用当前目标架构，使宿主与 SwiftPM 依赖匹配。挂载视图的 layer 截图保存在 `visual/ios-native/ios-native`，真实 App 视口截图保存在 `visual/ios-native/ios-ui` 并附于 Gallery `.xcresult`，不会互相覆盖。共享 Lang 输入为单份纯数据 fixture；Gallery 的固定测试场景只在 Debug iOS 的显式测试启动环境下启用，普通浏览入口不展示这些场景。

[CI](../../.github/workflows/native-sdk.yml) 直接调用同一份 runner。四个 profile 分别上传完整输出目录；原始日志与截图位于 `sdk-validation-<profile>-<run_id>-<attempt>` artifact。最终 `Native SDK acceptance` 下载本次四份产物并调用：

```sh
python3 Validation/SDK/run.py collect \
  --input outputs/verification/sdk-validation-inputs \
  --expected-sha "$(git rev-parse HEAD)" \
  --output outputs/verification/sdk-validation-acceptance
```

汇总要求四个 profile 和全部检查齐全且唯一，提交一致，工作区初始干净且执行期间源码未变，runner 一致，所有检查成功，产物存在且哈希匹配。任何缺失、重复、改写、失败、取消或 skipped job 都不能通过。下载时保留每份 `report.json` 与其输出目录的相对布局；汇总执行报告保存在 `sdk-acceptance-<run_id>-<attempt>` artifact。最终检查还须由仓库设置为 required check，才能由分支保护强制阻止合并。

## 覆盖索引

| 领域 | 固定验证内容 | 实现与证据 |
| --- | --- | --- |
| 运行时 | 语法、Schema、Store、Query、执行预算、异常与恢复 | [SwiftLangTests](../../Tests/SwiftLangTests)、官方语言对照、ASan |
| 流式 | Unicode、终态完整性、readiness、绑定、动作、换源和迟到回调 | 共享层与双库测试、[Gallery 终态比较](../../Examples/Gallery/Sources/GalleryValidation.swift)、Push 分布 |
| 组件 | 注册目录、位置参数、固定交互、媒体生命周期 | [OpenUI 测试](../../Tests/SwiftOpenUITests)、[OpenIntelligentUI 测试](../../Tests/SwiftIntelligentUITests)、三个独立消费者 |
| 布局 | proposal、有限几何、fitting、嵌套、RTL、字号、窗口变化 | 两库几何断言、原生挂载与 Gallery 全页画面 |
| 视觉 | 语义字体、颜色与间距、整页内容、深浅色 | 两库截图、实际访问树、逐图审查 |
| 性能 | 固定语言与公开 State 负载的 P50/P95/Max、RSS、发布次数 | [Release 性能工具](../Performance/README.md)原始 JSON；真机滚动另用 Instruments |

共享层、OpenUI、OpenIntelligentUI 分别由根的三个 XCTest target 执行；iOS 与 macOS 的平台条件用例不同，实际数量以各平台发现及结果为准。三个独立消费者分别只引入一个公开产品，验证真实外部接入与资源。

Gallery 配置遍历两库现有 225 份固定程序，执行完整求值和三种分片下的终态比较。终态同时比较内容、属性、动作、绑定和 Store 默认值；另有小型程序在每个 Unicode scalar 边界的回归和语义漂移反例。完整执行应得到 225 次 batch 与 675 次 streamed，实际结果写入日志。

两库的 heat-pump / code-isolation 整页截图采用相同 320/390pt、Light/Dark 条件，加辅助字号环境与原有图片行，共配置 22 张；原始内容和来源保留，未打包的图片请求明确失败。具体捕获规则见 [Gallery](../../Examples/Gallery/README.md)。这些是 macOS 画面，iOS 测试通过不意味着 iPhone/iPad 全页视觉已验收。

## 自动检查之外的验收

执行报告只说明实际检查结果。以下目标需要独立证据：

- 杂志感、主次、留白、图文适配、阅读舒适度以及批准的像素基线，需要查看实际截图并记录审查结论。
- iPhone/iPad 全页辅助字号、RTL、分屏、触摸、软键盘和 VoiceOver，需要按设备与场景验证。
- 真机长消息、连续滚动、帧时间、CPU、内存持有链，需要相同设备和构建的原始 Instruments trace；Simulator 测试和语言性能数据不能替代。
- 跨提交性能比较需要相同设备、工具链、配置和负载；CI host 的单次结果不直接作为设备性能回归阈值。

这些未完成目标写在本说明中，不另建带 `planned` / `existing` 状态的“验证用例”。新增可自动判断的行为，直接在所属产品或 Gallery 的测试中补充断言；需要新执行环境或独立工具时才扩展 runner。确认一个改动时先运行相关测试，完整 SDK 验收运行四个 profile。

App 宿主挂载测试验证 UIKit 编辑事件、焦点、选区和绑定；Gallery XCUITest 另外执行所列场景的真实 Simulator 点击、输入、翻页与纵向滚动。它们不代表所有真机、系统版本或输入法已经验收。分页连续压力操作、边缘手势竞争和 VoiceOver 朗读仍需独立设备交互证据。

全部实际证据保存在忽略的 `outputs/verification`。SDK 的 spec、Prompt、示例及 reader/writer 能力仍保留。固定生成契约与历史程序回归不代表模型生成成功率。以后设计模型、Agent 或 Skill 的 benchmark 时另行建立相应评测。

[静态校验](../README.md) 使用调用方提供的匹配契约；[ContractExport](../../Tools/ContractExport/README.md) 专用于 OpenIntelligentUI。Gallery 的两库 reader JSON 仍是其自身导出格式，不等同于静态文件入口要求的四文件契约包。
