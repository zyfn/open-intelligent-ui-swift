import Foundation
import XCTest
@testable import SwiftLang

final class NativeMediaRetryTests: XCTestCase {
  @MainActor private func key(_ loader: MediaRecoveryLoader, method: String = "GET") -> NativeResourceRequestID {
    var request = URLRequest(url: URL(string: "https://image.test/private?signature=frozen")!)
    request.httpMethod = method
    request.setValue("frozen-nonce", forHTTPHeaderField: "X-Nonce")
    return NativeResourceRequestID(request: request, loader: ObjectIdentifier(loader), attempt: 0,
      authorizationScope: loader.authorizationScopeID)
  }

  @MainActor func testConcurrentSubscribersShareTheEntireRecoveryAndCompletedImage() async throws {
    let cache = NativeMediaCache(), gate = MediaRecoveryGate()
    let firstStarted = expectation(description: "shared first transport")
    let loader = MediaRecoveryLoader { attempt, _ in
      if attempt == 1 {
        firstStarted.fulfill()
        try await gate.wait()
        throw URLError(.networkConnectionLost)
      }
      return mediaRecoveryPNG
    }
    let request = key(loader)
    let first = Task { try await cache.resource(request, loader: loader) }
    let second = Task { try await cache.resource(request, loader: loader) }
    defer { first.cancel(); second.cancel(); cache.removeAll() }
    await fulfillment(of: [firstStarted], timeout: 3)
    let joined = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      cache.pendingSubscriberCount == 2
    }, object: nil)
    await fulfillment(of: [joined], timeout: 3)
    await gate.open()
    let a = try await first.value, b = try await second.value
    XCTAssertGreaterThan(a.cost, 0)
    XCTAssertEqual(a.cost, b.cost)
    XCTAssertEqual(loader.requests.count, 2, "One pending decode owns the initial attempt and one recovery")
    XCTAssertTrue(loader.requests.allSatisfy { $0 == request.request }, "Both attempts keep the exact signed request")
    XCTAssertEqual(cache.pendingSubscriberCount, 0)
    _ = try await cache.resource(request, loader: loader)
    XCTAssertEqual(loader.requests.count, 2, "Recovery populates the same completed-image cache")
  }

  @MainActor func testCancellingOneSubscriberDoesNotRetireTheOthersRecovery() async throws {
    let cache = NativeMediaCache(), gate = MediaRecoveryGate()
    let firstStarted = expectation(description: "first transport")
    let firstFailed = expectation(description: "first transport failed")
    let loader = MediaRecoveryLoader { attempt, _ in
      if attempt == 1 {
        firstStarted.fulfill()
        try await gate.wait()
        firstFailed.fulfill()
        throw URLError(.timedOut)
      }
      return mediaRecoveryPNG
    }
    let request = key(loader)
    let first = Task { try await cache.resource(request, loader: loader) }
    let second = Task { try await cache.resource(request, loader: loader) }
    defer { first.cancel(); second.cancel(); cache.removeAll() }
    await fulfillment(of: [firstStarted], timeout: 3)
    let joined = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      cache.pendingSubscriberCount == 2
    }, object: nil)
    await fulfillment(of: [joined], timeout: 3)
    await gate.open()
    await fulfillment(of: [firstFailed], timeout: 3)
    first.cancel()
    do { _ = try await first.value; XCTFail("The cancelled subscriber cannot receive recovered pixels") }
    catch { XCTAssertTrue(error is CancellationError) }
    let image = try await second.value
    XCTAssertGreaterThan(image.cost, 0)
    XCTAssertEqual(loader.requests.count, 2)
    XCTAssertNotNil(cache[request])
    XCTAssertEqual(cache.pendingSubscriberCount, 0)
  }

  @MainActor func testLastSubscriberCancellationPreventsDelayedRecovery() async throws {
    let cache = NativeMediaCache()
    let failed = expectation(description: "initial failure")
    let unexpectedRetry = expectation(description: "no retry after the last subscriber exits")
    unexpectedRetry.isInverted = true
    let loader = MediaRecoveryLoader { attempt, _ in
      if attempt == 1 { failed.fulfill() }
      else { unexpectedRetry.fulfill() }
      throw URLError(.networkConnectionLost)
    }
    let request = key(loader)
    let task = Task { try await cache.resource(request, loader: loader) }
    defer { task.cancel(); cache.removeAll() }
    await fulfillment(of: [failed], timeout: 3)
    task.cancel()
    do { _ = try await task.value; XCTFail("The last subscriber must leave immediately") }
    catch { XCTAssertTrue(error is CancellationError) }
    await fulfillment(of: [unexpectedRetry], timeout: 0.6)
    XCTAssertEqual(loader.requests.count, 1)
    XCTAssertEqual(cache.pendingRequestCount, 0)
    XCTAssertNil(cache[request])
  }

  @MainActor func testResetAuthorizationAndPolicyChangesPreventRecoveryAndCacheFill() async throws {
    for retirement in 0..<3 {
      let cache = NativeMediaCache()
      let failed = expectation(description: "initial failure \(retirement)")
      let unexpectedRetry = expectation(description: "no retired retry \(retirement)")
      unexpectedRetry.isInverted = true
      let loader = MediaRecoveryLoader { attempt, _ in
        if attempt == 1 { failed.fulfill() }
        else { unexpectedRetry.fulfill() }
        throw URLError(.networkConnectionLost)
      }
      let request = key(loader)
      let task = Task { try await cache.resource(request, loader: loader) }
      await fulfillment(of: [failed], timeout: 3)
      switch retirement {
      case 0: cache.removeAll()
      case 1: loader.scope = "second-account"
      default: loader.limits.maximumResponseBytes = 1
      }
      do { _ = try await task.value; XCTFail("A retired lease cannot resume its old request") }
      catch { XCTAssertTrue(error is CancellationError) }
      await fulfillment(of: [unexpectedRetry], timeout: 0.6)
      XCTAssertEqual(loader.requests.count, 1)
      XCTAssertEqual(cache.pendingRequestCount, 0)
      XCTAssertNil(cache[request])
      task.cancel(); cache.removeAll()
    }
  }

  @MainActor func testResetDuringAnUncooperativeSecondAttemptCannotRefillCache() async throws {
    let cache = NativeMediaCache(), gate = MediaRecoveryGate()
    let secondStarted = expectation(description: "recovery transport started")
    let secondReturned = expectation(description: "retired transport returned")
    let loader = MediaRecoveryLoader { attempt, _ in
      if attempt == 1 { throw URLError(.networkConnectionLost) }
      secondStarted.fulfill()
      try await gate.wait(ignoringCancellation: true)
      secondReturned.fulfill()
      return mediaRecoveryPNG
    }
    let request = key(loader)
    let task = Task { try await cache.resource(request, loader: loader) }
    defer { task.cancel(); cache.removeAll() }
    await fulfillment(of: [secondStarted], timeout: 3)
    cache.removeAll()
    do { _ = try await task.value; XCTFail("Reset must release the subscriber before transport cooperates") }
    catch { XCTAssertTrue(error is CancellationError) }
    await gate.open()
    await fulfillment(of: [secondReturned], timeout: 3)
    // A subsequent load of this same key must fetch again. If the retired
    // operation refilled the cache it would skip this deliberate permanent error.
    loader.response = { _, _ in throw URLError(.cannotDecodeContentData) }
    do { _ = try await cache.resource(request, loader: loader); XCTFail("Old recovery pixels cannot become a cache hit") }
    catch { XCTAssertEqual((error as? URLError)?.code, .cannotDecodeContentData) }
    XCTAssertEqual(loader.requests.count, 3)
    XCTAssertNil(cache[request])
  }

  @MainActor func testPersistentTransientFailureStopsAtTwoActualTransportAttempts() async throws {
    let cache = NativeMediaCache()
    defer { cache.removeAll() }
    let loader = MediaRecoveryLoader { _, _ in throw URLError(.timedOut) }
    let request = key(loader)
    let task = Task { try await cache.resource(request, loader: loader) }
    let returned = expectation(description: "second failure ends recovery")
    let observer = Task { @MainActor in
      do { _ = try await task.value; XCTFail("The second failure must finish this operation") }
      catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
      returned.fulfill()
    }
    await fulfillment(of: [returned], timeout: 3)
    task.cancel() // Also release a regression that accidentally retries forever.
    await observer.value
    XCTAssertEqual(loader.requests.count, 2)
    XCTAssertEqual(cache.pendingRequestCount, 0)
  }

  @MainActor func testPermanentTransportBudgetAndDecodeFailuresDoNotRefetch() async throws {
    let codes: [URLError.Code] = [.dataLengthExceedsMaximum, .cannotDecodeContentData,
      .badURL, .unsupportedURL, .badServerResponse, .cancelled, .notConnectedToInternet]
    for code in codes {
      let cache = NativeMediaCache()
      let loader = MediaRecoveryLoader { _, _ in throw URLError(code) }
      do { _ = try await cache.resource(key(loader), loader: loader); XCTFail("A permanent error cannot produce pixels") }
      catch { XCTAssertEqual((error as? URLError)?.code, code) }
      XCTAssertEqual(loader.requests.count, 1, "Permanent error \(code) must not fetch again")
      cache.removeAll()
    }
    for exceedsBytes in [false, true] {
      let cache = NativeMediaCache()
      let loader = MediaRecoveryLoader { _, _ in exceedsBytes ? mediaRecoveryPNG : Data("not an image".utf8) }
      if exceedsBytes { loader.limits.maximumResponseBytes = 1 }
      let request = key(loader)
      do { _ = try await cache.resource(request, loader: loader); XCTFail("Invalid image bytes must be rejected") }
      catch {
        XCTAssertEqual((error as? URLError)?.code, .cannotDecodeContentData)
        if exceedsBytes {
          XCTAssertEqual((error as NSError).userInfo[NativeResourceError.stageKey] as? String, "responseBytes")
        }
      }
      XCTAssertEqual(loader.requests.count, 1)
      XCTAssertNil(cache[request])
      cache.removeAll()
    }
  }

  @MainActor func testHTTPRecoveryUsesTheSameBoundedImagePipeline() async throws {
    for status in [503, 401] {
      let cache = NativeMediaCache()
      let loader = MediaRecoveryLoader { attempt, request in
        if attempt == 1 {
          throw NativeResourceError.httpFailure(HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: nil)!)
        }
        return mediaRecoveryPNG
      }
      let request = key(loader)
      do {
        let entry = try await cache.resource(request, loader: loader)
        XCTAssertEqual(status, 503)
        XCTAssertGreaterThan(entry.cost, 0)
      } catch {
        XCTAssertEqual(status, 401)
        XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        XCTAssertEqual(NativeResourceError.httpStatus(for: error), status)
      }
      XCTAssertEqual(loader.requests.count, status == 503 ? 2 : 1)
      cache.removeAll()
    }
  }

  @MainActor func testRecoveryBackoffReleasesPipelinePermitsForOtherImages() async throws {
    let firstFailures = expectation(description: "two images entered recovery")
    firstFailures.expectedFulfillmentCount = 2
    let otherStarted = expectation(description: "another image can use the pipeline during backoff")
    let makeWaitingLoader = {
      MediaRecoveryLoader { attempt, request in
        if attempt == 1 { firstFailures.fulfill() }
        throw NativeResourceError.httpFailure(HTTPURLResponse(url: request.url!, statusCode: 503,
          httpVersion: nil, headerFields: ["Retry-After": "2"])!)
      }
    }
    let a = makeWaitingLoader(), b = makeWaitingLoader()
    let first = Task { try await NativeMediaCache.load(key(a).request!, loader: a) }
    let second = Task { try await NativeMediaCache.load(key(b).request!, loader: b) }
    defer { first.cancel(); second.cancel() }
    await fulfillment(of: [firstFailures], timeout: 3)
    let other = MediaRecoveryLoader { _, _ in otherStarted.fulfill(); return mediaRecoveryPNG }
    let third = Task { try await NativeMediaCache.load(key(other).request!, loader: other) }
    defer { third.cancel() }
    await fulfillment(of: [otherStarted], timeout: 1)
    // Release all tasks even if the permit assertion failed, so this test
    // cannot leave a global pipeline permit occupied for subsequent cases.
    first.cancel(); second.cancel()
    do { _ = try await first.value; XCTFail("Recovery should still have been waiting") }
    catch { XCTAssertTrue(error is CancellationError) }
    do { _ = try await second.value; XCTFail("Recovery should still have been waiting") }
    catch { XCTAssertTrue(error is CancellationError) }
    let image = try await third.value
    XCTAssertGreaterThan(image.cost, 0)
    XCTAssertEqual(a.requests.count, 1)
    XCTAssertEqual(b.requests.count, 1)
  }

  @MainActor func testTightenedLimitsInvalidateCompletedPixelsWithoutChangingRequestIdentity() async throws {
    let cache = NativeMediaCache()
    defer { cache.removeAll() }
    let loader = MediaRecoveryLoader { _, _ in mediaRecoveryPNG }
    let request = key(loader)
    _ = try await cache.resource(request, loader: loader)
    XCTAssertNotNil(cache[request])
    loader.limits.maximumResponseBytes = 1
    XCTAssertNil(cache[request], "Completed pixels retain the policy under which they were accepted")
    do { _ = try await cache.resource(request, loader: loader); XCTFail("A tighter policy must be checked on the same URL") }
    catch { XCTAssertEqual((error as? URLError)?.code, .cannotDecodeContentData) }
    XCTAssertEqual(loader.requests.count, 2)
    XCTAssertNil(cache[request])
  }

  @MainActor func testChangedLimitsDoNotJoinAnOlderPendingDecode() async throws {
    let cache = NativeMediaCache(), gate = MediaRecoveryGate()
    let started = expectation(description: "old-policy transport")
    let loader = MediaRecoveryLoader { attempt, _ in
      if attempt == 1 { started.fulfill(); try await gate.wait() }
      return mediaRecoveryPNG
    }
    let request = key(loader)
    let original = Task { try await cache.resource(request, loader: loader) }
    defer { original.cancel(); cache.removeAll() }
    await fulfillment(of: [started], timeout: 3)
    loader.limits.maximumResponseBytes = 1
    let current = Task { try await cache.resource(request, loader: loader) }
    defer { current.cancel() }
    let returned = expectation(description: "new-policy request finishes independently")
    let observer = Task { @MainActor in
      do { _ = try await current.value; XCTFail("The new-policy request must validate its own bytes") }
      catch { XCTAssertEqual((error as? URLError)?.code, .cannotDecodeContentData) }
      returned.fulfill()
    }
    await fulfillment(of: [returned], timeout: 3)
    XCTAssertEqual(loader.requests.count, 2, "The stricter subscriber cannot join work with an older policy")
    await gate.open()
    await observer.value
    do { _ = try await original.value; XCTFail("The original policy lease was retired") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertNil(cache[request])
  }

  func testRecoveryRequiresSafeMethodKnownStatusAndShortRetryAfter() throws {
    let url = try XCTUnwrap(URL(string: "https://image.test/photo.png"))
    var request = URLRequest(url: url)
    func failure(_ status: Int, retryAfter: String? = nil) throws -> URLError {
      NativeResourceError.httpFailure(try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status,
        httpVersion: nil, headerFields: retryAfter.map { ["Retry-After": $0] })))
    }
    for status in [408, 429, 500, 502, 503, 504] {
      XCTAssertNotNil(NativeMediaRetry.delay(after: try failure(status), request: request))
    }
    for status in [301, 400, 401, 403, 404, 410, 501] {
      XCTAssertNil(NativeMediaRetry.delay(after: try failure(status), request: request))
    }
    XCTAssertEqual(NativeMediaRetry.delay(after: try failure(429, retryAfter: "1"), request: request), 1_000_000_000)
    for value in ["30", "-1", "invalid"] {
      XCTAssertNil(NativeMediaRetry.delay(after: try failure(503, retryAfter: value), request: request))
    }
    request.httpMethod = "HEAD"
    XCTAssertNotNil(NativeMediaRetry.delay(after: URLError(.timedOut), request: request))
    request.httpMethod = "POST"
    XCTAssertNil(NativeMediaRetry.delay(after: URLError(.timedOut), request: request))
    XCTAssertNil(NativeMediaRetry.delay(after: try failure(503), request: request))
  }

  func testDiagnosticStageNeverExposesAnArbitraryLoaderString() {
    let sensitive = URLError(.cannotDecodeContentData, userInfo: [
      NativeResourceError.stageKey: "https://private.test/image?signature=secret"
    ])
    XCTAssertEqual(NativeMediaRetry.stage(for: sensitive), "transportOrDecode")
    for stage in ["httpStatus", "responseBytes", "imageSourcePixels", "decodedImageBytes"] {
      XCTAssertEqual(NativeMediaRetry.stage(for: URLError(.badServerResponse,
        userInfo: [NativeResourceError.stageKey: stage])), stage)
    }
  }
}

