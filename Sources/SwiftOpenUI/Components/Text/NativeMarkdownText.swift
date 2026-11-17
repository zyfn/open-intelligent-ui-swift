import SwiftLang
import MarkdownUI
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Shared native Markdown presentation. Remark owns text parsing and extensions;
/// MarkdownUI lays out native blocks, and CodeBlock shares the standard renderer.
struct NativeMarkdownText: View {
  let text: String
  var mode = NativeRichTextMode.markdown
  var style = NativeRichTextStyle()
  @Environment(\.openUITheme) private var theme
  @Environment(\.openUIInheritedFont) private var inheritedFont
  @Environment(\.openUIResourceContext) private var resources
  @Environment(\.cardSources) private var sources
  @Environment(\.openURL) private var openURL
  @Environment(\.openUIInlineLinksReady) private var linksReady
  @Environment(\.openUIStreamActive) private var streamActive
  @Environment(\.openUIActivationIntent) private var activationIntent
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.multilineTextAlignment) private var textAlignment
  @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
  @StateObject private var math = NativeMathRenderer()
  @StateObject private var streamText = NativeStreamingTextBuffer()
  @StateObject private var document = NativeMarkdownDocument()
  @State private var citation: NativeCitationSelection?
  private var foreground: Color { style.color ?? theme.textNeutralPrimary }
  private var frameAlignment: Alignment {
    switch textAlignment {
    case .center: return .center
    case .trailing: return .trailing
    default: return .leading
    }
  }
  private var font: OpenUIFont { style.resolvedFont(theme: theme, inherited: inheritedFont) }
  private var mathSize: CGFloat { font.size * scale }
  private var mathColor: String { NativeCSSColor.css(foreground, scheme: colorScheme) }
  private struct StreamingInput: Equatable {
    let source: OpenUIString
    let active: Bool
  }
  private var streamingInput: StreamingInput {
    .init(source: OpenUIString(text), active: streamActive)
  }
  private var visibleText: String {
    streamText.text(for: text, streaming: streamActive)
  }
  private var request: NativeRichTextRequest {
    .init(source: OpenUIString(visibleText), mode: mode, sources: sources, fontSize: Double(mathSize), color: mathColor)
  }

  var body: some View {
    MarkdownUI.Markdown(document.content(for: request),
      baseURL: resources.baseURL, imageBaseURL: resources.baseURL)
      .markdownTextStyle {
        ForegroundColor(foreground)
        FontFamily(font.family.map(FontProperties.Family.custom) ?? .system(font.design))
        // MarkdownUI applies the shared body scale once to this base size.
        FontSize(font.size)
        FontWeight(font.weight)
        TextTracking(font.letterSpacing * mathSize)
        FontDigitVariant(style.numeric || font.monospacedDigits ? .monospaced : .normal)
      }
      .markdownTextStyle(\.link) { ForegroundColor(theme.textNeutralLink); UnderlineStyle(.single) }
      .markdownTextStyle(\.strong) { FontWeight(style.emphasisWeight ?? theme.textBodyDefaultHeavy.weight) }
      .markdownSoftBreakMode(mode == .markdown ? .space : .lineBreak)
      .markdownBlockStyle(\.paragraph) { configuration in
        configuration.label.fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: frameAlignment)
          .relativeLineSpacing(.em(font.additionalLineSpacing() / max(1, font.size)))
          .markdownMargin(top: 0, bottom: mode == .inline ? 0 : theme.spaceM)
      }
      .markdownBlockStyle(\.heading1) { heading($0.label, level: 1, before: theme.spaceXl) }
      .markdownBlockStyle(\.heading2) { heading($0.label, level: 2, before: theme.spaceXl) }
      .markdownBlockStyle(\.heading3) { heading($0.label, level: 3, before: theme.spaceL) }
      .markdownBlockStyle(\.heading4) { heading($0.label, level: 4, before: theme.spaceM) }
      .markdownBlockStyle(\.heading5) { heading($0.label, level: 5, before: theme.spaceM) }
      .markdownBlockStyle(\.heading6) { heading($0.label, level: 6, before: theme.spaceM) }
      .markdownBlockStyle(\.codeBlock) { configuration in
        NativeCodeBlockContent(code: OpenUIString(configuration.content),
          language: OpenUIString(NativeMarkdownCode.language(configuration.language)), theme: theme)
          .markdownMargin(top: theme.spacing("s"), bottom: theme.spacing("s"))
      }
      .markdownTheme(.basic)
      .markdownImageProvider(NativeMarkdownImageProvider(math: math, fontSize: mathSize, color: mathColor))
      .markdownInlineImageProvider(NativeMarkdownInlineImages(math: math, fontSize: mathSize, color: mathColor, resources: resources))
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: frameAlignment)
      .background(alignment: .topLeading) {
        NativeMathHost(renderer: math).frame(width: 1, height: 1).clipped().opacity(0.001)
          .accessibilityHidden(true).allowsHitTesting(false)
      }
      .environment(\.openURL, OpenURLAction { url in
        guard linksReady, activationIntent?.permitsActivation != false else { return .discarded }
        if let selection = NativeCitationSelection(url: url, sources: sources) {
          citation = selection; return .handled
        }
        guard let safe = NativeRichTextEngine.shared.sourceURL(url.absoluteString), let target = URL(string: safe) else { return .discarded }
        openURL(target); return .handled
      })
      .popover(item: $citation) { selected in
        NativeCitationSources(indices: selected.indices, sources: sources)
          .environment(\.openUITheme, theme).environment(\.openUIResourceContext, resources)
      }
      // Source parsing and Store publication are never throttled; only the
      // native text presentation is coalesced. Do not animate reflow of
      // already-visible paragraphs as the final line grows.
      .transaction { if streamActive { $0.animation = nil } }
      .onAppear { streamText.receive(text, streaming: streamActive) }
      // The single-parameter onChange captures the previous view. Consume its
      // new value, keeping source and streaming status in the same snapshot.
      .onChange(of: streamingInput) { input in
        streamText.receive(input.source.displayString, streaming: input.active)
      }
      .onAppear { document.receive(request) }
      .onChange(of: request) { document.receive($0) }
      .onDisappear { document.cancel(); streamText.cancel(); math.cancel() }
  }
  private func heading<Content: View>(_ content: Content, level: Int, before: CGFloat) -> some View {
    let headingFont = theme.markdownHeadingStyle(level).font
    return content
      .fixedSize(horizontal: false, vertical: true)
      // The text-style modifier must surround this relative-size reader so its
      // em units use the heading's font, including custom leading and tracking.
      .relativeLineSpacing(.em(headingFont.additionalLineSpacing() / max(1, headingFont.size)))
      .markdownTextStyle {
        FontFamily(headingFont.family.map(FontProperties.Family.custom) ?? .system(headingFont.design))
        FontSize(.em(headingFont.size / max(1, font.size)))
        FontWeight(headingFont.weight)
        TextTracking(headingFont.letterSpacing * headingFont.size * scale)
        FontDigitVariant(headingFont.monospacedDigits ? .monospaced : .normal)
      }
      .markdownMargin(top: before, bottom: theme.spaceS)
  }
}

