# 验证与安全修复

本文记录四模块重构之后的依赖与源码验证修复。当前实现和安全修复在 `refactor/openui-four-module-foundation` 分支维护；具体提交的验收结果以 [Native SDK 流水线](https://github.com/zyfn/open-intelligent-ui-swift/actions/workflows/native-sdk.yml) 和 [PR #3](https://github.com/zyfn/open-intelligent-ui-swift/pull/3) 为准。当前生成输入由 [Tools/upstream.json](../Tools/upstream.json) 固定，原始导入来源可从 Git 历史与 [RC21 源码修复清单](../Validation/source-rc21/manifest.json) 查到。完整上游许可保存在 [THIRD-PARTY-NOTICES.txt](../Sources/OpenUILang/Resources/THIRD-PARTY-NOTICES.txt)，并随 SDK 资源打包。

## 1. 实际打包依赖与可复现生成

| 依赖 | 当前固定版本 | 修复与验证 |
|---|---|---|
| 官方语言核心 `@openuidev/lang-core` | `1.1.1` | 固定官方源码提交、原始/适配后源码树及实际 JavaScriptCore bundle；执行新版本语言行为与原生桥接回归 |
| Zod | `4.6.7` | 修复约束集合校验的内存耗尽问题；保留既有 schema 导出与原生 record 契约，重新生成语言 bundle、manifest 与 oracle 构建指纹 |
| KaTeX | `0.18.2` | 修复从原型继承信任选项的问题；更新标准富文本与 Intelligent UI 实际使用的公式资源 |

官方安全公告分别为 [GHSA-mrhx-c7xc-m3w5](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5) 和 [GHSA-238p-pmpm-9mq7](https://github.com/advisories/GHSA-238p-pmpm-9mq7)。后一个问题依赖于已有原型污染；修复后的依赖不再把继承的选项视为应用主动启用信任。

Zod 与 KaTeX 更新使用 npm 提供的真实 tarball 与 integrity，锁文件固定构建图。标准富文本中直接和传递的 KaTeX 使用相同的精确版本。Intelligent UI 的 MathML 引擎也由受审计的生成工具维护，避免只更新 npm 依赖而遗留旧的运行时文件。

当前 SDK 的语言上游升级为 `@openuidev/lang-core` 1.1.1，固定官方源码提交 `39a4e3f6493673fdf2de04681240374c8d6f6be8`。构建从该版本源码生成随 SDK 打包的 JavaScriptCore 资源，并记录 Apple 平台桥接、兼容补丁与执行预算；客户端不运行时下载脚本，也不自动跟随 `latest`。实际提交、源码树与资源哈希以 [upstream.json](../Tools/upstream.json) 和 [core-manifest.json](../Sources/OpenUILang/Resources/core-manifest.json) 为准。

语言升级的回归需要覆盖新上游的表达式状态、列表/数学函数、查询依赖与重试、流式解析及动作/序列化行为。与官方版本同步产生的语义变化应有对应的上游依据和专门用例，不能仅更新 fixture 来掩盖原生桥接差异。组件目录和设计系统的变更独立于语言版本；原生契约检查仍对照固定的历史 Intelligent UI 基线，完整比较组件顺序、位置参数和 schema。

Zod 4.6.7 的 JSON Schema 导出新增了把纯标量 `anyOf` 合并成 `type` 数组的优化。两种写法表达相同类型集合，但本 SDK 保留既有导出契约，因此在现有构建兼容层中仅禁用该导出压缩步骤。共享适配同时用于原生 bundle 和官方组件目录生成，严格校验 Zod 版本、源文件 SHA-256、唯一匹配的替换片段及变换后 SHA-256；清单中的 `dependencyTransforms` 记录这些证据。Zod 的解析、校验和修复后的集合限制不受此导出适配影响。

Zod 的 JSON Schema 导入也把简单字符串键 record 包装为带校验的 pipe，固定 Lang 核心无法由该表示还原历史 record 签名。现有 authoring 桥接只对没有显式字段、patternProperties、属性数量或键名约束的简单 record 恢复新版 `z.record` 表示，并保留原来的字符串键检查、元数据、默认值和绑定身份。带额外约束的对象继续使用完整的新版 guard.pipe，保留预解析检查。

组件目录继续与原已提交文件逐字一致，不刷新 schema 期望来接受漂移。回归直接执行实际打包的 `nativeAuthoring`，比较全部 84 个组件、304 个参数和完整签名，覆盖联合分支顺序、nullable、类型数组输入、默认值、约束、嵌套、参数顺序及历史 parser 结果。另通过真实桥接的 `props.safeParse` 执行对象大小、键名、固定字段、额外属性类型和 patternProperties 的正反校验，验证安全检查实际生效。

标准富文本生成器继续嵌入字体，运行时不加载外部 CSS 或字体。Intelligent UI 继续输出 MathML，保留原来的 `trust: false`、严格语法、展开次数和输出大小限制。公式安全回归在隔离的 JavaScript 上下文中验证原型污染不能开启受信任渲染，并覆盖有效公式与非法输入。

当前资源版本与内容哈希由各资源 manifest 记录。生成器运行后，CI 要求资源与当前提交逐字一致；它不再要求后续安全修复继续等于原始导入的旧哈希。

## 2. RC21 源码修复候选

`source-rc21-gate` 使用 `zyfn/openui` 的固定基线 `f3dfa1d0b479c131b6d4268e81961186f22ff09c`，然后应用本分支保存的 [修复清单](../Validation/source-rc21/manifest.json)。该任务检验的是“固定源码 + 已审查修复”的候选，不把修补结果记成未经修改的原始源码通过。

该历史候选独立于当前 SDK 的 Lang 1.1.1 升级。清单中的 `sdk_payload_revision` 固定为 `cbd57808d1fe3f086ed261c602874d16a0ee14f9`，copy 操作从该 SDK Git 提交读取已审查的文件并校验原有 SHA-256，不读取当前工作树中的新资源。原始基线、逐文件 before/after 哈希、patch 和完整候选 tree `51eedac918540b31206b9f613e3ac7566da025a3` 保持不变。CI 为修复工具 checkout 保留完整历史，确保存有该不可变输入。

修复包括以下真实问题：

- 原视觉测试直接写只读的 SwiftUI `accessibilityReduceMotion` 环境值，在当前 Xcode 上无法编译。改用已有 presentation 配置和 transaction 控制动画，保留原视觉断言。
- 原 ObjectCard 图片边缘测试使用没有图片地址的占位内容来断言红色图片。改用已加载的确定性红色 PNG，保留边缘、留白、像素坐标和阈值断言。
- 源码候选的 Zod 与 KaTeX 同步升级，接入相同的精确 JSON Schema 导出与原生 record 兼容适配后独立重建；原始 Lang 源码不变。源路径下的适配器哈希按其实际生成器单独计算，清单包含这些经过审查的修改。
- 源码中三份 presentation 锁文件的遗留私有下载地址改为公开 npm registry；该地址规范化逐项保留包版本、integrity 和其余元数据，并使用全新 npm cache 验证实际下载与审计。

[修复工具](../Tools/repair_rc21_source.py) 验证基线 HEAD 和完整 tree、SDK payload 提交存在且为完整 commit ID、补丁 SHA-256、每个文件的前后哈希、允许变化的文件集合及完整候选 tree。copy 操作使用已经核对过的固定提交字节，证据中记录 payload revision。工具不移动基线 HEAD，不写入源码仓库的真实 index；它用临时 index 计算完整候选 tree。

原始源码测试、Release 尺寸拟合、authoring fixtures、依赖审计、资源再生成、原组件目录逐字比较、AddressSanitizer、macOS 示例与 iOS 16 Simulator 编译均继续运行。资源再生成及所有构建完成后，再次验证完整候选 tree，确保测试过程没有悄悄改变候选。

在具备固定源码 checkout 的本机，可以从 SDK 根目录执行：

```sh
python3 Tools/repair_rc21_source.py \
  --source /path/to/source-rc21 \
  --evidence /path/to/source-rc21-evidence

# 在源码 checkout 中执行原始测试与生成器后复核：
python3 Tools/repair_rc21_source.py \
  --source /path/to/source-rc21 \
  --evidence /path/to/source-rc21-evidence --verify
```

证据目录必须位于源码 checkout 之外。CI 产物包含基线/候选 tree、控制分支提交、修复 manifest、完整源码 diff、逐轮验证记录和各检查日志；源码仓库及其发布记录不由该任务修改。

## 3. 验收范围

流水线包含四个独立结论：可复现输入、依赖安全、当前 SDK 原生验收、RC21 源码修复候选验收。安全审计覆盖所有五个当前 SDK 生成工具依赖图，以及源码候选的四个生成工具依赖图，保留原有 `--audit-level=high` 门槛。修复没有排除公告、降低阈值或使用 `continue-on-error`。

原生验收覆盖四个独立产品消费者：仅 Lang、仅 Core、仅标准 UI 和仅 Intelligent UI。每个外部包只声明对应的一个产品；编译期检查禁止 Lang 导入 Core/UI、Core 导入两套 UI、任一 UI 导入另一套库。Core 和两套 UI 使用相同宿主模板，Lang 直接使用语言契约、解析和流式接口。Lang 不依赖 SwiftUI 另由模块图与源码边界检查验证。

其余原生验收覆盖全部原生测试、Release fitting、独立 Gallery 测试与双库案例完整/流式验证、完整历史契约、语言 ASan、独立契约/性能工具及 iOS 编译。独立检查在前一个检查失败后仍可收集证据，但任何检查失败都会保留为任务失败。消费者源码生成或语法检查不等于实际 Swift 编译通过；原生编译与测试结果以对应提交的执行日志为准。

这些记录用于验证当前分支的实现与构建；真机交互、产品发布和合并仍是独立的交付动作。
