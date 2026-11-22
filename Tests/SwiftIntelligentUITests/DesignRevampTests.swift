import XCTest
import SwiftUI
import SwiftLang
@testable import SwiftIntelligentUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

final class DesignRevampTests: XCTestCase {
    private func node(_ name: String, _ props: [(String, Value)] = []) -> Value {
        .element(EvaluatedElement(typeName: name, props: props))
    }

    func testTextDefaultsMatchExplicitBodyAndKeepHostTypography() {
        var theme = OpenIntelligentUITheme()
        theme.bodyFont = .system(size: 23)
        theme.bodyLargeFont = .system(size: 31)
        theme.bodyLineSpacing = 6
        let body = TextTypography(size: "md", weight: "normal", theme: theme)
        let amount = TextTypography(size: "lg", weight: "semibold", theme: theme)
        let omitted = TextTypography(size: nil, weight: nil, theme: theme)
        XCTAssertEqual(body.role, .body)
        XCTAssertEqual(body.font, theme.bodyFont)
        XCTAssertEqual(body.sizeName, "md")
        XCTAssertEqual(body.lineSpacing, 6)
        XCTAssertEqual(amount.font, theme.bodyLargeFont)
        XCTAssertEqual(amount.weight, .semibold)
        XCTAssertEqual(omitted.role, body.role)
        XCTAssertEqual(omitted.font, body.font)
        XCTAssertEqual(omitted.weight, body.weight)
        XCTAssertEqual(omitted.lineSpacing, body.lineSpacing)
    }

    func testTitleDefaultsAndMarkdownLevelsUseTheSameSemanticRoles() {
        let theme = OpenIntelligentUITheme()
        XCTAssertEqual(TitleTypography.font(size: "md", theme: theme), theme.titleFont)
        XCTAssertEqual(TitleTypography.font(size: "xl", theme: theme), theme.pageTitleFont)
        XCTAssertEqual(TitleTypography.font(size: "3xl", theme: theme), theme.displayFont)
        XCTAssertEqual(TitleTypography.font(size: nil, theme: theme), theme.titleFont)
        for (level, expected) in [(1, theme.pageTitleFont), (2, theme.sectionTitleFont), (3, theme.titleFont)] {
            XCTAssertEqual(TitleTypography.font(size: TitleTypography.size(forMarkdownLevel: level), theme: theme), expected)
        }
    }

    func testDefaultNormalBodyAndStrongEmphasisRemainDistinct() {
        let theme = OpenIntelligentUITheme()
        let body = TextTypography(size: "md", weight: nil, theme: theme)
        XCTAssertEqual(body.weight, .regular)
        XCTAssertEqual(theme.emphasisWeight, .semibold)
        XCTAssertNotEqual(body.weight, theme.emphasisWeight)
    }

    @MainActor func testNativeFontPairingPreservesFamilyAndClearsWhenHostChangesTheFont() throws {
        var theme = OpenIntelligentUITheme()
        let native = PlatformFont.monospacedSystemFont(ofSize: 25, weight: .regular)
        theme.setTextFont(native, for: .body)
        let style = TextTypography(size: "md", weight: "normal", theme: theme)
        XCTAssertEqual(style.font, Font(native))
        XCTAssertEqual(style.nativeFont, native)
        let view = makeNativeView()
        var bridge = makeBridge([.text("paired 字体")])
        bridge.nativeFont = style.nativeFont
        view.configure(bridge)
        _ = view.measure(240)
        XCTAssertEqual(view.baseFont.fontName, native.fontName)
        XCTAssertEqual(view.baseFont.pointSize, 25)
        theme.bodyFont = .title
        XCTAssertNil(theme.nativeTextFonts[.body])
    }

