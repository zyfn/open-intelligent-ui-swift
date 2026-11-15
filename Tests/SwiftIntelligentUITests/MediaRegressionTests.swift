import XCTest
import Foundation
import CoreGraphics
import ImageIO
import SwiftLang
@testable import SwiftIntelligentUI

final class MediaRegressionTests: XCTestCase {
    func testImagePixelTiersRespectScaleAndZoom() {
        XCTAssertEqual(ImagePixelSize.target(points: CGSize(width: 100, height: 100), scale: 2), 256)
        XCTAssertEqual(ImagePixelSize.target(points: CGSize(width: 300, height: 200), scale: 3), 1024)
        XCTAssertEqual(ImagePixelSize.target(points: CGSize(width: 400, height: 800), scale: 3, zoom: 4), 4096)
        XCTAssertEqual(ImagePixelSize.target(points: .zero, scale: 2), 1600)
        XCTAssertEqual(ImagePixelSize.ratio(.nan, fallback: 1.5), 1.5)
    }

    func testSVGViewBoxRequiresFourFiniteNumbersAndPositiveExtent() throws {
        XCTAssertEqual(try SVGMarkup.viewBox("-5 0 1e3 500"), [-5, 0, 1000, 500])
        for invalid in ["0 0 0 100", "1..2 0 100 100", "0 0 nan 100", "0 0 1e100 20", "0 0 -10 20"] {
            XCTAssertThrowsError(try SVGMarkup.viewBox(invalid), invalid)
        }
    }

    func testSVGPreservesAllNodesBelowTheWholeDocumentBudget() throws {
        let circles = (0..<2050).map { _ in Value.element(circle()) }
        let root = EvaluatedElement(typeName: "Svg", props: [("children", .array(circles)), ("viewBox", .string("0 0 100 100"))])
        let document = try SVGMarkup.document(root)
        XCTAssertEqual(document.markup.components(separatedBy: "<circle ").count - 1, 2050)
        let group = Value.element(EvaluatedElement(typeName: "G", props: [("children", .array(circles))]))
        let tooLarge = EvaluatedElement(typeName: "Svg", props: [("children", .array([group, group])), ("viewBox", .string("0 0 100 100"))])
        XCTAssertThrowsError(try SVGMarkup.document(tooLarge))
    }

    func testSVGBoundsPathWorkWithoutReplacingItsGrammarAndKeepsPaintIsolation() throws {
        let valid = EvaluatedElement(typeName: "Path", props: [("d", .string("M0 0 A5 5 0 1 0 10 10 Z"))])
        XCTAssertTrue(try SVGMarkup.document(valid).markup.contains("<path"))
        let compactArc = "M0 0 A10 10 0 0110 10"
        XCTAssertTrue(try SVGMarkup.document(EvaluatedElement(typeName: "Path", props: [("d", .string(OpenUIString(compactArc)))])).markup.contains(compactArc))
        let transform = "translate (10,20), scale(2)"
        let group = EvaluatedElement(typeName: "G", props: [("children", .array([.element(circle())])), ("transform", .string(OpenUIString(transform)))])
        XCTAssertTrue(try SVGMarkup.document(group).markup.contains(transform))
        XCTAssertThrowsError(try SVGMarkup.document(EvaluatedElement(typeName: "Path", props: [("d", .string("M0 0\"><script>bad</script>"))])))
        let excessivePath = "M0 0 " + String(repeating: "L1 1 ", count: 3000)
        XCTAssertThrowsError(try SVGMarkup.document(EvaluatedElement(typeName: "Path", props: [("d", .string(OpenUIString(excessivePath)))])))
        XCTAssertEqual(SVGMarkup.paint("chart1", palette: ["chart1": "#123456"]), "#123456")
        XCTAssertEqual(SVGMarkup.paint("#abcdef"), "#abcdef")
        XCTAssertNil(SVGMarkup.paint("url(https://example.com/image.svg)"))
        let text = EvaluatedElement(typeName: "SvgText", props: [("text", .string("<script>bad</script>")), ("x", .number(0)), ("y", .number(0))])
        XCTAssertTrue(try SVGMarkup.document(text).markup.contains("&lt;script&gt;"))
    }

