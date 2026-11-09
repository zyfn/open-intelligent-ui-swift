import Foundation
import OpenUILang
import OpenUISwiftUI
import SwiftIntelligentUI

@MainActor enum ProgramChecks {
    static func run(_ name: String?, state: OpenUIState, library: IntelligentUILibrary) async -> [String: Bool] {
        guard let name, let root = state.root else { return [:] }
        let nodes = elements(.element(root))
        var checks = ["nativeScenario": !nodes.contains { ["HtmlView", "YouTube", "Map", "SearchImage"].contains($0.typeName) }]
        switch name {
        case "reading":
            checks["structuredReading"] = nodes.contains { ["List", "Markdown"].contains($0.typeName) }
        case "budget":
            guard let input = nodes.first(where: { ["Input", "Slider"].contains($0.typeName) }),
                  let binding = state.binding(for: input, prop: "value") else { checks["editableBudget"] = false; return checks }
            checks["editableBudget"] = true
            binding.wrappedValue = .number(90)
            let rendered = state.root.map { strings(.element($0)).joined(separator: " ") } ?? ""
            let regex = try! NSRegularExpression(pattern: #"(?<!\d)30(?:\.0+)?(?!\d)"#)
            checks["recalculatesThreeShares"] = regex.numberOfMatches(in: rendered, range: NSRange(rendered.startIndex..., in: rendered)) >= 3
        case "comparison":
            checks["hasTable"] = nodes.contains { $0.typeName == "Table" }
            var urls: [String] = []
            state.onAction = { event in
                if event.type == "open_url", case .string(let url) = event.params.first(where: { $0.0 == "url" })?.1 { urls.append(url.displayString) }
            }
            for node in nodes {
                let context = OpenUIComponentContext(element: node, registry: library.components.registry, state: state)
                if node.typeName == "Link", let url = context.string("url") { _ = await context.perform(OpenUIActions.openURL(url)) }
                else if let action = context.action() { _ = await context.perform(action) }
            }
            checks["preservesSourceURLs"] = Set(urls) == Set(["/a", "/b"])
            let text = strings(.element(root)).joined(separator: " ")
            checks["doesNotInventInventory"] = !["现货", "库存充足", "有货"].contains { text.contains($0) }
        case "editorial":
            checks["hasCover"] = nodes.contains { $0.typeName == "Image" }
            let composedRows = nodes.filter { node in
                guard node.typeName == "Row" else { return false }
                let children = elements(.element(node))
                return children.contains { $0.typeName == "Image" } && children.contains { ["Text", "Title"].contains($0.typeName) }
            }
            checks["hasEditorialRows"] = composedRows.count >= 2 || nodes.filter { $0.typeName == "ImageText" }.count == 2
            checks["hasSources"] = nodes.contains { $0.typeName == "Citation" }
            let values = Set(strings(.element(root)))
            checks["preservesImageURLs"] = values.contains("https://example.com/photo-a.jpg") && values.contains("https://example.com/photo-b.jpg")
            checks["preservesSourceURLs"] = values.contains("/source/a") && values.contains("/source/b")
        case "shopping":
            let cards = nodes.filter { $0.typeName == "ProductCard" }
            let products = cards.compactMap { $0.props.first { $0.0 == "product" }?.1 }
            checks["twoProducts"] = products.count == 2 && products.map { field($0, "id") } == [.string("camera"), .string("headphones")]
            checks["horizontalCollection"] = nodes.contains { $0.typeName == "Carousel" }
            checks["largeMedia"] = cards.allSatisfy { node in
                let layout = node.props.first { $0.0 == "layout" }?.1
                return layout == nil || layout == .null || layout == .string("vertical")
            }
            checks["preservesPrices"] = products.count == 2
                && pricePreserved(in: products[0], amount: 9999, rawAmount: "9999", display: "¥9,999")
                && pricePreserved(in: products[1], amount: 299, rawAmount: "299", display: "¥299")
            checks["preservesPurchaseURLs"] = products.map { field($0, "purchaseURL") } == [.string("/products/nikon-demo?item=camera"), .string("/products/sony-demo?item=headphones")]
            let imageURLs = products.map { product -> Value? in
                guard case .array(let photos) = field(product, "images"), let first = photos.first else { return nil }
                return field(first, "url")
            }
            checks["preservesImageURLs"] = imageURLs == [.string("https://upload.wikimedia.org/wikipedia/commons/9/9b/Nikon_DSLR_camera_D850.jpg"), .string("https://upload.wikimedia.org/wikipedia/commons/thumb/1/13/Sony_WH-CH500-40869.jpg/500px-Sony_WH-CH500-40869.jpg")]
            checks["noInventedTerms"] = products.allSatisfy { product in
                ["merchant", "availability", "condition", "offers"].allSatisfy { field(product, $0) == nil || field(product, $0) == .null }
            }
        case "transport":
            guard let node = nodes.first(where: { $0.typeName == "TransportCard" }), let journey = node.props.first(where: { $0.0 == "journey" })?.1,
                  case .array(let legs) = field(journey, "legs") else { checks["hasJourney"] = false; return checks }
            checks["twoLegs"] = legs.count == 2
            checks["separateTickets"] = field(journey, "separateTickets") == .boolean(true)
            checks["keepsLegURLs"] = legs.map { field($0, "bookingURL") } == [.string("/transport/train"), .string("/transport/flight")]
            checks["keepsDates"] = legs.map { field($0, "departureDate") } == [.string("2026-11-12"), .string("2026-11-13")]
            let connections: [Value] = { if case .array(let values) = field(journey, "connections") { return values.values }; return [] }()
            checks["changeStationIsExplicit"] = connections.contains { field($0, "afterLeg") == .number(0) && field($0, "changeStation") == .boolean(true) && field($0, "durationText") == .string("10小时") }
            checks["noInventedTotal"] = (field(journey, "priceText") == nil || field(journey, "priceText") == .null) && (field(journey, "durationText") == nil || field(journey, "durationText") == .null)
        default: break
        }
        return checks
    }
    private static func pricePreserved(in product: Value, amount: Double, rawAmount: String, display: String) -> Bool {
        let price = field(product, "price"), currency = field(product, "currency")
        if price == .string(display) { return true }
        if price == .number(amount) || price == .string(rawAmount) { return currency == .string("CNY") }
        return field(product, "priceText") == .string(display)
    }
    private static func field(_ value: Value, _ key: String) -> Value? {
        if case .object(let object) = value { return object.fields.first { $0.key == OpenUIString(key) }?.value }
        return nil
    }
    private static func elements(_ value: Value, depth: Int = 0) -> [EvaluatedElement] {
        guard depth < 64 else { return [] }
        switch value {
        case .element(let e): return [e] + e.props.flatMap { elements($0.1, depth: depth + 1) }
        case .array(let a): return a.flatMap { elements($0, depth: depth + 1) }
        case .object(let o): return o.fields.flatMap { elements($0.value, depth: depth + 1) }
        default: return []
        }
    }
    private static func strings(_ value: Value, depth: Int = 0) -> [String] {
        guard depth < 64 else { return [] }
        switch value {
        case .string(let s): return [s.displayString]
        case .number(let n): return [String(n)]
        case .element(let e): return e.props.flatMap { strings($0.1, depth: depth + 1) }
        case .array(let a): return a.flatMap { strings($0, depth: depth + 1) }
        case .object(let o): return o.fields.flatMap { strings($0.value, depth: depth + 1) }
        default: return []
        }
    }
}
