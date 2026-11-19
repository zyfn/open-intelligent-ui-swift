import React, { useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  ArrowUpRight, ArrowRight, BookOpen, Braces, Check, ChevronRight,
  Code2, Copy, GitBranch, Layers, Moon, Play, ShieldCheck, Sun,
  Workflow, Zap
} from "lucide-react";
import CurrentSDK from "./CurrentSDK";
import { HeroArt, EditorialShowcase, DesignStudio } from "./EditorialExperience";
import "./editorial.css";
import "./site.css";

const repo = "https://github.com/zyfn/open-intelligent-ui-swift";
const docs = [
  { title: "SDK 接入指南", sub: "安装、运行、契约导出与状态生命周期", href: repo + "/blob/main/README.md", marker: "01" },
  { title: "架构与职责", sub: "SwiftLang、组件库、状态与渲染的真实分层", href: repo + "/blob/main/docs/architecture.md", marker: "02" },
  { title: "OpenUI", sub: "组件语义、原生设计与生成规则", href: repo + "/blob/main/docs/openui.md", marker: "03" },
  { title: "Intelligent UI", sub: "布局、交互、媒体、设计系统及生成契约", href: repo + "/blob/main/docs/openintelligentui.md", marker: "04" },
  { title: "原生 Gallery", sub: "macOS / iOS 上的真实组件与流式预览", href: repo + "/tree/main/Examples/Gallery", marker: "05" },
  { title: "验证与性能", sub: "安全、回归、Release 测量与开放问题", href: repo + "/blob/main/docs/validation-and-security.md", marker: "06" }
];

const examples = {
  openui: {
    label: "OpenUI",
    module: "SwiftOpenUI",
    product: "swift-ui",
    create: ".openUI()",
    program: 'root = Stack([TextContent("你好，OpenUI")])'
  },
  intelligent: {
    label: "Intelligent UI",
    module: "SwiftIntelligentUI",
    product: "swift-intelligent-ui",
    create: ".openIntelligentUI()",
    program: 'root = Col([Text("你好，Intelligent UI")])'
  }
} as const;

type Choice = keyof typeof examples;

function CodeSample({ value, mini = false }: { value: string; mini?: boolean }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className={"code-sample" + (mini ? " code-sample--mini" : "")}>
      <button type="button" className="copy-code" aria-label="复制代码"
        onClick={async () => {
          try {
            await navigator.clipboard.writeText(value);
            setCopied(true);
            window.setTimeout(() => setCopied(false), 1200);
          } catch { setCopied(false); }
        }}>
        {copied ? <Check size={15} /> : <Copy size={15} />}
        <span>{copied ? "已复制" : "复制"}</span>
      </button>
      <pre><code>{value}</code></pre>
    </div>
  );
}

