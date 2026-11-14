#if os(macOS)
import AppKit
import OpenUILang
import SwiftUI
import XCTest
@testable import OpenUISwiftUI

final class SliderFeedbackRenderingTests: XCTestCase {
  @MainActor func testSubmittedErrorTracksMountedNumericDraftBeforeNextSubmit() throws {
    _ = NSApplication.shared
    let library = try OpenUIStandardComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("root=Slider(\"budget\",\"continuous\",0,100,1,[10],\"Budget\")")
    let context = OpenUIComponentContext(element: try XCTUnwrap(state.root),
      registry: library.registry, state: state, formName: "qa")
    let validation = NativeFormValidation()
    let host = NSHostingView(rootView: OpenUINativeField(context: context, kind: .slider)
      .environmentObject(state).environment(\.openUIFormValidation, validation)
      .frame(width: 320))
    let window = mount(host, width: 320, height: 200)
    defer { window.close() }
    pump(host)
    let draft = state.editingRecord(kind: "slider", form: "qa", name: "budget", create: NativeSliderDraft.init)
    XCTAssertEqual(draft.values, [10], "Use the actual mounted field's record")
    draft.edit("150", at: 0)
    XCTAssertFalse(validation.validateAll())
    pump(host)
    XCTAssertEqual(validation.errors["budget"], "Value must be between 0 and 100")
    try snapshot(host, name: "feedback-submitted-150")
    for invalid in ["", "1e", "-"] {
      draft.edit(invalid, at: 0)
      pump(host)
      XCTAssertEqual(validation.errors["budget"], "Invalid number", invalid)
      XCTAssertEqual(state.fieldValue(form: "qa", name: "budget"), .array([.number(10)]))
      if invalid.isEmpty { try snapshot(host, name: "feedback-empty-before-submit") }
    }
    draft.edit("37", at: 0)
    pump(host)
    XCTAssertNil(validation.errors["budget"], "A valid draft clears stale feedback before its delayed Store write")
    try snapshot(host, name: "feedback-valid-37-before-submit")
    XCTAssertTrue(validation.validateAll())
    XCTAssertEqual(state.fieldValue(form: "qa", name: "budget"), .array([.number(37)]))
  }

  @MainActor func testNativeMouseDragUsesRTLAndLTRRangeCoordinates() throws {
    _ = NSApplication.shared
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      var changes: [[Double]] = []
      var endings = 0
      let configuration = NativeSliderConfiguration(minimum:0,maximum:100,step:1,discrete:false)
      let host = NSHostingView(rootView: NativeSliderTrack(values:[20,80],configuration:configuration,
        enabled:true,showsDots:false,label:"Budget",select:{value,index in
          var next=[20.0,80.0]; next[index]=value; changes.append(next)
        },
        ended:{endings += 1}).environment(\.layoutDirection,direction).frame(width:320,height:44))
      let window = mount(host,width:320,height:44)
      defer { window.close() }
      pump(host)
      let geometry = NativeSliderTrackGeometry(width:320,minimum:0,maximum:100,rightToLeft:direction == .rightToLeft)
      func event(_ type:NSEvent.EventType,_ value:Double,_ number:Int)throws->NSEvent{
        try XCTUnwrap(NSEvent.mouseEvent(with:type,location:host.convert(NSPoint(x:geometry.x(for:value),y:22),to:nil),
          modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,
          context:nil,eventNumber:number,clickCount:1,pressure:type == .leftMouseUp ? 0 : 1))
      }
      // Events remain in this test process; no desktop cursor or AX value setter.
      for (start, end, expected) in [(20.0,30.0,[30.0,80.0]), (80.0,70.0,[20.0,70.0])] {
        let down = try event(.leftMouseDown,start,1)
        let dragged = try event(.leftMouseDragged,end,2)
        let up = try event(.leftMouseUp,end,3)
        window.sendEvent(down)
        pump(host)
        window.sendEvent(dragged)
        pump(host)
        window.sendEvent(up)
        pump(host)
        XCTAssertEqual(try XCTUnwrap(changes.last),expected,"\(direction)")
      }
      XCTAssertEqual(endings,2)
    }
  }

  @MainActor private func snapshot(_ view: NSView, name: String) throws {
    guard let out = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"] else { return }
    try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      .write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
  }

  @MainActor private func mount<V: View>(_ host: NSHostingView<V>, width: CGFloat, height: CGFloat) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: width,height: height),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    return window
  }
  @MainActor private func pump(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    view.layoutSubtreeIfNeeded()
  }
}
#endif
