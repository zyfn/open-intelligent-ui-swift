import SwiftLang
#if os(macOS)
import AppKit
import Combine
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class TableMountedViewTests:XCTestCase {
  @MainActor func testConstructingAnUnmountedTableDoesNotCreateAnEditingRecord() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    defer { state.reset() }
    state.setSource("root=EditableTable(\"orders\",[{header:\"Name\",type:\"string\"}],[{id:\"r1\",values:[\"before\"]}])")
    let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.registry, state: state)
    let table = NativeEditableTable(context: context)
    let record: NativeTableEditingState? = state.existingEditingRecord(kind: "table", form: nil, name: "orders")
    XCTAssertNil(record, "The mounted StateObject, not view construction or fitting inputs, creates the record")
    withExtendedLifetime(table) {}
  }

  @MainActor func testAutomaticReadingLayoutKeepsMountedCustomCellsInputDraftAndActions() throws {
    _ = NSApplication.shared
    let standard = try OpenUIComponents.library()
    let button = try XCTUnwrap(standard.library.components.first { $0.name == "Button" })
    let customCell = OpenUIComponent(name: "MountedTableValue", description: "Mounted cell evidence",
      params: [OpenUIParameter.string("id"), OpenUIParameter.string("value")]) { context in
        MountedTableValue(id: context.string("id") ?? "", value: context.string("value") ?? "")
          .fixedSize()
      }
    let library = try standard.extending(adding: [customCell], overriding: [
      OpenUIComponent(button) { context in
        NativeComponentHost(context: context) { context in
          OpenUINativeButton(context: context).background(MountedTableMarker(id: "action"))
        }
      }
    ])
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("""
      root=Table([
        Col("Details",[
          Stack([Input("draft",null,"text",null,"initial"),Button("Send",@ToAssistant("Original table message"))]),
          TextContent("Second row")
        ]),
        Col("Amount",[MountedTableValue("short","12"),MountedTableValue("long","123456")],"number")
      ])
      """)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    var received: [ActionEvent] = []
    state.onAction = { received.append($0) }
    let typeSize = MountedTableTextSize()
    let hosting = NSHostingView(rootView: MountedTableEnvironment(typeSize: typeSize,
      content: OpenUIContentView(state: state, registry: library.registry)
        .frame(width: 560).fixedSize(horizontal: false, vertical: true)
        .frame(width: 560, height: 620, alignment: .topLeading)))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    window.orderFront(nil)
    defer { window.close() }

    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func marker(_ id: String) throws -> NSView {
      let matches = descendants(hosting).filter { $0.identifier?.rawValue == "openui.test.table.\(id)" }
      XCTAssertEqual(matches.count, 1, "A layout change must not create a second mounted \(id) cell")
      return try XCTUnwrap(matches.first)
    }
    func inputs() -> [NSTextField] {
      descendants(hosting).compactMap { $0 as? NSTextField }.filter(\.isEditable)
    }
    func settle() {
      hosting.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      hosting.layoutSubtreeIfNeeded()
    }
    func frame(_ view: NSView) -> CGRect {
      let rect = view.convert(view.bounds, to: hosting)
      return CGRect(x: rect.minX,
        y: hosting.isFlipped ? rect.minY : hosting.bounds.maxY - rect.maxY,
        width: rect.width, height: rect.height)
    }
    // As in ReferenceRenderingTests, dispatch public AppKit events only to
    // this offscreen window. Its inactive SwiftUI AX tree is not complete.
    func click(_ point: NSPoint) throws {
      let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
      let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
        windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
      NSApplication.shared.postEvent(up, atStart: false)
      window.sendEvent(down)
      window.sendEvent(up)
      settle()
    }
    func sendAction(expectedCount: Int) throws {
      let action = try marker("action")
      try click(action.convert(NSPoint(x: action.bounds.midX, y: action.bounds.midY), to: nil))
      let deadline = Date().addingTimeInterval(2)
      while received.count < expectedCount && Date() < deadline { settle() }
      XCTAssertEqual(received.count, expectedCount, "The real table Button must still dispatch exactly once")
      XCTAssertEqual(received.last?.type, "continue_conversation")
      XCTAssertEqual(received.last?.humanFriendlyMessage, "Original table message")
    }

    settle()
    XCTAssertEqual(inputs().count, 1)
    let input = try XCTUnwrap(inputs().first)
    let short = try XCTUnwrap(try marker("short") as? NSTextField)
    let long = try XCTUnwrap(try marker("long") as? NSTextField)
    let action = try marker("action")
    XCTAssertEqual(state.fieldValue(form: nil, name: "draft"), .string("initial"))
    input.selectText(nil)
    let editor = try XCTUnwrap(input.currentEditor() as? NSTextView)
    editor.insertText("Edited table draft", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    window.makeFirstResponder(nil)
    settle()
    XCTAssertEqual(state.fieldValue(form: nil, name: "draft"), .string("Edited table draft"),
      "The draft must come through the mounted Input binding")
    let revision = state.presentationRevision
    try sendAction(expectedCount: 1)
    let gridShort = frame(short), gridLong = frame(long)
    XCTAssertGreaterThan(gridLong.width, gridShort.width)
    XCTAssertEqual(gridShort.maxX, gridLong.maxX, accuracy: 1, "Numeric table cells share a trailing edge")
    XCTAssertGreaterThan(gridShort.minX, frame(input).maxX, "The numeric column must not overlap the input")
    XCTAssertGreaterThan(gridLong.minY, gridShort.maxY)

    for (index, reading) in [true, false].enumerated() {
      // Accessibility text sizes select row reading automatically, without a
      // second mode control or replacing the document and its mounted cells.
      typeSize.value = reading ? .accessibility1 : .large
      settle()
      XCTAssertEqual(inputs().count, 1)
      XCTAssertTrue(inputs().first === input, "Reading mode must retain the native editing field")
      XCTAssertTrue(try marker("short") === short, "Custom cell identity must survive both layout directions")
      XCTAssertTrue(try marker("long") === long)
      XCTAssertTrue(try marker("action") === action)
      XCTAssertEqual(input.stringValue, "Edited table draft")
      XCTAssertEqual(state.fieldValue(form: nil, name: "draft"), .string("Edited table draft"))
      XCTAssertEqual(short.stringValue, "12")
      XCTAssertEqual(long.stringValue, "123456")
      XCTAssertEqual(state.presentationRevision, revision, "Reading mode is presentation, not a new document")
      let currentShort = frame(short), currentLong = frame(long)
      for rect in [currentShort, currentLong, frame(input)] {
        XCTAssertTrue(rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite)
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
      }
      if reading {
        XCTAssertEqual(currentShort.minX, currentLong.minX, accuracy: 1)
        XCTAssertLessThan(currentShort.minX, gridShort.minX, "Accessibility text must actually switch to row reading")
        XCTAssertGreaterThan(currentShort.minY, frame(input).maxY, "Each value follows the previous cell vertically")
      } else {
        XCTAssertEqual(currentShort.maxX, currentLong.maxX, accuracy: 1)
        XCTAssertEqual(currentShort.maxX, gridShort.maxX, accuracy: 1)
        XCTAssertEqual(currentShort.minY, gridShort.minY, accuracy: 1)
      }
      try sendAction(expectedCount: index + 2)
    }
    typeSize.tableAppearance = OpenUITableAppearance(gridLine: .red, headerBackground: .blue, background: .white)
    settle()
    XCTAssertTrue(inputs().first === input, "Theme changes must preserve the mounted editing field")
    XCTAssertTrue(try marker("short") === short, "Theme changes must preserve mounted cells")
    XCTAssertEqual(state.fieldValue(form: nil, name: "draft"), .string("Edited table draft"))
    try sendAction(expectedCount: 4)
    typeSize.tableAppearance = nil
    settle()
    XCTAssertTrue(inputs().first === input, "Returning to the default theme must preserve the editing field")
    XCTAssertTrue(try marker("action") === action)
    try sendAction(expectedCount: 5)
  }

  @MainActor func testMountedSourceObservationDoesNotClearRejectedDraft() async throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema:library.library.toSchema())
    state.push("root=Stack([EditableTable(\"orders\",[{header:\"Name\",type:\"string\"}],[{id:\"r1\",values:[\"before\"]}]),TextContent(\"unfinished")
    let element = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
    let context = OpenUIComponentContext(element:element,registry:library.registry,state:state)
    let editing = NativeTableEditingState()
    let host = NSHostingView(rootView:NativeEditableTable(context:context,editing:editing).environmentObject(state).frame(width:350))
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:350,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
    window.contentView = host
    defer { window.contentView = nil }
    host.layoutSubtreeIfNeeded()
    for _ in 0..<30 where editing.draft.rows.isEmpty { try await Task.sleep(nanoseconds:10_000_000) }
    XCTAssertEqual(editing.draft.rows.count,1,"The actual view must mount and receive its initial source")
    editing.draft.write(.string("after"),row:0,column:0)
    // Simulate publication of a local field write whose later dispatch was
    // rejected. The view's real onChange handler must retain the old baseline.
    state.setFieldValue(form:"orders",name:"orders",value:editing.draft.value,componentType:"EditableTable")
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds:30_000_000)
    XCTAssertTrue(editing.draft.hasChanges)
    var received = 0
    state.onAction = {_ in received += 1}
    await editing.save(context:context,name:"orders",columns:1)
    await editing.save(context:context,name:"orders",columns:1)
    XCTAssertEqual(received,1)
    XCTAssertFalse(editing.draft.hasChanges)
  }

  @MainActor func testCompletedTableUpdatesMountedCellsAndShrinksItsVisibleRows() throws {
    _ = NSApplication.shared
    let standard = try OpenUIComponents.library()
    let customCell = OpenUIComponent(name: "MountedTableValue", description: "Mounted cell evidence",
      params: [OpenUIParameter.string("id"), OpenUIParameter.string("value")]) { context in
        MountedTableValue(id: context.string("id") ?? "", value: context.string("value") ?? "")
          .fixedSize()
      }
    let library = try standard.extending(adding: [customCell])
    let state = OpenUIState(schema: library.library.toSchema())
    defer { state.reset() }
    state.setSource("""
      $rows=[]
      root=Table([Col("Value",@Each($rows,row,MountedTableValue(row.id,row.value)))])
      """)
    func rows(_ count: Int, prefix: String) -> Value {
      .array((0..<count).map { index in
        .object([
          ObjectField(key: "id", value: .string("r\(index)")),
          ObjectField(key: "value", value: .string("\(prefix) \(index)")),
        ])
      })
    }
    state.setState("$rows", value: rows(12, prefix: "before"))
    XCTAssertTrue(state.isComplete)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let revision = state.presentationRevision
    let hosting = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .frame(width: 360).fixedSize(horizontal: false, vertical: true)
      .frame(width: 360, height: 700, alignment: .topLeading))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 700),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    window.orderFront(nil)
    defer { window.close() }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func cells() -> [NSTextField] {
      descendants(hosting).compactMap { $0 as? NSTextField }
        .filter { $0.identifier?.rawValue.hasPrefix("openui.test.table.") == true }
    }
    func cell(_ id: String) throws -> NSTextField {
      try XCTUnwrap(cells().first { $0.identifier?.rawValue == "openui.test.table.\(id)" })
    }
    func settle() {
      hosting.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      hosting.layoutSubtreeIfNeeded()
    }

    settle()
    XCTAssertEqual(cells().count, 10, "The initial table mounts only its first page")
    let first = try cell("r0")
    XCTAssertEqual(first.stringValue, "before 0")
    XCTAssertEqual(try cell("r9").stringValue, "before 9")

    state.setState("$rows", value: rows(12, prefix: "updated"))
    settle()
    XCTAssertTrue(try cell("r0") === first, "A completed table updates its existing cell")
    XCTAssertEqual(first.stringValue, "updated 0")
    XCTAssertEqual(try cell("r9").stringValue, "updated 9")
    XCTAssertEqual(cells().count, 10)

    state.setState("$rows", value: rows(2, prefix: "short"))
    settle()
    XCTAssertTrue(try cell("r0") === first)
    XCTAssertEqual(first.stringValue, "short 0")
    XCTAssertEqual(try cell("r1").stringValue, "short 1")
    XCTAssertEqual(cells().count, 2, "Row and pagination inputs must use the current columns")
    XCTAssertEqual(state.presentationRevision, revision)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")

    state.setSource(#"root=Table([Col("Replacement",[MountedTableValue("replacement","new document")])])"#)
    settle()
    XCTAssertEqual(cells().count, 1)
    XCTAssertEqual(try cell("replacement").stringValue, "new document")
    XCTAssertFalse(cells().contains { $0 === first }, "Replacing the source retires the old table contents")
  }
}

