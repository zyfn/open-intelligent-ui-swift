import XCTest
import SwiftUI
import OpenUILang
import OpenSwiftUI
@testable import OpenIntelligentSwiftUI

final class UpstreamParityTests: XCTestCase {
    private func node(_ name: String) -> Value { .element(EvaluatedElement(typeName: name, props: [])) }

    func testNestedFlowUsesGroupSpacingAndCaptionStaysAttached() {
        let theme = IntelligentUITheme()
        XCTAssertEqual(EditorialSpacing.between(node("Image"), node("Text"), theme: theme), 24)
        XCTAssertEqual(EditorialSpacing.between(node("Image"), node("Text"), theme: theme, nested: true), 12)
        XCTAssertEqual(EditorialSpacing.between(node("Title"), node("Text"), theme: theme), 8)
        XCTAssertEqual(EditorialSpacing.between(node("Caption"), node("Title"), theme: theme), 4)
        XCTAssertEqual(EditorialSpacing.between(node("Text"), node("Text"), theme: theme), 12)
        XCTAssertEqual(EditorialSpacing.between(node("Image"), node("Caption"), theme: theme), 8)
        XCTAssertEqual(EditorialSpacing.between(node("Text"), node("Image"), theme: theme), 12)
        XCTAssertEqual(EditorialSpacing.between(node("Image"), node("Text"), theme: theme), 24)
    }

    func testNoneTimelineHasNoDanglingConnector() {
        XCTAssertFalse(ListMarkerRules.connects(mode: "none", wide: false, timeline: true))
        XCTAssertTrue(ListMarkerRules.connects(mode: "none", wide: true, timeline: true))
        XCTAssertTrue(ListMarkerRules.connects(mode: "bullet", wide: false, timeline: true))
        XCTAssertTrue(ListMarkerRules.connects(mode: "number", wide: false, timeline: true))
        XCTAssertFalse(ListMarkerRules.connects(mode: "bullet", wide: false, timeline: false))
    }

    func testTimelineNodeAndConnectorShareTheSameAnchorAtEveryScale() {
        for scale in [1.0, 1.6, 2.5] {
            for wide in [true, false] {
                let lane = (wide ? 64.0 : 24.0) * scale
                let anchor = TimelineGeometry.anchor(lane: lane, wide: wide)
                let line = TimelineGeometry.connector(lane: lane, wide: wide, markerHeight: 26 * scale, rowHeight: 160 * scale)
                XCTAssertEqual(line.start.x, anchor)
                XCTAssertEqual(line.end.x, anchor)
                XCTAssertGreaterThan(line.end.y, line.start.y)
            }
        }
    }

    func testAlbumsReuseExactSourcesAndDoNotTreatProductPicturesAsEditorialPhotos() {
        func image(_ source: String) -> Value { .element(EvaluatedElement(typeName: "Image", props: [("src", .string(OpenUIString(source))), ("alt", .string("来源图片"))])) }
        let url = "https://example.com/photo?opaque=A%2FB%3D&x=1"
        let group = Value.element(EvaluatedElement(typeName: "Col", props: [("children", .array([image(url), image(url), image("local-key")]))]))
        let product = Value.element(EvaluatedElement(typeName: "ProductCard", props: [("product", .object([.init(key: "image", value: image("unrelated"))]))]))
        XCTAssertEqual(ImageAlbumItem.collect([group, product]).map(\.source), [url, "local-key"])
    }

    @MainActor func testLateDependencyPublishesReadySiblingsWithoutReservingMissingSlot() throws {
        let state = try IntelligentUILibrary().makeState()
        state.push("root=Col([early,later])\nlater=Text(\"后面的块\")\n")
        let root = try XCTUnwrap(state.root)
        let partial = OpenUIRenderChild.children(of: PropValue.value(root, "children") ?? .null)
        XCTAssertEqual(partial.count, 1)
        XCTAssertEqual(ValueReading.string(ValueReading.field(partial.first?.value, "text")), "后面的块")
        state.push("early=Text(\"前面的块\")\n"); state.complete()
        XCTAssertTrue(state.errors.isEmpty)
        let finished = OpenUIRenderChild.children(of: PropValue.value(try XCTUnwrap(state.root), "children") ?? .null)
        XCTAssertEqual(finished.count, 2)
        XCTAssertEqual(ValueReading.string(ValueReading.field(finished.last?.value, "text")), "后面的块")
        XCTAssertEqual(ValueReading.string(ValueReading.field(finished.first?.value, "text")), "前面的块")
    }

    func testParserReportsMissingDependencyWithoutPreservingItsSlot() throws {
        let library = try IntelligentUILibrary()
        let parser = createStreamingParser(schema: library.components.library.toSchema())
        let result = parser.push("root=Col([early,later])\nlater=Text(\"后面的块\")\n")
        XCTAssertTrue(result.meta.unresolved.contains("early"))
        let root = try XCTUnwrap(result.root)
        guard case .array(let children) = root.props.first(where: { $0.key == "children" })?.value else { return XCTFail("Expected children") }
        XCTAssertEqual(children.count, 1)
        XCTAssertNil(result.rootExpression)
    }