    func testMapLabelsUseTheirRectanglesAndSelectionPriority() {
        let candidates = [
            MapLabelLayout.Candidate(id: "A", order: 0, selected: false, rect: CGRect(x: 0, y: 0, width: 140, height: 80)),
            MapLabelLayout.Candidate(id: "B", order: 1, selected: true, rect: CGRect(x: 100, y: 0, width: 140, height: 80)),
            MapLabelLayout.Candidate(id: "C", order: 2, selected: false, rect: CGRect(x: 400, y: 0, width: 140, height: 80))
        ]
        XCTAssertEqual(MapLabelLayout.visible(candidates), Set(["B", "C"]))
        XCTAssertNotNil(MapPoint.displayIcon("🏛️"))
        XCTAssertNotNil(MapPoint.displayIcon("🇨🇳"))
        XCTAssertNil(MapPoint.displayIcon("a long label"))
    }

    func testMapOverviewHasNoImplicitSelectionAndFilteringClearsHiddenSelection() {
        let places: Value = .array([
            .element(EvaluatedElement(typeName: "MapMarker", props: [("label", .string("A")), ("lat", .number(30)), ("lng", .number(120)), ("category", .string("one"))])),
            .element(EvaluatedElement(typeName: "MapMarker", props: [("label", .string("B")), ("lat", .number(31)), ("lng", .number(121)), ("category", .string("two"))]))
        ])
        let points = MapPoint.decode(places)
        XCTAssertEqual(MapPoint.validSelection("", in: points), "")
        XCTAssertEqual(MapPoint.validSelection("A", in: points), "A")
        XCTAssertEqual(MapPoint.validSelection("A", in: points.filter { $0.category == "two" }), "")
        XCTAssertEqual(MapPoint.validSelection("B", in: points), "B")
        XCTAssertEqual(MapPoint.validSelection("unknown", in: points), "")
    }

