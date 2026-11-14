# Recorded generation fixtures

六份 JSON 是 2026-11-03 至 2026-11-04 保存的未改写模型程序：reading、budget、comparison、editorial、transport、shopping。迁移目录时程序字节保持不变；`RecordedGenerationTests` 用它们检查当前运行时兼容性。

当时请求模型为 `gpt-6.1-terra`，客户端记录为 `codex-cli 0.166.0-alpha.5.1`；CLI 没有提供实际响应模型 ID，不能将请求值当成独立确认的实际模型身份。历史版本范围为 `0.1.0-preview.1`、`.10`、`.11`。原始运行记录可从迁移前的 Git 历史查看。

这些是固定回归输入，不是当前模型质量结论或当前 UI 验收证据。新模型评测见 [Validation/Generation](../../../../Validation/Generation/README.md)；人工浏览使用 [Gallery](../../../../Examples/Gallery/README.md)。
