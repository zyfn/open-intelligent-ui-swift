import SwiftUI
import OpenUILang
import OpenSwiftUI
import CoreText
#if os(iOS)
import UIKit
typealias PlatformTextView = UITextView
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias InlineHost = UIHostingController<AnyView>
#else
import AppKit
typealias PlatformTextView = NSTextView
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias InlineHost = NSHostingView<AnyView>
#endif

/// TextKit owns line breaking, with stable SwiftUI hosts for attachment glyphs.
struct InlineParagraph: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.self) private var inheritedEnvironment
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.locale) private var locale
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.intelligentUIEditorial) private var editorial
    @Environment(\.intelligentUIImages) private var images
    @Environment(\.intelligentUIImageRevisions) private var imageRevisions
    @Environment(\.intelligentUIImagePresentations) private var imagePresentations
    @Environment(\.intelligentUIMapContentInsets) private var mapInsets
    @Environment(\.intelligentUIImageAlbum) private var album
    @Environment(\.intelligentUIInteractiveContent) private var interactive
    @Environment(\.intelligentUIScrolling) private var scrolling
    @Environment(\.intelligentUIContentBackground) private var background
    @Environment(\.layoutDirection) private var direction
    @State private var attachmentRevision = 0
    #if compiler(>=6.2)
    @Environment(\.fontResolutionContext) private var fontContext
    #endif

    private var typography: TextTypography {
        TextTypography(size: context.string("size"), weight: context.string("weight"), editorial: editorial,
                       theme: theme, colorScheme: colorScheme)
    }
    private var nativeFont: PlatformFont {
        let style = typography
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            var font = style.font.weight(style.weight)
            if context.flag("tabularNums") == true { font = font.monospacedDigit() }
            if context.flag("italic") == true { font = font.italic() }
            return font.resolve(in: fontContext).ctFont as PlatformFont
        }
        #endif
        let base = style.nativeFont ?? InlineFonts.semantic(size: style.sizeName, typeSize: typeSize)
        return InlineFonts.styled(base, weight: style.weight, tabular: context.flag("tabularNums") == true,
                                  italic: context.flag("italic") == true)
    }

    var body: some View {
        let style = typography
        let environment = InlineEnvironment(theme: theme, typeSize: typeSize, colorScheme: colorScheme,
            contrast: contrast, locale: locale.identifier, displayScale: displayScale,
            reduceMotion: reduceMotion, differentiateWithoutColor: differentiateWithoutColor,
            editorial: editorial, images: images, imageRevisions: imageRevisions,
            imagePresentations: imagePresentations, mapInsets: mapInsets, album: album,
            interactive: interactive, scrolling: scrolling, background: background, direction: direction,
            canInteract: context.canInteract)
        return InlineParagraphBridge(parts: context.children("text").map { child in
            if case .string(let text) = child.value { return .text(text.displayString) }
            return .attachment(id: child.id, value: child.value, view: AnyView(context.render(child.value)
                .environmentObject(state)
                .environment(\.intelligentUIInlineContent, true)
                // The outer snapshot preserves read-only system values; the inner
                // inline flag deliberately overrides its captured value.
                .environment(\.self, inheritedEnvironment)))
        }, size: style.sizeName, color: theme.textColor(context.string("color")), weight: style.weightName,
        lineSpacing: style.lineSpacing, maxLines: TextLineLimit.resolve(context.number("maxLines")),
        open: { url in
            guard context.canInteract, !interactive, SourceURL.isActionable(url) else { return }
            Task { await context.perform(OpenUIActions.openURL(url)) }
        }, italic: context.flag("italic") == true, lineThrough: context.flag("lineThrough") == true,
        tabularNums: context.flag("tabularNums") == true, typeSize: typeSize, emphasisWeight: theme.emphasisWeight,
        nativeFont: nativeFont, direction: direction, environment: environment,
        layoutRevision: attachmentRevision, onLayoutInvalidation: { attachmentRevision &+= 1 })
    }
}

struct InlineEnvironment: Equatable {
    let theme: IntelligentUITheme
    let typeSize: DynamicTypeSize
    let colorScheme: ColorScheme
    let contrast: ColorSchemeContrast
    let locale: String
    let displayScale: CGFloat
    let reduceMotion: Bool
    let differentiateWithoutColor: Bool
    let editorial: EditorialContext
    let images: [String: Image]
    let imageRevisions: [String: String]
    let imagePresentations: [String: IntelligentUIImagePresentation]
    let mapInsets: EdgeInsets?
    let album: [ImageAlbumItem]
    let interactive: Bool
    let scrolling: Bool
    let background: Color?
    let direction: LayoutDirection
    let canInteract: Bool
}

