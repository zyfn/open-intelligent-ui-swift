import Foundation
import ImageIO
import CoreGraphics
import CoreImage

/// Bounded decoded-image cache shared by image components. Decoding runs on this actor, off the UI actor.
actor ImagePipeline {
    static let shared = ImagePipeline()
    private let session: URLSession
    private let cache = NSCache<NSString, CachedImage>()
    private var pending: [String: Task<CGImage, Error>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 40
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func load(_ url: URL, maximumDimension: Int = 1600) async throws -> CGImage {
        let dimension = min(4096, max(64, maximumDimension))
        let key = url.absoluteString + "#" + String(dimension)
        if let image = cache.object(forKey: key as NSString) { return image.image }
        if let task = pending[key] { return try await task.value }
        let session = session
        let task = Task<CGImage, Error> {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count <= 20 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: dimension,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
            return image
        }
        pending[key] = task
        defer { pending[key] = nil }
        let image = try await task.value
        cache.setObject(CachedImage(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
        return image
    }
}

private final class CachedImage: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
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