/// Immutable parsed content crosses the serialized worker once. MarkdownUI's
/// content is a value tree; it is not mutated after construction or shared with
/// an active parser. No views or native UI objects cross this boundary.
struct NativePreparedMarkdown: @unchecked Sendable {
  let request: NativeRichTextRequest
  let content: MarkdownContent
}

private actor NativeMarkdownWorker {
  static let shared = NativeMarkdownWorker()
  func prepare(_ request: NativeRichTextRequest) throws -> NativePreparedMarkdown {
    try NativeRuntimeTrace.measure("Markdown preparation") {
      try Task.checkCancellation()
      let source: String
      do {
        source = try NativeRichTextEngine.shared.prepare(request.source.displayString,
          mode: request.mode, sources: request.sources, fontSize: request.fontSize, color: request.color)
      } catch is CancellationError { throw CancellationError() }
      catch { source = request.source.displayString }
      try Task.checkCancellation()
      let result = NativePreparedMarkdown(request: request, content: MarkdownContent(source))
      try Task.checkCancellation()
      return result
    }
  }
}

/// One current task plus one replaceable pending request. Appending does not
/// cancel already useful work; source corrections, configuration changes and
/// unmounts reject old results. A fit reads this projection without publishing.
@MainActor final class NativeMarkdownDocument: ObservableObject {
  typealias Preparation = @MainActor (NativeRichTextRequest) async throws -> NativePreparedMarkdown

