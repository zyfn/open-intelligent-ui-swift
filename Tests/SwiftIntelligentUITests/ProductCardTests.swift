import XCTest
import CoreGraphics
import SwiftUI
import SwiftLang
@testable import SwiftIntelligentUI

final class ProductCardTests: XCTestCase {
    @MainActor func testBookableChoicePreservesQuotedPriceLabelAndExactDestination() async throws {
        let (library, state, decoded) = try data(#"{id:"stay-a",title:"住宿候选",images:[],priceText:"¥495（来源查询价）",purchaseURL:"https://example.com/stay?checkIn=2026-11-20&opaque=A%2FB%3D",actionLabel:"去预订"}"#)
        let product = try XCTUnwrap(decoded)
        XCTAssertEqual(product.priceText, "¥495（来源查询价）")
        XCTAssertEqual(product.purchaseActionLabel, "去预订")
        XCTAssertTrue(library.validationIssues(in: try XCTUnwrap(state.root)).isEmpty)
        var events: [ActionEvent] = []
        state.onAction = { events.append($0) }
        let card = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let context = OpenUIComponentContext(element: card, registry: library.components.registry, state: state)
        _ = await context.perform(OpenUIActions.openURL(try XCTUnwrap(product.purchaseURL)))
        XCTAssertEqual(events.map(\.type), ["open_url"])
        XCTAssertEqual(events.first?.params.first(where: { $0.0 == "url" })?.1, .string("https://example.com/stay?checkIn=2026-11-20&opaque=A%2FB%3D"))
    }

    private static let product = """
    {id: "camera", title: "相机", images: [{url: "https://example.com/front.jpg", alt: "正面"}, {url: "https://example.com/rear.jpg", alt: "背面"}], merchant: "A", priceText: "¥100（条件 A）", condition: "不含运费", purchaseURL: "/buy?item=camera", sourceURL: "/source/camera"}
    """
    @MainActor private func data(_ source: String) throws -> (OpenIntelligentUIComponents, OpenUIState, ProductCardData?) {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource("root = Col([ProductCard(\(source))])")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let card = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let context = OpenUIComponentContext(element: card, registry: library.components.registry, state: state)
        return (library, state, ProductCardData(context.value("product")))
    }

    @MainActor func testProductPreservesSuppliedFields() throws {
        let (_, _, decoded) = try data(Self.product)
        let product = try XCTUnwrap(decoded)
        XCTAssertEqual(product.images.map(\.alt), ["正面", "背面"])
        XCTAssertEqual(product.priceText, "¥100（条件 A）")
        XCTAssertEqual(product.condition, "不含运费")
        XCTAssertEqual(product.purchaseURL, "/buy?item=camera")
        XCTAssertEqual(product.sourceURL, "/source/camera")
    }

    @MainActor func testUnknownFactsRemainAbsent() throws {
        let (_, _, decoded) = try data("{id: \"missing\", title: \"待确认\", images: []}")
        let product = try XCTUnwrap(decoded)
        XCTAssertTrue(product.images.isEmpty)
        XCTAssertNil(product.priceText)
        XCTAssertNil(product.availability)
        XCTAssertNil(product.purchaseURL)
        XCTAssertNil(product.sourceURL)
        XCTAssertNil(product.actionLabel)
        XCTAssertEqual(product.purchaseActionLabel, "去购买")
    }

    @MainActor func testMalformedImageIsRejected() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource(#"root = ProductCard({id: "p", title: "商品", images: [{url: "/image"}]})"#)
        XCTAssertFalse(state.errors.isEmpty)
    }

    @MainActor func testCarouselKeepsProductsIndependent() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource("root = Carousel([ProductCard(\(Self.product)), ProductCard({id: \"headphones\", title: \"耳机\", images: [], priceText: \"¥50\", purchaseURL: \"/buy?item=headphones\"})])")
        XCTAssertTrue(state.errors.isEmpty)
        let cards = PropValue.children(try XCTUnwrap(state.root))
        let products = cards.compactMap { ProductCardData(OpenUIComponentContext(element: $0, registry: library.components.registry, state: state).value("product")) }
        XCTAssertEqual(products.map(\.id), ["camera", "headphones"])
        XCTAssertEqual(products.map(\.purchaseURL), ["/buy?item=camera", "/buy?item=headphones"])
    }

