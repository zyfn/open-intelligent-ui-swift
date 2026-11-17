import CoreGraphics
import Foundation
import ImageIO
import SwiftLang
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import SwiftOpenUI
#if os(macOS)
import AppKit
#endif

final class NativeImageSizingTests: XCTestCase {
  func testDisplayRequirementsTrackScaleAndIgnoreSmallLayoutChanges() throws {
    let card = CGSize(width: 400, height: 225)
    let two = try XCTUnwrap(NativeMediaPreview.displaySize(viewport: card, scale: 2, mode: .fill))
    let three = try XCTUnwrap(NativeMediaPreview.displaySize(viewport: card, scale: 3, mode: .fill))
    let source = CGSize(width: 2560, height: 1440)
    XCTAssertEqual(three.pixelSize(sourceSize: source, maximum: 2048), 1280)
    XCTAssertGreaterThanOrEqual(two.pixelSize(sourceSize: source, maximum: 2048), 800)
    XCTAssertLessThan(two.pixelSize(sourceSize: source, maximum: 2048), 1280)
    XCTAssertEqual(
      NativeMediaPreview.displaySize(viewport: CGSize(width: 400.1, height: 225.1), scale: 3, mode: .fill),
      NativeMediaPreview.displaySize(viewport: CGSize(width: 400.2, height: 225.2), scale: 3, mode: .fill))
    XCTAssertNil(NativeMediaPreview.displaySize(viewport: .zero, scale: 3, mode: .fill))
    XCTAssertNil(NativeMediaPreview.displaySize(viewport: CGSize(width: CGFloat.infinity, height: 100), scale: 3, mode: .fill))
    XCTAssertNil(NativeMediaPreview.displaySize(viewport: CGSize(width: 400, height: 0), scale: 3, mode: .fit))
    XCTAssertNil(NativeMediaPreview.displaySize(viewport: card, scale: .nan, mode: .fill))
  }

  @MainActor func testCardDecodesDisplayPixelsInOnePassAndRetainsOriginalGeometry() async throws {
    let data = try imageData(width: 2560, height: 1440)
    let loader = SizedImageLoader(data: data)
    let target = try XCTUnwrap(NativeMediaPreview.displaySize(
      viewport: CGSize(width: 400, height: 225), scale: 3, mode: .fill))
    let entry = try await NativeMediaCache.prepare(data, loader: loader, displaySize: target)
    XCTAssertEqual(entry.size, CGSize(width: 2560, height: 1440))
    XCTAssertEqual(entry.decodedPixelSize, 1280)
    XCTAssertLessThan(entry.cost, 4 * 1024 * 1024,
      "A phone card should not retain the default 2048-pixel image buffer")
    XCTAssertTrue(entry.satisfies(2048, displaySize: target))
    XCTAssertFalse(entry.satisfies(2048), "Inline pixels are not an already-complete fullscreen upgrade")
  }

  func testPortraitFillAndEXIFRotationKeepTheCroppedDimensionSharp() throws {
    let target = try XCTUnwrap(NativeMediaPreview.displaySize(
      viewport: CGSize(width: 300, height: 168.75), scale: 3, mode: .fill))
    let portrait = try NativeImageDecoder.decode(imageData(width: 1200, height: 1800),
      maximumPixelSize: 2048, limits: .init(), displaySize: target)
    XCTAssertGreaterThanOrEqual(portrait.image.width, 900,
      "A portrait image needs enough source width when it fills a landscape card")
    XCTAssertLessThan(portrait.image.height, 1800)

    let rotatedTarget = try XCTUnwrap(NativeMediaPreview.displaySize(
      viewport: CGSize(width: 200, height: 112.5), scale: 2, mode: .fill))
    let rotated = try NativeImageDecoder.decode(imageData(width: 1200, height: 800, orientation: 6),
      maximumPixelSize: 2048, limits: .init(), displaySize: rotatedTarget)
    XCTAssertEqual(rotated.sourceSize, CGSize(width: 800, height: 1200))
    XCTAssertGreaterThanOrEqual(rotated.image.width, 400)
    XCTAssertGreaterThan(rotated.image.height, rotated.image.width)
  }

