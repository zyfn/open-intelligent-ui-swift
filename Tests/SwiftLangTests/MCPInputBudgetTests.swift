import XCTest
@testable import SwiftLang

final class MCPInputBudgetTests: XCTestCase {
    private func expectBudgetRejection(_ input: JSONValue,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try extractToolResult(input), file: file, line: line) { error in
            XCTAssertEqual((error as? MCPToolError)?.toolErrorText,
                OpenUIString(runtimeBudgetError().message), file: file, line: line)
        }
    }

    func testDeepStructuredInputIsRejectedBeforeNativeProjection() {
        var value = JSONValue.number(1)
        for _ in 0..<300 { value = .array([value]) }
        expectBudgetRejection(.object([.init(key: "structuredContent", value: value)]))
    }

    func testWideAndLongStructuredInputsAreRejected() {
        expectBudgetRejection(.object([.init(key: "structuredContent",
            value: .array(Array(repeating: .number(0), count: 100_000)))]))
        expectBudgetRejection(.object([.init(key: "structuredContent",
            value: .string(OpenUIString(String(repeating: "x", count: OpenUIRuntimeBudget.maximumSourceUTF16 + 1))))]))
    }

    func testSmallTextEnvelopeCannotExpandIntoAnOversizedValue() {
        let deep = String(repeating: "[", count: 257) + "0" + String(repeating: "]", count: 257)
        let wide = "[" + Array(repeating: "0", count: 100_000).joined(separator: ",") + "]"
        for text in [deep, wide] {
            expectBudgetRejection(.object([.init(key: "content", value: .array([
                .object([.init(key: "type", value: .string("text")),
                         .init(key: "text", value: .string(OpenUIString(text)))])
            ]))]))
        }
    }

    func testMaximumDepthPreservesTheAcceptedScalar() throws {
        let cases: [(String, Value)] = [("42", .number(42)), ("true", .boolean(true)),
                                        ("\"kept\"", .string("kept")), ("null", .null)]
        for (leaf, expected) in cases {
            let text = String(repeating: "[", count: NativeValueCost.maximumDepth)
                + leaf + String(repeating: "]", count: NativeValueCost.maximumDepth)
            var value = try extractToolResult(.object([.init(key: "content", value: .array([
                .object([.init(key: "type", value: .string("text")),
                         .init(key: "text", value: .string(OpenUIString(text)))])
            ]))]))
            for _ in 0..<NativeValueCost.maximumDepth {
                guard case .array(let children) = value, children.count == 1 else {
                    XCTFail("Accepted MCP data must preserve every container and scalar")
                    return
                }
                value = children[0]
            }
            XCTAssertEqual(value, expected)
        }
    }

    func testOrdinaryStructuredAndTextResultsRemainUnchangedAfterRejection() throws {
        expectBudgetRejection(.array(Array(repeating: .null, count: 100_000)))
        XCTAssertEqual(try extractToolResult(.object([
            .init(key: "structuredContent", value: .number(0)),
            .init(key: "content", value: .array([]))
        ])), .number(0))
        let text = try parseJSONPreservingOrder(#"{"content":[{"type":"text","text":"{\"a\":"},{"type":"text","text":"1}"}]}"#)
        XCTAssertEqual(try extractToolResult(text), .object([.init(key: "a", value: .number(1))]))
        let error = try parseJSONPreservingOrder(#"{"isError":true,"content":[{"type":"text","text":"provider failed"}]}"#)
        XCTAssertThrowsError(try extractToolResult(error)) {
            XCTAssertEqual(($0 as? MCPToolError)?.toolErrorText, "provider failed")
        }
    }
}