enum InlinePart {
    case text(String)
    /// Retained for internal clients/tests; production attachments use child IDs.
    case view(AnyView)
    case attachment(id: String, value: Value, view: AnyView)
}
private enum InlinePartIdentity: Equatable {
    case text(String)
    case attachment(String)
}

private struct InlineAttachmentRoot: View {
    let content: AnyView
    let reportSize: (CGSize) -> Void
    var body: some View {
        content.fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { reportSize($0) }
    }
}

final class InlineNativeView: PlatformTextView {
    private final class Hosted {
        let host: InlineHost
        let attachment = NSTextAttachment()
        var value: Value?
        var environment: InlineEnvironment?
        var generation = 0
        var width: CGFloat?
        var fitted: CGSize?
        var reported: CGSize?
        init(host: InlineHost) { self.host = host }
    }
    private var records: [String: Hosted] = [:]
    private var orderedIDs: [String] = []
    private var identities: [InlinePartIdentity] = []
    private var parsed: [String: AttributedString] = [:]
    private var styled: [String: NSAttributedString] = [:]
    private var cachedWidth: CGFloat?
    private var cachedSize: CGSize = .zero
    private var relayoutScheduled = false
    private var lastEnvironment: InlineEnvironment?
    private var lastColor: Color?
    private var lastDirection: LayoutDirection = .leftToRight
    private var layoutInvalidated: () -> Void = {}
    var hosts: [InlineHost] { orderedIDs.compactMap { records[$0]?.host } }
    var parts: [InlinePart] = []
    var baseFont = PlatformFont.systemFont(ofSize: 17)
    var ink = PlatformColor.labelColorCompat
    var spacing: CGFloat = 4
    var limit: Int = 0
    var italic = false
    var lineThrough = false
    var tabularNums = false
    var emphasisWeight: Font.Weight = .medium
    var open: (String) -> Void = { _ in }

    #if os(iOS)
    override init(frame: CGRect, textContainer: NSTextContainer?) { super.init(frame: frame, textContainer: textContainer) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func didMoveToWindow() { super.didMoveToWindow(); attachHosts() }
    private func attachHosts() {
        var responder: UIResponder? = next
        while let current = responder, !(current is UIViewController) { responder = current.next }
        let parent = window == nil ? nil : responder as? UIViewController
        for host in hosts where host.parent !== parent {
            if host.parent != nil { host.willMove(toParent: nil); host.removeFromParent() }
            if let parent { parent.addChild(host); host.didMove(toParent: parent) }
        }
    }
    #endif

    func configure(_ bridge: InlineParagraphBridge) {
        IntelligentUIPerformance.record("inline.configure")
        let proposedFont = bridge.nativeFont ?? InlineFonts.legacy(size: bridge.size, typeSize: bridge.typeSize,
            weight: bridge.weight, tabular: bridge.tabularNums)
        let styleChanged = !baseFont.isEqual(proposedFont) || lastColor != bridge.color || spacing != bridge.lineSpacing
            || limit != (bridge.maxLines ?? 0) || italic != bridge.italic || lineThrough != bridge.lineThrough
            || tabularNums != bridge.tabularNums || emphasisWeight != bridge.emphasisWeight
            || lastDirection != bridge.direction || lastEnvironment?.colorScheme != bridge.environment?.colorScheme
            || lastEnvironment?.contrast != bridge.environment?.contrast
        parts = bridge.parts; baseFont = proposedFont; ink = PlatformColor(bridge.color)
        lastColor = bridge.color; spacing = bridge.lineSpacing; limit = bridge.maxLines ?? 0
        italic = bridge.italic; lineThrough = bridge.lineThrough; tabularNums = bridge.tabularNums
        emphasisWeight = bridge.emphasisWeight; lastDirection = bridge.direction; open = bridge.open
        layoutInvalidated = bridge.onLayoutInvalidation
        if styleChanged { styled.removeAll(keepingCapacity: true); cachedWidth = nil }

        var nextIDs: [String] = [], nextIdentities: [InlinePartIdentity] = [], textKeys = Set<String>()
        var legacyIndex = 0
        for part in parts {
            let id: String, value: Value?, view: AnyView, legacy: Bool
            switch part {
            case .text(let text):
                nextIdentities.append(.text(text)); textKeys.insert(text)
                continue
            case .view(let content):
                id = "legacy-\(legacyIndex)"; legacyIndex += 1; value = nil; view = content; legacy = true
            case .attachment(let childID, let contentValue, let content):
                id = childID; value = contentValue; view = content; legacy = false
            }
            nextIDs.append(id); nextIdentities.append(.attachment(id))
            let record: Hosted
            if let existing = records[id] { record = existing }
            else {
                record = Hosted(host: InlineHost(rootView: AnyView(EmptyView())))
                records[id] = record
                #if os(iOS)
                record.host.view.backgroundColor = .clear; addSubview(record.host.view)
                #else
                addSubview(record.host)
                #endif
            }
            if legacy || record.generation == 0 || record.value != value || record.environment != bridge.environment {
                record.generation += 1
                let generation = record.generation
                record.value = value; record.environment = bridge.environment
                record.width = nil; record.fitted = nil; record.reported = nil
                record.host.rootView = AnyView(InlineAttachmentRoot(content: view, reportSize: { [weak self] size in
                    self?.attachmentChanged(id: id, generation: generation, size: size)
                }))
                IntelligentUIPerformance.record("inline.hostUpdate")
                cachedWidth = nil
            }
        }
        let retained = Set(nextIDs)
        for id in records.keys.filter({ !retained.contains($0) }) {
            if let record = records.removeValue(forKey: id) { detach(record.host) }
        }
        if identities != nextIdentities { cachedWidth = nil }
        identities = nextIdentities; orderedIDs = nextIDs; lastEnvironment = bridge.environment
        parsed = parsed.filter { textKeys.contains($0.key) }
        styled = styled.filter { textKeys.contains($0.key) }
        #if os(iOS)
        attachHosts()
        #endif
    }

    private func attachmentChanged(id: String, generation: Int, size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              let record = records[id], record.generation == generation else { return }
        let previous = record.reported ?? record.fitted
        record.reported = size
        if let previous, abs(previous.width - size.width) < 0.5, abs(previous.height - size.height) < 0.5 { return }
        record.width = nil; cachedWidth = nil
        scheduleRelayout()
    }
    private func scheduleRelayout() {
        guard !relayoutScheduled else { return }
        relayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.relayoutScheduled = false
            self.invalidateIntrinsicContentSize()
            #if os(iOS)
            self.setNeedsLayout()
            #else
            self.needsLayout = true
            #endif
            self.layoutInvalidated()
        }
    }

