import SwiftLang
import XCTest
@testable import SwiftOpenUI
#if os(macOS)
import AppKit
import SwiftUI
#endif

final class JourneyLineTests: XCTestCase {
  @MainActor func testModeIsNotGuessedDuringStreamingOrAfterInterrupt() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=JourneyLine(\"fli")
    let partial = try XCTUnwrap(state.root)
    XCTAssertFalse(partial.sourceReadiness["mode"].complete)
    let context = OpenUIComponentContext(element: partial, registry: library.registry, state: state)
    XCTAssertNil(NativeJourneyLine.symbol(for: context), "An incomplete flight mode must not be displayed as taxi")
    state.interrupt()
    let interrupted = try XCTUnwrap(state.root)
    let interruptedContext = OpenUIComponentContext(element: interrupted, registry: library.registry, state: state)
    XCTAssertNil(NativeJourneyLine.symbol(for: interruptedContext), "A stopped partial mode must not acquire a taxi symbol")

    for (mode, expected) in [("flight", "airplane"), ("train", "tram.fill"), ("bus", "bus.fill"), ("taxi", "car.fill")] {
      state.reset()
      state.push("root=JourneyLine(\"\(mode)\")"); state.complete()
      let root = try XCTUnwrap(state.root)
      let complete = OpenUIComponentContext(element: root, registry: library.registry, state: state)
      XCTAssertEqual(NativeJourneyLine.symbol(for: complete), expected)
    }
  }

  @MainActor func testDesignerContractRendersInCardForEveryMode() throws {
    let library = try OpenUIComponents.library()
    let component = try XCTUnwrap(library.toSpec().components.first { $0.name == "JourneyLine" })
    XCTAssertEqual(component.signature, "JourneyLine(mode: \"flight\" | \"train\" | \"bus\" | \"taxi\")")
    XCTAssertNotNil(library.registry["JourneyLine"])
    XCTAssertNil(library.registry["CStyleJourneyLine"])
    XCTAssertTrue(library.prompt().contains("JourneyLine(mode:"))
    let state = OpenUIState(schema: library.library.toSchema())
    for mode in ["flight", "train", "bus", "taxi"] {
      let source = "root=Card([JourneyLine(\"\(mode)\")])"
      state.setSource(source)
      XCTAssertTrue(state.errors.isEmpty, "\(source): \(state.errors)")
      let card = try XCTUnwrap(state.root)
      let journey = try XCTUnwrap(PropValue.children(card).first)
      XCTAssertEqual(journey.typeName, "JourneyLine")
      XCTAssertEqual(PropValue.string(journey, "mode"), mode)
      #if os(macOS)
      _ = NSApplication.shared
      let view = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry).frame(width: 320))
      XCTAssertGreaterThan(view.fittingSize.height, 28, mode)
      #endif
    }
  }
}
