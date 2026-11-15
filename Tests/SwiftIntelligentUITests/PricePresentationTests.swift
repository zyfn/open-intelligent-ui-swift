import XCTest
import SwiftLang
@testable import SwiftIntelligentUI

final class PricePresentationTests: XCTestCase {
    @MainActor func testCanonicalPriceAndTagsPreserveAmountAndScope() throws {
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        state.setSource(#"root=ProductCard({id:"p",title:"住宿",images:[],price:360,currency:"CNY",priceNote:"成人销售价",priceText:"查询报价 ¥999",tags:["近地铁","含早","近地铁"]})"#)
        XCTAssertTrue(state.errors.isEmpty)
        let data = try XCTUnwrap(ProductCardData(PropValue.value(try XCTUnwrap(state.root), "product")))
        XCTAssertEqual(data.price.text, "¥360")
        XCTAssertEqual(data.priceText, "¥360")
        XCTAssertEqual(data.price.note, "成人销售价")
        XCTAssertEqual(data.tags, ["近地铁", "含早"])
    }
    @MainActor func testLegacyReadCompatibilityRemovesOnlyDisplayBoilerplate() throws {
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        for (legacy, expected) in [("查询报价 ¥360", "¥360"), ("¥100（条件 A）", "¥100（条件 A）")] {
            state.setSource("root=ProductCard({id:\"p\",title:\"商品\",images:[],priceText:\"\(legacy)\"})")
            let data = try XCTUnwrap(ProductCardData(PropValue.value(try XCTUnwrap(state.root), "product")))
            XCTAssertEqual(data.priceText, legacy)
            XCTAssertEqual(data.price.text, expected)
        }
        XCTAssertFalse(PricePresentation.valid(.string("查询报价 ¥360")))
        XCTAssertTrue(PricePresentation.valid(.string("¥360")))
    }
    @MainActor func testTransportPriceNeverInfersScopeFromRoundLinkOrLegCount() throws {
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        state.setSource(#"root=TransportCard({id:"t",legs:[{mode:"train",from:"A",to:"B"},{mode:"train",from:"B",to:"A"}],price:"63.00",currency:"CNY",priceNote:"成人销售价",bookingURL:"https://example.com/round?x=1"})"#)
        let data = try XCTUnwrap(TransportData(PropValue.value(try XCTUnwrap(state.root), "journey")))
        XCTAssertEqual(data.price.text, "¥63.00")
        XCTAssertEqual(data.price.note, "成人销售价")
        XCTAssertTrue(library.validationIssues(in: state, source: "").isEmpty)
    }
}
