import XCTest
import SwiftUI
import CoreGraphics
@testable import SwiftIntelligentUI

final class CommerceCompositionTests: XCTestCase {
    // Exact complete reproduction from the independent host. This macOS render
    // smoke check does not replace the host's iOS viewport/scroll regression.
    private let source = #"""
root = Col([Title("商品图像与横滑", "xl"), Text("全部为演示商品与演示金额，不能购买。"), Carousel([ProductCard(a), ProductCard(b, "vertical", "contain")], 288, 3, $selected, ["a","b"]), Caption("大卡 3:2 · 无数字分页"), ProductCard(a, "horizontal"), ProductCard(b, "compact"), ProductCard({id:"missing",title:"缺失图片和价格的演示对象",images:[]}), Text("当前对象：" + $selected)])
$selected = "a"
a = {id:"a",title:"演示相机 · 长名称测试与规格描述",images:[{url:"test-landscape",alt:"相机测试照片"},{url:"test-square",alt:"相机测试第二张"}],specification:"用于验证图像与价格就近关联",priceText:"¥2,000（测试）",merchant:"演示商店",purchaseURL:"/products/a?variant=alpha%2Fbeta&x=1"}
b = {id:"b",title:"演示耳机",images:[{url:"test-portrait",alt:"耳机测试照片"}],specification:"完整轮廓测试",priceText:"¥300（测试）",condition:"演示状态",purchaseURL:"https://example.org/products/b?x=1&y=2"}
"""#

    @MainActor func testCompleteCommerceCompositionWithImagesAndMixedSiblingLayouts() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertEqual(library.validationIssues(in: try XCTUnwrap(state.root)), [])
        func picture(_ width: Int, _ height: Int) throws -> Image {
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return Image(decorative: try XCTUnwrap(context.makeImage()), scale: 1)
        }
        let images = ["test-landscape": try picture(120, 80), "test-square": try picture(80, 80), "test-portrait": try picture(80, 120)]
        for type in [DynamicTypeSize.large, .accessibility1] {
            for color in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: IntelligentUIView(state: state, library: library)
                    .intelligentUIImages(images).environment(\.dynamicTypeSize, type).environment(\.colorScheme, color).frame(width: 320))
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(image.width, 320)
                XCTAssertGreaterThan(image.height, 0)
            }
        }
    }
}