function App() {
  const [library, setLibrary] = useState<Choice>("openui");
  const [dark, setDark] = useState(false);
  const sample = examples[library];
  const source = useMemo(() => [
    "import " + sample.module,
    "",
    "let library: OpenUILibrary = try " + sample.create,
    "let state = library.makeState()",
    "",
    "state.onAction = { event in",
    "    // Forward to your app's action handler.",
    "}",
    "",
    "state.setSource(#\"" + sample.program + "\"#)",
    "let view = OpenUIView(state: state, library: library)"
  ].join("\n"), [sample]);

  return (
    <div className="site" data-theme={dark ? "dark" : "light"}>
      <header className="topbar">
        <a href="#top" className="brand" aria-label="返回首页">
          <span className="brand-symbol">ui<span>.</span></span>
          <span className="brand-copy">OPENUI <i>/</i> SWIFT SDK</span>
        </a>
        <nav aria-label="站点导航">
          <a href="#overview">架构</a>
          <a href="#showcase">案例</a>
          <a href="#design">设计系统</a>
          <a href="#components">组件</a>
          <a href="#integration">接入</a>
        </nav>
        <div className="top-actions">
          <button type="button" className="theme-toggle" onClick={() => setDark(!dark)} aria-label={dark ? "切换浅色" : "切换深色"}>
            {dark ? <Sun size={18} /> : <Moon size={18} />}
          </button>
          <a href={repo} target="_blank" rel="noreferrer" className="github-link">GitHub <ArrowUpRight size={15} /></a>
        </div>
      </header>

      <main id="top">
        <section className="hero" aria-labelledby="hero-heading">
          <div className="hero-copy">
            <div className="eyebrow"><span className="eyebrow-dot" /> NATIVE GENERATIVE UI / VOL. 01</div>
            <h1 id="hero-heading">让回答，<br /><em>长成界面。</em></h1>
            <p className="lede">从一段文字，到一个可理解、可探索、可操作的界面。为 iOS 与 macOS 构建的原生生成式 UI，保持设计的秩序，也保留内容的自由。</p>
            <div className="hero-actions">
              <a href="#showcase" className="button-primary">探索案例 <ArrowRight size={17} /></a>
              <a href="#integration" className="button-quiet">快速接入 <ChevronRight size={17} /></a>
            </div>
            <div className="hero-facts">
              <div><strong>1.1.1</strong><span>OpenUI Lang Core</span></div>
              <div><strong>02</strong><span>独立 Library</span></div>
              <div><strong>16+</strong><span>iOS 最低版本</span></div>
              <div><strong>13+</strong><span>macOS 最低版本</span></div>
            </div>
          </div>
          <HeroArt />
        </section>

        <section id="overview" className="section architecture" aria-labelledby="arch-title">
          <div className="section-head">
            <div className="kicker">01 / SYSTEM</div>
            <h2 id="arch-title">一个运行时，两套表达体系。</h2>
            <p>SwiftLang 不依赖具体组件库。它负责解析、流式状态、动作、绑定和原生宿主；各 Library 提供自己的组件契约、设计系统与视图实现。</p>
          </div>
          <div className="architecture-map">
            <div className="arch-item arch-host"><span>APPLICATION</span><strong>Agent / Host</strong><p>模型通信 · 会话管理 · 工具与业务动作</p></div>
            <div className="arch-connector"><i/><i/></div>
            <div className="arch-libs">
              <div className="arch-item"><span>LIBRARY A</span><strong>SwiftOpenUI</strong><p>Stack · TextContent · 业务内容</p></div>
              <div className="arch-item"><span>LIBRARY B</span><strong>SwiftIntelligentUI</strong><p>Col · Row · Grid · 基础原语</p></div>
            </div>
            <div className="arch-connector"><i/><i/></div>
            <div className="arch-item arch-core"><span>SHARED RUNTIME</span><strong>SwiftLang</strong><p>Parser · State · Streaming · Actions · Renderer</p></div>
            <div className="arch-connector arch-one"><i/></div>
            <div className="arch-item arch-bottom"><span>LANGUAGE ENGINE</span><strong>@openuidev/lang-core 1.1.1</strong><p>随 SDK 打包，通过 JavaScriptCore 运行</p></div>
          </div>
          <div className="architecture-notes">
            <div><Layers size={19}/><span><strong>同一接入接口</strong>OpenUILibrary · OpenUIState · OpenUIView</span></div>
            <div><Workflow size={19}/><span><strong>独立组件契约</strong>新输出与历史 Reader 分别管理</span></div>
            <div><ShieldCheck size={19}/><span><strong>原生行为边界</strong>真实交易、网络与会话由宿主处理</span></div>
          </div>
        </section>

        <EditorialShowcase />
        <DesignStudio />

        <section id="components" className="components-section">
          <CurrentSDK />
        </section>

        <section id="integration" className="section integration" aria-labelledby="integration-title">
          <div className="section-head">
            <div className="kicker">05 / INTEGRATION</div>
            <h2 id="integration-title">最小接入，完整控制。</h2>
            <p>选择 SwiftPM 产品后，生成 Prompt、组件注册、状态和原生 View 都使用同一个 Library。不要用 Intelligent UI 的 Reader 解释历史 Stack 程序。</p>
          </div>
          <div className="integration-grid">
            <div className="integration-copy">
              <div className="step"><span>01</span><div><h3>选择组件库</h3><p>OpenUI 使用 <code>swift-ui</code>；Intelligent UI 使用 <code>swift-intelligent-ui</code>。两者共享 <code>SwiftLang</code>。</p></div></div>
              <div className="step"><span>02</span><div><h3>生成并输入内容</h3><p>将 <code>library.systemPrompt</code> 与 <code>library.specificationJSON</code> 提供给生成端；客户端使用 <code>push / complete / interrupt</code>。</p></div></div>
              <div className="step"><span>03</span><div><h3>由宿主管理生命周期</h3><p>每条活跃文档保持同一 State。资源、业务回调和消息分页不由组件库替代。</p></div></div>
            </div>
            <div className="integration-editor">
              <div className="integration-editor-top">
                <div className="file-label"><Code2 size={15}/> Native integration</div>
                <div className="switch-small" role="group" aria-label="接入组件库">
                  <button type="button" aria-pressed={library==="openui"} onClick={()=>setLibrary("openui")}>OpenUI</button>
                  <button type="button" aria-pressed={library==="intelligent"} onClick={()=>setLibrary("intelligent")}>Intelligent UI</button>
                </div>
              </div>
              <CodeSample value={source}/>
              <div className="source-caption">模型新输出使用 {sample.label} 的 root：<code>{library==="openui"?"Stack":"Col"}</code>。</div>
            </div>
          </div>
          <a href={repo+"/blob/main/README.md"} className="text-link" target="_blank" rel="noreferrer">阅读完整接入文档 <ArrowUpRight size={16}/></a>
        </section>

        <section id="references" className="section references">
          <div className="section-head">
            <div className="kicker">06 / DOCUMENTATION</div>
            <h2>从源码和真实文档出发。</h2>
            <p>组件信息从 SDK 当前生成契约导出。设计、架构与验收结论始终以各自权威文档和真实原生 Gallery 为准。</p>
          </div>
          <div className="reference-list">
            {docs.map((d)=><a key={d.marker} href={d.href} target="_blank" rel="noreferrer" className="reference-item">
              <span className="reference-index">{d.marker}</span>
              <span className="reference-text"><strong>{d.title}</strong><small>{d.sub}</small></span>
              <ArrowUpRight size={18}/>
            </a>)}
          </div>
          <div className="verification-note"><BookOpen size={19}/><span>这里的组件签名是编译时导出的<strong>真实 SDK 契约</strong>。网站并不假装能在浏览器中执行 SwiftUI：界面外观、无障碍和交互须在原生 Gallery 验证。</span></div>
        </section>
      </main>
      <footer className="footer">
        <div><span className="brand-symbol">ui<span>.</span></span><span>OpenUI Swift SDK</span></div>
        <span>Native components · Shared runtime · Generated contracts</span>
        <a href={repo} target="_blank" rel="noreferrer">Source <ArrowUpRight size={14}/></a>
      </footer>
    </div>
  );
}

createRoot(document.getElementById("root")!).render(<App/>);