    func measure(_ proposedWidth: CGFloat) -> CGSize {
        IntelligentUIPerformance.record("inline.fittingRequest")
        let width = proposedWidth.isFinite ? max(1, proposedWidth) : 320
        if cachedWidth == width { return cachedSize }
        return IntelligentUIPerformance.measure("inline.measure") { layout(width) }
    }

    private func layout(_ width: CGFloat) -> CGSize {
        let result = NSMutableAttributedString(string: "")
        var placements: [(position: Int, id: String, size: CGSize)] = []
        var attachmentIndex = 0
        for part in parts {
            switch part {
            case .text(let text): result.append(styledText(text))
            case .view, .attachment:
                guard orderedIDs.indices.contains(attachmentIndex), let record = records[orderedIDs[attachmentIndex]] else { continue }
                let id = orderedIDs[attachmentIndex]; attachmentIndex += 1
                let size: CGSize
                if record.width == width, let fitted = record.fitted { size = fitted }
                else {
                    let ideal = IntelligentUIPerformance.measure("inline.attachmentFit") {
                        #if os(iOS)
                        return record.host.sizeThatFits(in: CGSize(width: width, height: 10_000))
                        #else
                        record.host.frame.size.width = width
                        return record.host.fittingSize
                        #endif
                    }
                    size = CGSize(width: min(width, max(1, ideal.width)), height: max(1, ideal.height))
                    record.width = width; record.fitted = size
                }
                record.attachment.bounds = CGRect(x: 0, y: baseFont.descender, width: size.width, height: size.height)
                placements.append((result.length, id, size))
                result.append(NSAttributedString(attachment: record.attachment))
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = spacing; paragraph.lineBreakMode = .byWordWrapping
        paragraph.baseWritingDirection = lastDirection == .rightToLeft ? .rightToLeft : .leftToRight
        paragraph.alignment = .natural
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        #if os(iOS)
        if attributedText == nil || !attributedText.isEqual(to: result) {
            let selection = selectedRange
            attributedText = result
            if selection.location != NSNotFound, NSMaxRange(selection) <= result.length { selectedRange = selection }
        }
        let container = textContainer, manager = layoutManager
        #else
        if textStorage?.isEqual(to: result) != true {
            let selection = selectedRange()
            textStorage?.setAttributedString(result)
            if selection.location != NSNotFound, NSMaxRange(selection) <= result.length { setSelectedRange(selection) }
        }
        guard let container = textContainer, let manager = layoutManager else { return .zero }
        container.widthTracksTextView = false; container.heightTracksTextView = false
        #endif
        container.lineFragmentPadding = 0; container.lineBreakMode = .byWordWrapping
        container.maximumNumberOfLines = limit; container.size = CGSize(width: width, height: 1_000_000)
        manager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: result.length), actualCharacterRange: nil)
        IntelligentUIPerformance.measure("inline.layout") { manager.ensureLayout(for: container) }
        let glyphs = manager.glyphRange(for: container)
        for placement in placements {
            guard let record = records[placement.id] else { continue }
            let range = manager.glyphRange(forCharacterRange: NSRange(location: placement.position, length: 1), actualCharacterRange: nil)
            let visible = NSIntersectionRange(range, glyphs).length > 0
            let rect = manager.boundingRect(forGlyphRange: range, in: container)
            #if os(iOS)
            let view = record.host.view!
            view.isUserInteractionEnabled = visible
            #else
            let view = record.host
            #endif
            view.isHidden = !visible
            let frame = CGRect(origin: rect.origin, size: placement.size)
            if view.frame != frame { view.frame = frame }
        }
        cachedWidth = width
        cachedSize = CGSize(width: width, height: ceil(max(baseFont.ascender - baseFont.descender, manager.usedRect(for: container).maxY)))
        return cachedSize
    }

