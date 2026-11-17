import SwiftLang
import MarkdownUI
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum NativeMarkdownTableAlignment: Equatable {
  case leading, center, trailing

  var frameAlignment: Alignment {
    switch self {
    case .leading: return .leading
    case .center: return .center
    case .trailing: return .trailing
    }
  }

  /// MarkdownUI exposes a canonical Markdown representation of the parsed
  /// table. Its delimiter row contains only pipes, colons and hyphens, so it
  /// supplies column alignment without inspecting or rewriting cell content.
  static func columns(in markdown: String) -> [Self] {
    guard let delimiter = markdown.split(separator: "\n").first(where: { line in
      let text = line.trimmingCharacters(in: .whitespaces)
      return text.contains("-") && text.allSatisfy { $0 == "|" || $0 == ":" || $0 == "-" || $0.isWhitespace }
    }) else { return [] }
    var text = delimiter.trimmingCharacters(in: .whitespaces)
    if text.first == "|" { text.removeFirst() }
    if text.last == "|" { text.removeLast() }
    return text.split(separator: "|", omittingEmptySubsequences: false).map { part in
      let item = part.trimmingCharacters(in: .whitespaces)
      if item.hasPrefix(":") && item.hasSuffix(":") { return .center }
      if item.hasSuffix(":") { return .trailing }
      return .leading
    }
  }
}

private struct NativeMarkdownTableLayout {
  var width: CGFloat = 0
  var alignments: [NativeMarkdownTableAlignment] = []
  var minimumColumnWidth: CGFloat? {
    guard width > 0, !alignments.isEmpty else { return nil }
    return max(0, (width - CGFloat(alignments.count + 1) * 0.5) / CGFloat(alignments.count))
  }
}
private struct NativeMarkdownTableLayoutKey: EnvironmentKey {
  static let defaultValue = NativeMarkdownTableLayout()
}
private extension EnvironmentValues {
  var nativeMarkdownTableLayout: NativeMarkdownTableLayout {
    get { self[NativeMarkdownTableLayoutKey.self] }
    set { self[NativeMarkdownTableLayoutKey.self] = newValue }
  }
}
private struct NativeMarkdownTableWidthKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct NativeMarkdownTable: View {
  let configuration: BlockConfiguration
  let appearance: OpenUITableAppearance
  let radius: CGFloat
  @State private var width: CGFloat = 0
  @State private var alignments: [NativeMarkdownTableAlignment] = []

  var body: some View {
    NativeTableViewport {
      configuration.label
        .fixedSize(horizontal: true, vertical: false)
        .environment(\.nativeMarkdownTableLayout, .init(width: width, alignments: alignments))
        .markdownTableBorderStyle(.init(.insideBorders, color: appearance.gridLine, width: 0.5))
        .markdownTableBackgroundStyle(.init { row, column in
          row == 0 || column == 0 ? appearance.headerBackground : appearance.background
        })
        .clipShape(RoundedRectangle(cornerRadius: appearance.cornerRadius ?? radius, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: appearance.cornerRadius ?? radius, style: .continuous)
            .strokeBorder(appearance.gridLine, lineWidth: 0.5)
        }
    }
    .background(GeometryReader { geometry in
      Color.clear.preference(key: NativeMarkdownTableWidthKey.self, value: geometry.size.width)
    })
    .onPreferenceChange(NativeMarkdownTableWidthKey.self) { value in
      if value.isFinite && value > 0 && abs(width - value) > 0.5 { width = value }
    }
    .onAppear { updateAlignment(configuration.content) }
    .onChange(of: configuration.content) { updateAlignment($0) }
  }
  private func updateAlignment(_ content: MarkdownContent) {
    let next = NativeMarkdownTableAlignment.columns(in: content.renderMarkdown())
    if next != alignments { alignments = next }
  }
}