    func testFlowSpacingUsesThemeTokensAndKeepsDirectWrapperBoundaries() {
        var theme = OpenIntelligentUITheme()
        theme.paragraphSpacing = 19
        theme.innerSpacing = 9
        theme.sectionSpacing = 30
        theme.spacingUnit = 5
        XCTAssertEqual(EditorialSpacing.between(node("Text"), node("Text"), theme: theme), 19)
        XCTAssertEqual(EditorialSpacing.between(node("Text"), node("Markdown"), theme: theme), 35)
        let image = node("Image")
        let wrapped = node("Box", [("children", .array([image]))])
        let surface = node("Box", [("children", .array([image])), ("background", .string("surface"))])
        XCTAssertEqual(EditorialSpacing.between(wrapped, node("Caption"), theme: theme), 35)
        XCTAssertEqual(EditorialSpacing.between(surface, node("Caption"), theme: theme), 35)
        for media in ["Image", "SearchImage", "Chart", "Table", "Svg", "YouTube", "Map", "Math", "HtmlView"] {
            XCTAssertEqual(EditorialSpacing.between(node(media), node("Caption"), theme: theme), 35, media)
        }
        let credit = node("Text", [("text", .array([.string("来源 "), node("Citation")]))])
        XCTAssertEqual(EditorialSpacing.between(wrapped, credit, theme: theme), 35)
        XCTAssertEqual(EditorialSpacing.between(node("Caption"), node("Title"), theme: theme), 5)
        XCTAssertEqual(EditorialSpacing.between(node("Title"), node("Caption"), theme: theme), 9)
        XCTAssertEqual(EditorialSpacing.between(wrapped, credit, theme: theme, nested: true), 19)
    }

    func testReadingBlockDetectionRemainsSeparateFromMediaSizing() {
        let pair = [node("Image"), node("Text")]
        XCTAssertTrue(pair.allSatisfy(RowPresentation.isReadingBlock))
        XCTAssertFalse(RowPresentation.isReadingBlock(node("Input")))
    }

    func testSpacerKeepsAWeightAndExplicitBoxFlexKeepsPriority() {
        XCTAssertEqual(RowFlexRules.weight(node("Spacer")), 1)
        XCTAssertEqual(RowFlexRules.weight(node("Text")), 0)
        XCTAssertEqual(RowFlexRules.weight(node("Box", [("flex", .number(3))])), 3)
        XCTAssertEqual(RowFlexRules.weight(node("Box", [("flex", .number(0))])), 0)
        XCTAssertEqual(WrappingRowLayout.layoutProperties.stackOrientation, .horizontal)
        let geometry = RowGeometry(sizes: [CGSize(width: 40, height: 48), CGSize(width: 1, height: 0), CGSize(width: 30, height: 20)],
            width: 160, gap: 8, alignment: "center", justification: "start", wraps: false, stretchIndices: [1])
        XCTAssertEqual(geometry.frames[1].height, 48)
        XCTAssertEqual(geometry.frames[1].minY, 0)
    }

    func testCarouselFinalItemHasAReachableLeadingAlignment() {
        let width: CGFloat = 240, gap: CGFloat = 12, viewport: CGFloat = 390
        let natural: CGFloat = 3 * width + 2 * gap
        let padded = natural + CarouselMetrics.trailingSpace(available: viewport, itemWidth: width)
        XCTAssertEqual(padded - viewport, 2 * (width + gap))
        XCTAssertEqual(CarouselMetrics.index(offset: padded - viewport, itemWidth: width, gap: gap, count: 3), 2)
        XCTAssertEqual(CarouselMetrics.index(offset: .greatestFiniteMagnitude, itemWidth: 80, gap: 0, count: 3), 2)
        XCTAssertEqual(CarouselMetrics.index(offset: .nan, itemWidth: width, gap: gap, count: 3), 0)
        XCTAssertEqual(CarouselMetrics.currentIndex(current: 1, previousIDs: ["a", "b"], newIDs: ["x", "a", "b"]), 2)
    }

    func testCarouselOnlyEqualizesComparableEntityCards() {
        XCTAssertTrue(CarouselMetrics.comparable([node("ProductCard"), node("ProductCard")]))
        XCTAssertTrue(CarouselMetrics.comparable([node("Card", [("children", .array([node("TransportCard")]))]), node("TransportCard")]))
        XCTAssertFalse(CarouselMetrics.comparable([node("Card"), node("Card")]))
        XCTAssertFalse(CarouselMetrics.comparable([node("Text"), node("Text")]))
        XCTAssertFalse(CarouselMetrics.comparable([node("ProductCard"), node("TransportCard")]))
    }

    func testLongListMarkersBelongToTheirOwnRowHeader() {
        let markers = ["A", "周六上午09:30–11:00", "", "B"]
        XCTAssertEqual(markers.map(ListMarkerRules.usesHeader), [false, true, false, false])
        XCTAssertTrue(ListMarkerRules.usesHeader("A\nB"))
        XCTAssertFalse(ListMarkerRules.usesHeader("🚉"))
    }