  @Published private var prepared: NativePreparedMarkdown?
  private var latest: NativeRichTextRequest?
  private var work: Task<Void, Never>?
  private let prepare: Preparation
  private var generation: UInt64 = 0
  private var fallbackRequest: NativeRichTextRequest?
  private var fallback = MarkdownContent("")
  private(set) var fallbackParseCount = 0
  private(set) var preparationCount = 0
  var currentSource: OpenUIString? { prepared?.request.source }

  init(prepare: Preparation? = nil) {
    self.prepare = prepare ?? { try await NativeMarkdownWorker.shared.prepare($0) }
  }

  private func compatible(_ old: NativeRichTextRequest, _ next: NativeRichTextRequest) -> Bool {
    old.mode == next.mode && old.sources == next.sources
      && old.fontSize == next.fontSize && old.color == next.color
      && next.source.codeUnits.starts(with: old.source.codeUnits)
  }

  func content(for request: NativeRichTextRequest) -> MarkdownContent {
    let appending = latest.map { compatible($0, request) } ?? false
    if let prepared, (latest == nil || appending), compatible(prepared.request, request) {
      return prepared.content
    }
    // Until the first worker result arrives, growing inputs keep the readable
    // prefix already parsed on this actor. A busy worker must not cause one
    // synchronous Markdown parse per append as well as its background work.
    // Compare with the last input too: A -> AB -> AC is a correction even
    // though AC still extends the displayed fallback A.
    if work != nil, appending, let fallbackRequest, compatible(fallbackRequest, request) {
      return fallback
    }
    // Synchronous snapshot/size-only hosts still receive readable content on
    // first render and after corrections, without scheduling preparation.
    if fallbackRequest != request {
      fallbackRequest = request
      fallback = NativeRuntimeTrace.measure("Markdown fallback") {
        MarkdownContent(request.source.displayString)
      }
      fallbackParseCount += 1
    }
    return fallback
  }

  func receive(_ request: NativeRichTextRequest) {
    if latest == request, work != nil || prepared?.request == request { return }
    let previous = latest
    latest = request
    if let previous, !compatible(previous, request) {
      generation &+= 1
      work?.cancel(); work = nil
      // An older prepared prefix must not mask a corrected suffix or retain
      // the old math/citation configuration. A body may already have made the
      // replacement fallback before onChange delivers this same request.
      if let prepared, prepared.request != request { self.prepared = nil }
      if fallbackRequest != request { fallbackRequest = nil }
    }
    guard work == nil, prepared?.request != request else { return }
    start(request)
  }

  private func start(_ request: NativeRichTextRequest) {
    preparationCount += 1
    let epoch = generation
    let prepare = self.prepare
    work = Task { @MainActor [weak self] in
      let result = try? await prepare(request)
      guard !Task.isCancelled, let self, self.generation == epoch else { return }
      self.work = nil
      if let result, let latest = self.latest, self.compatible(request, latest) {
        self.prepared = result
      }
      if let next = self.latest, next != request { self.start(next) }
    }
  }

  func cancel() {
    generation &+= 1
    work?.cancel(); work = nil; latest = nil
  }
  deinit { work?.cancel() }
}

