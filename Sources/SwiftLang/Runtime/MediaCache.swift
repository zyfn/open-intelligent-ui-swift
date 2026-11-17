import Foundation
import SwiftUI
import ImageIO
import CoreGraphics
import os

/// A viewport requirement, not a source-image size. Source proportions are
/// applied after ImageIO reads the header, so filling a wide card from a portrait
/// image retains enough pixels in the cropped dimension.
package struct NativeImageDisplaySize: Hashable, Sendable {
  package enum Mode: Hashable, Sendable { case fit, fill, width }
  package let width: Int
  package let height: Int
  package let mode: Mode

  package init(width: Int, height: Int, mode: Mode) {
    self.width = max(1, width); self.height = mode == .width ? 1 : max(1, height)
    self.mode = mode
  }

  package func pixelSize(sourceSize: CGSize, maximum: Int) -> Int {
    let cap = max(1, maximum)
    guard sourceSize.width.isFinite, sourceSize.height.isFinite,
      sourceSize.width > 0, sourceSize.height > 0 else { return cap }
    let horizontal = CGFloat(width) / sourceSize.width
    let vertical = CGFloat(height) / sourceSize.height
    let scale: CGFloat
    switch mode {
    case .fit: scale = min(horizontal, vertical)
    case .fill: scale = max(horizontal, vertical)
    case .width: scale = horizontal
    }
    let required = max(sourceSize.width, sourceSize.height) * scale
    guard required.isFinite else { return cap }
    // Small, stable decode steps avoid generating almost-identical bitmaps as
    // layout settles. Round up so the cached result covers the requested pixels.
    let step: CGFloat = required > 1024 ? 128 : required > 256 ? 64 : 16
    return max(1, Int(min(CGFloat(cap), ceil(required / step) * step)))
  }
}

