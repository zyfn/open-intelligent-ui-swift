import SwiftLang
import XCTest
@testable import SwiftOpenUI
#if os(macOS)
import AppKit
import SwiftUI
#endif

final class StepsTimelineTests: XCTestCase {
  @MainActor func testOptionalParametersAreAppendedAndOldProgramsStillParse() throws {
    let library = try OpenUIComponents.library()
    let schema = library.library.toSchema()
    XCTAssertEqual(library.registry.presentationLayoutFields("Steps"), ["variant"])
    XCTAssertEqual(schema.components["Steps"]?.map(\.name), ["items", "variant"])
    XCTAssertEqual(schema.components["StepsItem"]?.map(\.name), ["title", "details", "time"])
    XCTAssertEqual(schema.components["Steps"]?.map(\.required), [true, false])
    XCTAssertEqual(schema.components["StepsItem"]?.map(\.required), [true, true, false])
    let state = OpenUIState(schema: schema)
    for source in [
      "root=Steps([StepsItem(\"Prepare\",\"Bring water\")])",
      "root=Steps([StepsItem(\"Prepare\",\"Bring water\")],\"default\")",
      "root=Steps([StepsItem(\"西湖\",\"步行\",\"09:00\"),StepsItem(\"灵隐\",\"参观\")],\"timeline\")"
    ] {
      state.setSource(source)
      XCTAssertTrue(state.errors.isEmpty, "\(source): \(state.errors)")
      let root = try XCTUnwrap(state.root)
      XCTAssertEqual(root.typeName, "Steps")
      XCTAssertTrue(root.sourceReadiness["variant"].complete, source)
      XCTAssertFalse(PropValue.children(root, "items").isEmpty, source)
    }
    let items = PropValue.children(try XCTUnwrap(state.root), "items")
    XCTAssertEqual(PropValue.string(items[0], "time"), "09:00")
    XCTAssertNil(PropValue.string(items[1], "time"))
    state.setSource("root=Card([Steps([StepsItem(\"西湖\",\"步行\",\"09:00\")],\"timeline\")])")
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let nested = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
    XCTAssertEqual(nested.typeName, "Steps")
    XCTAssertEqual(PropValue.string(nested, "variant"), "timeline")
    XCTAssertEqual(PropValue.string(try XCTUnwrap(PropValue.children(nested, "items").first), "time"), "09:00")
    XCTAssertTrue(library.prompt().contains("Steps(items: StepsItem[], variant?:"))
    XCTAssertTrue(library.prompt().contains("StepsItem(title: string, details: string, time?: string)"))
  }

  @MainActor func testCharacterStreamingMatchesBatchAndDoesNotCommitPartialTimeOrVariant() throws {
    let library = try OpenUIComponents.library()
    let schema = library.library.toSchema()
    let source = "root=Steps([StepsItem(\"西湖\",\"步行\",\"09:00\"),StepsItem(\"灵隐\",\"参观\")],\"timeline\")"
    let batch = createParser(schema: schema).parse(source)
    XCTAssertTrue(batch.meta.errors.isEmpty, "\(batch.meta.errors)")
    let parser = createStreamingParser(schema: schema)
    for character in source { parser.push(String(character)) }
    let streamed = parser.getResult(complete: true)
    XCTAssertEqual(streamed.root, batch.root)
    XCTAssertTrue(streamed.meta.errors.isEmpty, "\(streamed.meta.errors)")

    let state = OpenUIState(schema: schema)
    state.push("root=Steps([StepsItem(\"西湖\",\"步行\",\"09:")
    if let root = state.root {
      XCTAssertFalse(root.sourceReadiness["variant"].complete)
      if let item = OpenUIComponentContext(element: root, registry: library.registry, state: state).children("items").first {
        XCTAssertNil(NativeStepsTimeline.time(item.value), "An unfinished time must not be displayed")
      }
    }
    state.push("00\"),StepsItem(\"灵隐\",\"参观\")],\"time")
    let partial = try XCTUnwrap(state.root)
    XCTAssertFalse(partial.sourceReadiness["variant"].complete, "Do not commit a partial trailing enum")
    XCTAssertEqual(PropValue.string(PropValue.children(partial, "items")[0], "time"), "09:00")
    state.push("line\")"); state.complete()
    let finished = try XCTUnwrap(state.root)
    XCTAssertTrue(finished.sourceReadiness["variant"].complete)
    XCTAssertEqual(PropValue.string(finished, "variant"), "timeline")
  }

