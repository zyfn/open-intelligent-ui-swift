# Language runtime benchmark

独立 SwiftPM 消费者，仅依赖公开 `OpenUILang` 产品。要求 macOS 13+ 与 Swift 6 工具链。

初始 `Package.resolved` 沿用根 SDK 的既有 pins，未在本次无 Swift 的环境中重新解析。SwiftPM 仍可能解析根包的传递包图，但该 executable 只链接 Lang 产品，不导入 UI 模块。

从仓库根目录运行：

```sh
Benchmarks/LanguageRuntime/run.sh
Benchmarks/LanguageRuntime/run.sh --iterations 1000 --warmup 20 --rows 60
```

runner 使用 Release 构建，将结果写入 `outputs/benchmarks/language-runtime.json` 并输出到终端。可传 `--output /absolute/path/report.json` 保存另一次测量。

每次迭代创建 parser、Store 与 evaluator，解析包含 30 个文字节点的固定程序，执行一次初始求值和三次状态更新后的求值。参数允许改变节点数、预热与测量次数。输出 p50/p95/最大耗时、实际构建配置及每 100 次迭代的进程 RSS 样本。

它不创建 SwiftUI 视图，因此不能代表布局成本、帧率或真机体验。RSS 包含 JavaScript VM、分配器和缓存保留，单纯增长不等于内存泄漏；工具不访问 SDK 内部 GC 或私有运行时。对比时记录提交、工具链、机器、参数，并使用相同条件。新的公开 API 工作负载与旧内部 GC 驱动数据不直接作性能回归比较。
