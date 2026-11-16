import XCTest
@testable import SwiftLang

final class OrderedObjectFieldsTests: XCTestCase {
    func testDuplicateWritesPreserveFirstPositionAndExactCodeUnitKeys() {
        let high = OpenUIString(codeUnits: [0xD800])
        let replacement = OpenUIString(codeUnits: [0xFFFD])
        let keys: [OpenUIString] = ["tail", "10", "2", "01", "4294967295", "0", "-0",
                                    "4294967294", "é", "e\u{301}", high, replacement, "tail", "2", high]
        let fields = keys.enumerated().map { ObjectField(key: $0.element, value: .number(Double($0.offset))) }
        let actual = OpenUIObject(fields)
        XCTAssertEqual(actual.map(\.key), ["0", "2", "10", "4294967294", "tail", "01", "4294967295",
                                           "-0", "é", "e\u{301}", high, replacement])
        XCTAssertEqual(actual["tail"], .number(12))
        XCTAssertEqual(actual["2"], .number(13))
        XCTAssertEqual(actual[high], .number(14))
        XCTAssertEqual(actual["é"], .number(8))
        XCTAssertEqual(actual["e\u{301}"], .number(9))
        XCTAssertEqual(actual[replacement], .number(11))
    }

    func testMixedKeyEnumerationMatchesJavaScriptOwnProperties() {
        var fields = (0..<300).map {
            ObjectField(key: OpenUIString($0.isMultiple(of: 3) ? String(300 - $0) : "field\($0)"),
                        value: .number(Double($0)))
        }
        fields += [ObjectField(key: "constructor", value: .number(1)),
                   ObjectField(key: "__proto__", value: .number(2)),
                   ObjectField(key: "field1", value: .number(999)),
                   ObjectField(key: "300", value: .number(1000)),
                   ObjectField(key: OpenUIString(codeUnits: [0xD800]), value: .number(3))]
        // Define raw own properties directly in JS, bypassing OpenUIObject's
        // ordering implementation, and read the engine's enumeration order.
        let core = SharedCore.shared
        let expected = core.sync {
            let object = core.object(fields.map { ($0.key, core.encode($0.value)) })
            return core.entries(object).map { ObjectField(key: $0.0, value: core.decode($0.1)) }
        }
        XCTAssertEqual(OpenUIObject(fields).fields, expected)
    }

    func testLargeToolObjectRetainsAllFieldsAndLastWrite() {
        let count = 20_000
        var fields = (0..<count).map { ObjectField(key: "field\($0)", value: .number(Double($0))) }
        fields.append(ObjectField(key: "field0", value: .string("last")))
        let object = OpenUIObject(fields)
        XCTAssertEqual(object.count, count)
        XCTAssertEqual(object.first?.key, "field0")
        XCTAssertEqual(object.first?.value, .string("last"))
        XCTAssertEqual(object.last?.key, OpenUIString("field\(count - 1)"))
        XCTAssertEqual(object.last?.value, .number(Double(count - 1)))
    }
}
