import SwiftLang
import Foundation
import XCTest
import MarkdownUI
@testable import SwiftOpenUI

final class MarkdownDelimiterTests: XCTestCase {
  func testChinesePunctuationBoundaryPreservesEmphasisWithoutChangingTheSource() throws {
    let source = "**想一次玩够选上海，想省力省钱选香港。**下面把影响决定的几项摊开。"
    let prepared = try NativeRichTextEngine.shared.prepare(source, mode: .textContent, sources: [])
    XCTAssertEqual(MarkdownContent(prepared).renderPlainText().trimmingCharacters(in: .whitespacesAndNewlines),
      "想一次玩够选上海，想省力省钱选香港。下面把影响决定的几项摊开。")
    XCTAssertTrue(MarkdownContent(prepared).renderHTML().contains("<strong>想一次玩够选上海，想省力省钱选香港。</strong>"))
    let corrected = "**想一次玩够选上海，想省力省钱选香港**。下面把影响决定的几项摊开。"
    let readable = NativeInlineMarkdown.attributed(try NativeRichTextEngine.shared.prepare(corrected, mode: .textContent, sources: []))
    XCTAssertEqual(String(readable.characters).trimmingCharacters(in: .whitespacesAndNewlines), "想一次玩够选上海，想省力省钱选香港。下面把影响决定的几项摊开。")
    XCTAssertTrue(readable.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
  }

  func testScreenshotChineseEmphasisSurvivesTheNativeMarkdownParserInEveryTextMode() throws {
    let examples = [
      ("**看你要不要收藏。**17173 同期另一篇提到", "看你要不要收藏。", "17173 同期另一篇提到"),
      ("**看等级阶段。**如果你正好在 14–20 级这个区间练级", "看等级阶段。", "如果你正好在 14–20 级这个区间练级"),
      ("中文**（说明）**正文", "（说明）", "正文"),
    ]
    for mode in [NativeRichTextMode.textContent, .markdown, .inline] {
      for (source, emphasized, suffix) in examples {
        let prepared = try NativeRichTextEngine.shared.prepare(source, mode: mode, sources: [])
        let rendered = MarkdownContent(prepared)
        XCTAssertTrue(rendered.renderHTML().contains("<strong>\(emphasized)</strong>"), "\(mode): \(source)")
        XCTAssertTrue(rendered.renderPlainText().contains(suffix))
        XCTAssertFalse(rendered.renderPlainText().contains("**"))
        XCTAssertFalse(rendered.renderPlainText().contains("\u{200B}"), "Do not repair delimiters by inserting invisible characters")
      }
    }
  }

  func testChineseEmphasisKeepsNestedLinksCodeAndExplicitLiteralStars() throws {
    let source = #"**看[说明](https://example.com/a)。**接着读，`**代码。**正文`，\*\*原样。\*\*正文"#
    let prepared = try NativeRichTextEngine.shared.prepare(source, mode: .textContent, sources: [])
    let html = MarkdownContent(prepared).renderHTML()
    XCTAssertTrue(html.contains(#"<strong>看<a href="https://example.com/a">说明</a>。</strong>接着读"#))
    XCTAssertTrue(html.contains("<code>**代码。**正文</code>"))
    XCTAssertTrue(MarkdownContent(prepared).renderPlainText().contains("**原样。**正文"))
  }
  func testValidChineseEmphasisRendersWithoutMarkersAfterPreparation() throws {
    for source in ["**重点**", "前文。 **想一次玩够选上海，想省力省钱选香港。** 后文。"] {
      let prepared = try NativeRichTextEngine.shared.prepare(source, mode: .textContent, sources: [])
      let attributed = NativeInlineMarkdown.attributed(prepared)
      XCTAssertFalse(String(attributed.characters).contains("**"))
      XCTAssertTrue(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }
  }
  func testSpacesInsideDelimitersAndEscapedOrCodeStarsRemainLiteral() throws {
    for source in ["** 重点 **", "**重点 **", "\\*\\*重点\\*\\*", "`**重点**`"] {
      let prepared = try NativeRichTextEngine.shared.prepare(source, mode: .textContent, sources: [])
      let attributed = NativeInlineMarkdown.attributed(prepared)
      XCTAssertTrue(String(attributed.characters).contains("**"), source)
      XCTAssertFalse(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }, source)
    }
  }
}
