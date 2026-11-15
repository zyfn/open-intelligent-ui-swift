import XCTest
import SwiftLang
@testable import SwiftIntelligentUI

final class FeedbackDiagnosticsTests: XCTestCase {
    @MainActor func testRichProductRendersCoreButStrictlyReportsMetadata() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource(#"root=ProductCard({id:"a",title:"耳机",images:[],priceText:"¥300",purchaseURL:"/a?exParams=x%2Fy&flag=1",priceCNY:300,noiseControl:"输入原文"})"#)
        let root = try XCTUnwrap(state.root)
        let data = try XCTUnwrap(ProductCardData(PropValue.value(root, "product")))
        XCTAssertEqual(data.title, "耳机")
        XCTAssertEqual(data.priceText, "¥300")
        XCTAssertEqual(data.purchaseURL, "/a?exParams=x%2Fy&flag=1")
        let issues = library.validationIssues(in: root)
        XCTAssertTrue(issues.contains { $0.contains("priceCNY") })
        XCTAssertTrue(issues.contains { $0.contains("noiseControl") })
        XCTAssertFalse(issues.contains { $0.contains("incomplete product") })
    }

    @MainActor func testEquivalentColorWarningsAreNonBlockingAndRespectCardSurface() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource(#"root=Box([Row([Text("不可读","md","muted")]),Card([Text("独立表面","md","muted")])],"col",2,3,"faint")"#)
        let root = try XCTUnwrap(state.root)
        XCTAssertTrue(library.validationIssues(in: root).isEmpty)
        XCTAssertTrue(library.presentationWarnings(in: root).isEmpty)
        state.setSource(#"root=Box([Text("不可读","md","warning")],"col",2,3,"chart4")"#)
        let warnings = library.presentationWarnings(in: try XCTUnwrap(state.root))
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("same semantic color (warning)"))
        state.setSource(#"root=Box([Text("状态文字","md","warning")],"col",2,3,"warning")"#)
        XCTAssertTrue(library.presentationWarnings(in: try XCTUnwrap(state.root)).isEmpty)
        state.setSource(#"root=Box([Icon("info","md","warning"),Text("可读","md","ink")],"col",2,3,"surface")"#)
        XCTAssertTrue(library.presentationWarnings(in: try XCTUnwrap(state.root)).isEmpty)
    }

    @MainActor func testRecoveredInvalidEnumIsNotAcceptedAsValidContract() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        for invalidSize in [" 分钟", "xl", "2xl"] {
            let recovered = EvaluatedElement(typeName: "Text", props: [("text", .string("正文")), ("size", .string(OpenUIString(invalidSize)))])
            XCTAssertTrue(library.validationIssues(in: recovered).contains { $0.contains("invalid option") })
        }
        state.setSource(#"""
        root=Col([Text(row["车型"]),Text(row["耗时"]+" 分钟")])
        row={"车型":"高铁","耗时":45}
        """#)
        XCTAssertTrue(state.errors.isEmpty)
        let root = try XCTUnwrap(state.root)
        XCTAssertTrue(library.validationIssues(in: root).isEmpty)
        XCTAssertEqual(PropValue.children(root).map { PropValue.string($0, "text") }, ["高铁", "45 分钟"])
    }

    @MainActor func testSourcePreflightRejectsNonASCIIIdentifiersWithoutRejectingQuotedContent() throws {
        let library = try OpenIntelligentUIComponents()
        XCTAssertFalse(library.sourceIssues(in: #"root=Text(row.耗时)"#).isEmpty)
        XCTAssertFalse(library.sourceIssues(in: #"rows=[{耗时:45,票价:78}]"#).isEmpty)
        XCTAssertTrue(library.sourceIssues(in: #"root=Text(row["耗时"]+" 分钟")"#).isEmpty)
        XCTAssertTrue(library.sourceIssues(in: #"rows=[{"耗时":45,"票价":78}]"#).isEmpty)
        XCTAssertTrue(library.sourceIssues(in: "// 中文注释\nroot=Text(\"中文 .耗时 和转义\\\"词\") /* 中文 */").isEmpty)
        let state = library.makeState()
        let unquoted = #"""
        root=Text(@Default(rows[0]["耗时"],"missing"))
        rows=[{耗时:45,票价:78}]
        """#
        state.setSource(unquoted)
        XCTAssertTrue(library.validationIssues(in: state, source: unquoted).contains { $0.contains("non-ASCII code identifier") })
    }
}
