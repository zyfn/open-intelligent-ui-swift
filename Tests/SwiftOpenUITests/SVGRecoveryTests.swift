import SwiftLang
#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class SVGRecoveryTests: XCTestCase {
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
    let point = host.convert(NSPoint(x: host.bounds.midX, y: host.bounds.midY), to: nil)
    let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
      windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
    NSApplication.shared.postEvent(up, atStart: false)
    window.sendEvent(down); window.sendEvent(up)
    await settle(.loaded)
    XCTAssertEqual(loader.requests.count, 2)
    XCTAssertEqual(loader.signatures, 2)
    XCTAssertNotEqual(loader.requests.first?.url, loader.requests.last?.url)
    XCTAssertEqual(loader.requests.last?.cachePolicy, .reloadIgnoringLocalCacheData)
    for _ in 0..<5 { _ = host.fittingSize; try await Task.sleep(nanoseconds: 10_000_000) }
    XCTAssertEqual(loader.signatures, 2, "Fitting a recovered SVG must not refresh its signature")
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
