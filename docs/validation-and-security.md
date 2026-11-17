# 验证与依赖安全

文档版本：1.29 · 更新日期：2026-11-17

本文说明当前 SDK 的可复现输入、依赖安全和原生验收范围。具体提交的执行结果以 [Native SDK 流水线](../.github/workflows/native-sdk.yml) 的日志为准。当前生成输入由 [Tools/upstream.json](../Tools/upstream.json) 固定，完整上游许可保存在随 SDK 打包的 [THIRD-PARTY-NOTICES.txt](../Sources/SwiftLang/Resources/THIRD-PARTY-NOTICES.txt)。

历史定向记录：中文强调与正文尾部反馈的修复基于 `c20081d`，原始中文标点案例和终态未闭合 Stack 的新增检查先复现失败，修复后 Markdown、流式文本准备、布局与 readiness 相关 55 项 Debug 检查通过。该次 Release 使用忽略目录中的精简测试包，只复制原有目标 XCTest 文件并直接链接当前 Sources/资源，11 项中文强调、正文前缀、诊断隐藏及 Host 拟合检查通过；该次标准整包 Release 测试构建被 Xcode 26.6 的 SwiftLangTests `NativeValueBudgetTests.testSyntheticMetadataAndActionLeavesShareTheInspectionAllowance` 优化器崩溃阻断，不能记为通过。另一次较宽的定向运行发现 `FullLibraryParityTests.testModalPresentationWritesDuringStreamingButRejectsReplacedSources` 失败，未修改的 `c20081d` 独立 checkout 也复现同一断言，原断言保留。该次未执行全量测试，日志保存在 `outputs/targeted-chinese-markdown/`。下文 Xcode 26.3 的完整验收不代表该 Xcode 26.6 优化器问题已修复。

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

流水线按当前 SDK 分成三项检查：可复现输入、依赖安全和原生验收，最后由 `Native SDK acceptance` 汇总。汇总仅在三项均为 success 时成功；failure、cancelled、skipped 或缺失结果均不算通过，并在摘要记录实际 checkout SHA 和各项结果。该 job 的存在不自动设置仓库分支保护，合并阻断还需仓库将它配置为 required check。可复现输入检查重建实际打包资源并运行语言、authoring 和组件目录回归；安全审计覆盖 Core、标准富文本、代码高亮、图标和 Intelligent 函数五个生成工具依赖图，使用 `--audit-level=high` 门槛。原生验收构建并测试根 SDK 及其公开产品消费者。

原生验收覆盖 SwiftLang、OpenUI、OpenIntelligentUI 三个独立产品消费者。每个外部包只声明一个产品，验证打包资源、authoring、解析、流式、生成契约、原生宿主和状态读写；不启动窗口，不能代替 UI 视觉验收。模块检查禁止适配层导入两套组件库、任一 UI 导入另一套库；适配层内部 Language 目录不导入 UI 框架，Runtime 目录承接 SwiftUI。

其余原生验收覆盖全部原生测试、Release fitting、Release 挂载流式与呈现/订阅回归、独立 Gallery 测试与双库案例完整/流式验证、完整历史契约、语言 ASan、独立契约/性能工具及 iOS 编译。独立检查在前一个检查失败后仍可收集证据，但任何检查失败都会保留为任务失败。消费者源码生成或语法检查不等于实际 Swift 编译通过；原生编译与测试结果以对应提交的执行日志为准。

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

readiness 通过 parser-owned Symbols、基础 WeakMaps、单次求值的 snapshot WeakMaps 和 Each 输出位置的私有 scope 记录源边界和依赖；这些元数据不进入 Lang 值和序列化 AST。共享原生容器的临时未就绪标记和 Query 归属不能污染另一次求值，也不能污染同一次求值中直接复用该值的兄弟位置。Swift 投影按 JS 值身份与 scope 缓存，必要时重建带元数据的不可变路径，并保留原 JS 身份、SameValue 与反向编码关系。Action 的 opaque capture 保持业务值身份，不继承展示位置的 pending 约束。仅具名的原生元数据可在官方协议比较中排除。必须用原生交互测试验证完整控件可用、未完成动作不可执行、文档替换后旧回调失效。

未闭合 `Each` 的失效约束现在随输出位置传递，不再遍历共享后代写入 metadata；模板求值本身的写入也留在该 Each 的局部 snapshot。Core 已有的 prop-array 映射携带这一约束，不为附加 metadata 无差别复制 Lang 值。输出预算仍按每次出现累计。对应回归直接计数数组访问：500 个结果共享同一个 500 项数组时，readiness 失效遍历为 0 次，最终展开输出仍被原预算拒绝。这个计数只证明该遍历被移除，不是设备性能测量。

早期修正曾执行 33 项 native JavaScript 回归、独立官方内核对照，以及 480 组普通分块、24 组封包分块的终态比较；历史证据保存在忽略的 `outputs/audit-lang-2ae6ced/`。本轮生成资源的执行计数以第 4 节为准。JS 结果不覆盖所有中间帧，也不能替代 Swift 桥接、原生交互和设备帧率验收。

原生数据桥接使用私有对象身份区分真实 ActionPlan 与含 `steps` 字段的业务对象。静态和动态业务对象保留其字段；宿主显式构造的原生 plan 可直接用作 action prop，显式 `Action(...)` 组合仍保留官方 `ownSteps` 对自定义动作的来源检查。此数据修复、表单校验器仅查自身键的修复以及下列预算均列在适配清单中，不通过修改历史 fixture 隐藏与固定官方核心的边缘差异。单键 Store 读取仅检查该键并读取其值，保留键不存在与显式 `undefined` 的区别。

完整消息的 `push`、`set` 和批量解析使用同一官方消息提取规则；重试帧选择最后一个 content。普通 Lang 分块保留增量路径，协议标记跨分块时由原生输入适配保留边界，不引入另一份语言 parser。替换 Mutation 时，原生 Task 与等待中的 Promise 按声明实例一起取消；即使宿主 provider 忽略取消，等待动作也能结束，其他 Query 不受该局部取消影响。

serializer 修复后的程序须由未修改的官方 parser 接受，并保留求值意义；不能将其输出拼写变化描述为逐字等价。standalone patch 必须与实际构建变换一致。

| 原生预算 | 边界及超限结果 |
| --- | --- |
| 源码 | 1,048,576 UTF-16 units；100,000 tokens；4,096 statements；单表达式 128 层嵌套或 256 个运算符；超限为 parse-exception，最后有效前缀只读 |
| Materialization | 256 层 / 100,000 工作单位；整批状态默认值共用余额，超限为 parse-exception，并在投影状态默认值和根节点前将私有失败标记传给 Swift |
| 动态求值 | 每个同步求值范围 100,000 工作单位、256 层；涵盖递归求值、Each 展开和内建函数工作量；Query 批次共用余额，超限立即停止 |
| 整条 Action | 一次计划累计 100,000 工作单位，覆盖步骤、原生输入/输出、表达式、逐步 root 更新与同步 Query 工作；私有 JS 入口接收剩余额度，嵌套求值不重置或重复消费同一 JS 工作量。超限停止剩余步骤；已完成步骤的 Store 可见性和回调顺序保留 |
| 输出与渲染 | 展开后的值最多 100,000 节点、256 层、4,096 个组件实例及 1,048,576 UTF-16 units；共享子树每次出现都累计成本，以缓存和饱和计数避免检查本身指数展开 |
| Store 写入与初始化 | 对提交后的整份状态统一检查上述图预算，增量写入用字段成本账本计算替换后的总量；initialize 在编码和提交前检查输入与最终候选，拒绝时保留原状态，不留下部分初始化 |
| 有序 JSON 解码 | 128 层；超限为原生 JSON 错误，JSON 语法仍由 JavaScriptCore 校验 |
| 正则 | 65,536 pattern units、1,048,576 input units，限制内存、栈与 VM；资源耗尽阻止表单提交，普通不匹配与非法表达式保持各自语义 |
| 原生值转换 | 保留 256 层防御检查；更深传输不在已验证的等价范围内 |

预算之外不宣称与 stock core 等价。有限 fixtures 通过也不证明任意程序、后续版本、所有设备或网络时序正确。新差异必须解释或修复，再决定是否有依据增加新的版本预期。

真实流式性能与重复拟合分开验收。当前 `OpenUIState` 在 MainActor 上同步执行每次 push 的解析、根求值和 live-element 索引；`SwiftLangView` 观察完整的原生呈现提交，轻量组件 Host 仍观察最近 State，内部内容使用节点订阅。`RuntimeHostIsolationTests` 与 `HostSizingIsolationTests` 中重复提交相同源码和尺寸拟合的检查，只证明该路径不重复解析、发布或重挂，不能证明真实尾部增量不会刷新无关组件。局部刷新与每帧耗时需要在目标设备的 Release 构建中，另测不同内容规模和分块频率下的解析、桥接、求值、组件 body 与布局成本；没有运行证据时不宣称该观察路径已经收敛。

任一物化、求值或输出预算失败后，OpenUIState 保留最近一次通过预算的已显示内容，停止当前文档的动作、Query 和 Mutation；不能把失败产生的 `null` 继续写入状态或作为工具参数。替换源码或 reset 可以恢复。预算用于限制异常工作量，并非每帧耗时或设备帧率保证；原生不卡顿仍需在目标设备 Release 构建上测量。

原生控件验收还包括：EditableTable 的本地提交不得代表远程持久化；被拒绝的草稿不能随 Store 发布而提交；替换文档建立新草稿生命周期。Slider 的离散选择同时考虑 minimum 和 step 精度，非整除范围允许拖到最大值，连续文本仍按范围校验。对应控件测试与真实窗口检查各自报告。

## 4. 内核稳定性审查与当前验收状态

