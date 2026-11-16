import Foundation
import ImageIO
import CoreGraphics
import CoreImage
import SwiftLang

/// Transport identity is kept out of strings/logs: requests can contain credentials.
/// Holding the loader with a cached image also prevents ObjectIdentifier reuse.
struct ImageResourceScope: Hashable {
    let loader: ObjectIdentifier
    let authorization: String
    let baseURL: URL?
    let limits: OpenUIResourceLimits

    init(_ resources: OpenUIResourceContext) {
        loader = ObjectIdentifier(resources.loader)
        authorization = resources.loader.authorizationScopeID
        baseURL = resources.baseURL
        limits = resources.loader.resourceLimits
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(loader); hasher.combine(authorization); hasher.combine(baseURL)
        hasher.combine(limits.maximumResponseBytes); hasher.combine(limits.maximumConcurrentRequests)
        hasher.combine(limits.maximumRedirects); hasher.combine(limits.allowsCrossOriginRedirects)
        hasher.combine(limits.maximumImageSourcePixels); hasher.combine(limits.maximumImagePixelSize)
    }
}

struct ImageResourceTarget: Hashable {
    let scope: ImageResourceScope
    let source: String?
    let revision: String

    init(source: String?, resources: OpenUIResourceContext, revision: String = "") {
        scope = ImageResourceScope(resources)
        self.source = source; self.revision = revision
    }
}

struct ImageResourceID: Hashable {
    let target: ImageResourceTarget
    let request: URLRequest?
    let attempt: Int
    var scope: ImageResourceScope { target.scope }
    var source: String? { target.source }
    var revision: String { target.revision }
}

struct ImageResource {
    let id: ImageResourceID
    let loader: any OpenUIResourceLoading

    init(source: String?, resources: OpenUIResourceContext, revision: String = "", attempt: Int = 0) {
        loader = resources.loader
        let target = ImageResourceTarget(source: source, resources: resources, revision: revision)
        var request = resources.request(for: source)
        // Revision/retry must also bypass the platform transport's retained bytes.
        if attempt > 0 || !revision.isEmpty { request?.cachePolicy = .reloadIgnoringLocalCacheData }
        id = ImageResourceID(target: target, request: request, attempt: attempt)
    }

    var isCurrent: Bool {
        // Validate the captured epoch without asking a signing resolver to
        // construct another request. A resource owns exactly one request.
        openUIResourceScopeIsCurrent(loader, authorizationScope: id.scope.authorization)
            && loader.resourceLimits == id.scope.limits
    }
}

private enum ImageCacheKey: Hashable {
    case image(ImageResourceID, Int)
    case frame(ImageResourceTarget, ObjectIdentifier, CGFloat)
}

