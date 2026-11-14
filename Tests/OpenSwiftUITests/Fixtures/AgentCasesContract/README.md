# Standard case contract fixtures

`manifest.json` 与 `test-library-spec.json` 是八个标准案例的固定回归输入，迁移时保留原字节。它们只用于检查历史内容摘要及组件契约，不能覆盖 Gallery 运行时的实际 reader。

程序唯一源码位于 [Gallery standard cases](../../../../Examples/Gallery/Resources/Cases/standard/)。`AgentExampleContractTests` 分别读取这里的固定契约与那里实际展示的程序，继续验证原有流式、表单和签名断言；不为测试再复制八份源码。
