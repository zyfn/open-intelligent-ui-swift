import SwiftLang
import Combine
import XCTest
@testable import SwiftOpenUI

final class CompletionDeliveryTests: XCTestCase {
  @MainActor func testDuplicateFinalDeliveryAndEmptyChunksNeverClearTheRenderedRoot() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    let source = "root=Stack([TextContent(\"Visible prefix\"),Image(\"Photo\",\"https://example.com/image.png\")])"
    state.push(source)
    let revision = state.presentationRevision
    let mediaGeneration = state.mediaCache.generation
    var emptyFrames = 0
    let subscription = state.$root.sink { if $0 == nil { emptyFrames += 1 } }
    state.complete()
    state.push("")
    state.setSource(source)
    state.complete()
    state.setSource(source)
    XCTAssertEqual(emptyFrames, 0)
    XCTAssertEqual(state.presentationRevision, revision)
    XCTAssertEqual(state.mediaCache.generation, mediaGeneration)
    XCTAssertTrue(state.isComplete)
    withExtendedLifetime(subscription) {}
    state.setSource("root=TextContent(\"Different message\")")
    XCTAssertGreaterThan(state.presentationRevision, revision, "Actual replacements still reset the presentation")
  }
  @MainActor func testSameFinalSnapshotPreservesUserFields() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    let source = "root=Form(\"prefs\",Buttons([Button(\"Submit\")]),[FormControl(\"Name\",Input(\"name\"))])"
    state.setSource(source)
    state.setFieldValue(form: "prefs", name: "name", value: .string("Edited"), componentType: "Input")
    let snapshot = state.snapshotState()
    state.setSource(source)
    state.push("")
    XCTAssertEqual(state.snapshotState(), snapshot)
  }

  @MainActor func testUnescapedInnerQuotesRetainPrefixesAndTerminalDiagnostics() throws {
    // Preserve the malformed input verbatim; this records recovery, not repair.
    let source = #"""
      root = Stack([headline, verdictText])
      headline = MarkDownRenderer("# 杭州好玩，但它不给"刺激"，给的是"松弛"")
      verdictText = TextContent("杭州的好玩，是"待着舒服"，不是"玩得尽兴"。")
      """#
    try assertQuotedTextDelivery(source,
      headline: "# 杭州好玩，但它不给", verdict: "杭州的好玩，是",
      errors: [
        ["type-mismatch", "headline", "MarkDownRenderer", "/variant"],
        ["excess-args", "headline", "MarkDownRenderer", ""],
        ["type-mismatch", "verdictText", "TextContent", "/size"],
        ["excess-args", "verdictText", "TextContent", ""],
      ])
  }

  @MainActor func testEscapedInnerQuotesPreserveCompleteTextThroughFinalDelivery() throws {
    let source = #"""
      root = Stack([headline, verdictText])
      headline = MarkDownRenderer("# 杭州好玩，但它不给\"刺激\"，给的是\"松弛\"")
      verdictText = TextContent("杭州的好玩，是\"待着舒服\"，不是\"玩得尽兴\"。")
      """#
    try assertQuotedTextDelivery(source,
      headline: "# 杭州好玩，但它不给\"刺激\"，给的是\"松弛\"",
      verdict: "杭州的好玩，是\"待着舒服\"，不是\"玩得尽兴\"。", errors: [])
  }

  @MainActor private func assertQuotedTextDelivery(_ source: String, headline: String, verdict: String,
                                                  errors: [[String?]]) throws {
    let schema = try OpenUIComponents.library().library.toSchema()
    for streaming in [false, true] {
      let state = OpenUIState(schema: schema)
      var latestMeta: ParseMeta?
      var limitExceeded: Bool?
      state.onParseResult = { result in
        latestMeta = result.meta
        limitExceeded = result.nativeLimitExceeded
      }
      if streaming {
        for scalar in source.unicodeScalars { state.push(String(scalar)) }
        state.complete()
      } else {
        state.setSource(source)
      }

      XCTAssertTrue(state.isComplete)
      XCTAssertFalse(state.isInterrupted)
      XCTAssertEqual(limitExceeded, false)
      let meta = try XCTUnwrap(latestMeta)
      XCTAssertFalse(meta.incomplete)
      XCTAssertTrue(meta.unresolved.isEmpty)
      let diagnostics: ([OpenUIError]) -> [[String?]] = { values in
        values.map { [$0.code.rawValue, $0.statementId, $0.component, $0.path?.displayString] }
      }
      XCTAssertEqual(diagnostics(meta.errors), errors, "streaming: \(streaming)")
      XCTAssertEqual(diagnostics(state.errors), errors, "Final diagnostics must survive completion")

      let root = try XCTUnwrap(state.root)
      XCTAssertEqual(root.typeName, "Stack")
      let children = PropValue.children(root)
      XCTAssertEqual(children.map(\.typeName), ["MarkDownRenderer", "TextContent"])
      guard children.count == 2 else { continue }
      XCTAssertEqual(PropValue.string(children[0], "textMarkdown"), headline)
      XCTAssertEqual(PropValue.string(children[1], "text"), verdict)
    }
  }
}
