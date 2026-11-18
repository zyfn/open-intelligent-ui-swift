import SwiftLang
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class MapDetailPresentationTests: XCTestCase {
  @MainActor func testMountedMapRequestsACommittedPhotoWhileOtherPlacesAreStreaming() async throws {
    guard #available(macOS 14, *) else { throw XCTSkip("Native Map requires macOS 14") }
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=Stack([trip])\ntrip=Map([a,b])\na=MapPoint(\"A\",30,120,\"https://map.test/pho")
    let photo = expectation(description: "First photo requested before the first description or the second place is complete")
    let loader = MapDetailImageLoader { if $0 == "/photo.jpg" { photo.fulfill() } }
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUIResourceContext(.init(loader: loader)).frame(width: 350, height: 360))
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 350, height: 360),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertTrue(loader.paths.isEmpty, "An unfinished image URL must never be requested")
    state.push("to.jpg\",null,\"Still arriving")
    await fulfillment(of: [photo], timeout: 3)
    XCTAssertEqual(loader.paths, ["/photo.jpg"])
    XCTAssertFalse(state.isComplete)
    state.interrupt()
  }

  @MainActor func testSelectionBindingControlsCardsAndUnboundMapShowsFirstPlace() async throws {
    guard #available(macOS 14, *) else { throw XCTSkip("Native Map requires macOS 14") }
    _ = NSApplication.shared
    let standard = try OpenUIComponents.library()
    // Exercise the existing opt-in binding support without changing Map's
    // public points/crs contract or adding parameters to the SDK catalog.
    let replacements = OpenUIComponents.components.compactMap { component -> OpenUIComponent? in
      guard ["Map", "MapPoint"].contains(component.definition.name) else { return nil }
      var definition = component.definition
      definition.params.append(definition.name == "MapPoint"
        ? OpenUIParameter.string("id", required: false)
        : OpenUIParameter.selection("value", required: false))
      return component.replacingDefinition(definition)
    }
    let library = try standard.extending(overriding: replacements)
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("""
      $choice=null
      $alternate=false
      $photo="https://map.test/c"
      a=MapPoint("A",30,120,"https://map.test/a",null,null,"a")
      b=MapPoint("B",31,121,"https://map.test/b",null,null,"b")
      c=MapPoint("C",32,122,$photo,null,null,"c")
      root=Map($alternate ? [c] : [a,b],"wgs84",$choice)
      """)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let selectedB = expectation(description: "Explicitly selected B mounts its artwork")
    let selectedC = expectation(description: "Explicitly selected C mounts its artwork")
    let defaultPlace = expectation(description: "An unbound map mounts its first place card")
    let loader = MapDetailImageLoader { path in
      if path == "/b" { selectedB.fulfill() }
      if path == "/c" { selectedC.fulfill() }
      if path == "/unbound" { defaultPlace.fulfill() }
    }
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUIResourceContext(.init(loader: loader)).frame(width: 350, height: 360))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 360),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    func settle() async throws {
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(nanoseconds: 200_000_000)
      host.layoutSubtreeIfNeeded()
    }
    try await settle()
    XCTAssertTrue(loader.paths.isEmpty, "An explicit null selection must not mount an arbitrary place card")

    state.setState("$choice", value: .string("b"))
    await fulfillment(of: [selectedB], timeout: 3)
    try await settle()
    XCTAssertEqual(state.stateValue("$choice"), .string("b"),
      "Mounting the carousel must preserve the chosen point rather than select page one")

    state.setState("$alternate", value: .boolean(true))
    try await settle()
    XCTAssertFalse(loader.paths.contains("/c"), "Removing the selected point returns to overview")
    XCTAssertEqual(state.stateValue("$choice"), .string("b"), "Presentation must not rewrite the host binding")

    state.setState("$choice", value: .string("c"))
    await fulfillment(of: [selectedC], timeout: 3)
    state.setState("$choice", value: .null)
    state.setState("$photo", value: .string("https://map.test/cleared"))
    try await settle()
    XCTAssertFalse(loader.paths.contains("/cleared"), "Clearing the binding must retire the detail card")

    state.setSource("root=Map([MapPoint(\"D\",33,123,\"https://map.test/unbound\")])")
    await fulfillment(of: [defaultPlace], timeout: 3)
  }
}

private final class MapDetailImageLoader: OpenUIResourceLoading {
  private let lock = NSLock()
  private var requestedPaths = Set<String>()
  private let onFirstLoad: (String) -> Void
  init(onFirstLoad: @escaping (String) -> Void) { self.onFirstLoad = onFirstLoad }
  var paths: Set<String> { lock.lock(); defer { lock.unlock() }; return requestedPaths }
  func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
    OpenUIURLSessionResourceLoader.shared.request(for: source, relativeTo: baseURL)
  }
  private func record(_ path: String) {
    lock.lock(); let inserted = requestedPaths.insert(path).inserted; lock.unlock()
    if inserted { onFirstLoad(path) }
  }
  func data(for request: URLRequest) async throws -> Data {
    record(request.url?.path ?? "")
    throw URLError(.resourceUnavailable)
  }
}
#endif
