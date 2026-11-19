import { useEffect, useState } from "react";
import { ArrowRight, ArrowUpRight, BookOpen, ChevronRight, Image as ImageIcon, MapPin, MoveRight, Sparkles } from "lucide-react";

const galleryRoot = "https://github.com/zyfn/open-intelligent-ui-swift/blob/main/Examples/Gallery/Resources/Cases/openintelligentui/";
const lakeImage = "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f9/West_Lake_%28Hangzhou%29_sunset_2016_January.jpg/960px-West_Lake_%28Hangzhou%29_sunset_2016_January.jpg";
const palaceImage = "https://upload.wikimedia.org/wikipedia/commons/thumb/8/8c/Deshou_Palace.jpg/960px-Deshou_Palace.jpg";

type Case = "travel" | "analysis" | "explainer";
const samples: Record<Case, { n: string; title: string; English: string; desc: string; path: string }> = {
  travel: {
    n: "01", title: "两天，两种杭州。", English: "THE ART OF EXPLORATION",
    desc: "连续的叙事、适合的图片与时间安排。一个旅行回答可以读起来像一本旅行杂志，而不必处处都是卡片。",
    path: galleryRoot + "hangzhou-weekend.openui"
  },
  analysis: {
    n: "02", title: "让数字自己说话。", English: "DATA, IN CONTEXT",
    desc: "重要的不只是图表，而是同一个页面里，筛选、数值、解释与计划能够围绕同一份状态协作。",
    path: galleryRoot + "monthly-spending.openui"
  },
  explainer: {
    n: "03", title: "把抽象概念画出来。", English: "A BETTER WAY TO EXPLAIN",
    desc: "有时候一张流程示意，比一大段说明更容易理解。Agent 选择的不只是文字，也是一种表达媒介。",
    path: galleryRoot + "heat-pump.openui"
  }
};

export function HeroArt() {
  return (
    <div className="editorial-cover" aria-label="来自当前 Gallery 行程案例的编辑式网页示意">
      <div className="editorial-cover__photo">
        <img src={lakeImage} alt="杭州西湖夕阳与湖面，来自当前 SDK Gallery 的图片清单" loading="eager" />
        <span className="editorial-cover__volume">O P E N U I / V O L . 0 1</span>
        <div className="editorial-cover__footer"><span>FIELD NOTES</span><span>HANGZHOU, CHINA</span></div>
      </div>
      <div className="editorial-cover__folio">
        <div className="cover-folio-heading">
          <span>01 — FIELD REPORT</span>
          <span className="dot-medium" />
        </div>
        <div className="cover-folio-body">
          <div className="cover-kicker">DESIGN IN MOTION</div>
          <strong>两天，<br />两种杭州。</strong>
          <p>一段由内容决定形态的旅程。</p>
        </div>
        <div className="cover-folio-bottom">
          <span>图文 · 路线 · 交互</span>
          <MapPin size={16} aria-hidden="true" />
        </div>
      </div>
      <div className="cover-side-index">A / 01 &nbsp; · &nbsp; AN EXPRESSION STUDY</div>
      <p className="editorial-cover__credit">
        图片：Morio / CC BY-SA 4.0 · 当前 Gallery 图片素材。网页排版示意，非原生 SwiftUI 截图。
      </p>
    </div>
  );
}

function TravelSpecimen() {
  const [day, setDay] = useState(0);
  return (
    <div className="showcase-page travel-page">
      <div className="page-eyebrow">HANGZHOU / A VISUAL JOURNEY</div>
      <div className="page-headline">杭州两日 · 实景预览</div>
      <div className="page-intro">南宋临安的宫苑，与西湖边的文人遗迹。让两天拥有不同的阅读节奏。</div>
      <div className="travel-photo-main">
        <img src={day === 0 ? palaceImage : lakeImage} loading="lazy" alt={day === 0 ? "德寿宫图片素材" : "杭州西湖图片素材"} />
        <div className="travel-image-overlay">{day === 0 ? "THE SOUTHERN SONG" : "WEST LAKE STORIES"}</div>
      </div>
      <div className="day-nav" role="group" aria-label="切换旅行日">
        <button type="button" onClick={() => setDay(0)} aria-pressed={day === 0}>DAY 01 · 临安</button>
        <button type="button" onClick={() => setDay(1)} aria-pressed={day === 1}>DAY 02 · 西湖</button>
      </div>
      <div className="travel-day-copy">
        <div><small>{day === 0 ? "HERITAGE / 01" : "LANDSCAPE / 02"}</small>
          <h4>{day === 0 ? "循着宋韵，走入旧时临安。" : "沿湖而行，寻找文人留下的足迹。"}</h4>
          <p>{day === 0 ? "官窑博物馆 → 德寿宫 → 南宋遗址陈列馆" : "苏堤 → 岳王庙 → 孤山与放鹤亭"}</p>
        </div>
        <span className="day-count">0{day + 1}<small>/ 02</small></span>
      </div>
    </div>
  );
}

