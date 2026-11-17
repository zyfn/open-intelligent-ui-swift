import Foundation
import SwiftLang
import XCTest
@testable import SwiftOpenUI
#if os(macOS)
import AppKit
import SwiftUI
#endif

final class NativeMediaResourceTests: XCTestCase {
  @MainActor func testCanonicallyEquivalentSourceSpellingsKeepTheirExactResourceIdentity() {
    let loader = NonceMediaResourceLoader()
    let resources = OpenUIResourceContext(loader: loader)
    let cache = NativeMediaCache()
    let composed = "https://assets.test/\u{00E9}.png"
    let decomposed = "https://assets.test/e\u{0301}.png"
    XCTAssertEqual(composed, decomposed, "Swift's display-string equality must not define resource identity")
    let first = NativeMediaResourceTarget(source: composed, resources: resources)
    let second = NativeMediaResourceTarget(source: decomposed, resources: resources)
    XCTAssertNotEqual(first, second)
    XCTAssertEqual(Set([first, second]).count, 2)
    let a = NativeMediaRequestSnapshot(target: first, cache: cache)
    let b = NativeMediaRequestSnapshot(target: second, cache: cache)
    XCTAssertEqual(loader.signingCount, 2, "The host signer receives both exact source spellings")
    XCTAssertEqual(loader.sources, [OpenUIString(composed), OpenUIString(decomposed)])
    XCTAssertNotEqual(a.request.request?.url, b.request.request?.url)
    XCTAssertFalse(a.matches(second, cache: cache))
  }

