import XCTest
import SwiftUI
import CoreGraphics
@testable import OpenIntelligentSwiftUI

final class PressableSurfaceTests: XCTestCase {
    @MainActor func testMultipleChildrenShareOneContinuousBackground() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(#"""
        root = Col([Pressable([Text("第一项"),Text("第二项"),Caption("第三项")],@Set($selected,true),false,3,"chart1")])
        $selected = false
        """#)
        XCTAssertTrue(state.errors.isEmpty)
        var theme = IntelligentUITheme()
        theme.chartColors[0] = Color(red: 1, green: 0, blue: 0)
        let renderer = ImageRenderer(content: IntelligentUIView(state: state, library: library).intelligentUITheme(theme).frame(width: 320))
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width, height = image.height
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var pixels = (0..<(width * height)).map { bytes[$0 * 4] > 220 && bytes[$0 * 4 + 1] < 30 && bytes[$0 * 4 + 2] < 30 && bytes[$0 * 4 + 3] > 220 }
        var surfaces = 0
        for index in pixels.indices where pixels[index] {
            var pending = [index], area = 0
            pixels[index] = false
            while let current = pending.popLast() {
                area += 1
                let x = current % width, y = current / width
                for next in [x > 0 ? current - 1 : -1, x + 1 < width ? current + 1 : -1, y > 0 ? current - width : -1, y + 1 < height ? current + width : -1] {
                    if next >= 0, pixels[next] { pixels[next] = false; pending.append(next) }
                }
            }
            if area > 50 { surfaces += 1 }
        }
        XCTAssertEqual(surfaces, 1, "One Pressable must own one surface, regardless of child count")
    }
}