private struct NativeMarkdownTableCell: View {
  let configuration: TableCellConfiguration
  @Environment(\.nativeMarkdownTableLayout) private var layout
  @Environment(\.openUITheme) private var theme
  @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
  var body: some View {
    let alignment = layout.alignments.indices.contains(configuration.column)
      ? layout.alignments[configuration.column].frameAlignment : .leading
    let font = configuration.row == 0 ? theme.tableAppearance?.headerFont : theme.tableAppearance?.bodyFont
    configuration.label
      .markdownTextStyle {
        if let font {
          FontFamily(font.family.map(FontProperties.Family.custom) ?? .system(font.design))
          FontSize(font.size)
          FontWeight(font.weight)
        } else if configuration.row == 0 { FontWeight(.medium) }
        BackgroundColor(nil)
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(minHeight: font.map { $0.resolved(for: .body).measuredLineHeight(scale: scale) }, alignment: .top)
      .padding(.horizontal, 8)
      .padding(.vertical, 12)
      .frame(minWidth: configuration.row == 0 ? layout.minimumColumnWidth : nil, alignment: alignment)
  }
}

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
  private var markdownTheme: Theme {
    var result = Theme.basic
    if let table = theme.tableAppearance {
      result = result.table { configuration in
        NativeMarkdownTable(configuration: configuration, appearance: table, radius: theme.radius3xl)
          .markdownMargin(top: 0, bottom: theme.spaceM)
      }.tableCell { configuration in
        NativeMarkdownTableCell(configuration: configuration)
      }
    }
    if let spacing = theme.markdownListItemSpacing {
      result = result.listItem { configuration in
        configuration.label
          .frame(minHeight: font.measuredLineHeight(scale: scale), alignment: .topLeading)
          .padding(.bottom, max(0, spacing) * scale)
      }
    }
    return result
  }
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
      .markdownTextStyle(\.strong) {
        if let emphasis = theme.markdownEmphasisFont {
          FontFamily(emphasis.family.map(FontProperties.Family.custom) ?? .system(emphasis.design))
          FontWeight(emphasis.weight)
        } else {
          FontWeight(style.emphasisWeight ?? theme.textBodyDefaultHeavy.weight)
        }
      }
      .markdownTextStyle(\.code) {
        if theme.markdownEmphasisFont != nil { FontFamily(.system(.monospaced)) }
        FontFamilyVariant(.monospaced)
        FontSize(.em(0.94))
      }
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
      .markdownTheme(markdownTheme)
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
private struct NativePreparedMarkdown: @unchecked Sendable {
  let request: NativeRichTextRequest
  let content: MarkdownContent
}

private actor NativeMarkdownWorker {
  static let shared = NativeMarkdownWorker()
  func prepare(_ request: NativeRichTextRequest) throws -> NativePreparedMarkdown {
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

/// One current task plus one replaceable pending request. Appending does not
/// cancel already useful work; source corrections, configuration changes and
/// unmounts reject old results. A fit reads this projection without publishing.
@MainActor final class NativeMarkdownDocument: ObservableObject {
  @Published private var prepared: NativePreparedMarkdown?
  private var latest: NativeRichTextRequest?
  private var work: Task<Void, Never>?
  private var generation: UInt64 = 0
  private var fallbackSource: OpenUIString?
  private var fallback = MarkdownContent("")
  private(set) var fallbackParseCount = 0
  private(set) var preparationCount = 0
  var currentSource: OpenUIString? { prepared?.request.source }

  private func compatible(_ old: NativeRichTextRequest, _ next: NativeRichTextRequest) -> Bool {
    old.mode == next.mode && old.sources == next.sources
      && old.fontSize == next.fontSize && old.color == next.color
      && next.source.displayString.utf16.starts(with: old.source.displayString.utf16)
  }

  func content(for request: NativeRichTextRequest) -> MarkdownContent {
    if let prepared, compatible(prepared.request, request) { return prepared.content }
    // Synchronous snapshot/size-only hosts still receive readable content on
    // first render. Cache that one prefix rather than parsing in every body/fit.
    if fallbackSource != request.source {
      fallbackSource = request.source
      fallback = MarkdownContent(request.source.displayString)
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
    }
    guard work == nil, prepared?.request != request else { return }
    start(request)
  }

  private func start(_ request: NativeRichTextRequest) {
    preparationCount += 1
    let epoch = generation
    work = Task { @MainActor [weak self] in
      let result = try? await NativeMarkdownWorker.shared.prepare(request)
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
