import SwiftLang
import Foundation
import SwiftUI
import WebKit

enum OpenUIGraphicComponents {
    static var svg: OpenUIComponent {
        OpenUIComponent(name: "SVG", description: "Use to explain shapes, structures, mechanisms, or relationships when a diagram makes them easier to understand. Keep the key idea clear and labels readable at the available width. Supply either inline SVG content or an HTTPS src, not both, with a valid viewBox. Size is derived automatically from viewBox; omit height.", params: [
            OpenUIParameter.string("content", required: false), OpenUIParameter.string("src", required: false),
            OpenUIParameter.string("alt", required: false), OpenUIParameter.number("height")
        ]) { context in MainActor.assumeIsolated { NativeSVG(context: context) } }
    }
}

struct NativeSVG: View {
    let context: OpenUIComponentContext
    var onResourceStatus: ((NativeMediaStatus) -> Void)? = nil
    @State private var downloaded: String?
    @State private var downloadedTarget: NativeMediaResourceTarget?
    @State private var failedTarget: NativeMediaResourceTarget?
    @State private var retryableTarget: NativeMediaResourceTarget?
    @State private var retryState = NativeImageRetryState()
    @State private var preview = false
    @State private var documents = NativeSVGDocumentCache()
    @Environment(\.openUIResourceContext) private var resources
    @Environment(\.openUICardIsAction) private var cardIsAction
    @Environment(\.isEnabled) private var hostEnabled
    private var document: NativeSVGDocument? {
        if context.string("content") != nil && context.string("src") != nil { return nil }
        guard context.string("content") == nil || context.element.sourceReadiness["content"].complete else { return nil }
        let remoteText = downloadedTarget == remoteTarget && remoteTarget?.isCurrent == true ? downloaded : nil
        return documents.value(context.string("content") ?? remoteText)
    }
    private var failed: Bool { remoteTarget != nil && failedTarget == remoteTarget }
    var body: some View {
        Group {
            if let document {
                NativeSVGCanvas(document: document, alt: context.string("alt") ?? "", onOpen: {
                    guard context.canActivate else { return }
                    preview = true
                })
                    .aspectRatio(document.viewportRatio, contentMode: .fit)
                    .frame(maxHeight: 1024)
                    .disabled(!context.canInteract)
            } else {
                if failed, retryableTarget == remoteTarget {
                    Group {
                        if cardIsAction {
                            placeholder(loading: false)
                                .highPriorityGesture(TapGesture().onEnded { retry() },
                                    including: context.canInteract && hostEnabled ? .all : .subviews)
                                .accessibilityAction(named: Text("Tap image to retry", bundle: NativeControlResources.bundle), retry)
                        } else {
                            Button(action: retry) { placeholder(loading: false) }
                                .buttonStyle(.plain)
                        }
                    }
                    .disabled(!context.canInteract)
                    .accessibilityHint(Text("Tap image to retry", bundle: NativeControlResources.bundle))
                    .accessibilityIdentifier("openui.svg.retry")
                } else {
                    placeholder(loading: !failed && (context.isStreaming || remoteTarget?.isCurrent == true))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $preview) {
            if let document {
                NativeSVGPreview(document: document, alt: context.string("alt") ?? "")
            }
        }
        .onChange(of: context.string("content")) { _ in preview = false }
        .onChange(of: remoteTarget) { _ in preview = false }
        .task(id: remoteTarget) {
            downloaded = nil; downloadedTarget = nil; failedTarget = nil; retryableTarget = nil
            guard !Task.isCancelled, let target = remoteTarget, target.isCurrent else { return }
            onResourceStatus?(.loading)
            guard var request = NativeSVGResource.request(target.source,
              resources: OpenUIResourceContext(baseURL: target.baseURL, loader: target.loader), attempt: target.attempt) else {
                failedTarget = target; onResourceStatus?(.unavailable); return
            }
            do {
                request.timeoutInterval = 20
                let data = try await target.loader.data(for: request)
                try Task.checkCancellation()
                guard target.isCurrent, context.isCurrentPresentation else { return }
                guard data.count <= 1_000_000,
                      let text = String(data: data, encoding: .utf8), NativeSVGDocument.parse(text) != nil else {
                    failedTarget = target; retryableTarget = target; onResourceStatus?(.unavailable); return
                }
                downloaded = text; downloadedTarget = target
                onResourceStatus?(.loaded)
            } catch {
                // Transport cancellation is not necessarily cancellation of
                // this view task. An unexpected one must leave a retry path.
                if !Task.isCancelled, target.isCurrent, context.isCurrentPresentation {
                    failedTarget = target; retryableTarget = target
                    onResourceStatus?(.unavailable)
                }
            }
        }
    }
    private func placeholder(loading: Bool) -> some View {
        NativeSVGPlaceholder(alt: context.string("alt") ?? "", loading: loading)
            .aspectRatio(context.presentation.coverAspectRatio, contentMode: .fit)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func retry() {
        guard hostEnabled, context.canActivate, let target = baseTarget else { return }
        retryState.retry(target)
    }
    private var baseTarget: NativeMediaResourceTarget? {
        guard context.element.sourceReadiness["src"].complete, context.string("content") == nil,
              let source = context.string("src") else { return nil }
        return NativeMediaResourceTarget(source: source, resources: resources)
    }
    private var remoteTarget: NativeMediaResourceTarget? {
        guard let target = baseTarget else { return nil }
        return NativeMediaResourceTarget(source: target.source, resources: resources,
            attempt: retryState.attempt(for: target))
    }
}

private struct NativeSVGPlaceholder: View {
    let alt: String
    let loading: Bool

    var body: some View {
        Color.clear.overlay {
            NativeLoadingSurface(active: loading, showsMediaSymbol: true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(alt.isEmpty
            ? Text(loading ? "Loading" : "Unable to load graphic", bundle: NativeControlResources.bundle)
            : Text(alt))
        .accessibilityValue(Text(alt.isEmpty ? "" : loading ? "Loading" : "Unable to load graphic",
            bundle: NativeControlResources.bundle))
    }
}

private struct NativeSVGCanvas: View {
    let document: NativeSVGDocument
    let alt: String
    var onOpen: (() -> Void)? = nil
    @State private var status = NativeMediaStatus.loading
    @State private var renderAttempt = 0
    @Environment(\.openUITheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openUIActivationIntent) private var intent
    @Environment(\.openUICardIsAction) private var cardIsAction
    @Environment(\.isEnabled) private var hostEnabled

    private func retry() {
        guard hostEnabled, status == .unavailable, intent?.permitsActivation != false else { return }
        status = .loading
        renderAttempt += 1
    }
    private func openPreview() {
        guard hostEnabled, status == .loaded, intent?.permitsActivation != false else { return }
        onOpen?()
    }

    var body: some View {
        ZStack {
            SVGWebView(html: document.html(textColor: NativeCSSColor.css(theme.textNeutralPrimary, scheme: scheme)),
                onStatus: { status = $0 })
                .id(renderAttempt)
                // Authored WebKit content is display-only; native recovery and
                // preview gestures remain outside that noninteractive surface.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if status == .loading {
                NativeSVGPlaceholder(alt: alt, loading: true)
            } else if status == .unavailable {
                if cardIsAction {
                    NativeSVGPlaceholder(alt: alt, loading: false)
                        .highPriorityGesture(TapGesture().onEnded { retry() },
                            including: hostEnabled ? .all : .subviews)
                        .accessibilityAction(named: Text("Tap image to retry", bundle: NativeControlResources.bundle), retry)
                        .accessibilityHint(Text("Tap image to retry", bundle: NativeControlResources.bundle))
                } else {
                    Button(action: retry) {
                        NativeSVGPlaceholder(alt: alt, loading: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(alt.isEmpty
                        ? Text("Unable to load graphic", bundle: NativeControlResources.bundle) : Text(alt))
                    .accessibilityValue(Text(alt.isEmpty ? "" : "Unable to load graphic",
                        bundle: NativeControlResources.bundle))
                    .accessibilityHint(Text("Tap image to retry", bundle: NativeControlResources.bundle))
                }
            } else if onOpen != nil {
                // The graphic itself is the target. Keep WebKit mounted
                // while its one native action changes from retry to preview.
                if cardIsAction {
                    // An action card owns the primary tap. Its graphic remains
                    // inspectable without placing another button in the label.
                    Color.clear.contentShape(Rectangle())
                        .contextMenu {
                            Button(action: openPreview) {
                                Label { Text("View full graphic", bundle: NativeControlResources.bundle) }
                                    icon: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(alt.isEmpty ? "SVG" : alt)
                        .accessibilityAddTraits(.isImage)
                        .accessibilityAction(named: Text("View full graphic", bundle: NativeControlResources.bundle), openPreview)
                        .accessibilityHint(Text("Touch and hold to preview", bundle: NativeControlResources.bundle))
                        .accessibilityIdentifier("openui.svg.expand")
                } else {
                    Button(action: openPreview) {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(alt.isEmpty
                        ? Text("View full graphic", bundle: NativeControlResources.bundle) : Text(alt))
                    .accessibilityHint(Text("Tap to preview", bundle: NativeControlResources.bundle))
                    .accessibilityIdentifier("openui.svg.expand")
                }
            } else {
                Color.clear
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(alt.isEmpty ? "SVG" : alt)
                    .accessibilityAddTraits(.isImage)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct NativeSVGPreview: View {
    let document: NativeSVGDocument
    let alt: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openUITheme) private var theme
    @ScaledMetric(relativeTo: .body) private var descriptionHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spaceM) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spaceM) {
                Text("Graphic preview", bundle: NativeControlResources.bundle)
                    .nativeTextStyle(theme.objectTitleStyle())
                Spacer(minLength: 0)
                Button { dismiss() } label: { Image(systemName: "xmark").openUIControlTarget() }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Close", bundle: NativeControlResources.bundle))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("openui.svg.preview.close")
            }
            NativeSVGCanvas(document: document, alt: alt)
                .modifier(NativeImageZoom(resetID: document.markup))
                .accessibilityHint(Text("Zoom and pan to inspect the graphic", bundle: NativeControlResources.bundle))
                .accessibilityIdentifier("openui.svg.preview.zoom")
            if !alt.isEmpty {
                ScrollView(.vertical) {
                    Text(alt).nativeTextStyle(theme.textStyle(.body))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: descriptionHeight)
            }
        }
        .padding(theme.spaceML)
        .frame(idealWidth: 840, idealHeight: 700)
        .background(theme.background)
        .foregroundStyle(theme.textNeutralPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("openui.svg.preview")
    }
}

@MainActor private final class SVGWebCoordinator: NSObject, WKNavigationDelegate {
    private var html = ""
    private var generation = 0
    private var navigation: WKNavigation?
    private var timeout: Task<Void, Never>?
    private var onStatus: ((NativeMediaStatus) -> Void)?
    func update(_ html: String, view: WKWebView, onStatus: @escaping (NativeMediaStatus) -> Void) {
        self.onStatus = onStatus
        guard self.html != html else { return }
        self.html = html
        generation += 1
        let epoch = generation
        timeout?.cancel()
        navigation = view.loadHTMLString(html, baseURL: nil)
        Task { @MainActor [weak self] in
            guard let self, self.generation == epoch else { return }
            self.onStatus?(.loading)
        }
        timeout = Task { @MainActor [weak self, weak view] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            guard let self, self.generation == epoch else { return }
            view?.stopLoading(); self.finish(.unavailable)
        }
    }
    private func finish(_ status: NativeMediaStatus) {
        timeout?.cancel(); timeout = nil
        onStatus?(status)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === self.navigation else { return }
        finish(.loaded)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === self.navigation else { return }
        finish(.unavailable)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard navigation === self.navigation else { return }
        finish(.unavailable)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.unavailable) }
    func dispose(_ view: WKWebView) {
        generation += 1; timeout?.cancel(); timeout = nil; onStatus = nil
        view.navigationDelegate = nil; view.stopLoading(); navigation = nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
    }
}
@MainActor private func svgWebView(_ coordinator: SVGWebCoordinator) -> WKWebView {
    let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
    config.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = coordinator
    #if os(iOS)
    view.isOpaque = false; view.backgroundColor = .clear; view.scrollView.isScrollEnabled = false
    #endif
    return view
}
#if os(iOS)
private struct SVGWebView: UIViewRepresentable {
    let html: String
    let onStatus: (NativeMediaStatus) -> Void
    func makeCoordinator() -> SVGWebCoordinator { SVGWebCoordinator() }
    func makeUIView(context: Context) -> WKWebView { svgWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.update(html, view: view, onStatus: onStatus)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: SVGWebCoordinator) { coordinator.dispose(view) }
}
#else
private struct SVGWebView: NSViewRepresentable {
    let html: String
    let onStatus: (NativeMediaStatus) -> Void
    func makeCoordinator() -> SVGWebCoordinator { SVGWebCoordinator() }
    func makeNSView(context: Context) -> WKWebView { svgWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(html, view: view, onStatus: onStatus)
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: SVGWebCoordinator) { coordinator.dispose(view) }
}
#endif

enum NativeSVGResource {
    static func request(_ source: String?, resources: OpenUIResourceContext, attempt: Int = 0) -> URLRequest? {
        guard let source, let url = URL(string: source, relativeTo: resources.baseURL)?.absoluteURL,
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil,
              var request = resources.request(for: source), request.url?.scheme?.lowercased() == "https" else { return nil }
        if attempt > 0 { request.cachePolicy = .reloadIgnoringLocalCacheData }
        return request
    }
}
