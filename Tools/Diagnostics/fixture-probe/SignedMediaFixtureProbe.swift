import AppKit
import CoreGraphics
import Foundation
import ImageIO

private enum ProbeError: Error { case failed(String) }
private func XCTUnwrap<T>(_ value: T?) throws -> T {
  guard let value else { throw ProbeError.failed("Unexpected nil in fixture probe") }
  return value
}
private func XCTAssertTrue(_ value: Bool) {
  precondition(value, "The reference PNG encoder did not finish")
}

// Verbatim generators from the pinned main. No SDK or XCTest code is imported.
  @MainActor private func png(_ color: NSColor) throws -> Data {
    let pixels = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
      pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 8, bitsPerPixel: 32))
    for x in 0..<2 { for y in 0..<2 { pixels.setColor(color, atX: x, y: y) } }
    return try XCTUnwrap(pixels.representation(using: .png, properties: [:]))
  }

  @MainActor private func largePNG(side: Int, color: NSColor = .red) throws -> Data {
    let canvas = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    canvas.setFillColor(color.cgColor)
    canvas.fill(CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(canvas.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

private func inspect(_ data: Data, expectedChannel: Int) throws -> [String: Any] {
  let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
  let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
  let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
  let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
  let canvas = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space, bitmapInfo: info))
  canvas.setBlendMode(.copy)
  canvas.interpolationQuality = .none
  canvas.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
  let bytes = try XCTUnwrap(canvas.data).assumingMemoryBound(to: UInt8.self)
  var pixels: [[Int]] = []
  for y in 0..<image.height {
    for x in 0..<image.width {
      let offset = y * canvas.bytesPerRow + x * 4
      pixels.append((0..<4).map { Int(bytes[offset + $0]) })
    }
  }
  let expected = image.width == 2 && image.height == 2 && pixels.allSatisfy { pixel in
    pixel[3] >= 250 && pixel[expectedChannel] > 40
      && (0..<3).filter { $0 != expectedChannel }.allSatisfy { pixel[expectedChannel] > pixel[$0] * 2 }
  }
  return ["width": image.width, "height": image.height,
    "sourceColorSpace": String(describing: image.colorSpace),
    "sourceColorSpaceModel": image.colorSpace.map { Int($0.model.rawValue) } ?? -1,
    "sourceBitsPerComponent": image.bitsPerComponent,
    "sourceBitsPerPixel": image.bitsPerPixel,
    "sourceAlphaInfo": String(describing: image.alphaInfo),
    "normalizedLayout": "sRGB RGBA8 premultiplied, byteOrder32Big, row-major",
    "rgba": pixels, "expectedOpaquePrimaryColor": expected]
}

@main private struct SignedMediaFixtureProbe {
  @MainActor static func main() throws {
    guard CommandLine.arguments.count == 3 else {
      throw ProbeError.failed("Usage: probe OUTPUT_DIRECTORY SOURCE_MANIFEST_JSON")
    }
    _ = NSApplication.shared
    NSApplication.shared.appearance = NSAppearance(named: .aqua)
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let manifest = try JSONSerialization.jsonObject(with:
      Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
    var cases: [[String: Any]] = []
    var referenceValid = true
    for (name, color, channel) in [("red", NSColor.red, 0), ("green", NSColor.green, 1), ("blue", NSColor.blue, 2)] {
      for (path, data) in [("legacy", try png(color)), ("cgcontext", try largePNG(side: 2, color: color))] {
        let filename = "\(path)-\(name).png"
        try data.write(to: output.appendingPathComponent(filename))
        let image = try inspect(data, expectedChannel: channel)
        if path == "cgcontext", image["expectedOpaquePrimaryColor"] as? Bool != true { referenceValid = false }
        cases.append(["generator": path, "expectedColor": name, "png": filename,
          "pngBytes": data.count, "inputNSColor": String(describing: color),
          "inputCGColorSpace": String(describing: color.cgColor.colorSpace), "decoded": image])
      }
    }
    let report: [String: Any] = ["source": manifest,
      "checkout": ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "local",
      "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
      "referenceAllExpected": referenceValid, "cases": cases]
    let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: output.appendingPathComponent("fixture-pixels.json"))
    print(String(decoding: json, as: UTF8.self))
    guard referenceValid else { throw ProbeError.failed("The independent CGContext reference is not a valid opaque primary color") }
  }
}