  func testIntrinsicImageUsesWidthWithoutAnInitialPlaceholderAspectUpgrade() throws {
    let narrow = try XCTUnwrap(NativeMediaPreview.displaySize(
      viewport: CGSize(width: 300, height: 225), scale: 2, mode: .width))
    let tall = try XCTUnwrap(NativeMediaPreview.displaySize(
      viewport: CGSize(width: 300, height: 1800), scale: 2, mode: .width))
    XCTAssertEqual(narrow, tall, "The source aspect ratio must not start a second intrinsic-image request")
    let decoded = try NativeImageDecoder.decode(imageData(width: 800, height: 1600),
      maximumPixelSize: 2048, limits: .init(), displaySize: narrow)
    XCTAssertGreaterThanOrEqual(decoded.image.width, 600)
    XCTAssertLessThan(decoded.image.width, 800)
  }

  @MainActor func testCacheDoesNotConfuseFitPixelsWithFillPixelsAndNeverDowngrades() async throws {
    let loader = SizedImageLoader(data: try imageData(width: 1200, height: 1800))
    let cache = NativeMediaCache()
    let request = try XCTUnwrap(loader.request(for: "https://images.test/portrait", relativeTo: nil))
    let id = NativeResourceRequestID(request: request, loader: ObjectIdentifier(loader), attempt: 0)
    let viewport = CGSize(width: 400, height: 225)
    let fit = try XCTUnwrap(NativeMediaPreview.displaySize(viewport: viewport, scale: 2, mode: .fit))
    let fill = try XCTUnwrap(NativeMediaPreview.displaySize(viewport: viewport, scale: 2, mode: .fill))
    let small = try await cache.resource(id, loader: loader, displaySize: fit)
    XCTAssertTrue(small.satisfies(2048, displaySize: fit))
    XCTAssertFalse(small.satisfies(2048, displaySize: fill))
    let large = try await cache.resource(id, loader: loader, displaySize: fill)
    XCTAssertGreaterThan(large.decodedPixelSize, small.decodedPixelSize)
    XCTAssertTrue(large.satisfies(2048, displaySize: fill))
    XCTAssertEqual(loader.requestCount, 2)
    let again = try await cache.resource(id, loader: loader, displaySize: fit)
    XCTAssertEqual(again.decodedPixelSize, large.decodedPixelSize)
    XCTAssertEqual(loader.requestCount, 2, "Shrinking reuses the already accepted pixels")
    cache.insert(small, for: id)
    XCTAssertEqual(cache[id]?.decodedPixelSize, large.decodedPixelSize)
  }

  @MainActor func testDifferentPendingFitAndFillRequirementsDoNotShareAnUndersizedDecode() async throws {
    let started = expectation(description: "both distinct display requirements started")
    started.expectedFulfillmentCount = 2
    let loader = SizedImageLoader(data: try imageData(width: 1200, height: 1800), started: started)
    let cache = NativeMediaCache()
    let request = try XCTUnwrap(loader.request(for: "https://images.test/portrait", relativeTo: nil))
    let id = NativeResourceRequestID(request: request, loader: ObjectIdentifier(loader), attempt: 0)
    let fit = NativeImageDisplaySize(width: 800, height: 464, mode: .fit)
    let fill = NativeImageDisplaySize(width: 800, height: 464, mode: .fill)
    let a = Task { try await cache.resource(id, loader: loader, displaySize: fit) }
    let b = Task { try await cache.resource(id, loader: loader, displaySize: fill) }
    defer { a.cancel(); b.cancel(); loader.release(); cache.removeAll() }
    await fulfillment(of: [started], timeout: 2)
    loader.release()
    let small = try await a.value, large = try await b.value
    XCTAssertLessThan(small.decodedPixelSize, large.decodedPixelSize)
    XCTAssertTrue(large.satisfies(2048, displaySize: fill))
    XCTAssertEqual(cache[id]?.decodedPixelSize, large.decodedPixelSize)
  }

