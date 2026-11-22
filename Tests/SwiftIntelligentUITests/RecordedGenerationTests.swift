import XCTest
import Foundation
import SwiftLang
import SwiftIntelligentUI

final class RecordedGenerationTests: XCTestCase {
    @MainActor func testRecordedModelProgramsRemainExecutable() throws {
        let library = try OpenIntelligentUIComponents()
        for name in ["reading", "budget", "comparison", "editorial", "transport", "shopping"] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json",
                                                     subdirectory: "Fixtures/GeneratedPrograms"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String])
            let state = library.makeState()
            state.setSource(try XCTUnwrap(object["program"]))
            XCTAssertTrue(state.errors.isEmpty, "\(name): \(state.errors)")
            XCTAssertNotNil(state.root, name)
            XCTAssertTrue(library.validationIssues(in: try XCTUnwrap(state.root)).isEmpty, name)
            if name == "editorial" {
                let issues = library.validationIssues(in: try XCTUnwrap(state.root), profile: .generation)
                XCTAssertEqual(issues, [
                    "root.Col.children[1].ImageText: component is not available in this validation profile",
                    "root.Col.children[2].ImageText: component is not available in this validation profile"
                ])
            }
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
