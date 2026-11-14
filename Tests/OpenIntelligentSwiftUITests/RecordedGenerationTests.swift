import XCTest
import Foundation
import OpenUILang
import OpenUICore
import OpenIntelligentSwiftUI

final class RecordedGenerationTests: XCTestCase {
    @MainActor func testRecordedModelProgramsRemainExecutable() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let library = try IntelligentUILibrary()
        for name in ["reading", "budget", "comparison", "editorial", "transport", "shopping"] {
            let url = root.appendingPathComponent("Benchmarks/Recorded/" + name + ".json")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String])
            let state = library.makeState()
            state.setSource(try XCTUnwrap(object["program"]))
            XCTAssertTrue(state.errors.isEmpty, "\(name): \(state.errors)")
            XCTAssertNotNil(state.root, name)
            XCTAssertTrue(library.validationIssues(in: try XCTUnwrap(state.root)).isEmpty, name)
            if name == "budget" {
                state.setState("$total", value: .number(90))
                let text = strings(.element(try XCTUnwrap(state.root))).joined(separator: " ")
                XCTAssertTrue(text.contains("30 / 30 / 30"))
            }
        }
    }
    private func strings(_ value: Value) -> [String] {
        switch value {
        case .string(let s): return [s.displayString]
        case .element(let e): return e.props.flatMap { strings($0.1) }
        case .array(let a): return a.flatMap(strings)
        default: return []
        }
    }
}