/// Coalesced requests with bounded transfer, decoding and retained-cache costs.
actor ImagePipeline {
    static let shared = ImagePipeline()
    private let defaultLoader: any OpenUIResourceLoading
    private let permits: ImageRequestPermits
    private let cache = ImageMemoryCache(countLimit: 40, costLimit: 64 * 1024 * 1024)
    private struct AdmissionKey: Hashable {
        let loader: ObjectIdentifier
        let maximum: Int
    }
    private struct Admission {
        let permits: ImageRequestPermits
        var users: Int
    }
    private var admissions: [AdmissionKey: Admission] = [:]
    private struct Pending {
        let id: UUID
        let task: Task<Void, Never>
        var consumers: [UUID: CheckedContinuation<CGImage, Error>]
    }
    private var pending: [ImageCacheKey: Pending] = [:]
    var pendingConsumerCount: Int { pending.values.reduce(0) { $0 + $1.consumers.count } }

    init(session: URLSession = .shared, maximumConcurrentRequests: Int = 4,
         maximumResponseBytes: Int = 20 * 1024 * 1024) {
        defaultLoader = OpenUIURLSessionResourceLoader(session: session, limits: OpenUIResourceLimits(
            maximumResponseBytes: maximumResponseBytes, maximumConcurrentRequests: maximumConcurrentRequests))
        permits = ImageRequestPermits(limit: maximumConcurrentRequests)
    }

    nonisolated static func effectiveDimension(_ requested: Int, limits: OpenUIResourceLimits) -> Int {
        max(1, min(4096, requested, limits.maximumImagePixelSize))
    }

    func load(_ url: URL, maximumDimension: Int = 1600, revision: String = "") async throws -> CGImage {
        try await load(ImageResource(source: url.absoluteString, resources: .init(loader: defaultLoader),
                                     revision: revision), maximumDimension: maximumDimension)
    }

    func load(_ resource: ImageResource, maximumDimension: Int = 1600) async throws -> CGImage {
        try Task.checkCancellation()
        guard resource.isCurrent else { throw CancellationError() }
        guard resource.id.request != nil else { throw URLError(.unsupportedURL) }
        let dimension = Self.effectiveDimension(maximumDimension, limits: resource.id.scope.limits)
        let key = ImageCacheKey.image(resource.id, dimension)
        if let image = cache.image(for: key) { OpenIntelligentUIPerformance.record("image.cache.hit"); return image }
        let consumer = UUID()
        let image = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if var work = pending[key] {
                    work.consumers[consumer] = continuation
                    pending[key] = work
                } else {
                    let workID = UUID()
                    let task = Task {
                        do {
                            let image = try await fetch(resource, dimension: dimension)
                            finish(key: key, workID: workID, owner: resource.loader, result: .success(image))
                        } catch { finish(key: key, workID: workID, owner: resource.loader, result: .failure(error)) }
                    }
                    pending[key] = Pending(id: workID, task: task, consumers: [consumer: continuation])
                }
            }
        } onCancel: {
            Task { await self.release(consumer, key: key) }
        }
        try Task.checkCancellation()
        guard resource.isCurrent else { throw CancellationError() }
        return image
    }

    private func fetch(_ resource: ImageResource, dimension: Int) async throws -> CGImage {
        let scope = resource.id.scope
        let admissionKey = AdmissionKey(loader: openUIResourceOwnerIdentity(resource.loader),
                                        maximum: max(1, scope.limits.maximumConcurrentRequests))
        var admission = admissions[admissionKey] ?? Admission(permits: ImageRequestPermits(limit: admissionKey.maximum), users: 0)
        admission.users += 1; admissions[admissionKey] = admission
        let scopePermits = admission.permits
        defer {
            if var current = admissions[admissionKey] {
                current.users -= 1
                admissions[admissionKey] = current.users == 0 ? nil : current
            }
        }
        try await permits.acquire()
        defer { Task { await permits.release() } }
        try await scopePermits.acquire()
        defer { Task { await scopePermits.release() } }
        try Task.checkCancellation()
        guard resource.isCurrent else { throw CancellationError() }
        guard let request = resource.id.request else { throw URLError(.unsupportedURL) }
        OpenIntelligentUIPerformance.record("image.request")
        let data = try await resource.loader.data(for: request)
        try Task.checkCancellation()
        guard resource.isCurrent else { throw CancellationError() }
        guard data.count <= max(1, scope.limits.maximumResponseBytes) else { throw URLError(.dataLengthExceedsMaximum) }
        let image = try Self.decode(data, maximumDimension: dimension, limits: scope.limits)
        try Task.checkCancellation()
        guard resource.isCurrent else { throw CancellationError() }
        return image
    }

    private func finish(key: ImageCacheKey, workID: UUID, owner: any OpenUIResourceLoading, result: Result<CGImage, Error>) {
        guard let work = pending[key], work.id == workID else { return }
        pending[key] = nil
        if case .success(let image) = result { cache.insert(image, for: key, owner: owner) }
        for continuation in work.consumers.values { continuation.resume(with: result) }
    }

    /// Executes on the same non-UI actor; callers retain cancellation and no detached jobs accumulate.
    func framed(_ image: CGImage, target: ImageResourceTarget, loader: any OpenUIResourceLoading, ratio: CGFloat) throws -> CGImage? {
        try Task.checkCancellation()
        guard openUIResourceScopeIsCurrent(loader, authorizationScope: target.scope.authorization),
              loader.resourceLimits == target.scope.limits else { throw CancellationError() }
        let key = ImageCacheKey.frame(target, ObjectIdentifier(image), ratio)
        if let cached = cache.image(for: key) { return cached }
        guard let framed = OpenIntelligentUIPerformance.measure("image.frame", { ImageFraming.contained(image, ratio: ratio) }) else { return nil }
        try Task.checkCancellation()
        cache.insert(framed, for: key, owner: loader, original: image)
        return framed
    }

    private func release(_ consumer: UUID, key: ImageCacheKey) {
        guard var work = pending[key], let continuation = work.consumers.removeValue(forKey: consumer) else { return }
        continuation.resume(throwing: CancellationError())
        if work.consumers.isEmpty {
            pending[key] = nil
            OpenIntelligentUIPerformance.record("image.cancel")
            work.task.cancel()
        } else { pending[key] = work }
    }

    private static func decode(_ data: Data, maximumDimension: Int, limits: OpenUIResourceLimits) throws -> CGImage {
        try OpenIntelligentUIPerformance.measure("image.decode") { try decodeImage(data, maximumDimension: maximumDimension, limits: limits) }
    }

    private static func decodeImage(_ data: Data, maximumDimension: Int, limits: OpenUIResourceLimits) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0,
              width <= 100_000, height <= 100_000, width * height <= Double(max(1, limits.maximumImageSourcePixels)),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        return image
    }
}

