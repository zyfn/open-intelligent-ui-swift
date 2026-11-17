import Foundation
import SwiftUI

/// Default limits are host-overridable, not model-facing language parameters.
/// Bytes describe one response; image pixels describe the uncompressed source.
public struct OpenUIResourceLimits: Sendable, Equatable {
    public var maximumResponseBytes: Int
    public var maximumConcurrentRequests: Int
    public var maximumRedirects: Int
    public var allowsCrossOriginRedirects: Bool
    public var maximumImageSourcePixels: Int
    public var maximumImagePixelSize: Int

    public init(maximumResponseBytes: Int = 20 * 1024 * 1024,
                maximumConcurrentRequests: Int = 4, maximumRedirects: Int = 8,
                allowsCrossOriginRedirects: Bool = false,
                maximumImageSourcePixels: Int = 64_000_000,
                maximumImagePixelSize: Int = 2048) {
        self.maximumResponseBytes = max(1, maximumResponseBytes)
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
        self.maximumRedirects = max(0, maximumRedirects)
        self.allowsCrossOriginRedirects = allowsCrossOriginRedirects
        self.maximumImageSourcePixels = max(1, maximumImageSourcePixels)
        self.maximumImagePixelSize = max(1, maximumImagePixelSize)
    }
}

/// A single injection seam for authorization, resource addressing and transport.
/// Custom transports must enforce their declared response limit while receiving;
/// the SDK additionally checks their returned Data before decoding it.
public protocol OpenUIResourceLoading: AnyObject {
    var resourceLimits: OpenUIResourceLimits { get }
    /// A non-secret epoch changed by a host when the same loader changes accounts/permissions.
    var authorizationScopeID: String { get }
    func request(for source: String, relativeTo baseURL: URL?) -> URLRequest?
    func data(for request: URLRequest) async throws -> Data
}

extension OpenUIResourceLoading {
    public var resourceLimits: OpenUIResourceLimits { OpenUIResourceLimits() }
    public var authorizationScopeID: String { "" }
}

/// Preserve the existing URLError contract while keeping enough non-secret
/// context to distinguish HTTP failures from resource budgets. Consumers must
/// not retain a response or signed URL merely to diagnose an image failure.
package enum NativeResourceError {
    package static let stageKey = "OpenUIResourceStage"
    package static let actualKey = "OpenUIResourceActual"
    package static let limitKey = "OpenUIResourceLimit"
    package static let statusKey = "OpenUIHTTPStatusCode"
    package static let retryAfterKey = "OpenUIRetryAfterSeconds"

    package static func limitExceeded(stage: String, actual: Double, limit: Double,
                                      code: URLError.Code = .dataLengthExceedsMaximum) -> URLError {
        URLError(code, userInfo: [stageKey: stage, actualKey: actual, limitKey: limit])
    }

    package static func httpFailure(_ response: HTTPURLResponse, now: Date = Date()) -> URLError {
        var info: [String: Any] = [stageKey: "httpStatus", statusKey: response.statusCode]
        if let header = response.value(forHTTPHeaderField: "Retry-After") {
            // Invalid or unsupported Retry-After values disable an automatic
            // retry instead of retrying sooner than the server requested.
            let value = header.trimmingCharacters(in: .whitespacesAndNewlines)
            let seconds: Double
            if !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
               let delay = Double(value), delay.isFinite {
                seconds = delay
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
                formatter.isLenient = false
                seconds = formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) } ?? .infinity
            }
            info[retryAfterKey] = seconds
        }
        return URLError(.badServerResponse, userInfo: info)
    }

    package static func httpStatus(for error: Error) -> Int? {
        (error as NSError).userInfo[statusKey] as? Int
    }

    package static func retryAfter(for error: Error) -> Double? {
        (error as NSError).userInfo[retryAfterKey] as? Double
    }
}

/// FIFO admission with cancellation. No sleeping thread or global network queue.
package actor NativeResourceAdmission {
    private let maximum: Int
    private var active = 0
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []
    package init(maximum: Int) { self.maximum = max(1, maximum) }
    package func acquire() async throws {
        try Task.checkCancellation()
        if active < maximum { active += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiting.append((id, continuation)) }
            }
        }, onCancel: { Task { await self.cancel(id) } })
        // The caller owns the permit even if cancellation races with delivery;
        // it installs a release defer before checking cancellation again.
    }
    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(throwing: CancellationError())
    }
    package func release() {
        if !waiting.isEmpty { waiting.removeFirst().1.resume() }
        else { active = max(0, active - 1) }
    }
}

