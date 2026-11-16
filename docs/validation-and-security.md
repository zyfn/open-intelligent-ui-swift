# 验证与依赖安全

文档版本：1.3 · 更新日期：2026-11-16

本文说明当前 SDK 的可复现输入、依赖安全和原生验收范围。具体提交的执行结果以 [Native SDK 流水线](../.github/workflows/native-sdk.yml) 的日志为准。当前生成输入由 [Tools/upstream.json](../Tools/upstream.json) 固定，完整上游许可保存在随 SDK 打包的 [THIRD-PARTY-NOTICES.txt](../Sources/SwiftLang/Resources/THIRD-PARTY-NOTICES.txt)。

## 1. 实际打包依赖与可复现生成

| 依赖 | 当前固定版本 | 修复与验证 |
|---|---|---|
| 官方语言核心 `@openuidev/lang-core` | `1.1.1` | 固定官方源码提交、原始/适配后源码树及实际 JavaScriptCore bundle；执行新版本语言行为与原生桥接回归 |
| Zod | `4.6.7` | 修复约束集合校验的内存耗尽问题；保留既有 schema 导出与原生 record 契约，重新生成语言 bundle、manifest 与 oracle 构建指纹 |
| KaTeX | `0.18.2` | 修复从原型继承信任选项的问题；更新标准富文本与 Intelligent UI 实际使用的公式资源 |