/// A small deterministic LRU. This bounds retained cache entries, not images held by visible views.
private final class ImageMemoryCache {
    private struct Entry {
        let image: CGImage
        let owner: any OpenUIResourceLoading
        let original: CGImage?
        let cost: Int
        var access: UInt64
    }
    private let countLimit: Int
    private let costLimit: Int
    private var entries: [ImageCacheKey: Entry] = [:]
    private var cost = 0
    private var access: UInt64 = 0
    init(countLimit: Int, costLimit: Int) { self.countLimit = countLimit; self.costLimit = costLimit }
    func image(for key: ImageCacheKey) -> CGImage? {
        guard var entry = entries[key] else { return nil }
        access &+= 1; entry.access = access; entries[key] = entry
        return entry.image
    }
    func insert(_ image: CGImage, for key: ImageCacheKey, owner: any OpenUIResourceLoading, original: CGImage? = nil) {
        // Frame entries retain their original so its identity cannot be reused.
        let imageCost = image.bytesPerRow * image.height + (original.map { $0.bytesPerRow * $0.height } ?? 0)
        guard imageCost <= costLimit else { return }
        if let old = entries.removeValue(forKey: key) { cost -= old.cost }
        while entries.count >= countLimit || cost + imageCost > costLimit {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access }) else { break }
            cost -= oldest.value.cost
            entries[oldest.key] = nil
        }
        access &+= 1
        entries[key] = Entry(image: image, owner: owner, original: original, cost: imageCost, access: access); cost += imageCost
    }
}

private actor ImageRequestPermits {
    private struct Waiter { let id: UUID; let continuation: CheckedContinuation<Void, Error> }
    private let limit: Int
    private var active = 0
    private var waiters: [Waiter] = []
    init(limit: Int) { self.limit = max(1, limit) }
    func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if active < limit { active += 1; continuation.resume() }
                else { waiters.append(Waiter(id: id, continuation: continuation)) }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func release() {
        if waiters.isEmpty { active = max(0, active - 1) }
        else { waiters.removeFirst().continuation.resume() }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

/// Fits the intact photo over softly interpolated edge colors, without duplicating its subject.
enum ImageFraming {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    static func contained(_ source: CGImage, ratio: CGFloat) -> CGImage? {
        guard ratio.isFinite, ratio > 0 else { return nil }
        var image = CIImage(cgImage: source)
        let targetWidth = max(CGFloat(source.width), CGFloat(source.height) * ratio)
        let targetHeight = max(CGFloat(source.height), CGFloat(source.width) / ratio)
        let scale = min(1, 2048 / max(targetWidth, targetHeight))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let width = targetWidth * scale, height = targetHeight * scale
        let rect = CGRect(x: image.extent.midX - width / 2, y: image.extent.midY - height / 2, width: width, height: height)
        let space = CGColorSpaceCreateDeviceRGB()
        let bands = 8, strip = max(1, image.extent.width * 0.015)
        var colors = [UInt8](repeating: 0, count: 2 * bands * 4)
        for band in 0..<bands {
            guard !Task.isCancelled else { return nil }
            for side in 0..<2 {
                let region = CGRect(x: side == 0 ? 0 : image.extent.width - strip,
                                    y: CGFloat(band) * image.extent.height / CGFloat(bands),
                                    width: strip, height: image.extent.height / CGFloat(bands))
                let average = image.cropped(to: region).applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: region)])
                var pixel = [UInt8](repeating: 0, count: 4)
                pixel.withUnsafeMutableBytes { bytes in
                    context.render(average, toBitmap: bytes.baseAddress!, rowBytes: 4,
                                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: space)
                }
                let offset = (band * 2 + side) * 4
                colors.replaceSubrange(offset..<offset + 4, with: pixel)
            }
        }
        let field = CIImage(bitmapData: Data(colors), bytesPerRow: 8, size: CGSize(width: 2, height: bands), format: .RGBA8, colorSpace: space)
            .transformed(by: CGAffineTransform(scaleX: image.extent.width / 2, y: image.extent.height / CGFloat(bands)))
        let blur = max(8, min(width, height) * 0.06)
        let backdrop = field.clampedToExtent().cropped(to: rect.insetBy(dx: -blur * 3, dy: -blur * 3))
            .applyingGaussianBlur(sigma: blur).cropped(to: rect)
        let fade = max(4, min(image.extent.width, image.extent.height) * 0.05)
        let masks = [
            gradient(from: CGPoint(x: -fade, y: 0), to: .zero, reversed: true),
            gradient(from: CGPoint(x: image.extent.maxX, y: 0), to: CGPoint(x: image.extent.maxX + fade, y: 0)),
            gradient(from: CGPoint(x: 0, y: -fade), to: .zero, reversed: true),
            gradient(from: CGPoint(x: 0, y: image.extent.maxY), to: CGPoint(x: 0, y: image.extent.maxY + fade))
        ]
        let mask = masks.dropFirst().reduce(masks[0]) { $0.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: $1]) }
        let seamless = backdrop.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image.clampedToExtent(), kCIInputMaskImageKey: mask])
        return context.createCGImage(image.composited(over: seamless).cropped(to: rect), from: rect)
    }
    private static func gradient(from start: CGPoint, to end: CGPoint, reversed: Bool = false) -> CIImage {
        CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(cgPoint: start), "inputPoint1": CIVector(cgPoint: end),
            "inputColor0": reversed ? CIColor.white : CIColor.black,
            "inputColor1": reversed ? CIColor.black : CIColor.white
        ])?.outputImage ?? CIImage(color: .black)
    }
}
