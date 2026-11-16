# Language runtime benchmark

文档版本：1.0 · 更新日期：2026-11-16

独立 SwiftPM 消费者，仅依赖公开 `SwiftLang` 产品。要求 macOS 13+ 与 Swift 6 工具链。

初始 `Package.resolved` 沿用根 SDK 的既有 pins，未在本次无 Swift 的环境中重新解析。SwiftPM 仍可能解析根包的传递包图，但该 executable 只链接 Lang 产品，不导入 UI 模块。

从仓库根目录运行：

```sh
Benchmarks/LanguageRuntime/run.sh
Benchmarks/LanguageRuntime/run.sh --iterations 1000 --warmup 20 --rows 60
Benchmarks/LanguageRuntime/run.sh --iterations 100 --rows 200 --stream-iterations 10 --chunk-units 32
```

runner 使用 Release 构建，将结果写入 `outputs/benchmarks/language-runtime.json` 并输出到终端。可传 `--output /absolute/path/report.json` 保存另一次测量。

报告包含三个工作负载。原有语言工作负载每次迭代创建 parser、Store 与 evaluator，解析默认包含 30 个文字节点的固定程序，执行一次初始求值和三次状态更新后的求值。参数允许改变节点数、预热与测量次数。输出 p50/p95/最大耗时、实际构建配置及每 100 次迭代的进程 RSS 样本。

流式工作负载经过公开 `OpenUIState` 的 MainActor 路径：逐块送入包含稳定兄弟节点和不断增长的 ASCII 文本尾部的真实程序，最后调用 `complete()`；验证末态内容完整。默认测量 20 次，每块 128 个 UTF-16 units；`--stream-iterations` 与 `--chunk-units` 可改变测量次数和输入频率。报告逐次 push、complete 和整条流的 p50/p95/最大耗时，并记录解析回调与 `objectWillChange` 发布次数。它测到适配层的解析、求值和投影，不是重复提交同一缓冲区的空操作测试。对比不同分块大小时保持程序、机器、工具链和迭代数一致。

宽对象工作负载构造包含 10,000 个不同字段及一次重复写入的 `OpenUIObject`，检查原始位置与最后写入值，并记录构造耗时。它覆盖工具/状态对象在 JS 求值预算之外的原生字段整理成本，测量次数沿用 `--stream-iterations`。

它不创建 SwiftUI 视图，因此发布次数不是组件 body 次数，耗时也不能代表布局成本、帧率或真机体验。RSS 样本覆盖原有语言工作负载，包含 JavaScript VM、分配器和缓存保留，单纯增长不等于内存泄漏；工具不访问 SDK 内部 GC 或私有运行时。对比时记录提交、工具链、机器、参数，并使用相同条件。新的公开 API 工作负载与旧内部 GC 驱动数据不直接作性能回归比较。
