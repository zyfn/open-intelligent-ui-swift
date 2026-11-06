import SwiftUI
import OpenUILang

/// Native equivalent of the pinned upstream's contextual CSS selectors.
struct EditorialContext {
    var flowDepth = 0
    var cardDepth = 0
    var compactContent = false
    var openingCardTitle = false
    var cardSubtitle = false
    var mediaRatio: CGFloat? = nil

}

extension EnvironmentValues {
    @Entry var intelligentUIEditorial = EditorialContext()
    @Entry var intelligentUIInlineContent = false
    @Entry var intelligentUIInteractiveContent = false
}

enum EditorialNode {
    static func imageRatio(_ value: Value) -> CGFloat? {
        if let ratio = ValueReading.number(ValueReading.field(value, "aspectRatio")) { return CGFloat(min(5, max(0.2, ratio))) }
        if kind(value) == "Box", let image = ValueReading.array(ValueReading.field(value, "children")).first { return imageRatio(image) }
        return nil
    }
    static func kind(_ value: Value) -> String {
        if case .element(let element) = value { return element.typeName }
        return "Text"
    }
    static func smallTitle(_ value: Value) -> Bool {
        kind(value) == "Title" && ["", "sm", "md"].contains(ValueReading.string(ValueReading.field(value, "size")))
    }
    static func media(_ value: Value) -> Bool {
        if kind(value) == "Image" || kind(value) == "SearchImage" { return true }
        guard kind(value) == "Box", case .array(let values) = ValueReading.field(value, "children"), values.count == 1 else { return false }
        return ["Image", "SearchImage"].contains(kind(values[0]))
    }
}
