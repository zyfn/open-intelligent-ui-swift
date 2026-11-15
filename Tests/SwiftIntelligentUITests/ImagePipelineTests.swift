import XCTest
import Foundation
import ImageIO
import CoreGraphics
@testable import SwiftIntelligentUI

final class ImagePipelineTests: XCTestCase {
    func testContainFramingPreservesWholePhotoOverOpaqueBackdrop() throws {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 15, y: 5, width: 10, height: 30))
        let framed = try XCTUnwrap(ImageFraming.contained(try XCTUnwrap(context.makeImage()), ratio: 1.5))
        XCTAssertEqual(framed.width, 60)
        XCTAssertEqual(framed.height, 40)
        let output = try XCTUnwrap(CGContext(data: nil, width: 60, height: 40, bitsPerComponent: 8, bytesPerRow: 240, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        output.draw(framed, in: CGRect(x: 0, y: 0, width: 60, height: 40))
        let pixels = try XCTUnwrap(output.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(pixels[20 * 240 + 3], 255, "Background must fill the frame")
        XCTAssertEqual(pixels[20 * 240 + 59 * 4 + 3], 255)
        for x in [0, 5, 54, 59] {
            XCTAssertLessThanOrEqual(abs(Int(pixels[20 * 240 + x * 4]) - Int(pixels[20 * 240 + x * 4 + 2])), 2,
                                    "A blue subject must not be repeated into a neutral edge-color backdrop")
        }
        XCTAssertGreaterThan(pixels[20 * 240 + 30 * 4 + 2], 240, "The central product must remain visible")
        XCTAssertLessThan(pixels[20 * 240 + 30 * 4], 10)
        XCTAssertGreaterThan(pixels[5 * 240 + 30 * 4 + 2], 240, "The top of the subject must not be cropped")
        XCTAssertGreaterThan(pixels[34 * 240 + 30 * 4 + 2], 240, "The bottom of the subject must not be cropped")
    }

    func testConcurrentLoadsAreCoalescedDownsampledAndCached() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        ImageTestProtocol.configure(data: bytes as Data, status: 200)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageTestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let pipeline = ImagePipeline(session: session)
        let url = try XCTUnwrap(URL(string: "https://image.test/success.png"))
        async let first = pipeline.load(url, maximumDimension: 64)
        async let second = pipeline.load(url, maximumDimension: 64)
        let (a, b) = try await (first, second)
        XCTAssertTrue(a === b)
        XCTAssertLessThanOrEqual(max(a.width, a.height), 64)
        let cached = try await pipeline.load(url, maximumDimension: 64)
        XCTAssertTrue(a === cached)
        XCTAssertEqual(ImageTestProtocol.requestCount, 1)
    }

    func testHTTPFailureDoesNotBecomeSuccessfulImage() async throws {
        ImageTestProtocol.configure(data: Data(), status: 404)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageTestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let pipeline = ImagePipeline(session: session)
        for _ in 0..<2 {
            do {
                _ = try await pipeline.load(try XCTUnwrap(URL(string: "https://image.test/missing.png")))
                XCTFail("HTTP failures must not render as successful images")
            } catch { XCTAssertTrue(error is URLError) }
        }
        XCTAssertEqual(ImageTestProtocol.requestCount, 2, "Failed requests must remain retryable")
    }

    func testFailedLoadCanRecoverAndCacheTheSuccessfulRetry() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageTestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let pipeline = ImagePipeline(session: session)
        let url = try XCTUnwrap(URL(string: "https://image.test/recover.png"))
        ImageTestProtocol.configure(data: Data(), status: 503)
        do { _ = try await pipeline.load(url); XCTFail("The first load must fail") }
        catch { XCTAssertTrue(error is URLError) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        ImageTestProtocol.configure(data: bytes as Data, status: 200)
        let recovered = try await pipeline.load(url)
        let cached = try await pipeline.load(url)
        XCTAssertEqual(recovered.width, 32)
        XCTAssertTrue(recovered === cached)
        XCTAssertEqual(ImageTestProtocol.requestCount, 1)
    }
}

private final class ImageTestProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var payload = Data()
    private static var status = 200
    private static var requests = 0
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return requests }
    static func configure(data: Data, status: Int) {
        lock.lock(); defer { lock.unlock() }
        payload = data; self.status = status; requests = 0
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "image.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        let data = Self.payload, status = Self.status
        Self.lock.unlock()
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "image/png"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