    @MainActor func testCancelledMathJobDoesNotRender() async throws {
        let typesetter = try MathTypesetter()
        let task = Task { try await typesetter.renderAsync("\\frac{a}{b}", inline: true) }
        task.cancel()
        do { _ = try await task.value; XCTFail("A cancelled queued formula must not render") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func circle() -> EvaluatedElement {
        EvaluatedElement(typeName: "Circle", props: [("cx", .number(10)), ("cy", .number(10)), ("r", .number(2))])
    }
}

final class MediaPipelineLifecycleTests: XCTestCase {
    func testOversizedUnknownLengthBodyFailsBeforeTheResponseFinishes() async throws {
        let server = MediaImageServer(expectedStarts: 1)
        let session = makeSession(server)
        defer { session.invalidateAndCancel(); MediaImageProtocol.unregister(server) }
        let pipeline = ImagePipeline(session: session, maximumResponseBytes: 1024)
        let completed = expectation(description: "bounded response terminates")
        let task = Task {
            defer { completed.fulfill() }
            return try await pipeline.load(server.url("large"))
        }
        await fulfillment(of: [server.started], timeout: 2)
        server.send(Data(repeating: 1, count: 1025), finish: false)
        await fulfillment(of: [completed], timeout: 2)
        server.finishAll(with: Data())
        do { _ = try await task.value; XCTFail("Oversized body should fail while the server is still open") }
        catch { XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum) }
    }

    func testCancellingLastConsumerStopsTheTransfer() async throws {
        let server = MediaImageServer(expectedStarts: 1)
        let session = makeSession(server)
        defer { session.invalidateAndCancel(); MediaImageProtocol.unregister(server) }
        let pipeline = ImagePipeline(session: session)
        let task = Task { try await pipeline.load(server.url("cancel")) }
        await fulfillment(of: [server.started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled consumer must finish") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [server.stopped], timeout: 2)
        XCTAssertEqual(server.cancelCount, 1)
    }

    func testCancellingOneConsumerKeepsTheSharedTransferForTheOther() async throws {
        let server = MediaImageServer(expectedStarts: 1)
        let session = makeSession(server)
        defer { session.invalidateAndCancel(); MediaImageProtocol.unregister(server) }
        let pipeline = ImagePipeline(session: session)
        let first = Task { try await pipeline.load(server.url("shared")) }
        let second = Task { try await pipeline.load(server.url("shared")) }
        await fulfillment(of: [server.started], timeout: 2)
        let joined = await waitForConsumers(2, pipeline: pipeline)
        XCTAssertTrue(joined)
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled waiter must return without waiting for its peer") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(server.cancelCount, 0)
        server.finishAll(with: try png())
        let image = try await second.value
        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(server.startCount, 1)
    }

    func testDifferentURLsObeyTheConcurrencyLimitAndRevisionInvalidatesCache() async throws {
        let server = MediaImageServer(expectedStarts: 2)
        let session = makeSession(server)
        defer { session.invalidateAndCancel(); MediaImageProtocol.unregister(server) }
        let pipeline = ImagePipeline(session: session, maximumConcurrentRequests: 2)
        let tasks = (0..<5).map { index in Task { try await pipeline.load(server.url("image\(index)")) } }
        await fulfillment(of: [server.started], timeout: 2)
        XCTAssertEqual(server.startCount, 2)
        XCTAssertEqual(server.maximumActiveCount, 2)
        server.finishAll(with: try png())
        for task in tasks { _ = try await task.value }
        XCTAssertLessThanOrEqual(server.maximumActiveCount, 2)
        _ = try await pipeline.load(server.url("image0"))
        XCTAssertEqual(server.startCount, 5)
        _ = try await pipeline.load(server.url("image0"), revision: "updated")
        XCTAssertEqual(server.startCount, 6)
    }

    private func makeSession(_ server: MediaImageServer) -> URLSession {
        MediaImageProtocol.register(server)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaImageProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func waitForConsumers(_ count: Int, pipeline: ImagePipeline) async -> Bool {
        for _ in 0..<2000 {
            if await pipeline.pendingConsumerCount == count { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    private func png() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// Deterministic transport fixture: tests decide when bodies finish, without a real network.
private final class MediaImageServer: @unchecked Sendable {
    let host = UUID().uuidString.lowercased() + ".media.test"
    let started = XCTestExpectation(description: "requests started")
    let stopped = XCTestExpectation(description: "request cancelled")
    private let lock = NSLock()
    private let expectedStarts: Int
    private var clients: [ObjectIdentifier: MediaImageProtocol] = [:]
    private var automaticBody: Data?
    private var starts = 0, cancellations = 0, maximumActive = 0
    init(expectedStarts: Int) {
        self.expectedStarts = expectedStarts
        started.expectedFulfillmentCount = expectedStarts
    }
    func url(_ name: String) -> URL { URL(string: "https://\(host)/\(name)")! }
    var startCount: Int { lock.lock(); defer { lock.unlock() }; return starts }
    var cancelCount: Int { lock.lock(); defer { lock.unlock() }; return cancellations }
    var maximumActiveCount: Int { lock.lock(); defer { lock.unlock() }; return maximumActive }

    func start(_ client: MediaImageProtocol) {
        lock.lock()
        clients[ObjectIdentifier(client)] = client; starts += 1
        maximumActive = max(maximumActive, clients.count)
        let shouldSignal = starts <= expectedStarts, body = automaticBody
        lock.unlock()
        let response = HTTPURLResponse(url: client.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
        client.client?.urlProtocol(client, didReceive: response, cacheStoragePolicy: .notAllowed)
        if shouldSignal { started.fulfill() }
        if let body { deliver(client, data: body, finish: true) }
    }
    func stop(_ client: MediaImageProtocol) {
        lock.lock()
        let removed = clients.removeValue(forKey: ObjectIdentifier(client)) != nil
        if removed { cancellations += 1 }
        let shouldSignal = removed && cancellations == 1
        lock.unlock()
        if shouldSignal { stopped.fulfill() }
    }
    func send(_ data: Data, finish: Bool) {
        lock.lock(); let waiting = Array(clients.values); lock.unlock()
        for client in waiting { deliver(client, data: data, finish: finish) }
    }
    func finishAll(with data: Data) {
        lock.lock(); automaticBody = data; let waiting = Array(clients.values); lock.unlock()
        for client in waiting { deliver(client, data: data, finish: true) }
    }
    private func deliver(_ client: MediaImageProtocol, data: Data, finish: Bool) {
        lock.lock()
        let active = clients[ObjectIdentifier(client)] != nil
        if finish { clients[ObjectIdentifier(client)] = nil }
        lock.unlock()
        guard active else { return }
        client.client?.urlProtocol(client, didLoad: data)
        if finish { client.client?.urlProtocolDidFinishLoading(client) }
    }
}

private final class MediaImageProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var servers: [String: MediaImageServer] = [:]
    private var server: MediaImageServer?
    static func register(_ server: MediaImageServer) { lock.lock(); servers[server.host] = server; lock.unlock() }
    static func unregister(_ server: MediaImageServer) { lock.lock(); servers[server.host] = nil; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".media.test") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); server = Self.servers[request.url?.host ?? ""]; Self.lock.unlock()
        server?.start(self)
    }
    override func stopLoading() { server?.stop(self) }
}