package final class NativeResourceRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    package let limits: OpenUIResourceLimits
    private var redirects = 0
    package init(limits: OpenUIResourceLimits) { self.limits = limits }
    private static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        let schemeA = a.scheme?.lowercased(), schemeB = b.scheme?.lowercased()
        return schemeA == schemeB && a.host?.lowercased() == b.host?.lowercased()
            && (a.port ?? (schemeA == "https" ? 443 : 80)) == (b.port ?? (schemeB == "https" ? 443 : 80))
    }
    package static func permitted(from old: URL?, to new: URL?, limits: OpenUIResourceLimits) -> Bool {
        guard let old, let new, let scheme = new.scheme?.lowercased(),
              ["http", "https"].contains(scheme), new.host?.isEmpty == false,
              new.user == nil, new.password == nil else { return false }
        if old.scheme?.lowercased() == "https", scheme != "https" { return false }
        return sameOrigin(old, new) || limits.allowsCrossOriginRedirects
    }
    package func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= limits.maximumRedirects,
              Self.permitted(from: response.url, to: request.url, limits: limits) else {
            completionHandler(nil); return
        }
        var next = request
        if let old = response.url, let new = request.url, !Self.sameOrigin(old, new) {
            for header in ["Authorization", "Proxy-Authorization", "Cookie"] {
                next.setValue(nil, forHTTPHeaderField: header)
            }
        }
        completionHandler(next)
    }
}

public final class OpenUIURLSessionResourceLoader: OpenUIResourceLoading {
    public static let shared = OpenUIURLSessionResourceLoader()
    private let session: URLSession
    public let resourceLimits: OpenUIResourceLimits
    private let admission: NativeResourceAdmission

    public init(session: URLSession = .shared, limits: OpenUIResourceLimits = .init()) {
        self.session = session; self.resourceLimits = limits
        self.admission = NativeResourceAdmission(maximum: limits.maximumConcurrentRequests)
    }
    public func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
        guard !source.isEmpty,
              let url = URL(string: source, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return URLRequest(url: url)
    }
    public func data(for request: URLRequest) async throws -> Data {
        guard self.request(for: request.url?.absoluteString ?? "", relativeTo: nil) != nil else {
            throw URLError(.unsupportedURL)
        }
        try await admission.acquire()
        defer { Task { await admission.release() } }
        try Task.checkCancellation()
        let policy = NativeResourceRedirectPolicy(limits: resourceLimits)
        let (bytes, response) = try await session.bytes(for: request, delegate: policy)
        defer { bytes.task.cancel() }
        if request.url?.scheme?.lowercased() == "https", response.url?.scheme?.lowercased() != "https" {
            throw URLError(.appTransportSecurityRequiresSecureConnection)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NativeResourceError.httpFailure(http)
        }
        let limit = max(1, resourceLimits.maximumResponseBytes)
        guard response.expectedContentLength <= Int64(limit) else {
            throw NativeResourceError.limitExceeded(stage: "responseBytes",
                actual: Double(response.expectedContentLength), limit: Double(limit))
        }
        return try await withTaskCancellationHandler(operation: {
            var data = Data()
            var chunk: [UInt8] = []; chunk.reserveCapacity(16_384)
            for try await byte in bytes {
                guard data.count < limit - chunk.count else {
                    throw NativeResourceError.limitExceeded(stage: "responseBytes",
                        actual: Double(data.count) + Double(chunk.count) + 1, limit: Double(limit))
                }
                chunk.append(byte)
                if chunk.count == 16_384 {
                    try Task.checkCancellation()
                    data.append(contentsOf: chunk); chunk.removeAll(keepingCapacity: true)
                }
            }
            try Task.checkCancellation()
            data.append(contentsOf: chunk)
            return data
        }, onCancel: { bytes.task.cancel() })
    }
}

public struct OpenUIResourceContext {
    public var baseURL: URL?
    public var loader: any OpenUIResourceLoading

    public init(baseURL: URL? = nil, loader: any OpenUIResourceLoading = OpenUIURLSessionResourceLoader.shared) {
        self.baseURL = baseURL
        self.loader = loader
    }

    public func request(for source: String?) -> URLRequest? {
        source.flatMap { loader.request(for: $0, relativeTo: baseURL) }
    }
}