/// Completed media belongs to the presentation, rather than a transient layout
/// branch. A late grid/carousel argument may relocate an already loaded image.
@MainActor package final class NativeMediaCache {
  package init() {}
  @MainActor package struct Entry {
    package let image: Image
    package let size: CGSize
    package let cost: Int
    // Keep ObjectIdentifier(loader) valid for the lifetime of this entry.
    package let resourceOwner: any OpenUIResourceLoading
    package let resourceLimits: OpenUIResourceLimits
    package var wasPresented = false
    package var decodedPixelSize: Int = .max
    package init(image: Image, size: CGSize, cost: Int,
                 resourceOwner: any OpenUIResourceLoading, wasPresented: Bool = false,
                 decodedPixelSize: Int = .max, resourceLimits: OpenUIResourceLimits? = nil) {
      self.image = image; self.size = size; self.cost = cost
      self.resourceOwner = resourceOwner; self.wasPresented = wasPresented
      self.decodedPixelSize = decodedPixelSize
      self.resourceLimits = resourceLimits ?? resourceOwner.resourceLimits
    }
    package func satisfies(_ requested: Int, displaySize: NativeImageDisplaySize? = nil) -> Bool {
      let required = displaySize?.pixelSize(sourceSize: size, maximum: requested) ?? requested
      return decodedPixelSize >= required || max(size.width, size.height) <= CGFloat(decodedPixelSize)
    }
  }
  private var entries: [NativeResourceRequestID: Entry] = [:]
  private var order: [NativeResourceRequestID] = []
  private struct RequestSnapshot {
    let request: NativeResourceRequestID
    let owner: any OpenUIResourceLoading
    let limits: OpenUIResourceLimits
  }
  // Stable presentation identities point to complete, already resolved
  // requests. A nonce-bearing URL is never reconstructed for cache lookup.
  private var requestSnapshots: [AnyHashable: RequestSnapshot] = [:]
  private var requestSnapshotOrder: [AnyHashable] = []
  private struct DecodeKey: Hashable {
    let resource: NativeResourceRequestID
    let pixelSize: Int
    let displaySize: NativeImageDisplaySize?
    let limits: OpenUIResourceLimits

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.resource == rhs.resource && lhs.pixelSize == rhs.pixelSize
        && lhs.displaySize == rhs.displaySize && lhs.limits == rhs.limits
    }
    func hash(into hasher: inout Hasher) {
      hasher.combine(resource); hasher.combine(pixelSize); hasher.combine(displaySize)
      hasher.combine(limits.maximumResponseBytes); hasher.combine(limits.maximumConcurrentRequests)
      hasher.combine(limits.maximumRedirects); hasher.combine(limits.allowsCrossOriginRedirects)
      hasher.combine(limits.maximumImageSourcePixels); hasher.combine(limits.maximumImagePixelSize)
    }
  }
  private final class Pending {
    let id = UUID()
    var task: Task<Void, Never>?
    var waiters: [UUID: CheckedContinuation<Entry, Error>] = [:]
  }
  private var pending: [DecodeKey: Pending] = [:]
  package var pendingRequestCount: Int { pending.count }
  package var pendingSubscriberCount: Int { pending.values.reduce(0) { $0 + $1.waiters.count } }
  private let maximumCost = 32 * 1024 * 1024
  package private(set) var generation = 0
  package subscript(_ key: NativeResourceRequestID) -> Entry? {
    guard let entry = entries[key], ObjectIdentifier(entry.resourceOwner) == key.loader,
      entry.resourceOwner.resourceLimits == entry.resourceLimits,
      openUIResourceScopeIsCurrent(entry.resourceOwner, authorizationScope: key.authorizationScope) else { return nil }
    return entry
  }
  package func requestSnapshot(for key: AnyHashable) -> NativeResourceRequestID? {
    guard let snapshot = requestSnapshots[key],
          openUIResourceScopeIsCurrent(snapshot.owner, authorizationScope: snapshot.request.authorizationScope),
          snapshot.owner.resourceLimits == snapshot.limits else { return nil }
    return snapshot.request
  }
  package func retainRequestSnapshot(_ request: NativeResourceRequestID, for key: AnyHashable,
                                     owner: any OpenUIResourceLoading) {
    guard request.loader == ObjectIdentifier(owner),
          openUIResourceScopeIsCurrent(owner, authorizationScope: request.authorizationScope) else { return }
    requestSnapshots[key] = RequestSnapshot(request: request, owner: owner, limits: owner.resourceLimits)
    requestSnapshotOrder.removeAll { $0 == key }; requestSnapshotOrder.append(key)
    while requestSnapshotOrder.count > 32 {
      requestSnapshots.removeValue(forKey: requestSnapshotOrder.removeFirst())
    }
  }
  package func markPresented(_ key: NativeResourceRequestID) { entries[key]?.wasPresented = true }
  package func insert(_ entry: Entry, for key: NativeResourceRequestID) {
    guard entry.cost <= maximumCost, ObjectIdentifier(entry.resourceOwner) == key.loader,
      entry.resourceOwner.resourceLimits == entry.resourceLimits,
      openUIResourceScopeIsCurrent(entry.resourceOwner, authorizationScope: key.authorizationScope) else { return }
    if let current = self[key], current.decodedPixelSize > entry.decodedPixelSize { return }
    entries[key] = entry
    order.removeAll { $0 == key }; order.append(key)
    while order.count > 8 || entries.values.reduce(0, { $0 + $1.cost }) > maximumCost {
      entries.removeValue(forKey: order.removeFirst())
    }
  }
  nonisolated package static func effectivePixelSize(_ requested: Int?, limits: OpenUIResourceLimits) -> Int {
    max(1, min(requested ?? limits.maximumImagePixelSize, limits.maximumImagePixelSize, 2816))
  }
  package func resource(_ key: NativeResourceRequestID, loader: any OpenUIResourceLoading,
                targetPixelSize: Int? = nil, displaySize: NativeImageDisplaySize? = nil) async throws -> Entry {
    try Task.checkCancellation()
    guard key.loader == ObjectIdentifier(loader),
      openUIResourceScopeIsCurrent(loader, authorizationScope: key.authorizationScope) else { throw CancellationError() }
    let limits = loader.resourceLimits
    let target = Self.effectivePixelSize(targetPixelSize, limits: limits)
    if let value = self[key], value.satisfies(target, displaySize: displaySize) { return value }
    guard let request = key.request else { throw URLError(.badURL) }
    let decodeKey = DecodeKey(resource: key, pixelSize: target, displaySize: displaySize, limits: limits)
    let waiterID = UUID(), epoch = generation
    let scope = key.authorizationScope
    let entry: Entry = try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in
        guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
        if let group = pending[decodeKey] { group.waiters[waiterID] = continuation; return }
        let group = Pending()
        group.waiters[waiterID] = continuation; pending[decodeKey] = group
        let id = group.id
        group.task = Task { @MainActor [weak self] in
          let result: Result<Entry, Error>
          do {
            try Self.checkLease(loader, scope: scope, limits: limits)
            let value = try await Self.load(request, loader: loader, targetPixelSize: target, displaySize: displaySize)
            try Self.checkLease(loader, scope: scope, limits: limits)
            result = .success(value)
          } catch { result = .failure(error) }
          self?.finish(decodeKey, id: id, epoch: epoch, result: result)
        }
      }
    }, onCancel: { [weak self] in
      Task { @MainActor in self?.cancelWaiter(decodeKey, id: waiterID) }
    })
    // Cancellation can race completion before the actor processes onCancel.
    // Check the subscriber task, not only the shared transport task.
    try Task.checkCancellation()
    guard generation == epoch,
      openUIResourceScopeIsCurrent(loader, authorizationScope: scope),
      loader.resourceLimits == limits else { throw CancellationError() }
    return entry
  }
  private func cancelWaiter(_ key: DecodeKey, id: UUID) {
    guard let group = pending[key], let waiter = group.waiters.removeValue(forKey: id) else { return }
    waiter.resume(throwing: CancellationError())
    if group.waiters.isEmpty {
      pending.removeValue(forKey: key)
      group.task?.cancel(); group.task = nil
    }
  }
  private func finish(_ key: DecodeKey, id: UUID, epoch: Int, result: Result<Entry, Error>) {
    guard generation == epoch, let group = pending[key], group.id == id else { return }
    pending.removeValue(forKey: key); group.task = nil
    if case .success(let entry) = result { insert(entry, for: key.resource) }
    for waiter in group.waiters.values { waiter.resume(with: result) }
    group.waiters.removeAll()
  }
  // Bound the complete image pipeline, not just the decode step: queued
  // compressed Data must not grow while a limited decoder is occupied.
  private static let imageAdmission = NativeResourceAdmission(maximum: 2)
  package static func load(_ request: URLRequest, loader: any OpenUIResourceLoading,
                   targetPixelSize: Int? = nil, displaySize: NativeImageDisplaySize? = nil) async throws -> Entry {
    let scope = loader.authorizationScopeID, limits = loader.resourceLimits
    var mayRetry = true
    while true {
      do {
        return try await downloadAttempt(request, loader: loader, scope: scope, limits: limits,
          targetPixelSize: targetPixelSize, displaySize: displaySize)
      } catch {
        try checkLease(loader, scope: scope, limits: limits)
        let delay = mayRetry ? NativeMediaRetry.delay(after: error, request: request) : nil
        NativeMediaRetry.record(error, retrying: delay != nil)
        guard let delay else { throw error }
        mayRetry = false
        // The pending decode owns this one recovery for all its subscribers.
        // No network/decode permit is held during the cancellable backoff, and
        // the host's frozen signed request is never reconstructed here.
        try await Task.sleep(nanoseconds: delay)
      }
    }
  }
  private static func checkLease(_ loader: any OpenUIResourceLoading, scope: String,
                                 limits: OpenUIResourceLimits) throws {
    try Task.checkCancellation()
    guard openUIResourceScopeIsCurrent(loader, authorizationScope: scope),
      loader.resourceLimits == limits else { throw CancellationError() }
  }
  private static func downloadAttempt(_ request: URLRequest, loader: any OpenUIResourceLoading,
    scope: String, limits: OpenUIResourceLimits, targetPixelSize: Int?,
    displaySize: NativeImageDisplaySize?) async throws -> Entry {
    try checkLease(loader, scope: scope, limits: limits)
    try await imageAdmission.acquire()
    let result: Entry
    do {
      try checkLease(loader, scope: scope, limits: limits)
      let data = try await loader.data(for: request)
      try checkLease(loader, scope: scope, limits: limits)
      result = try await prepare(data, loader: loader, targetPixelSize: targetPixelSize, displaySize: displaySize)
      try checkLease(loader, scope: scope, limits: limits)
    } catch {
      await imageAdmission.release()
      throw error
    }
    await imageAdmission.release()
    try checkLease(loader, scope: scope, limits: limits)
    return result
  }
  package static func prepare(_ data: Data, loader: any OpenUIResourceLoading,
                      targetPixelSize: Int? = nil, displaySize: NativeImageDisplaySize? = nil) async throws -> Entry {
    let limits = loader.resourceLimits, scope = loader.authorizationScopeID
    try checkLease(loader, scope: scope, limits: limits)
    let target = effectivePixelSize(targetPixelSize, limits: limits)
    let work = Task.detached(priority: .userInitiated) {
      try NativeRuntimeTrace.measure("Image decode") {
        try NativeImageDecoder.decode(data, maximumPixelSize: target, limits: limits, displaySize: displaySize)
      }
    }
    let decoded = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
    try checkLease(loader, scope: scope, limits: limits)
    return entry(decoded, loader: loader, limits: limits)
  }
  /// Synchronous entry is retained for small fixtures and explicit native callers.
  /// Live resource consumers use prepare to keep decoding off the UI actor.
  package static func decode(_ data: Data, loader: any OpenUIResourceLoading) throws -> Entry {
    let limits = loader.resourceLimits
    return entry(try NativeImageDecoder.decode(data, maximumPixelSize: limits.maximumImagePixelSize,
      limits: limits), loader: loader, limits: limits)
  }
  private static func entry(_ decoded: NativeImageDecoder.Pixels, loader: any OpenUIResourceLoading,
                            limits: OpenUIResourceLimits) -> Entry {
    Entry(image: Image(decorative: decoded.image, scale: 1), size: decoded.sourceSize,
      cost: decoded.image.bytesPerRow * decoded.image.height, resourceOwner: loader,
      decodedPixelSize: max(decoded.image.width, decoded.image.height), resourceLimits: limits)
  }
  package func removeAll() {
    generation &+= 1
    let groups = Array(pending.values); pending.removeAll()
    for group in groups {
      group.task?.cancel(); group.task = nil
      for waiter in group.waiters.values { waiter.resume(throwing: CancellationError()) }
      group.waiters.removeAll()
    }
    entries.removeAll(); order.removeAll()
    requestSnapshots.removeAll(); requestSnapshotOrder.removeAll()
  }
}
/// Recovery belongs to the shared image operation, not each mounted subscriber.
/// It never changes a request's authorization, policy or source address.
enum NativeMediaRetry {
  private static let logger = Logger(subsystem: "dev.openui.swift", category: "Media")

