import SwiftUI
import SwiftLang

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
    static func summary(_ value: Value?, locale: Locale = .current, depth: Int = 0) -> String {
        guard depth < 16, let value else { return "" }
        switch value {
        case .string(let text): return text.displayString
        case .number, .boolean: return ValueReading.string(value)
        case .array(let values):
            return values.map { summary($0, locale: locale, depth: depth + 1) }.filter { !$0.isEmpty }.joined(separator: "，")
        case .element(let element):
            if element.typeName == "Table" {
                let columns = ValueReading.array(ValueReading.field(value, "columns")).map { ValueReading.string($0) }
                return ValueReading.array(ValueReading.field(value, "rows")).map { row in
                    let cells = ValueReading.array(row)
                    return columns.indices.map { index in
                        let cell = cells.indices.contains(index) ? ValueReading.string(cells[index]) : ""
                        return columns[index] + ": " + (cell.isEmpty ? "—" : cell)
                    }.joined(separator: "，")
                }.joined(separator: "；")
            }
            if element.typeName == "Chart" {
                let data = ChartData(rows: ValueReading.field(value, "data"),
                    x: ValueReading.field(value, "x").map { ValueReading.string($0) },
                    series: ValueReading.field(value, "series"),
                    scatter: ValueReading.string(ValueReading.field(value, "type")) == "scatter")
                return data.entries.map { entry in
                    entry.label + "，" + entry.series + ": " + (entry.value.map {
                        ChartData.formatted($0, kind: ValueReading.field(value, "format").map { ValueReading.string($0) },
                                            currency: ValueReading.field(value, "currency").map { ValueReading.string($0) }, locale: locale)
                    } ?? SDKStrings.text("chart.missing_value", locale: locale))
                }.joined(separator: "；")
            }
            let keys = ["text", "title", "description", "alt", "label", "code", "tex", "children", "content", "footer", "product", "journey", "items", "sources", "markers"]
            return keys.compactMap { key in element.props.last { $0.0 == key }?.1 }
                .map { summary($0, locale: locale, depth: depth + 1) }.filter { !$0.isEmpty }.joined(separator: "，")
        case .object:
            // Only source fields actually used for presentation are eligible.
            // In particular never read actions, opaque IDs or navigation URLs.
            let keys = ["title", "name", "text", "label", "description", "body", "subtitle", "badge", "caption", "alt",
                        "specification", "merchant", "tags", "condition", "availability",
                        "from", "to", "fromCity", "toCity", "departureDate", "departureTime", "departureZone", "fromTerminal",
                        "arrivalDate", "arrivalTime", "arrivalZone", "toTerminal", "carrier", "serviceNumber", "durationText",
                        "location", "notice", "legs", "connections", "children"]
            var parts = keys.compactMap { ValueReading.field(value, $0) }
                .map { summary($0, locale: locale, depth: depth + 1) }.filter { !$0.isEmpty }
            let price = PricePresentation(value)
            if let text = price.accessibilityText(locale: locale), !text.isEmpty { parts.append(text) }
            if let note = price.note { parts.append(note) }
            // Image slots may contain source strings as well as objects. Their
            // URL is never a spoken label; use only a supplied alt description.
            let images = [ValueReading.field(value, "image")].compactMap { $0 }
                + ValueReading.array(ValueReading.field(value, "images"))
            parts += images.map { ValueReading.string(ValueReading.field($0, "alt")) }.filter { !$0.isEmpty }
            return parts.joined(separator: "，")
        default: return ""
        }
    }
}

extension View {
    /// Applied inside an outer Button label; that Button supplies its own label.
    /// Scrolling containers can stay outside this modifier to retain scrolling.
    func openIntelligentUIPresentationOnly() -> some View {
        environment(\.openIntelligentUIInteractiveContent, true)
            .environment(\.openURL, OpenURLAction { _ in .discarded })
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
