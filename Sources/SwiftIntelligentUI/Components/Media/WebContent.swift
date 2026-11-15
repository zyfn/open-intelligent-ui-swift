import SwiftUI
import WebKit
import SwiftLang

enum HtmlViewComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "HtmlView", description: "Isolated WebKit HTML with inline scripts, no native bridge, no forms or network except HTTPS images. Runs only once source is complete. Height defaults to 360 points, range 80...2400; content scrolls within the supplied height. External user-clicked links are dispatched to the caller.", params: [
            OpenUIParameter.string("html"), Parameter.number("height", minimum: 80, maximum: 2400), OpenUIParameter.string("title", required: false)
        ]) { context in
            HtmlContentView(context: context)
        }
    }
}
private struct HtmlContentView: View {
    let context: OpenUIComponentContext
    @Environment(\.locale) private var locale
    var body: some View {
        WebContent(context: context, content: context.string("html") ?? "", height: CGFloat(min(2400, max(80, context.number("height") ?? 360))), scripts: true, frames: false)
            .accessibilityLabel(context.string("title") ?? SDKStrings.text("web.interactive_title", locale: locale))
    }
}
enum YouTubeComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "YouTube", description: "YouTube privacy-enhanced embedded player. Accepts a video ID or youtube.com/youtu.be URL. Requires network, playback begins only after user interaction. Invalid IDs show an error.", params: [OpenUIParameter.string("video"), OpenUIParameter.string("title", required: false)]) { context in
            YouTubeView(context: context)
        }
    }
}
private struct YouTubeView: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    private var video: String { context.string("video") ?? "" }
    private var id: String? { YouTubeVideo.id(video) }
    private var originalURL: String? {
        guard let id else { return nil }
        return URL(string: video)?.host == nil ? "https://www.youtube.com/watch?v=\(id)" : video
    }
    var body: some View {
        Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit).overlay {
            GeometryReader { geometry in
                Group {
                    if !context.element.isSourceComplete { ProgressView(SDKStrings.text("video.preparing", locale: locale)) }
                    else if let id {
                        WebContent(context: context,
                            content: "<iframe title=\"\(XMLText.escape(context.string("title") ?? "YouTube"))\" src=\"https://www.youtube-nocookie.com/embed/\(id)?rel=0\" style=\"border:0;width:100%;height:100vh\" allowfullscreen></iframe>",
                            height: geometry.size.height, scripts: true, frames: true, failureURL: originalURL)
                    } else {
                        Label(SDKStrings.text("video.invalid", locale: locale), systemImage: "play.slash").foregroundStyle(theme.secondaryText)
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            if let originalURL {
                Button(SDKStrings.text("video.open", locale: locale)) { open(originalURL) }.disabled(!context.canInteract)
            }
        }
        .accessibilityActions {
            if let originalURL {
                Button(SDKStrings.text("video.open", locale: locale)) { open(originalURL) }.disabled(!context.canInteract)
            }
        }
    }
    private func open(_ url: String) {
        guard context.canInteract, SourceURL.isActionable(url) else { return }
        Task { await context.perform(OpenUIActions.openURL(url)) }
    }
}
enum YouTubeVideo {
    static func id(_ source: String) -> String? {
        if source.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil { return source }
        guard let url = URL(string: source), let host = url.host?.lowercased(), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let id: String?
        if host == "youtu.be" { id = url.pathComponents.dropFirst().first }
        else if ["youtube.com", "www.youtube.com", "m.youtube.com", "www.youtube-nocookie.com"].contains(host) {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value ?? url.pathComponents.last
        } else { return nil }
        guard let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return nil }
        return id
    }
}

enum XMLText {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
}

enum WebContentPhase: Equatable { case loading, ready, failed }

