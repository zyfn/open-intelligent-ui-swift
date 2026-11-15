import XCTest
@testable import SwiftLang

final class PreparedLibraryTests: XCTestCase {
    private func library() throws -> Library {
        try createLibrary(components: [defineComponent(name: "Text", description: "",
            params: [ParamDef(name: "text", required: true)])], root: "Text")
    }
    func testPreparedLibraryIsReusedAcrossImmutableSchemaCopies() throws {
        let core = SharedCore.shared
        let original = try library().toSchema()
        core.sync {
            let first = core.library(original), copy = original
            XCTAssertTrue(core.library(copy) === first)
            for _ in 0..<20 { XCTAssertTrue(core.library(original) === first) }
        }
        let independent = try library().toSchema()
        core.sync { XCTAssertFalse(core.library(independent) === core.library(original)) }
    }
    func testOfficialExtensionCreatesANewSnapshotWithoutChangingOriginal() throws {
        let core = SharedCore.shared, base = try library()
        let original = base.toSchema()
        let extended = try base.extend(LibraryExtension(addComponents: [
            defineComponent(name: "Extra", description: "", params: [ParamDef(name: "value", required: true)])
        ])).toSchema()
        core.sync {
            let first = core.library(original)
            XCTAssertFalse(core.library(extended) === first)
            XCTAssertTrue(core.library(original) === first)
        }
        XCTAssertNil(original.components["Extra"])
        XCTAssertNotNil(extended.components["Extra"])
        XCTAssertEqual(createParser(schema: extended).parse("root=Extra(7)").root?.typeName, "Extra")
    }
}
