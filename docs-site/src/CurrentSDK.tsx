import React, { useEffect, useMemo, useState } from "react";

type ComponentDefinition = {
  description?: string;
  params?: Array<{ name?: string; required?: boolean; type?: string }> | Record<string, unknown>;
  signature?: string;
  [key: string]: unknown;
};
type Contract = {
  root?: string;
  components?: Record<string, ComponentDefinition>;
  functions?: Record<string, unknown>;
};

function signature(name: string, component: ComponentDefinition): string {
  if (typeof component.signature === "string") return component.signature;
  const params = component.params;
  if (Array.isArray(params)) {
    return name + "(" + params.map((p) => (p.name ?? "arg") + (p.required ? "" : "?")).join(", ") + ")";
  }
  return name + "(…)";
}

export default function CurrentSDK() {
  const [variant, setVariant] = useState<"openui" | "intelligent-ui">("openui");
  const [contract, setContract] = useState<Contract | null>(null);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState("");

  useEffect(() => {
    let cancelled = false;
    setContract(null);
    setError("");
    const url = import.meta.env.BASE_URL + "current/" + variant + ".json";
    fetch(url)
      .then((response) => {
        if (!response.ok) throw new Error("Missing exported SDK contract");
        return response.json();
      })
      .then((value: Contract) => { if (!cancelled) setContract(value); })
      .catch(() => {
        if (!cancelled) setError("尚未提供该组件库的 SDK 契约导出。macOS 开发环境请运行 npm run generate:current。");
      });
    return () => { cancelled = true; };
  }, [variant]);

  const entries = useMemo(() => Object.entries(contract?.components ?? {}).sort(([a], [b]) => a.localeCompare(b)), [contract]);
  const filtered = useMemo(() => entries.filter(([name, definition]) =>
    (name + " " + (definition.description ?? "")).toLocaleLowerCase().includes(query.toLocaleLowerCase())
  ), [entries, query]);
  const chosen = entries.find(([name]) => name === selected) ?? filtered[0];
  const name = chosen?.[0] ?? "";
  const definition = chosen?.[1];
  const label = variant === "openui" ? "OpenUI" : "OpenIntelligentUI";

  return (
    <section id="current" className="current-guide" aria-label="当前 SDK 组件文档">
      <div className="current-guide__eyebrow">CURRENT SDK · NATIVE CONTRACT</div>
      <div className="current-guide__intro">
        <div>
          <h2>从实际组件库出发</h2>
          <p>这里展示当前 Swift SDK 导出的生成契约，而不是旧版 React 演示组件。两套组件库共享 SwiftLang，但有各自独立的组件名、参数和设计系统。</p>
        </div>
        <a href="https://github.com/zyfn/open-intelligent-ui-swift/tree/main/Examples/Gallery" target="_blank" rel="noreferrer">查看原生 Gallery ↗</a>
      </div>
      <div className="current-guide__switch" role="group" aria-label="选择组件库">
        <button type="button" aria-pressed={variant === "openui"} onClick={() => { setVariant("openui"); setQuery(""); setSelected(""); }}>OpenUI</button>
        <button type="button" aria-pressed={variant === "intelligent-ui"} onClick={() => { setVariant("intelligent-ui"); setQuery(""); setSelected(""); }}>Intelligent UI</button>
      </div>
      <div className="current-guide__summary">
        <div><small>当前库</small><strong>{label}</strong></div>
        <div><small>根组件</small><strong>{contract?.root ?? "—"}</strong></div>
        <div><small>注册组件</small><strong>{contract ? entries.length : "—"}</strong></div>
        <div><small>自定义函数</small><strong>{contract ? Object.keys(contract.functions ?? {}).length : "—"}</strong></div>
      </div>
      {error ? (
        <p className="current-guide__error">{error}</p>
      ) : !contract ? (
        <p className="current-guide__loading">读取当前 SDK 契约…</p>
      ) : (
        <div className="current-guide__browser">
          <div className="current-guide__catalog">
            <label htmlFor="sdk-component-search">搜索实际注册的组件</label>
            <input id="sdk-component-search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="组件名或用途" />
            <div className="current-guide__list" role="group" aria-label="组件目录">
              {filtered.map(([componentName, component]) => (
                <button key={componentName} type="button" className={componentName === name ? "is-active" : ""} onClick={() => setSelected(componentName)}>
                  <span>{componentName}</span>
                  <small>{component.description || "组件定义"}</small>
                </button>
              ))}
              {filtered.length === 0 && <p>没有匹配的组件。</p>}
            </div>
          </div>
          <div className="current-guide__details">
            {definition && (
              <>
                <div className="current-guide__details-label">SDK 生成契约</div>
                <h3>{name}</h3>
                <p>{definition.description || "当前 SDK 注册的组件。"}</p>
                <code>{signature(name, definition)}</code>
                <details>
                  <summary>查看导出的原始定义</summary>
                  <pre>{JSON.stringify(definition, null, 2)}</pre>
                </details>
              </>
            )}
            <p className="current-guide__note">此处显示真实语言契约，不模拟原生 SwiftUI 的组件视觉或交互。原生效果以 Gallery 中对应 SDK 提交的验收为准。</p>
          </div>
        </div>
      )}
      <div className="current-guide__history">
        <strong>RC20 设计档案</strong>
        <span>下方保留旧站的交互式讲解与 React Web 标本，包括 <a href="#component-TextContent">TextContent</a>。它们是历史参考，不能当作当前 Native SDK 的渲染验收。</span>
      </div>
    </section>
  );
}
