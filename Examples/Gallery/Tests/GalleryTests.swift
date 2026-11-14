import Foundation
import OpenUICore
import OpenUILang
import SwiftUI
import XCTest
@testable import OpenUIGallery

#if os(macOS)
import AppKit
#endif

final class GalleryTests: XCTestCase {
    private func catalogData(programs: [String: String], duplicate: Bool = false) throws -> Data {
        let item: [String: Any] = ["id": "case", "title": "Case", "summary": "Summary", "category": "Test",
                                  "tags": [], "programs": programs]
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "cases": duplicate ? [item, item] : [item]])
    }

    func testCatalogRejectsMixedLibrariesEscapedPathsAndDuplicateIDs() throws {
        let valid = ["standard": "standard/case.openui", "intelligent": "intelligent/case.openui"]
        XCTAssertEqual(try GalleryCatalog.decode(catalogData(programs: valid), requiringBothLibraries: true).count, 1)
        XCTAssertThrowsError(try GalleryCatalog.decode(catalogData(programs: ["future": "future/case.openui"]), requiringBothLibraries: false))
        XCTAssertThrowsError(try GalleryCatalog.decode(catalogData(programs: ["standard": "standard/case.openui"]), requiringBothLibraries: true))
        XCTAssertThrowsError(try GalleryCatalog.decode(catalogData(programs: valid, duplicate: true), requiringBothLibraries: true))
        for path in ["../case.openui", "/case.openui", "standard/../case.openui", "standard\\case.openui"] {
            XCTAssertThrowsError(try GalleryCatalog.decode(catalogData(programs: ["standard": path]), requiringBothLibraries: false))
        }
    }

    func testExternalProgramRequiresExplicitLibraryAndValidViewport() throws {
        XCTAssertThrowsError(try GalleryOptions.parse(["--program", "example.openui"]))
        XCTAssertThrowsError(try GalleryOptions.parse(["--library", "unknown"]))
        XCTAssertThrowsError(try GalleryOptions.parse(["--unknown"]))
        XCTAssertThrowsError(try GalleryOptions.parse(["--stream-suffix", "tail.openui"]))
        XCTAssertThrowsError(try GalleryOptions.parse(["--zoom", "nan"]))
        XCTAssertThrowsError(try GalleryOptions.parse(["--width", "40"]))
        let options = try GalleryOptions.parse(["--program", "example.json", "--library", "standard", "--width", "768", "--height", "1024", "--zoom", "0.75"])
        XCTAssertEqual(options.library, .standard)
        XCTAssertEqual(options.width, 768)
        XCTAssertEqual(options.height, 1024)
        XCTAssertEqual(options.zoom, 0.75)
    }

    func testJSONImportChecksLibraryAndPreservesUTF8Source() throws {
        let source = #"root = Col([Text("原始内容 🧭")])"#
        let json = try JSONSerialization.data(withJSONObject: ["program": source, "library": "intelligent"])
        let text = try XCTUnwrap(String(data: json, encoding: .utf8))
        XCTAssertEqual(try GalleryImportedProgram.decode(text, isJSON: true, library: .intelligent), source)
        XCTAssertThrowsError(try GalleryImportedProgram.decode(text, isJSON: true, library: .standard))
        XCTAssertThrowsError(try GalleryImportedProgram.decode("{}", isJSON: true, library: .intelligent))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("record.txt")
        try json.write(to: file)
        XCTAssertEqual(try GalleryImportedProgram.read(url: file, library: .intelligent), source)
        try Data([0xff]).write(to: file)
        XCTAssertThrowsError(try GalleryImportedProgram.read(url: file, library: .intelligent))
    }

    @MainActor func testChangingCaseOrLibraryRetiresTheOldDocumentAndItsState() throws {
        let model = GalleryModel()
        XCTAssertNil(model.failure)
        let entries = model.entries.filter { $0.section == .cases }
        XCTAssertGreaterThan(entries.count, 1)
        model.select(entries[0].id)
        let first = try XCTUnwrap(model.session)
        first.state.setState("$gallerySentinel", value: .string("edited"))
        model.select(entries[1].id)
        let second = try XCTUnwrap(model.session)
        XCTAssertFalse(first.state === second.state)
        XCTAssertNil(first.state.root)
        XCTAssertNil(second.state.snapshotState()["$gallerySentinel"])
        model.selectLibrary(.standard)
        let standard = try XCTUnwrap(model.session)
        XCTAssertEqual(model.selectedID, entries[1].id)
        XCTAssertFalse(second.state === standard.state)
        XCTAssertNil(second.state.root)
        XCTAssertEqual(standard.kind, .standard)
        XCTAssertEqual(standard.state.root?.typeName, "Stack")
        standard.retire()
    }

    @MainActor func testPauseResumeAndRetirementDoNotAllowLateStreamingWrites() async throws {
        let source = "root = Col([Text(\"" + String(repeating: "流式文字", count: 100) + "\")])"
        let session = try GalleryDocumentSession(kind: .intelligent, source: source, title: "Stream")
        var updates = 0
        session.state.onParseResult = { _ in updates += 1 }
        session.stream(chunkSize: 24, intervalNanoseconds: 2_000_000)
        await eventually { updates >= 2 }
        session.pause()
        let pausedUpdates = updates
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(updates, pausedUpdates)
        XCTAssertEqual(session.playback, .paused)
        XCTAssertFalse(session.state.isComplete)
        session.resume(chunkSize: 80, intervalNanoseconds: 1_000_000)
        await eventually { session.playback == .complete }
        XCTAssertTrue(session.state.isComplete)
        XCTAssertTrue(session.state.errors.isEmpty)
        session.stream(chunkSize: 1, intervalNanoseconds: 2_000_000)
        await eventually { session.playback == .streaming }
        session.retire()
        let retiredUpdates = updates
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(updates, retiredUpdates)
        XCTAssertNil(session.state.root)
    }

    @MainActor func testSuffixRestoreInterruptAndCompleteAlwaysKeepTheWholeProgram() throws {
        let prefix = "root = Stack([TextContent(\"未闭合"
        let suffix = "字符串\")])"
        let whole = prefix + suffix
        let restored = try GalleryDocumentSession(kind: .standard, source: prefix, title: "Suffix", suffix: suffix)
        XCTAssertEqual(restored.draft, whole)
        XCTAssertFalse(restored.state.isComplete)
        restored.restore()
        XCTAssertTrue(restored.state.isComplete)
        XCTAssertTrue(restored.state.errors.isEmpty)
        XCTAssertEqual(restored.draft, whole)
        restored.retire()

        let interrupted = try GalleryDocumentSession(kind: .standard, source: prefix, title: "Suffix", suffix: suffix)
        interrupted.interrupt()
        XCTAssertTrue(interrupted.state.isInterrupted)
        XCTAssertNil(interrupted.pendingSuffix)
        XCTAssertEqual(interrupted.draft, whole)
        interrupted.render()
        XCTAssertFalse(interrupted.state.isInterrupted)
        XCTAssertTrue(interrupted.state.errors.isEmpty)
        interrupted.retire()

        let appended = try GalleryDocumentSession(kind: .standard, source: prefix, title: "Suffix", suffix: suffix)
        appended.appendSuffix()
        XCTAssertEqual(appended.draft, whole, "Appending the preview suffix must not duplicate it in the editor")
        XCTAssertTrue(appended.state.errors.isEmpty)
        appended.retire()
    }

    @MainActor func testRawStreamSuffixMayStartWithAnObjectLiteral() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("suffix.openui")
        let suffix = "{title: \"Lamp\"}]\nroot = Stack([TextContent(items[0].title)])"
        try suffix.write(to: url, atomically: true, encoding: .utf8)
        let raw = try GalleryImportedProgram.readRaw(url: url)
        XCTAssertEqual(raw, suffix)
        let session = try GalleryDocumentSession(kind: .standard, source: "items = [", title: "Raw suffix", suffix: raw)
        session.appendSuffix()
        XCTAssertTrue(session.state.errors.isEmpty)
        XCTAssertNotNil(session.state.root)
        session.retire()
    }

    @MainActor func testLocalQueryDiagnosticUpdatesItsDependentResultInBothLibraries() async throws {
        let catalog = try GalleryCatalog(resourceRoot: GalleryResources.root())
        let entry = try XCTUnwrap(catalog.entries.first { $0.item.id == "query-chain" })
        for kind in GalleryLibrary.allCases {
            let session = try GalleryDocumentSession(kind: kind, source: entry.source(for: kind), title: "Queries")
            await eventually { self.queryValue(session) == .number(1) }
            session.state.runQuery(statementId: "seed", tool: "gallery.seed", args: .object([]),
                                   defaults: .object([ObjectField(key: "value", value: .number(0))]))
            await eventually { self.queryValue(session) == .number(2) }
            XCTAssertTrue(session.state.errors.isEmpty)
            session.retire()
        }
    }

    func testBundledImageMatchesItsExactSourceAndFailureStaysLocal() async throws {
        let root = try GalleryResources.root()
        let loader = try GalleryImageLoader(resourceRoot: root)
        let request = try XCTUnwrap(loader.request(for: GalleryImageLoader.cameraURL, relativeTo: nil))
        let data = try await loader.data(for: request)
        XCTAssertEqual(data, try Data(contentsOf: root.appendingPathComponent("Images/nikon-front.jpg")))
        let missing = try XCTUnwrap(loader.request(for: "https://gallery.invalid/missing.jpg", relativeTo: nil))
        do { _ = try await loader.data(for: missing); XCTFail("The diagnostic request must fail locally") }
        catch { XCTAssertTrue(error is GalleryFailure) }
    }

    #if os(macOS)
    @MainActor func testNativePreviewResizingAndZoomingKeepEditedStateAndSourceRevision() throws {
        _ = NSApplication.shared
        let session = try GalleryDocumentSession(kind: .standard,
            source: "root = Stack([TextContent($value)])\n$value = \"original\"", title: "Viewport")
        session.state.setState("$value", value: .string("edited"))
        let revision = session.state.sourceRevision
        func preview(_ viewport: GalleryViewport) -> GalleryPreview {
            GalleryPreview(session: session, resources: .init(), viewport: viewport,
                           dynamicType: .large, locale: Locale(identifier: "en"), direction: .leftToRight)
        }
        let host = NSHostingView(rootView: preview(.init(width: 390, height: 844, zoom: 1)))
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 1000)
        host.layoutSubtreeIfNeeded()
        host.rootView = preview(.init(width: 768, height: 1024, zoom: 0.5))
        host.layoutSubtreeIfNeeded()
        host.rootView = preview(.init(width: 320, height: 568, zoom: 1.5))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(session.state.sourceRevision, revision)
        XCTAssertEqual(session.state.stateValue("$value"), .string("edited"))
        XCTAssertEqual(session.playback, .complete)
        session.retire()
    }
    #endif

    @MainActor private func queryValue(_ session: GalleryDocumentSession) -> Value? {
        guard case .object(let result) = session.state.queryStates["details"]?.data else { return nil }
        return result["value"]
    }

    @MainActor private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Gallery operation did not complete")
    }
}