  static func delay(after error: Error, request: URLRequest) -> UInt64? {
    guard ["GET", "HEAD"].contains((request.httpMethod ?? "GET").uppercased()),
      let failure = error as? URLError else { return nil }
    switch failure.code {
    case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
      return 350_000_000
    case .badServerResponse:
      guard let status = NativeResourceError.httpStatus(for: error),
        [408, 429, 500, 502, 503, 504].contains(status) else { return nil }
      let seconds = NativeResourceError.retryAfter(for: error) ?? 0.35
      guard seconds.isFinite, seconds >= 0, seconds <= 2 else { return nil }
      return UInt64(max(0.35, seconds) * 1_000_000_000)
    default:
      // Cancellation, invalid sources, auth/404, decoding and byte/pixel
      // budgets cannot be repaired by fetching the same image immediately.
      return nil
    }
  }

  static func stage(for error: Error) -> String {
    switch (error as NSError).userInfo[NativeResourceError.stageKey] as? String {
    case "httpStatus": return "httpStatus"
    case "responseBytes": return "responseBytes"
    case "imageSourcePixels": return "imageSourcePixels"
    case "decodedImageBytes": return "decodedImageBytes"
    default: return "transportOrDecode"
    }
  }

  static func record(_ error: Error, retrying: Bool) {
    guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
    let failure = error as NSError
    let stage = stage(for: error)
    let status = NativeResourceError.httpStatus(for: error) ?? 0
    let actual = failure.userInfo[NativeResourceError.actualKey] as? Double ?? 0
    let limit = failure.userInfo[NativeResourceError.limitKey] as? Double ?? 0
    // Only fixed SDK stage names and numeric diagnostics are public. Never log
    // arbitrary userInfo strings, URLs, headers, bytes or error descriptions.
    logger.debug("Image failure: stage=\(stage, privacy: .public) code=\(failure.code) http=\(status) actual=\(actual) limit=\(limit) automaticRetry=\(retrying)")
  }
}

