import Foundation
import SwiftUI
import ImageIO
import CoreGraphics

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
    package var wasPresented = false
    package var decodedPixelSize: Int = .max
    package init(image: Image, size: CGSize, cost: Int,
                 resourceOwner: any OpenUIResourceLoading, wasPresented: Bool = false,
                 decodedPixelSize: Int = .max) {
      self.image = image; self.size = size; self.cost = cost
      self.resourceOwner = resourceOwner; self.wasPresented = wasPresented
      self.decodedPixelSize = decodedPixelSize
    }
    package func satisfies(_ requested: Int) -> Bool {
      decodedPixelSize >= requested || max(size.width, size.height) <= CGFloat(decodedPixelSize)
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
  private struct DecodeKey: Hashable { let resource: NativeResourceRequestID; let pixelSize: Int }
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
  package subscript(_ key: NativeResourceRequestID) -> Entry? { entries[key] }
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
    guard entry.cost <= maximumCost else { return }
    if let current = entries[key], current.decodedPixelSize > entry.decodedPixelSize { return }
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
                targetPixelSize: Int? = nil) async throws -> Entry {
    try Task.checkCancellation()
    let target = Self.effectivePixelSize(targetPixelSize, limits: loader.resourceLimits)
    if let value = entries[key], value.satisfies(target) { return value }
    guard let request = key.request else { throw URLError(.badURL) }
    let decodeKey = DecodeKey(resource: key, pixelSize: target)
    let waiterID = UUID(), epoch = generation
    let scope = loader.authorizationScopeID
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
            let value = try await Self.load(request, loader: loader, targetPixelSize: target)
            try Task.checkCancellation()
            guard loader.authorizationScopeID == scope else { throw CancellationError() }
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
    guard generation == epoch, loader.authorizationScopeID == scope else { throw CancellationError() }
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
                   targetPixelSize: Int? = nil) async throws -> Entry {
    try await imageAdmission.acquire()
    defer { Task { await imageAdmission.release() } }
    try Task.checkCancellation()
    let scope = loader.authorizationScopeID
    let data = try await loader.data(for: request)
    try Task.checkCancellation()
    let entry = try await prepare(data, loader: loader, targetPixelSize: targetPixelSize)
    guard loader.authorizationScopeID == scope else { throw CancellationError() }
    return entry
  }
  package static func prepare(_ data: Data, loader: any OpenUIResourceLoading,
                      targetPixelSize: Int? = nil) async throws -> Entry {
    let limits = loader.resourceLimits
    let target = effectivePixelSize(targetPixelSize, limits: limits)
    let work = Task.detached(priority: .userInitiated) {
      try NativeImageDecoder.decode(data, maximumPixelSize: target, limits: limits)
    }
    let decoded = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
    try Task.checkCancellation()
    return entry(decoded, loader: loader)
  }
  /// Synchronous entry is retained for small fixtures and explicit native callers.
  /// Live resource consumers use prepare to keep decoding off the UI actor.
  package static func decode(_ data: Data, loader: any OpenUIResourceLoading) throws -> Entry {
    entry(try NativeImageDecoder.decode(data, maximumPixelSize: loader.resourceLimits.maximumImagePixelSize,
      limits: loader.resourceLimits), loader: loader)
  }
  private static func entry(_ decoded: NativeImageDecoder.Pixels, loader: any OpenUIResourceLoading) -> Entry {
    Entry(image: Image(decorative: decoded.image, scale: 1), size: decoded.sourceSize,
      cost: decoded.image.bytesPerRow * decoded.image.height, resourceOwner: loader,
      decodedPixelSize: max(decoded.image.width, decoded.image.height))
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
/// ImageIO validates source dimensions before decoding and never eagerly expands
/// a full-resolution UIImage/NSImage for a thumbnail. The pixel object is immutable.
package enum NativeImageDecoder {
  package struct Pixels: @unchecked Sendable {
    package let image: CGImage
    package let sourceSize: CGSize
  }
  package static func decode(_ data: Data, maximumPixelSize: Int, limits: OpenUIResourceLimits) throws -> Pixels {
    try Task.checkCancellation()
    guard data.count <= max(1, limits.maximumResponseBytes),
      let source = CGImageSourceCreateWithData(data as CFData,
        [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      width.isFinite, height.isFinite, width > 0, height > 0,
      width * height <= Double(max(1, limits.maximumImageSourcePixels)) else {
        throw URLError(.cannotDecodeContentData)
    }
    let target = max(1, min(maximumPixelSize, limits.maximumImagePixelSize, 2816))
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
      throw URLError(.dataLengthExceedsMaximum)
    }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let rotated = (5...8).contains(orientation)
    return Pixels(image: image, sourceSize: CGSize(width: rotated ? height : width, height: rotated ? width : height))
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