/// Presentation-scoped transport shared by images and native Markdown.
/// A view relocation does not own/cancel the underlying request. Credentials,
/// resource policy and source addresses continue to belong to the injected loader.
@MainActor package final class NativeResourceStore {
    package convenience init() { self.init(budget: NativeResourceCacheBudgets.responseBytes) }
    init(budget: NativeResourceCacheBudget) {
        completed = NativeResourceCache(maximumCost: 2 * 1024 * 1024, maximumCount: 16, budget: budget)
    }
    private struct OwnerKey: Hashable {
        let identity: ObjectIdentifier
        let scope: String
    }
    private struct Key: Hashable {
        let request: URLRequest
        let owner: OwnerKey
        let policy: UInt
    }
    private final class Pending {
        let id = UUID()
        var task: Task<Void, Never>?
        var waiters: [UUID: CheckedContinuation<Data, Error>] = [:]
    }
    private var loaders: [OwnerKey: ScopedResourceLoader] = [:]
    private var pending: [Key: Pending] = [:]
    private let completed: NativeResourceCache<Key, Data>
    private var generation = 0
    package var pendingSubscriberCount: Int { pending.values.reduce(0) { $0 + $1.waiters.count } }

    package func scoped(_ context: OpenUIResourceContext) -> OpenUIResourceContext {
        var owner = context.loader
        while let scoped = owner as? ScopedResourceLoader { owner = scoped.owner }
        let key = OwnerKey(identity: ObjectIdentifier(owner), scope: owner.authorizationScopeID)
        // Retire other epochs of this same transport instead of retaining
        // cached private responses indefinitely after an account switch.
        for old in loaders.keys.filter({ $0.identity == key.identity && $0 != key }) {
            loaders[old]?.invalidateScope()
            loaders.removeValue(forKey: old)
            for resource in completed.keys.filter({ $0.owner == old }) {
                completed.removeValue(forKey: resource)
            }
            for resource in pending.keys.filter({ $0.owner == old }) {
                guard let group = pending.removeValue(forKey: resource) else { continue }
                group.task?.cancel(); group.task = nil
                for waiter in group.waiters.values { waiter.resume(throwing: CancellationError()) }
                group.waiters.removeAll()
            }
        }
        let loader: ScopedResourceLoader
        if let existing = loaders[key] { loader = existing }
        else {
            loader = ScopedResourceLoader(owner: owner, store: self, epoch: generation, scope: key.scope)
            loaders[key] = loader
        }
        return .init(baseURL: context.baseURL, loader: loader)
    }

    fileprivate func data(_ request: URLRequest, owner: any OpenUIResourceLoading,
                          epoch: Int, scope: String) async throws -> Data {
        try Task.checkCancellation()
        guard epoch == generation, owner.authorizationScopeID == scope else { throw CancellationError() }
        let key = Key(request: request,
            owner: OwnerKey(identity: ObjectIdentifier(owner), scope: scope), policy: request.cachePolicy.rawValue)
        let retains = request.cachePolicy == .useProtocolCachePolicy
            || request.cachePolicy == .returnCacheDataElseLoad || request.cachePolicy == .returnCacheDataDontLoad
        if retains, let data = completed[key] { return data }
        let waiterID = UUID()
        let data: Data = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if let group = pending[key] {
                    group.waiters[waiterID] = continuation
                    return
                }
                let group = Pending()
                group.waiters[waiterID] = continuation
                pending[key] = group
                let id = group.id
                group.task = Task { @MainActor [weak self] in
                    let result: Result<Data, Error>
                    do {
                        let data = try await owner.data(for: request)
                        try Task.checkCancellation()
                        guard owner.authorizationScopeID == scope else { throw CancellationError() }
                        guard data.count <= max(1, owner.resourceLimits.maximumResponseBytes) else {
                            throw NativeResourceError.limitExceeded(stage: "responseBytes", actual: Double(data.count),
                                limit: Double(max(1, owner.resourceLimits.maximumResponseBytes)))
                        }
                        result = .success(data)
                    } catch { result = .failure(error) }
                    self?.finish(key, id: id, epoch: epoch, retains: retains, result: result)
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in self?.cancel(key, waiterID: waiterID, epoch: epoch) }
        })
        // Completion may resume this waiter before its cancellation/reset is
        // processed. Validate the subscriber and its lease again on return;
        // another live subscriber still owns the shared transport result.
        try Task.checkCancellation()
        guard epoch == generation, owner.authorizationScopeID == scope else { throw CancellationError() }
        return data
    }

    private func finish(_ key: Key, id: UUID, epoch: Int, retains: Bool, result: Result<Data, Error>) {
        guard generation == epoch, let group = pending[key], group.id == id else { return }
        pending.removeValue(forKey: key)
        if retains, case .success(let data) = result {
            completed.insert(data, for: key, cost: data.count)
        }
        for continuation in group.waiters.values { continuation.resume(with: result) }
        group.waiters.removeAll(); group.task = nil
    }
    private func cancel(_ key: Key, waiterID: UUID, epoch: Int) {
        guard generation == epoch, let group = pending[key],
              let continuation = group.waiters.removeValue(forKey: waiterID) else { return }
        continuation.resume(throwing: CancellationError())
        if group.waiters.isEmpty {
            pending.removeValue(forKey: key)
            group.task?.cancel(); group.task = nil
        }
    }
    package func removeAll() {
        generation &+= 1
        for loader in loaders.values { loader.invalidateScope() }
        let requests = Array(pending.values)
        pending.removeAll()
        for group in requests {
            group.task?.cancel(); group.task = nil
            for continuation in group.waiters.values { continuation.resume(throwing: CancellationError()) }
            group.waiters.removeAll()
        }
        completed.removeAll(); loaders.removeAll()
    }
}