    func testPresentationSummaryIncludesStructuredVisibleContentWithoutActionOrURLData() {
        let product = Value.object([
            .init(key: "id", value: .string("opaque-id")),
            .init(key: "title", value: .string("相机套装")),
            .init(key: "images", value: .array([.object([.init(key: "url", value: .string("https://example.com/photo-only")), .init(key: "alt", value: .string("相机图片"))])])),
            .init(key: "price", value: .number(1299)),
            .init(key: "priceText", value: .string("旧报价 999")),
            .init(key: "currency", value: .string("CNY")),
            .init(key: "purchaseURL", value: .string("https://example.com/private-path"))
        ])
        let text = PresentationText.summary(node("ProductCard", [("product", product)]))
        XCTAssertTrue(text.contains("相机套装"))
        XCTAssertTrue(text.contains("1299"))
        XCTAssertTrue(text.contains("CNY"))
        XCTAssertFalse(text.contains("opaque-id"))
        XCTAssertFalse(text.contains("private-path"))
        XCTAssertFalse(text.contains("photo-only"))
        XCTAssertFalse(text.contains("旧报价"))
        XCTAssertTrue(text.contains("相机图片"))
        let editorial = Value.object([.init(key: "title", value: .string("济州岛")), .init(key: "body", value: .string("海景"))])
        XCTAssertEqual(PresentationText.summary(node("ImageText", [("content", editorial)])), "济州岛，海景")
        XCTAssertEqual(PresentationText.summary(node("List", [("items", .array([node("ListItem", [("title", .string("第一项"))])]))])), "第一项")
    }

    func testPresentationSummaryKeepsTableLabelsAndOnlyTheChartDisplaySeries() {
        let table = node("Table", [("columns", .array([.string("名称"), .string("数值")])),
                                   ("rows", .array([.array([.string("A"), .number(0.004)])]))])
        XCTAssertEqual(PresentationText.summary(table), "名称: A，数值: 0.004")
        let row = Value.object([.init(key: "x", value: .string("A")), .init(key: "value", value: .number(1.23456)), .init(key: "hidden", value: .number(999))])
        let chart = node("Chart", [("type", .string("line")), ("x", .string("x")), ("series", .array([.string("value")])), ("data", .array([row]))])
        XCTAssertEqual(PresentationText.summary(chart, locale: Locale(identifier: "en_US")), "A，value: 1.23456")
        XCTAssertFalse(PresentationText.summary(chart).contains("999"))
    }

    func testCodePreviewBoundsLinesAndKeepsUnicodeGraphemesIntact() {
        let source = (1...60).map { "line \($0)" }.joined(separator: "\n")
        let preview = CodePreview(source)
        XCTAssertTrue(preview.isTruncated)
        XCTAssertEqual(preview.text.components(separatedBy: "\n").count, 40)
        XCTAssertTrue(source.hasPrefix(preview.text))
        let emoji = String(repeating: "👩🏽‍💻", count: 10)
        XCTAssertEqual(CodePreview(emoji, maximumCharacters: 4).text, String(repeating: "👩🏽‍💻", count: 4))
        XCTAssertFalse(CodePreview("small\ncode").isTruncated)
    }

    @MainActor func testCollapsedLongCodeStillDispatchesItsCompleteSource() async throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource(#"root = Code("source")"#)
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        let source = String(repeating: "let 完整 = \"原文\"\n", count: 100)
        XCTAssertTrue(CodePreview(source).isTruncated)
        var event: ActionEvent?
        state.onAction = { event = $0 }
        _ = await context.perform(CodeComponent.copyAction(source))
        XCTAssertEqual(event?.params.first?.1, .string(OpenUIString(source)))
    }

    @MainActor func testRepeatedStableInlineFittingDoesNotReparseOrRefitAttachments() throws {
        let previous = OpenIntelligentUIPerformance.isEnabled
        OpenIntelligentUIPerformance.isEnabled = true; OpenIntelligentUIPerformance.reset()
        defer { OpenIntelligentUIPerformance.isEnabled = previous; OpenIntelligentUIPerformance.reset() }
        let view = makeNativeView()
        let bridge = makeBridge([.text("Stable **paragraph** "), attachment("a")])
        view.configure(bridge)
        let first = view.measure(240)
        for _ in 0..<100 { XCTAssertEqual(view.measure(240), first) }
        view.configure(bridge)
        XCTAssertEqual(view.measure(240), first)
        let samples = OpenIntelligentUIPerformance.snapshot()
        XCTAssertEqual(samples["inline.parse"]?.count, 1)
        XCTAssertEqual(samples["inline.measure"]?.count, 1)
        XCTAssertEqual(samples["inline.attachmentFit"]?.count, 1)
        XCTAssertEqual(samples["inline.hostUpdate"]?.count, 1)
    }