此前从已核对的 main `1f070fe5428467ed60c6be2870a2f5f6e1386494` 集成独立的文档资源生命周期优化，保留主线的图片尺寸、自动重试、请求策略和 readiness 修复，见[文档资源生命周期](#文档资源生命周期)；此前的内核清理记录见[内核职责与失败边界清理](#内核职责与失败边界清理)。整合后的验收源码为 `315cd4edc9de744b8996a1b9c3bb271c6b34acbc`，执行记录为 [CI 44073952191](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44073952191)，逐项状态见[客户端复测收尾候选](#客户端复测收尾候选)。下文历史章节中的“本轮”“当前”“尚未执行”描述该轮交付时的状态，通过数量、客户端样本和 CI 结果仅属于其标明的版本，不覆盖后续执行记录。

### Query 反馈去重与终态引号回归

本轮从 `f8ea337cd1421dae08fd224ce27428e47215e4b0` 开始，交付前整合主线 `d2e4cabdb649452f9ddc02c851ad20d1d9aa1998` 的图片占位主题更新。Context 与原生呈现的 Query 反馈改为同一个内部函数，一次遍历计算 pending、failed、interrupted，删除临时 Query 数组；两个调用方仍分别读取实时状态和同一份不可变提交。Core 构建中的嵌套变换展开为原顺序的语句，合并职责重叠的插件包装。没有新增公开 API、缓存、状态所有者或语言解析路径。

引号案例加入现有 `native-streaming.test.mjs` 和 `CompletionDeliveryTests`，均使用实际 OpenUI 组件契约。未转义输入固定保留原样，验证终态的两个文本前缀与四项诊断；正确转义对照验证完整正文、空诊断，以及批量和逐字符输入的一致性。Swift 用例还覆盖 `onParseResult` 和最终 `state.errors`，不要求完成时再次触发已去重的 `onError`。这些测试记录现有容错行为，宿主展示规则见 [README](../README.md#终态与诊断)。日志重建的最小输入不代表原会话全文回放，也未确定转义在哪一环丢失。

| 检查 | 实际结果与边界 |
| --- | --- |
| 正常 Core 重建 | PASS；`lang-core.js` 仍为 867,563 bytes，SHA-256 `cff0c3f3dd7009ef0f779e1e16b1fb510087c79ff2dedc8f081987fc35cd2a49` 与基线相同；生成清单仅更新 adapterSha256 |
| 全部 Core JS 回归 | **172/172 PASS，0 failed、0 skipped**，含新增的两项引号回归；单独运行流式文件为 28/28，已包含在 172 项中 |
| 独立上游对照 | PASS：51 parser、5 action、4 Query、6 serializer round-trip、21 Lang 1.1、2 split/merge 对照，`unexplainedDifferences=0` |
| 源码所有权与格式 | `check_openui_integration.py` 和 `git diff --check` PASS；不代表原生编译通过 |
| Swift 原生验收 | BLOCKED：定向 XCTest、完整 `swift test`、Release host 子集均因找不到 swift 返回 127；模块图检查同样无法运行 `swift package dump-package`。新增 4 项 XCTest 尚未编译/执行，其中 Query 反馈测试含 24 组状态预期及实时/提交边界检查 |

执行证据在忽略的 `outputs/lang-runtime-boundaries/`。删除中间数组和合并遍历属于源码层面的工作收敛；本轮没有 Apple App CPU、内存、帧率或 push 延迟测量，不据此宣称设备性能提升。

### 完成长文档的滚动与布局

本轮从已合入的 `2db93675e50ba89579594c5220e935928bea55bd` 开始。客户端反馈来自锁定 SDK `7d9b36a` 的模拟器 Debug 长会话：页面约 53,810 pt，观测到的三个视图实例约 14,091–18,034 pt，各实例根求值结果按对象身份去重可达 162–206 个元素。实例未绑定业务标识，不能认定为三个独立文档；可达元素数量不是实际 SwiftUI 视图数。

| 客户端一次隔离实验 | 超过 100 ms 的回调间隔数 | 最大间隔 |
| --- | ---: | ---: |
| 完整 OpenUI | 19 | 约 280 ms |
| 表格等高隔离 | 20 | 约 197 ms |
| Markdown 等高隔离 | 17 | 约 183 ms |
| 整个 OpenUI 根视图等高隔离 | 0 | 约 57 ms |

以上是用户提供的 CADisplayLink 回调间隔，非函数耗时或本环境实测。每组仅一次，操作总时长、位置和机器负载未完全控制，过程中模拟器曾重启，不能换算成优化百分比。表格 `currentColumns` 的临时复用实验消除了对应采样出现，仍有长间隔；单独移除表格或 Markdown 也不足以解释整体问题。内存快照未附有效分配栈或持有链，尚未证明泄漏。临时等高隐藏只用于隔离，没有作为 SDK 的呈现策略。

源码核对确认，`7d9b36a` 至本轮基线的 FlowLayout、标准表格和 Markdown 核心呈现路径没有变化。此次只收敛两处明确重复工作：Flex 的测量与放置共享当前 Layout 有效 proposal 的 frames；表格一次 body 只推导一份当前列及分页值，复用不可变列数组。保持原有布局算法、组件身份、流式推进、表格数据回退和完成后的动态更新，机制说明在 [OpenUI](openui.md#布局与流式)。布局或子视图变化的失效遵循 Apple 的 [Layout.updateCache](https://developer.apple.com/documentation/swiftui/layout/updatecache(_:subviews:)) 契约；缓存仅属于一个布局实例，不能以文档 complete 作为永久有效条件。

共享压力输入使用 [mixed-long-document.openui](../Tests/SwiftOpenUITests/Fixtures/mixed-long-document.openui)，文字为固定合成内容，不含真实会话、账号或网络资源。随包内核与真实目录解析得到 200 个可达元素，批量输入与每 64、512 个 UTF-16 单元分块输入的完整结果一致，错误及未解析引用均为空。它覆盖混合正文、卡片、表格和表单；目标是在同一输入下复测尺寸、更新和交互，尚未证明与客户端真实会话等价。原生测试记录实际元素数量和高度，不把设计目标高度写成测量值。可通过现有 Gallery 直接打开：

~~~sh
swift run --package-path Examples/Gallery -c release OpenUIGallery \
  --library openui \
  --program "$PWD/Tests/SwiftOpenUITests/Fixtures/mixed-long-document.openui" \
  --width 390 --height 844 --zoom 1
~~~

验收分开检查计算复用与正确失效：同一有效 proposal 的 frame 计算可复用；宽度、同数量内容、字体、布局值、子项增删仍更新几何；完成后表格状态修改及行数收缩仍更新可见内容。长文档重复拟合须保持无额外解析、语义发布或重挂，宽度往返仍恢复正确几何。计数和几何测试不代表滚动帧率，最终仍需同一输入、设备、构建和手势下的 App 对照，包括滚动位置、流式尾部、动态高度、表单草稿、链接和会话切换。

字体失效回归在 macOS 上显式切换继承的 font 环境，保留高度必须增长及恢复的断言。Apple 明确说明 [dynamicTypeSize 在 macOS 不改变文字大小](https://developer.apple.com/documentation/swiftui/environmentvalues/dynamictypesize)，因此不能用该环境值下文字等高来判定缓存失效，也不能把 macOS 字体回归写成 iOS 系统 Dynamic Type 的运行结果；后者仍需目标平台验收。

当前本地没有 Apple/Swift 执行环境；本轮新增原生用例的编译与执行状态以候选 CI 为准。现有 Debug/Release 组件回归入口加入 `LayoutMeasurementReductionTests`，长文档接入现有 HostSizingIsolationTests 与 Release fitting 验收；没有另建性能测试流程。LanguageRuntime 基准不挂载 SwiftUI，不能替代此项验收。本地执行记录在忽略的 `outputs/long-document-layout-cost/`。后续若需要区段呈现，宿主继续拥有滚动可见范围、消息回收和阅读位置，SDK 继续拥有同一文档的节点身份、引用、Store 和交互；本轮没有引入分段 State 或视口管理器。

### 文档资源生命周期

此前独立提交 `dad6d4f` 沿用现有 State、Store、Query 和同步输入 API，收敛已完成资源缓存与桥接身份记录的所有权；本轮将其集成到 `1f070fe`。两类缓存共用一个内部实现，保留单文档额度并加入跨文档合计额度；数据不跨文档共享。iOS 内存警告和 macOS 内存压力只清理可重建的已完成缓存，保留 pending 请求、鉴权 scope、generation 和视图已持有图片。预算与宿主责任只在[架构](architecture.md#文档与资源的生命周期)维护，客户端不需要新增 `snapshotState()` 调用。

桥接的五类原生引用值各自持有 JS 身份，SharedCore 只留弱反查。销毁旧快照按记录身份精确撤销，移除原来每 32 次调用的全表扫描；JS 堆的垃圾回收时机仍由 JavaScriptCore 决定。析构不获取执行域锁，弱表短锁内不调用 JS 或释放强原生/JS 引用，防止 VM 回收回调与执行域锁形成反向等待。该锁序依据 [Apple 的 JavaScriptCore 线程说明](https://developer.apple.com/documentation/javascriptcore/jsvirtualmachine) 和 [WebKit 的 JSValue 析构实现](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/API/JSValue.mm)核对；源码推导仍须通过原生并发与生命周期回归。原生对象编码为 JS 数据，不能改为直接导出拥有 JSValue 的原生包装对象。

新增 15 项 XCTest：`ResourceCacheBudgetTests` 6 项、`ResourceStoreTests` 4 项、`SharedCoreBridgeTests` 5 项。覆盖跨文档 LRU、单文档/合计额度、超大候选保留旧值、替换成本、零成本条数限制、弱 owner 释放、压力下 pending 成功、请求 scope 与图片快照保留，以及桥接包装立即释放、旧/新 readiness 身份和跨线程析构。图片测试使用小图和显式成本，不作为实际内存或画面测量；桥接释放断言针对原生对象及 JSValue 包装，不把 JS GC 或 RSS 回落当作同步承诺。Release 定向集合加入这两个测试类，保留原有全部集合与断言。

此次集成保留这 15 项，另增加一项共享图片预算与当前请求策略的组合回归：修改限额后允许较小的有效图片替换旧高清缓存，拒绝旧限额结果、退休 scope 和不匹配的 owner 入池。冲突解决同时保留主线的显示尺寸、HTTP 自动重试、签名请求及全部限额检查；Release 筛选取两条分支的完整并集。原独立分支的检查结果列在下表，不作为此次集成的原生通过证据。

| `dad6d4f` 交付时的检查 | 当时的实际结果与边界 |
| --- | --- |
| 实际打包核心的 JS 回归 | 167/167 通过，0 failed、0 skipped；本轮 JS 资源未修改，这只保留语言行为基线，不覆盖新的 Swift 实现 |
| Validation / catalog compatibility | 6/6 与 7/7 通过，0 failed、0 skipped |
| 资源完整性与源码归属 | `check_openui_integration.py` 通过；lang-core.js、manifest 和许可 SHA-256 与基线一致；没有修改历史 fixture |
| 原生测试与完整 SwiftPM 图 | 当时本地 `swift test` 与模块图检查受缺少 Swift 工具链阻塞；新增 XCTest 未编译、未执行，Release fitting 与设备 UI 复测未运行 |

集成候选 `21cbb3e` 已在 macOS CI 运行扩大后的 Debug 前置组，103/103 通过，其中新增生命周期回归 16/16 通过。Release 和完整门禁结果统一记录于[客户端复测收尾候选](#客户端复测收尾候选)，不再以独立分支交付时的工具链限制描述集成后的状态。

本地日志在忽略的 `outputs/document-resource-lifetime/`。缓存上限不包含宿主强持有的所有历史 State、挂载图片、工具结果和系统资源；本轮没有自动卸载文档、暂停 Query、删除未提交草稿或实现完整 checkpoint。缓存淘汰后再次访问旧资源可能重新加载。每个未桥接原生引用现在也持有一枚空身份记录，净分配成本和移除全表扫描的实际收益需同条件 Release 测量。尚无本候选的 App CPU、真机内存、帧率或持续滚动证据，不据此宣布客户端卡顿或长会话问题已全部解决。

### 历史修复记录

本节保留各轮修复的执行证据。早期以 `9e05d888ef31cfff6eb8c75f3ca01ed089ec3e78` 为基线完成下表修复，经 `bdac1bfd03bf19df527681517b2f3c3aee19a368` 合入 main，随后继续处理原生执行及文本同步；`c7310054e5a58ecb7e42e9f37e4c77e7fed30ce7` 是后续客户端审查的历史基线，不是本节所记录的最新修复。

内核修复 [`1063d9f2`](https://github.com/zyfn/open-intelligent-ui-swift/commit/1063d9f21466ffa9da2d53f1bb8e33ef1c3af4bd) 已通过 [`a4808be3`](https://github.com/zyfn/open-intelligent-ui-swift/commit/a4808be333598bb15a6990f47eeb0d23c930c1dd) 与同期 main 合并。用户随后提供该合并版本的 Apple Release 及 App Debug 定向复测：19 项外部探针全部通过，同步计算与发布次数下降，但 App 平均进程 CPU 仍约 92.8%，官方 XCTest 目标另被新的测试类型错误阻塞。该版本的高 CPU 与原生验收仍未关闭。合入时的本地证据和后续客户端复测在下文分别记录；客户端结果只覆盖固定的 `a4808be3`，不代表后续修复分支的效果。剩余工作见[性能证据与未完成项](#性能证据与未完成项)，设计约束见[架构](architecture.md#内核必须保持的约束)，依赖版本及兼容性检查仍按第 3 节记录。组件视觉由独立任务负责。

| 问题 | 触发与依据 | 前轮处理及验证层级 |
| --- | --- | --- |
| 隐式转换逃逸工作量预算 | 约 6 KB 程序用共享数组做 `==` 或动作字符串参数，最终值很小但中间发生大规模遍历；500 项探针实际读取 250,500 次，旧预算仅报告 1,506 工作单位 | 转换前测量并累计成本，覆盖比较、索引、拼接、动作及 Filter/Sort 内重复转换；新增回归中 8 项在旧资源失败，修复后通过；1,053 个小输入与独立官方核心对照无差异 |
| readiness 跨文档污染与容器缓存过期 | 不完整 Each 在共享对象上留下未就绪/Query 标记；完整文档仍读到旧标记，而 Swift 命中父容器缓存又可能跳过后代变化 | 改为单次求值 snapshot 与显式原生投影；保留旧快照和 JS 身份。3 项新 JS 回归旧资源全失败、修复后全通过；真实 Swift 缓存/交互回归已加入，待原生运行 |
| 原生对象字段整理为平方级 | 每插入一个键线性扫描已存在字段，10,000 个不同字段固定发生 49,995,000 次键比较；这在 JS 求值预算之外 | 以精确 UTF-16 哈希键保存首次位置/最后值，整数键只解析一次后排序；新增顺序、重复键、Unicode、JS own-property 对照及宽对象回归，待原生运行 |
| 当前匿名节点重复搜索整个桶 | 不完整 Each 生成同类型、无 statementId 的控件，当前树的 1,000 个节点按旧逻辑需 1,000,000 次候选比较 | 当前对象身份 membership 直接返回，旧快照仍保留原有消歧；JS 输出及工作量计数可复现，原生快径与消歧回归待运行。旧快照的大桶搜索风险仍需测量 |
| 同步发布回调重入造成旧轮覆盖或重复通知 | `@Published` 在 willSet 同步调用订阅者；订阅者换源后旧 setter 和后续渠道仍可继续写入。onError 恢复也可能使外层再通知内层的解析结果 | 同步重入顺序执行、过期轮终止，并在执行排队的控件写入时再检查 revision；新增替换、同代状态写入、no-op 重放、连续命令和旧 Context 回归，待原生运行 |
| 异步 Query 返回后先派发再验根预算 | 现有依赖调度先从 rows 自动派发参数很小的下游工具，随后 root 的多层 Each 才超限；不能只检查 Query 参数 | 在原生自动派发进入 provider 前复检当前文档、完整性与呈现预算；增加原生时序回归，待运行。JS 探针证明调度次序，不冒称已执行 Swift Task race |
| 排队的旧 Query 仍可进入 provider | 等待 MainActor 检查期间 patch 改变或删除 Query，此前只在结果回来后判断旧 key；首次批次还可能在同步发布回调换源前开始调用 | 所有 Query 等待当前同步发布结束，已检查批次只复核存活状态，不再次算 root；进入 provider 前核对 Query 实例及请求 key，保留同 key 请求，拒绝删除后同名同 key 重建的旧请求。私有 hook 与原生时序回归分别验证 |
| 原生输入先编码后检查 | 工具返回值、纯函数返回、宿主状态/引用和原生 AST capture 可在进入 JS 预算之前递归编码；初始/恢复状态也可先进入 Store | 加入 Value、AST 与整批状态图预检，按共享子树每次出现累计成本，用 memo 和共享检查额度限制预检本身；上下文使用有限弱引用缓存避免重复扫描。失败中止当前 JS 预算、结束工具等待，并保留旧 Store/呈现，不能提交 `null` 或部分恢复。原生回归待运行 |

前轮正式生成资源执行过 **84/84** 项 `Tools/Core/native-*.test.mjs`，覆盖 26 个分块不变量案例的 **2,123 个中间前缀**及其末态；比较公开值、声明、诊断与私有 readiness。增量 push 与同前缀 fresh set 一致，这是分片不变量检查，不是独立官方 oracle。该轮独立官方检查执行 51 项 parser、5 项动作、4 项 Query、6 项 round-trip、21 项 Lang 1.1 专项，未发现未解释差异；额外 1,053 项隐式转换对照也无差异。6 项原生输入失败 JS 回归在旧资源均失败，修正后通过；5 项 Query 请求有效性回归覆盖变参、删除、保留、删除后重建与 dispose。历史 fixture 预期未修改；84 项是前轮计数，不是本轮最终结果。

前轮修复新增 54 项 XCTest，但本审查环境缺少 Swift/Xcode，`swift test` 曾实际返回 `swift: command not found`；完整 SwiftPM 模块图检查也受阻。已回读前轮合并提交的 [CI run 43809174570](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/43809174570)：reproducible-inputs 与 dependency-security 为 failure，runner 与 steps 为空；native-sdk 为 skipped。该记录既不是前轮原生通过证据，也不是本轮候选的 CI 结果。本轮 Swift/XCTest 同样未编译、未执行，Release 宿主测试和设备基准未运行。前轮日志保存在忽略的 `outputs/kernel-audit-9e05d88/`，不另建并行设计或审查文档。

### 已合入基线的前轮修复与验证

该轮已修改下列生产实现并补充回归，状态是“代码已实现，原生验收待执行”。客户端继续使用现有 `push`、`complete`、`interrupt` 及既有回调；没有新增流句柄、`beginStream` 或替代接入方式。公开 Lang 值、参数及业务回调顺序保留。裸 `push(String)` 本身没有请求来源信息；过滤已退休请求的迟到分块仍属于宿主现有请求生命周期管理，不能把这一限制包装成新的 SDK 用法。

| 该轮修复 | 实际处理 | 已执行证据与待验收范围 |
| --- | --- | --- |
| Store 总量与原子初始化 | `CoreStore` 在编码前检查写入后的整份状态，用字段成本账本计算替换后的总量；initialize 分别预检 defaults/persisted 输入并检查最终候选，确认后一次提交。失败保留旧值，合法后续写入可恢复，原 JS Store 仍持有业务值和通知 | 已补增量写入后的 snapshot 往返、替换、pristine/undefined 与失败不部分提交回归；Swift 未运行，不能声称真实 Store 往返已验收 |
| Action 调用方取消与 Mutation 等待退出 | 步骤前后及 await 返回后检查 `Task.isCancelled`；Mutation waiter 处理取消、完成、退休和 dispose 的竞争，并只恢复一次 continuation。取消对应请求后可重新操作，其他 Query/Mutation 不随之退休 | 已补已取消入口、等待中取消、忽略取消的 provider、迟到结果和后续步骤停止等原生回归；尚未执行。SDK 结束等待不代表可以抢占宿主 provider 的外部工作 |
| 整条 Action 的累计预算 | 一次计划共享工作额度，覆盖 plan/输入输出/步骤/事件、表达式、逐步 root 更新和同步 Query 工作。私有 JS bounded 入口接收剩余额度，嵌套沿用同一 scope，Swift 只在外层消费 JS work。完整步骤之后可让步，已有逐步 Store 可见性和回调次序保留 | JS 验证单独允许的两个 Query defaults 同批超限、剩余 1000 时在 1001 拒绝、嵌套不重置，以及同步 invalidation 通知内的求值计入额度；整条原生 action、取消/换源与 provider gate 尚待 XCTest。未实现多 Set 的 root 合并，也未宣称消除卡顿 |
| 公开底层入口的编码前预检 | 覆盖 `CoreStore.set/initialize`、被宿主改写后失去 parser snapshot 的 ParseResult、手工 Query AST 和 Mutation 声明/参数；在递归编码前拒绝深、宽或累计超限数据。OpenUIState 通过已有错误渠道退休执行，不能继续提交失败后的 null | 对应低层与高层原生回归已加入，未编译/执行；自定义 Store 与宿主函数返回前的自身计算仍由宿主负责 |
| 同次求值的共享 native graph readiness | Each 的模板求值和输出位置持有局部 scope；父子展示约束不再回写共享 Button/ActionPlan。Swift 按值身份与 scope 投影，保留旧快照、SameValue、重复子图复用和 opaque capture | 共享 getState/native function、两种兄弟顺序、Each 闭合恢复、query scope 隔离的 JS 回归通过；bridge 与实际 `canInteract` 回归已加但未运行。纯 Lang Button/Action 别名负对照没有复现旧问题，不能泛化为所有变量复用错误 |
| complete 父节点的旧 Action metadata | `ComponentHost` 与 `isElementReady` 按当前 projection membership 刷新旧父快照；不再因父节点自身 complete 而跳过内部 Action 更新。语义匹配存在不同 readiness 候选时继续保守处理 | 已补同一文档中保留旧 Context、依赖完成后恢复交互的回归，原生待运行；不依赖重挂载来修正旧快照 |
| Stack/Card 的扩展组件身份 | 标准容器将实际 `context.registry` 传给 children/identity 解析，使扩展组件的 `identityFields` 生效 | 已补真正挂入 Stack/Card 的重排与身份回归，原生待运行；不将 helper 单测视为 mounted 通过 |
| Query 通知的内部投递合并 | 每个订阅至多保留一个等待 MainActor 执行的更新任务，执行时读取最新 manager snapshot；退休订阅使排队更新失效。Query 调度、工具完成和对外业务回调仍由原路径负责 | 已补队列与 State 发布回归，原生待运行；只合并该内部呈现投递，不改同步 push 契约，也不保证不同时间到达的所有通知只产生一次 root 更新 |
| Gallery 预览挂载与持有范围 | 预览 pager 只挂载当前页及相邻各一页，缩略条使用 LazyHStack，离屏缩略图释放本地 phase；移除父层持有全图库图片的字典，页面持有随挂载窗口变化 | 已补窗口、请求与资源回归；实际 mounted 请求数、关闭释放和内存峰值均待原生测量。共享缓存上限仍不能代表整个 App 的图片内存上限 |
| OpenUI 大图像素升级 | 内联图可作为打开预览的初始像素，按 viewport、scale、zoom 与宿主 cap 请求后续尺寸；保留更高像素结果，尺寸升级期间可继续显示已接受图像，并验证资源/授权/重试归属 | 高清升级、低清先到/高清后到与资源变化回归已加入；尚无原生像素、清晰度或请求测量结果 |
| IntelligentUI 预览签名快照 | 稳定 source/owner/retry 沿用解析后的 request snapshot；以宿主 cap 后的有效像素决定尺寸档，避免等效尺寸因重复签名产生不同请求 | nonce 签名及 cap 回归已加入，尚未运行；不能以源码变化关闭用户报告的三项 signed media 失败 |
| 同源远程 SVG 重试 | 可重试的网络/内容失败显示重试操作，增加 attempt 并重新请求同一 source；保留 readiness、授权和目标存活检查，无效请求不绕过既有校验 | 首次失败、同节点重试恢复的原生回归已加入，未执行；此修复与用户 SVG 拖动像素失败属于不同验收 |

最终生成资源已执行 **96/96** 项 `node --test Tools/Core/native-*.test.mjs`，**0 failed、0 skipped**。其中包含该轮 49 项定向集合；49 是全量的子集，不能相加。独立 `verify-compatibility` 另执行 **51 parser、5 action、4 Query、6 serializer round-trip、21 Lang 1.1**，`unexplainedDifferences=0`。对照使用未应用原生补丁的固定官方源码；没有修改历史业务 fixture 来接受漂移。日志位于忽略的 `outputs/kernel-repair-native-tests.log` 与 `outputs/kernel-repair-compatibility.log`。

| 其他该轮检查 | 结果与边界 |
| --- | --- |
| Validation 与 catalog compatibility | 13/13 PASS，0 failed、0 skipped；覆盖契约、输入验证及目录兼容性。日志为 `outputs/kernel-repair-contract-tests.log`，不代表原生界面通过 |
| 源码与所有权检查 | PASS；确认源码职责/归属约束，属于静态检查，不是 Swift 编译或并发时序测试 |
| Gallery 目录完整性检查 | PASS；确认目录完整性，不代表 Gallery 的窗口、拖动、图片升级或内存已通过原生验收 |
| 本地化与文档链接 | PASS；检查既有资源键、调用位置与修改文档的本地链接 |
| 该轮 GitHub Actions 原生流水线 | BLOCKED；已对代码提交 `5f4ed69b0eb7815e07704fc36f12449c6caa4db9` 的新分支手动触发 [run 43815639524](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/43815639524)。两个前置任务的 runner/steps 均为空，页面明确提示账户付款或支出限额阻止启动；`native-sdk` 为 skipped，未进入 Swift 编译/XCTest，不能视为源码测试失败或通过 |

该轮 `lang-core.js` SHA-256 为 `ebabf51a466bc64aa250579397ffa635332ac8153d0867b28f26fb6528b293a8`，`core-manifest.json` SHA-256 为 `4cd06294b0bd03e903848cf1d9bcc62407f2751fd5e3adfbf2813468376f1fb8`。bundle、manifest 与适配清单由固定输入重新生成。预算新增参数和 readiness scope 仅存在于私有 SwiftCore bridge，不要求客户端采用新的 Lang 语法、公开参数或调用方式。

**该轮全部 Swift/XCTest 均未编译、未执行，所有媒体原生测试待验收。** 新增 `MountedStreamingTextProgressTests` 挂载真实 NSHostingView/OpenUIContentView，先显示半句 plain heading 与 Markdown，补全字段后继续用现有 push 追加无关节点约三秒，并从 AppKit accessibility 控件断言 done 前已出现完整文本。这只是已写入的回归，不是本环境的运行结果，更不是 Muse 回放、像素或 FPS 验收。旧 Slider 的 `testDraftFeedbackRefreshDoesNotFlushWritesOrRequestFocus` 已迁入现有测试文件，同样待执行。

### 原生文本流中停滞

2026-11-16 依据客户端提供的调试记录继续检查原有 `fix/kernel-stability-20261116` 分支（修正前为 `2a0201b`，文本代码与 `bdac1bf` 一致）：`source` 已是 `SHANGHAI → SUZHOU · 2 DAYS`，而 `NativeStreamingTextBuffer.received/displayed` 仍为 `SHANGHAI → SUZH`。记录来自客户端，本次未重新运行该 App 或原始回放。

确定的源码缺陷位于 `NativeMarkdownText`：单参数 `onChange(of:perform:)` 忽略传入的新值，改读闭包捕获的旧 `text`。该 API 的[闭包语义](https://developer.apple.com/documentation/swiftui/view/onchange(of:perform:))使 A → AB 的更新再次交付 A；若该字段不再变化，即使其它节点继续生成，也不会补交 AB，直到停止流式时才绕过旧显示值。这条路径与记录相符；单次断点本身不足以证明全部实际时序。

修正将文字的精确 UTF-16 值与流式状态组成私有输入，并由一个变化回调消费新参数，避免同帧变化时两个回调混用新旧值。保留 iOS 16 / macOS 13 支持、48ms 呈现合并、只读尺寸拟合和现有 Markdown 工作队列；不修改 parser、公共状态入口或客户端调用方式。

`MountedStreamingTextProgressTests` 在既有挂载回归上扩展为 4 项 XCTest、6 个场景，使用实际挂载的文本和标准 `OpenUIState.push` 路径，覆盖目标字段完成后其它节点继续生成、文字与流式状态同帧变化，以及最终分片紧接 `complete` / `interrupt`。验收必须确认缓冲和 Markdown 准备都收到完整文字、界面在 `complete` 之前更新；一次性输入完整程序或仅在流结束后检查正确文字不能替代该项。既有 `StreamingTextPresentationTests` 的无副作用读取和合并约束保留。

本次源码/所有权检查与 `git diff --check` 通过；`swift test` 实际因环境找不到 `swift` 返回 127，原生 XCTest 与客户端分块回放尚未执行，不能将源码修正称为 App 验收通过。执行结果与环境阻塞记录在忽略的 `outputs/verification/native-text-sync/`，不另建并行报告。

### a4808be 合入时的内核修复与验证

前轮内核修复已通过 `3310e3d8` 合入当时最新 main，并保留同期 UI 改动。以下记录修复客户端 `c7310054` 定向审查问题、最终合入 `a4808be3` 的这一轮：生产改动限于 SwiftLang 语言/运行时及 Core 适配，未修改组件库视觉、历史 fixture、`push / complete / interrupt` 或业务回调协议。该轮新增 19 个 XCTest 方法；合入时，本环境没有编译运行这些新增项及前轮 29 项，后续客户端编译结果另记于下一节。

| 问题 | 实际修复及回归边界 |
| --- | --- |
| 旧 Query 结果污染同名同 key 的新请求 | 以已有 cache entry 身份及当前消费者判定有效性；success、error、finally 和原生 provider 入口/返回统一遵守。受控 Promise 回归在旧 `c7310054` 资源中复现旧失败清掉新 loading、带入旧 error 等问题；修复后通过 |
| 共享请求状态与缓存恢复不一致 | 原声明移除或改参后，其他消费者仍接收有效共享结果；loading、refetching、错误与旧缓存引用一起更新。成功缓存命中也清理旧错误；多消费者 invalidate 只形成一个待刷新请求，dispose 自身生成停止加载的末态快照。清理统一在完整节点批次之后决定，保留同批接手和有效 fallback，移除连续改参后无消费者的旧缓存 |
| 旧请求长期不返回时持续积压 | 声明完整评估以及工具结果触发的 reader 重算结束后，整批移除已经失效的原生 pending，先 reject 全部旧 Promise，再向 Task 发取消，避免同步取消处理器重新消费未退休的旧条目；不在节点更新中途通知时清理。新增连续改参/删除、共享消费者、跨 ID key 交换、自动 reader 更新及双请求取消重入 5 项回归；原生未运行。库不能强制停止 provider 自身不响应取消的工作 |
| 旧超大结果或错误停止新文档 | Swift 返回阶段先复核请求，再扫描 Value、读取 Error 描述或编码。旧结果直接结束原 Promise；当前请求仍受完整预算约束。新增改参、删除再建立、共享消费者和旧错误描述零读取回归；原生未运行 |
| 错误负载和 MCP 提取绕过预算 | MCP 文本、普通 Error 描述、ToolNotFound 名称及名单在 JS 分配前检查总量；MCP 原始 JSON 先预检，文本展开后再验图预算。沿用既有错误渠道，正常错误类型/文本不变，Mutation 等待者能结束。当前超限及普通错误的原生回归未运行；MCP 展开拒绝在 JS 中已执行 |
| 合法深度边界静默截断 | 256 层容器后的标量在 JS 预算内，原 Swift guard 却先返回 null。现在先解标量，再限制继续展开的容器；新增 256 层 number/bool/string/null 保值与 257 层拒绝回归。JS 接受边界已验证，Swift 保值回归未运行 |
| 同代已移除组件的旧写入与动作 | revision 不变时也必须属于当前 live tree；绑定、字段及初始化在实际排队执行时复核目标。保留 partial 呈现开关、公开 Host 写入、相同 props 的最新 readiness 和有效动作自移除后的后续步骤；对应 7 项原生回归待运行 |
| 直接绑定往返后改变内部类型 | ReactiveAssign 缓存命中使用与首次解码相同的分类；直接 `$value` 仍为 binding，真实表达式仍为 reactiveBinding。新增首次/缓存及 Store 往返的类型、值和身份回归，原生未运行 |
| 取消任务中的 legacy 动作仍派发 | triggerAction 的公共执行入口检查 Task 取消，覆盖 legacy、plan 和默认动作；取消后的外部事件不能继续发送，正常动作不变，原生回归未运行 |
| Lang 解析重复投影未使用的消息 context | Parser 和 StreamParser 只读取共享消息解析器选中的 content，避免逐块创建无用 Swift JSONValue。公开 parseMessage 保留完整 context；新增桥接枚举计数回归，原生未运行。未改消息协议，也未移除 JS 对 context 的解析 |
| 普通 Lang 注释/字符串被误认成帧 | batch/set/push 共用增量 UTF-16 边界探测，首次真实帧前的引号、转义及行注释受保护；同一个消息算法继续处理真实封包与重试。新增 5 项实际 bundle 回归通过，4 项 Swift 回归待运行。原始 raw marker fixture 保留，纠正了用协议选帧器吞掉 raw 字符串再作为预期的旧 oracle；framed oracle 不变 |
| applyPatch 原始输入与合并成本无上限 | 原始 existing/patch/rootId 在合并前各自检查，合并共用累计 work 及输出预算；原始 2,097,169 UTF-16 patch 从接受 after 改为 `limitExceeded=true,value=null,work=0`。底层 mergeStatements 原位 throws，不保留静默兼容入口；applyPatch 保留原签名、最后有效 root/Store 与恢复行为。8 项 merge/split JS 回归通过，9 项新增 Swift 回归待运行 |
| 平铺大程序逐分片重扫整份源码 | 使用解析器已产生的 tokens 和 completed 声明计数，在递归前检查原有限额。旧全前缀预检已删除；重复 ID、pending 重读、fence/reset、精确 token 上限及恢复有回归。新增 5 项 source-budget JS 回归通过，相关 Swift 项待运行 |
| 多行三元式换行扫描为平方级 | 同次 split 复用下一非换行位置；2000 换行的 token 索引读取从 2,007,023 降到 10,022，结果仍是同一合法表达式。线性访问上界及两个独立上游语义对照通过 |
| 稳定 readiness 重复分配与跨桥属性读取 | 只共享冻结、无依赖的 open/closed 描述，Swift 直接识别；含 Query、observed、scope、slots、placeholder 的元数据仍完整投影。移除重复 identity 桥接调用并缓存只读 exports。4 项 JS 计数/语义回归通过；没有跨 push 缓存可能变化的 Lang 物化对象 |
| 一次普通 push 两次整 State 通知 | presentationRoot 随 root 同次发布，保留公开 `$root`；尾部文字即时更新及 delimiter-only readiness 均有新增原生回归。两个 Swift 测试尚未执行，不能把源码次数推导当原生计数；共享 ComponentHost 订阅仍存在 |
| 原生测试目标 String/OpenUIString 错误 | ActionWorkBudgetTests 的多字段 formState 显式构造 OpenUIString，保留全部事件/预算断言。源码类型修正已完成，原生 target 是否还有其他编译问题仍须 Swift 构建确认 |

合入 `a4808be3` 时，本环境实际执行结果：

| 检查 | 结果与限制 |
| --- | --- |
| 正式 Core 生成 | PASS；固定上游、锁文件及生成器生成 bundle/manifest，新增适配来源同步。对最终正式资源重新运行全套 JS 回归 |
| Core 全套 JS 回归 | **141/141 PASS，0 failed、0 skipped**；包含前轮 119 项与本轮 22 项，子集数字不相加。覆盖 Query、MCP、真实分片、预算、readiness、原始消息边界与 merge |
| 旧资源反证 | 旧 `c7310054` 的 Query 定向 **5 pass / 10 fail**；MCP 原 5 项 **1 pass / 4 fail**。相同用例在修复资源均通过。追加缓存清理回归在本轮前一候选 `39df813e…` 上为 22 项中的 4 项失败，最终资源已通过；新增合法深度对照不是旧失败案例 |
| 独立兼容性 | PASS：51 parser、5 action、4 Query、6 serializer round-trip、21 Lang 1.1，另有 2 个独立 split/merge 对照，`unexplainedDifferences=0`。固定对照源码与历史 fixture 预期未改 |
| 源码/所有权与 diff | `check_openui_integration.py` 和 `git diff --check` PASS；仅说明静态范围和格式 |
| Swift 与完整模块图 | BLOCKED；本机 `swift test` 返回 127（找不到 swift），`check_module_boundaries.py` 同样无法取得 SwiftPM 模块图。新增/既有 XCTest 均未在本次运行 |
| GitHub 原生门禁 | 合并版本 `a4808be3` 的 [run 43830544843](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/43830544843) 两个前置任务均失败且 steps 为空，native-sdk 为 skipped；未进入原生构建，不能当测试通过。本条只记录该版本的实际结果，不将其他历史流水线的阻塞原因归到本次 |
| App、Release、设备性能 | 合入时未在本环境执行；后续客户端针对 `a4808be3` 的 App Debug / 独立 Release 复测见下一节，仍不能据此关闭实际分块回放、帧率或长期内存验收 |

`a4808be3` 的 `lang-core.js` SHA-256 为 `842e71ddeee6d73a7c04df90f9c80f01ca43f504de2495e448047b7a75004e16`；`core-manifest.json` SHA-256 为 `0f6cb4bfc02b8442ae1e9f1c7d61678a4ecaaa75b0dc5ffeb19b2c023cfc8335`。该轮正式构建/全量/独立对照在忽略的 `outputs/client-audit/`；前后工作计数在 `outputs/kernel-client-performance/`，原始 patch 与 split 反证在 `outputs/client-patch-budget-build/`，前轮证据仍保留在 `outputs/kernel-followup/`。Swift 未执行的项目仍是验收缺口，不以 JS 或静态检查替代。

### 客户端 a4808be 定向复测（2026-11-16）

以下由用户提供，日期采用 Asia/Shanghai。新版固定为 `a4808be333598bb15a6990f47eeb0d23c930c1dd`，旧版为 `c7310054e5a58ecb7e42e9f37e4c77e7fed30ce7`。客户端未修改 SDK/Host 实现或历史 fixture，也未运行全量测试、提交或发布。本文记录报告中的实测值；原始 Mac 日志、JSON、sample 和图像未在本环境取得或重新执行，不能将其写成本环境独立复现。

**功能与原生门禁。** 外部消费者复用上一轮完全相同的 19 项公开 API 探针，仅更换固定 SDK checkout，结果为 **19/19 通过**：

| 检查 | c7310054 | a4808be3 |
| --- | --- | --- |
| 普通注释含 content 标记 | root 消失、无错误 | batch / stream / State 均保留 `kept` |
| 多行字符串含 content 标记 | root 消失、无错误 | batch / stream / State 均保留原文字 |
| 2,097,169 UTF-16 units 的原始 patch | 超过 1,048,576 上限仍提交 `after` | 约 1.78ms 拒绝，保留 `before`，`isInterrupted=true` 并返回预算错误 |
| 其余 16 项 | 通过 | 通过；覆盖 Unicode 分片、重试帧、pristine、重入、预算原子恢复、取消、表单输出及旧 Query / 下游派发隔离 |

这些是有限场景，不代表所有竞争组合。App Debug 构建通过；SDK 官方定向 XCTest 在执行前编译失败：`Tests/SwiftLangTests/FramedStreamingTests.swift:127` 将原始 parser 的 `ElementNode` 传给只接受 `EvaluatedElement` 的 `PropValue.string`。上一轮 `ActionWorkBudgetTests.swift:97` 的错误已修复，但此次选中的剥帧、patch 预算、单次发布和挂载文字进度用例均未执行，19 项外部探针不能替代原生门禁。报告引用 `public-probe-results.json`、`PublicProbe/Sources/PublicProbe/main.swift` 和 `targeted-sdk-tests.log`。

**独立 Release benchmark。** 同一机器、工具链和现有 LanguageBenchmark 源码，节点、分片、预热与测量配置保持一致；61 节点流式测量 3 次，201 节点 2 次。以下节点标签沿用客户端报告。消费者没有 SwiftUI 视图或网络等待，数值表示同步计算，不是帧率或模型延迟。

| 节点 / 每块 UTF-16 units | push p95（ms）旧 → 新 | 整条流计算 p50（ms）旧 → 新 | 每条流发布次数旧 → 新 |
| --- | ---: | ---: | ---: |
| 61 / 24 | 5.60 → 4.51 | 490.67 → 376.72 | 385 → 195 |
| 61 / 128 | 5.81 → 3.84 | 119.97 → 79.79 | 75 → 38 |
| 201 / 24 | 35.06 → 20.60 | 4628.50 → 3412.48 | 915 → 462 |
| 201 / 128 | 15.31 → 10.19 | 608.54 → 455.18 | 177 → 91 |

额外一次紧邻的旧/新 201 节点、24-unit 对照，push p95 为 32.95 → 19.15ms，整流计算 p50 为 4348.30 → 3095.48ms，方向一致；样本仍少，未做显著性推断。**长尾未收敛：** 主测和紧邻对照的新版本最大单次 push 分别约 102.35ms、79.89ms，对应旧版为 63.06ms、46.38ms。不能只报告 p95 改善，也不能仅凭最大值归因于 GC 或某个缓存。201 / 24 的 p95 仍约 20ms，尚未计入 UI 布局绘制。

发布次数接近减半与 readiness 不再单独 Published 的机制一致，但不等于 SwiftUI body 或 App CPU 减半。报告引用 `comparison.json`、`benchmark-*.json`、`paired-c731005-200rows-chunk24.json` 和 `paired-a4808be-200rows-chunk24.json`；测量期间没有并行编译或运行其他本任务 benchmark。

**实际 App 被动流。** 使用同一独立模拟器 `5ACEAD69-A401-4DD3-BBD0-0D8D9C04BD9C`、正常动画、Debug 包，以及原行程源码 SHA-256 `d6728e6104c9a218a20c1511eff72852f155bd9c269c34f2d6efc314dd3856be`，按 24 字符 / 80ms 回放。新版 PID 为 4621；发送后至采样结束没有 UI 查询、截图、手势、录屏或 LLDB。服务器流约 39.10 秒，CPU 计数覆盖完整流；55 秒 sample 包含流前空闲、完整流和少量流后时间，采样自身有开销。

| 指标 | c7310054 前轮 | a4808be3 本轮 |
| --- | ---: | ---: |
| 流中平均进程 CPU（单核心 = 100%） | 94.13% | 92.79% |
| CPU p95 | 117.16% | 112.94% |
| 250ms 峰值 | 146.01% | 145.11% |
| App footprint 峰值 | 189.39 MiB | 189.64 MiB |

每版仅一次被动流，差异很小，未建立 App CPU 有实质降低的结论。进程 CPU 包含后台线程；footprint 不含独立 WebKit，不能据此判断泄漏。新版包含同期组件视觉与排版改动，CPU 差异不能全部归因于内核。符号化样本仍见 SwiftUI/AttributeGraph、类型元数据和 ARC 工作；两次同步发布可能被 SwiftUI 合并在同一更新周期内，实际视图失效与布局成本仍需独立计数。部分 PLCrashReporter DWARF 解析有警告，报告称第一方 Swift 源路径可定位。该复测不是 Release App、真机、持续滚动或 FPS 验收，也没有新发真实模型请求。

报告引用 `passive-metrics.json`、`passive-process.jsonl`、`passive.sample.txt`、`passive-sample-analysis.json` 和 `final-ui.png`。App 构建沿用命令行 iOS 18 编译目标覆盖以处理本地 Network 模块最低版本冲突，未修改源码最低系统配置；不能把这次构建解释成所有最低部署目标均已验证。Muse 不直接调用已改为 `throws` 的 `mergeStatements`，本次无需修改其调用代码；其他直接使用该 helper 的消费者需处理异常，现有 `push / complete / interrupt` 接入继续使用。收尾恢复真实本地 3002/3003，只停止本次拥有的回放服务。

### a4808be 复测后的流式成本修复

本轮从仅修订文档的 `ae5c6bb249a6ab76b7cc27813004a25a7eb3dedd` 建立独立分支 `fix/kernel-streaming-cost-20261116`。实现保留同步 `push / complete / interrupt`、公开发布和业务回调，未添加客户端流句柄、兼容开关或第二套运行引擎；组件视觉及历史 fixture 未修改。以下是实现与本环境验证状态，不能用上节客户端 `a4808be3` 的 19/19 或性能数据作为本轮结果。

| 项目 | 本轮处理 | 验证与限制 |
| --- | --- | --- |
| XCTest 类型错误 | `FramedStreamingTests` 从 raw parser 的 ElementNode 属性中解包原始字符串，再与原生公开入口比较；不将 AST 当 EvaluatedElement | 两份原始输入的 JS oracle 已检查；没有删除断言。Swift 编译未执行，不能写原生门禁通过 |
| 组件内容更新 | Host 保留最近 EnvironmentObject，在内部内容及注册 builder 边界比较完整呈现输入；标量 SameValue、引用严格身份，不递归遍历业务树 | 新增稳定尾部、实际 Markdown、字段默认值/编辑、Query、readiness、旧节点移除、嵌套 State 和父闭包/环境挂载回归；全部待原生执行 |
| 非 props 的组件依赖 | 真实 Store、Query/Mutation、完成、中断、文档替换驱动内部通知；同步事务结束后交付，Context 带本次 revision | 无业务状态副本，无普通文字分片的无条件辅助广播。ActionSurface、原生字段及 EditableTable 仍保留直接挂载所需订阅，既有测试不改 |
| 匿名节点搜索 | 仅为匿名 scalar 属性建立细分候选桶，保留具名/复杂节点分组和最终歧义检查 | 新增 200 个匿名节点候选计数、NaN/零、精确字符串及 canonical 属性名/readiness 歧义回归；不是设备耗时结果 |
| JS/Swift 投影桥接 | 保留身份/scope 缓存早返回；未命中时成组读取类型/子 scope 及元素源状态，有序属性键值一次读取；删除旧单属性 get、keys/kind 私有路径 | 实际 bundle 的四项新 JS 桥接回归通过；Swift 桥接及跨 64 轮调用的旧值/ActionPlan/Store 生命周期回归待执行。不改变 Lang 对象身份或旧快照 |
| Query 呈现读取 | 同次呈现读取一次管理器快照和错误数组，按声明返回 QueryState | 真实 JS manager 的 Swift 读取模式重放中，10/20/40 个 Query 的错误项读取由 100/400/1600 降为 10/20/40，值一致；这是工作次数，不是原生时间。三项真实 Swift manager 回归待执行 |
| 临时桥接对象与长调用 | 最外层串行桥接结束时释放 autorelease 临时包装；新增解析、求值、投影、live index、桥接与弱引用清理的 Instruments intervals；benchmark 增加最慢 10 次 push 的分片位置 | 未改计时循环和工作负载；未将长尾归因于 GC，未宣布最大 push 已下降。需要 Apple 同负载采样 |

试验中的跨分片物化缓存没有进入生产实现。实际 bundle 的 200 rows、24-unit 分片中，200 个稳定叶子累计形成 48,404 个不同的 JS 元素对象；这解释了桥接重复工作，却不允许按 AST 直接复用结果。反例显示简单复用会改写旧 readiness，收窄后的缓存仍会改变真实 Lang 引用比较；即使既有 JS 回归通过，也不满足保留语义的要求。生产仅批量读取元数据并在原生视图输入边界过滤，不把实验缓存或回退开关保留下来。

本环境实际执行：

| 检查 | 结果 |
| --- | --- |
| 固定输入重建两次 | bundle 与 manifest 逐字一致 |
| Core 全套 JS 回归 | **145/145 PASS，0 failed、0 skipped**；包括新增四项，不与子集相加 |
| 独立语义对照 | 51 parser、5 action、4 Query、6 serializer、21 Lang 1.1.1、2 merge 对照；unexplainedDifferences 为 0 |
| 来源与模块使用静态检查 | `check_openui_integration.py` PASS，仅 source/ownership；`git diff --check` 通过 |
| XCTest / SwiftPM 模块图 | `swift test` 实际尝试因无 Swift 命令退出 127；`check_module_boundaries.py` 也因无法运行 Swift dump-package 阻塞。新增 24 项原生用例、历史全量和 Release 基准均未执行 |
| 实际 App / 设备性能 | 本轮未运行；上节 92.79% CPU 和 79.89–102.35ms 最大 push 仍是未关闭的基线，不能改写为本轮已解决 |

本轮 `lang-core.js` SHA-256 为 `a949bbb8ad880dba88a8ed7a09ccf2d50cb3c3194f38f7872d19daf041108a6b`；`core-manifest.json` SHA-256 为 `28db6d2f94130665a62108abbd6c1af8c6449bab37e4a9883b76d9b7b6e7893c`。正式资源由工具生成。日志、资源复建哈希、Query 读取计数和未采用的物化反例保留于忽略的 `outputs/kernel-streaming-cost/`，不建立第二份验收说明。

本轮原生验收先运行全量 `swift test`；定向失败排查包含 `FramedStreamingTests`、`ProjectionBridgeTests`、`QuerySnapshotBridgeTests`、`ComponentRenderInputTests`、`StreamingRenderIsolationTests`、`LiveElementIndexTests`、`MountedStreamingTextProgressTests` 及原有 `NativeActionRenderingTests`、字段和 EditableTable 挂载用例。通过后复跑同机 Release 24/128-unit 基准，同时交付 p95、最大值、slowestPushes 和阶段 trace，再以相同行程回放验证进程 CPU、可见文本及交互；标准命令见 [LanguageRuntime](../Benchmarks/LanguageRuntime/README.md)。

### cf8d2ad 基线的呈现提交与节点订阅

本轮从 `cf8d2add05ded01f7046fbf3ac82de54e0f00f83` 建立独立分支 `codex/streaming-commit-boundaries`。基线包含此前类型修复及桥接/渲染边界修改，也包含恢复的 OpenUI 字体与呈现设计。本轮只修改共享原生运行时、相关回归及 CI，不改组件视觉、Lang 资源、公开流式入口或历史 fixture。

| 范围 | 实现及待验证合同 |
| --- | --- |
| 内部完整提交 | `NativePresentationCommit` 汇总 root、readiness、revision、执行/完成/中断状态、Query/Mutation、错误及 Store 只读值。公开 Published 和逐步业务回调不改顺序；原生 setter 及节点通知受同一重入队列保护 |
| 节点依赖 | 每个挂载边界持有弱注册的订阅，记录实际字段与 Binding 读取；无关字段写入不应重新构造该节点。旧读取作用域和最近 State 切换不能污染新订阅；completion、interrupt、readiness、Query 与预算失败仍送达 |
| 动态读取与动作 | Context 的 props/标志属于构造时快照，字段/Binding 每次读取最新完整提交，延后首次 getter 也能得到当前值。动作和写入保持当前文档与节点的安全复核，不把旧 Context 当作冻结的业务事务 |
| 当前树索引 | 保留一次当前图遍历及候选顺序，按候选身份/顺序产生变化键。没有把旧节点与值相等的新 Lang 对象合并，没有永久 DAG/refcount 缓存；整树工作仍是开放成本 |
| 回归与 CI | 新增 `NativePresentationCommitTests`、`NativeComponentSubscriptionTests`、`NativeLiveElementUpdateTests`，扩展 `StreamingRenderIsolationTests`；CI 保留全量 XCTest 与 Release fitting，补 Release 流式/提交/订阅子集及严格汇总 job |

索引方案已按实际输入收紧：对随包 bundle 的 50 次普通文字分片做对象身份计数时，稳定叶子、root 和 children 数组每次都形成新 JS 对象，稳定身份命中均为 0/50。这只是 JS 对象身份的证据，没有测 Swift 投影身份或设备耗时；它足以否定“普通流必然共享稳定子树”的优化前提。人工复用 600 个原生节点的计数不能证明真实流的收益，因此未保留基于该前提的复杂增量索引。脚本与原始 JSON 位于忽略的 `outputs/streaming-commit-boundaries/`；正式 bundle 未修改。

| 实际检查 | 结果 |
| --- | --- |
| 来源/所有权 | `check_openui_integration.py` 通过，仅 source/ownership；bundle SHA-256 仍为 `a949bbb8ad880dba88a8ed7a09ccf2d50cb3c3194f38f7872d19daf041108a6b` |
| 差异与文档 | tracked 与新增文件的空白检查通过；修改文档的本地链接目标存在；语言实现、资源、组件视觉、历史 fixture 和 Package 输入均未改动 |
| CI 脚本 | YAML 与新增 shell 语法通过；六个 Release 过滤器对应实际测试类。汇总脚本验证 125 种状态组合，仅全 success 放行，3 个缺值负例均拒绝；没有因此执行原生测试 |
| `swift test` | 实际尝试因无 `swift` 退出 127；新增和既有 XCTest 均未执行，尚未确认 Swift 编译通过 |
| SwiftPM 模块图 | `check_module_boundaries.py` 因不能执行 `swift package dump-package` 阻塞，不能记为通过 |
| Release / 实际 App | 本轮没有 Apple 运行环境，没有新增 CPU、帧率、push 延迟或挂载计数结果；既有 92.79% CPU 和 79.89–102.35ms 最大 push 仍未关闭 |

本轮基线的 [run 43840534488](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/43840534488) 中，`reproducible-inputs` 与 `dependency-security` 均失败、steps 为空，runner 未分配，`native-sdk` 为 skipped。未取得能解释本次启动失败的日志或 annotation，不能将历史账单/额度阻塞原因直接归到该 run。新增汇总只明确表达未验收状态，不修复 GitHub runner 的启动条件，也未更改仓库分支保护。执行日志保留于 `outputs/streaming-commit-boundaries/` 和 `outputs/verification/ci-boundaries.log`。

本轮新增 33 项原生回归：完整提交 8 项、节点订阅 11 项、索引更新 12 项、实际挂载 2 项，全部待执行。下一次原生执行先跑完整 `swift test`，再运行 CI 中的 Release fitting 与流式子集；通过后用相同 24/128-unit、201 节点负载比较新增提交、索引变化键和订阅检查的成本，确认没有因边界更清晰而增加长调用。旧版本已有 `.equatable()` 输入过滤，新增节点订阅不能仅凭源码被当作 App CPU 改善。

### 内核职责与失败边界清理

本轮核对 main 仍为 `cf8d2add05ded01f7046fbf3ac82de54e0f00f83` 后，新建 `codex/kernel-clarity-audit`，接入已推送的前一候选 `fe81f250b016704997eaee85945bba7e6338b9dd`。审查覆盖自有 Language、Runtime、Core 适配和正则 C 桥接；第三方内核与正则 vendor 继续使用锁定来源。组件视觉、原始模型输入、历史 fixture 与公开 `push / complete / interrupt` 接入保留。

| 确认的问题 | 当前实现 |
| --- | --- |
| legacy action 绕过计划执行器的预算 | 原始 object、message、formName 以及合成后的 params / formState 共用一次动作工作预算；超限在 receipt 和业务事件之前停止 |
| 逃逸 JS 异常在 Release 桥接中可能变成 undefined | 正式 bounded 入口及自动 Query reader 产生携因失败；Evaluator、QueryManager、State 使用同一 `NativeExecutionFailure` 交接。原 `.budget` 通道与 `.runtime(OpenUIError)` 区分，公开 `nativeLimitExceeded` 仅对预算为 true；首错退休、等待结束和最后有效呈现保留 |
| 正常表达式诊断与致命异常容易混淆 | 官方已处理的 root prop / 自定义函数诊断保留可恢复语义；State 动作表达式的致命失败在写 Store、下一步工具和事件之前停止。Query 初始批次与异步 reader 同时覆盖 |
| MCP 非法 envelope 直接抛出 TypeError | 原有提取 catch 统一返回明确错误，由既有 Swift `throws MCPToolError` 交付；正常原始文本、structuredContent 与业务 MCP 错误保留 |
| 错误负载成为额外分配通道 | 自定义 Error 文本在 JS 分配前预检；reportError 与 root diagnostics 计入当前操作预算。解析结果的预算标记直接关联单条有界诊断，Swift 在投影错误列表、unresolved、root 或默认值之前检查失败标记 |
| Store 把写入判为 no-op，原生成本却换成候选值 | 私有 set 入口读取实际 snapshot 身份变化；真实 no-op 保留原值成本与新 pristine，真实通知中发生的重入写入继续拥有最终账本。没有复制另一套浅相等规则 |
| 错误去重遗漏字段并规范化 Unicode | 统一按全部错误字段及原始 UTF-16 比较；删除 NUL 拼接指纹，保留相同错误去重、恢复清空和回调重入顺序 |
| 资源完成与取消 / 换代相邻时缺少返回检查 | 字节 Store 在 await 返回后检查订阅取消及 epoch；像素缓存命中前与异步返回后检查 loader 身份和当前鉴权 scope，仍允许其他有效订阅取得共享结果 |
| 内部广播、revision、转换和入口重复 | 删除没有生产消费者的协调器 publisher、每节点与读作用域的重复 revision、索引第二清空入口、仅旧 JS 测试使用的非 bounded 包装，以及死的 materialized 转换和字符串比较转发。Parser 工厂与实现归同一文件，删除 API.swift；AST 直接编码，authoring 每组参数只编译一次 schema，删除未使用 registry |
| 普通候选分支不会触发原生 CI | push 选择 main、codex/**、refactor/**，PR 覆盖所有目标分支；保留严格汇总，并扩展 Release 到错误、Store、Query、Action、资源及流式边界。配置存在不等于 runner 已运行或原生通过 |

**已取得的旧资源反证。** 正式旧 bundle `a949bbb8ad880dba88a8ed7a09ccf2d50cb3c3194f38f7872d19daf041108a6b` 上，`extract(null)` / 非数组 content 可逃逸 TypeError；普通宿主对象 `{toString: 1, valueOf: 2}` 参与字符串转换时，bounded 求值与 Query 声明也可逃逸异常，且没有通过既有 reportError 交付。`root=Box([@Missing(), …])` 的 8,192 次调用只有 90,123 UTF-16 输入 units，结果已经被预算拒绝，但仍携带 8,193 条诊断、1,491,073 units 的诊断 JSON；旧 Swift 先枚举整个诊断数组再检查拒绝标记。这些是实际 JS 资源结果与 Swift 调用顺序证据，未执行 Swift 进程测量。

**回归的实际含义。** 新测试覆盖 legacy 输入 / 合成输出 / 累计动作工作、参数覆盖与回调顺序、原始 Unicode 错误变化、初始及异步 Query 致命失败、Mutation 等待结束、动作禁止写 null / 继续派发、Store 实际 no-op 与订阅重入、错误负载预算和被拒绝解析图的零枚举。节点通知测试改为观察真实节点订阅；文字分片保持零通知，收尾导致 root.partial 变化时应有一次通知。异步 root 保留测试以最后一个非失败的完整 commit 为准，不假定 provider continuation 恢复就代表 finishTool 已结束。

资源新增回归分别覆盖独立订阅取消、reset 后旧传输不能回填以及退休 scope 不能读取缓存像素。前两项控制常规生命周期，没有确定性制造 finish 恢复 continuation 后、等待方重新执行前的竞争窗口；post-await 检查是已定位的缺失边界修复，不能称为所有竞争条件已证明。退休 scope 的缓存命中可直接反证旧路径。

| 本轮最终检查 | 实际结果 |
| --- | --- |
| 正式 Core 全套 JS 回归 | **158/158 通过，0 failed、0 skipped**；针对最终生成的资源执行 |
| 独立、未适配的锁定上游对照 | 51 parser、5 action traces、4 Query snapshots、6 serializer round-trips、21 Lang 1.1、2 merge 对照；**0 unexplained differences** |
| 既有 Validation 与目录契约 | **6/6、7/7 通过**；目录检查包含全部 84 个固定组件的参数与完整签名 |
| 正常构建复现 | 同一固定上游与锁文件连续重建，JS、manifest、许可三份生成物逐字节一致；最终 JS 为 864,539 bytes，SHA-256 `8a9ecc205893d7b00868e7864000a1ff1a6c4fcf128e80ef59a0c1a3d77b6731` |
| 来源 / 所有权 | `check_openui_integration.py` 通过，仅说明 source / ownership；没有改检查器绕过验证 |
| 原生回归数量 | 净增 **21 项 XCTest**；另 3 个旧方法因移除广播 / 第二清空入口而迁移名称与观察对象，保留行为断言。全部尚未原生执行 |

**原生状态仍为未验收。** 本环境实际尝试完整 `swift test` 和 Release 的 `HostSizingIsolationTests | RuntimeHostIsolationTests`，均因找不到 swift 返回 127；模块图脚本因不能执行 `swift package dump-package` 失败。新增及既有 XCTest 尚未在本轮编译 / 执行。交叉源码复核纠正了一个无法合成 Equatable 的内部失败类型声明，并校准了异步测试观测时机；这些复核不能替代 Swift 编译。

**保留的边界。** 单一可写 Store、公开同步发布、Query 退休先结束等待再取消 Task、旧完整提交的 lazy lookup、资源字节合流与解码缓存各有职责，审查后保留。低层公开 `toString` / `toNumber` / `isLooselyEqual` 等无错误返回的工具，以及宿主自定义 `ActionRuntimeContext.evaluate`，没有因此获得一套新的通用失败合同；正式 State / Query 的执行保护不能外推到任意外部闭包或 authoring 图。宿主生成 Error.description、自定义函数自身的计算仍不可抢占。

执行证据集中保存在忽略的 `outputs/kernel-clarity-audit/`。本轮没有 Apple App 的 CPU、帧率、push 延迟或内存新结果；客户端 92.79% CPU 与 79.89–102.35ms 最大 push 的验收缺口继续保留。

### 流式重复工作收敛

本轮从已核对的 main `191c264540d4fde2ae3b05233b1c7ed47a254519` 创建 `codex/streaming-work-reduction`，保留该提交的全部组件视觉与目录变化。目标是在现有同步入口里减少重复工作；没有引入新 Store、客户端流句柄、后台执行协议或平行解析引擎。职责与保留边界见[架构](architecture.md#现有入口的性能边界与后续验证)。

| 修改 | 对应边界与验证 |
| --- | --- |
| 增量行预处理替换每次全文清理及前缀比较 | 批量、流式和公开 fence helper 共用一份规则；固定官方 oracle 验证逐 UTF-16 前缀、160 组词法碎片、围栏切换、注释/字符串与尾部空白；已消费行不重扫，未完成长行仍可重复处理 |
| 复用纯语法 metadata | 只记录已完成且无引用 AST 的闭合事实与高度；新回归保留跨轮新值、同轮 alias、声明身份、全局 partial、旧快照、自定义函数重新执行、诊断顺序与预算 reset |
| 投影 metadata 按需并成组读取 | 普通已缓存对象/数组跳过 source scope 查询；需要 metadata 的值一次取得类型、子 scope、完整性与 readiness；原有 direct/Each/旧 scope 隔离断言保留，native 类型与反向编码身份不变 |
| 函数/动作定义归文档所有 | 参数描述只准备一次；含对象或数组 default 的 params/returns/actions 每个执行 context 重新编码。原生回归明确区分同 context 默认值共享与跨 context 新身份，回调、失败观察者、工作预算和业务结果不缓存 |
| 稳定标量叶子的呈现变化与实际 membership 分开 | 唯一候选且完整呈现输入相同才省略 capture；引用属性、歧义、字段、Query、执行状态和换源保留独立判断。单候选 lookup 不再自比，深度边界仍在 |
| fallback 与字段观察收敛 | fallback 按快照身份保留最新 readiness，不发布额外更新；ActionSurface、字段、EditableTable 共用 Context 订阅。手工 Context 的 owner/epoch、派生子 Context、焦点、草稿和表格编辑记录懒创建均加入回归 |

**实际结构计数。** 使用同一既有探针工作负载，对 main 的精确 bundle 与本轮正式 bundle 分别建立独立 Node realm。先输入稳定声明与未完成尾部，再连续追加 50 次 `abc`，总计 150 UTF-16 units。只记录实际调用与对象身份，没有 Swift、JavaScriptCore、SwiftUI 或设备时间测量。

| 固定叶子数 | 全文按行切分次数：基线 → 本轮 | 切分输入累计 UTF-16 units：基线 → 本轮 | 以 Text/Stack 为键的 Map.get 次数：基线 → 本轮 |
| ---: | ---: | ---: | ---: |
| 1 | 50 → 0 | 6,375 → 0 | 1,700 → 1,500 |
| 60 | 50 → 0 | 73,325 → 0 | 45,950 → 33,950 |
| 200 | 50 → 0 | 244,325 → 0 | 150,950 → 110,950 |
| 600 | 50 → 0 | 744,325 → 0 | 450,950 → 330,950 |

零全文切分不表示零字符处理。单独的真实行消费者计数回归在 600 个稳定声明后追加同样 50 次片段，记录 50 次未完成行预览、少于 10,000 units 的行输入，没有重放完整前缀。Map 计数仅表示该工作负载中相关定义键的读取减少，不能换算为 CPU 降幅。两版固定叶子跨分片均没有保留物化对象身份；本轮仍执行完整物化/投影，不把缓存命中率当正确性目标。Query 快照序列化探针的重复工作仍在，本轮未因此关闭其开放项。

| 最终本地检查 | 实际结果 |
| --- | --- |
| 正式 Core JS 全套 | **167/167 通过，0 failed、0 skipped** |
| 独立锁定上游对照 | 51 parser、5 action、4 Query、6 serializer、21 Lang 1.1、2 merge；**0 unexplained differences** |
| Validation / 组件契约 | **6/6、7/7 通过**；保持全部 84 个固定组件的参数与完整签名 |
| 正常资源重建 | 连续重建的 JS、manifest、许可逐字节一致；JS 为 867,580 bytes，SHA-256 `3370c7cb7be0d9e7a1a60914c52547b5ae69b4c2d8f1703ebd275b7667bab485` |
| 来源与所有权 | `check_openui_integration.py` 通过；新预处理模块进入构建与检查器相同的 adapter 指纹列表 |
| 原生测试与 CI 配置 | 新增 **16 项 XCTest**，未删除旧测试方法；Release 相关子集保留原 14 类并扩为 24 类。YAML、过滤目标及 shell 静态检查通过，不代表这些测试执行通过 |
| 原生编译 / XCTest | 实际尝试 `swift test`、Release fitting、模块图及公开产品消费者，均被本环境缺少 Swift/Xcode 阻塞；未编译、未执行，不能以 JS 结果替代 |

新原生用例中，40 个由真实 `OpenUIState.push` 产生的稳定标量叶子在 4 次尾部追加中要求零订阅通知，并检查其呈现 delta 可跳过 capture；该用例尚待原生执行。即使通过，也不等于全部 SwiftUI body、布局或主线程工作为零。源码交叉复核修正了定义缓存可能复用对象默认值、旧 child Context 续期、表格 wrapper 提前创建编辑记录三处风险；这些审查不代替原生测试。

执行证据保存在忽略的 `outputs/streaming-work-reduction/`，包括精确基线资源、完整测试日志、正常重建比对及前后处理计数。现有客户端约 92.8% CPU、79.89–102.35ms 最大 push 仍未重新验收；本轮没有 Apple App CPU、帧率或最长同步调用的新结果，也没有 RC20 同环境性能对照。接下来按同一真实 App、输入、分片、动画及 Release 环境复测解析/桥接/呈现、主线程 p95/max、布局与滚动响应。

### OpenUI 图片与首次正文准备

该轮从 `ceb90cdf` 创建独立候选，最初处理 OpenUI 图片与原生 Markdown 的重复工作和恢复路径，必要的资源/诊断基础设施仍归 SwiftLang。随后根据客户端反馈，把基线的 13 项原生失败及深层数据崩溃纳入同一候选；以下分别记录实现修复、测试合同校正和待验证项。SwiftIntelligentUI、公开语言输入契约与原始 Lang fixture 保持。该轮尚未带入独立的文档资源生命周期分支；当前候选已将其基于 `1f070fe` 集成，验收单独记录在前文，不沿用图片候选的通过结果。

| 路径 | 本轮实现 | 验证目标 |
| --- | --- | --- |
| 显示像素 | 普通卡片实测宽高/倍率，解码时结合源比例及 EXIF 计算 fit/fill；未就绪不先做默认尺寸解码；原比例图片按宽度，已加载高分辨率继续复用 | 16:9、2×/3×、竖图填横卡、EXIF、fit→fill、显式→自动尺寸、变宽/变窄、同源新预算及取消 |
| 失败恢复 | 同一 pending decode 内共享最多一次暂时失败重试；每次传输/解码单独持有准入，等待时释放；冻结签名、scope 与预算 | 多消费者、取消一个/全部、退休/换账号/改限额、旧结果回填、HTTP 状态与 Retry-After、真实挂载自动成功及手动重试 |
| 失败归因 | 保留原 URLError 类型/代码，附加 HTTP 状态与预算阶段；调试日志只输出固定阶段及数值 | 区分响应字节、源像素、解码缓冲及 HTTP；无地址/凭据/任意错误文本进入日志 |
| 首次 Markdown | 后台首次 pending 时，同配置追加复用可读 fallback；中间结果照常交付，纠正与配置变化退休旧任务 | 受控 worker 的连续追加、中间进展、共享前缀纠正、配置切换、取消/重新进入；没有 prepared 的首次读取及已有 prepared 的兼容前缀读取 |

对应原生入口为 `NativeImageSizingTests`、`NativeMediaRetryTests`、`NativeMediaResourceTests`、`SignedMediaResourceTests`、`ResourceStoreTests`、`StreamingTextPresentationTests`，并保留 `MountedStreamingTextProgressTests`、`StreamingMediaRetentionTests`、`HostSizingIsolationTests` 和 `RuntimeHostIsolationTests`。图片与文字回归在全量门禁前分别执行 Debug / Release，并立即归档日志，随后执行 Release fitting 与 iOS SDK / App 构建；全量 `swift test` 在此前定向失败后仍执行，现有 Release 大组也保留全部旧类别。该顺序用于尽早取得 OpenUI 的运行和构建证据，不改变整体验收要求。

本地 Linux 没有 Swift/Xcode，原生命令实际退出 127；原生执行随后由 macOS CI 完成。首个候选 `05f0786f` 的新增测试存在 `CGSize(width: .infinity, ...)` 类型歧义，`4679be97` 显式改为 `CGFloat.infinity` 后编译通过。[该提交的完整 CI](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44033110029) 通过了独立产品消费者、Release fitting、Gallery 测试与案例、历史契约、性能工具与既有基准、iOS 16 Simulator SDK 编译及 Gallery App 构建。Debug 已观察到 691 个通过、13 个失败，随后在 Query 预算用例期间以 signal 10 中止；13 个失败 testcase 与 `ceb90cdf` 基线一致。ASan 仍有基线相同的 3 个失败 testcase 与 signal 4 中止，日志没有 AddressSanitizer 内存错误诊断。这些中止不能记作全量通过。

`4679be97` 的 Release 扩大组执行 278 项、264 项通过、14 项失败，其中最初新增的 34 项有 32 项通过；新增两项失败都落在 Signed 图片的可见像素条件。原有三项 Signed 测试同样失败，但此前 main 的全量测试在到达该类前中止，旧 Release filter 又未包含该类，不能直接把它们标成已复现的基线失败。其他扩入的 SVG 回退失败已在 main 的 Debug 日志存在。

为区分测试输入与 SDK 渲染，[独立 macOS 探针](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44038302782) 原样运行 main 与候选共同的 2×2 `NSBitmapImageRep.setColor` 造图器，并在进入 SDK 前用 ImageIO 回读。要求红、绿、蓝的三张原始 PNG 各四个像素实际全为 RGBA `(0,0,0,0)`；同尺寸、同颜色的既有 CGContext 造图路径则分别回读 `(255,0,0,255)`、`(0,255,0,255)`、`(0,0,255,255)`。原 helper 的 SHA-256 为 `82ae11797117be394556bd99ad9c100702bd879e4bf465ae89ef39a16ba4e099`，原 PNG、逐像素 JSON 与代码保留在该探针 artifact。测试造图器据此统一到既有 CGContext 路径，仍生成原先要求的 2×2 不透明主色，并增加独立颜色往返检查；原有显示、签名、请求、取消及尺寸断言全部保留。该修正不修改 SDK 生产源码或原始 Lang fixture，修正后的执行结果以对应分支流水线日志为准。

修正造图器后的 `ed6f4824` [定向日志](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44038868961) 中，Signed 全部 8 项在 Debug / Release 均通过；新增回归在 Release 为 35/35，Debug 为 34/35。Debug 额外捕获显式像素切回自动尺寸后仍停在 32px、请求数仍为 1 的问题。原尺寸监听丢弃回调的新值，再读取可能过期的 requestedPixelSize / mode / scale 捕获；实现改为在 GeometryReader 中纯计算完整目标，只观察该目标并把回调新值直接交给尺寸状态。既有断言和等待时限保持，没有把先前偶尔通过当作该问题已关闭；后续仍需复跑同一用例。两种配置共同的三项既有挂载文字失败与一项 SVG 回退失败仍保留。

检查命令、完整日志、基线对照与探针原图保存在忽略的 `outputs/verification/openui-media-responsiveness/`。默认仍下载原 src，不能把卡片像素缓冲的减少写成网络流量或 App CPU 的实测下降；测试造图器的透明像素也不能解释真实客户端的首次图片失败，该根因仍须由具体 HTTP/错误与实际限制判定。当前整体原生门禁仍未关闭，源码审查、局部通过及构建成功均不等于客户端流畅度验收。

最小客户端对照使用同一 Release App、设备、源码、节点数与图片，分别回放一次性静态和既有 24 units / 80ms 流式输入；图片再分同几何静态占位、已完成的缓存图片、冷加载三组。该控制实验保持原始 Lang，不改历史 fixture 以压低负载。各组记录被动展示和相同滚动过程的主线程占用、帧停顿、峰值内存及图片请求/解码次数。Instruments `org.openui.swiftlang` / `Runtime` 的 `Image decode`、`Markdown preparation`、`Markdown fallback` 与既有 Parse/Root evaluation/Native projection/Live index/Bridge operation 对照，可区分图片、正文准备和同步内核成本；生命周期集成已移除旧的周期 `Bridge cleanup` 区间。没有设备 trace 时不把剩余整 root 工作或屏外 shimmer 指定为当前 App 唯一根因。

### 基线原生失败的逐项核实

排查期间，远端 main 独立新增 `316dcb7` 的表格、列表和主题呈现。本候选通过正常三方合并完整保留这些改动与当前图片/Markdown 准备修复；后续 Debug/Release 前置组纳入 TableAppearance、ReadingRhythm、StreamingVisualState 和 TableMountedView，最终结果必须绑定整合后的提交，不能沿用任一父提交的通过状态。

`b41c8d00` 的后续定向执行中，新增 35 项在 Release 全通过，Debug 有 1 项卡片变宽后的解码升级失败；显式像素切回自动尺寸在两配置和额外三次 Debug 重复中通过。变宽失败没有作为随机失败忽略：尺寸观察移到加载/成功分支之外的同一个稳定边界，保留原像素、请求和签名断言，另记录实际画幅是否从 400 pt 变为 600 pt。该变更仍须同一原生回归验证。

| 问题 | 独立依据与本次处理 |
| --- | --- |
| 深层 Query 结果使测试进程中止 | 原日志只有 signal 10/4，没有可用内存错误栈。数组/对象的数据预算检查改为显式帧栈，保留全部额度、DAG 成本与循环检查；原崩溃用例不改，新增 512 KiB 工作线程上的 256/257/300 层检查及释放。后续 `1f070fe` Debug 深层前置 55/55、SwiftLang ASan 428/428 通过；`21cbb3e` 扩大后的 Debug 前置 103/103 通过，原失败用例在这些执行中未再中止 |
| 闭合组件仍不可交互、饼图初始为空 | 独立 shipped-bundle 探针确认 pending statement 被无条件标成未闭合；删除这层标记，继续使用真实 token/AST 边界。原饼图输入在旧资源中 values.closed=true 而 complete=false，新资源中已一致。未闭合字符串、数组和嵌套动作的拒绝回归保留 |
| 按钮“重挂载三次” | [原生隔离探针](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44043824471) 保留原断言，实际观测背景 GeometryReader 出现三次，而按钮边界只有一个 StateObject lifetime。布局测试改为计数持久组件身份，保留全部宽高和身份数量断言，没有改生产按钮 |
| 精确表单字段缺失 | 同一探针证实测试构造的 Input 不属于 live tree，写入按既有成员资格规则被拒绝。正例改用真实节点的公共字段 API，保留精确 form/key 和 payload 断言；另加真实解析 Unicode 字段正例及非当前节点不可写的反例，不放宽执行资格 |
| 选项列数 | `191c264` 将默认最小宽度从 200 改为 136，现有默认宽度用例要求三列。原两列稳定性用例显式设置已有宿主配置 200，保持原 raw Lang、两列、长文和身份断言，默认值不变 |
| SVG 中断后高度 | `433c2ed` 和现行 OpenUI 文档明确安静画幅及 alt 仅通过无障碍读取。旧扩高预期改为尺寸不变，并检查 Loading 转为 Unable to load graphic、完整 alt 可读及未闭合 URL 零请求；未恢复可见长说明 |
| Mutation patch 后状态 | 固定官方源码的独立构建确认原 patch 删除了不再被根引用的声明；该原始输入应没有状态项。保留取消、不等待 provider、用户编辑和旧结果隔离断言，以解析声明集合证明 nil；新增仍被根引用的声明保持 idle 对照 |
| 手工 rootExpression 无结果 | 同一官方 oracle 证明求值阶段 Comp 需要 mappedProps；手工 AST 补齐属性映射，保留原 manual 结果断言，没有另建参数映射器 |
| 临时文字尾空格 | 固定上游 preprocess 与 pending-statement trim 对未闭合前缀裁尾，闭合后保留原始尾空格。原分块不变，测试显式列出中间预览，并新增闭合尾空格到达同一挂载叶子的回归；不 trim 实际显示结果、不改固定 oracle |
| 回退快照、纯文字采集、Card 图片宽度 | 该阶段保留原断言，补充构建/更新计数、纯 SwiftUI 对照、无障碍树/截图和实际 inset；后续已取得观测路径与退出视图覆盖记录的独立证据，定位、修正及逐提交验收见[客户端复测收尾候选](#客户端复测收尾候选) |

本地实际执行 170 项 native JavaScript 回归全部通过；与未修改的固定官方源码对照完成 51 项 parser、5 项 action trace、4 项 Query snapshot、6 项 serializer、21 项 1.1.1 专项及 2 项 merge 比较，未解释差异为 0。上述两个原生测试前提的独立官方 oracle 另有 6 项断言通过。源码归属和工作流语法检查通过，模块脚本在本地仍因缺少 Swift 无法运行。CI 将深层数据和状态回归前置并立即归档，随后执行扩大的 Debug/Release 挂载组、原有全量和全部原有门禁；新增配置不代表原生检查已通过。

原始失败日志、未改 SDK 的 macOS 探针、逐像素图及官方源码对照证据保存在 `outputs/verification/openui-media-responsiveness/`。这些测试合同校正不计为客户端性能提升，CPU、FPS、滚动和首次真实图片成功率仍需客户端复测。

### 客户端仍未关闭的验收

以下保留较早的 SDK `9e05d888` 客户端记录及尚未关闭的复杂场景，不能当作 `a4808be3` 的同版本失败列表。原始 Mac 日志、录像和 xcresult 尚未取得。上节定向复测仅覆盖列出的功能、构建和性能样本，没有自动关闭此处其余历史失败；源码修复、JS 通过或合并同样不能代替复验。

| 验收项 | 已有证据与当前结论 |
| --- | --- |
| 流中文字长期停在半句 | 行程文字在输入早期及数据层已完整，画面约 18–54 秒仍显示截断，约 57 秒才补齐；酒店、表单也有类似观察。后续客户端断点显示 SDK source 已完整、received/displayed 仍旧前缀；本分支已修正文本 onChange 回调交付旧值的缺陷，原始客户端回放仍未重验。必须在 done 之前验证真实可见文本 |
| SDK 原生回归 | 用户报告 870 项中 10 个失败用例、24 条失败断言；涉及选项列宽、按钮身份、物化预算、Gallery 高度、mutation 退休、焦点、紧凑图表及三项 signed media。需要完整 testcase 和第一条 expected/actual；不能全部解释为生产缺陷或测试过时 |
| signed media 与 SVG | 三项 signed media 测试使用内存 PNG 和确定性 loader，不能用 App proxy HTTPError 解释。SVG 打开/缩放通过，拖动像素断言失败且归因未定；图像预览正常不等于 SVG 拖动通过 |
| 流中表单选择 | 复杂表单的自动点击实际发生在 done 后，流中选择跨完成状态保留仍未验收；小型状态测试不能替代此场景 |
| 性能 | 历史同一行程的一次 Debug 样本由旧版本平均 98.81% CPU / 峰值 220.58 MiB，变为 9e05 的 89.95% / 226.96 MiB；分片配置相同、实际传输时长不同。单样本不能证明改善或泄漏；后续 c7310054 / a4808be3 的独立 Release 与 App Debug 记录见上节，真机、FPS、有效 Instruments 与 memgraph 仍未验收 |
| App 与后端阻塞 | Release 在 App 的 TaskBrowserSession.performRefresh 遇 Swift 编译器内部错误；真实模型链路受 sandbox initialize 的 fixed_sandbox_missing 阻塞。两项应独立跟进，不据此归因 SDK parser |

“Mutation 参数函数同步换源后可能派发旧调用”没有列为正常输入缺陷：现行语言契约要求自定义函数纯且同步，不得修改状态。违反该契约的宿主重入可以另做防御核验，不能与普通纯函数执行混淆。

**原生复验顺序。** 固定候选 revision，先编译并运行新增与既有 XCTest，保留每项失败的第一条 expected/actual。随后复跑用户的 10 项原生失败、signed media 和 SVG 拖动；稳定性补测包括 Store 往返与原子拒绝、Action 取消/累计预算、共享原生值 readiness、旧 Context 刷新、标准容器身份，以及 Gallery 窗口、高清升级和签名复用。不能因本轮实现覆盖相近模块就修改旧断言压绿。

实际 Muse 半句停滞仍需取得原始输入与客户端回放，逐段关联输入、投影、发布、text buffer、Markdown prepared 与可见文本版本，检查“目标字段已完整，其他节点继续生成时，done 前画面必须更新”。覆盖直接 Text 与 Markdown 的 mounted 回归已在 macOS CI 执行；`1f070fe` 的三项文字采集用例失败，独立纯 SwiftUI 对照也无法被旧读取器取得。收尾候选修正实际无障碍树的观测路径，执行结果见[客户端复测收尾候选](#客户端复测收尾候选)；小型 SDK 用例不能替代复杂客户端回放。

现有 `testCanonicalMarkdownPreparationCoalescesWithoutStarvingContinuousInput` 在 MainActor 同步循环投喂后才等待最终结果，未证明持续分片时的中间可见进展。文本 buffer 的 48 ms 逻辑是 throttle，追加不重置计时器；不能把真实停滞直接解释成普通 debounce。两个允许旧前缀的展示阶段和共享 Markdown worker 的等待需测量；如果直接 Text 也停滞，还要检查更上游的宿主、投影和发布。后续客户端断点与源码复核将一个确定缺陷收敛到变化回调交付旧捕获文本，修正见上节；没有把共享 native Value 的特殊触发当作该 App 事故的根因。共享 worker 的等待和其它性能成本仍需另测。

早期只读探针保留在忽略的 `outputs/text-audit/`、`outputs/remaining-action-budget-probe.*`、`outputs/remaining-state-aggregate-probe.*` 与 `outputs/main-assessment-20261116/`；本轮执行日志以前述 `outputs/kernel-repair-*.log` 为准。只维护本文这份验收记录，不新增并行审查报告。

### 性能证据与未完成项

保留前期审查的成本证据：同一台运行器、Node v24.22.1、同一旧资源、160 个稳定节点加文字尾部（8,439 UTF-16 units），各测三次；每块执行实际增量 parser、Store 初始化和 boundedRoot，末态相同。下表不是本轮候选的前后性能比较：

| 每块 UTF-16 units | 每条流更新次数 | 整条流累计耗时中位数 |
| --- | ---: | ---: |
| 16 | 528 | 1,273.9 ms |
| 128 | 66 | 133.9 ms |
| 512 | 17 | 37.7 ms |

这只量化 JS/V8 下更新频率的成本，不包含 Swift 预检、JavaScriptCore、原生桥接、live index 或布局，也不是用户设备帧率。不能据此宣称 SwiftUI 已有某个固定倍数的提速。

前期另一个独立探针使用当时已修正资源预算的 bundle 和原生 `NativeExpressionGuard` 相同的判定，对实际 preprocess/tokenize/split 单独计时。在同样 8,439 UTF-16 units 的文档中，16-unit 分块触发 209 次完整前缀检查，累计扫描 1,417,847 UTF-16 units，检查本身三轮中位耗时 138.7 ms；128-unit 分块为 27 次、183,159 units、15.5 ms。它定位的是快速包络超过保守阈值后的额外前缀扫描，而非 parser 已完成语句缓存失效。本轮已删除这条额外扫描路径，改用同一 parser 已有 tokens；上述时间仅作为历史 Node/V8 证据保留，未包含 Swift/JavaScriptCore/设备 UI，不作新版本设备提速结论。

客户端先前的 `c7310054` Apple Release / App Debug 数据，现已补齐同机 `a4808be3` 对照，数值与限制集中记录于上节“客户端 a4808be 定向复测”。先前记录另有 `c7310054` 的 201 节点 / 128-unit 最大 push 为 20.21ms；新复测没有提供该分片规模的最大值对照。独立消费者的同步计算改善与 App CPU 接近不矛盾：两者覆盖的工作不同，不能将全部 CPU 归给 parser，也不能把 Debug CPU 换算为 FPS。

合入 `a4808be3` 前，使用仓库 benchmark 相同生成规则进行了工作量对照：基线 bundle `52011d56…` 与合入资源 `842e71dd…`。200 rows 流式程序为 10,841 UTF-16 units；24/128 units 分别为 452/85 块。这里沿用客户端的 rows 参数；流式生成器还包含变化尾部及容器，不将参数直接当成最终总节点数。旧额外检查按删除前 Swift 包络的完全相同条件调用实际固定 core 重放；新计数来自临时资源在真实 `checkSourceStatements` 循环内的两个计数器。元数据按实际 JS 对象身份计数，不是 Swift 分配或设备时间。

| 200 rows 流式指标 | 24-unit 基线 → a4808be3 资源 | 128-unit 基线 → a4808be3 资源 |
| --- | ---: | ---: |
| 额外全前缀预检次数 | 201 → 0 | 38 → 0 |
| 额外扫描 UTF-16 总量 | 1,698,041 → 0 | 323,417 → 0 |
| 源预算 token 访问 | 225,110 → 13,688 | 42,688 → 3,659 |
| 全部独立 readiness 对象 | 98,334 → 1,774 | 18,702 → 334 |
| 元素投影访问 | 48,937 → 48,937 | 9,307 → 9,307 |

源预算 token 访问减少 93.9% / 91.4%，但整树元素访问仍在。61 节点的小负载原本无需额外预检；新检查分别访问 1,872 / 595 个现有 tokens，同时独立 readiness 对象从 16,170 / 3,148 降到 866 / 161。不能只引用大负载计数就宣称全部规模的耗时均下降。证据为 `outputs/kernel-client-performance/work-counts.json`，计数资源只增加统计，不作为发布资源；`a4808be3` 后续 Apple CPU / Swift push 复测见上节，App FPS 仍未验收。

计划累计预算的修复依据也保留为历史证据：修复前，128 个 Set 与 128 行 Each 的合法程序按原生控制流会产生 129 次 root 求值，Node 单次 root 为 1,549 work；另一份 100 个 Set 的程序逐步调用 boundedEvaluate 并写入 JS Store，每步 19,315 work、合计 1,931,500 work，仍无单步超限。前者是源码次数推导，后者是 JS 单步预算探针，都不是设备阻塞时长。本轮已加整条 action 额度与步骤间取消检查，原生累计拒绝的实际运行和响应效果仍待验收，不能继续将“完全没有计划预算”列为当前实现状态。

本次还对 Query 快照序列化做了计数探针：共享一个 1,000 项默认数组，分别建立 10、20、40 个合法独立 Query；输入长 2,292 / 2,582 / 3,162 UTF-16 units，均无解析错误。整个初始化分别发生 12 / 22 / 42 次全快照 JSON.stringify，累计序列化 131,597 / 464,387 / 1,734,167 UTF-16 units，而已记录求值 work 仅 40 / 80 / 160。它证明快照比较中的重复工作接近平方增长，现有求值 work 不能代表该路径成本。记录在 `outputs/kernel-followup/query-snapshot-cost.jsonl`；不是 Apple CPU、帧率或本轮前后提速结论。另用实际 manager 验证：provider 同步入口、同步 listener 或两次求值之间可原地修改共享默认对象；现有快照会正确通知变化，未变时保持 snapshot identity。因此不能直接省掉收尾比较或按对象 identity 复用序列化；本次未通过削减通知、改变快照相等语义或假定任意工具对象不可变来掩盖该项。

以下仍是开放项，不能标为本次已解决：

- `OpenUIState.push` 仍在 MainActor 同步解析、整 root 求值/投影并建立 live index。持续细分块仍会增加整轮工作次数；本轮没有自动按显示帧合并输入，也没有改客户端的 push/complete/interrupt 使用方式。
- 多步 Action 的累计额度已经加入，但逐步 Set/Reset 引发的 root 更新及计划结束后的更新仍保留。内部呈现提交与节点字段订阅不等于语言求值的增量依赖计算，也未合并跨步骤的语义工作；必须保留每步 Store 可见性、Mutation 失败即停止和事件次序，不可直接删中间通知。
- Query 快照比较仍重复序列化完整数据，上述计数已确认其规模增长；本轮批量错误提取只减少原生呈现读取，没有删减 JS 快照比较。优化需保持 snapshot 值、正常通知及共享对象语义。Query 的内部通知投递已合并，实际原生执行次数和整 root 工作量尚未测量。旧 JS manager 探针中 100 个独立请求产生 100 次初始通知和 100 次完成通知；该计数不能直接换算成新实现的 MainActor 任务数，也不能宣称已测得“200 次变成 1 次”。不同执行时刻仍可能各产生一次呈现更新。
- 普通 push 的公开 readiness/root 双重通知已收敛到一次 root 发布；SwiftLangView 现观察完整内部提交，轻量 ComponentHost 仍观察最近 State。节点字段订阅和 mounted 回归已在 macOS CI 执行：`1f070fe` 的普通流式尾部隔离用例通过，字段读者用例在媒体/文本 Debug 组出现首次额外重算，而全量、Release streaming 和 ASan 组通过。候选增加实际挂载订阅信号与呈现输入对照，结果见[客户端复测收尾候选](#客户端复测收尾候选)。OpenUI 的 ActionSurface、字段和 EditableTable 已统一使用 Context 依赖；全局 partial 翻转、引用属性变化、Host 的环境观察和其他消费者仍会带来更新，不能宣称视图已完全隔离或 App CPU 已降低。
- SharedCore 用锁串行化共享 JavaScriptCore。锁保护线程安全，不会自动把工作移到后台；多个文档可能相互等待。迁移到 worker 需要同步定义不可变输入/输出、回调线程、取消和提交代次，不能用 `Task.detached` 直接包住当前 MainActor State。
- 当前节点的 identity 快径和匿名 scalar 属性分桶不消除复杂引用节点的旧快照语义搜索；变化键比较也有成本。当前内核普通流会重建 JS 引用，整树索引遍历及每轮挂载订阅检查仍需原生计时，不能假定其复杂度已经降到只与文字尾部有关。
- 尚无本轮真机 Release 的帧耗时、输入响应和长期内存数据。文档拥有的编辑记录保留离屏草稿，不能为压低缓存数字随意淘汰用户未提交内容；动态字段的长期留存需要专项测量。

编码前保护的范围以适配清单为准：高层 OpenUIState、Query/Mutation 输入输出、Evaluator 上下文和 AST，以及本轮补齐的 SDK CoreStore、手工 Query AST 与 ParseResult fallback 都在相应编码边界预检。底层 Store 保留原有 void 写入/初始化签名，拒绝时保留旧值，并通过内部失败状态供 OpenUIState 走已有错误渠道；没有新增客户端写入 API。自定义 Store 的策略、宿主函数返回前的自身计算，以及 provider 忽略取消后仍在进行的外部工作不能被库抢占。不能将这些限制解释为任意宿主代码的隔离沙箱。

现有 [LanguageRuntime 基准](../Benchmarks/LanguageRuntime/README.md) 使用公开 MainActor State 的真实流式路径及宽对象构造，报告逐次 push、complete、整流、发布次数与耗时分位数；CI 分片为客户端对照的 24/128 units 并保存 JSON，README 给出同样 201 节点参数。`1f070fe` 的 [CI run 44046828032](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44046828032) 已生成两组 Release 测量，rows=200、components=201、streamIterations=5；原始 JSON 保存在 `outputs/repair-baseline/native-acceptance/`。这些数值绑定该 runner，不把另一候选在不同 job 的数字当作同机性能提升。原生验收还必须同时检查 terminal flush、停止/换源后旧结果失效、超限前无工具派发、完整控件可用、未完整控件不可执行，以及 Release UI 的 body/布局/挂载和滚动交互。

前轮纠正了旧基准调用与公共 API 的漂移：`Evaluator(context:store:schema:)` 的 `store` 实参已没有对应初始化器，基准改为当前 `Evaluator(context:schema:)`，状态仍由传入的 EvaluationContext 回调读取。YAML 及 workflow 内 shell 语法曾单独检查；这些检查不构成 Swift 编译通过的证明。

### 客户端复测收尾候选

本次从远端 `main=1f070fe` 创建独立分支，整合 `dad6d4f` 的跨文档完成缓存预算、内存压力清理和原生对象拥有桥接身份。整合保留现行图片显示尺寸、自动恢复、冻结签名、owner/scope/limits 检查与完整旧测试集合；原 15 项生命周期回归均保留，另加共享预算下旧策略拒绝和新策略较小图片替换的组合回归。`snapshotState()` 仍只导出业务值，客户端不需要新增调用或改变 `push / complete / interrupt`。

收尾期间主线前进至 `7d9b36a`，候选通过正常合并保留 `c20081d` 的 JourneyLine/时间线、`176d9c5` 的中文强调及布局诊断修正，以及 `7d9b36a` 的不完整源码诊断隐藏；这些同期工作不是本次收尾重新实现的功能。原生验收必须绑定整合后的提交，不沿用任一父分支的通过状态。本文开头的 Xcode 26.6 精简包记录仍属于该次定向执行；本候选使用既有 CI 锁定的 Xcode 26.3 完整包门禁。

| 残留问题 | 独立依据与本次处理 |
| --- | --- |
| 字段启用状态变更后的焦点顺序慢一轮 | 原生用例连续禁用/启用时顺序反向滞后；`onChange` 回调把收到的新值传给登记函数，避免再次读取闭包捕获的旧 Environment 值。保留原焦点顺序断言 |
| Overview 指标行起点不齐 | 布局角色由 `NativeCardBlock` 的直接子项边界交给 pager，避免动态 renderer 内层的 layout value 未传达；不增加虚假文本或更改原对齐误差 |
| 回退快照与文字/SVG 采集 | 独立纯 SwiftUI 对照也读不到文字，surface/boundary 已收到最新 readiness 而测试 marker 未更新。marker 携带不可变快照身份；测试初始化当前进程 AX 树并遍历真实原生/虚拟节点，不把预期文本写入 label；原等待时限和断言保留 |
| Card 图片宽度 | [独立 macOS 日志](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44046887577/job/133914682735) 显示新 Card 正确应用 16 pt inset、内容宽 268 pt，退出的旧 Stack 随后用 300 pt 覆盖单个测试记录。探针改按挂载实例记录并在退出时删除；保留原输入、宽度、epoch 并检查唯一挂载实例，生产 Card 视觉不变 |
| 六个就绪回归把完整源码当作未完成输入 | 用锁定上游未修改源码独立构建，对原六段完整 Lang 及各自最后一个右括号之前的前缀逐阶段核对：前缀 `meta.incomplete=true`，右括号到达后为 false；正式 bundle 的 complete/closed 均一致。测试保留原完整源码，先喂真实前缀验证拒绝，再补同一末尾验证闭合即启用，不把全流结束重新设为交互门槛 |
| Store 读者的额外重算 | 原生诊断中只有 left 收到订阅信号，right/plain 的节点、订阅和呈现输入保持；`3165598` 的首轮父级更新出现 `@self changed`，没有调用持有动态属性的内容边界的相等比较。候选把纯输入 Equatable 边界与 StateObject/Environment 内容分开，保留最近文档解析、环境变化、注册表及父闭包捕获；原 builder/body 零增长断言与等待时限不变。`4a5108f` 的早期和完整媒体/文本组中均在 Debug/Release 通过，13 项隔离回归也全部通过 |
| SVG 的值在可读描述中 | `3165598` 的原生树明确显示 raw value 为 nil，而 `accessibilityValueDescription` 从 Loading 变为 Unable to load graphic。测试读取实际可读描述并遍历同 alt 的语义节点，不根据预期字符串选值；两配置均通过，完整 alt、固定高度和未闭合 URL 零请求断言保留 |
| Release 测试中的资源 owner 提前释放 | 空响应测试只有 scoped 弱引用继续使用，原 owner 数组最后一次 map 后可被释放，首次 request 因 scope 失效返回 nil。测试明确保持 owner 到全部断言结束；同类跨文档 LRU 夹具也保持三个 owner。生产的弱所有权、额度和原命中/淘汰断言均不改变 |

本地已完成 Core JS **170/170**、Validation **6/6**、目录兼容 **7/7**、固定上游独立对照 **0 unexplained differences**、来源/所有权、本地化、Gallery 目录、workflow YAML/Bash 及 `git diff --check`。当前 Linux 无 Swift/AppKit，原生结果以本候选在 macOS 的 Debug/Release、全量、ASan、独立消费者、iOS 和 Gallery 门禁为准；前置阶段新增生命周期组和六个就绪回归所属类别，没有删除旧门禁。

`21cbb3e` 的 Debug 前置 **103/103** 通过；媒体/文本两配置各执行 275 项，文字、readiness、焦点、Card 和 Overview 回归通过，三个尺寸转换重复各 **2/2**。该阶段仍有 SVG 读取、Store 读者及 Release owner 夹具失败，不能记作全组通过。`3165598` 的剩余三项定向检查为 Debug **3/3**、Release **2/3**：SVG 与空响应夹具均通过，Store 读者在 Release 仍多次构建，所以继续修正内部输入边界。诊断代码只用于定位，交付代码移除临时 `_printChanges` 和环境开关；后续检查按 Debug/Release 分别立即归档，全部既有大组与门禁仍执行。

合并同期主线后的 `4a5108f` 在 [CI 44060056387](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44060056387) 中通过 Debug 生命周期/深层/状态前置 **103/103**、早期收尾 Debug/Release 各 **3/3**、媒体/文本 Debug/Release 各 **278/278**，以及三个尺寸转换重复各 **2/2**。278 比此前的 275 多出同期主线的三项中文强调及诊断呈现回归，没有删减原组。Release fitting、iOS 16 Simulator 两库与 Gallery 构建也通过；全量包测试与后续门禁当时仍在执行，不能记为整条流水线通过。

用户随后提供的 17 项截图明确包含 SwiftIntelligentUI 的 Markdown 字体用例，因此本次范围增加这一项定向修复。独立诊断提交 `8856632` 在同一 macOS 15 runner 保留原文、320 pt 宽度、large/accessibility2 和 2 pt 容差：H1 为 Markdown 60 / Title 65 pt，H2 为 57/59、H3 为 48/48、正文为 36/36。独立纯 Text 与相同 AttributedString 的对照均显示语义 Font 和 Font(NSFont) 为 65，而同字号/字重的固定 system Font 为 60；17 pt semibold 相同，差异来自语义字体度量在 MarkdownUI 重建时丢失，非字重或输入内容。

直接使用 AppKit leading 差的候选 `3152ca7` 修正了 H1，却把 H2 从 57/59 pt 补成 62/59 pt，Debug/Release 均由原 2 pt 断言拦下。独立诊断进一步确认 CTFont 总行高、TextKit 默认行高和真实 SwiftUI 基线并非同一个量，不能按标题级别写固定补偿，也不能选择只让短文进入容差的近似值。

诊断提交 `2fc398a` 的 [原生执行](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44069771066) 保留原文字、宽度、字号和断言，另加入三倍长标题。公开 Canvas 文本解析与 NSHostingView 的 ViewDimensions 在 displayScale 1/2 上得到相同的实际行间基线：H1 为语义 22 / 固定 20 pt，H2 为 20/19，H3 为 16/16。18 次直接测量和 3 次外层 body 冷调用均同步完成；未观察到布局循环或更新中改写状态的诊断。采用该基线差的 SDK 探针中，原文的 Markdown/Title 高度为 64/65、59/59、48/48，长文为 196/197、159/159、112/112；ImageRenderer 与 NSHostingView 两条路径都在原 2 pt 容差内，H1 的 1 pt 首尾行框差没有逐行累积。这些通过结果属于诊断提交，不直接代替正式缓存实现的验收。

正式修正只在 macOS 默认语义系统标题路径，通过同一 Canvas context 解析实际语义字体和 MarkdownUI 重建的固定字体，读取首末行 baseline 差。缓存以完整字体对、动态字号、displayScale、locale、legibilityWeight 和布局方向为键，最多 32 项，只保留标量，不保留 renderer、图像、宿主或文档。未获得合法同步度量时不缓存；合法的零差正常复用。真实标题累加宿主已有行距；显式相对比例、自定义字体和 iOS 路径保持原规则。新增两项真实 SDK 回归覆盖短/长标题的首次及缓存渲染、两种字号与 scale 下的冷/重复原生拟合，以及拟合不发布 SDK 状态。正式候选 `315cd4e` 的早期收尾 Debug/Release 各 **17/17** 通过，其中 Intelligent UI 字体 **9/9**、OpenUI 字体 **4/4**，其余四项为 SVG、ResourceStore、Store 读者和 Query。原字体、长标题与重复拟合的 2 pt 断言均保留；两份日志未观察到 AttributeGraph、布局期间状态修改或 layout cycle 诊断。这是正式 Canvas 与缓存实现的原生证据，独立于前述探针；诊断专用源码、打印及 workflow 不进入交付。

`3152ca7` 的 [完整流水线记录](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44064403011) 中，包内 **1215** 个 testcase 执行完毕：SwiftLang **444/444**、SwiftOpenUI **570/570**，SwiftIntelligentUI **200 通过 / 1 失败**，唯一失败 testcase 为上述 H2 字体的两条断言。媒体/文本两配置各 **278/278**、Release 边界 **339/339**、Release fitting **4/4**、三个独立产品消费者、iOS 产品与 Gallery 构建、Gallery fixtures **184 batch + 184 streamed**、历史 IUI **61 个组件契约**、工具构建及两轮 Release benchmark 均成功。后续还出现以下两项独立失败，整条执行因此不能记作通过：

| 后续失败 | 独立依据与修正 |
| --- | --- |
| Gallery 目录数量仍写 87 | 主线 `c20081d` 已加入 JourneyLine，实际注册集合、ReferenceCatalogTests 和设计文档均为 88；`7d9b36a` 与 `3152ca7` 的独立 Gallery 均只有旧数量断言失败。数量同步为 88 并明确检查 JourneyLine 存在，保留全部集合相等、15 个 supporting 子项及逐例求值检查；原 Lang 示例不改。`315cd4e` 的独立 Gallery **16/16** 通过 |
| ASan 中 Query 停表后的调用计数 5/4 | ASan 构建与 444 个 testcase 均执行完成，443 通过 / 1 计时断言失败，没有 AddressSanitizer 内存错误报告。固定官方 queryManager 与实际 bundle 的受控时序均复现：40 ms tick 先接受第 5 个请求，停表时 provider 计数仍为 4，该已接受任务随后进入 provider；停表后 65 ms 没有新 tick 或新请求。测试改为等待已接受查询 success 后记录计数，保留原 65 ms、精确不增长及 in-flight 排队断言；不改生产调度，也不取消合法在途请求。该 case 在 `315cd4e` 的早期 Debug/Release 及完整 ASan 中均通过 |

#### 正式候选的执行结果

以下结果来自 `315cd4edc9de744b8996a1b9c3bb271c6b34acbc` 的同一轮 [CI 44073952191](https://github.com/zyfn/open-intelligent-ui-swift/actions/runs/44073952191)，按本轮原始日志计数；不由历史候选的通过数量推算。`dependency-security`、`reproducible-inputs`、`native-sdk` 和最终 `Native SDK acceptance` 四个任务均为 **success**，整条流水线已完成并通过。最终产物的提交标识、ZIP SHA-256 和 provenance 已相互核对；执行环境为 **Xcode 26.3（17C529）、Swift 6.2.4、macOS 15.8.2 arm64**。

| 验证范围 | 本候选实际结果 |
| --- | --- |
| 生命周期、深层数据与状态前置 | **103/103**，零失败 |
| 字体、SVG、资源、Store 读者与 Query 定向收尾 | Debug **17/17**、Release **17/17**，零失败 |
| OpenUI 媒体、文字、交互与布局 | Debug **278/278**、Release **278/278**，零失败 |
| 图片尺寸转换重复检查 | 三次独立执行，各 **2/2**，零失败 |
| 全量原生包测试 | **1217/1217**，零失败、零 unexpected；SwiftLang **444**、SwiftOpenUI **570**、SwiftIntelligentUI **203** |
| 流式挂载隔离 | 全量中的 **13/13**，包括 Store 读者、兄弟节点、Environment、注册表与闭包捕获 |
| Release 流式、失败与资源边界 | **339/339**，零失败 |
| Release 原生拟合 | **4/4**，零失败 |
| 独立 Gallery | **16/16**，零失败 |
| SwiftLang AddressSanitizer | **444/444**，零失败、零 unexpected；未出现 AddressSanitizer ERROR/SUMMARY 内存错误报告，未收集到 crash report |
| Gallery 示例程序 | **184 batch + 184 streamed**，零失败 |
| 历史 Intelligent UI 契约 | **61 个组件**的位置参数及完整 schema 保持不变 |
| 独立产品消费者 | `swift-lang`、`swift-ui`、`swift-intelligent-ui` 三个公共 API 消费者均完成实际构建和运行 |
| iOS 16 Simulator | SwiftOpenUI、SwiftIntelligentUI 产品及 Gallery 构建通过；不作为真机 UI 或性能执行结果 |
| 独立工具与测量 | ContractExport 与 Release 性能工具构建通过；24/128 分块的两轮 Release 测量均成功生成完整结果 |

截图六组所对应的原生用例均在本轮全量日志找到并通过：流式状态与交互 **7/7**、流式文字 **3/3**、图表 **1/1**、SVG **1/1**、布局与焦点 **4/4**、Markdown 字体 **1/1**，合计 **17/17**。额外的宽 Markdown 表格滚动至最后一列用例也通过。这里的 17 项截图回归与早期 17 项定向检查是不同集合；两者分别核对，没有用相同数量代替覆盖关系。

原生验收绑定上述源码提交；交付尾提交仅补充本文档。发布前逐路径比较确认源码、测试、依赖、资源、示例、工具和 workflow 与 `315cd4e` 完全相同，不把纯文档尾提交描述为另一次已执行的原生 CI。以上结果证明本轮 SDK 原生回归通过，不替代目标设备上 App CPU、帧耗时、持续滚动或长会话的同条件复测。

基线、readiness 与 Query 定时器独立 oracle 放 `outputs/repair-baseline/`，生命周期前置证据放 `outputs/repair-lifecycle/run-44053853788/`，历次候选分别放 `outputs/repair-candidate-21cbb3e/`、`outputs/repair-candidate-3165598/`、`outputs/repair-candidate-4a5108f/`、`outputs/repair-candidate-3152ca7/` 和 `outputs/repair-candidate-315cd4e/`，字体独立基线证据放 `outputs/typography-metrics-2fc398a/`；不将基线成功、新候选源码完成或部分原生通过写成完整客户端流畅度验收。

### 内核目标验收

下表是本轮原生复验及后续性能工作的验收要求，不是当前通过结果。每项实现时补对应验证，执行日志放 outputs；边界只在[架构](architecture.md#现有入口的性能边界与后续验证)维护，保持既有客户端入口和调用语义。

| 范围 | 验收场景与通过条件 |
| --- | --- |
| 现有输入与终止 | 连续用 push 送入细分块，检查每次同步返回的状态及终态 UTF-16 内容与既有契约一致。complete 提交完整尾部；interrupt 不补全截断 token，已闭合操作仍按 readiness 判断。reset/替换后 SDK 自己持有的旧异步任务不能回填；宿主用现有请求生命周期过滤旧请求的迟到 push 回调 |
| 排队与过载 | Query burst 的每个订阅至多一个待执行呈现投递，退休后不能回填，工具状态、错误与完成信息仍正确。持续细分块输入检查当前源码上限与实际主线程成本，不能丢内容或修改同步契约来压低次数 |
| 提交一致性 | 在 root/字段/readiness/错误发布和回调中制造重入、换源及乱序完成；每个可见提交内部一致，较旧更新不能覆盖较新结果，旧组件写入被拒绝 |
| 节点隔离 | 在稳定兄弟后持续修改文本尾部，并分别改变 readiness、Query 状态和字段值；无关节点的投影/body 计数不随分块等比例增长，实际依赖变化必须生效，焦点和未提交草稿保持 |
| 动作执行 | 多 Set 后发送事件，事件读取正确的逐步状态和既有回调顺序；完整计划的原生与 JS 工作累计，临近上限时不能再运行一个全额 JS 循环。Task 取消、累计超限、Mutation 失败或让步期间换源后，剩余步骤停止且 SDK 等待结束；provider 不配合取消的情况单独覆盖 |
| 原生输入与恢复 | 深/宽/共享图、整批状态恢复、直接底层入口均在大规模投影或写入之前明确拒绝；失败不提交部分无效数据，合法替换/reset 后可重新工作 |
| 设备响应与资源 | 同一设备、Release 构建、同一工作负载记录分阶段 p50/p95/max、主线程连续占用、提交/body 次数、输入与滚动响应；重复创建/退休文档检查任务和引用是否释放。JS 耗时、进程 RSS 或一次截图不能单独作为通过依据 |

帧耗时和响应阈值随目标设备及刷新率记录，并在前后比较前固定测试条件；当前尚未取得设备帧耗时与持续滚动基线，不填写未经测量的达标数值。行为不变量必须通过，性能优化还需证明目标工作量减少且正常交互无退化。
