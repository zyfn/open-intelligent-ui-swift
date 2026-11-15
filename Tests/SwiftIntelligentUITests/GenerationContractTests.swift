import XCTest
import SwiftLang
@testable import SwiftIntelligentUI

final class GenerationContractTests: XCTestCase {
    @MainActor func testWriterSignaturesAndSchemaHaveOneSourceWhileReaderRetainsLegacyFields() throws {
        let service = OpenIntelligentUIImageSearch { _ in .init(url: "https://example.invalid/image.jpg", alt: "Image") }
        let library = try OpenIntelligentUIComponents(imageSearch: service)
        let writer = library.components.library.components
        let reader = library.readerComponents.library.components
        XCTAssertEqual(writer.count, 61)
        XCTAssertEqual(reader.count, 61)
        XCTAssertEqual(writer.first { $0.name == "Image" }?.params.map(\.name), ["src", "alt"])
        XCTAssertEqual(reader.first { $0.name == "Image" }?.params.map(\.name), ["src", "alt", "aspectRatio", "radius", "fit"])
        XCTAssertEqual(writer.first { $0.name == "SearchImage" }?.params.map(\.name), ["query"])
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
        XCTAssertTrue(generated.contains { $0.contains("aspectRatio") })
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