function AnalyticsSpecimen() {
  const [period, setPeriod] = useState<"month" | "quarter">("month");
  const items = period === "month"
    ? [{ name: "住房", value: 3000 }, { name: "餐饮", value: 1800 }, { name: "交通", value: 600 }, { name: "其他", value: 1200 }]
    : [{ name: "住房", value: 9000 }, { name: "餐饮", value: 4800 }, { name: "交通", value: 1500 }, { name: "其他", value: 2700 }];
  const sum = items.reduce((a, v) => a + v.value, 0);
  return (
    <div className="showcase-page analytic-page">
      <div className="page-eyebrow">MONEY NOTES / AUG — OCT</div>
      <div className="page-headline">花费增加，主要不在房租。</div>
      <div className="page-intro">同一份示例账单，不同统计范围。每一次选择，都让数据和解释一起变化。</div>
      <div className="analytic-main">
        <div className="analytic-caption">{period === "month" ? "10 月 · TOTAL SPENT" : "8—10 月 · TOTAL SPENT"}</div>
        <div className="analytic-total">¥{sum.toLocaleString("en-US")}</div>
        <div className="analytic-line"><span>{period === "month" ? "住房保持 ¥3,000" : "三个月累计"}</span><span>4 CATEGORIES</span></div>
        <div className="analytic-bar" role="img" aria-label="分项支出占比图">
          {items.map((item, i) => <span key={item.name} className={"analytic-bar-piece piece-" + i} style={{ width: item.value / sum * 100 + "%" }} />)}
        </div>
        <div className="analytic-legend">
          {items.map((item, i) => <div key={item.name}><span className={"legend-dot piece-" + i}/><small>{item.name}</small><b>¥{item.value.toLocaleString("en-US")}</b></div>)}
        </div>
      </div>
      <div className="analytic-switch" role="group" aria-label="切换统计周期">
        <button type="button" aria-pressed={period === "month"} onClick={() => setPeriod("month")}>10 月</button>
        <button type="button" aria-pressed={period === "quarter"} onClick={() => setPeriod("quarter")}>三个月合计</button>
      </div>
      <p className="analytic-note">数值来自当前 Gallery 的 monthly-spending 案例；此为 Web 讲解标本。</p>
    </div>
  );
}

function HeatPumpSpecimen() {
  const [mode, setMode] = useState<"heating" | "cooling">("heating");
  return (
    <div className="showcase-page science-page">
      <div className="page-eyebrow">EXPLAINED / HEAT PUMP</div>
      <div className="page-headline">冬天空调，为什么也能制热？</div>
      <div className="page-intro">热泵不是凭空制造热量，而是在室内和室外之间搬运热量。</div>
      <div className="science-visual">
        <div className="science-outside">
          <span>OUTSIDE / 室外</span>
          <div className="temp-number">{mode === "heating" ? "0°" : "32°"}</div>
          <p>{mode === "heating" ? "从空气中吸热" : "向空气中放热"}</p>
        </div>
        <div className="science-flow">
          <div className="science-engine"><span>压缩机</span><b>COMPRESSOR</b></div>
          <div className={"science-direction " + (mode === "cooling" ? "science-direction--reverse" : "")}><MoveRight size={35} strokeWidth={1.5} /></div>
          <small>HEAT TRANSFER</small>
        </div>
        <div className="science-inside">
          <span>INSIDE / 室内</span>
          <div className="temp-number">{mode === "heating" ? "22°" : "26°"}</div>
          <p>{mode === "heating" ? "向房间释放热量" : "从房间吸收热量"}</p>
        </div>
      </div>
      <div className="analytic-switch" role="group" aria-label="制热制冷方式">
        <button type="button" aria-pressed={mode === "heating"} onClick={() => setMode("heating")}>冬季制热</button>
        <button type="button" aria-pressed={mode === "cooling"} onClick={() => setMode("cooling")}>夏季制冷</button>
      </div>
      <p className="science-note">温度为原理示意，不代表固定工作值。流程图为网页示意，真实 Svg 组件需在原生 Gallery 核对。</p>
    </div>
  );
}