private let mediaRecoveryPNG = Data(base64Encoded:
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!

private final class MediaRecoveryLoader: OpenUIResourceLoading, @unchecked Sendable {
  typealias Response = (Int, URLRequest) async throws -> Data
  private let lock = NSLock()
  private var recorded: [URLRequest] = []
  private var currentScope = "first-account"
  private var currentLimits = OpenUIResourceLimits()
  private var currentResponse: Response

  init(response: @escaping Response) { currentResponse = response }
  var response: Response {
    get { lock.lock(); defer { lock.unlock() }; return currentResponse }
    set { lock.lock(); currentResponse = newValue; lock.unlock() }
  }
  var scope: String {
    get { lock.lock(); defer { lock.unlock() }; return currentScope }
    set { lock.lock(); currentScope = newValue; lock.unlock() }
  }
  var limits: OpenUIResourceLimits {
    get { lock.lock(); defer { lock.unlock() }; return currentLimits }
    set { lock.lock(); currentLimits = newValue; lock.unlock() }
  }
  var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
  var authorizationScopeID: String { scope }
  var resourceLimits: OpenUIResourceLimits { limits }
  func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
    URL(string: source, relativeTo: baseURL).map { URLRequest(url: $0) }
  }
  private func record(_ request: URLRequest) -> (Int, Response) {
    lock.lock(); defer { lock.unlock() }
    recorded.append(request)
    return (recorded.count, currentResponse)
  }
  func data(for request: URLRequest) async throws -> Data {
    let (attempt, response) = record(request)
    return try await response(attempt, request)
  }
}

private actor MediaRecoveryGate {
  private var opened = false
  private var pending: [UUID: CheckedContinuation<Void, Error>] = [:]
  func wait(ignoringCancellation: Bool = false) async throws {
    if opened { return }
    let id = UUID()
    try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in
        if opened { continuation.resume() }
        else if Task.isCancelled && !ignoringCancellation { continuation.resume(throwing: CancellationError()) }
        else { pending[id] = continuation }
      }
    }, onCancel: {
      if !ignoringCancellation { Task { await self.cancel(id) } }
    })
  }
  private func cancel(_ id: UUID) { pending.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
  func open() {
    opened = true
    let waiting = Array(pending.values); pending.removeAll()
    for continuation in waiting { continuation.resume() }
  }
}
