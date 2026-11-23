import Foundation
import SwiftLang
import XCTest
@testable import OpenUIGallery

final class GalleryValidationTests: XCTestCase {
    func testStreamPartitionsPreserveExactUnicodeAndExerciseScalarBoundaries() {
        let source = "e\u{301}👩🏽‍💻中文" + String(repeating: #" \"quoted\" \uD83D\uDE80, [next] "#, count: 12)
        for partition in GalleryValidation.StreamPartition.allCases {
            let chunks = partition.chunks(source)
            XCTAssertGreaterThan(chunks.count, 1, partition.rawValue)
            XCTAssertFalse(chunks.contains(where: \.isEmpty), partition.rawValue)
            XCTAssertTrue(chunks.joined().utf8.elementsEqual(source.utf8), partition.rawValue)
        }
        let scalarChunks = GalleryValidation.StreamPartition.scalarPattern.chunks(source)
        XCTAssertEqual(scalarChunks.first, "e", "A transport boundary must be able to split a composed character")
        XCTAssertEqual(scalarChunks[1].unicodeScalars.first?.value, 0x301)
    }

    @MainActor func testBothLibrariesKeepFullContentBindingsActionsAndDefaultsAcrossPartitions() throws {
        for kind in GalleryLibrary.allCases {
            let library = try kind.makeLibrary()
            let source = program(for: kind)
            let expected = try snapshot(source, library: library)
            XCTAssertEqual(expected.state["$name"], .string("前半 e\u{301} 👩🏽‍💻 中文 \\ \"引用\" 🚀\n后半"))
            XCTAssertEqual(expected.state["$count"], .number(2))
            XCTAssertEqual(expected.state["$unused"], .string("unused"))
            for partition in GalleryValidation.StreamPartition.allCases {
                let actual = try snapshot(source, library: library, chunks: partition.chunks(source))
                XCTAssertTrue(GalleryValidation.terminalDifferences(actual, from: expected).isEmpty,
                              "\(kind.rawValue)/\(partition.rawValue): \(GalleryValidation.terminalDifferences(actual, from: expected))")
            }
            // Only this small mixed-Unicode program visits every scalar
            // boundary, including every character of the escaped surrogate pair.
            let scalarByScalar = try snapshot(source, library: library, chunks: source.unicodeScalars.map { String($0) })
            XCTAssertTrue(GalleryValidation.terminalDifferences(scalarByScalar, from: expected).isEmpty, kind.rawValue)
        }
    }

    @MainActor func testTerminalComparisonRejectsSilentContentBindingActionAndDefaultDrift() throws {
        for kind in GalleryLibrary.allCases {
            let library = try kind.makeLibrary()
            let source = program(for: kind)
            let expected = try snapshot(source, library: library)
            let field = kind == .openUI ? #"Input("name", "姓名", "text", null, $name)"# : #"Input($name, "姓名")"#
            let variants = [
                ("content", source.replacingOccurrences(of: "前半", with: "正文被替换")),
                ("binding", source.replacingOccurrences(of: field, with: field.replacingOccurrences(of: "$name", with: "$other"))),
                ("action", source.replacingOccurrences(of: "$count + 1", with: "$count + 2"))
            ]
            for (name, changed) in variants {
                XCTAssertNotEqual(changed, source, name)
                let actual = try snapshot(changed, library: library)
                XCTAssertTrue(GalleryValidation.terminalDifferences(actual, from: expected)
                    .contains(where: { $0.contains("root/content/props") }), "\(kind.rawValue)/\(name)")
            }
            let changedDefault = try snapshot(source.replacingOccurrences(of: #"$unused = "unused""#,
                with: #"$unused = "changed""#), library: library)
            XCTAssertEqual(changedDefault.root, expected.root, "An unused default must not require a visible tree change")
            XCTAssertTrue(GalleryValidation.terminalDifferences(changedDefault, from: expected)
                .contains(where: { $0.contains("state/defaults") && $0.contains("$unused") }), kind.rawValue)
        }
    }

    @MainActor func testTerminalComparisonIgnoresElementDeclarationIdentity() throws {
        for kind in GalleryLibrary.allCases {
            let library = try kind.makeLibrary()
            let container = kind == .openUI ? "Stack" : "Col"
            let text = kind == .openUI ? "TextContent" : "Text"
            let first = try snapshot("root = \(container)([first])\nfirst = \(text)(\"相同内容\")", library: library)
            let renamed = try snapshot("root = \(container)([renamed])\nrenamed = \(text)(\"相同内容\")", library: library)
            XCTAssertTrue(GalleryValidation.terminalDifferences(renamed, from: first).isEmpty, kind.rawValue)
        }
    }

    @MainActor func testTerminalComparisonRejectsInterruptedDocuments() throws {
        for kind in GalleryLibrary.allCases {
            let library = try kind.makeLibrary()
            let source = program(for: kind)
            let expected = try snapshot(source, library: library)
            let interrupted = library.makeState()
            defer { interrupted.reset() }
            var meta: ParseMeta?
            interrupted.onParseResult = { meta = $0.meta }
            interrupted.push(source)
            interrupted.interrupt()
            XCTAssertNotNil(interrupted.root)
            XCTAssertTrue(interrupted.isComplete)
            XCTAssertTrue(interrupted.isInterrupted)
            XCTAssertTrue(GalleryValidation.terminalDifferences(.init(interrupted, meta: meta), from: expected)
                .contains(where: { $0.contains("completion/interruption") }), kind.rawValue)
        }
    }

    private func program(for kind: GalleryLibrary) -> String {
        let container = kind == .openUI ? "Stack" : "Col"
        let text = kind == .openUI ? "TextContent" : "Text"
        let input = kind == .openUI ? #"Input("name", "姓名", "text", null, $name)"# : #"Input($name, "姓名")"#
        return """
        root = \(container)([\(input), \(text)($name), Button("下一步", @Set($count, $count + 1))])
        """ + "\n" + #"""
        $name = "前半 é 👩🏽‍💻 中文 \\ \"引用\" \uD83D\uDE80\n后半"
        $other = "前半 é 👩🏽‍💻 中文 \\ \"引用\" \uD83D\uDE80\n后半"
        $count = 2
        $unused = "unused"
        """#
    }

    @MainActor private func snapshot(_ source: String, library: OpenUILibrary, chunks: [String]? = nil,
                                    file: StaticString = #filePath, line: UInt = #line) throws -> GalleryValidation.TerminalSnapshot {
        let state = library.makeState()
        defer { state.reset() }
        var meta: ParseMeta?
        state.onParseResult = { meta = $0.meta }
        if let chunks {
            XCTAssertTrue(chunks.joined().utf8.elementsEqual(source.utf8), file: file, line: line)
            for chunk in chunks { state.push(chunk) }
            state.complete()
        } else { state.setSource(source) }
        XCTAssertNotNil(state.root, file: file, line: line)
        XCTAssertTrue(state.isComplete, file: file, line: line)
        XCTAssertFalse(state.isInterrupted, file: file, line: line)
        XCTAssertTrue(state.errors.isEmpty, state.errors.map(\.message).joined(separator: "; "), file: file, line: line)
        XCTAssertFalse(try XCTUnwrap(meta, file: file, line: line).incomplete, file: file, line: line)
        XCTAssertTrue(meta?.unresolved.isEmpty == true, file: file, line: line)
        return GalleryValidation.TerminalSnapshot(state, meta: meta)
    }
}
