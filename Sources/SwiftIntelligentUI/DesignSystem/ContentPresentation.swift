import SwiftUI
import OpenUILang

/// One mounted content tree. Measurement only changes the viewport, so crossing
/// its height limit never replaces fields, disclosures, or local focus state.
struct BoundedContentScroll<Content: View>: View {
    var maximumHeight: CGFloat = 480
    @ViewBuilder let content: () -> Content
    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { value in
                    guard value.isFinite, value >= 0, abs(value - measuredHeight) > 0.5 else { return }
                    measuredHeight = value
                }
        }
        .frame(idealHeight: viewportHeight, maxHeight: viewportHeight)
    }
    private var viewportHeight: CGFloat { measuredHeight > 0 ? min(maximumHeight, measuredHeight) : maximumHeight }
}

/// Summary for an outer native control whose children are presentation only.
/// Do not include action payloads, URLs or raw serialized component syntax.
enum PresentationText {
    static func summary(_ value: Value?, depth: Int = 0) -> String {
        guard depth < 16, let value else { return "" }
        switch value {
        case .string(let text): return text.displayString
        case .array(let values):
            return values.map { summary($0, depth: depth + 1) }.filter { !$0.isEmpty }.joined(separator: "，")
        case .element(let element):
            let keys = ["text", "title", "description", "alt", "label", "children", "content"]
            return keys.compactMap { key in element.props.last { $0.0 == key }?.1 }
                .map { summary($0, depth: depth + 1) }.filter { !$0.isEmpty }.joined(separator: "，")
        default: return ""
        }
    }
}

extension View {
    /// Applied inside an outer Button label; that Button supplies its own label.
    /// Scrolling containers can stay outside this modifier to retain scrolling.
    func intelligentUIPresentationOnly() -> some View {
        environment(\.intelligentUIInteractiveContent, true)
            .environment(\.openURL, OpenURLAction { _ in .discarded })
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