  @MainActor func testStableTargetsFreezeFullSignedRequestsUntilAnExplicitRetry() throws {
    let loader = NonceMediaResourceLoader()
    let resources = OpenUIResourceContext(baseURL: URL(string: "https://assets.test/folder/"), loader: loader)
    let cache = NativeMediaCache()
    let target = NativeMediaResourceTarget(source: "photo.png", resources: resources)
    let sameTarget = NativeMediaResourceTarget(source: "photo.png", resources: resources)
    XCTAssertEqual(target, sameTarget)
    XCTAssertNil(target.cachedRequest(in: cache))
    XCTAssertEqual(loader.signingCount, 0, "Presentation identity and cache reads must not invoke the signer")

    let first = NativeMediaRequestSnapshot(target: target, cache: cache)
    let relocated = NativeMediaRequestSnapshot(target: sameTarget, cache: cache)
    XCTAssertEqual(loader.signingCount, 1, "A layout relocation reuses the frozen signed request")
    XCTAssertEqual(first.request, relocated.request)
    XCTAssertEqual(first.request.request?.url?.path, "/folder/photo.png")
    XCTAssertEqual(first.request.request?.value(forHTTPHeaderField: "X-Nonce"), "1")
    XCTAssertTrue(first.matches(sameTarget, cache: cache))

    let retryTarget = NativeMediaResourceTarget(source: "photo.png", resources: resources, attempt: 1)
    let retry = NativeMediaRequestSnapshot(target: retryTarget, cache: cache)
    XCTAssertEqual(loader.signingCount, 2)
    XCTAssertNotEqual(first.request.request?.url, retry.request.request?.url)
    XCTAssertEqual(retry.request.request?.value(forHTTPHeaderField: "X-Nonce"), "2")
    XCTAssertEqual(retry.request.request?.cachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertFalse(first.matches(retryTarget, cache: cache))

    cache.removeAll()
    XCTAssertFalse(first.matches(target, cache: cache), "A removed document cannot revive a mounted request snapshot")
    XCTAssertNil(target.cachedRequest(in: cache))
    let replacement = NativeMediaRequestSnapshot(target: target, cache: cache)
    XCTAssertEqual(loader.signingCount, 3)
    XCTAssertNotEqual(first.request, replacement.request)
  }

  @MainActor func testAuthorizationOwnerAndBaseURLArePartOfTheFrozenTarget() throws {
    let loader = NonceMediaResourceLoader()
    let resources = OpenUIResourceContext(baseURL: URL(string: "https://assets.test/a/"), loader: loader)
    let cache = NativeMediaCache()
    let first = NativeMediaResourceTarget(source: "photo.png", resources: resources)
    let snapshot = NativeMediaRequestSnapshot(target: first, cache: cache)
    loader.scope = "second-account"
    XCTAssertFalse(first.isCurrent)
    XCTAssertNil(first.cachedRequest(in: cache))
    XCTAssertFalse(snapshot.matches(first, cache: cache))

    let otherScope = NativeMediaResourceTarget(source: "photo.png", resources: resources)
    XCTAssertNotEqual(first, otherScope)
    let scoped = NativeMediaRequestSnapshot(target: otherScope, cache: cache)
    XCTAssertEqual(scoped.request.request?.value(forHTTPHeaderField: "X-Scope"), "second-account")
    XCTAssertEqual(loader.signingCount, 2)

    let otherBase = NativeMediaResourceTarget(source: "photo.png", resources:
      OpenUIResourceContext(baseURL: URL(string: "https://assets.test/b/"), loader: loader))
    XCTAssertNotEqual(otherScope, otherBase)
    let moved = NativeMediaRequestSnapshot(target: otherBase, cache: cache)
    XCTAssertEqual(moved.request.request?.url?.path, "/b/photo.png")
    XCTAssertEqual(loader.signingCount, 3)

    let replacementLoader = NonceMediaResourceLoader()
    let otherOwner = NativeMediaResourceTarget(source: "photo.png", resources:
      OpenUIResourceContext(baseURL: resources.baseURL, loader: replacementLoader))
    XCTAssertNotEqual(first, otherOwner)
    let owned = NativeMediaRequestSnapshot(target: otherOwner, cache: cache)
    XCTAssertNotEqual(snapshot.request.loader, owned.request.loader)
    XCTAssertEqual(replacementLoader.signingCount, 1)
  }

  @MainActor func testRequestSnapshotsRetainOwnersOnlyWithinTheBoundedDocumentCache() {
    let cache = NativeMediaCache()
    weak var retainedOwner: NonceMediaResourceLoader?
    func populate() {
      let loader = NonceMediaResourceLoader()
      retainedOwner = loader
      let target = NativeMediaResourceTarget(source: "https://assets.test/photo.png",
        resources: OpenUIResourceContext(loader: loader))
      _ = NativeMediaRequestSnapshot(target: target, cache: cache)
    }
    populate()
    XCTAssertNotNil(retainedOwner, "The request identity must keep its loader alive against ObjectIdentifier reuse")
    cache.removeAll()
    XCTAssertNil(retainedOwner, "Reset releases request-only owners as well as decoded entries")

    let loader = NonceMediaResourceLoader()
    let resources = OpenUIResourceContext(loader: loader)
    let first = NativeMediaResourceTarget(source: "https://assets.test/0.png", resources: resources)
    for index in 0..<33 {
      let target = NativeMediaResourceTarget(source: "https://assets.test/\(index).png", resources: resources)
      _ = NativeMediaRequestSnapshot(target: target, cache: cache)
    }
    XCTAssertNil(first.cachedRequest(in: cache), "Request-only targets cannot grow without a bound")
    XCTAssertEqual(loader.signingCount, 33)
  }

  @MainActor func testTransientFailureRetriesTheFrozenRequestOnceWithoutResigning() async throws {
    let loader = NonceMediaResourceLoader()
    let cache = NativeMediaCache()
    defer { cache.removeAll() }
    let target = NativeMediaResourceTarget(source: "https://assets.test/photo.png",
      resources: .init(loader: loader))
    let snapshot = NativeMediaRequestSnapshot(target: target, cache: cache)
    var requests: [URLRequest] = []
    loader.response = { request in
      requests.append(request)
      if requests.count == 1 { throw URLError(.networkConnectionLost) }
      return Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
    }
    let image = try await cache.resource(snapshot.request, loader: loader)
    XCTAssertGreaterThan(image.cost, 0)
    XCTAssertEqual(requests.count, 2)
    XCTAssertTrue(requests.allSatisfy { $0 == snapshot.request.request })
    XCTAssertEqual(loader.signingCount, 1, "Automatic recovery preserves the frozen host signature")
    XCTAssertEqual(target.cachedRequest(in: cache), snapshot.request)
  }

  #if os(macOS)
  @MainActor func testInterruptedSVGWithAnUnclosedSourceReplacesLoadingWithReadableFallback() async throws {
    _ = NativeAccessibilityTestSupport.application
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    let loader = NonceMediaResourceLoader()
    let alternative = "The complete alternative description remains available when this diagram source is interrupted before its address is complete. It explains the result even though the graphic could not arrive."
    state.push("root=SVG(null,source,\"\(alternative)\")\nsource=\"https://assets.test/incomplete.svg")
    XCTAssertNotNil(state.root)
    XCTAssertFalse(state.root?.sourceReadiness["src"].complete ?? true)
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUIResourceContext(OpenUIResourceContext(loader: loader)).frame(width: 240))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 300),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    try await NativeAccessibilityTestSupport.activate(in: host)
    var graphicCandidates: [String] = []
    func graphicAccessibility() -> (label: String, value: String)? {
      var matches: [(label: String, value: String)] = []
      graphicCandidates.removeAll(keepingCapacity: true)
      for element in NativeAccessibilityTestSupport.elements(in: host) {
        guard let label = NativeAccessibilityTestSupport.stringAttribute("accessibilityLabel", of: element),
          label == alternative else { continue }
        let value = NativeAccessibilityTestSupport.stringAttribute("accessibilityValue", of: element)
        let role = NativeAccessibilityTestSupport.stringAttribute("accessibilityRole", of: element)
        let description = NativeAccessibilityTestSupport.stringAttribute("accessibilityValueDescription", of: element)
        graphicCandidates.append("\(String(reflecting: type(of: element))) role=\(String(describing: role)) value=\(String(describing: value)) valueDescription=\(String(describing: description))")
        matches.append((label, NativeAccessibilityTestSupport.readableValue(of: element) ?? ""))
      }
      // A native wrapper can inherit its only child's label while the virtual
      // semantic child owns the value. Inspect all matching nodes before
      // selecting a value; never select by the expected loading/error text.
      return matches.first { !$0.value.isEmpty } ?? matches.first
    }
    let loading = NSLocalizedString("Loading", bundle: NativeControlResources.bundle, comment: "")
    let unavailable = NSLocalizedString("Unable to load graphic", bundle: NativeControlResources.bundle, comment: "")
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 50_000_000)
    let loadingHeight = host.fittingSize.height
    let loadingAccessibility = graphicAccessibility()
    print("SVG loading accessibility: \(graphicCandidates)")
    XCTAssertEqual(loadingAccessibility?.label, alternative, "\(graphicCandidates)")
    XCTAssertEqual(loadingAccessibility?.value, loading, "\(graphicCandidates)")
    XCTAssertEqual(loader.signingCount, 0, "An unclosed source cannot start an SVG resource request")

    state.interrupt()
    let deadline = Date().addingTimeInterval(2)
    repeat {
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(nanoseconds: 20_000_000)
    } while graphicAccessibility()?.value != unavailable && Date() < deadline
    XCTAssertTrue(state.isInterrupted)
    // The quiet-placeholder contract restored by 433c2ed keeps the
    // graphic's frame and exposes its complete alternative through accessibility.
    // Visible multiline failure copy is no longer part of this presentation.
    XCTAssertEqual(host.fittingSize.height, loadingHeight, accuracy: 1,
      "A terminal graphic state must preserve its reserved frame")
    let unavailableAccessibility = graphicAccessibility()
    print("SVG interrupted accessibility: \(graphicCandidates)")
    XCTAssertEqual(unavailableAccessibility?.label, alternative,
      "The complete authored alternative remains readable after interruption; \(graphicCandidates)")
    XCTAssertEqual(unavailableAccessibility?.value, unavailable,
      "The mounted graphic must stop announcing a load after its stream is interrupted; \(graphicCandidates)")
    XCTAssertEqual(loader.signingCount, 0, "Stopping an incomplete stream must not submit its partial address")
  }
  #endif
}

private final class NonceMediaResourceLoader: OpenUIResourceLoading {
  var scope = "first-account"
  private(set) var signingCount = 0
  private(set) var sources: [OpenUIString] = []
  var authorizationScopeID: String { scope }
  var response: ((URLRequest) async throws -> Data)?

  func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
    signingCount += 1
    sources.append(OpenUIString(source))
    guard let url = URL(string: source, relativeTo: baseURL)?.absoluteURL,
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "nonce", value: String(signingCount))]
    guard let signed = components.url else { return nil }
    var request = URLRequest(url: signed)
    request.setValue(String(signingCount), forHTTPHeaderField: "X-Nonce")
    request.setValue(scope, forHTTPHeaderField: "X-Scope")
    return request
  }
  func data(for request: URLRequest) async throws -> Data {
    if let response { return try await response(request) }
    return Data()
  }
}
