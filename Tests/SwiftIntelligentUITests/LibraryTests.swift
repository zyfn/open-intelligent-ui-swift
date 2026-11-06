import XCTest
import OpenUILang
import OpenUISwiftUI
@testable import SwiftIntelligentUI

final class LibraryTests: XCTestCase {
    func testExportContainsOnlyImplementedComponents() throws {
        let library = try IntelligentUILibrary()
        let expected = Set(["Col", "Row", "Grid", "Box", "Card", "Text", "Title", "Checkbox", "Button", "Slider", "Image", "Icon", "Caption", "Label", "Link", "Input", "TextArea", "Select", "SegmentedControl", "RadioGroup", "ProductCard", "Markdown", "Quote", "Code", "Badge", "List", "ListItem", "Table", "Chart", "Divider", "Spacer", "Carousel", "Form", "Popover", "IconButton", "Pressable", "DatePicker", "Timer", "Flashcard", "Celebration", "Math", "Map", "MapMarker", "HtmlView", "YouTube", "Svg", "Circle", "Ellipse", "Rect", "Line", "Path", "Polyline", "Polygon", "G", "SvgText", "TransportCard", "ImageText", "Citation", "Disclosure", "Progress"])
        XCTAssertEqual(Set(library.specification.components.map(\.name)), expected)
        XCTAssertEqual(Set(library.components.library.components.map(\.name)), expected)
        for name in expected { XCTAssertNotNil(library.components.registry[name]) }
        XCTAssertNil(library.components.registry["SearchImage"])
        let exported = try LibrarySpec(jsonString: library.specificationJSON)
        XCTAssertEqual(exported.components.map(\.signature), library.specification.components.map(\.signature))
        XCTAssertTrue(library.systemPrompt.contains("Checkbox"))
        XCTAssertFalse(library.systemPrompt.contains("priceText?:"))
        XCTAssertTrue(library.systemPrompt.contains("visibleIds?: $binding<string[] | null>"))
        XCTAssertFalse(library.systemPrompt.contains("SearchImage("))
        XCTAssertTrue(library.systemPrompt.contains("Image(src: string, alt: string)"))
        XCTAssertFalse(library.systemPrompt.contains("aspectRatio?:"))
        XCTAssertFalse(library.systemPrompt.contains("This creates a progressive top-down reveal"))
        XCTAssertFalse(library.systemPrompt.contains("Data values — leaf content last"))
        XCTAssertFalse(library.systemPrompt.contains("does not guarantee visual top-down ordering"))
        XCTAssertTrue(library.systemPrompt.contains("source-ordered ready prefix"))
        XCTAssertTrue(try XCTUnwrap(library.components.library.components.first { $0.name == "Image" }).params.contains { $0.name == "aspectRatio" })
    }

    func testBindingsAndPositionalContracts() throws {
        let library = try IntelligentUILibrary()
        let checkbox = try XCTUnwrap(library.components.library.components.first { $0.name == "Checkbox" })
        XCTAssertEqual(checkbox.params.map(\.name), ["checked", "label", "lineThrough"])
        XCTAssertTrue(checkbox.params[0].isBindable)
        XCTAssertFalse(checkbox.params[1].isBindable)
        let button = try XCTUnwrap(library.components.library.components.first { $0.name == "Button" })
        XCTAssertEqual(button.params.map(\.name), ["label", "action", "variant", "color", "size", "icon", "disabled", "block"])
    }

    func testIndependentLibraryConstructionHasStableExport() throws {
        XCTAssertEqual(try IntelligentUILibrary().specificationJSON, try IntelligentUILibrary().specificationJSON)
    }

    @MainActor func testGenerationContractExamplesAndExplicitActionPolicy() throws {
        let library = try IntelligentUILibrary()
        XCTAssertFalse(library.systemPrompt.contains("Buttons without an action automatically send"))
        XCTAssertTrue(library.systemPrompt.contains("Buttons without an explicit action are disabled"))
        XCTAssertTrue(library.systemPrompt.contains("without a Markdown fence or a JSON wrapper"))
        for example in IntelligentUILibrary.generationExamples {
            let start = try XCTUnwrap(example.range(of: "root = Col("))
            let state = library.makeState()
            state.setSource(String(example[start.lowerBound...]))
            XCTAssertTrue(state.errors.isEmpty, "\(example): \(state.errors)")
            _ = try XCTUnwrap(state.root)
            XCTAssertEqual(library.validationIssues(in: state, source: String(example[start.lowerBound...])), [], example)
        }
    }

    @MainActor func testClockSortExampleSelectsRecordAndPreservesActionField() async throws {
        let library = try IntelligentUILibrary()
        let example = try XCTUnwrap(IntelligentUILibrary.generationExamples.first { $0.contains("Earliest record") })
        let start = try XCTUnwrap(example.range(of: "root = Col("))
        let program = String(example[start.lowerBound...])
        let state = library.makeState()
        state.setSource(program)
        XCTAssertTrue(library.validationIssues(in: state, source: program).isEmpty)
        let children = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertEqual(children.first(where: { $0.typeName == "Text" }).flatMap { PropValue.string($0, "text") }, "最早抵达：07:49")
        let button = try XCTUnwrap(children.first { $0.typeName == "Button" })
        let context = OpenUIComponentContext(element: button, registry: library.components.registry, state: state)
        var urls: [String] = []
        state.onAction = { event in
            if case .string(let url)? = event.params.first(where: { $0.0 == "url" })?.1 { urls.append(url.displayString) }
        }
        _ = await context.perform(try XCTUnwrap(context.action()))
        XCTAssertEqual(urls, ["https://example.com/journey?itemParams=BB%3D%3D&flag=1"])
    }

    @MainActor func testConsumerConfirmationExampleRetainsCardPriceAndDestination() throws {
        let library = try IntelligentUILibrary()
        let example = try XCTUnwrap(IntelligentUILibrary.generationExamples.first { $0.contains("Consumer confirmation") })
        let start = try XCTUnwrap(example.range(of: "root = Col("))
        let state = library.makeState(); state.setSource(String(example[start.lowerBound...]))
        func product() throws -> Value {
            let card = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first { $0.typeName == "ProductCard" })
            return try XCTUnwrap(PropValue.value(card, "product"))
        }
        let before = try product()
        state.setState("$confirmed", value: .boolean(true))
        let after = try product()
        for field in ["id", "price", "purchaseURL"] { XCTAssertEqual(ValueReading.field(before, field), ValueReading.field(after, field)) }
        XCTAssertTrue(PropValue.children(try XCTUnwrap(state.root)).contains { $0.typeName == "Checkbox" })
        XCTAssertTrue(library.validationIssues(in: try XCTUnwrap(state.root)).isEmpty)
    }
}