enum NativeMarkdownCode {
  static func language(_ info: String?) -> String {
    guard let info, let match = info.range(of: #"^\w+"#, options: .regularExpression) else { return "text" }
    return String(info[match])
  }
}

enum NativeCSSColor {
  static func css(_ color: Color, scheme: ColorScheme) -> String {
    #if os(iOS)
    let value = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
    value.getRed(&r, green: &g, blue: &b, alpha: &a)
    #else
    var resolved = NSColor.black
    let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    appearance?.performAsCurrentDrawingAppearance { resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? .black }
    let r = resolved.redComponent, g = resolved.greenComponent, b = resolved.blueComponent, a = resolved.alphaComponent
    #endif
    return String(format: "#%02x%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
  }
}

private struct NativeMarkdownImageProvider: ImageProvider {
  let math: NativeMathRenderer
  let fontSize: CGFloat
  let color: String
  @ViewBuilder func makeImage(url: URL?) -> some View {
    if let url, let descriptor = NativeMathDescriptor(url: url) {
      NativeMathBlock(descriptor: descriptor, renderer: math, fontSize: fontSize, color: color)
    } else { NativeMarkdownImage(url: url) }
  }
}

private struct NativeMarkdownInlineImages: InlineImageProvider {
  let math: NativeMathRenderer
  let fontSize: CGFloat
  let color: String
  let resources: OpenUIResourceContext
  func image(with url: URL, label: String) async throws -> Image {
    if let descriptor = NativeMathDescriptor(url: url) {
      return try await math.image(for: descriptor, fontSize: fontSize, color: color).swiftUIImage(label: label)
    }
    guard let request = resources.request(for: url.absoluteString) else { throw URLError(.unsupportedURL) }
    let entry = try await NativeMediaCache.load(request, loader: resources.loader,
      targetPixelSize: max(1, Int(min(256, fontSize * 3))))
    return await MainActor.run { entry.image }
  }
}

private struct NativeMathBlock: View {
  @Environment(\.openUITheme) private var theme
  let descriptor: NativeMathDescriptor
  let renderer: NativeMathRenderer
  let fontSize: CGFloat
  let color: String
  @State private var image: NativeMathImage?
  @State private var failed = false
  private var key: String {
    "\(fontSize):\(color):" + ((try? JSONEncoder().encode(descriptor).base64EncodedString()) ?? "")
  }
  var body: some View {
    Group {
      if let image {
        ScrollView(.horizontal) {
          image.swiftUIImage(label: descriptor.tex).frame(width: image.size.width, height: image.size.height)
        }.frame(height: image.size.height)
          .accessibilityElement(children: .ignore).accessibilityLabel(descriptor.tex)
          .accessibilityAddTraits(.isImage).accessibilityIdentifier("openui.math.rendered")
      } else if failed {
        Text(descriptor.tex).openUIFont(theme.textCodeDefault, role: .code).textSelection(.enabled)
          .accessibilityIdentifier("openui.math.fallback")
      } else {
        NativeDelayedPresentation(active: true) { visible in
          NativeLoadingIndicator().opacity(visible ? 1 : 0)
        }.frame(minHeight: fontSize * 1.5)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(Text("Loading data", bundle: NativeControlResources.bundle))
          .accessibilityIdentifier("openui.math.loading")
      }
    }.task(id: key) {
      image = nil; failed = false
      do {
        let result = try await renderer.image(for: descriptor, fontSize: fontSize, color: color)
        guard !Task.isCancelled else { return }
        image = result
      } catch { if !Task.isCancelled { failed = true } }
    }
  }
}

private struct NativeMarkdownImage: View {
  let url: URL?
  @Environment(\.openUITheme) private var theme
  @State private var status: NativeMediaStatus = .loading
  var body: some View {
    NativeRemoteImage(src: url?.absoluteString, layout: .intrinsic, onStatus: { phase, _ in status = phase })
      .clipShape(RoundedRectangle(cornerRadius: theme.radiusM, style: .continuous))
      .accessibilityElement(children: .ignore).accessibilityAddTraits(.isImage)
      .accessibilityIdentifier(identifier)
  }
  private var identifier: String {
    switch status {
    case .loading: return "openui.markdown.image.loading"
    case .loaded: return "openui.markdown.image.loaded"
    case .unavailable: return "openui.markdown.image.unavailable"
    }
  }
}

// Internal test seam; normal consumers still use the registered components.
extension NativeMarkdownText {
  @MainActor init(text: String, mode: NativeRichTextMode = .markdown,
    streamText: NativeStreamingTextBuffer? = nil,
    document: NativeMarkdownDocument) {
    self.init(text: text, mode: mode)
    if let streamText { _streamText = StateObject(wrappedValue: streamText) }
    _document = StateObject(wrappedValue: document)
  }
}
