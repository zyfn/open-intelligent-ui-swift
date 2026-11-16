import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class ChartPresentationTests: XCTestCase {
  #if os(iOS) || os(macOS)
  @MainActor func testSingleSeriesPlotDoesNotReserveADataToolbarRow() throws {
    let context = try chartContext()
    for locale in ["en_US", "zh_Hans_CN"] {
      let content = NativeChart(context: context)
        .environment(\.locale, Locale(identifier: locale))
        .environment(\.dynamicTypeSize, .large)
        .frame(width: 320).fixedSize(horizontal: false, vertical: true)
      #if os(iOS)
      let host = UIHostingController(rootView: content)
      let height = host.sizeThatFits(in: CGSize(width: 320, height: 10_000)).height
      #else
      _ = NSApplication.shared
      let height = NSHostingView(rootView: content).fittingSize.height
      #endif
      XCTAssertEqual(height, 250, accuracy: 1,
        "A single-series chart needs only its plot; data access must not reserve a permanent control row")
    }
  }
  #endif

  #if os(iOS)
  @MainActor func testTouchPlotKeepsNativeTapInspectionAlongsideItsSystemContextMenu() throws {
    let context = try chartContext()
    let host = UIHostingController(rootView: ScrollView {
      NativeChart(context: context).frame(width: 320)
      Color.clear.frame(height: 600)
    }.environment(\.dynamicTypeSize, .large))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
    window.rootViewController = host
    window.isHidden = false
    defer { window.isHidden = true; window.rootViewController = nil }
    host.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.view.layoutIfNeeded()

    func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    let views = descendants(host.view)
    let taps = views.flatMap { $0.gestureRecognizers ?? [] }
      .compactMap { $0 as? UITapGestureRecognizer }
      .filter { $0.name == "openui.chart.inspection.tap" }
    XCTAssertEqual(taps.count, 1)
    let tap = try XCTUnwrap(taps.first)
    XCTAssertNotNil(tap.view)
    XCTAssertFalse(tap.cancelsTouchesInView,
      "Inspection must retain the native tap's non-cancelling touch behavior")
    XCTAssertTrue(views.contains { $0 is UIScrollView }, "The plot is mounted inside a real scrolling host")
    XCTAssertTrue(views.flatMap(\.interactions).contains { $0 is UIContextMenuInteraction },
      "Complete data remains reachable through the plot's system context menu")
  }
  #endif

  @MainActor private func chartContext() throws -> OpenUIComponentContext {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("""
      root=HorizontalBarChart(["First","Second"],[Series("Distance",[3.125,8.75])],"grouped","km")
      """)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    return OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.registry, state: state)
  }
}
