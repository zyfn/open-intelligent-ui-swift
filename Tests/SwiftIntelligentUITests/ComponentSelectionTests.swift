import XCTest
import SwiftUI
import SwiftLang
@testable import SwiftIntelligentUI

final class ComponentSelectionTests: XCTestCase {
    private let excluded: Set<String> = ["ImageText", "YouTube", "Timer"]

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
        }
    }

    func testImageTextIsReaderOnlyByDefaultAndItsExplicitExclusionIsIdempotent() throws {
        let standard = try OpenIntelligentUIComponents()
        let explicit = try OpenIntelligentUIComponents(excludingComponents: ["ImageText"])
        let writer = Set(standard.specification.components.map(\.name))
        let reader = Set(standard.readerSpecification.components.map(\.name))
        XCTAssertEqual(reader.subtracting(writer), ["ImageText"])
        XCTAssertEqual(writer.subtracting(reader), [])
        XCTAssertNil(standard.components.registry["ImageText"])
        XCTAssertNotNil(standard.readerComponents.registry["ImageText"])
        XCTAssertFalse(standard.specificationJSON.contains("ImageText"))
        XCTAssertFalse(standard.systemPrompt.contains("ImageText"))
        XCTAssertEqual(explicit.specificationJSON, standard.specificationJSON)
        XCTAssertEqual(explicit.readerSpecification.jsonString(), standard.readerSpecification.jsonString())
        XCTAssertEqual(explicit.systemPrompt, standard.systemPrompt)
    }

    @MainActor func testExistingMessagesRemainReadableWithSelectedContracts() throws {
        let selected = try OpenIntelligentUIComponents(excludingComponents: excluded)
        let source = #"""
        root=Col([ImageText({title:"旧消息",subtitle:"原内容"}),Timer($seconds),YouTube("invalid"),Map([MapMarker("地点",30,120)])])
        $seconds=30
        """#
        XCTAssertTrue(selected.recognizesUI(in: #"root=ImageText({title:"旧消息"})"#))
        XCTAssertTrue(selected.recognizesUI(in: source))
        XCTAssertFalse(selected.recognizesUI(in: "这是一段普通 Markdown。"))
        let state = selected.makeState(); state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertEqual(selected.validationIssues(in: state, source: source), [])
        let root = try XCTUnwrap(state.root)
        XCTAssertEqual(PropValue.children(root).map(\.typeName), ["ImageText", "Timer", "YouTube", "Map"])
        #if os(macOS)
        let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: selected).frame(width: 320))
        XCTAssertNotNil(renderer.nsImage)
        #endif
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
