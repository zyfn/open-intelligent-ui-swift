import XCTest
@testable import OpenIntelligentSwiftUI

final class LocalizationTests: XCTestCase {
    func testHostLocaleSelectsPackageCopyInsteadOfProcessLanguage() {
        XCTAssertEqual(SDKStrings.text("common.done", locale: Locale(identifier: "en_US")), "Done")
        XCTAssertEqual(SDKStrings.text("common.done", locale: Locale(identifier: "zh_Hans_CN")), "完成")
        XCTAssertEqual(SDKStrings.text("common.done", locale: Locale(identifier: "ar_SA")), "تم")
        XCTAssertEqual(SDKStrings.text("common.done", locale: Locale(identifier: "fr_FR")), "Done")
    }

    func testSourceTextIsInsertedVerbatimRatherThanLocalized() {
        let source = "Café ¥100 https://example.invalid/a%2Fb?token=abc"
        XCTAssertEqual(SDKStrings.text("citation.openOne", locale: Locale(identifier: "en_US"), source),
                       "View source: " + source)
        XCTAssertEqual(SDKStrings.text("citation.openOne", locale: Locale(identifier: "zh_CN"), source),
                       "查看来源：" + source)
    }
}