    private func styledText(_ text: String) -> NSAttributedString {
        if let cached = styled[text] { return cached }
        let value: AttributedString
        if let cached = parsed[text] { value = cached }
        else {
            value = IntelligentUIPerformance.measure("inline.parse") {
                (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
            }
            parsed[text] = value
        }
        let result = NSMutableAttributedString(attributedString: NSAttributedString(value))
        result.addAttributes([.font: baseFont, .foregroundColor: ink], range: NSRange(location: 0, length: result.length))
        var offset = 0
        for segment in value.runs {
            let count = String(value[segment.range].characters).utf16.count
            let intent = segment.inlinePresentationIntent ?? []
            var font = intent.contains(.code) ? PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular) : baseFont
            if intent.contains(.stronglyEmphasized) {
                font = InlineFonts.styled(font, weight: emphasisWeight, tabular: tabularNums && !intent.contains(.code), italic: false)
            }
            if italic || intent.contains(.emphasized) { font = InlineFonts.italic(font) }
            result.addAttribute(.font, value: font, range: NSRange(location: offset, length: count))
            if lineThrough || intent.contains(.strikethrough) { result.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: offset, length: count)) }
            offset += count
        }
        styled[text] = result
        return result
    }

    func removeAllHosts() {
        for record in records.values { detach(record.host) }
        records.removeAll(); orderedIDs.removeAll(); identities.removeAll()
        cachedWidth = nil; layoutInvalidated = {}
    }
    private func detach(_ host: InlineHost) {
        host.rootView = AnyView(EmptyView())
        #if os(iOS)
        host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
        #else
        host.removeFromSuperview()
        #endif
    }
}

