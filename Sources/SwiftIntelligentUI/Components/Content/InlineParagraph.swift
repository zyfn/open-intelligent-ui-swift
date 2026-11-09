import SwiftUI
import OpenUILang
import OpenUISwiftUI
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

/// TextKit owns line breaking. Embedded SwiftUI views occupy attachment glyphs,
/// so a link, badge or formula can follow the last line of a paragraph.
struct InlineParagraph: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.intelligentUIEditorial) private var editorial
    @Environment(\.intelligentUIImages) private var images
    @Environment(\.intelligentUIImageAlbum) private var album
    @Environment(\.intelligentUIInteractiveContent) private var interactive
    @Environment(\.intelligentUIScrolling) private var scrolling
    @Environment(\.intelligentUIContentBackground) private var background
    @Environment(\.layoutDirection) private var direction
    private var size: String { editorial.cardSubtitle ? "xs" : context.string("size") ?? (editorial.compactContent ? "sm" : "md") }
    private var weight: String {
        if let weight = context.string("weight") { return weight }
        return size == "md" && theme.defaultBodyWeight(for: colorScheme) == .medium ? "medium" : "normal"
    }
    var body: some View {
        InlineParagraphBridge(parts: context.children("text").map { child in
            if case .string(let text) = child.value { return .text(text.displayString) }
            return .view(AnyView(context.render(child.value)
                .environmentObject(state).environment(\.intelligentUITheme, theme)
                .environment(\.dynamicTypeSize, typeSize).environment(\.colorScheme, colorScheme)
                .environment(\.intelligentUIEditorial, editorial)
                .environment(\.intelligentUIImages, images).environment(\.intelligentUIImageAlbum, album)
                .environment(\.intelligentUIInteractiveContent, interactive).environment(\.intelligentUIScrolling, scrolling)
                .environment(\.intelligentUIContentBackground, background)
                .environment(\.layoutDirection, direction)
                .environment(\.intelligentUIInlineContent, true)))
        }, size: size,
        color: editorial.cardSubtitle && context.string("color") == nil ? theme.secondaryText : theme.textColor(context.string("color")), weight: weight,
        lineSpacing: theme.bodyLineSpacing, maxLines: TextLineLimit.resolve(context.number("maxLines")),
        open: { url in
            guard context.canInteract, SourceURL.isActionable(url) else { return }
            Task { await context.perform(OpenUIActions.openURL(url)) }
        }, italic: context.flag("italic") == true, lineThrough: context.flag("lineThrough") == true, tabularNums: context.flag("tabularNums") == true, typeSize: typeSize, emphasisWeight: theme.emphasisWeight)
    }
}

enum InlinePart { case text(String), view(AnyView) }

