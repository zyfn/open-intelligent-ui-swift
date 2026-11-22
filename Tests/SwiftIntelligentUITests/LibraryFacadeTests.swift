import Foundation
@testable import SwiftIntelligentUI
import SwiftLang
import SwiftUI
import XCTest
#if os(macOS)
import AppKit
#endif

final class LibraryFacadeTests: XCTestCase {
    @MainActor func testRemovedComponentsAreAbsentFromFacadeContracts() throws {
        let library = try OpenUILibrary.openIntelligentUI()
        for name in ["ImageText", "TransportCard"] {
            XCTAssertFalse(library.specification.components.contains { $0.name == name })
            XCTAssertFalse(library.readerSpecification.components.contains { $0.name == name })
            XCTAssertFalse(library.systemPrompt.contains(name))
            XCTAssertFalse(library.specificationJSON.contains(name))
        }
    }

    @MainActor func testFacadeRendersAtomicImageAndTextAndJourneyLineComposition() throws {
        let library = try OpenUILibrary.openIntelligentUI()
        let source = #"root = Col([Row([Image("https://example.com/photo.jpg", "建筑"), Col([Title("建筑观察"), Text("观察建筑形制")])]), Row([Col([Text("08:30"), Text("北京南站")]), JourneyLine("train"), Col([Text("13:15"), Text("上海虹桥站")])])])"#
        let state = library.makeState()
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertTrue(library.recognizesUI(in: source))
        XCTAssertEqual(try OpenIntelligentUIComponents().validationIssues(in: state, source: source), [])
        XCTAssertEqual(PropValue.children(try XCTUnwrap(state.root)).map(\.typeName), ["Row", "Row"])
        #if os(macOS)
        _ = NSApplication.shared
        let image = ImageRenderer(content: OpenUIView(state: state, library: library).frame(width: 320))
        XCTAssertGreaterThan(try XCTUnwrap(image.nsImage).size.height, 0)
        #endif
    }

    @MainActor func testIntelligentFunctionsRetainReferenceDateAndReactiveBindings() throws {
        let library = try OpenUILibrary.openIntelligentUI(referenceDate: Date(timeIntervalSince1970: 0))
        let persisted: [String: Value] = ["$total": .number(90)]
        let state = library.makeState(persistedState: persisted)
        state.setSource("""
            root = Col([Input($total, "Amount", "number"), Text(@Join(@Allocate($total, [1,1,1]), " / ")), Text(@Now())])
            $total = 100
            """)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertEqual(children.count, 3)
        let input = try XCTUnwrap(children.first)
        let amount = try XCTUnwrap(children.dropFirst().first)
        let date = try XCTUnwrap(children.dropFirst(2).first)
        let binding = try XCTUnwrap(state.binding(for: input, prop: "value"))
        XCTAssertEqual(binding.wrappedValue, .number(90))
        XCTAssertEqual(PropValue.string(amount, "text"), "30 / 30 / 30")
        XCTAssertEqual(PropValue.string(date, "text"), "1970-01-01T00:00:00.000Z")

        binding.wrappedValue = .number(120)
        XCTAssertEqual(state.stateValue("$total"), .number(120))
        let updated = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertEqual(PropValue.string(try XCTUnwrap(updated.dropFirst().first), "text"), "40 / 40 / 40")
    }
}