    @MainActor func testCompletionDoesNotMakeUnresolvedSourceValid() throws {
        let library = try IntelligentUILibrary(), state = library.makeState()
        let incomplete = "root=Col([Title(\"开头\"),missing,Text(\"结尾\")])"
        state.setSource(incomplete)
        XCTAssertTrue(library.validationIssues(in: state, source: incomplete).contains { $0.contains("unresolved source") })
        let inactive = "root=Col([Title(\"开头\"),false?missing:null,Text(\"结尾\")])"
        state.setSource(inactive)
        XCTAssertTrue(library.validationIssues(in: state, source: inactive).contains { $0.contains("unresolved source") })
    }

    @MainActor func testReadingAnchorSurvivesLateInsertionWithoutCrossingMessagesOrReplacements() throws {
        let library = try IntelligentUILibrary(), state = library.makeState()
        let prefix = "root=Col([later,early])\nlater=Text(\"后面的块\")\n"
        state.push(prefix)
        let first = try XCTUnwrap(OpenUIRenderChild.children(of: PropValue.value(try XCTUnwrap(state.root), "children") ?? .null).first)
        let anchor = ReadingAnchor(state: state, child: first.id)
        state.push("early=Text(\"前面的块\")\n"); state.complete()
        let last = try XCTUnwrap(OpenUIRenderChild.children(of: PropValue.value(try XCTUnwrap(state.root), "children") ?? .null).first)
        XCTAssertEqual(anchor, ReadingAnchor(state: state, child: last.id))
        let other = library.makeState(); other.setSource(prefix + "early=Text(\"前面的块\")")
        XCTAssertNotEqual(anchor, ReadingAnchor(state: other, child: last.id))
        state.setSource(prefix + "early=Text(\"另一份内容\")")
        XCTAssertNotEqual(anchor, ReadingAnchor(state: state, child: last.id))
        let before = [anchor: CGRect(x: 0, y: 400, width: 320, height: 240)]
        let above = [anchor: CGRect(x: 0, y: 582, width: 320, height: 240)]
        XCTAssertEqual(ReadingPosition.displacement(of: anchor, from: before, to: above), 182)
        XCTAssertEqual(ReadingPosition.displacement(of: anchor, from: before, to: before), 0)
        XCTAssertEqual(ReadingPosition.displacement(of: anchor, from: before, to: [:]), 0)
    }

    @MainActor func testEditorialRowsRenderLeadingAndTrailingMedia() throws {
        #if os(macOS)
        let library = try IntelligentUILibrary(excludingComponents: ["ImageText", "YouTube", "Timer"])
        for leading in [true, false] {
            let state = library.makeState()
            let picture = #"Image("local-photo","原地点照片")"#
            let copy = #"Col([Title("一个较长但真实提供的地点名称"),Caption("地址与类别来自同一实体")])"#
            state.setSource("root=Card([Row([" + (leading ? picture + "," + copy : copy + "," + picture) + "])])")
            let renderer = ImageRenderer(content: IntelligentUIView(state: state, library: library)
                .intelligentUIImages(["local-photo": Image(systemName: "photo")]).frame(width: 320))
            let size = try XCTUnwrap(renderer.nsImage).size
            XCTAssertGreaterThan(size.height, 40)
        }
        #endif
    }

    @MainActor func testInlineAttachmentUsesTheLastTextLineAndWrapsWithIt() throws {
        #if os(macOS)
        let view = InlineNativeView(frame: .zero)
        view.textContainerInset = .zero
        view.isEditable = false
        func configure(_ text: String) {
            view.configure(InlineParagraphBridge(parts: [.text(text), .view(AnyView(Color.clear.frame(width: 30, height: 18)))], size: "md", color: .primary, weight: "normal", lineSpacing: 4, maxLines: nil, open: { _ in }))
        }
        configure("Short text ")
        let short = view.measure(240)
        let first = try XCTUnwrap(view.hosts.first).frame
        XCTAssertGreaterThan(first.minX, 40)
        XCTAssertLessThan(first.minY, 30)
        configure("这是一段需要自然换行的中文正文，引用应当跟随文字的最后一行，而不是作为另一个占满整行的块。 ")
        let long = view.measure(240)
        let last = try XCTUnwrap(view.hosts.first).frame
        XCTAssertGreaterThan(long.height, short.height)
        XCTAssertGreaterThan(last.minY, first.minY)
        XCTAssertLessThanOrEqual(last.maxX, 240.5)
        XCTAssertLessThanOrEqual(last.maxY, long.height + 8)
        let narrow = view.measure(120)
        XCTAssertGreaterThan(narrow.height, long.height)
        XCTAssertLessThanOrEqual(try XCTUnwrap(view.hosts.first).frame.maxX, 120.5)
        #endif
    }
}