final class InlineNativeView: PlatformTextView {
    #if os(iOS)
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachHosts()
    }
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
    var parts: [InlinePart] = []
    var hosts: [InlineHost] = []
    var baseFont = PlatformFont.systemFont(ofSize: 17)
    var ink = PlatformColor.labelColorCompat
    var spacing: CGFloat = 4
    var limit: Int = 0
    var italic = false
    var lineThrough = false
    var tabularNums = false
    var emphasisWeight: Font.Weight = .medium
    var open: (String) -> Void = { _ in }

    func configure(_ bridge: InlineParagraphBridge) {
        parts = bridge.parts; ink = PlatformColor(bridge.color); spacing = bridge.lineSpacing
        limit = bridge.maxLines ?? 0; open = bridge.open
        italic = bridge.italic; lineThrough = bridge.lineThrough; tabularNums = bridge.tabularNums
        emphasisWeight = bridge.emphasisWeight
        #if os(iOS)
        let style: UIFont.TextStyle = bridge.size == "xs" ? .caption1 : bridge.size == "sm" ? .subheadline : bridge.size == "lg" ? .title3 : .body
        let categories: [DynamicTypeSize: UIContentSizeCategory] = [.xSmall: .extraSmall, .small: .small, .medium: .medium, .large: .large, .xLarge: .extraLarge, .xxLarge: .extraExtraLarge, .xxxLarge: .extraExtraExtraLarge, .accessibility1: .accessibilityMedium, .accessibility2: .accessibilityLarge, .accessibility3: .accessibilityExtraLarge, .accessibility4: .accessibilityExtraExtraLarge, .accessibility5: .accessibilityExtraExtraExtraLarge]
        baseFont = UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: categories[bridge.typeSize] ?? .large))
        #else
        let scales: [DynamicTypeSize: CGFloat] = [.xSmall: 0.82, .small: 0.88, .medium: 0.94, .large: 1, .xLarge: 1.12, .xxLarge: 1.24, .xxxLarge: 1.35, .accessibility1: 1.65, .accessibility2: 1.95, .accessibility3: 2.35, .accessibility4: 2.76, .accessibility5: 3.12]
        baseFont = NSFont.systemFont(ofSize: (bridge.size == "xs" ? 12 : bridge.size == "sm" ? 15 : bridge.size == "lg" ? 20 : 17) * (scales[bridge.typeSize] ?? 1))
        #endif
        if bridge.weight != "normal" {
            baseFont = PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: bridge.weight == "semibold" ? .semibold : .medium)
        }
        if tabularNums { baseFont = PlatformFont.monospacedDigitSystemFont(ofSize: baseFont.pointSize, weight: bridge.weight == "semibold" ? .semibold : bridge.weight == "medium" ? .medium : .regular) }
        let views = parts.compactMap { part -> AnyView? in if case .view(let view) = part { return view }; return nil }
        while hosts.count > views.count {
            let host = hosts.removeLast()
            #if os(iOS)
            host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
            #else
            host.removeFromSuperview()
            #endif
        }
        for (index, view) in views.enumerated() {
            if hosts.indices.contains(index) { hosts[index].rootView = view }
            else {
                let host = InlineHost(rootView: view)
                hosts.append(host)
                #if os(iOS)
                host.view.backgroundColor = .clear; addSubview(host.view)
                #else
                addSubview(host)
                #endif
            }
        }
        #if os(iOS)
        attachHosts()
        #endif
    }

    func measure(_ width: CGFloat) -> CGSize {
        let width = max(1, width)
        let result = NSMutableAttributedString(string: "")
        var attachments: [(Int, Int, CGSize)] = []
        var childIndex = 0
        for part in parts {
            switch part {
            case .text(let text):
                let value = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
                let run = NSMutableAttributedString(attributedString: NSAttributedString(value))
                run.addAttributes([.font: baseFont, .foregroundColor: ink], range: NSRange(location: 0, length: run.length))
                var offset = 0
                for segment in value.runs {
                    let count = String(value[segment.range].characters).utf16.count
                    let intent = segment.inlinePresentationIntent ?? []
                    var font = intent.contains(.code) ? PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular) : baseFont
                    if intent.contains(.stronglyEmphasized) {
                        let weight = nativeWeight(emphasisWeight)
                        if intent.contains(.code) { font = PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: weight) }
                        else if tabularNums { font = PlatformFont.monospacedDigitSystemFont(ofSize: baseFont.pointSize, weight: weight) }
                        else { font = PlatformFont.systemFont(ofSize: baseFont.pointSize, weight: weight) }
                    }
                    #if os(iOS)
                    var traits = font.fontDescriptor.symbolicTraits
                    if italic || intent.contains(.emphasized) { traits.insert(.traitItalic) }
                    if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { font = UIFont(descriptor: descriptor, size: font.pointSize) }
                    #else
                    if italic || intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                    #endif
                    run.addAttribute(.font, value: font, range: NSRange(location: offset, length: count))
                    if lineThrough || intent.contains(.strikethrough) { run.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: offset, length: count)) }
                    offset += count
                }
                result.append(run)
            case .view:
                let host = hosts[childIndex]
                #if os(iOS)
                let ideal = host.sizeThatFits(in: CGSize(width: width, height: 10_000))
                #else
                host.frame.size.width = width
                let ideal = host.fittingSize
                #endif
                let size = CGSize(width: min(width, max(1, ideal.width)), height: max(1, ideal.height))
                let attachment = NSTextAttachment()
                attachment.bounds = CGRect(x: 0, y: baseFont.descender, width: size.width, height: size.height)
                attachments.append((result.length, childIndex, size))
                result.append(NSAttributedString(attachment: attachment)); childIndex += 1
            }
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = spacing; paragraph.lineBreakMode = .byWordWrapping
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        #if os(iOS)
        attributedText = result
        let container = textContainer
        let manager = layoutManager
        #else
        textStorage?.setAttributedString(result)
        guard let container = textContainer, let manager = layoutManager else { return .zero }
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        #endif
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        container.maximumNumberOfLines = limit
        container.size = CGSize(width: width, height: 1_000_000)
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        for (position, index, size) in attachments {
            let range = manager.glyphRange(forCharacterRange: NSRange(location: position, length: 1), actualCharacterRange: nil)
            let visible = NSIntersectionRange(range, glyphs).length > 0
            let rect = manager.boundingRect(forGlyphRange: range, in: container)
            #if os(iOS)
            let view = hosts[index].view!
            #else
            let view = hosts[index]
            #endif
            view.isHidden = !visible
            view.frame = CGRect(x: rect.minX, y: rect.minY, width: size.width, height: size.height)
        }
        return CGSize(width: width, height: ceil(max(baseFont.ascender - baseFont.descender, manager.usedRect(for: container).maxY)))
    }

    private func nativeWeight(_ weight: Font.Weight) -> PlatformFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .medium
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
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let view = InlineNativeView(frame: .zero, textContainer: container)
        view.isEditable = false; view.isScrollEnabled = false; view.backgroundColor = .clear
        view.textContainerInset = .zero; view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: InlineNativeView, context: Context) { view.configure(self) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: InlineNativeView, context: Context) -> CGSize? { uiView.measure(proposal.width ?? 320) }
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
        view.isEditable = false; view.drawsBackground = false; view.textContainerInset = .zero
        view.isHorizontallyResizable = false; view.isVerticallyResizable = true
        view.delegate = context.coordinator
        return view
    }
    func updateNSView(_ view: InlineNativeView, context: Context) { view.configure(self) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: InlineNativeView, context: Context) -> CGSize? { nsView.measure(proposal.width ?? 320) }
}
#endif
