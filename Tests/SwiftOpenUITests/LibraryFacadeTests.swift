import SwiftLang
@testable import SwiftOpenUI
import SwiftUI
import XCTest
#if os(macOS)
import AppKit
#endif

final class LibraryFacadeTests: XCTestCase {
    func testStandardFacadePreservesThePublishedContractAndPrompt() throws {
        let library = try OpenUILibrary.openUI(id: "consumer.standard")
        let original = try OpenUIComponents.library(id: "consumer.standard")
        let specification = original.toSpec().jsonString()
        XCTAssertEqual(library.specification.jsonString(), specification)
        XCTAssertEqual(library.specificationJSON, specification)
        XCTAssertEqual(library.readerSpecification.jsonString(), specification)
        XCTAssertEqual(library.systemPrompt, original.prompt(OpenUIComponents.promptOptions))
        XCTAssertTrue(library.recognizesUI(in: #"root = Stack([TextContent("Ready")])"#))
        XCTAssertFalse(library.recognizesUI(in: "An ordinary paragraph without a UI program."))
    }

    @MainActor func testStandardFacadeStreamsRestoredStateAndUsesTheNativeRenderer() throws {
        let library = try OpenUILibrary.openUI()
        let persisted: [String: Value] = ["$label": .string("restored")]
        let state = library.makeState(persistedState: persisted)
        state.push("$label = \"default\"\nroot = Stack([TextContent(")
        state.push("$label)])")
        state.complete()
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertEqual(PropValue.string(try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first), "text"), "restored")
        state.setState("$label", value: .string("updated"))
        XCTAssertEqual(PropValue.string(try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first), "text"), "updated")

        #if os(macOS)
        _ = NSApplication.shared
        let original = try OpenUIComponents.library()
        let unified = ImageRenderer(content: OpenUIView(state: state, library: library).frame(width: 320))
        let legacy = ImageRenderer(content: OpenUIContentView(state: state, registry: original.registry).frame(width: 320))
        let image = try XCTUnwrap(unified.nsImage)
        let reference = try XCTUnwrap(legacy.nsImage)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertEqual(image.size, reference.size)
        #endif
    }
}
