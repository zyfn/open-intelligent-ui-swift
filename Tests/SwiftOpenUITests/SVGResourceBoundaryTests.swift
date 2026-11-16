import SwiftLang
import XCTest
@testable import SwiftOpenUI

final class SVGResourceBoundaryTests: XCTestCase {
  func testOrdinarySVGRemainsValid() throws {
    let svg = #"<svg viewBox="0 0 320 180"><rect width="320" height="180"/></svg>"#
    XCTAssertEqual(try XCTUnwrap(NativeSVGDocument.parse(svg)).ratio, 320.0 / 180.0, accuracy: 0.001)
  }

  func testExtremeRatiosAreRejectedBeforeNativeFitting() {
    XCTAssertNil(NativeSVGDocument.parse(#"<svg viewBox="0 0 100000000 1"/>"#))
    XCTAssertNil(NativeSVGDocument.parse(#"<svg viewBox="0 0 1 100000000"/>"#))
  }

  func testDeepNestingAndExcessiveElementsAreRejected() {
    let nested = #"<svg viewBox="0 0 10 10">"# + String(repeating: "<g>", count: 140)
      + String(repeating: "</g>", count: 140) + "</svg>"
    XCTAssertNil(NativeSVGDocument.parse(nested))
    let many = #"<svg viewBox="0 0 10 10">"# + String(repeating: "<path d=\"M0 0\"/>", count: 10_100) + "</svg>"
    XCTAssertNil(NativeSVGDocument.parse(many))
  }

  func testExternalEntitiesAndScriptAreRejected() {
    XCTAssertNil(NativeSVGDocument.parse(#"<!DOCTYPE svg [<!ENTITY e SYSTEM "https://example.com/">]><svg viewBox="0 0 10 10"/>"#))
    XCTAssertNil(NativeSVGDocument.parse(#"<svg viewBox="0 0 10 10"><script>bad()</script></svg>"#))
  }

  func testInlineAndPreviewDocumentKeepSandboxAndAuthoredColors() throws {
    let source = ##"<svg viewBox="0 0 320 180"><rect fill="#123456" stroke="currentColor" width="320" height="180"/><text x="10" y="30">原始说明</text></svg>"##
    let document = try XCTUnwrap(NativeSVGDocument.parse(source))
    for textColor in ["#15171A", "#ECEEF2"] {
      let html = document.html(textColor: textColor)
      XCTAssertTrue(html.contains(source), "Preview must preserve authored markup, labels and colors")
      XCTAssertTrue(html.contains("script-src 'none'"))
      XCTAssertTrue(html.contains("connect-src 'none'"))
      XCTAssertTrue(html.contains("default-src 'none'"))
      XCTAssertTrue(html.contains("background:transparent;color:" + textColor))
      XCTAssertFalse(html.contains("filter:"), "Dark appearance must not invert authored SVG colors")
    }
  }
}

extension SVGResourceBoundaryTests {
  func testSVGProjectionIsBoundedAndRepeatedFitsDoNotReparseXML() throws {
    let source = #"<svg viewBox="0 0 1 5000"><rect width="1" height="5000"/></svg>"#
    let cache = NativeSVGDocumentCache()
    for _ in 0..<100 {
      let document = try XCTUnwrap(cache.value(source))
      XCTAssertGreaterThanOrEqual(document.viewportRatio, 0.25)
      XCTAssertLessThanOrEqual(document.viewportRatio, 8)
    }
    XCTAssertEqual(cache.parseCount, 1)
    _ = cache.value(#"<svg viewBox="0 0 320 180"/>"#)
    XCTAssertEqual(cache.parseCount, 2)
  }
}