/// ImageIO validates source dimensions before decoding and never eagerly expands
/// a full-resolution UIImage/NSImage for a thumbnail. The pixel object is immutable.
package enum NativeImageDecoder {
  package struct Pixels: @unchecked Sendable {
    package let image: CGImage
    package let sourceSize: CGSize
  }
  package static func decode(_ data: Data, maximumPixelSize: Int, limits: OpenUIResourceLimits,
                             displaySize: NativeImageDisplaySize? = nil) throws -> Pixels {
    try Task.checkCancellation()
    guard data.count <= max(1, limits.maximumResponseBytes) else {
      throw NativeResourceError.limitExceeded(stage: "responseBytes", actual: Double(data.count),
        limit: Double(max(1, limits.maximumResponseBytes)), code: .cannotDecodeContentData)
    }
    guard let source = CGImageSourceCreateWithData(data as CFData,
        [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      width.isFinite, height.isFinite, width > 0, height > 0 else {
        throw URLError(.cannotDecodeContentData)
    }
    guard width * height <= Double(max(1, limits.maximumImageSourcePixels)) else {
      throw NativeResourceError.limitExceeded(stage: "imageSourcePixels", actual: width * height,
        limit: Double(max(1, limits.maximumImageSourcePixels)), code: .cannotDecodeContentData)
    }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let rotated = (5...8).contains(orientation)
    let sourceSize = CGSize(width: rotated ? height : width, height: rotated ? width : height)
    let cap = max(1, min(maximumPixelSize, limits.maximumImagePixelSize, 2816))
    let target = displaySize?.pixelSize(sourceSize: sourceSize, maximum: cap) ?? cap
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: target,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw URLError(.cannotDecodeContentData)
    }
    try Task.checkCancellation()
    guard image.height > 0, image.bytesPerRow <= (32 * 1024 * 1024) / image.height else {
      throw NativeResourceError.limitExceeded(stage: "decodedImageBytes",
        actual: Double(image.bytesPerRow) * Double(image.height), limit: Double(32 * 1024 * 1024))
    }
    return Pixels(image: image, sourceSize: sourceSize)
  }
}

private struct NativeMediaCacheKey: EnvironmentKey { static let defaultValue: NativeMediaCache? = nil }
private struct NativeMediaSourceKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
  package var openUIMediaSourceReady: Bool {
    get { self[NativeMediaSourceKey.self] }
    set { self[NativeMediaSourceKey.self] = newValue }
  }
  package var openUIMediaCache: NativeMediaCache? {
    get { self[NativeMediaCacheKey.self] }
    set { self[NativeMediaCacheKey.self] = newValue }
  }
}

