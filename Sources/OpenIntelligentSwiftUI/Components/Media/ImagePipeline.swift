import Foundation
import ImageIO
import CoreGraphics
import CoreImage

/// Coalesced requests with bounded transfer, decoding and retained-cache costs.
actor ImagePipeline {
    static let shared = ImagePipeline()
    private let downloads: BoundedImageDownloads
    private let permits: ImageRequestPermits
    private let cache = ImageMemoryCache(countLimit: 40, costLimit: 64 * 1024 * 1024)
    private struct Pending {
        let id: UUID
        let task: Task<Void, Never>
        var consumers: [UUID: CheckedContinuation<CGImage, Error>]
    }
    private var pending: [String: Pending] = [:]
    var pendingConsumerCount: Int { pending.values.reduce(0) { $0 + $1.consumers.count } }

    init(session: URLSession = .shared, maximumConcurrentRequests: Int = 4,
         maximumResponseBytes: Int = 20 * 1024 * 1024) {
        downloads = BoundedImageDownloads(configuration: session.configuration, maximumBytes: maximumResponseBytes)
        permits = ImageRequestPermits(limit: maximumConcurrentRequests)
    }

    deinit { downloads.invalidate() }

    func load(_ url: URL, maximumDimension: Int = 1600, revision: String = "") async throws -> CGImage {
        try Task.checkCancellation()
        let dimension = min(4096, max(64, maximumDimension))
        let resource = "\(url.absoluteString.utf8.count):\(url.absoluteString)\(revision.utf8.count):\(revision)"
        let key = "image:\(resource):\(dimension)"
        if let image = cache.image(for: key) { IntelligentUIPerformance.record("image.cache.hit"); return image }
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
                            let image = try await fetch(url, dimension: dimension)
                            finish(key: key, workID: workID, result: .success(image))
                        } catch { finish(key: key, workID: workID, result: .failure(error)) }
                    }
                    pending[key] = Pending(id: workID, task: task, consumers: [consumer: continuation])
                }
            }
        } onCancel: {
            Task { await self.release(consumer, key: key) }
        }
        try Task.checkCancellation()
        return image
    }

    private func fetch(_ url: URL, dimension: Int) async throws -> CGImage {
        try await permits.acquire()
        do {
            try Task.checkCancellation()
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            let data = try await downloads.data(for: request)
            try Task.checkCancellation()
            let image = try Self.decode(data, maximumDimension: dimension)
            try Task.checkCancellation()
            await permits.release()
            return image
        } catch {
            await permits.release()
            throw error
        }
    }

    private func finish(key: String, workID: UUID, result: Result<CGImage, Error>) {
        guard let work = pending[key], work.id == workID else { return }
        pending[key] = nil
        if case .success(let image) = result { cache.insert(image, for: key) }
        for continuation in work.consumers.values { continuation.resume(with: result) }
    }

    /// Executes on the same non-UI actor; callers retain cancellation and no detached jobs accumulate.
    func framed(_ image: CGImage, resource: String, ratio: CGFloat) throws -> CGImage? {
        try Task.checkCancellation()
        let key = "frame:\(resource.utf8.count):\(resource):\(image.width)x\(image.height):\(ratio)"
        if let cached = cache.image(for: key) { return cached }
        guard let framed = IntelligentUIPerformance.measure("image.frame", { ImageFraming.contained(image, ratio: ratio) }) else { return nil }
        try Task.checkCancellation()
        cache.insert(framed, for: key)
        return framed
    }

    private func release(_ consumer: UUID, key: String) {
        guard var work = pending[key], let continuation = work.consumers.removeValue(forKey: consumer) else { return }
        continuation.resume(throwing: CancellationError())
        if work.consumers.isEmpty {
            pending[key] = nil
            IntelligentUIPerformance.record("image.cancel")
            work.task.cancel()
        } else { pending[key] = work }
    }

    private static func decode(_ data: Data, maximumDimension: Int) throws -> CGImage {
        try IntelligentUIPerformance.measure("image.decode") { try decodeImage(data, maximumDimension: maximumDimension) }
    }

    private static func decodeImage(_ data: Data, maximumDimension: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0,
              width <= 100_000, height <= 100_000, width * height <= 100_000_000,
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
    private struct Entry { let image: CGImage; var access: UInt64 }
    private let countLimit: Int
    private let costLimit: Int
    private var entries: [String: Entry] = [:]
    private var cost = 0
    private var access: UInt64 = 0
    init(countLimit: Int, costLimit: Int) { self.countLimit = countLimit; self.costLimit = costLimit }
    func image(for key: String) -> CGImage? {
        guard var entry = entries[key] else { return nil }
        access &+= 1; entry.access = access; entries[key] = entry
        return entry.image
    }
    func insert(_ image: CGImage, for key: String) {
        let imageCost = image.bytesPerRow * image.height
        guard imageCost <= costLimit else { return }
        if let old = entries.removeValue(forKey: key) { cost -= old.image.bytesPerRow * old.image.height }
        while entries.count >= countLimit || cost + imageCost > costLimit {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access }) else { break }
            cost -= oldest.value.image.bytesPerRow * oldest.value.image.height
            entries[oldest.key] = nil
        }
        access &+= 1
        entries[key] = Entry(image: image, access: access); cost += imageCost
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

/// Receives bounded chunks instead of first materializing an arbitrarily large response.
private final class BoundedImageDownloads: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Entry {
        let continuation: CheckedContinuation<Data, Error>
        var data = Data()
        init(_ continuation: CheckedContinuation<Data, Error>) { self.continuation = continuation }
    }
    private final class Handle: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDataTask?
        private var cancelled = false
        func attach(_ task: URLSessionDataTask) {
            lock.lock(); self.task = task; let cancelled = cancelled; lock.unlock()
            if cancelled { task.cancel() }
        }
        func cancel() {
            lock.lock(); cancelled = true; let task = task; lock.unlock()
            task?.cancel()
        }
    }
    private let maximumBytes: Int
    private let lock = NSLock()
    private var entries: [Int: Entry] = [:]
    private var session: URLSession!
    init(configuration: URLSessionConfiguration, maximumBytes: Int) {
        self.maximumBytes = max(1, maximumBytes)
        super.init()
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }
    func invalidate() { session.invalidateAndCancel() }
    func data(for request: URLRequest) async throws -> Data {
        let handle = Handle()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                IntelligentUIPerformance.record("image.request")
                let task = session.dataTask(with: request)
                lock.lock(); entries[task.taskIdentifier] = Entry(continuation); lock.unlock()
                handle.attach(task)
                task.resume()
            }
        } onCancel: { handle.cancel() }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            finish(dataTask, error: URLError(.badServerResponse)); completionHandler(.cancel); return
        }
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            finish(dataTask, error: URLError(.dataLengthExceedsMaximum)); completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let entry = entries[dataTask.taskIdentifier] else { lock.unlock(); return }
        let exceedsLimit = data.count > maximumBytes - entry.data.count
        if !exceedsLimit { entry.data.append(data) }
        lock.unlock()
        if exceedsLimit { finish(dataTask, error: URLError(.dataLengthExceedsMaximum)); dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(task, error: error)
    }
    private func finish(_ task: URLSessionTask, error: Error?) {
        lock.lock(); let entry = entries.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let entry else { return }
        if let error { entry.continuation.resume(throwing: error) }
        else { entry.continuation.resume(returning: entry.data) }
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
