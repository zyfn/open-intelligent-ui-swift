#if os(macOS)
import AppKit
import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class SliderFeedbackRenderingTests: XCTestCase {
  @MainActor func testMountedReactiveBindingAcceptsANormalizedValueEqualToItsPreviousValue() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("""
      $numbers=[10]
      root=Form("normalize",Buttons([]),[FormControl("Budget",Slider("budget","continuous",0,100,1,[10],"Budget",null,$numbers=[10]))])
      """)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry).frame(width: 320))
    let window = mount(host, width: 320, height: 240)
    defer { state.onStateUpdate = nil; window.close() }
    pump(host)
    let draft: NativeSliderDraft = try XCTUnwrap(state.existingEditingRecord(kind: "slider", form: "normalize", name: "budget"))
    var publications = 0
    state.onStateUpdate = { _ in publications += 1 }
    draft.edit("11", at: 0)
    draft.flush()
    XCTAssertEqual(state.stateValue("$numbers"), .array([.number(10)]))
    XCTAssertEqual(state.fieldValue(form: "normalize", name: "budget"), .array([.number(10)]))
    XCTAssertEqual(draft.text, ["10"], "A legal reactive transformation is an accepted write even when the Store stays at 10")
    XCTAssertEqual(publications, 1)
    draft.receive([10])
    draft.flush()
    pump(host)
    XCTAssertEqual(try numericInput(in: host).stringValue, "10")
    XCTAssertEqual(publications, 1, "The accepted normalized edit must not remain pending and write again")
  }

  @MainActor func testMountedQueuedRetirementKeepsTheDraftAndAcceptedWritesPreserveNewerEdits() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("""
      $fieldName="a"
      root=Slider($fieldName,"continuous",0,100,1,[10],"Budget")
      """)
    state.setFieldValue(form: nil, name: "b", value: .array([.number(10)]), componentType: "Slider")
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry).frame(width: 320))
    let window = mount(host, width: 320, height: 240)
    defer { state.onStateUpdate = nil; window.close() }
    pump(host)
    let draft: NativeSliderDraft = try XCTUnwrap(state.existingEditingRecord(kind: "slider", form: nil, name: "a"))
    let commit = try XCTUnwrap(draft.commit)
    var attempts = 0
    draft.commit = { value, complete in attempts += 1; commit(value, complete) }
    draft.edit("37", at: 0)
    var queued = false
    state.onStateUpdate = { _ in
      guard !queued else { return }
      queued = true
      state.setState("$fieldName", value: .string("b"))
      draft.flush()
      draft.flush()
    }
    state.setState("$trigger", value: .number(1))
    XCTAssertTrue(queued)
    XCTAssertEqual(attempts, 1, "The same pending edit cannot be enqueued twice before its actual acceptance callback")
    XCTAssertEqual(state.fieldValue(form: nil, name: "a"), .array([.number(10)]))
    XCTAssertEqual(state.fieldValue(form: nil, name: "b"), .array([.number(10)]))
    pump(host)
    XCTAssertEqual(draft.text, ["37"])

    state.onStateUpdate = nil
    state.setState("$fieldName", value: .string("a"))
    pump(host)
    var editedAgain = false
    state.onStateUpdate = { _ in
      guard !editedAgain, state.fieldValue(form: nil, name: "a") == .array([.number(37)]) else { return }
      editedAgain = true
      draft.edit("42", at: 0)
      draft.receive([37])
    }
    draft.flush()
    XCTAssertTrue(editedAgain, "The rejected queued attempt must release its in-flight slot for a later mount")
    XCTAssertEqual(draft.text, ["42"], "Acceptance must advance the baseline before a public callback can edit again")
    pump(host)
    XCTAssertEqual(try numericInput(in: host).stringValue, "42")
    draft.flush()
    XCTAssertEqual(state.fieldValue(form: nil, name: "a"), .array([.number(42)]))
    XCTAssertEqual(state.fieldValue(form: nil, name: "b"), .array([.number(10)]))
  }

  @MainActor func testStreamingFieldAndFormNamesRetainOnlyTheirCompletedEditingRecord() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    for namesForm in [false, true] {
      let state = OpenUIState(schema: library.library.toSchema())
      let root = namesForm
        ? "Form($name,Buttons([]),[FormControl(\"Budget\",Slider(\"budget\",\"continuous\",0,100,1,[10],\"Budget\"))])"
        : "Slider($name,\"continuous\",0,100,1,[10],\"Budget\")"
      state.push("root=" + root + "\n$name=\"a")
      let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry).frame(width: 320))
      let window = mount(host, width: 320, height: 240)
      defer { window.close() }
      func record(_ name: String) -> NativeSliderDraft? {
        state.existingEditingRecord(kind: "slider", form: namesForm ? OpenUIString(name) : nil,
          name: namesForm ? "budget" : OpenUIString(name))
      }
      pump(host)
      XCTAssertNil(record("a"))
      var name = "a"
      for character in "mount" {
        name.append(character)
        state.push(String(character))
        pump(host)
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "name"), name)
        XCTAssertFalse(try XCTUnwrap(state.root).sourceReadiness["name"].complete)
        XCTAssertNil(record(name), "A partial \(namesForm ? "form" : "field") name must not own a retained draft")
      }
      state.push("\"")
      state.complete()
      pump(host)
      let draft = try XCTUnwrap(record(name))
      XCTAssertEqual(draft.values, [10])
      XCTAssertEqual(try numericInput(in: host).stringValue, "10")
      XCTAssertEqual(state.fieldValue(form: namesForm ? OpenUIString(name) : nil,
        name: namesForm ? "budget" : OpenUIString(name)), .array([.number(10)]))
      XCTAssertNil(record("a"))
      XCTAssertNil(record("amo"))
      XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    }
  }

  @MainActor func testMountedNameChangeKeepsDraftsAndRejectedPendingWritesWithTheirField() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("""
      $fieldName="a"
      root=Slider($fieldName,"continuous",0,100,1,[10],"Budget")
      """)
    for name in [OpenUIString("a"), OpenUIString("b")] {
      state.setFieldValue(form: nil, name: name, value: .array([.number(10)]), componentType: "Slider")
    }
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let revision = state.presentationRevision
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry).frame(width: 320))
    let window = mount(host, width: 320, height: 220)
    defer { window.close() }
    func record(_ name: OpenUIString) throws -> NativeSliderDraft {
      try XCTUnwrap(state.existingEditingRecord(kind: "slider", form: nil, name: name))
    }
    func value(_ name: OpenUIString) -> Value { state.fieldValue(form: nil, name: name) }

    pump(host)
    let a = try record("a")
    try edit("1e", in: host, window: window)
    XCTAssertEqual(a.text, ["1e"], "The unrepresentable draft comes from the real mounted TextField")
    state.setState("$fieldName", value: .string("b"))
    pump(host)
    let b = try record("b")
    XCTAssertFalse(a === b)
    XCTAssertEqual(try numericInput(in: host).stringValue, "10")
    try edit("-", in: host, window: window)
    state.setState("$fieldName", value: .string("a"))
    pump(host)
    XCTAssertTrue(try record("a") === a)
    XCTAssertEqual(try numericInput(in: host).stringValue, "1e")
    XCTAssertEqual(b.text, ["-"])

    a.edit("37", at: 0)
    let oldCommit = try XCTUnwrap(a.commit)
    state.setState("$fieldName", value: .string("b"))
    // Exercise the old scheduled flush at a controlled point, before the view
    // processes the new target. No timer delay is needed to reproduce the race.
    a.flush()
    XCTAssertEqual(value("a"), .array([.number(10)]))
    XCTAssertEqual(value("b"), .array([.number(10)]))
    pump(host)
    XCTAssertTrue(try record("b") === b)
    XCTAssertEqual(try numericInput(in: host).stringValue, "-")
    var oldResult: Bool?
    oldCommit([99]) { oldResult = $0 != nil }
    XCTAssertEqual(oldResult, false, "A retained callback cannot adopt the new field's name")
    a.flush()
    XCTAssertEqual(value("a"), .array([.number(10)]))
    XCTAssertEqual(value("b"), .array([.number(10)]))

    state.setState("$fieldName", value: .string("a"))
    pump(host)
    XCTAssertEqual(try numericInput(in: host).stringValue, "37", "A rejected write remains a's local draft")
    a.flush()
    XCTAssertEqual(value("a"), .array([.number(37)]))
    XCTAssertEqual(value("b"), .array([.number(10)]))
    XCTAssertEqual(b.text, ["-"])
    pump(host)
    let retainedInput = try numericInput(in: host)
    state.setFieldValue(form: nil, name: "a", value: .array([.number(42)]), componentType: "Slider")
    pump(host)
    XCTAssertTrue(try numericInput(in: host) === retainedInput, "Ordinary value updates retain the control")
    XCTAssertTrue(try record("a") === a)
    XCTAssertEqual(retainedInput.stringValue, "42")
    XCTAssertEqual(state.presentationRevision, revision)

    state.setState("$fieldName", value: .string("c"))
    pump(host)
    XCTAssertEqual(value("c"), .array([.number(10)]), "A newly addressed field initializes its declared default")
    state.setState("$fieldName", value: .string("a"))
    pump(host)
    XCTAssertEqual(value("a"), .array([.number(42)]), "Returning to a field must not replace its accepted value with the default")
    XCTAssertEqual(try numericInput(in: host).stringValue, "42")

    state.reset()
    state.setSource("root=Slider(\"a\",\"continuous\",0,100,1,[60],\"Replacement\")")
    pump(host)
    XCTAssertFalse(try record("a") === a)
    oldResult = nil
    oldCommit([99]) { oldResult = $0 != nil }
    XCTAssertEqual(oldResult, false, "The old document's callback stays retired")
    XCTAssertEqual(value("a"), .array([.number(60)]))
    XCTAssertEqual(try numericInput(in: host).stringValue, "60")
  }

  @MainActor func testMountedParentFormChangeKeepsDraftsAndCallbacksInTheirOriginalForm() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("""
      $formName="first"
      root=Form($formName,Buttons([]),[FormControl("Budget",Slider("budget","continuous",0,100,1,[10],"Budget"))])
      """)
    state.setFieldValue(form: "first", name: "budget", value: .array([.number(10)]), componentType: "Slider")
    state.setFieldValue(form: "second", name: "budget", value: .array([.number(20)]), componentType: "Slider")
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry).frame(width: 320))
    let window = mount(host, width: 320, height: 240)
    defer { window.close() }
    func record(_ form: OpenUIString) throws -> NativeSliderDraft {
      try XCTUnwrap(state.existingEditingRecord(kind: "slider", form: form, name: "budget"))
    }
    func value(_ form: OpenUIString) -> Value { state.fieldValue(form: form, name: "budget") }

    pump(host)
    let first = try record("first")
    try edit("1e", in: host, window: window)
    let firstCommit = try XCTUnwrap(first.commit)
    state.setState("$formName", value: .string("second"))
    pump(host)
    let second = try record("second")
    XCTAssertFalse(first === second)
    XCTAssertEqual(try numericInput(in: host).stringValue, "20")
    try edit("-", in: host, window: window)
    state.setState("$formName", value: .string("first"))
    pump(host)
    XCTAssertTrue(try record("first") === first)
    XCTAssertEqual(try numericInput(in: host).stringValue, "1e")
    XCTAssertEqual(second.text, ["-"])
    XCTAssertEqual(value("first"), .array([.number(10)]))
    XCTAssertEqual(value("second"), .array([.number(20)]))

    first.edit("37", at: 0)
    state.setState("$formName", value: .string("second"))
    first.flush()
    pump(host)
    XCTAssertEqual(value("first"), .array([.number(37)]))
    XCTAssertEqual(value("second"), .array([.number(20)]), "The pending write must keep its captured form")
    firstCommit([38]) { XCTAssertEqual($0, [38]) }
    XCTAssertEqual(value("first"), .array([.number(38)]))
    XCTAssertEqual(value("second"), .array([.number(20)]), "Even a late callback cannot write the current form")
    second.edit("44", at: 0)
    second.flush()
    XCTAssertEqual(value("first"), .array([.number(38)]))
    XCTAssertEqual(value("second"), .array([.number(44)]))
    state.setState("$formName", value: .string("first"))
    pump(host)
    XCTAssertTrue(try record("first") === first)
    XCTAssertEqual(try numericInput(in: host).stringValue, "38")
    XCTAssertEqual(second.text, ["44"])
    state.setState("$formName", value: .string("third"))
    pump(host)
    XCTAssertEqual(value("third"), .array([.number(10)]), "A new form receives the field's default through the existing initialization API")
    state.setState("$formName", value: .string("second"))
    pump(host)
    XCTAssertEqual(value("second"), .array([.number(44)]))
    XCTAssertEqual(try numericInput(in: host).stringValue, "44")
  }

  @MainActor func testSubmittedErrorTracksMountedNumericDraftBeforeNextSubmit() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
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

  @MainActor private func numericInput(in host: NSView) throws -> NSTextField {
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let inputs = descendants(host).compactMap { $0 as? NSTextField }.filter(\.isEditable)
    XCTAssertEqual(inputs.count, 1)
    return try XCTUnwrap(inputs.first)
  }
  @MainActor private func edit(_ value: String, in host: NSView, window: NSWindow) throws {
    let input = try numericInput(in: host)
    input.selectText(nil)
    let editor = try XCTUnwrap(input.currentEditor() as? NSTextView)
    editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    window.makeFirstResponder(nil)
    pump(host)
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