官方安全公告分别为 [GHSA-mrhx-c7xc-m3w5](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5) 和 [GHSA-238p-pmpm-9mq7](https://github.com/advisories/GHSA-238p-pmpm-9mq7)。后一个问题依赖于已有原型污染；修复后的依赖不再把继承的选项视为应用主动启用信任。

Zod 与 KaTeX 更新使用 npm 提供的真实 tarball 与 integrity，锁文件固定构建图。标准富文本中直接和传递的 KaTeX 使用相同的精确版本。Intelligent UI 的 MathML 引擎也由受审计的生成工具维护，避免只更新 npm 依赖而遗留旧的运行时文件。

当前 SDK 的语言上游升级为 `@openuidev/lang-core` 1.1.1，固定官方源码提交 `39a4e3f6493673fdf2de04681240374c8d6f6be8`。构建从该版本源码生成随 SDK 打包的 JavaScriptCore 资源，并记录 Apple 平台桥接、兼容补丁与执行预算；客户端不运行时下载脚本，也不自动跟随 `latest`。实际提交、源码树与资源哈希以 [upstream.json](../Tools/upstream.json) 和 [core-manifest.json](../Sources/SwiftLang/Resources/core-manifest.json) 为准。

语言升级的回归需要覆盖新上游的表达式状态、列表/数学函数、查询依赖与重试、流式解析及动作/序列化行为。与官方版本同步产生的语义变化应有对应的上游依据和专门用例，不能仅更新 fixture 来掩盖原生桥接差异。组件目录和设计系统的变更独立于语言版本；原生契约检查仍对照固定的历史 Intelligent UI 基线，完整比较组件顺序、位置参数和 schema。

Zod 4.6.7 的 JSON Schema 导出新增了把纯标量 `anyOf` 合并成 `type` 数组的优化。两种写法表达相同类型集合，但本 SDK 保留既有导出契约，因此在现有构建兼容层中仅禁用该导出压缩步骤。共享适配同时用于原生 bundle 和官方组件目录生成，严格校验 Zod 版本、源文件 SHA-256、唯一匹配的替换片段及变换后 SHA-256；清单中的 `dependencyTransforms` 记录这些证据。Zod 的解析、校验和修复后的集合限制不受此导出适配影响。

Zod 的 JSON Schema 导入也把简单字符串键 record 包装为带校验的 pipe，固定 Lang 核心无法由该表示还原历史 record 签名。现有 authoring 桥接只对没有显式字段、patternProperties、属性数量或键名约束的简单 record 恢复新版 `z.record` 表示，并保留原来的字符串键检查、元数据、默认值和绑定身份。带额外约束的对象继续使用完整的新版 guard.pipe，保留预解析检查。

组件目录继续与原已提交文件逐字一致，不刷新 schema 期望来接受漂移。回归直接执行实际打包的 `nativeAuthoring`，比较全部 84 个组件、304 个参数和完整签名，覆盖联合分支顺序、nullable、类型数组输入、默认值、约束、嵌套、参数顺序及历史 parser 结果。另通过真实桥接的 `props.safeParse` 执行对象大小、键名、固定字段、额外属性类型和 patternProperties 的正反校验，验证安全检查实际生效。

标准富文本生成器继续嵌入字体，运行时不加载外部 CSS 或字体。Intelligent UI 继续输出 MathML，保留原来的 `trust: false`、严格语法、展开次数和输出大小限制。公式安全回归在隔离的 JavaScript 上下文中验证原型污染不能开启受信任渲染，并覆盖有效公式与非法输入。

当前资源版本与内容哈希由各资源 manifest 记录。生成器运行后，CI 要求资源与当前提交逐字一致；它不再要求后续安全修复继续等于原始导入的旧哈希。

## 2. 验收范围

流水线按当前 SDK 分成三项检查：可复现输入、依赖安全和原生验收。可复现输入检查重建实际打包资源并运行语言、authoring 和组件目录回归；安全审计覆盖 Core、标准富文本、代码高亮、图标和 Intelligent 函数五个生成工具依赖图，使用 `--audit-level=high` 门槛。原生验收构建并测试根 SDK 及其公开产品消费者。

原生验收覆盖 SwiftLang、OpenUI、OpenIntelligentUI 三个独立产品消费者。每个外部包只声明一个产品，验证打包资源、authoring、解析、流式、生成契约、原生宿主和状态读写；不启动窗口，不能代替 UI 视觉验收。模块检查禁止适配层导入两套组件库、任一 UI 导入另一套库；适配层内部 Language 目录不导入 UI 框架，Runtime 目录承接 SwiftUI。

其余原生验收覆盖全部原生测试、Release fitting、独立 Gallery 测试与双库案例完整/流式验证、完整历史契约、语言 ASan、独立契约/性能工具及 iOS 编译。独立检查在前一个检查失败后仍可收集证据，但任何检查失败都会保留为任务失败。消费者源码生成或语法检查不等于实际 Swift 编译通过；原生编译与测试结果以对应提交的执行日志为准。

这些记录用于验证当前分支的实现与构建；真机交互、产品发布和合并仍是独立的交付动作。

## 3. 语言版本与验证边界

包、目录与职责只见[架构](architecture.md)。当前运行官方 lang-core 1.1.1；docs/language 的 1.0 规范与 Fixtures/Language/1.0 是保留的参考输入，不是另一条运行路径。模型输入使用所选库当前导出的 Prompt/spec。

| 相对 1.0 参考的差异 | 1.1.1 行为 |
| --- | --- |
| Query 依赖 | 跟踪普通语句和别名中的状态/查询依赖，等待上游查询结果后再执行 |
| Query 失败与环 | 相同输入不自动重试失败；显式 Run 或失效操作可重试；依赖环报告 query-cycle，不派发工具 |
| 状态默认值 | 可由表达式计算初值；初始化后不因被引用状态改变而自动成为派生公式 |
| 数学函数 | Round、Abs、Floor、Ceil 也支持逐元素处理数组 |
| 诊断 | source 可以缺省，Swift 保留其真实存在性，不补造 parser 来源 |

当前 306 例参考由固定的未修改官方源码独立生成，保留原始输入与案例 ID。与旧参考的 33 个输出差异有独立记录；旧文件只用于审计，不作为备用运行实现。严格检查必须比较协议字段、顺序和诊断可选字段，不得通过排序、丢弃错误或覆写历史预期消除差异。

语言与资源修改在 SDK 根目录执行：

~~~sh
npm ci --prefix Tools/Core --ignore-scripts
node Tools/Core/build.mjs
node Tools/Core/verify-compatibility.mjs
node --test Tools/Core/native-*.test.mjs
swift test
~~~

离线构建可用 OPENUI_UPSTREAM_GIT 指向预取仓库；仍校验固定提交和源码树，不信任任意本地修改。生成 JS、manifest 与适配清单必须同源。对照器独立构建未应用 Swift patch/readiness 注入的官方内核，并执行官方 React 动作回调。对照覆盖完整/截断/中间流式快照、动作与工具结果、Query 替换与晚到结果、1.1.1 专项及 serializer round-trip；Swift 测试另外覆盖真实 native callbacks 和文档生命周期。生成 fixture 不能代替运行这些检查。

readiness 通过 parser-owned Symbols、基础 WeakMaps 与单次求值的 snapshot WeakMaps 记录源边界和依赖；这些元数据不进入 Lang 值和序列化 AST。共享原生容器的临时未就绪标记和 Query 归属不能污染另一次求值。Swift 投影读取对应 snapshot，必要时重建带元数据的不可变路径，并保留原 JS 身份与反向编码关系。仅具名的原生元数据可在官方协议比较中排除。必须用原生交互测试验证完整控件可用、未完成动作不可执行、文档替换后旧回调失效。

未闭合 `Each` 的 readiness 失效标记按对象身份去重，防止同一共享数组在最终输出预算检查前被反复扫描。这一步只减少幂等标记的重复工作，输出预算仍按每次出现累计，不改变值、引用身份、控件就绪规则和超限拒绝。对应回归对实际数组访问次数计数：500 个结果共享同一个 500 项数组时，失效遍历由 250,000 次子项访问降至 500 次，两种情况下最终输出仍被原预算拒绝。

2026-11-16 本轮该修正已通过正式资源重建、33 项 native JavaScript 回归和独立官方内核对照（无未解释差异）；另外 480 组普通分块、24 组封包分块的终态值/声明/公开 meta/预算结果一致。这些结果不覆盖所有中间帧，也不能替代 Swift 桥接、原生交互和设备帧率验收；对应证据保存在忽略的 `outputs/audit-lang-2ae6ced/`。

原生数据桥接使用私有对象身份区分真实 ActionPlan 与含 `steps` 字段的业务对象。静态和动态业务对象保留其字段；宿主显式构造的原生 plan 可直接用作 action prop，显式 `Action(...)` 组合仍保留官方 `ownSteps` 对自定义动作的来源检查。此数据修复、表单校验器仅查自身键的修复以及下列预算均列在适配清单中，不通过修改历史 fixture 隐藏与固定官方核心的边缘差异。单键 Store 读取仅检查该键并读取其值，保留键不存在与显式 `undefined` 的区别。

完整消息的 `push`、`set` 和批量解析使用同一官方消息提取规则；重试帧选择最后一个 content。普通 Lang 分块保留增量路径，协议标记跨分块时由原生输入适配保留边界，不引入另一份语言 parser。替换 Mutation 时，原生 Task 与等待中的 Promise 按声明实例一起取消；即使宿主 provider 忽略取消，等待动作也能结束，其他 Query 不受该局部取消影响。

serializer 修复后的程序须由未修改的官方 parser 接受，并保留求值意义；不能将其输出拼写变化描述为逐字等价。standalone patch 必须与实际构建变换一致。

| 原生预算 | 边界及超限结果 |
| --- | --- |
| 源码 | 1,048,576 UTF-16 units；100,000 tokens；4,096 statements；单表达式 128 层嵌套或 256 个运算符；超限为 parse-exception，最后有效前缀只读 |
| Materialization | 256 层 / 100,000 工作单位；整批状态默认值共用余额，超限为 parse-exception，并在投影状态默认值和根节点前将私有失败标记传给 Swift |
| 动态求值 | 每个同步求值范围 100,000 工作单位、256 层；涵盖递归求值、Each 展开和内建函数工作量；Query 批次共用余额，超限立即停止 |
| 输出与渲染 | 展开后的值最多 100,000 节点、256 层、4,096 个组件实例及 1,048,576 UTF-16 units；共享子树每次出现都累计成本，以缓存和饱和计数避免检查本身指数展开 |
| 有序 JSON 解码 | 128 层；超限为原生 JSON 错误，JSON 语法仍由 JavaScriptCore 校验 |
| 正则 | 65,536 pattern units、1,048,576 input units，限制内存、栈与 VM；资源耗尽阻止表单提交，普通不匹配与非法表达式保持各自语义 |
| 原生值转换 | 保留 256 层防御检查；更深传输不在已验证的等价范围内 |

预算之外不宣称与 stock core 等价。有限 fixtures 通过也不证明任意程序、后续版本、所有设备或网络时序正确。新差异必须解释或修复，再决定是否有依据增加新的版本预期。

真实流式性能与重复拟合分开验收。当前 `OpenUIState` 在 MainActor 上同步执行每次 push 的解析、根求值和 live-element 索引；公共 host 与组件 host 订阅同一个状态。`RuntimeHostIsolationTests` 与 `HostSizingIsolationTests` 中重复提交相同源码和尺寸拟合的检查，只证明该路径不重复解析、发布或重挂，不能证明真实尾部增量不会刷新无关组件。局部刷新与每帧耗时需要在目标设备的 Release 构建中，另测不同内容规模和分块频率下的解析、桥接、求值、组件 body 与布局成本；没有运行证据时不宣称该观察路径已经收敛。

任一物化、求值或输出预算失败后，OpenUIState 保留最近一次通过预算的已显示内容，停止当前文档的动作、Query 和 Mutation；不能把失败产生的 `null` 继续写入状态或作为工具参数。替换源码或 reset 可以恢复。预算用于限制异常工作量，并非每帧耗时或设备帧率保证；原生不卡顿仍需在目标设备 Release 构建上测量。

原生控件验收还包括：EditableTable 的本地提交不得代表远程持久化；被拒绝的草稿不能随 Store 发布而提交；替换文档建立新草稿生命周期。Slider 的离散选择同时考虑 minimum 和 step 精度，非整除范围允许拖到最大值，连续文本仍按范围校验。对应控件测试与真实窗口检查各自报告。

## 4. 内核稳定性审查与当前验收状态

前一轮以 `9e05d888ef31cfff6eb8c75f3ca01ed089ec3e78` 为基线完成下表修复，已通过 `bdac1bfd03bf19df527681517b2f3c3aee19a368` 合入 main。本次剩余问题评估核对的 main 仍是该提交，源码树为 `786a43155949e57ada4ea8bd898d381ab17420c3`。设计约束见[架构](architecture.md#内核必须保持的约束)，依赖版本及兼容性检查仍按第 3 节记录。以下区分已执行的 JS 证据、确定的源码路径、用户提供的客户端验收和仍未执行的原生验证；合并不代表这些验收已经通过。

| 问题 | 触发与依据 | 本轮处理及验证层级 |
| --- | --- | --- |
| 隐式转换逃逸工作量预算 | 约 6 KB 程序用共享数组做 `==` 或动作字符串参数，最终值很小但中间发生大规模遍历；500 项探针实际读取 250,500 次，旧预算仅报告 1,506 工作单位 | 转换前测量并累计成本，覆盖比较、索引、拼接、动作及 Filter/Sort 内重复转换；新增回归中 8 项在旧资源失败，修复后通过；1,053 个小输入与独立官方核心对照无差异 |
| readiness 跨文档污染与容器缓存过期 | 不完整 Each 在共享对象上留下未就绪/Query 标记；完整文档仍读到旧标记，而 Swift 命中父容器缓存又可能跳过后代变化 | 改为单次求值 snapshot 与显式原生投影；保留旧快照和 JS 身份。3 项新 JS 回归旧资源全失败、修复后全通过；真实 Swift 缓存/交互回归已加入，待原生运行 |
| 原生对象字段整理为平方级 | 每插入一个键线性扫描已存在字段，10,000 个不同字段固定发生 49,995,000 次键比较；这在 JS 求值预算之外 | 以精确 UTF-16 哈希键保存首次位置/最后值，整数键只解析一次后排序；新增顺序、重复键、Unicode、JS own-property 对照及宽对象回归，待原生运行 |
| 当前匿名节点重复搜索整个桶 | 不完整 Each 生成同类型、无 statementId 的控件，当前树的 1,000 个节点按旧逻辑需 1,000,000 次候选比较 | 当前对象身份 membership 直接返回，旧快照仍保留原有消歧；JS 输出及工作量计数可复现，原生快径与消歧回归待运行。旧快照的大桶搜索风险仍需测量 |
| 同步发布回调重入造成旧轮覆盖或重复通知 | `@Published` 在 willSet 同步调用订阅者；订阅者换源后旧 setter 和后续渠道仍可继续写入。onError 恢复也可能使外层再通知内层的解析结果 | 同步重入顺序执行、过期轮终止，并在执行排队的控件写入时再检查 revision；新增替换、同代状态写入、no-op 重放、连续命令和旧 Context 回归，待原生运行 |
| 异步 Query 返回后先派发再验根预算 | 现有依赖调度先从 rows 自动派发参数很小的下游工具，随后 root 的多层 Each 才超限；不能只检查 Query 参数 | 在原生自动派发进入 provider 前复检当前文档、完整性与呈现预算；增加原生时序回归，待运行。JS 探针证明调度次序，不冒称已执行 Swift Task race |
| 排队的旧 Query 仍可进入 provider | 等待 MainActor 检查期间 patch 改变或删除 Query，此前只在结果回来后判断旧 key；首次批次还可能在同步发布回调换源前开始调用 | 所有 Query 等待当前同步发布结束，已检查批次只复核存活状态，不再次算 root；进入 provider 前核对 Query 实例及请求 key，保留同 key 请求，拒绝删除后同名同 key 重建的旧请求。私有 hook 与原生时序回归分别验证 |
| 原生输入先编码后检查 | 工具返回值、纯函数返回、宿主状态/引用和原生 AST capture 可在进入 JS 预算之前递归编码；初始/恢复状态也可先进入 Store | 加入 Value、AST 与整批状态图预检，按共享子树每次出现累计成本，用 memo 和共享检查额度限制预检本身；上下文使用有限弱引用缓存避免重复扫描。失败中止当前 JS 预算、结束工具等待，并保留旧 Store/呈现，不能提交 `null` 或部分恢复。原生回归待运行 |

本轮正式生成资源已执行 **84/84** 项 `Tools/Core/native-*.test.mjs`，覆盖 26 个分块不变量案例的 **2,123 个中间前缀**及其末态；比较公开值、声明、诊断与私有 readiness。增量 push 与同前缀 fresh set 一致，这是分片不变量检查，不是独立官方 oracle。独立官方检查另执行 51 项 parser、5 项动作、4 项 Query、6 项 round-trip、21 项 Lang 1.1 专项，未发现未解释差异；额外 1,053 项隐式转换对照也无差异。新加入的 6 项原生输入失败 JS 回归在旧资源均失败，当前通过；5 项 Query 请求有效性回归覆盖变参、删除、保留、删除后重建与 dispose。未修改历史 fixture 预期。

上述修复新增 54 项 XCTest，原生测试、Release 宿主测试和新基准尚未在本审查环境执行：当前环境缺少 Swift/Xcode，`swift test` 实际返回 `swift: command not found`；完整 SwiftPM 模块图检查也被同一条件阻塞。已回读合并提交的 [CI run 43809174570](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/43809174570)：reproducible-inputs 与 dependency-security 为 failure，runner 与 steps 为空；native-sdk 为 skipped。没有原生测试执行结果可作为本提交通过证据。源码归属、生成资源和 JS 检查分别报告。原修复日志保存在忽略的 `outputs/kernel-audit-9e05d88/`，不另建并行设计或审查文档。

### 当前 main 的剩余问题

本次重新评估只更新工作规则与本验证文档，没有修改生产源码或把下列事项标为已修复。JS 探针使用当前实际分发的 `lang-core.js`，SHA-256 为 `b84833a91b9f63589c9093cf12d374d24280a0a0f1c438007396b36eda3dba73`。原生代码的确定控制流与真实 Swift 执行结果仍需分开。

**客户端已有失败。** 用户提供的 2026-11-16 记录使用 SDK `9e05d888`，不是合并后的 `bdac1bfd`；原始 Mac 日志、录像和 xcresult 尚未取得。以下保留用户报告的结果，不冒称在本环境复现，也不以本次内核合并自动关闭这些失败。

| 验收项 | 已有证据与当前结论 |
| --- | --- |
| 流中文字长期停在半句 | 行程文字在输入早期及数据层已完整，画面约 18–54 秒仍显示截断，约 57 秒才补齐；酒店、表单也有类似观察。显示更新链路尚未定位到 Host 或 SDK 的具体断点。必须在 done 之前验证真实可见文本 |
| SDK 原生回归 | 用户报告 870 项中 10 个失败用例、24 条失败断言；涉及选项列宽、按钮身份、物化预算、Gallery 高度、mutation 退休、焦点、紧凑图表及三项 signed media。需要完整 testcase 和第一条 expected/actual；不能全部解释为生产缺陷或测试过时 |
| signed media 与 SVG | 三项 signed media 测试使用内存 PNG 和确定性 loader，不能用 App proxy HTTPError 解释。SVG 打开/缩放通过，拖动像素断言失败且归因未定；图像预览正常不等于 SVG 拖动通过 |
| 流中表单选择 | 复杂表单的自动点击实际发生在 done 后，流中选择跨完成状态保留仍未验收；小型状态测试不能替代此场景 |
| 性能 | 同一行程的一次 Debug 样本由旧版本平均 98.81% CPU / 峰值 220.58 MiB，变为 9e05 的 89.95% / 226.96 MiB；分片配置相同、实际传输时长不同。单样本不能证明改善或泄漏，未取得当前 main 的 Release、真机、FPS、有效 Instruments 或 memgraph 证据 |
| App 与后端阻塞 | Release 在 App 的 TaskBrowserSession.performRefresh 遇 Swift 编译器内部错误；真实模型链路受 sandbox initialize 的 fixed_sandbox_missing 阻塞。两项应独立跟进，不据此归因 SDK parser |

**新增的具体正确性与接入缺口。** 下表的源码定位均对应本次核对的 main。缺少原生执行的项目仍需原生最小回归，不把源码推导冒充已发生的 App 事故。

| 问题与证据层级 | 触发、影响及代码入口 | 处理与验收要求 |
| --- | --- | --- |
| 增量写入与状态恢复的预算范围不一致：源码确定，JS Store 探针通过 | `OpenUIState.setStateNow` 只检查本次 Value；`update` 只对待恢复 persistedState 做整批检查。两次写入各 60,001 节点的合法数组可留下 120,003 节点快照，恢复却被 100,000 节点上限拒绝。现有 StateInputBudgetTests 已有同样的整批超限数据，缺增量写入后的往返验证 | 以提交后的文档状态为统一预算范围，在写入前检查字段替换后的总成本；边界内 snapshot 必须可恢复，超限写入不能先污染 Store。避免每次写入全量重扫 |
| Action 的调用方取消未接入执行器：源码确定 | `Actions.runActionPlan` 只检查 context.isActive；State 提供的判定只看 generation。`QueryManager.runMutation` 使用 continuation，没有调用方取消处理，provider 在独立 Task。取消外层 action Task 而不换源时，等待不会因此结束，成功返回后剩余步骤仍可能执行 | 定义 action/request 级取消，SDK 等待者有界退出，迟到结果不能继续 Set 或发送事件；取消一个 action 不影响其他 Query。外部 provider 不配合取消不能成为 SDK 等待不退出的理由 |
| 共享原生值在同一次求值不同出现位置的 readiness 相互影响：实际 JS bundle 复现 | `Tools/Core/readiness.ts` 的 snapshot WeakMaps 仍按对象身份存储。实际探针通过 JS getState 注入经 tagNativeSource 标记的共享 Button/Action 值图，并分别用于直接分支和未完成 Each；直接分支也会读到 incomplete，不共享的同值对照正常、Each 闭合后恢复。Swift 注入与函数返回入口仍待原生复验 | 位置相关 presentation metadata 与 Lang 对象身份分离，保留 SameValue。此问题限定于复用同一原生值图；纯 Lang Button/Action 别名的 5 类、10 个 pending/closed 用例没有复现，不能扩大为普通变量复用错误 |
| complete 父元素仍可能持有旧的 incomplete Action：源码确定，原生未运行 | `ComponentHost.body` 与 `OpenUIState.isElementReady` 仅在元素自身 incomplete 时刷新 live element；父元素 complete、内部 plan incomplete 的旧 Context 会持续检查旧 plan。context.perform 先被 canInteract 拦截，尚未进入 currentActionPlan 的刷新保护 | 用当前 projection membership 或明确的 presentation revision 判断是否需要刷新；保留旧 Context，完成依赖后，在同一 sourceRevision 下交互应与新 Context 一致，不依赖重挂载 |
| 标准 Stack/Card 漏传组件身份规则：源码确定 | `StandardContainers.swift` 的 OpenUIStack.children 调用 children(of:) 时没有传 context.registry。扩展组件的 identityFields 在此退回 key/id/resourceId；稳定业务 key 加服务端 id 更新可能重挂载，没有默认 id 时重排可能按位置复用状态 | 标准容器使用实际 registry；把 ProbeOption 真正挂入 Stack/Card，检查重排、无关 id 改变、局部状态和焦点。现有 RegistryIdentityTests 只直接调用带 registry 的 helper，未覆盖此入口 |
| 部分公开底层输入在预算前编码：源码确定 | `CoreStore.set/initialize`、改写 ParseResult 后的 Evaluator.evaluateRoot fallback、手工 Query AST 的 evaluateStatements 先进入 core.encode/materialized/ast；常用 wrapper 的预检没有覆盖这些原生调用路径 | 在实际公开编码边界有界拒绝深/宽输入并明确失败；不泛化成普通 parser 输出都能绕过。高低层对同一输入的预算与恢复契约应一致 |
| 裸 push 无法识别旧流迟到分块：已知接入契约缺口 | `pushNow` 在 isComplete 时 reset 并开启新流。若宿主把旧请求 A 的迟到块送给已完成 B 的同一 State，B 会被重置；字符串本身不含流身份 | 保留既有裸 push 兼容行为，按架构提供带文档句柄的入口；旧句柄在完成、停止或替换后不能改变新 root、Store、草稿或资源。现有入口要求宿主自行屏蔽旧回调 |

“Mutation 参数函数同步换源后可能派发旧调用”没有列为正常输入缺陷：现行语言契约要求自定义函数纯且同步，不得修改状态。此类违反契约的宿主重入可作为防御核验，不与普通纯函数执行混淆。

**媒体与规模问题。** 两套 UI 的图片实现分别审查，不能把一套的恢复机制视为另一套也已具备；下表属于源码确定的触发路径，未取得原生请求/清晰度/内存测量。

| 问题 | 当前机制与用户可见影响 | 最小验收 |
| --- | --- | --- |
| Gallery 预览按全图库挂载与测量 | NativeGalleryPreview 将所有图片传入非惰性 NativePager；缩略条也是普通 HStack。离屏页的 phase 和父 pictures 字典继续持有 Image，32 MiB / 8 项共享缓存上限不能限制这些引用；正文 previewLimit=5 不限制预览工作量 | 较多不同图片打开预览时，只为当前页及受限邻页启动/保留资源；记录实际请求、解码、挂载与布局次数，关闭后检查释放。缓存 cost 不能单独作为总内存证据 |
| OpenUI 大图预览复用并锁定首个缩略图 | NativeSingleImagePreview 传 cachedImage 后，NativeRemoteImage 加载任务直接返回；Gallery pictures[key] 只接收首次 Image，后来的高分辨率结果不替换。缩放只做 scaleEffect | 先加载小缩略图再打开大预览，验证最终显示像素升级；再用低清先到/高清后到的受控 loader，不能仅断言 loaded 或总请求为 1 |
| IntelligentUI 预览跨尺寸档重新签名 | ImagePreview 每个 pixelTarget task 新建 ImageResource；nonce 签名进入缓存 key。2560/4096 两档即使都被宿主 cap 截成相同有效像素，也可能反复签名下载；正文 SourceImage 已有 snapshot，预览未沿用 | nonce loader 下往返缩放，稳定 source/owner/retry 沿用请求快照；以 cap 后的有效像素作为升级依据，避免相同解码尺寸重复请求 |
| OpenUI 远程 SVG 缺同源恢复入口 | task 只按 remoteTarget 变化重启，失败后只有说明，没有 retry attempt 或组件内操作。网络恢复但 source/owner 不变时，保持挂载的节点不能主动重试 | 第一次失败、第二次返回合法 SVG 的 loader；同一节点、同一 source 下用户触发一次新尝试并恢复。此项与 SVG 拖动像素失败不同 |

**验证补齐顺序。** 先固定当前 revision 与真实回放，补“目标字段早已完整、其他节点继续生成时，done 前画面必须更新”的原生挂载用例；同时比较直接 Text 与 Markdown 路径，并记录输入/投影/发布/buffer/prepared/可见文本版本。随后补状态 snapshot 往返、action 调用方取消、共享原生值 readiness、旧 Context 刷新和标准容器 identity。资源用例再覆盖预览升级、签名复用与图库窗口。每轮仍要复验用户的 10 项原生失败，保留第一条断言，不改历史预期压绿。

现有 `testCanonicalMarkdownPreparationCoalescesWithoutStarvingContinuousInput` 在 MainActor 同步循环投喂后才等待最终结果，未证明持续分片时的中间可见进展。文本 buffer 的 48 ms 逻辑是 throttle，追加不重置计时器；不能把真实停滞直接解释成普通 debounce。两个允许旧前缀的展示阶段和共享 Markdown worker 的等待需测量；如果直接 Text 也停滞，则还要检查更上游的宿主/投影/发布。旧 Slider 提交中的 `testDraftFeedbackRefreshDoesNotFlushWritesOrRequestFocus` 也尚未迁入，它属于验证遗漏，不是已证生产故障。

本次可复跑探针位于忽略的 `outputs/text-audit/`、`outputs/remaining-action-budget-probe.*`、`outputs/remaining-state-aggregate-probe.*` 与 `outputs/main-assessment-20261116/`。只维护本文这份验收记录，不新增并行审查报告。

### 性能证据与未完成项

同一台审查运行器、Node v24.22.1、同一旧资源、160 个稳定节点加文字尾部（8,439 UTF-16 units），各测三次；每块执行实际增量 parser、Store 初始化和 boundedRoot，末态相同：

| 每块 UTF-16 units | 每条流更新次数 | 整条流累计耗时中位数 |
| --- | ---: | ---: |
| 16 | 528 | 1,273.9 ms |
| 128 | 66 | 133.9 ms |
| 512 | 17 | 37.7 ms |

这只量化 JS/V8 下更新频率的成本，不包含 Swift 预检、JavaScriptCore、原生桥接、live index 或布局，也不是用户设备帧率。不能据此宣称 SwiftUI 已有某个固定倍数的提速。

另一个独立探针使用修复后的资源和原生 `NativeExpressionGuard` 相同的判定，对实际 preprocess/tokenize/split 单独计时。在同样 8,439 UTF-16 units 的文档中，16-unit 分块触发 209 次完整前缀检查，累计扫描 1,417,847 UTF-16 units，检查本身三轮中位耗时 138.7 ms；128-unit 分块为 27 次、183,159 units、15.5 ms。原生快速包络超过保守阈值后，完整前缀检查因此会贡献重复工作；这不是 parser 已完成语句缓存被清空。探针仍是 Node/V8，未包含 Swift 遍历、JavaScriptCore 调用与设备 UI，不与上表混为同一轮前后性能对比。

以下仍是开放项，不能标为本轮已解决：

- `OpenUIState.push` 在 MainActor 同步工作，没有自动按显示帧合并输入。应用持续送入很细分块时会增加整轮求值和投影次数；本轮同步重入队列不改变这一点。
- 原生输入保护在超过快速包络阈值后会再次扫描完整前缀。优化时必须保留截断 token、注释、转义、消息封包和实际表达式深度限制；不能为降低次数简单删掉保护。
- 多步 Action 没有整条计划的累计工作预算或渲染合并。每个 Set/Reset 通知 State 同步重算 root，结束后再重算；实际合法的 2,034 UTF-16 units 探针含 128 个 Set 和 128 行 Each，各次求值均未超限，按现有 Swift 路径会发生 129 次 root 求值。Node 单次 root 为 1,549 工作单位，乘数是源码推导，不是设备计时。后续必须在保留逐步 Store 可见性、Mutation 失败即停止和事件顺序的前提下设计提交/累计额度，不能直接删掉中间状态通知。
- 本次另用正式 JS bundle 解析 9,946 字节的合法程序，取得 100 个 Set 后逐步调用 boundedEvaluate 并写入 JS Store：解析/root 均未超限，每步为 19,315 work，100 步累计 1,931,500 work，仍无一步失败。这直接证明单次 100,000 work 上限没有覆盖整个计划；探针未调用原生 runActionPlan，不含 Swift 每次 Set 的 root 刷新，也不是设备阻塞时长。应将计划累计预算、可取消等待与必要的让步一起验证。
- Query 通知也没有呈现合并：实际分发 JS manager 的 100 个独立请求产生 100 次初始通知和 100 次完成通知；`OpenUIState.observeQueries` 当前对每次通知创建 MainActor Task 并 update。200 是实测 JS 通知数，原生任务执行/整树求值次数仍需计数；不能通过丢失请求状态、错误或完成事件来压低通知量。
- SwiftLangView 与各 ComponentHost 广泛订阅同一个 ObservableObject，尚未获得真实“尾部更新而稳定兄弟不重算”的 body 计数。不能仅加 `equatable()` 就假定依赖已被隔离。
- SharedCore 用锁串行化共享 JavaScriptCore。锁保护线程安全，不会自动把工作移到后台；多个文档可能相互等待。迁移到 worker 需要同步定义不可变输入/输出、回调线程、取消和提交代次，不能用 `Task.detached` 直接包住当前 MainActor State。
- 当前节点的 identity 快径不消除所有旧快照的语义搜索；规模较大的匿名桶需原生计数与耗时证明，再决定索引粒度。
- 尚无本轮真机 Release 的帧耗时、输入响应和长期内存数据。文档拥有的编辑记录保留离屏草稿，不能为压低缓存数字随意淘汰用户未提交内容；动态字段的长期留存需要专项测量。

编码前保护的范围以适配清单为准：高层 OpenUIState 的写入/恢复、Query/Mutation 输入输出、Evaluator 上下文与 `evaluate(ASTNode)` 已加入预检；直接使用底层 CoreStore 的 void 写入/初始化、手工构造 ParseResult 的非 snapshot 物化路径尚未形成统一的显式失败契约。宿主函数在返回前的自身计算、外部 provider 忽略取消后的执行也不能被库抢占。不能将本轮修复解释为对任意宿主代码或所有低层构造入口提供了隔离沙箱。

现有 [LanguageRuntime 基准](../Benchmarks/LanguageRuntime/README.md) 新增公开 MainActor State 的真实流式路径和宽对象构造，报告逐次 push、complete、整流、发布次数与耗时分位数；CI 已配置实际运行 32/256 两种分块并保存 JSON。配置完成不等于测量已执行。原生验收还必须同时检查 terminal flush、停止/换源后旧结果失效、超限前无工具派发、完整控件可用、未完整控件不可执行，以及 Release UI 的 body/布局/挂载和滚动交互。

本轮还纠正了旧基准调用与公共 API 的漂移：`Evaluator(context:store:schema:)` 的 `store` 实参已没有对应初始化器，基准改为当前 `Evaluator(context:schema:)`，状态仍由传入的 EvaluationContext 回调读取。YAML 及 workflow 内 shell 语法单独检查；这些检查不构成 Swift 编译通过的证明。

### 内核目标验收

下表是后续设计的验收要求，不是当前通过结果。每项实现时补对应验证，执行日志放 outputs；设计本身只在[架构](architecture.md#执行与呈现的目标设计)维护。

| 范围 | 验收场景与通过条件 |
| --- | --- |
| 输入合并与结束 | 控制显示调度，连续送入细分块；周期内至多一次普通流式提交，最终 UTF-16 内容与直接输入一致。complete 不依赖下一帧且提交完整尾部；interrupt 不补全截断 token，旧流不能自动派发工具，已闭合操作仍按 readiness 判断。带文档句柄的入口拒绝旧流晚到分块；reset/替换后旧队列不能回填，并分别保留既定的状态清理/保留语义 |
| 排队与过载 | 生产速度持续高于消费速度，缓冲与待执行任务数仍受定义的上限约束；达到输入上限明确失败，不能丢内容后继续宣称成功 |
| 提交一致性 | 在 root/字段/readiness/错误发布和回调中制造重入、换源及乱序完成；每个可见提交内部一致，较旧更新不能覆盖较新结果，旧组件写入被拒绝 |
| 节点隔离 | 在稳定兄弟后持续修改文本尾部，并分别改变 readiness、Query 状态和字段值；无关节点的投影/body 计数不随分块等比例增长，实际依赖变化必须生效，焦点和未提交草稿保持 |
| 动作执行 | 多 Set 后发送事件，事件读取正确的逐步状态；纯写入段的 root 工作按提交段收敛，必要回调顺序保持。累计超限、Mutation 失败或让步期间换源后，剩余步骤停止且等待结束 |
| 原生输入与恢复 | 深/宽/共享图、整批状态恢复、直接底层入口均在大规模投影或写入之前明确拒绝；失败不提交部分无效数据，合法替换/reset 后可重新工作 |
| 设备响应与资源 | 同一设备、Release 构建、同一工作负载记录分阶段 p50/p95/max、主线程连续占用、提交/body 次数、输入与滚动响应；重复创建/退休文档检查任务和引用是否释放。JS 耗时、进程 RSS 或一次截图不能单独作为通过依据 |

帧耗时和响应阈值随目标设备及刷新率记录，并在前后比较前固定测试条件；当前尚未取得设备基线，不填写未经测量的达标数值。行为不变量必须通过，性能优化还需证明目标工作量减少且正常交互无退化。
