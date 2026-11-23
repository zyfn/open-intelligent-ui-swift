import XCTest
import SwiftUI
import SwiftLang
@testable import SwiftIntelligentUI

final class ComponentSelectionTests: XCTestCase {
    private let excluded: Set<String> = ["YouTube", "Timer"]

    @MainActor func testSelectedContractsStayInSyncWithoutChangingTheDefaultCatalog() throws {
        let full = try OpenIntelligentUIComponents()
        let selected = try OpenIntelligentUIComponents(excludingComponents: excluded)
        let expected = Set(full.specification.components.map(\.name)).subtracting(excluded)
        XCTAssertEqual(full.specification.components.count, 59)
        XCTAssertEqual(expected.count, 57)
        XCTAssertEqual(Set(selected.specification.components.map(\.name)), expected)
        XCTAssertEqual(Set(selected.manifest.components.map(\.name)), expected)
        XCTAssertEqual(Set(selected.components.library.components.map(\.name)), expected)
        XCTAssertEqual(selected.specification.functions.map(\.signature), full.specification.functions.map(\.signature))
        XCTAssertEqual(selected.specification.functions.count, 59)
        for name in excluded {
            XCTAssertNil(selected.components.registry[name])
            XCTAssertNotNil(selected.readerComponents.registry[name])
            XCTAssertFalse(selected.systemPrompt.contains(name))
            XCTAssertFalse(selected.specificationJSON.contains(name))
        }
        XCTAssertEqual(try OpenIntelligentUIComponents(excludingComponents: excluded).systemPrompt, selected.systemPrompt)
        XCTAssertNotNil(selected.components.registry["Map"])
        for example in selected.selectedGenerationExamples {
            let start = try XCTUnwrap(example.range(of: "root = Col("))
            let source = String(example[start.lowerBound...])
            let state = selected.makeState(); state.setSource(source)
            XCTAssertEqual(selected.validationIssues(in: state, source: source), [])
            XCTAssertEqual(selected.validationIssues(in: state, source: source, profile: .generation), [])
        }
    }

    @MainActor func testRemovedComponentsAreAbsentFromEveryCatalogAndPrompt() throws {
        let library = try OpenIntelligentUIComponents()
        for name in ["ImageText", "TransportCard"] {
            XCTAssertNil(library.components.registry[name])
            XCTAssertNil(library.readerComponents.registry[name])
            XCTAssertFalse(library.specificationJSON.contains(name))
            XCTAssertFalse(library.systemPrompt.contains(name))
        }
    }

    @MainActor func testSelectionRejectsUnknownNamesAndRootAndKeepsOptionalSearchIndependent() throws {
        XCTAssertThrowsError(try OpenIntelligentUIComponents(excludingComponents: ["Typo"]))
        XCTAssertThrowsError(try OpenIntelligentUIComponents(excludingComponents: ["Col"]))
        XCTAssertEqual(try OpenIntelligentUIComponents(excludingComponents: ["SearchImage"]).specification.components.count, 59)
        let service = OpenIntelligentUIImageSearch { _ in .init(url: "https://example.com/photo.jpg", alt: "来源") }
        XCTAssertEqual(try OpenIntelligentUIComponents(imageSearch: service, excludingComponents: excluded).specification.components.count, 58)
        XCTAssertEqual(try OpenIntelligentUIComponents(imageSearch: service, excludingComponents: excluded.union(["SearchImage"])).specification.components.count, 57)
    }
}