  @MainActor func testDisplaySizedRequestStillCancelsWithoutWaitingForUncooperativeTransport() async throws {
    let started = expectation(description: "image transport started")
    let loader = SizedImageLoader(data: try imageData(width: 800, height: 450), started: started)
    let cache = NativeMediaCache()
    let request = try XCTUnwrap(loader.request(for: "https://images.test/cancel", relativeTo: nil))
    let id = NativeResourceRequestID(request: request, loader: ObjectIdentifier(loader), attempt: 0)
    let task = Task { try await cache.resource(id, loader: loader,
      displaySize: NativeImageDisplaySize(width: 400, height: 225, mode: .fill)) }
    defer { task.cancel(); loader.release(); cache.removeAll() }
    await fulfillment(of: [started], timeout: 2)
    task.cancel()
    do { _ = try await task.value; XCTFail("The subscriber must stop before the held transport returns") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(cache.pendingRequestCount, 0)
    XCTAssertNil(cache[id])
    loader.release()
    for _ in 0..<5 { await Task.yield() }
    XCTAssertNil(cache[id], "A retired decode cannot repopulate the cache")
  }

  @MainActor func testDisplaySizingPreservesResponseAndSourceLimits() async throws {
    let data = try imageData(width: 800, height: 450)
    let target = NativeImageDisplaySize(width: 400, height: 225, mode: .fill)
    let limited = SizedImageLoader(data: data, limits: .init(maximumImagePixelSize: 256))
    let entry = try await NativeMediaCache.prepare(data, loader: limited, displaySize: target)
    XCTAssertLessThanOrEqual(entry.decodedPixelSize, 256)
    XCTAssertTrue(entry.satisfies(256, displaySize: target))

    for (limits, stage) in [
      (OpenUIResourceLimits(maximumResponseBytes: 1), "responseBytes"),
      (OpenUIResourceLimits(maximumImageSourcePixels: 100), "imageSourcePixels")
    ] {
      do {
        _ = try await NativeMediaCache.prepare(data, loader: SizedImageLoader(data: data, limits: limits), displaySize: target)
        XCTFail("Display sizing must not bypass \(stage)")
      } catch {
        XCTAssertEqual((error as? URLError)?.code, .cannotDecodeContentData)
        XCTAssertEqual((error as NSError).userInfo[NativeResourceError.stageKey] as? String, stage)
      }
    }
  }

  #if os(macOS)
  @MainActor func testMountedImageCanSwitchFromExplicitPixelsToMeasuredPixels() async throws {
    _ = NSApplication.shared
    let loader = SizedImageLoader(data: try imageData(width: 2560, height: 1440))
    let probe = SizedImageProbe()
    func view(_ pixels: Int?) -> AnyView {
      AnyView(NativeRemoteImage(src: "https://images.test/switch", layout: .aspect(16.0 / 9.0),
        requestedPixelSize: pixels, onResource: { probe.pixels = $0.decodedPixelSize })
        .environment(\.displayScale, 3)
        .openUIResourceContext(.init(loader: loader))
        .frame(width: 400, height: 225)
        .transaction { $0.animation = nil; $0.disablesAnimations = true })
    }
    let host = NSHostingView(rootView: view(32))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 225),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    await settle(host) { probe.pixels == 32 }
    XCTAssertEqual(probe.pixels, 32)
    host.rootView = view(nil)
    await settle(host) { probe.pixels == 1280 }
    XCTAssertEqual(probe.pixels, 1280,
      "An unchanged viewport must still be measured after an explicit request becomes automatic")
    XCTAssertEqual(loader.requestCount, 2)
    XCTAssertEqual(loader.signingCount, 1)
  }

  @MainActor func testMountedPixelsRespectChangedLimitsEvenWhenTheRequestURLIsUnchanged() async throws {
    _ = NSApplication.shared
    let loader = SizedImageLoader(data: try imageData(width: 2560, height: 1440))
    let cache = NativeMediaCache(), probe = SizedImageProbe()
    func view(_ revision: Int) -> AnyView {
      AnyView(NativeRemoteImage(src: "https://images.test/policy", alt: "Policy \(revision)",
        layout: .aspect(16.0 / 9.0), onStatus: { status, _ in probe.status = status },
        onResource: { probe.pixels = $0.decodedPixelSize })
        .environment(\.displayScale, 3).environment(\.openUIMediaCache, cache)
        .openUIResourceContext(.init(loader: loader))
        .frame(width: 400, height: 225)
        .transaction { $0.animation = nil; $0.disablesAnimations = true })
    }
    let host = NSHostingView(rootView: view(0))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 225),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    await settle(host) { probe.pixels == 1280 }
    XCTAssertEqual(probe.pixels, 1280)

    loader.setLimits(.init(maximumImagePixelSize: 256))
    host.rootView = view(1)
    await settle(host) { probe.pixels == 256 }
    XCTAssertEqual(probe.pixels, 256,
      "A previous larger entry cannot defeat the replacement resource policy")
    XCTAssertEqual(loader.requestCount, 2)