export function EditorialShowcase() {
  const [active, setActive] = useState<Case>("travel");
  const current = samples[active];
  return (
    <section className="editorial-showcase" id="showcase">
      <div className="editorial-showcase__top">
        <div className="section-issue">02 / COMPOSITIONS</div>
        <h2>界面不应该<br /><i>只有一种形状。</i></h2>
        <p>真正的生成式 UI，不是把所有内容塞进相同的容器。它应该让信息的关系，决定界面的组织。</p>
      </div>
      <div className="showcase-switch" role="tablist" aria-label="选择内容案例">
        {(["travel", "analysis", "explainer"] as const).map((key) => (
          <button key={key} role="tab" type="button" aria-selected={active === key} onClick={() => setActive(key)}>
            <span>{samples[key].n}</span><b>{key === "travel" ? "旅行 · 图文" : key === "analysis" ? "分析 · 数据" : "理解 · 图解"}</b>
            <ChevronRight size={16}/>
          </button>
        ))}
      </div>
      <div className="showcase-grid">
        <div className="showcase-stage">
          {active === "travel" ? <TravelSpecimen /> : active === "analysis" ? <AnalyticsSpecimen /> : <HeatPumpSpecimen />}
          <div className="showcase-frame-caption"><ImageIcon size={14}/><span>交互式 Web 排版标本 · 非 SDK 原生截图</span></div>
        </div>
        <div className="showcase-aside">
          <div className="showcase-number">{current.n}<span>/03</span></div>
          <div className="showcase-English">{current.English}</div>
          <h3>{current.title}</h3>
          <p>{current.desc}</p>
          <div className="showcase-properties">
            <span><Sparkles size={15}/> 内容与结构一同生成</span>
            <span><BookOpen size={15}/> 来自当前 SDK Gallery 案例</span>
          </div>
          <a href={current.path} target="_blank" rel="noreferrer" className="showcase-source">
            查看这份案例的真实 OpenUI Lang <ArrowUpRight size={17}/>
          </a>
        </div>
      </div>
    </section>
  );
}

type Font = { size?: number; weight?: number; family?: string; lineHeight?: number | null };
type ThemeData = { colors?: Record<string, { light: string; dark: string }>; metrics?: Record<string, number>; fonts?: Record<string, Font> };
const tok = {
  openui: [
    ["textNeutralPrimary", "主文字"],
    ["textNeutralSecondary", "辅助文字"],
    ["borderDefault", "轮廓线"],
    ["sunk", "下沉表面"]
  ],
  "intelligent-ui": [
    ["primaryText", "主文字"],
    ["secondaryText", "辅助文字"],
    ["separator", "分隔线"],
    ["surface", "次级表面"]
  ]
} as const;

