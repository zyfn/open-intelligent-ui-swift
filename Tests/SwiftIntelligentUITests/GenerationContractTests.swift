import XCTest
import SwiftLang
@testable import SwiftIntelligentUI

final class GenerationContractTests: XCTestCase {
    @MainActor func testWriterSignaturesAndSchemaHaveOneSourceWhileReaderRetainsLegacyFields() throws {
        let service = OpenIntelligentUIImageSearch { _ in .init(url: "https://example.invalid/image.jpg", alt: "Image") }
        let library = try OpenIntelligentUIComponents(imageSearch: service)
        let writer = library.components.library.components
        let reader = library.readerComponents.library.components
        XCTAssertEqual(writer.count, 60)
        XCTAssertEqual(reader.count, 61)
        XCTAssertEqual(Set(reader.map(\.name)).subtracting(writer.map(\.name)), ["ImageText"])
        XCTAssertEqual(writer.first { $0.name == "Image" }?.params.map(\.name), ["src", "alt", "aspectRatio", "radius", "fit"])
        XCTAssertEqual(reader.first { $0.name == "Image" }?.params.map(\.name), ["src", "alt", "aspectRatio", "radius", "fit"])
        XCTAssertEqual(writer.first { $0.name == "SearchImage" }?.params.map(\.name), ["query", "aspectRatio", "radius", "fit"])
        for components in [reader, writer] {
            XCTAssertEqual(components.first { $0.name == "Map" }?.params.map(\.name), ["markers", "route", "selected", "height"])
            XCTAssertEqual(components.first { $0.name == "MapMarker" }?.params.map(\.name), ["label", "lat", "lng", "category", "icon"])
        }
        XCTAssertGreaterThan(try XCTUnwrap(reader.first { $0.name == "SearchImage" }).params.count, 1)
        for entry in library.specification.components {
            XCTAssertTrue(library.systemPrompt.contains(entry.signature), entry.name)
        }
        XCTAssertFalse(library.specification.components.first { $0.name == "ProductCard" }!.signature.contains("priceText"))
        XCTAssertTrue(library.readerSpecification.components.first { $0.name == "ProductCard" }!.signature.contains("priceText"))
        XCTAssertEqual(library.manifest.components.map(\.name), library.specification.components.map(\.name))
    }

    @MainActor func testImageTextHistoryDoesNotBecomeNewGeneration() throws {
        let library = try OpenIntelligentUIComponents()
        let source = #"root=Col([ImageText({title:"旧消息",body:"历史图文内容"})])"#
        let state = library.makeState()
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertTrue(library.recognizesUI(in: source))
        XCTAssertEqual(library.validationIssues(in: state, source: source, profile: .historical), [])
        XCTAssertEqual(library.validationIssues(in: state, source: source, profile: .generation), [
            "root.Col.children[0].ImageText: component is not available in this validation profile"
        ])
    }

    @MainActor func testPrimitiveExamplesUseDefaultMediaLayoutAndOrdinaryChildren() throws {
        let library = try OpenIntelligentUIComponents()
        func example(_ title: String) throws -> EvaluatedElement {
            let text = try XCTUnwrap(library.selectedGenerationExamples.first { $0.hasPrefix(title) })
            let start = try XCTUnwrap(text.range(of: "root = Col("))
            let source = String(text[start.lowerBound...])
            let state = library.makeState()
            state.setSource(source)
            XCTAssertEqual(library.validationIssues(in: state, source: source, profile: .generation), [], title)
            return try XCTUnwrap(state.root)
        }

        let mediaRoot = try example("Photo beside reading content")
        let row = try XCTUnwrap(PropValue.children(mediaRoot).first)
        XCTAssertEqual(row.typeName, "Row")
        XCTAssertNil(PropValue.string(row, "align"))
        XCTAssertNil(ValueReading.number(PropValue.value(row, "gap")))
        let children = PropValue.children(row)
        XCTAssertEqual(children.map(\.typeName), ["Image", "Col"])
        let image = try XCTUnwrap(children.first)
        XCTAssertEqual(PropValue.string(image, "src"), "https://example.com/detail.jpg")
        XCTAssertEqual(PropValue.string(image, "alt"), "建筑细节")
        XCTAssertNil(ValueReading.number(PropValue.value(image, "aspectRatio")))
        XCTAssertEqual(PropValue.children(try XCTUnwrap(children.last)).map(\.typeName), ["Title", "Text"])

        let gridRoot = try example("Equal columns")
        let grid = try XCTUnwrap(PropValue.children(gridRoot).first { $0.typeName == "Grid" })
        XCTAssertEqual(PropValue.children(grid).map(\.typeName), ["Col", "Col"])
        XCTAssertEqual(PropValue.value(grid, "columns"), .number(2))
        XCTAssertEqual(PropValue.value(grid, "minChildWidth"), .number(160))
        XCTAssertEqual(PropValue.children(gridRoot).filter { $0.typeName == "Card" }.count, 1)

        let carouselRoot = try example("Horizontal browsing")
        let carousel = try XCTUnwrap(PropValue.children(carouselRoot).first { $0.typeName == "Carousel" })
        XCTAssertEqual(PropValue.children(carousel).map(\.typeName), ["Col", "Col"])
        XCTAssertEqual(PropValue.value(carousel, "itemWidth"), .number(240))
    }

