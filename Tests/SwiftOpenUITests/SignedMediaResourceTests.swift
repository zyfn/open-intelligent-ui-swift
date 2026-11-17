import SwiftLang
#if os(macOS)
import AppKit
import Foundation
import ImageIO
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class SignedMediaResourceTests: XCTestCase {
  @MainActor func testMountedImageRecoversTransientFailureWithoutATapOrNewSignature() async throws {
    let loader = SignedImageLoader(data: try png(.red), transientFailures: 1)
    let log = SignedImageStatusLog()
    let (host, window) = mount(image("https://signed.test/transient.png", loader: loader, log: log))
    defer { window.close() }
    await settleAsync(host, until: { log.statuses.last == .loaded && self.hasPixels(.red, in: host) })
    XCTAssertEqual(loader.requests.count, 2, "One temporary transport failure receives one automatic retry")
    XCTAssertEqual(loader.signingCount, 1, "Automatic transport recovery keeps the frozen request")
    XCTAssertEqual(loader.requests.first, loader.requests.last)
    XCTAssertFalse(log.statuses.contains(.unavailable), "The retry wait should keep the loading surface")
    XCTAssertTrue(hasPixels(.red, in: host), "The recovered photograph is visible without clicking")
  }

  @MainActor func testMountedPersistentFailureStopsThenManualRetryRefreshesSignature() async throws {
    let loader = SignedImageLoader(data: try png(.red), transientFailures: 2)
    let log = SignedImageStatusLog()
    let (host, window) = mount(image("https://signed.test/persistent.png", loader: loader, log: log))
    defer { window.close() }
    await settleAsync(host, until: { log.statuses.last == .unavailable })
    XCTAssertEqual(loader.requests.count, 2)
    XCTAssertEqual(loader.signingCount, 1)
    let size = host.fittingSize
    try clickCenter(host, window: window)
    await settleAsync(host, until: { log.statuses.last == .loaded && self.hasPixels(.red, in: host) })
    XCTAssertEqual(loader.requests.count, 3)
    XCTAssertEqual(loader.signingCount, 2, "The existing explicit retry still asks the host for a fresh request")
    XCTAssertNotEqual(loader.requests.first?.url, loader.requests.last?.url)
    XCTAssertEqual(loader.requests.last?.cachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertEqual(host.fittingSize, size)
  }

  @MainActor func testPreviewUpgradesAThumbnailWithoutChangingItsSignedRequest() async throws {
    let data = try largePNG(side: 512)
    let loader = SignedImageLoader(data: data, heldPaths: ["detail.png"])
    let resources = OpenUIResourceContext(loader: loader)
    let cache = NativeMediaCache()
    let target = NativeMediaResourceTarget(source: "https://signed.test/detail.png", resources: resources)
    let request = target.resolve(in: cache)
    let thumbnail = try await NativeMediaCache.prepare(largePNG(side: 512, color: .blue), loader: loader, targetPixelSize: 32)
    cache.insert(thumbnail, for: request)
    cache.markPresented(request)
    let probe = SignedPixelProbe()
    func view(_ pixels: Int) -> AnyView {
      presented(AnyView(NativeRemoteImage(src: target.source, alt: "Detailed image", layout: .fit,
        cachedImage: thumbnail.image, cachedImageTarget: target, upgradesCachedImage: true,
        requestedPixelSize: pixels, onResource: { probe.pixels = $0.decodedPixelSize })
        .environment(\.openUIMediaCache, cache).openUIResourceContext(resources)), width: 180)
    }
    let (host, window) = mount(view(512))
    defer { loader.releaseHeldRequests(); window.close() }
    await settleAsync(host, until: { loader.heldCount == 1 && self.hasPixels(.blue, in: host) })
    loader.releaseHeldRequests()
    await settleAsync(host, until: { probe.pixels == 512 && self.hasPixels(.red, in: host) && !self.hasPixels(.blue, in: host) })
    XCTAssertEqual(cache[request]?.decodedPixelSize, 512)
    XCTAssertEqual(loader.signingCount, 1, "A decode upgrade reuses the frozen signed request")
    XCTAssertEqual(loader.requests.count, 1)
    XCTAssertTrue(hasPixels(.red, in: host))
    XCTAssertFalse(hasPixels(.blue, in: host), "The full-size image must replace the provisional thumbnail on screen")

    host.rootView = view(64)
    for _ in 0..<5 { host.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 10_000_000) }
    XCTAssertEqual(probe.pixels, 512, "Shrinking must not downgrade accepted full-size pixels")
    XCTAssertEqual(loader.requests.count, 1)
    XCTAssertEqual(loader.signingCount, 1)
  }

  @MainActor func testWindowedMediaPagerOnlyMountsAndLoadsItsNeighbors() async throws {
    let loader = SignedImageLoader(data: try png(.red))
    let cache = NativeMediaCache()
    let mounts = SignedPageMounts()
    func view(_ selected: Int) -> AnyView {
      AnyView(NativePager(ids: Array(0..<40), selection: .constant(selected), enabled: true,
        identifier: "test.media.pages", pageRadius: 1) { index in
        NativeRemoteImage(src: "https://signed.test/page-\(index).png", layout: .fit,
          releasesImageWhenHidden: true, previewEnabled: false)
          .frame(width: 180, height: 120)
          .onAppear { mounts.active.insert(index) }
          .onDisappear { mounts.active.remove(index) }
      }.environment(\.openUIMediaCache, cache).openUIResourceContext(.init(loader: loader))
        .frame(width: 180, height: 120))
    }
    let (host, window) = mount(view(0))
    defer { window.close() }
    await settleAsync(host, until: { loader.completedCount == 2 && mounts.active == Set([0, 1]) })
    XCTAssertEqual(Set(loader.requests.compactMap { $0.url?.lastPathComponent }), Set(["page-0.png", "page-1.png"]))
    host.rootView = view(20)
    await settleAsync(host, until: { loader.completedCount == 5 && mounts.active == Set([19, 20, 21]) })
    XCTAssertEqual(Set(loader.requests.compactMap { $0.url?.lastPathComponent }),
      Set(["page-0.png", "page-1.png", "page-19.png", "page-20.png", "page-21.png"]))
    XCTAssertEqual(mounts.active.count, 3, "Retired full-size pages must leave the mounted tree")
  }

  @MainActor func testMountedSignedImageRetriesAndChangesOnlyWithItsResourceIdentity() throws {
    let red = try png(.red), blue = try png(.blue), green = try png(.green)
    let loader = SignedImageLoader(data: red, pathData: ["second.png": blue],
      scopeData: ["account-b": green], failsFirstRequest: true)
    let log = SignedImageStatusLog()
    let first = "https://signed.test/first.png", second = "https://signed.test/second.png"
    let (host, window) = mount(image(first, loader: loader, log: log))
    defer { window.close() }

    settle(host, until: { log.statuses.last == .unavailable })
    XCTAssertEqual(loader.signingCount, 1, "Reading a pending/failed request must not sign it again")
    XCTAssertEqual(loader.requests.count, 1)
    let size = host.fittingSize
    try clickCenter(host, window: window)
    settle(host, until: { log.statuses.last == .loaded && self.hasPixels(.red, in: host) })
    XCTAssertEqual(loader.signingCount, 2, "An explicit retry receives one fresh signature")
    let retried = loader.requests
    XCTAssertEqual(retried.count, 2)
    XCTAssertNotEqual(retried.first?.url, retried.last?.url, "The retry must not reuse its failed signed URL")
    XCTAssertEqual(retried.last?.cachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertEqual(host.fittingSize, size)

    for index in 0..<12 {
      host.rootView = image(first, loader: loader, log: log, alt: "Updated description \(index)")
      _ = host.fittingSize
      pump(host)
    }
    XCTAssertTrue(hasPixels(.red, in: host))
    XCTAssertEqual(loader.signingCount, 2, "Copy and fitting changes do not refresh a successful signature")
    XCTAssertEqual(loader.requests.count, 2)

    host.rootView = image(second, loader: loader, log: log)
    settle(host, until: { loader.requests.count == 3 && self.hasPixels(.blue, in: host) })
    XCTAssertEqual(loader.signingCount, 3, "Changing source creates one new request")

    loader.setScope("account-b")
    host.rootView = image(second, loader: loader, log: log, alt: "New account")
    settle(host, until: { loader.requests.count == 4 && self.hasPixels(.green, in: host) })
    XCTAssertEqual(loader.signingCount, 4, "Changing authorization scope must replace retained pixels")
    XCTAssertEqual(loader.requests.last?.value(forHTTPHeaderField: "X-Test-Scope"), "account-b")

    let replacement = SignedImageLoader(data: red)
    host.rootView = image(second, loader: replacement, log: log, alt: "New resource owner")
    settle(host, until: { replacement.requests.count == 1 && self.hasPixels(.red, in: host) })
    XCTAssertEqual(replacement.signingCount, 1)
    XCTAssertEqual(loader.requests.count, 4, "A replaced loader must not receive later requests")
    for _ in 0..<12 { _ = host.fittingSize; pump(host) }
    XCTAssertEqual(replacement.signingCount, 1)
    XCTAssertEqual(replacement.requests.count, 1)
    XCTAssertEqual(host.fittingSize, size)
  }

  @MainActor func testLateSignedResponseCannotReplaceTheCurrentImage() throws {
    let loader = SignedImageLoader(data: try png(.red), pathData: ["fresh.png": try png(.blue)],
      heldPaths: ["slow.png"])
    let log = SignedImageStatusLog()
    let (host, window) = mount(image("https://signed.test/slow.png", loader: loader, log: log))
    defer { loader.releaseHeldRequests(); window.close() }
    settle(host, until: { loader.requests.count == 1 && loader.heldCount == 1 })
    XCTAssertFalse(log.statuses.contains(.loaded))

    host.rootView = image("https://signed.test/fresh.png", loader: loader, log: log)
    settle(host, until: { log.statuses.last == .loaded && self.hasPixels(.blue, in: host) })
    let accepted = log.statuses.filter { $0 == .loaded }.count
    let size = host.fittingSize
    // This loader deliberately ignores cancellation until the test releases
    // its continuation. The old response must still be rejected by the view.
    loader.releaseHeldRequests()
    settle(host, until: { loader.completedCount == 2 })
    for _ in 0..<8 { pump(host) }
    XCTAssertTrue(hasPixels(.blue, in: host))
    XCTAssertFalse(hasPixels(.red, in: host))
    XCTAssertEqual(log.statuses.filter { $0 == .loaded }.count, accepted,
      "A stale completion must not publish another loaded callback")
    XCTAssertEqual(loader.signingCount, 2)
    XCTAssertEqual(loader.requests.count, 2)
    XCTAssertEqual(host.fittingSize, size)
  }

  @MainActor func testGalleryAndBackgroundCardsRetainSignedSuccessAcrossStoreUpdates() throws {
    let standard = try OpenUIComponents.library()
    let title = try XCTUnwrap(standard.library.components.first { $0.name == "BoldText" })
    let probe = SignedArtworkProbe()
    let library = try standard.extending(overriding: [OpenUIComponent(title) { context in
      NativeComponentHost(context: context) { context in
        MainActor.assumeIsolated { probe.titleInk = context.theme.textNeutralPrimary }
        return NativeInlineText(context: context, bold: true)
      }
    }])
    let cases = [
      ("gallery", "root=ImageGallery([{src:\"https://signed.test/gallery.png\",alt:$copy}])\n$copy=\"Caption\""),
      ("background", "root=VisualCardItem(BoldText(\"text\",$copy),\"card\",\"https://signed.test/background.png\",null,\"Photo\")\n$copy=\"Caption\"")
    ]
    for (name, source) in cases {
      probe.titleInk = nil
      let loader = SignedImageLoader(data: try png(.red))
      let state = OpenUIState(schema: library.library.toSchema())
      state.setSource(source)
      XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
      let view = OpenUIContentView(state: state, registry: library.registry)
        .openUIResourceContext(.init(loader: loader))
        .frame(width: 320).frame(height: 360, alignment: .top)
      let (host, window) = mount(presented(AnyView(view), width: 320),
        size: CGSize(width: 320, height: 360))
      defer { window.close() }
      settle(host, until: {
        self.hasPixels(.red, in: host) && (name != "background" || probe.titleInk == .white)
      })
      XCTAssertEqual(loader.requests.count, 1, "\(name) must accept one successful transport result")
      let signed = loader.signingCount
      XCTAssertGreaterThan(signed, 0)
      let size = host.fittingSize
      for index in 0..<12 {
        state.setState("$copy", value: .string("Caption \(index)"))
        _ = host.fittingSize
        pump(host)
      }
      XCTAssertTrue(hasPixels(.red, in: host), "\(name) must keep the actual loaded photograph")
      if name == "background" {
        XCTAssertEqual(probe.titleInk, .white, "The background owner must retain its accepted loaded state")
      }
      XCTAssertEqual(loader.signingCount, signed, "\(name) must not sign again on Store or fitting changes")
      XCTAssertEqual(loader.requests.count, 1)
      XCTAssertEqual(host.fittingSize, size)
    }
  }

  @MainActor private func image(_ source: String, loader: SignedImageLoader,
    log: SignedImageStatusLog, alt: String = "Image") -> AnyView {
    presented(AnyView(NativeRemoteImage(src: source, alt: alt, layout: .aspect(1.5),
      onStatus: { status, _ in log.statuses.append(status) })
      .openUIResourceContext(.init(loader: loader))), width: 180)
  }

  @MainActor private func presented(_ view: AnyView, width: CGFloat) -> AnyView {
    var presentation = OpenUIPresentation()
    presentation.motion.mediaRevealDuration = 0
    return AnyView(view.openUIPresentation(presentation)
      .transaction { $0.animation = nil; $0.disablesAnimations = true }
      .environment(\.colorScheme, .light)
      .frame(width: width).background(Color.white))
  }

  @MainActor private func mount(_ view: AnyView, size: CGSize = CGSize(width: 180, height: 120))
    -> (NSHostingView<AnyView>, NSWindow) {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    return (host, window)
  }

  @MainActor private func pump(_ host: NSHostingView<AnyView>) {
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    host.layoutSubtreeIfNeeded()
  }

  @MainActor private func settleAsync(_ host: NSHostingView<AnyView>, until ready: () -> Bool,
    file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<300 {
      host.layoutSubtreeIfNeeded()
      if ready() { return }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(ready(), "Mounted resource did not reach the expected state", file: file, line: line)
  }

  @MainActor private func largePNG(side: Int, color: NSColor = .red) throws -> Data {
    let canvas = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    canvas.setFillColor(color.cgColor)
    canvas.fill(CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(canvas.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

  @MainActor private func settle(_ host: NSHostingView<AnyView>, until ready: () -> Bool,
    file: StaticString = #filePath, line: UInt = #line) {
    let deadline = Date().addingTimeInterval(3)
    repeat { pump(host) } while !ready() && Date() < deadline
    XCTAssertTrue(ready(), "Mounted signed image did not reach the expected state", file: file, line: line)
  }

  @MainActor private func clickCenter(_ host: NSHostingView<AnyView>, window: NSWindow) throws {
    let point = host.convert(NSPoint(x: host.bounds.midX, y: host.bounds.midY), to: nil)
    let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
      windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
    NSApplication.shared.postEvent(up, atStart: false)
    window.sendEvent(down)
    window.sendEvent(up)
    pump(host)
  }

  private enum PixelColor { case red, green, blue }

  @MainActor private func hasPixels(_ color: PixelColor, in host: NSHostingView<AnyView>) -> Bool {
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let image = bitmap.cgImage,
      let canvas = CGContext(data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    canvas.setFillColor(CGColor(gray: 1, alpha: 1))
    canvas.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = canvas.data else { return false }
    let pixels = data.assumingMemoryBound(to: UInt8.self)
    var count = 0
    for index in stride(from: 0, to: image.width * image.height * 4, by: 4) {
      let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
      switch color {
      case .red: if r > 40 && r > g * 2 && r > b * 2 { count += 1 }
      case .green: if g > 40 && g > r * 2 && g > b * 2 { count += 1 }
      case .blue: if b > 40 && b > r * 2 && b > g * 2 { count += 1 }
      }
    }
    // Far more pixels than a fallback symbol: this must be the photograph.
    return count > 1000
  }

  @MainActor private func png(_ color: NSColor) throws -> Data {
    let pixels = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
      pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 8, bitsPerPixel: 32))
    for x in 0..<2 { for y in 0..<2 { pixels.setColor(color, atX: x, y: y) } }
    return try XCTUnwrap(pixels.representation(using: .png, properties: [:]))
  }
}

@MainActor private final class SignedImageStatusLog { var statuses: [NativeMediaStatus] = [] }
@MainActor private final class SignedArtworkProbe { var titleInk: Color? }
@MainActor private final class SignedPixelProbe { var pixels = 0 }
@MainActor private final class SignedPageMounts { var active = Set<Int>() }

/// request(for:) is intentionally non-idempotent, as with nonce-based signed
/// URLs. Transport is deterministic and never touches the network.
private final class SignedImageLoader: OpenUIResourceLoading {
  private let lock = NSLock()
  private let data: Data
  private let pathData: [String: Data]
  private let scopeData: [String: Data]
  private let failsFirstRequest: Bool
  private let transientFailures: Int
  private let heldPaths: Set<String>
  private var scope = "account-a"
  private var signed = 0
  private var sent: [URLRequest] = []
  private var completed = 0
  private var held: [(CheckedContinuation<Data, Error>, Data)] = []
  private var holdReleased = false

  init(data: Data, pathData: [String: Data] = [:], scopeData: [String: Data] = [:],
    failsFirstRequest: Bool = false, heldPaths: Set<String> = [], transientFailures: Int = 0) {
    self.data = data; self.pathData = pathData; self.scopeData = scopeData
    self.failsFirstRequest = failsFirstRequest; self.heldPaths = heldPaths
    self.transientFailures = transientFailures
  }
  var authorizationScopeID: String { lock.lock(); defer { lock.unlock() }; return scope }
  var signingCount: Int { lock.lock(); defer { lock.unlock() }; return signed }
  var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return sent }
  var completedCount: Int { lock.lock(); defer { lock.unlock() }; return completed }
  var heldCount: Int { lock.lock(); defer { lock.unlock() }; return held.count }
  func setScope(_ value: String) { lock.lock(); scope = value; lock.unlock() }

  func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
    guard let url = URL(string: source, relativeTo: baseURL),
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
    lock.lock()
    signed += 1
    let nonce = signed, account = scope
    lock.unlock()
    parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "nonce", value: "\(nonce)")]
    guard let signedURL = parts.url else { return nil }
    var request = URLRequest(url: signedURL)
    request.setValue(account, forHTTPHeaderField: "X-Test-Scope")
    return request
  }

  private func record(_ request: URLRequest) -> Int {
    lock.lock(); defer { lock.unlock() }
    sent.append(request)
    return sent.count
  }
  private func finish() { lock.lock(); completed += 1; lock.unlock() }
  private func hold(_ continuation: CheckedContinuation<Data, Error>, data: Data) {
    lock.lock()
    if holdReleased { lock.unlock(); continuation.resume(returning: data) }
    else { held.append((continuation, data)); lock.unlock() }
  }
  func releaseHeldRequests() {
    lock.lock(); holdReleased = true; let waiters = held; held.removeAll(); lock.unlock()
    for (continuation, data) in waiters { continuation.resume(returning: data) }
  }
  func data(for request: URLRequest) async throws -> Data {
    let attempt = record(request)
    defer { finish() }
    if attempt <= transientFailures { throw URLError(.networkConnectionLost) }
    if failsFirstRequest && attempt == 1 { throw URLError(.cannotLoadFromNetwork) }
    let value = scopeData[request.value(forHTTPHeaderField: "X-Test-Scope") ?? ""]
      ?? pathData[request.url?.lastPathComponent ?? ""] ?? data
    if heldPaths.contains(request.url?.lastPathComponent ?? "") {
      return try await withCheckedThrowingContinuation { hold($0, data: value) }
    }
    return value
  }
}
#endif
