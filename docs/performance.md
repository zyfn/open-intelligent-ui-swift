# 性能优化记录

文档版本：1.0 · 更新日期：2026-11-18

记录已合入的性能改动，相关修正归入同一主题。每次优化补充“优化了什么、实际效果、版本与证据”，后续复测更新原条目。日期按 Asia/Shanghai；耗时只适用于所列负载，工作量和缓存上限不等于设备提速；没有同条件耗时或内存对照的项目标为“未量化”。

## 优化记录

| 日期 / 版本 | 优化了什么 | 实际效果 | 证据 |
| --- | --- | --- | --- |
| 11-18 · [e11f23b](https://github.com/zyfn/open-intelligent-ui-swift/commit/e11f23b) | 查询依赖递归复用已闭合、无引用的语法判断，跳过重复扫描。 | 固定探针枚举 **606→6 次**；同机 Mac Release、128 单位分片的 push p95 范围 **34.64–43.93→24.60–31.59 ms**。24 单位仍波动，候选最大 push **111.99 ms**。 | [同机对照](validation-and-security.md#同机对照与阶段证据) |
| 11-18 · [fc45e0a](https://github.com/zyfn/open-intelligent-ui-swift/commit/fc45e0a) → [807d016](https://github.com/zyfn/open-intelligent-ui-swift/commit/807d016) | 同一组件目录复用 reader 元数据，每份文档仍保持独立运行状态。 | `807d016` 同进程重复创建文档，Release p50 **137.74→14.03 ms**，Debug **109.38→13.16 ms**；各路径 12 次。Release 首次准备仍为 **141.55 ms**。 | [文档创建测量](validation-and-security.md#sdk-正常接入与生命周期审查) |
| 11-16～18 · [fe81f25](https://github.com/zyfn/open-intelligent-ui-swift/commit/fe81f25) → [fc45e0a](https://github.com/zyfn/open-intelligent-ui-swift/commit/fc45e0a) | 按节点及实际字段订阅，稳定呈现跳过重复处理；分离输入比较和挂载观察，移除 11 处无用 State 订阅。 | 原生订阅回归：**40 个稳定标量叶子、4 次真实尾部 push，通知为 0**。这不是全部 SwiftUI body/布局计数；滚动收益未量化。 | [更新收敛](validation-and-security.md#流式重复工作收敛)、[挂载修正](validation-and-security.md#客户端复测收尾候选) |
| 11-17～18 · [05f0786](https://github.com/zyfn/open-intelligent-ui-swift/commit/05f0786) → [fc45e0a](https://github.com/zyfn/open-intelligent-ui-swift/commit/fc45e0a) | Markdown 首次后台准备期间复用可读内容，成功覆盖后释放旧备用源码和解析树。 | 受控回归中，等待期间 **100 次追加只做 1 次首次备用解析**，中间结果继续推进。设备耗时及释放字节未量化。 | [正文准备](validation-and-security.md#openui-图片与首次正文准备)、[回收](validation-and-security.md#sdk-正常接入与生命周期审查) |
| 11-17 · [7ed102a](https://github.com/zyfn/open-intelligent-ui-swift/commit/7ed102a) | Flex 测量与放置复用同一有效 proposal 的帧计算；表格在每次 body 中集中派生列及分页。 | 同 proposal 的重复请求只执行 **1 次帧计算**；内容、宽度、字体变化仍正确失效。真实滚动收益未量化。 | [布局与表格](validation-and-security.md#完成长文档的滚动与布局) |
| 11-16～17 · [73544e4](https://github.com/zyfn/open-intelligent-ui-swift/commit/73544e4) → [2db9367](https://github.com/zyfn/open-intelligent-ui-swift/commit/2db9367) | Query 呈现共用快照和错误数组，反馈一次遍历完成，减少临时数组。 | 真实 JS manager 读取探针：40 个 Query 的错误项读取 **1,600→40 次**，结果一致。原生耗时未量化；完整快照序列化仍待优化。 | [批量读取](validation-and-security.md#a4808be-复测后的流式成本修复)、[反馈](validation-and-security.md#query-反馈去重与终态引号回归) |
| 11-16～17 · [3828c3c](https://github.com/zyfn/open-intelligent-ui-swift/commit/3828c3c) → [dad6d4f](https://github.com/zyfn/open-intelligent-ui-swift/commit/dad6d4f) | 图片预览只挂载当前及相邻页；已完成资源加入跨文档总预算和内存压力回收。 | 预览窗口最多 **3 页**；SDK 完成项缓存成本上限为图片 **64 MiB**、响应 **8 MiB**。这些是持有边界，进程内存收益未量化。 | [预览](validation-and-security.md#已合入基线的前轮修复与验证)、[缓存](architecture.md#文档与资源的生命周期) |
| 11-17 · [dad6d4f](https://github.com/zyfn/open-intelligent-ui-swift/commit/dad6d4f) | 桥接身份随原生对象释放，共享索引只留弱引用。 | 移除原来**每 32 次桥接的全表扫描**；释放及并发回归通过。净分配和 App 内存收益未量化。 | [身份生命周期](validation-and-security.md#文档资源生命周期) |
| 11-17 · [05f0786](https://github.com/zyfn/open-intelligent-ui-swift/commit/05f0786) | 按实际显示尺寸、倍率和裁剪方式解码图片，复用足够清晰的缓存及相同在途解码。 | 尺寸转换、像素目标和请求复用回归通过；CPU、内存及滚动收益未量化。仍下载原 URL，未声称减少下载字节。 | [图片解码](validation-and-security.md#openui-图片与首次正文准备) |
| 11-17 · [06c165f](https://github.com/zyfn/open-intelligent-ui-swift/commit/06c165f) | 流式预处理改为消费增量行，稳定完成行不再全文重扫。 | 200 个稳定叶子追加 50 次：全文按行切分 **50→0 次**，该步骤扫描 **244,325→0 UTF-16 units**。未完成行仍需处理；设备耗时未单独量化。 | [处理计数](validation-and-security.md#流式重复工作收敛) |
| 11-16～17 · [73544e4](https://github.com/zyfn/open-intelligent-ui-swift/commit/73544e4) → [06c165f](https://github.com/zyfn/open-intelligent-ui-swift/commit/06c165f) | JS/Swift 元数据成组读取；不可变函数和动作描述按所有者准备一次。 | 减少逐属性读取、临时包装和重复定义准备；对象默认值仍按执行上下文隔离。独立原生耗时未量化。 | [桥接](validation-and-security.md#a4808be-复测后的流式成本修复)、[定义准备](validation-and-security.md#流式重复工作收敛) |
| 11-16～17 · [1063d9f](https://github.com/zyfn/open-intelligent-ui-swift/commit/1063d9f) → [06c165f](https://github.com/zyfn/open-intelligent-ui-swift/commit/06c165f) | 复用无依赖 readiness 描述及纯语法闭合信息，保持业务值身份。 | `3828c3c→a4808be` 资源对照，`rows=200` / 24 单位：独立描述 **98,334→1,774 个**，元素访问仍为 **48,937 次**；后续纯语法复用未单独计时。 | [工作量对照](validation-and-security.md#性能证据与未完成项) |
| 11-16 · [1063d9f](https://github.com/zyfn/open-intelligent-ui-swift/commit/1063d9f) / [a4808be](https://github.com/zyfn/open-intelligent-ui-swift/commit/a4808be) | 复用 parser tokens 做预算检查，去掉额外全前缀扫描；普通 push 合并重复发布。 | 客户端 `c731005→a4808be` 同机 Release 报告，`rows=200` / 24 单位：p95 **35.06→20.60 ms**，发布 **915→462 次/流**；最大 push **63.06→102.35 ms**，长尾未改善。另测 App Debug CPU **94.13%→92.79%**，未证明实质下降。 | [客户端报告](validation-and-security.md#客户端-a4808be-定向复测2026-11-16) |
| 11-16 · [a88dd28](https://github.com/zyfn/open-intelligent-ui-swift/commit/a88dd28) / [9af2de5](https://github.com/zyfn/open-intelligent-ui-swift/commit/9af2de5) | Store 单键读取只读目标键；宽对象按 UTF-16 键整理；当前匿名节点按对象身份查找。 | 去掉宽对象逐字段线性查找和当前节点全桶搜索，保留字段顺序与歧义检查。独立设备耗时未量化。 | [数据整理](validation-and-security.md#历史修复记录)、[单键读取回归](../Tools/Core/native-bridge.test.mjs) |

表内同主题后续正确性修正已随主线保留，具体执行版本见证据。p95 范围是多份报告各自 p95 的范围；不同机器、版本、样本量之间不直接比较。`rows=200` 的现有流式负载末态为 202 个元素，沿用参数描述以免混用旧报告的节点标签。

## 尚未关闭

- 细分块下的同步 push 长尾仍在；解析临时对象与原生投影是已测量的主要排查入口。
- Query 完整快照比较、多步 Action 更新及跨文档 JSC 等待仍需各自测量。
- Muse 完成长会话的滚动、真机表现和同进程内存生命周期仍需复测。

详细测量及验收见 [验证说明](validation-and-security.md)，复现命令见 [LanguageRuntime](../Benchmarks/LanguageRuntime/README.md)。