struct WebContent: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    let content: String
    let height: CGFloat
    var scripts = false
    var frames = false
    var onMeasure: ((CGSize) -> Void)? = nil
    var failureURL: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIContentBackground) private var contentBackground
    @Environment(\.openIntelligentUIInteractiveContent) private var interactive
    @ScaledMetric(relativeTo: .body) private var bodySize = 17.0
    @State private var phase: WebContentPhase = .loading
    @State private var retry = 0

    var body: some View {
        Group {
            if context.element.isSourceComplete {
                BrowserSurface(html: document, scripts: scripts, dark: colorScheme == .dark,
                    styles: [
                        "--iui-ink": BridgeColor.css(theme.primaryText, dark: colorScheme == .dark),
                        "--iui-body-size": "\(bodySize)px",
                        "--iui-body-weight": theme.defaultBodyWeight(for: colorScheme) == .medium ? "500" : "400",
                        "background-color": BridgeColor.css(contentBackground ?? theme.canvas, dark: colorScheme == .dark)
                    ], reload: retry, open: open, onMeasure: onMeasure, onPhase: { phase = $0 })
                    .overlay {
                        if phase == .loading {
                            ProgressView(SDKStrings.text("web.loading", locale: locale)).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(contentBackground ?? theme.canvas)
                                .allowsHitTesting(false)
                        } else if phase == .failed {
                            VStack(spacing: theme.innerSpacing) {
                                Label(SDKStrings.text("web.failed", locale: locale), systemImage: "exclamationmark.triangle")
                                    .font(theme.captionFont).foregroundStyle(theme.secondaryText)
                                if !interactive {
                                    Button(SDKStrings.text("common.retry", locale: locale)) { retry &+= 1 }.buttonStyle(.borderless)
                                    if let failureURL, let url = URL(string: failureURL), SourceURL.isActionable(failureURL) {
                                        Button(SDKStrings.text("web.open_original", locale: locale)) { open(url) }.buttonStyle(.borderless)
                                    }
                                }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(contentBackground ?? theme.canvas)
                        }
                    }
            } else { ProgressView(SDKStrings.text("web.preparing", locale: locale)) }
        }.frame(height: height).frame(maxWidth: .infinity)
    }
    private func open(_ url: URL) {
        guard context.canInteract, SourceURL.isActionable(url.absoluteString) else { return }
        Task { await context.perform(OpenUIActions.openURL(url.absoluteString)) }
    }
    private var document: String {
        let csp = "default-src 'none'; script-src \(scripts ? "'unsafe-inline'" : "'none'"); style-src 'unsafe-inline'; img-src data: https:; font-src data:; media-src data:; connect-src 'none'; frame-src \(frames ? "https://www.youtube-nocookie.com" : "'none'"); form-action 'none'; base-uri 'none';"
        return "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta http-equiv=\"Content-Security-Policy\" content=\"\(csp)\"><style>:root{color-scheme:light dark}body{font:var(--iui-body-weight,400) var(--iui-body-size,17px)/1.5 -apple-system,system-ui;color:var(--iui-ink,CanvasText);margin:0}svg{display:block;max-width:100%}</style>" + content
    }
}

private final class ContentWebView: WKWebView {
    var onWidthChange: ((WKWebView) -> Void)?
    private var observedWidth: CGFloat = -1
    #if os(iOS)
    override func layoutSubviews() { super.layoutSubviews(); reportWidth() }
    #else
    override func layout() { super.layout(); reportWidth() }
    #endif
    private func reportWidth() {
        guard bounds.width.isFinite, abs(bounds.width - observedWidth) > 0.5 else { return }
        observedWidth = bounds.width
        onWidthChange?(self)
    }
}

