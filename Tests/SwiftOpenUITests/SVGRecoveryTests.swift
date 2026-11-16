import SwiftLang
#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import WebKit
import XCTest
@testable import SwiftOpenUI

final class SVGRecoveryTests: XCTestCase {
  @MainActor func testGraphicTapOpensPreviewWithoutFooterAndRespectsReadingDrag() async throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("root=SVG(\"<svg viewBox='0 0 200 100'><rect width='200' height='100'/></svg>\",null,\"Diagram\")")
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.registry, state: state)
    var time: TimeInterval = 0
    let intent = NativeActivationIntent(now: { time })
    let host = NSHostingView(rootView: NativeSVG(context: context)
      .environment(\.openUIActivationIntent, intent)
      .frame(width: 320).fixedSize(horizontal: false, vertical: true))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer {
      if let sheet = window.attachedSheet { window.endSheet(sheet) }
      window.close()
    }
    let web = try await loadedWebView(in: host)
    host.layoutSubtreeIfNeeded()
    XCTAssertEqual(host.fittingSize.height, 160, accuracy: 1,
      "The SVG reserves only its viewBox height, without a separate expand row")

    intent.moved()
    try clickCenter(of: host, in: window)
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertNil(window.attachedSheet, "A reading drag must not open the graphic")
    intent.ended(); time = 1
    try clickCenter(of: host, in: window)
    for _ in 0..<300 {
      if window.attachedSheet != nil { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertNotNil(window.attachedSheet, "Tapping the loaded graphic opens its existing preview")
    XCTAssertTrue(webViews(in: host).first === web, "Preview activation must retain the inline WebView")
  }

  @MainActor func testActionCardGraphicRetriesFailureThenPreservesItsPrimaryTap() async throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("root=SVG(null,\"https://signed.test/graphic.svg\",\"Diagram\")")
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.registry, state: state)
    let loader = SVGRecoveryLoader()
    let log = SVGRecoveryLog()
    var actions: [ActionEvent] = []
    state.onAction = { actions.append($0) }
    let host = NSHostingView(rootView: OpenUIActionSurface(
      context: context, action: OpenUIActions.continueConversation("Open diagram card")
    ) {
      NativeSVG(context: context, onResourceStatus: { log.status = $0 })
    }.environmentObject(state).openUIResourceContext(.init(loader: loader)).frame(width: 320))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer {
      if let sheet = window.attachedSheet { window.endSheet(sheet) }
      window.close()
    }
    for _ in 0..<300 {
      host.layoutSubtreeIfNeeded()
      if log.status == .unavailable { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(log.status, .unavailable)
    host.layoutSubtreeIfNeeded()
    try clickCenter(of: host, in: window)
    let web = try await loadedWebView(in: host)
    XCTAssertEqual(loader.requests.count, 2, "The failed graphic retries without a nested button")
    XCTAssertTrue(actions.isEmpty, "Retrying the graphic must not dispatch the card action")

    try clickCenter(of: host, in: window)
    for _ in 0..<300 {
      if !actions.isEmpty { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(actions.count, 1, "The loaded graphic leaves the primary tap to its action card")
    XCTAssertNil(window.attachedSheet, "Action-card preview is available through touch and hold or accessibility")
    XCTAssertTrue(webViews(in: host).first === web)
  }

  @MainActor func testUnexpectedTransportCancellationCanRetryTheSameSignedSource() async throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("root=SVG(null,\"https://signed.test/graphic.svg\",\"Diagram\")")
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.registry, state: state)
    let loader = SVGRecoveryLoader()
    let log = SVGRecoveryLog()
    var presentation = OpenUIPresentation()
    presentation.minimumControlTargetSize = 44
    let host = NSHostingView(rootView: NativeSVG(context: context, onResourceStatus: { log.status = $0 })
      .openUIResourceContext(.init(loader: loader)).openUIPresentation(presentation)
      .frame(width: 320))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    func settle(_ status: NativeMediaStatus) async {
      for _ in 0..<300 {
        host.layoutSubtreeIfNeeded()
        if log.status == status { return }
        try? await Task.sleep(nanoseconds: 10_000_000)
      }
      XCTAssertEqual(log.status, status)
    }
    await settle(.unavailable)
    XCTAssertEqual(loader.requests.count, 1, "A transport's CancellationError must terminate the loading state")

    // The whole reserved graphic is the retry target; no separate error stack
    // or small Retry control is needed to recover the signed resource.
    host.layoutSubtreeIfNeeded()
    try clickCenter(of: host, in: window)
    await settle(.loaded)
    XCTAssertEqual(loader.requests.count, 2)
    XCTAssertEqual(loader.signatures, 2)
    XCTAssertNotEqual(loader.requests.first?.url, loader.requests.last?.url)
    XCTAssertEqual(loader.requests.last?.cachePolicy, .reloadIgnoringLocalCacheData)
    for _ in 0..<5 { _ = host.fittingSize; try await Task.sleep(nanoseconds: 10_000_000) }
    XCTAssertEqual(loader.signatures, 2, "Fitting a recovered SVG must not refresh its signature")
  }

  @MainActor private func clickCenter(of host: NSView, in window: NSWindow) throws {
    let point = host.convert(NSPoint(x: host.bounds.midX, y: host.bounds.midY), to: nil)
    let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
      windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
    NSApplication.shared.postEvent(up, atStart: false)
    window.sendEvent(down); window.sendEvent(up)
  }

  @MainActor private func webViews(in view: NSView) -> [WKWebView] {
    (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap { webViews(in: $0) }
  }

  @MainActor private func loadedWebView(in host: NSView) async throws -> WKWebView {
    for _ in 0..<300 {
      host.layoutSubtreeIfNeeded()
      if let web = webViews(in: host).first, web.url != nil, !web.isLoading { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let web = try XCTUnwrap(webViews(in: host).first)
    XCTAssertNotNil(web.url)
    XCTAssertFalse(web.isLoading)
    try await Task.sleep(nanoseconds: 50_000_000)
    host.layoutSubtreeIfNeeded()
    return web
  }
}

@MainActor private final class SVGRecoveryLog { var status: NativeMediaStatus? }

private final class SVGRecoveryLoader: OpenUIResourceLoading {
  private let lock = NSLock()
  private var resolved = 0
  private var sent: [URLRequest] = []
  var signatures: Int { lock.lock(); defer { lock.unlock() }; return resolved }
  var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return sent }
  func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
    guard var parts = URLComponents(string: source) else { return nil }
    lock.lock(); resolved += 1; let nonce = resolved; lock.unlock()
    parts.queryItems = [URLQueryItem(name: "nonce", value: String(nonce))]
    return parts.url.map { URLRequest(url: $0) }
  }
  private func record(_ request: URLRequest) -> Int {
    lock.lock(); defer { lock.unlock() }; sent.append(request); return sent.count
  }
  func data(for request: URLRequest) async throws -> Data {
    if record(request) == 1 { throw CancellationError() }
    return Data(#"<svg viewBox="0 0 100 50"><rect width="100" height="50"/></svg>"#.utf8)
  }
}
#endif