@MainActor private enum InlineFonts {
    static func semantic(size: String, typeSize: DynamicTypeSize) -> PlatformFont {
        #if os(iOS)
        let style: UIFont.TextStyle = size == "xs" ? .caption1 : size == "sm" ? .subheadline : size == "lg" ? .title3 : .body
        let categories: [DynamicTypeSize: UIContentSizeCategory] = [.xSmall: .extraSmall, .small: .small, .medium: .medium, .large: .large, .xLarge: .extraLarge, .xxLarge: .extraExtraLarge, .xxxLarge: .extraExtraExtraLarge, .accessibility1: .accessibilityMedium, .accessibility2: .accessibilityLarge, .accessibility3: .accessibilityExtraLarge, .accessibility4: .accessibilityExtraExtraLarge, .accessibility5: .accessibilityExtraExtraExtraLarge]
        return UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: categories[typeSize] ?? .large))
        #else
        let style: NSFont.TextStyle = size == "xs" ? .caption1 : size == "sm" ? .subheadline : size == "lg" ? .title3 : .body
        return NSFont.preferredFont(forTextStyle: style)
        #endif
    }
    static func legacy(size: String, typeSize: DynamicTypeSize, weight: String, tabular: Bool) -> PlatformFont {
        #if os(iOS)
        let base = semantic(size: size, typeSize: typeSize)
        #else
        let scales: [DynamicTypeSize: CGFloat] = [.xSmall: 0.82, .small: 0.88, .medium: 0.94, .large: 1, .xLarge: 1.12, .xxLarge: 1.24, .xxxLarge: 1.35, .accessibility1: 1.65, .accessibility2: 1.95, .accessibility3: 2.35, .accessibility4: 2.76, .accessibility5: 3.12]
        let base = NSFont.systemFont(ofSize: (size == "xs" ? 12 : size == "sm" ? 15 : size == "lg" ? 20 : 17) * (scales[typeSize] ?? 1))
        #endif
        let nativeWeight: PlatformFont.Weight = weight == "semibold" ? .semibold : weight == "medium" ? .medium : .regular
        return tabular ? PlatformFont.monospacedDigitSystemFont(ofSize: base.pointSize, weight: nativeWeight) : PlatformFont.systemFont(ofSize: base.pointSize, weight: nativeWeight)
    }
    static func styled(_ font: PlatformFont, weight: Font.Weight, tabular: Bool, italic: Bool) -> PlatformFont {
        let nativeWeight = self.weight(weight)
        // Preserve the supplied family while applying traits. Core Text is
        // public on every deployment target and supports custom font partners.
        var attributes: [String: Any] = [kCTFontTraitsAttribute as String: [kCTFontWeightTrait as String: nativeWeight.rawValue]]
        if tabular { attributes[kCTFontFeatureSettingsAttribute as String] = [[kCTFontFeatureTypeIdentifierKey as String: kNumberSpacingType, kCTFontFeatureSelectorIdentifierKey as String: kMonospacedNumbersSelector]] }
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        var result = CTFontCreateCopyWithAttributes(font as CTFont, font.pointSize, nil, descriptor) as PlatformFont
        if italic { result = self.italic(result) }
        return result
    }
    static func italic(_ font: PlatformFont) -> PlatformFont {
        #if os(iOS)
        var traits = font.fontDescriptor.symbolicTraits; traits.insert(.traitItalic)
        return font.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
        #else
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #endif
    }
    static func weight(_ value: Font.Weight) -> PlatformFont.Weight {
        switch value {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

private extension PlatformColor {
    static var labelColorCompat: PlatformColor {
        #if os(iOS)
        .label
        #else
        .labelColor
        #endif
    }
}

struct InlineParagraphBridge {
    let parts: [InlinePart]
    let size: String
    let color: Color
    let weight: String
    let lineSpacing: CGFloat
    let maxLines: Int?
    let open: (String) -> Void
    var italic = false
    var lineThrough = false
    var tabularNums = false
    var typeSize: DynamicTypeSize = .large
    var emphasisWeight: Font.Weight = .medium
    var nativeFont: PlatformFont? = nil
    var direction: LayoutDirection = .leftToRight
    var environment: InlineEnvironment? = nil
    var layoutRevision = 0
    var onLayoutInvalidation: () -> Void = {}
}
#if os(iOS)
extension InlineParagraphBridge: UIViewRepresentable {
    final class Coordinator: NSObject, UITextViewDelegate {
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            (textView as? InlineNativeView)?.open(URL.absoluteString); return false
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> InlineNativeView {
        let storage = NSTextStorage(), manager = NSLayoutManager(), container = NSTextContainer(size: .zero)
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let view = InlineNativeView(frame: .zero, textContainer: container)
        view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false; view.backgroundColor = .clear
        view.textContainerInset = .zero; view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: InlineNativeView, context: Context) { view.configure(self) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: InlineNativeView, context: Context) -> CGSize? { uiView.measure(proposal.width ?? 320) }
    static func dismantleUIView(_ view: InlineNativeView, coordinator: Coordinator) { view.removeAllHosts(); view.delegate = nil }
}
#else
extension InlineParagraphBridge: NSViewRepresentable {
    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL { (textView as? InlineNativeView)?.open(url.absoluteString) }
            else if let url = link as? String { (textView as? InlineNativeView)?.open(url) }
            return true
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> InlineNativeView {
        let view = InlineNativeView(frame: .zero)
        view.isEditable = false; view.isSelectable = true; view.drawsBackground = false; view.textContainerInset = .zero
        view.isHorizontallyResizable = false; view.isVerticallyResizable = true; view.delegate = context.coordinator
        return view
    }
    func updateNSView(_ view: InlineNativeView, context: Context) { view.configure(self) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: InlineNativeView, context: Context) -> CGSize? { nsView.measure(proposal.width ?? 320) }
    static func dismantleNSView(_ view: InlineNativeView, coordinator: Coordinator) { view.removeAllHosts(); view.delegate = nil }
}
#endif