    @MainActor func testProductDispatchesItsOriginalURL() async throws {
        let (library, state, decoded) = try data(Self.product)
        let product = try XCTUnwrap(decoded)
        let card = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let context = OpenUIComponentContext(element: card, registry: library.components.registry, state: state)
        var events: [ActionEvent] = []
        state.onAction = { events.append($0) }
        _ = await context.perform(OpenUIActions.openURL(try XCTUnwrap(product.purchaseURL)))
        XCTAssertEqual(events.map { $0.params.first { $0.0 == "url" }?.1 }, [.string("/buy?item=camera")])
    }

    @MainActor func testProductLayoutsRenderWithInjectedImages() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource("root = Col([ProductCard(\(Self.product), \"horizontal\")])")
        for width in [320.0, 800.0] {
            for typeSize in [DynamicTypeSize.large, .accessibility2] {
                let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library)
                    .openIntelligentUIImages(["https://example.com/front.jpg": Image(systemName: "camera")])
                    .environment(\.dynamicTypeSize, typeSize).frame(width: width))
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(image.width, Int(width))
                XCTAssertGreaterThan(image.height, 80)
            }
        }
    }

    @MainActor func testHorizontalLayoutIsDistinctAtPhoneWidthsAndReflowsForAccessibility() throws {
        let library = try OpenIntelligentUIComponents()
        func height(_ layout: String, width: Double, type: DynamicTypeSize) throws -> Int {
            let state = library.makeState()
            state.setSource("root = Col([ProductCard(\(Self.product), \"\(layout)\")])")
            let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library)
                .openIntelligentUIImages(["https://example.com/front.jpg": Image(systemName: "camera")])
                .environment(\.dynamicTypeSize, type).frame(width: width))
            return try XCTUnwrap(renderer.cgImage).height
        }
        for width in [300.0, 320.0, 353.0] {
            let vertical = try height("vertical", width: width, type: .large)
            let horizontal = try height("horizontal", width: width, type: .large)
            XCTAssertLessThan(horizontal, vertical - 30, "Phone horizontal layout must not silently fall back to vertical")
            XCTAssertEqual(try height("horizontal", width: width, type: .accessibility2), try height("vertical", width: width, type: .accessibility2))
        }
    }

    @MainActor func testProductWithoutPhotosDoesNotReserveMediaSpace() throws {
        let library = try OpenIntelligentUIComponents()
        let width = 320.0
        let declaredPhoto = #"[{url:"local-product-photo",alt:"房间"}]"#

        func height(_ layout: String, photos: String, injectPhoto: Bool = false) throws -> Int {
            let state = library.makeState()
            state.setSource("""
            root = Col([ProductCard({id:"stay",title:"站旁双床房",images:\(photos),price:1720,currency:"CNY",specification:"两张普通床、电梯、独立淋浴"}, "\(layout)")])
            """)
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
            let images = injectPhoto ? ["local-product-photo": Image(systemName: "photo")] : [:]
            let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library)
                .openIntelligentUIImages(images)
                .environment(\.dynamicTypeSize, .large).frame(width: width))
            let rendered = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(rendered.width, Int(width))
            return rendered.height
        }

        let detailsHeight = try height("vertical", photos: "[]")
        for layout in ["vertical", "horizontal", "compact"] {
            let noPhoto = try height(layout, photos: "[]")
            let unavailable = try height(layout, photos: declaredPhoto)
            let available = try height(layout, photos: declaredPhoto, injectPhoto: true)
            print("Product media at width \(Int(width)), \(layout): no photo \(noPhoto), unavailable \(unavailable), available \(available)")
            XCTAssertEqual(noPhoto, detailsHeight, "\(layout) must give the card details the full width when no photo was supplied")
            XCTAssertEqual(unavailable, available, "\(layout) must retain the media frame for a supplied photo that is unavailable")
            XCTAssertGreaterThan(unavailable, noPhoto, "\(layout) must allocate media space only for a supplied photo")
        }
        XCTAssertGreaterThan(try height("vertical", photos: declaredPhoto) - detailsHeight, Int(width / 2))
    }

    @MainActor func testThumbnailImageFitPreservesOrCropsBothEndsOfPortrait() throws {
        let library = try OpenIntelligentUIComponents()
        let markerSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let portrait = try XCTUnwrap(CGContext(data: nil, width: 24, height: 120, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: markerSpace, bitmapInfo: bitmapInfo))
        let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let green = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let blue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        for (y, height, color) in [(0, 24, red), (24, 72, green), (96, 24, blue)] {
            portrait.setFillColor(color)
            portrait.fill(CGRect(x: 0, y: y, width: 24, height: height))
        }
        let image = Image(decorative: try XCTUnwrap(portrait.makeImage()), scale: 1)
        let product = #" {id:"portrait", title:"雨衣", images:[{url:"local-portrait", alt:"长款雨衣"}]} "#

        func render(_ layout: String, imageFit: String? = nil) throws -> (height: Int, markers: [Int]) {
            let state = library.makeState()
            let fitArgument = imageFit.map { ", \"\($0)\"" } ?? ""
            state.setSource("root = Col([ProductCard(\(product), \"\(layout)\"\(fitArgument))])")
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
            let card = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
            XCTAssertEqual(PropValue.string(card, "imageFit"), imageFit)
            let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library)
                .openIntelligentUIImages(["local-portrait": image])
                .environment(\.dynamicTypeSize, .large).frame(width: 320))
            let rendered = try XCTUnwrap(renderer.cgImage)
            let output = try XCTUnwrap(CGContext(data: nil, width: rendered.width, height: rendered.height, bitsPerComponent: 8,
                                                 bytesPerRow: 0, space: markerSpace, bitmapInfo: bitmapInfo))
            output.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
            let pixels = try XCTUnwrap(output.data).assumingMemoryBound(to: UInt8.self)
            // Color conversion can shift channels; use the dominant marker color.
            var markers = [0, 0, 0]
            for y in 0..<rendered.height {
                for x in 0..<rendered.width {
                    let offset = y * output.bytesPerRow + x * 4
                    let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
                    if red > max(green, blue) + 100 { markers[0] += 1 }
                    if green > max(red, blue) + 100 { markers[1] += 1 }
                    if blue > max(red, green) + 100 { markers[2] += 1 }
                }
            }
            return (rendered.height, markers)
        }

        for layout in ["horizontal", "compact"] {
            let contain = try render(layout, imageFit: "contain")
            let cover = try render(layout, imageFit: "cover")
            let defaultFit = try render(layout)
            for (marker, count) in zip(["red lower end", "green middle", "blue upper end"], contain.markers) {
                XCTAssertGreaterThan(count, 100, "\(layout) contain must preserve the \(marker)")
            }
            XCTAssertEqual(cover.markers[0], 0, "\(layout) cover must crop the lower end")
            XCTAssertGreaterThan(cover.markers[1], 100, "\(layout) cover must render the middle")
            XCTAssertEqual(cover.markers[2], 0, "\(layout) cover must crop the upper end")
            XCTAssertEqual(defaultFit.markers, cover.markers, "\(layout) must default to cover")
            XCTAssertEqual(contain.height, cover.height, "\(layout) fitting must keep the thumbnail geometry")
        }
    }

}