@MainActor private struct BrowserSurface {
    let html: String
    let scripts: Bool
    let dark: Bool
    let styles: [String: String]
    let reload: Int
    let open: (URL) -> Void
    var onMeasure: ((CGSize) -> Void)?
    let onPhase: (WebContentPhase) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(open: open, onPhase: onPhase) }
    func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = scripts
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        let web = ContentWebView(frame: .zero, configuration: configuration)
        web.underPageBackgroundColor = .clear
        web.navigationDelegate = coordinator
        web.onWidthChange = { [weak coordinator] web in coordinator?.requestMeasurement(web) }
        #if os(iOS)
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        #else
        web.wantsLayer = true; web.layer?.backgroundColor = NSColor.clear.cgColor
        #endif
        return web
    }
    func update(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.open = open; coordinator.onMeasure = onMeasure; coordinator.onPhase = onPhase
        let appearanceChanged = coordinator.styles != styles
        coordinator.styles = styles
        #if os(iOS)
        web.overrideUserInterfaceStyle = dark ? .dark : .light
        #else
        web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        #endif
        if coordinator.html != html || coordinator.reload != reload {
            coordinator.html = html; coordinator.reload = reload
            coordinator.beginLoad(web, html: html)
        } else if appearanceChanged {
            coordinator.updateAppearance(web)
            coordinator.requestMeasurement(web)
        }
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var html = ""
        var reload = -1
        var open: (URL) -> Void
        var onMeasure: ((CGSize) -> Void)?
        var onPhase: (WebContentPhase) -> Void
        var styles: [String: String] = [:]
        private var generation: UInt64 = 0
        private var measurement: UInt64 = 0
        private var navigation: WKNavigation?
        private var phase: WebContentPhase = .loading
        private var lastSize: CGSize?
        private var measurementScheduled = false
        private var timeout: DispatchWorkItem?
        private var dismantled = false
        init(open: @escaping (URL) -> Void, onPhase: @escaping (WebContentPhase) -> Void) {
            self.open = open; self.onPhase = onPhase
        }
        func beginLoad(_ web: WKWebView, html: String) {
            timeout?.cancel()
            generation &+= 1; measurement &+= 1; lastSize = nil
            phase = .loading; publish(.loading)
            OpenIntelligentUIPerformance.record("web.load")
            navigation = web.loadHTMLString(html, baseURL: nil)
            let revision = generation
            let timeout = DispatchWorkItem { [weak self, weak web] in
                guard let self, let web, self.generation == revision, self.phase == .loading, !self.dismantled else { return }
                self.phase = .failed; self.publish(.failed); web.stopLoading()
            }
            self.timeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        }
        private func publish(_ value: WebContentPhase) {
            let revision = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.dismantled, self.generation == revision else { return }
                self.onPhase(value)
            }
        }
        func updateAppearance(_ webView: WKWebView) {
            guard let data = try? JSONSerialization.data(withJSONObject: styles, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else { return }
            let script = "for(const [k,v] of Object.entries(\(json))){document.documentElement.style.setProperty(k,v)}"
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { _ in }
        }
        func requestMeasurement(_ webView: WKWebView) {
            measurement &+= 1
            guard onMeasure != nil, phase == .ready, !measurementScheduled, !dismantled else { return }
            measurementScheduled = true
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.measurementScheduled = false
                guard self.phase == .ready, !self.dismantled, webView.bounds.width > 0 else { return }
                let revision = self.generation, ticket = self.measurement, width = webView.bounds.width
                OpenIntelligentUIPerformance.record("web.measure")
                webView.evaluateJavaScript("(()=>{const e=document.getElementById('equation');if(!e)return null;const r=e.getBoundingClientRect();return [r.width,Math.max(r.height,document.body.getBoundingClientRect().height)]})()", in: nil, in: .defaultClient) { [weak self, weak webView] result in
                    guard let self, let webView, !self.dismantled, self.generation == revision,
                          self.measurement == ticket, abs(webView.bounds.width - width) < 0.5,
                          case .success(let value) = result,
                          let values = value as? [Double], values.count == 2,
                          values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return }
                    let size = CGSize(width: values[0] + 8, height: values[1] + 8)
                    if let old = self.lastSize, abs(old.width - size.width) < 0.5, abs(old.height - size.height) < 0.5 { return }
                    self.lastSize = size; self.onMeasure?(size)
                }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === self.navigation, !dismantled else { return }
            timeout?.cancel(); phase = .ready
            updateAppearance(webView); publish(.ready); requestMeasurement(webView)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(navigation) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(navigation) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail(navigation) }
        private func fail(_ navigation: WKNavigation?) {
            guard navigation === self.navigation, !dismantled else { return }
            timeout?.cancel(); measurement &+= 1; phase = .failed; publish(.failed)
        }
        func dismantle(_ web: WKWebView) {
            dismantled = true; generation &+= 1; timeout?.cancel()
            web.stopLoading(); web.pauseAllMediaPlayback {}
            web.navigationDelegate = nil; (web as? ContentWebView)?.onWidthChange = nil
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "about" { decisionHandler(.allow); return }
            if navigationAction.targetFrame?.isMainFrame == false && url.host == "www.youtube-nocookie.com" { decisionHandler(.allow); return }
            if navigationAction.navigationType == .linkActivated { open(url) }
            decisionHandler(.cancel)
        }
    }
}

enum BridgeColor {
    static func css(_ color: Color, dark: Bool) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        #if os(iOS)
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            NSColor(color).usingColorSpace(.sRGB)?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        }
        #endif
        return "rgba(\(Int(red * 255)),\(Int(green * 255)),\(Int(blue * 255)),\(alpha))"
    }
}
#if os(iOS)
extension BrowserSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { coordinator.dismantle(view) }
}
#else
extension BrowserSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { coordinator.dismantle(view) }
}
#endif