    loader.setLimits(.init(maximumResponseBytes: 1, maximumImagePixelSize: 256))
    host.rootView = view(2)
    await settle(host) { probe.status == .unavailable }
    XCTAssertEqual(probe.status, .unavailable,
      "Mounted pixels obey the same byte policy as a fresh cache lookup")
    XCTAssertEqual(loader.requestCount, 3, "A permanent budget failure must not auto-retry")
  }

  @MainActor func testMountedCardWaitsForResolvedWidthThenUpgradesOnlyWhenNeeded() async throws {
    _ = NSApplication.shared
    let loader = SizedImageLoader(data: try imageData(width: 2560, height: 1440))
    let cache = NativeMediaCache()
    let probe = SizedImageProbe()
    func view(width: CGFloat, ready: Bool) -> AnyView {
      AnyView(NativeRemoteImage(src: "https://images.test/card", layout: .aspect(16.0 / 9.0),
        onResource: { probe.pixels = $0.decodedPixelSize })
        .environment(\.displayScale, 3)
        .environment(\.openUIMediaWidthReady, ready)
        .environment(\.openUIMediaCache, cache)
        .openUIResourceContext(.init(loader: loader))
        .frame(width: width, height: width * 9 / 16)
        .transaction { $0.animation = nil; $0.disablesAnimations = true })
    }
    let host = NSHostingView(rootView: view(width: 400, ready: false))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 340),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    for _ in 0..<5 { host.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 10_000_000) }
    XCTAssertEqual(loader.requestCount, 0, "Unresolved card geometry must not start a full-size download/decode")
    host.rootView = view(width: 400, ready: true)
    await settle(host) { probe.pixels == 1280 }
    XCTAssertEqual(probe.pixels, 1280)
    XCTAssertEqual(loader.requestCount, 1)
    XCTAssertEqual(loader.signingCount, 1)

    host.rootView = view(width: 600, ready: true)
    await settle(host) { probe.pixels >= 1800 }
    XCTAssertGreaterThanOrEqual(probe.pixels, 1800)
    XCTAssertLessThanOrEqual(probe.pixels, 2048)
    XCTAssertEqual(loader.requestCount, 2)
    XCTAssertEqual(loader.signingCount, 1, "A geometry upgrade reuses its frozen signed request")
    let accepted = probe.pixels
    host.rootView = view(width: 200, ready: true)
    for _ in 0..<5 { host.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 10_000_000) }
    XCTAssertEqual(probe.pixels, accepted)
    XCTAssertEqual(loader.requestCount, 2)
  }

  @MainActor private func settle(_ host: NSHostingView<AnyView>, until condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline {
      host.layoutSubtreeIfNeeded()
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    host.layoutSubtreeIfNeeded()
  }
  #endif

  private func imageData(width: Int, height: Int, orientation: Int = 1) throws -> Data {
    let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    let image = try XCTUnwrap(context.makeImage())
    let data = NSMutableData()
    let type = orientation == 1 ? UTType.png : UTType.tiff
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }
}

@MainActor private final class SizedImageProbe {
  var pixels = 0
  var status: NativeMediaStatus?
}

private final class SizedImageLoader: OpenUIResourceLoading {
  private var limits: OpenUIResourceLimits
  private let data: Data
  private let started: XCTestExpectation?
  private let lock = NSLock()
  private var requests = 0
  private var signatures = 0
  private var released = false
  private var waiting: [CheckedContinuation<Void, Never>] = []
  var requestCount: Int { lock.lock(); defer { lock.unlock() }; return requests }
  var signingCount: Int { lock.lock(); defer { lock.unlock() }; return signatures }
  var resourceLimits: OpenUIResourceLimits { lock.lock(); defer { lock.unlock() }; return limits }

  init(data: Data, limits: OpenUIResourceLimits = .init(), started: XCTestExpectation? = nil) {
    self.data = data; self.limits = limits; self.started = started
  }
  func setLimits(_ value: OpenUIResourceLimits) { lock.lock(); limits = value; lock.unlock() }
  func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
    lock.lock(); signatures += 1; lock.unlock()
    return URL(string: source, relativeTo: baseURL).map { URLRequest(url: $0) }
  }
  private func record() { lock.lock(); requests += 1; lock.unlock() }
  func data(for request: URLRequest) async throws -> Data {
    record()
    if let started {
      await withCheckedContinuation { continuation in
        lock.lock()
        let ready = released
        if !ready { waiting.append(continuation) }
        lock.unlock()
        started.fulfill()
        if ready { continuation.resume() }
      }
    }
    return data
  }
  func release() {
    lock.lock(); released = true
    let continuations = waiting; waiting.removeAll(); lock.unlock()
    for continuation in continuations { continuation.resume() }
  }
}