    @MainActor func testAttachmentHostsFollowIDsAcrossInsertionReorderingAndRemoval() throws {
        let view = makeNativeView()
        view.configure(makeBridge([.text("text "), attachment("a"), attachment("b")]))
        _ = view.measure(240)
        let a = try XCTUnwrap(view.hosts.first), b = try XCTUnwrap(view.hosts.last)
        view.configure(makeBridge([attachment("new"), attachment("b"), .text("text "), attachment("a")]))
        _ = view.measure(240)
        XCTAssertTrue(view.hosts[1] === b)
        XCTAssertTrue(view.hosts[2] === a)
        view.configure(makeBridge([attachment("a")]))
        XCTAssertEqual(view.hosts.count, 1)
        XCTAssertTrue(view.hosts[0] === a)
        #if os(iOS)
        XCTAssertNil(b.view.superview)
        XCTAssertNil(b.parent)
        #else
        XCTAssertNil(b.superview)
        #endif
        view.removeAllHosts()
        XCTAssertTrue(view.hosts.isEmpty)
    }

    @MainActor func testInlineWidthAndTextChangesInvalidateOnlyTheNecessaryWork() throws {
        let previous = OpenIntelligentUIPerformance.isEnabled
        OpenIntelligentUIPerformance.isEnabled = true; OpenIntelligentUIPerformance.reset()
        defer { OpenIntelligentUIPerformance.isEnabled = previous; OpenIntelligentUIPerformance.reset() }
        let view = makeNativeView()
        view.configure(makeBridge([.text("first "), attachment("a"), .text(" last")]))
        _ = view.measure(240)
        let host = try XCTUnwrap(view.hosts.first)
        _ = view.measure(120)
        XCTAssertEqual(OpenIntelligentUIPerformance.snapshot()["inline.parse"]?.count, 2)
        view.configure(makeBridge([.text("first grows "), attachment("a"), .text(" last")]))
        _ = view.measure(120)
        XCTAssertTrue(view.hosts.first === host)
        XCTAssertEqual(OpenIntelligentUIPerformance.snapshot()["inline.parse"]?.count, 3)
        XCTAssertEqual(OpenIntelligentUIPerformance.snapshot()["inline.hostUpdate"]?.count, 1)
    }

    @MainActor func testNativeRTLParagraphAndLineLimitDoNotLeaveAnActiveHiddenAttachment() throws {
        let view = makeNativeView()
        var bridge = InlineParagraphBridge(parts: [.text(String(repeating: "النص الطويل ", count: 80)), attachment("last")], size: "md", color: .primary, weight: "normal", lineSpacing: 4, maxLines: 1, open: { _ in })
        bridge.direction = .rightToLeft
        view.configure(bridge); _ = view.measure(160)
        #if os(iOS)
        let paragraph = view.attributedText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let attachmentView = try XCTUnwrap(view.hosts.first?.view)
        XCTAssertTrue(attachmentView.isHidden)
        XCTAssertFalse(attachmentView.isUserInteractionEnabled)
        #else
        let paragraph = view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertTrue(try XCTUnwrap(view.hosts.first).isHidden)
        #endif
        XCTAssertEqual(paragraph?.baseWritingDirection, .rightToLeft)
    }

    @MainActor private func attachment(_ id: String) -> InlinePart {
        .attachment(id: id, value: .string(OpenUIString(id)), view: AnyView(Color.clear.frame(width: 30, height: 18)))
    }
    private func makeBridge(_ parts: [InlinePart]) -> InlineParagraphBridge {
        InlineParagraphBridge(parts: parts, size: "md", color: .primary, weight: "normal", lineSpacing: 4, maxLines: nil, open: { _ in })
    }
    @MainActor private func makeNativeView() -> InlineNativeView {
        #if os(iOS)
        let storage = NSTextStorage(), manager = NSLayoutManager(), container = NSTextContainer(size: .zero)
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        let view = InlineNativeView(frame: .zero, textContainer: container)
        view.isScrollEnabled = false
        #else
        let view = InlineNativeView(frame: .zero)
        #endif
        view.isEditable = false; view.textContainerInset = .zero
        return view
    }
}
