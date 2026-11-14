import XCTest
import Foundation
import SwiftUI
import CoreGraphics
import ImageIO
import OpenUILang
import OpenUICore
@testable import OpenIntelligentSwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

final class ResourceInjectionTests: XCTestCase {
    func testSigningResolverCreatesOneRequestSnapshotForTheWholeLoad() async throws {
        let transport = InjectedImageTransport(data: try png())
        let loader = InjectedImageLoader(transport: transport, signsEachRequest: true)
        let resource = ImageResource(source: "https://images.example/signed", resources: .init(loader: loader))
        let pipeline = ImagePipeline()
        let image = try await pipeline.load(resource)
        let cached = try await pipeline.load(resource)
        XCTAssertTrue(image === cached)
        XCTAssertEqual(loader.resolutionCount, 1, "Epoch checks must not regenerate a signed request")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "X-Request-Nonce"), "1")
    }

    func testInjectedLoaderResolvesRelativeSourcesPreservesHeadersAndLimitsPixels() async throws {
        let transport = InjectedImageTransport(data: try png())
        let loader = InjectedImageLoader(transport: transport, limits: .init(maximumImagePixelSize: 32))
        let resources = OpenUIResourceContext(baseURL: URL(string: "https://images.example/account/"), loader: loader)
        let resource = ImageResource(source: "hero.png", resources: resources)
        let pipeline = ImagePipeline()
        let image = try await pipeline.load(resource, maximumDimension: 4096)
        let cached = try await pipeline.load(resource, maximumDimension: 4096)
        XCTAssertTrue(image === cached)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 32)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://images.example/account/hero.png")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer test-a")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "X-Image-Client"), "native-test")
    }

    func testSameURLDoesNotReuseImagesAcrossAccountsRequestsOrLoaders() async throws {
        let transport = InjectedImageTransport(data: try png())
        let loader = InjectedImageLoader(transport: transport)
        let context = OpenUIResourceContext(loader: loader)
        let original = ImageResource(source: "https://images.example/private", resources: context)
        let pipeline = ImagePipeline()
        let first = try await pipeline.load(original)
        loader.configure(account: "b", token: "test-b")
        do { _ = try await pipeline.load(original); XCTFail("An obsolete account must not hit decoded cache") }
        catch { XCTAssertTrue(error is CancellationError) }
        let second = try await pipeline.load(ImageResource(source: original.id.source, resources: context))
        XCTAssertFalse(first === second)
        loader.configure(token: "refreshed-b")
        let refreshed = try await pipeline.load(ImageResource(source: original.id.source, resources: context))
        XCTAssertFalse(second === refreshed, "The full request, including authorization headers, identifies pixels")
        let other = InjectedImageLoader(transport: transport)
        other.configure(account: "b", token: "refreshed-b")
        let isolated = try await pipeline.load(ImageResource(source: original.id.source, resources: .init(loader: other)))
        XCTAssertFalse(refreshed === isolated)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") },
                       ["Bearer test-a", "Bearer test-b", "Bearer refreshed-b", "Bearer refreshed-b"])
    }

    func testChangedResourceLimitsCannotBeBypassedByAnExistingDecodedImage() async throws {
        let data = try png(width: 20, height: 10)
        let transport = InjectedImageTransport(data: data)
        let loader = InjectedImageLoader(transport: transport)
        let context = OpenUIResourceContext(loader: loader)
        let source = "https://images.example/limited"
        let pipeline = ImagePipeline()
        _ = try await pipeline.load(ImageResource(source: source, resources: context))
        loader.configure(limits: .init(maximumImageSourcePixels: 100))
        do {
            _ = try await pipeline.load(ImageResource(source: source, resources: context))
            XCTFail("Source-pixel limits must apply even when this URL was previously decoded")
        } catch { XCTAssertEqual((error as? URLError)?.code, .cannotDecodeContentData) }
        loader.configure(limits: .init(maximumResponseBytes: data.count - 1))
        do {
            _ = try await pipeline.load(ImageResource(source: source, resources: context))
            XCTFail("A custom transport's returned Data is checked before decoding")
        } catch { XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testInjectedTransferIsSharedAndOneCancelledConsumerDoesNotCancelItsPeer() async throws {
        let started = expectation(description: "injected request starts")
        let transport = InjectedImageTransport(data: try png(), held: true, started: started)
        let loader = InjectedImageLoader(transport: transport)
        let resource = ImageResource(source: "https://images.example/shared", resources: .init(loader: loader))
        let pipeline = ImagePipeline()
        let first = Task { try await pipeline.load(resource) }
        let second = Task { try await pipeline.load(resource) }
        await fulfillment(of: [started], timeout: 2)
        let joined = await waitForConsumers(2, pipeline: pipeline)
        XCTAssertTrue(joined)
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled waiter must return") }
        catch { XCTAssertTrue(error is CancellationError) }
        let beforeRelease = await transport.cancelled
        XCTAssertEqual(beforeRelease, 0)
        await transport.releaseAll()
        _ = try await second.value
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testInjectedConcurrencyLimitAndLastConsumerCancellation() async throws {
        let started = expectation(description: "first admitted request starts")
        let stopped = expectation(description: "last consumer cancels the injected transfer")
        let transport = InjectedImageTransport(data: try png(), held: true, started: started, stopped: stopped)
        let loader = InjectedImageLoader(transport: transport, limits: .init(maximumConcurrentRequests: 1))
        let pipeline = ImagePipeline()
        let tasks = (0..<3).map { index in
            Task { try await pipeline.load(ImageResource(source: "https://images.example/\(index)", resources: .init(loader: loader))) }
        }
        await fulfillment(of: [started], timeout: 2)
        let joined = await waitForConsumers(3, pipeline: pipeline)
        XCTAssertTrue(joined)
        let admitted = await transport.requests
        XCTAssertEqual(admitted.count, 1)
        let activePath = try XCTUnwrap(admitted.first?.url?.lastPathComponent)
        let activeIndex = try XCTUnwrap(Int(activePath))
        let queued = tasks.enumerated().filter { $0.offset != activeIndex }.map(\.element)
        for task in queued { task.cancel() }
        for task in queued {
            do { _ = try await task.value; XCTFail("Cancelled request must finish") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
        tasks[activeIndex].cancel()
        do { _ = try await tasks[activeIndex].value; XCTFail("The last active consumer must cancel its transfer") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 2)
        await transport.releaseAll()
        _ = try await pipeline.load(ImageResource(source: "https://images.example/recovery", resources: .init(loader: loader)))
        let maximum = await transport.maximumActive
        let cancellations = await transport.cancelled
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(cancellations, 1)
    }

    @MainActor func testTwoDocumentScopesShareTheInjectedOwnersConcurrencyLimit() async throws {
        let started = expectation(description: "one document is admitted")
        let transport = InjectedImageTransport(data: try png(), held: true, started: started)
        let loader = InjectedImageLoader(transport: transport, limits: .init(maximumConcurrentRequests: 1))
        let firstStore = NativeResourceStore(), secondStore = NativeResourceStore()
        defer { firstStore.removeAll(); secondStore.removeAll() }
        let first = ImageResource(source: "https://images.example/shared", resources: firstStore.scoped(.init(loader: loader)))
        let second = ImageResource(source: "https://images.example/shared", resources: secondStore.scoped(.init(loader: loader)))
        let pipeline = ImagePipeline()
        let a = Task { try await pipeline.load(first) }
        let b = Task { try await pipeline.load(second) }
        await fulfillment(of: [started], timeout: 2)
        let joined = await waitForConsumers(2, pipeline: pipeline)
        XCTAssertTrue(joined)
        let admitted = await transport.requests
        XCTAssertEqual(admitted.count, 1, "Separate Core wrappers must not multiply a host loader's request budget")
        await transport.releaseAll()
        _ = try await a.value; _ = try await b.value
        let maximum = await transport.maximumActive
        let completed = await transport.requests
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(completed.count, 2, "Decoded resources remain isolated by document scope")
    }

    @MainActor func testRevisionAndAccountChangesReachTheCoreScopedTransport() async throws {
        let transport = InjectedImageTransport(data: try png())
        let loader = InjectedImageLoader(transport: transport)
        let store = NativeResourceStore()
        let parent = OpenUIResourceContext(baseURL: URL(string: "https://images.example/"), loader: loader)
        let scoped = store.scoped(parent)
        let initial = ImageResource(source: "image.png", resources: scoped)
        let pipeline = ImagePipeline()
        _ = try await pipeline.load(initial)
        _ = try await pipeline.load(ImageResource(source: "image.png", resources: scoped, revision: "changed"))
        let revised = await transport.requests
        XCTAssertEqual(revised.count, 2, "Revision invalidates retained transport bytes as well as decoded pixels")
        XCTAssertEqual(revised.last?.cachePolicy, .reloadIgnoringLocalCacheData)
        loader.configure(account: "b", token: "test-b")
        do { _ = try await pipeline.load(initial); XCTFail("A retired Core-scoped loader cannot expose cached account pixels") }
        catch { XCTAssertTrue(error is CancellationError) }
        let current = ImageResource(source: "image.png", resources: store.scoped(parent))
        _ = try await pipeline.load(current)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer test-b")
        store.removeAll()
        do { _ = try await pipeline.load(current); XCTFail("Document reset must invalidate decoded cache access too") }
        catch { XCTAssertTrue(error is CancellationError) }
        _ = try await pipeline.load(ImageResource(source: "image.png", resources: store.scoped(parent)))
        let afterReset = await transport.requests
        XCTAssertEqual(afterReset.count, 4)
    }

    #if os(macOS)
    @MainActor func testMountedImageKeepsSignedRequestStableAcrossBodyUpdates() async throws {
        _ = NSApplication.shared
        let started = expectation(description: "mounted image uses the injected transport")
        let transport = InjectedImageTransport(data: try png(), started: started)
        let loader = InjectedImageLoader(transport: transport, signsEachRequest: true)
        let resources = OpenUIResourceContext(baseURL: URL(string: "https://images.example/"), loader: loader)
        func content(_ alt: String) -> some View {
            SourceImage(source: "photo.png", alt: alt)
                .frame(width: 180, height: 120)
                .environment(\.displayScale, 1)
                .openUIResourceContext(resources)
        }
        let hosting = NSHostingView(rootView: content("first description"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        await fulfillment(of: [started], timeout: 2)
        var rendered = false
        for _ in 0..<200 {
            hosting.layoutSubtreeIfNeeded()
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                if let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB),
                   center.blueComponent > 0.8, center.redComponent < 0.2 { rendered = true; break }
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(rendered, "The injected blue image must reach the real SourceImage view")
        hosting.rootView = content("updated description")
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(loader.resolutionCount, 1, "Display keys and body evaluation must not repeatedly sign the same source")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }
    #endif

    @MainActor func testInlineAttachmentKeepsItsHostButRefreshesWhenResourceScopeChanges() throws {
        let previous = IntelligentUIPerformance.isEnabled
        IntelligentUIPerformance.isEnabled = true; IntelligentUIPerformance.reset()
        defer { IntelligentUIPerformance.isEnabled = previous; IntelligentUIPerformance.reset() }
        let loader = InjectedImageLoader(transport: InjectedImageTransport(data: try png()))
        var resources = OpenUIResourceContext(baseURL: URL(string: "https://images.example/a/"), loader: loader)
        #if os(iOS)
        let storage = NSTextStorage(), manager = NSLayoutManager(), container = NSTextContainer(size: .zero)
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let view = InlineNativeView(frame: .zero, textContainer: container)
        #else
        let view = InlineNativeView(frame: .zero)
        #endif
        func configure() {
            var bridge = InlineParagraphBridge(parts: [.attachment(id: "stable", value: .string("image"),
                view: AnyView(Color.clear.frame(width: 30, height: 18)))], size: "md", color: .primary,
                weight: "normal", lineSpacing: 4, maxLines: nil, open: { _ in })
            bridge.environment = InlineEnvironment(theme: .init(), typeSize: .large, colorScheme: .light,
                contrast: .standard, locale: "en", displayScale: 1, reduceMotion: false,
                differentiateWithoutColor: false, editorial: .init(), images: [:], imageRevisions: [:],
                imagePresentations: [:], mapInsets: nil, album: [], interactive: false, scrolling: false,
                background: nil, direction: .leftToRight, canInteract: true, resources: ImageResourceScope(resources))
            view.configure(bridge)
        }
        configure()
        let host = try XCTUnwrap(view.hosts.first)
        configure()
        XCTAssertEqual(IntelligentUIPerformance.snapshot()["inline.hostUpdate"]?.count, 1)
        resources.baseURL = URL(string: "https://images.example/b/")
        configure()
        loader.configure(account: "b", token: "test-b")
        configure()
        XCTAssertTrue(view.hosts.first === host, "Resource changes update the retained attachment rather than losing its native identity")
        XCTAssertEqual(IntelligentUIPerformance.snapshot()["inline.hostUpdate"]?.count, 3)
        view.removeAllHosts()
    }

    private func waitForConsumers(_ count: Int, pipeline: ImagePipeline) async -> Bool {
        for _ in 0..<2000 {
            let consumers = await pipeline.pendingConsumerCount
            if consumers == count { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    private func png(width: Int = 200, height: Int = 100) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private final class InjectedImageLoader: OpenUIResourceLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var account = "a"
    private var token = "test-a"
    private var limits: OpenUIResourceLimits
    private let signsEachRequest: Bool
    private var resolutions = 0
    private let transport: InjectedImageTransport
    init(transport: InjectedImageTransport, limits: OpenUIResourceLimits = .init(), signsEachRequest: Bool = false) {
        self.transport = transport; self.limits = limits; self.signsEachRequest = signsEachRequest
    }
    var authorizationScopeID: String { locked { account } }
    var resourceLimits: OpenUIResourceLimits { locked { limits } }
    var resolutionCount: Int { locked { resolutions } }
    func configure(account: String? = nil, token: String? = nil, limits: OpenUIResourceLimits? = nil) {
        locked {
            if let account { self.account = account }
            if let token { self.token = token }
            if let limits { self.limits = limits }
        }
    }
    func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
        guard let url = URL(string: source, relativeTo: baseURL)?.absoluteURL else { return nil }
        let resolved = locked { resolutions += 1; return (token, resolutions) }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + resolved.0, forHTTPHeaderField: "Authorization")
        request.setValue("native-test", forHTTPHeaderField: "X-Image-Client")
        if signsEachRequest { request.setValue(String(resolved.1), forHTTPHeaderField: "X-Request-Nonce") }
        return request
    }
    func data(for request: URLRequest) async throws -> Data { try await transport.data(for: request) }
    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
}

private actor InjectedImageTransport {
    let bytes: Data
    private var held: Bool
    private let started: XCTestExpectation?
    private let stopped: XCTestExpectation?
    private var waiting: [UUID: CheckedContinuation<Void, Error>] = [:]
    private(set) var requests: [URLRequest] = []
    private var active = 0
    private(set) var maximumActive = 0
    private(set) var cancelled = 0
    init(data: Data, held: Bool = false, started: XCTestExpectation? = nil, stopped: XCTestExpectation? = nil) {
        bytes = data; self.held = held; self.started = started; self.stopped = stopped
    }
    func data(for request: URLRequest) async throws -> Data {
        requests.append(request); active += 1; maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        if held {
            let id = UUID()
            try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                    waiting[id] = continuation
                    if requests.count == 1 { started?.fulfill() }
                }
            }, onCancel: { Task { await self.cancel(id) } })
        } else if requests.count == 1 { started?.fulfill() }
        try Task.checkCancellation()
        return bytes
    }
    private func cancel(_ id: UUID) {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        cancelled += 1; stopped?.fulfill(); continuation.resume(throwing: CancellationError())
    }
    func releaseAll() {
        held = false
        let continuations = Array(waiting.values); waiting.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}