  @MainActor func testInlineRowsCanArriveBeforeTheTrailingVariant() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=Steps([StepsItem(\"西湖\",\"步行\"),")
    let partial = try XCTUnwrap(state.root)
    XCTAssertFalse(partial.sourceReadiness["variant"].complete)
    let context = OpenUIComponentContext(element: partial, registry: library.registry, state: state)
    XCTAssertFalse(context.layoutConfigurationReady, "Steps must use the shared layout readiness contract")
    let first = try XCTUnwrap(context.children("items").first)
    XCTAssertEqual(NativeValue.string(first.value, "title"), "西湖")
    state.push("StepsItem(\"灵隐\",\"参观\")],\"timeline\")"); state.complete()
    let completed = try XCTUnwrap(state.root)
    let finalContext = OpenUIComponentContext(element: completed, registry: library.registry, state: state)
    XCTAssertTrue(finalContext.layoutConfigurationReady)
    let final = finalContext.children("items")
    XCTAssertEqual(final.first?.id, first.id)
    XCTAssertEqual(PropValue.string(completed, "variant"), "timeline")
  }

  @MainActor func testStreamingRowsKeepIdentityAndTimeRemainsOptional() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=Steps(rows,\"timeline\")\nrows=[StepsItem(\"西湖\",\"步行\",\"09:00\"),")
    let firstRoot = try XCTUnwrap(state.root)
    let firstContext = OpenUIComponentContext(element: firstRoot, registry: library.registry, state: state)
    XCTAssertTrue(firstContext.layoutConfigurationReady, "A known variant must not wait for later list items")
    let first = firstContext.children("items")
    XCTAssertEqual(first.count, 1)
    XCTAssertEqual(PropValue.string(firstRoot, "variant"), "timeline")
    state.push("StepsItem(\"灵隐\",\"参观\"),")
    let nextRoot = try XCTUnwrap(state.root)
    let next = OpenUIComponentContext(element: nextRoot, registry: library.registry, state: state).children("items")
    XCTAssertEqual(next.count, 2)
    XCTAssertEqual(next[0].id, first[0].id)
    XCTAssertNil(NativeValue.string(next[1].value, "time"))
    state.push("]"); state.complete()
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
  }

  @MainActor func testInterruptKeepsAnAlreadyCommittedTimelineStyleAndTime() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=Steps(rows,\"timeline\")\nrows=[StepsItem(\"West Lake\",\"Walk\",\"09:00\"),")
    let before = try XCTUnwrap(state.root)
    XCTAssertTrue(before.sourceReadiness["variant"].complete)
    XCTAssertEqual(PropValue.string(before, "variant"), "timeline")
    state.interrupt()
    let retained = try XCTUnwrap(state.root)
    XCTAssertTrue(retained.sourceReadiness["variant"].complete)
    XCTAssertEqual(PropValue.string(retained, "variant"), "timeline")
    let item = try XCTUnwrap(OpenUIComponentContext(element: retained, registry: library.registry, state: state).children("items").first)
    XCTAssertEqual(NativeStepsTimeline.time(item.value), "09:00")
  }

  #if os(macOS)
  @MainActor func testInterruptedInlineStepsDisplayDefaultNumbersWithoutInventingTime() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=Steps([StepsItem(\"First\",\"Details\"),")
    let root = try XCTUnwrap(state.root)
    XCTAssertFalse(root.sourceReadiness["variant"].complete)
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .frame(width: 220, height: 100, alignment: .topLeading).background(Color.white))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 220, height: 100),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.appearance = NSAppearance(named: .aqua)
    window.setFrameOrigin(.init(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    func ink(marker: Bool) throws -> Int {
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.15))
      let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: image)
      let scale = CGFloat(image.pixelsWide) / host.bounds.width
      let pixels = marker ? 0..<min(image.pixelsWide, Int(28 * scale))
        : min(image.pixelsWide, Int(45 * scale))..<image.pixelsWide
      return (0..<image.pixelsHigh).reduce(0) { count, y in
        count + pixels.reduce(0) { n, x in
          guard let pixel = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return n }
          return n + (max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.6 ? 1 : 0)
        }
      }
    }
    let before = try ink(marker: true)
    XCTAssertGreaterThan(try ink(marker: false), 8, "An unresolved layout must still show the received text")
    state.interrupt()
    XCTAssertTrue(state.isInterrupted)
    let retained = try XCTUnwrap(state.root)
    XCTAssertFalse(retained.sourceReadiness["variant"].complete)
    XCTAssertEqual(PropValue.children(retained, "items").count, 1)
    let after = try ink(marker: true)
    XCTAssertGreaterThan(after, before + 8, "A stopped, undecided Steps must show its default number")
  }

  @MainActor func testTimelineRendersTimedAndUntimedRowsAndWraps() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    func height(_ source: String) throws -> CGFloat {
      let state = OpenUIState(schema: library.library.toSchema()); state.setSource(source)
      XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
      return NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
        .frame(width: 180)).fittingSize.height
    }
    let withoutTime = try height("root=Steps([StepsItem(\"西湖\",\"步行\")],\"timeline\")")
    let withTime = try height("root=Steps([StepsItem(\"西湖\",\"步行\",\"09:00\")],\"timeline\")")
    let long = try height("root=Steps([StepsItem(\"西湖\",\"这是需要在窄屏下自然换行的长说明，这是需要在窄屏下自然换行的长说明。\",\"09:00\")],\"timeline\")")
    XCTAssertGreaterThan(withTime, withoutTime + 8)
    XCTAssertGreaterThan(long, withTime + 10)
  }
  #endif
}