/// Resource consumers can check a frozen scope without constructing another
/// request. A host may sign each request with a fresh nonce or timestamp.
package func openUIResourceScopeIsCurrent(_ loader: any OpenUIResourceLoading,
                                          authorizationScope: String) -> Bool {
    guard loader.authorizationScopeID == authorizationScope else { return false }
    return (loader as? ScopedResourceLoader)?.isCurrent ?? true
}

/// Admission is shared by the transport owner; cached pixels remain scoped to
/// each document's wrapper so one document cannot reuse another document's lease.
package func openUIResourceOwnerIdentity(_ loader: any OpenUIResourceLoading) -> ObjectIdentifier {
    var owner = loader
    while let scoped = owner as? ScopedResourceLoader { owner = scoped.owner }
    return ObjectIdentifier(owner)
}

private final class ResourceScopeLifetime {
    private let lock = NSLock()
    private var active = true
    var isCurrent: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        active = false
    }
}

private final class ScopedResourceLoader: OpenUIResourceLoading {
    fileprivate let owner: any OpenUIResourceLoading
    private weak var store: NativeResourceStore?
    private let epoch: Int
    private let lifetime = ResourceScopeLifetime()
    let authorizationScopeID: String
    init(owner: any OpenUIResourceLoading, store: NativeResourceStore, epoch: Int, scope: String) {
        self.owner = owner; self.store = store; self.epoch = epoch; self.authorizationScopeID = scope
    }
    var resourceLimits: OpenUIResourceLimits { owner.resourceLimits }
    fileprivate var isCurrent: Bool {
        lifetime.isCurrent && store != nil && owner.authorizationScopeID == authorizationScopeID
    }
    fileprivate func invalidateScope() { lifetime.invalidate() }
    func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
        guard isCurrent else { return nil }
        return owner.request(for: source, relativeTo: baseURL)
    }
    @MainActor func data(for request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        guard isCurrent, let store else { throw CancellationError() }
        return try await store.data(request, owner: owner, epoch: epoch, scope: authorizationScopeID)
    }
}

private struct OpenUIResourceContextKey: EnvironmentKey {
    static let defaultValue = OpenUIResourceContext()
}

extension EnvironmentValues {
    public var openUIResourceContext: OpenUIResourceContext {
        get { self[OpenUIResourceContextKey.self] }
        set { self[OpenUIResourceContextKey.self] = newValue }
    }
}

extension View {
    public func openUIResourceContext(_ context: OpenUIResourceContext) -> some View {
        environment(\.openUIResourceContext, context)
    }
}

package struct NativeResourceRequestID: Hashable {
    package let request: URLRequest?
    package let loader: ObjectIdentifier
    package let attempt: Int
    package var authorizationScope: String

    package init(request: URLRequest?, loader: ObjectIdentifier, attempt: Int,
                 authorizationScope: String = "") {
        self.request = request
        self.loader = loader
        self.attempt = attempt
        self.authorizationScope = authorizationScope
    }
}
