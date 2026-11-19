# OpenUI Swift SDK 文档站

面向当前 [zyfn/open-intelligent-ui-swift](https://github.com/zyfn/open-intelligent-ui-swift) 原生 SDK 的公开开发者文档，而非 RC20 存档。迁移了旧站的编辑式视觉方向，但只展示当前 SDK 语义与权威接口。

## 内容

- SwiftLang、SwiftOpenUI、SwiftIntelligentUI 分层和两套 Library 的关系
- 当前 `OpenUILibrary.specificationJSON` 导出的可搜索组件契约（不是静态手写组件表）
- 正式 SwiftPM 接入路径、状态/流式与生成契约
- 跳转到现有 README、架构、两个组件指南、原生 Gallery、验证说明

GitHub Pages 网站本身是 React + Vite 静态页面，不执行 SwiftUI，不把 Web 演示冒充原生截图。原生验收以当前 Gallery 与 CI 为准。

## 本地使用

在 macOS / Xcode / Swift 6 环境中从仓库根目录：

```sh
cd docs-site
npm ci
npm run generate:current
npm run dev
npm run build
```

生成的 `public/current/*.json` 被忽略，CI 在构建前通过 `tools/GuideExport` 使用 SDK 现有 `OpenUILibrary.specificationJSON` 导出。它不会修改 `Sources/`、`Tests/`、`Package.swift` 或原生组件库。无需另维护一份 JSON Schema。

## 发布

工作流 `.github/workflows/docs-site-pages.yml` 在 main 的站点改动或手动触发时构建并部署 GitHub Pages。

预期地址：<https://zyfn.github.io/open-intelligent-ui-swift/>。需要仓库 Pages 配置允许 GitHub Actions 部署。旧站 <https://zyfn.github.io/openui/> 保持原样，旧版 RC20 组件演示仍可在那里访问。
