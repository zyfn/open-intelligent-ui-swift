import XCTest
@testable import SwiftLang

final class NativeValidationBridgeTests: XCTestCase {
    func testInheritedRuleNamesAreUnknownAndDoNotSkipFollowingRules() {
        for name in ["valueOf", "toString", "constructor", "__proto__", "hasOwnProperty"] {
            let unknown = ParsedRule(type: name)
            XCTAssertNil(validate(.string("data"), rules: [unknown]), name)
            XCTAssertEqual(validate(.string(""), rules: [unknown, ParsedRule(type: "required")]),
                "This field is required", name)
        }
    }

    func testExplicitCustomValidatorWithInheritedNameStillRuns() {
        XCTAssertEqual(validate(.string("data"), rules: [ParsedRule(type: "valueOf")],
            customValidators: ["valueOf": { _, _ in "Custom rule failed" }]), "Custom rule failed")
        XCTAssertNil(validate(.string("data"), rules: [ParsedRule(type: "email")],
            customValidators: ["email": { _, _ in nil }]))
    }

    func testValueConversionExceptionBecomesValidationFailureAndRealmRecovers() {
        let value = Value.object([.init(key: "toString", value: .number(1)), .init(key: "valueOf", value: .number(2))])
        XCTAssertEqual(validate(value, rules: [ParsedRule(type: "min", arg: .number(0))]),
            "Validation could not complete: invalid rule or value.")
        XCTAssertEqual(validate(.string(""), rules: [ParsedRule(type: "required")]), "This field is required")
        XCTAssertNil(validate(.string("ok"), rules: [ParsedRule(type: "required")]))
    }
}