@MainActor private final class MountedTableTextSize: ObservableObject {
  @Published var value: DynamicTypeSize = .large
  @Published var tableAppearance: OpenUITableAppearance?
}

private struct MountedTableEnvironment<Content: View>: View {
  @ObservedObject var typeSize: MountedTableTextSize
  let content: Content
  var body: some View {
    var theme = OpenUIThemeValues()
    theme.tableAppearance = typeSize.tableAppearance
    return content.environment(\.dynamicTypeSize, typeSize.value).environment(\.openUITheme, theme)
  }
}

private struct MountedTableValue: NSViewRepresentable {
  let id: String
  let value: String
  func makeNSView(context: Context) -> NSTextField {
    let view = NSTextField(labelWithString: value)
    view.identifier = NSUserInterfaceItemIdentifier("openui.test.table.\(id)")
    view.font = .monospacedDigitSystemFont(ofSize: 16, weight: .regular)
    return view
  }
  func updateNSView(_ view: NSTextField, context: Context) { view.stringValue = value }
}

private final class MountedTableMarkerView: NSView {
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private struct MountedTableMarker: NSViewRepresentable {
  let id: String
  func makeNSView(context: Context) -> MountedTableMarkerView {
    let view = MountedTableMarkerView()
    view.identifier = NSUserInterfaceItemIdentifier("openui.test.table.\(id)")
    return view
  }
  func updateNSView(_ view: MountedTableMarkerView, context: Context) {}
}
#endif
