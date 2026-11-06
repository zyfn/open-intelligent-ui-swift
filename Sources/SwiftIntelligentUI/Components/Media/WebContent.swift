import SwiftUI
import WebKit
import OpenUILang
import OpenUISwiftUI

enum HtmlViewComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "HtmlView", description: "Isolated WebKit HTML with inline scripts, no native bridge, no forms or network except HTTPS images. Runs only once source is complete. Height defaults to 360 points, range 80...2400; content scrolls within the supplied height. External user-clicked links are dispatched to the caller.", params: [
            OpenUIParameter.string("html"), Parameter.number("height", minimum: 80, maximum: 2400), OpenUIParameter.string("title", required: false)
        ]) { context in
            WebContent(context: context, content: context.string("html") ?? "", height: CGFloat(min(2400, max(80, context.number("height") ?? 360))), scripts: true, frames: false)
                .accessibilityLabel(context.string("title") ?? "交互内容")
        }
    }
}
enum YouTubeComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "YouTube", description: "YouTube privacy-enhanced embedded player. Accepts a video ID or youtube.com/youtu.be URL. Requires network, playback begins only after user interaction. Invalid IDs show an error.", params: [OpenUIParameter.string("video"), OpenUIParameter.string("title", required: false)]) { context in
            if let id = YouTubeVideo.id(context.string("video") ?? "") {
                Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit).overlay {
                    GeometryReader { geometry in
                        WebContent(context: context, content: "<iframe title=\"\(XMLText.escape(context.string("title") ?? "YouTube"))\" src=\"https://www.youtube-nocookie.com/embed/\(id)?rel=0\" style=\"border:0;width:100%;height:100vh\" allowfullscreen></iframe>", height: geometry.size.height, scripts: true, frames: true)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 12))
            } else { Text("视频地址无效").foregroundStyle(.secondary) }
        }
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

struct WebContent: View {
    let context: OpenUIComponentContext
    let content: String
    let height: CGFloat
    var scripts = false
    var frames = false
    var onMeasure: ((CGSize) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.intelligentUIContentBackground) private var contentBackground
    var body: some View {
        Group {
            if context.element.isSourceComplete {
                BrowserSurface(html: document, scripts: scripts, dark: colorScheme == .dark,
                               backgroundCSS: BridgeColor.css(contentBackground ?? theme.canvas, dark: colorScheme == .dark), open: { url in
                    guard context.canInteract, SourceURL.isActionable(url.absoluteString) else { return }
                    Task { await context.perform(OpenUIActions.openURL(url.absoluteString)) }
                }, onMeasure: onMeasure)
            } else { ProgressView("正在准备内容") }
        }.frame(height: height).frame(maxWidth: .infinity)
    }
    private var document: String {
        let csp = "default-src 'none'; script-src \(scripts ? "'unsafe-inline'" : "'none'"); style-src 'unsafe-inline'; img-src data: https:; font-src data:; media-src data:; connect-src 'none'; frame-src \(frames ? "https://www.youtube-nocookie.com" : "'none'"); form-action 'none'; base-uri 'none';"
        return "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta http-equiv=\"Content-Security-Policy\" content=\"\(csp)\"><style>:root{color-scheme:light dark}body{font:17px/1.5 -apple-system,system-ui;margin:0}svg{display:block;max-width:100%}</style>" + content
    }
}

private struct BrowserSurface {
    let html: String
    let scripts: Bool
    let dark: Bool
    let backgroundCSS: String
    let open: (URL) -> Void
    var onMeasure: ((CGSize) -> Void)?
    func makeCoordinator() -> Coordinator { Coordinator(open: open) }
    func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = scripts
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.underPageBackgroundColor = .clear
        web.navigationDelegate = coordinator
        #if os(iOS)
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        #else
        web.wantsLayer = true; web.layer?.backgroundColor = NSColor.clear.cgColor
        #endif
        return web
    }
    func update(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.open = open
        coordinator.onMeasure = onMeasure
        let appearanceChanged = coordinator.backgroundCSS != backgroundCSS
        coordinator.backgroundCSS = backgroundCSS
        // Appearance changes must not reload interactive HTML and lose its state.
        #if os(iOS)
        web.overrideUserInterfaceStyle = dark ? .dark : .light
        #else
        web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        #endif
        if coordinator.html != html { coordinator.html = html; web.loadHTMLString(html, baseURL: nil) }
        else if appearanceChanged { coordinator.updateBackground(web) }
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html = ""
        var open: (URL) -> Void
        var onMeasure: ((CGSize) -> Void)?
        var backgroundCSS = "transparent"
        init(open: @escaping (URL) -> Void) { self.open = open }
        func updateBackground(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.documentElement.style.backgroundColor='\(backgroundCSS)'", in: nil, in: .defaultClient) { _ in }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateBackground(webView)
            guard onMeasure != nil else { return }
            webView.evaluateJavaScript("(()=>{const e=document.getElementById('equation');if(!e)return null;const r=e.getBoundingClientRect();return [r.width,Math.max(r.height,document.body.getBoundingClientRect().height)]})()", in: nil, in: .defaultClient) { [weak self] result in
                guard case .success(let value) = result else { return }
                guard let values = value as? [Double], values.count == 2, values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return }
                self?.onMeasure?(CGSize(width: values[0] + 8, height: values[1] + 8))
            }
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

private enum BridgeColor {
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
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { view.stopLoading(); view.navigationDelegate = nil }
}
#else
extension BrowserSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { view.stopLoading(); view.navigationDelegate = nil }
}
#endif
