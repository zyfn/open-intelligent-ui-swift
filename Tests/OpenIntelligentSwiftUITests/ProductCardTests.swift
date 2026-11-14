import XCTest
import SwiftUI
import OpenUILang
import OpenSwiftUI
@testable import OpenIntelligentSwiftUI

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
    @MainActor private func data(_ source: String) throws -> (IntelligentUILibrary, OpenUIState, ProductCardData?) {
        let library = try IntelligentUILibrary()
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
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(#"root = ProductCard({id: "p", title: "商品", images: [{url: "/image"}]})"#)
        XCTAssertFalse(state.errors.isEmpty)
    }

    @MainActor func testCarouselKeepsProductsIndependent() throws {
        let library = try IntelligentUILibrary()
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
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource("root = Col([ProductCard(\(Self.product), \"horizontal\")])")
        for width in [320.0, 800.0] {
            for typeSize in [DynamicTypeSize.large, .accessibility2] {
                let renderer = ImageRenderer(content: IntelligentUIView(state: state, library: library)
                    .intelligentUIImages(["https://example.com/front.jpg": Image(systemName: "camera")])
                    .environment(\.dynamicTypeSize, typeSize).frame(width: width))
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(image.width, Int(width))
                XCTAssertGreaterThan(image.height, 80)
            }
        }
    }

    @MainActor func testHorizontalLayoutIsDistinctAtPhoneWidthsAndReflowsForAccessibility() throws {
        let library = try IntelligentUILibrary()
        func height(_ layout: String, width: Double, type: DynamicTypeSize) throws -> Int {
            let state = library.makeState()
            state.setSource("root = Col([ProductCard(\(Self.product), \"\(layout)\")])")
            let renderer = ImageRenderer(content: IntelligentUIView(state: state, library: library)
                .intelligentUIImages(["https://example.com/front.jpg": Image(systemName: "camera")])
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

}
