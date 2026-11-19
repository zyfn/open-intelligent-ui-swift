# Swift SDK 交互式文档站

基于旧站 [zyfn/openui/sites/swift-sdk](https://github.com/zyfn/openui/tree/e3fec603efbd876e8d6527a1fdf77dd184b7af50/sites/swift-sdk) 迁移。文档站是独立的 Vite/React 应用，不修改 SwiftLang、SwiftOpenUI、SwiftIntelligentUI 或 Gallery 的实现。

## 文档边界

首页首先展示**当前 SDK**真实的 OpenUI / Intelligent UI 组件语言契约。数据来自现有 OpenUILibrary 的 specificationJSON，构建时导出，并非手写的另一套 schema。

下方保留原站 RC20 的文章、历史组件说明、交互样例和 React Web 预览。历史标本使用固定的 React 0.18.1 运行环境与当时导出的数据；它不宣称与新 SwiftUI SDK 逐像素一致。旧站地图与 SVG 的原生截图通过固定提交的 GitHub 原始地址引用，没有复制大体积历史二进制文件。

## 本地开发（macOS + Swift 6 / Xcode）

从仓库根目录运行：

~~~~sh
cd docs-site
npm ci
npm run generate:current
npm run dev
~~~~

检查生产构建：

~~~~sh
npm run build
~~~~

generate:current 仅在 docs-site/public/current 写入导出的静态 JSON，不改动 SDK 源码和 Package.swift，也不重编写组件注册定义。public/current 是构建产物，不作为另一份权威组件清单提交。仅执行 npm run build 不会凭空生成它；GitHub Pages 工作流会先运行导出。

## 发布

文档站位于 docs-site，发布工作流位于 .github/workflows/docs-site-pages.yml。只有合并到 main 且触及文档站路径时才会触发 Pages 部署；PR 只进行构建验证。新仓库的 Pages 地址是 https://zyfn.github.io/open-intelligent-ui-swift/，实际是否可访问取决于 GitHub Pages 设置与工作流成功与否。

旧站仍保留在 https://zyfn.github.io/openui/，不直接修改或替换其部署。历史链接 #component-TextContent 在迁移后的站点仍指向旧 RC20 交互标本。

## 维护原则

SDK 源码、生成契约和设计指南继续以仓库现有 Sources、docs 和 Examples/Gallery 为准。网页只负责展示，不另建 Lang 语义、设计 Token 或运行时；新增样例需注明其来自当前原生库还是历史 Web 演示。
