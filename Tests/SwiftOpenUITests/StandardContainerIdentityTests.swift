#if os(macOS)
import AppKit
import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class StandardContainerIdentityTests: XCTestCase {
  @MainActor func testStackAndCardKeepRegisteredChildIdentityAcrossReorderAndServerRefresh() throws {
    _ = NSApplication.shared
    for container in ["Stack", "Card"] {
      let log = ContainerIdentityLog()
      let probe = OpenUIComponent(name: "IdentityProbe", description: "Client-owned stable selection",
        params: [OpenUIParameter.string("selectedKey"), OpenUIParameter.string("id")]) { context in
          ContainerIdentityProbe(key: context.string("selectedKey") ?? "", record: context.string("id") ?? "", log: log)
            .frame(height: 24)
        }.presentation(identityFields: ["selectedKey"])
      let library = try OpenUIComponents.library().extending(adding: [probe])
      let state = OpenUIState(schema: library.library.toSchema())
      state.setSource("$items=[{selectedKey:\"a\",id:\"server-a\"},{selectedKey:\"b\",id:\"server-b\"}]\nroot=\(container)(@Each($items,\"item\",IdentityProbe(item.selectedKey,item.id)))")
      XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
      let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry).frame(width: 320))
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 400),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      window.setFrameOrigin(.init(x: -10000, y: -10000))
      window.orderFront(nil)
      defer { window.close() }
      func settle() {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
      }
      settle()
      let firstA = try XCTUnwrap(log.tokens["a"]), firstB = try XCTUnwrap(log.tokens["b"])
      func item(_ key: String, _ record: String) -> Value {
        .object([.init(key: "selectedKey", value: .string(OpenUIString(key))),
                 .init(key: "id", value: .string(OpenUIString(record)))])
      }
      state.setState("$items", value: .array([item("b", "server-b"), item("a", "server-a")]))
      settle()
      XCTAssertEqual(log.tokens["a"], firstA, "\(container) must retain the selected item's native view when reordered")
      XCTAssertEqual(log.tokens["b"], firstB)

      state.setState("$items", value: .array([item("b", "refreshed-b"), item("a", "refreshed-a")]))
      settle()
      XCTAssertEqual(log.tokens["a"], firstA, "The registered selection key takes precedence over a changing server id")
      XCTAssertEqual(log.tokens["b"], firstB)
      XCTAssertEqual(log.mounts, ["a": 1, "b": 1])
      XCTAssertEqual(log.records, ["a": "refreshed-a", "b": "refreshed-b"], "Existing views must still receive changed props")
    }
  }
}

@MainActor private final class ContainerIdentityLog {
  var tokens: [String: UUID] = [:]
  var mounts: [String: Int] = [:]
  var records: [String: String] = [:]
}

private final class ContainerIdentityView: NSView {
  let identity = UUID()
}

private struct ContainerIdentityProbe: NSViewRepresentable {
  let key: String
  let record: String
  let log: ContainerIdentityLog
  func makeNSView(context: Context) -> ContainerIdentityView {
    log.mounts[key, default: 0] += 1
    return ContainerIdentityView()
  }
  func updateNSView(_ view: ContainerIdentityView, context: Context) {
    log.tokens[key] = view.identity
    log.records[key] = record
  }
}
#endif
