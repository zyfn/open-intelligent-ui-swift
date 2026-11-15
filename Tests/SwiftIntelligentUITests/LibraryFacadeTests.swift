import Foundation
@testable import SwiftIntelligentUI
import SwiftLang
import SwiftUI
import XCTest
#if os(macOS)
import AppKit
#endif

final class LibraryFacadeTests: XCTestCase {
    @MainActor func testExcludedWriterComponentsRemainReadableThroughTheUnifiedView() throws {
        let library = try OpenUILibrary.openIntelligentUI(excludingComponents: ["ImageText"])
        let original = try OpenIntelligentUIComponents(excludingComponents: ["ImageText"])
        XCTAssertEqual(library.specificationJSON, original.specificationJSON)
        XCTAssertEqual(library.readerSpecification.jsonString(), original.readerSpecification.jsonString())
        XCTAssertEqual(library.systemPrompt, original.systemPrompt)
        XCTAssertFalse(library.specification.components.contains { $0.name == "ImageText" })
        XCTAssertTrue(library.readerSpecification.components.contains { $0.name == "ImageText" })

        let source = #"root = Col([ImageText({title: "Archived title", subtitle: "Stored content"})])"#
        XCTAssertTrue(library.recognizesUI(in: source))
        XCTAssertFalse(library.recognizesUI(in: "An ordinary paragraph without a UI program."))
        let state = library.makeState()
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertEqual(PropValue.children(try XCTUnwrap(state.root)).map(\.typeName), ["ImageText"])

        #if os(macOS)
        _ = NSApplication.shared
        let unified = ImageRenderer(content: OpenUIView(state: state, library: library).frame(width: 320))
        let legacy = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: original).frame(width: 320))
        let image = try XCTUnwrap(unified.nsImage)
        let reference = try XCTUnwrap(legacy.nsImage)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertEqual(image.size, reference.size)
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