export function DesignStudio() {
  const [library, setLibrary] = useState<"openui" | "intelligent-ui">("openui");
  const [theme, setTheme] = useState<ThemeData | null>(null);
  const [mode, setMode] = useState<"light" | "dark">("light");
  const [expanded, setExpanded] = useState(false);
  useEffect(() => {
    let active = true;
    setTheme(null);
    fetch(import.meta.env.BASE_URL + "current/theme-" + library + ".json")
      .then((r) => { if (!r.ok) throw new Error("not exported"); return r.json(); })
      .then((v: ThemeData) => { if (active) setTheme(v); })
      .catch(() => { if (active) setTheme(null); });
    return () => { active = false; };
  }, [library]);
  const metrics = theme?.metrics ?? {};
  const heading = theme?.fonts?.textHeadingMd?.size;
  const body = theme?.fonts?.textBodyDefault?.size;
  const group = metrics[library === "openui" ? "spaceML" : "groupSpacing"];
  const radius = metrics[library === "openui" ? "radius3xl" : "contentCardRadius"];
  return (
    <section className="design-studio" id="design">
      <div className="studio-heading">
        <div className="section-issue">03 / DESIGN LANGUAGE</div>
        <div className="studio-heading__split"><h2>字，间距，<br /><i>以及留白的秩序。</i></h2>
        <p>原来网站里最有价值的并不是卡片数量，而是能看懂每一层设计取舍。现在继续保留这种可探索的表达，但数据直接来自 SDK 的 Theme。</p></div>
      </div>
      <div className="studio-controls">
        <div className="studio-pills" role="group" aria-label="选择设计系统">
          <button aria-pressed={library === "openui"} onClick={() => setLibrary("openui")} type="button">OpenUI</button>
          <button aria-pressed={library === "intelligent-ui"} onClick={() => setLibrary("intelligent-ui")} type="button">Intelligent UI</button>
        </div>
        <div className="studio-pills studio-theme" role="group" aria-label="预览外观">
          <button type="button" aria-pressed={mode === "light"} onClick={() => setMode("light")}>浅色</button>
          <button type="button" aria-pressed={mode === "dark"} onClick={() => setMode("dark")}>深色</button>
        </div>
      </div>
      <div className="studio-grid">
        <div className={"studio-proof studio-proof--" + mode}>
          <div className="studio-proof-label"><span>TYPE / 01</span><span>EDITORIAL SPECIMEN</span></div>
          <div className="studio-typography">
            <span className="studio-overline">OPENUI / THE LANGUAGE OF INTERACTION</span>
            <h3>内容自有<br />它的形状。</h3>
            <div className="studio-rule" />
            <p>一张图片讲清楚外观，一段文字承载思考，适当的间距让两者自然呼吸。</p>
            <div className="studio-figure"><strong>26</strong><span>TYPOGRAPHY<br/>ROLE & RHYTHM</span><b>01 / 02</b></div>
          </div>
          <div className="studio-proof-foot">WEB TYPOGRAPHY STUDY <span>·</span> 与 SDK 排印角色分别展示</div>
        </div>
        <div className="studio-inspector">
          <div className="inspector-header"><div className="inspector-heading">设计变量 <span>FROM SDK</span></div><span className="inspector-version">Native Theme</span></div>
          <div className="inspector-metrics">
            <div><small>{library === "openui" ? "textHeadingMd" : "pageTitleFont"}</small><strong>{heading ? heading + "pt" : "Dynamic Type"}</strong><span>章节与标题</span></div>
            <div><small>{library === "openui" ? "textBodyDefault" : "bodyFont"}</small><strong>{body ? body + "pt" : "System Body"}</strong><span>正文角色</span></div>
            <div><small>{library === "openui" ? "spaceML" : "groupSpacing"}</small><strong>{group !== undefined ? group + "pt" : "—"}</strong><span>组合间距</span></div>
            <div><small>{library === "openui" ? "radius3xl" : "contentCardRadius"}</small><strong>{radius !== undefined ? radius + "pt" : "—"}</strong><span>内容圆角</span></div>
          </div>
          <div className="inspector-colors">
            <div className="inspector-subheading">PALETTE <span>LIGHT / DARK RESOLVED</span></div>
            <div className="inspector-palette">
              {tok[library].map(([name, label]) => <div className="palette-cell" key={name}>
                <div className="palette-color" style={{ background: theme?.colors?.[name]?.[mode] ?? "transparent" }} />
                <b>{label}</b><small>{theme?.colors?.[name]?.[mode] ?? "—"}</small>
              </div>)}
            </div>
          </div>
          <button className="inspector-explain" onClick={() => setExpanded(!expanded)} aria-expanded={expanded} type="button">关于这些数值的来源 <ChevronRight size={16}/></button>
          {expanded && <p className="inspector-info">构建工作流在 macOS 上实例化当前 SDK Theme，并导出能够公开解析的尺寸与颜色。字体显示为系统语义类型时不猜测固定 point 值；这里的网页排版标本不代表 SwiftUI 像素级截图。</p>}
        </div>
      </div>
      <div className="studio-afterline">
        <p>设计系统不是一堆彩色按钮，而是可重复、可验证的视觉语法。</p>
        <a href="https://github.com/zyfn/open-intelligent-ui-swift/blob/main/docs/openui.md" target="_blank" rel="noreferrer">阅读 OpenUI 视觉规范 <ArrowRight size={17}/></a>
      </div>
    </section>
  );
}