    func testPrimitiveExamplesFollowSelectedComponentDependencies() throws {
        let library = try OpenIntelligentUIComponents(excludingComponents: ["Box", "Grid", "Carousel"])
        XCTAssertTrue(library.selectedGenerationExamples.contains { $0.hasPrefix("Editorial cover") })
        XCTAssertTrue(library.selectedGenerationExamples.contains { $0.hasPrefix("Photo beside reading content") })
        XCTAssertTrue(library.selectedGenerationRules.contains { $0.hasPrefix("For a photo beside text") })
        XCTAssertFalse(library.selectedGenerationExamples.contains { $0.hasPrefix("Equal columns") })
        XCTAssertFalse(library.selectedGenerationExamples.contains { $0.hasPrefix("Horizontal browsing") })
        XCTAssertFalse(library.selectedGenerationRules.contains { $0.hasPrefix("Box supplies") })
        XCTAssertFalse(library.selectedGenerationRules.contains { $0.hasPrefix("Grid arranges") })
        let withoutRow = try OpenIntelligentUIComponents(excludingComponents: ["Row"])
        XCTAssertFalse(withoutRow.selectedGenerationExamples.contains { $0.hasPrefix("Photo beside reading content") })
        XCTAssertFalse(withoutRow.selectedGenerationRules.contains { $0.hasPrefix("For a photo beside text") })
        XCTAssertTrue(withoutRow.selectedGenerationRules.contains { $0.hasPrefix("Box supplies") })
    }

    func testExclusionDoesNotDeleteUnrelatedActionsOrSourceFidelityRules() throws {
        let library = try OpenIntelligentUIComponents(excludingComponents: ["Pressable", "ProductCard", "Image"])
        XCTAssertFalse(library.systemPrompt.contains("Pressable"))
        XCTAssertTrue(library.systemPrompt.contains("Every enabled Button needs an explicit action"))
        XCTAssertTrue(library.systemPrompt.contains("Every enabled IconButton needs an explicit action"))
        XCTAssertTrue(library.systemPrompt.contains("ToAssistant is allowed only"))
        XCTAssertTrue(library.systemPrompt.contains("Never normalize, shorten, decode, repair or remove parts"))
        XCTAssertTrue(library.systemPrompt.contains("Use TransportCard for transport"))
        XCTAssertFalse(library.selectedGenerationRules.contains { $0.contains("ProductCard") })
        XCTAssertFalse(library.selectedGenerationExamples.contains { $0.contains("Image(") })
    }

    @MainActor func testGenerationAndHistoryAreSeparateWithoutChangingParsing() throws {
        let library = try OpenIntelligentUIComponents(excludingComponents: ["Timer"])
        let source = #"root=Col([Image("photo","Image",1.5),Timer($seconds),ProductCard({id:"p",title:"Item",images:[],priceText:"¥12"})])"# + "\n$seconds=10"
        let state = library.makeState()
        state.setSource(source)
        let root = try XCTUnwrap(state.root)
        XCTAssertEqual(library.validationIssues(in: root, profile: .historical), [])
        let generated = library.validationIssues(in: root, profile: .generation)
        XCTAssertFalse(generated.contains { $0.contains("aspectRatio") })
        XCTAssertTrue(generated.contains { $0.contains("Timer") && $0.contains("not available") })
        XCTAssertTrue(generated.contains { $0.contains("priceText") })
        XCTAssertTrue(library.recognizesUI(in: source))
    }

    @MainActor func testOmittedReaderCompatibilityFieldsDoNotInvalidateNewOutput() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        let source = #"root=Col([Image("photo","Image"),Text("Body")])"#
        state.setSource(source)
        XCTAssertEqual(library.validationIssues(in: state, source: source, profile: .generation), [])
    }
}

