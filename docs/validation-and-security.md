# 验证与安全修复

本文记录四模块重构之后的依赖与源码验证修复。当前实现和安全修复在 `refactor/openui-four-module-foundation` 分支维护；具体提交的验收结果以 [Native SDK 流水线](https://github.com/zyfn/open-intelligent-ui-swift/actions/workflows/native-sdk.yml) 和 [PR #3](https://github.com/zyfn/open-intelligent-ui-swift/pull/3) 为准。历史导入的提交、文件映射和资源哈希仍保留在 [IMPORT.json](../OpenUI/IMPORT.json)。

## 1. 实际打包依赖与可复现生成

| 依赖 | 当前固定版本 | 修复与验证 |
|---|---|---|
| Zod | `4.6.7` | 修复约束集合校验的内存耗尽问题；重新生成语言 bundle、manifest 与 oracle 构建指纹 |
| KaTeX | `0.18.2` | 修复从原型继承信任选项的问题；更新标准富文本与 Intelligent UI 实际使用的公式资源 |

官方安全公告分别为 [GHSA-mrhx-c7xc-m3w5](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5) 和 [GHSA-238p-pmpm-9mq7](https://github.com/advisories/GHSA-238p-pmpm-9mq7)。后一个问题依赖于已有原型污染；修复后的依赖不再把继承的选项视为应用主动启用信任。

这些更新使用 npm 提供的真实 tarball 与 integrity，锁文件固定构建图。标准富文本中直接和传递的 KaTeX 使用相同的精确版本。Intelligent UI 的 MathML 引擎也由受审计的生成工具维护，避免只更新 npm 依赖而遗留旧的运行时文件。

语言上游仍是 `@openuidev/lang-core` 1.0.2，来源 revision、位置参数补丁和适配后的语言源码树保持不变。Zod 更新后的严格 oracle fixture 只有 `oracleSHA256` 改变；解析、动作、查询、序列化及其来源期望保持原值。原生契约检查仍对照固定的历史 Intelligent UI 基线，完整比较组件顺序、位置参数和 schema。

Zod 4.6.7 的 JSON Schema 导出新增了把纯标量 `anyOf` 合并成 `type` 数组的优化。两种写法表达相同类型集合，但本 SDK 保留既有导出契约，因此在现有构建兼容层中仅禁用该导出压缩步骤。共享适配同时用于原生 bundle 和官方组件目录生成，严格校验 Zod 版本、源文件 SHA-256、唯一匹配的替换片段及变换后 SHA-256；清单中的 `dependencyTransforms` 记录这些证据。Zod 的解析、校验和修复后的集合限制不受此导出适配影响。

组件目录继续与原已提交文件逐字一致，不刷新 schema 期望来接受漂移。新增回归直接执行实际打包的 `nativeAuthoring`，覆盖联合分支顺序、nullable、类型数组输入、默认值、约束、嵌套、参数顺序及历史 parser 结果。

标准富文本生成器继续嵌入字体，运行时不加载外部 CSS 或字体。Intelligent UI 继续输出 MathML，保留原来的 `trust: false`、严格语法、展开次数和输出大小限制。公式安全回归在隔离的 JavaScript 上下文中验证原型污染不能开启受信任渲染，并覆盖有效公式与非法输入。

当前资源版本与内容哈希由各资源 manifest 记录。生成器运行后，CI 要求资源与当前提交逐字一致；它不再要求后续安全修复继续等于原始导入的旧哈希。

## 2. RC21 源码修复候选

`source-rc21-gate` 使用 `zyfn/openui` 的固定基线 `f3dfa1d0b479c131b6d4268e81961186f22ff09c`，然后应用本分支保存的 [修复清单](../OpenUI/Validation/source-rc21/manifest.json)。该任务检验的是“固定源码 + 已审查修复”的候选，不把修补结果记成未经修改的原始源码通过。

修复包括以下真实问题：

- 原视觉测试直接写只读的 SwiftUI `accessibilityReduceMotion` 环境值，在当前 Xcode 上无法编译。改用已有 presentation 配置和 transaction 控制动画，保留原视觉断言。
- 原 ObjectCard 图片边缘测试使用没有图片地址的占位内容来断言红色图片。改用已加载的确定性红色 PNG，保留边缘、留白、像素坐标和阈值断言。
- 源码候选的 Zod 与 KaTeX 同步升级，生成器接入同一份精确 JSON Schema 导出适配后独立重建；原始 Lang 源码不变。源路径下的适配器哈希按其实际生成器单独计算，清单包含这些经过审查的修改。
- 源码中三份 presentation 锁文件的遗留私有下载地址改为公开 npm registry；该地址规范化逐项保留包版本、integrity 和其余元数据，并使用全新 npm cache 验证实际下载与审计。

[修复工具](../Tools/repair_rc21_source.py) 验证基线 HEAD 和完整 tree、补丁 SHA-256、每个文件的前后哈希、允许变化的文件集合及完整候选 tree。可复用的生成资源也通过精确哈希声明来源。工具不移动基线 HEAD，不写入源码仓库的真实 index；它用临时 index 计算完整候选 tree。

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

原生验收覆盖两套独立产品消费者、全部原生测试、Release fitting、Gallery fixtures、完整历史契约、语言 ASan、独立 macOS 示例和 iOS 编译。独立检查在前一个检查失败后仍可收集证据，但任何检查失败都会保留为任务失败。

这些记录用于验证当前分支的实现与构建；真机交互、产品发布和合并仍是独立的交付动作。
