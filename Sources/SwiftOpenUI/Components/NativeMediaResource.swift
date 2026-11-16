import Foundation
import SwiftLang

/// A presentation target is stable even when a host signs every request with
/// a new nonce. It owns its loader so cached identities cannot be recycled.
struct NativeMediaResourceTarget: Hashable {
  let source: String?
  private let exactSource: OpenUIString?
  let baseURL: URL?
  let loader: any OpenUIResourceLoading
  let authorizationScope: String
  let limits: OpenUIResourceLimits
  let attempt: Int

  init(source: String?, resources: OpenUIResourceContext, attempt: Int = 0) {
    self.source = source; exactSource = source.map { OpenUIString($0) }
    baseURL = resources.baseURL; loader = resources.loader
    authorizationScope = resources.loader.authorizationScopeID
    limits = resources.loader.resourceLimits; self.attempt = attempt
  }

  var isCurrent: Bool {
    openUIResourceScopeIsCurrent(loader, authorizationScope: authorizationScope)
      && loader.resourceLimits == limits
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.exactSource == rhs.exactSource && lhs.baseURL == rhs.baseURL
      && ObjectIdentifier(lhs.loader) == ObjectIdentifier(rhs.loader)
      && lhs.authorizationScope == rhs.authorizationScope && lhs.limits == rhs.limits
      && lhs.attempt == rhs.attempt
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(exactSource); hasher.combine(baseURL); hasher.combine(ObjectIdentifier(loader))
    hasher.combine(authorizationScope); hasher.combine(attempt)
    hasher.combine(limits.maximumResponseBytes); hasher.combine(limits.maximumConcurrentRequests)
    hasher.combine(limits.maximumRedirects); hasher.combine(limits.allowsCrossOriginRedirects)
    hasher.combine(limits.maximumImageSourcePixels); hasher.combine(limits.maximumImagePixelSize)
  }

  @MainActor func cachedRequest(in cache: NativeMediaCache?) -> NativeResourceRequestID? {
    guard isCurrent else { return nil }
    return cache?.requestSnapshot(for: self)
  }

  @MainActor func cachedImage(in cache: NativeMediaCache?) -> NativeMediaCache.Entry? {
    guard let request = cachedRequest(in: cache) else { return nil }
    return cache?[request]
  }

  /// Call only when starting a resource attempt, never while computing a view
  /// or checking whether an asynchronous result still belongs to that view.
  @MainActor func resolve(in cache: NativeMediaCache?) -> NativeResourceRequestID {
    if let retained = cachedRequest(in: cache) { return retained }
    var request = isCurrent ? source.flatMap { loader.request(for: $0, relativeTo: baseURL) } : nil
    if attempt > 0 { request?.cachePolicy = .reloadIgnoringLocalCacheData }
    let id = NativeResourceRequestID(request: request, loader: ObjectIdentifier(loader),
      attempt: attempt, authorizationScope: authorizationScope)
    if isCurrent { cache?.retainRequestSnapshot(id, for: self, owner: loader) }
    return id
  }
}

/// The mounted view keeps its successful phase even after the bounded shared
/// cache evicts an entry. A cache reset cannot revive this request snapshot.
struct NativeMediaRequestSnapshot {
  let target: NativeMediaResourceTarget
  let request: NativeResourceRequestID
  private let cacheIdentity: ObjectIdentifier?
  private let generation: Int?

  @MainActor init(target: NativeMediaResourceTarget, cache: NativeMediaCache?) {
    self.target = target; request = target.resolve(in: cache)
    cacheIdentity = cache.map(ObjectIdentifier.init); generation = cache?.generation
  }

  @MainActor func matches(_ target: NativeMediaResourceTarget, cache: NativeMediaCache?) -> Bool {
    self.target == target && target.isCurrent
      && cacheIdentity == cache.map(ObjectIdentifier.init) && generation == cache?.generation
  }
}
