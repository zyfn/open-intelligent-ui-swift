import Dispatch
import Foundation
import SwiftLang
@testable import SwiftOpenUI
import SwiftUI
import XCTest
#if os(macOS)
import AppKit
#endif

final class LibraryFacadeTests: XCTestCase {
    @MainActor func testRepeatedDocumentCreationPreservesIndependentStateAndRecordsPreparationCost() throws {
        let components = try OpenUIComponents.library()
        let preparationStart = DispatchTime.now().uptimeNanoseconds
        let library = OpenUILibrary(components: components)
        let preparationMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - preparationStart) / 1_000_000
        let firstDocumentStart = DispatchTime.now().uptimeNanoseconds
        let firstDocument = library.makeState()
        let firstDocumentMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - firstDocumentStart) / 1_000_000
        let iterations = 12
        var preparedSamples: [Double] = [], rebuiltSamples: [Double] = []
        let source = "$label=\"default\"\nroot=Stack([TextContent($label)])"
        firstDocument.setSource(source)
        XCTAssertTrue(firstDocument.errors.isEmpty, "\(firstDocument.errors)")

        // Compare the real facade with its previous preparation path in the
        // same process. Timing ends before parsing; no view is mounted here.
        func create(recompile: Bool, record: Bool) {
            autoreleasepool {
                let start = DispatchTime.now().uptimeNanoseconds
                let state = recompile
                    ? OpenUIState(schema: components.library.toSchema(), functions: components.library.customFunctions())
                    : OpenUILibrary(components: components).makeState()
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                if record {
                    if recompile { rebuiltSamples.append(elapsed) } else { preparedSamples.append(elapsed) }
                }
                state.setSource(source)
                XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
                XCTAssertEqual(state.stateValue("$label"), .string("default"))
                state.setState("$label", value: .string("edited"))
                XCTAssertEqual(state.stateValue("$label"), .string("edited"))
            }
        }
        for _ in 0..<2 {
            create(recompile: true, record: false)
            create(recompile: false, record: false)
        }
        for index in 0..<iterations {
            create(recompile: index.isMultiple(of: 2), record: true)
            create(recompile: !index.isMultiple(of: 2), record: true)
        }
        func statistics(_ values: [Double]) -> [String: Double] {
            let ordered = values.sorted()
            return ["p50Milliseconds": ordered[(ordered.count - 1) / 2],
                    "p95Milliseconds": ordered[Int(ceil(Double(ordered.count) * 0.95)) - 1],
                    "maxMilliseconds": ordered.last!]
        }
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let report: [String: Any] = [
            "workload": "standard OpenUI catalog, repeated independent document creation",
            "configuration": configuration, "iterationsPerPath": iterations,
            "componentDefinitions": components.library.components.count,
            "facadePreparationMilliseconds": preparationMilliseconds,
            "firstDocumentIncludingReaderPreparationMilliseconds": firstDocumentMilliseconds,
            "preparedReader": statistics(preparedSamples), "recompiledReader": statistics(rebuiltSamples),
            "limits": "Same-process preparation comparison, not App loading time, scrolling or frame rate."
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if let directory = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"] {
            let output = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try data.write(to: output.appendingPathComponent("library-document-creation-\(configuration).json"))
        }
    }

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
