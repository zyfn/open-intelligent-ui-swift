import XCTest
import SwiftUI
import SwiftLang
@testable import SwiftIntelligentUI
#if os(macOS)
import AppKit
import CoreText
#endif

final class SemanticTypographyTests: XCTestCase {
    private let copy = "Readable content keeps its role when a layout wraps it. 中文正文应保持相同层级，并随系统字号自然换行。"

    @MainActor private func height(_ component: String, library: OpenIntelligentUIComponents,
                                   theme: OpenIntelligentUITheme = .init(), size: DynamicTypeSize = .large,
                                   scheme: ColorScheme = .light) throws -> Double {
        let state = library.makeState()
        state.setSource("root = Col([\(component)])\n$copy = \"\(copy)\"")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library)
            .openIntelligentUITheme(theme).environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, scheme).frame(width: 320))
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertGreaterThan(image.height, 0)
        return Double(image.height)
    }

    @MainActor func testOmittedTextDefaultsMatchExplicitBodyInEveryContainer() throws {
        let library = try OpenIntelligentUIComponents()
        let containers: [(String, (String) -> String)] = [
            ("flow", { $0 }),
            ("card", { "Card([\($0)])" }),
            ("nested card", { "Card([Col([Box([\($0)])])])" }),
            ("grid", { "Grid([Col([\($0)])],1)" }),
            ("carousel", { "Carousel([Col([\($0)])],288)" })
        ]
        for (name, wrap) in containers {
            for size in [DynamicTypeSize.large, .accessibility2] {
                for scheme in [ColorScheme.light, .dark] {
                    let omitted = try height(wrap("Text($copy)"), library: library, size: size, scheme: scheme)
                    let explicit = try height(wrap("Text($copy,\"md\",\"ink\",\"normal\")"), library: library, size: size, scheme: scheme)
                    XCTAssertEqual(omitted, explicit, accuracy: 1, "\(name), \(size), \(scheme)")
                }
            }
        }
    }

    @MainActor func testTransparentCardWrappersDoNotChangeTheDefaultHeading() throws {
        let library = try OpenIntelligentUIComponents()
        for size in [DynamicTypeSize.large, .accessibility2] {
            let direct = try height("Card([Title($copy)])", library: library, size: size)
            let wrapped = try height("Card([Col([Box([Title($copy)])])])", library: library, size: size)
            let explicit = try height("Card([Title($copy,\"md\")])", library: library, size: size)
            XCTAssertEqual(direct, wrapped, accuracy: 1)
            XCTAssertEqual(direct, explicit, accuracy: 1)
        }
    }

    @MainActor func testMarkdownUsesTheSameBodyAndHeadingMetricsAtDynamicTypeSizes() throws {
        let library = try OpenIntelligentUIComponents()
        for size in [DynamicTypeSize.large, .accessibility2] {
            let markdownBody = try height("Markdown($copy)", library: library, size: size)
            let nativeBody = try height("Text($copy)", library: library, size: size)
            print("Typography metrics: size=\(size) role=body markdown=\(markdownBody) native=\(nativeBody)")
            XCTAssertEqual(markdownBody, nativeBody, accuracy: 2, "body at \(size)")
            for (prefix, titleSize) in [("# ", "xl"), ("## ", "lg"), ("### ", "md")] {
                let markdown = try height("Markdown(\"\(prefix)\" + $copy)", library: library, size: size)
                let native = try height("Title($copy,\"\(titleSize)\")", library: library, size: size)
                print("Typography metrics: size=\(size) role=\(titleSize) markdown=\(markdown) native=\(native)")
                XCTAssertEqual(markdown, native, accuracy: 2, "heading \(prefix) at \(size)")
                #if os(macOS)
                try diagnoseHeadingFont(level: prefix.count - 1, titleSize: titleSize, size: size)
                #endif
            }
        }
    }

    #if os(macOS)
    /// Isolate the font adapter from Markdown parsing and the component layout.
    /// Keep the same copy, width and Dynamic Type environment as the assertion.
    @MainActor private func diagnoseHeadingFont(level: Int, titleSize: String, size: DynamicTypeSize) throws {
        let theme = OpenIntelligentUITheme()
        let preferred = InlineFonts.semantic(style: MarkdownTypography.nativeHeadingStyle(level: level), typeSize: size)
        let native = InlineFonts.styled(preferred, weight: theme.headingWeight, tabular: false, italic: false)
        let adapter = MarkdownFontStyle(native)
        let fixed = NSFont.systemFont(ofSize: adapter.size.rounded(), weight: InlineFonts.weight(adapter.weight))
        let fixedStyled = InlineFonts.styled(NSFont.systemFont(ofSize: adapter.size.rounded()),
                                             weight: adapter.weight, tabular: false, italic: false)
        let layout = NSLayoutManager()
        func coreTextLineHeight(_ font: NSFont) -> CGFloat {
            CTFontGetAscent(font as CTFont) + CTFontGetDescent(font as CTFont) + CTFontGetLeading(font as CTFont)
        }
        for (name, font) in [("preferred", preferred), ("styled", native), ("fixed", fixed), ("fixed-styled", fixedStyled)] {
            print("Typography native font: size=\(size) role=\(titleSize) recipe=\(name) name=\(font.fontName) points=\(font.pointSize) ascent=\(font.ascender) descent=\(font.descender) leading=\(font.leading) ctLineHeight=\(coreTextLineHeight(font)) layoutLineHeight=\(layout.defaultLineHeight(for: font)) descriptor=\(font.fontDescriptor.fontAttributes)")
        }
        print("Typography adapter: role=\(titleSize) size=\(adapter.size) family=\(adapter.family) weight=\(adapter.weight) themeWeight=\(theme.headingWeight)")
        let leadingDelta = max(0, native.leading - fixed.leading)
        let coreTextDelta = max(0, coreTextLineHeight(native) - coreTextLineHeight(fixed))
        let layoutDelta = max(0, layout.defaultLineHeight(for: native) - layout.defaultLineHeight(for: fixed))
        let styledCoreTextDelta = max(0, coreTextLineHeight(native) - coreTextLineHeight(fixedStyled))
        let styledLayoutDelta = max(0, layout.defaultLineHeight(for: native) - layout.defaultLineHeight(for: fixedStyled))
        print("Typography spacing candidates: size=\(size) role=\(titleSize) leading=\(leadingDelta) coreText=\(coreTextDelta) layout=\(layoutDelta) styledCoreText=\(styledCoreTextDelta) styledLayout=\(styledLayoutDelta)")
        let fixedFont = Font.system(size: adapter.size.rounded()).weight(adapter.weight)
        let fonts: [(String, Font, CGFloat)] = [
            ("semantic", TitleTypography.font(size: titleSize, theme: theme), 0),
            ("native", Font(native), 0),
            ("fixed-native", Font(fixed), 0),
            ("fixed-styled-native", Font(fixedStyled), 0),
            ("fixed-adapter-weight", fixedFont, 0),
            ("fixed-theme-weight", .system(size: adapter.size.rounded()).weight(theme.headingWeight), 0),
            ("fixed-leading-delta", fixedFont, leadingDelta),
            ("fixed-coretext-delta", fixedFont, coreTextDelta),
            ("fixed-layout-delta", fixedFont, layoutDelta),
            ("fixed-styled-coretext-delta", fixedFont, styledCoreTextDelta),
            ("fixed-styled-layout-delta", fixedFont, styledLayoutDelta),
        ]
        let samples = [
            ("copy", copy),
            ("latin-one", "Heading"),
            ("latin-two", "Heading\nHeading"),
            ("cjk-one", "中文标题"),
            ("cjk-two", "中文标题\n中文标题"),
        ]
        for (name, font) in [("native", native), ("fixed", fixed), ("fixed-styled", fixedStyled)] {
            for (sample, text) in samples {
                try diagnoseNativeLayout(font: font, text: text, sample: sample, recipe: name, role: titleSize, size: size)
            }
        }
        for (name, font, spacing) in fonts {
            for (sample, text) in samples {
                let plain = try diagnosticHeight(Text(verbatim: text).font(font).lineSpacing(spacing), size: size)
                print("Typography isolated text: size=\(size) role=\(titleSize) recipe=\(name) sample=\(sample) spacing=\(spacing) plain=\(plain)")
            }
            let attributed = try diagnosticHeight(
                Text(InlineTypography.attributed(copy, font: font, emphasis: theme.headingWeight)).font(font).lineSpacing(spacing), size: size)
            print("Typography isolated attributed: size=\(size) role=\(titleSize) recipe=\(name) spacing=\(spacing) attributed=\(attributed)")
        }
    }

    @MainActor private func diagnoseNativeLayout(font: NSFont, text: String, sample: String,
                                                 recipe: String, role: String, size: DynamicTypeSize) throws {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let storage = NSTextStorage(attributedString: attributed)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 320, height: 10_000))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var fragments: [[String: Any]] = []
        var previousBaseline: CGFloat?
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) {
            rect, used, _, glyphs, _ in
            let glyph = layout.location(forGlyphAt: glyphs.location)
            let baseline = rect.minY + glyph.y
            var record: [String: Any] = ["y": Double(rect.minY), "height": Double(rect.height),
                "usedY": Double(used.minY), "usedHeight": Double(used.height),
                "glyphY": Double(glyph.y), "baseline": Double(baseline)]
            if let previousBaseline { record["advance"] = Double(baseline - previousBaseline) }
            fragments.append(record)
            previousBaseline = baseline
        }

        let setter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 320, height: 10_000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: attributed.length), path, nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let coreTextLines: [[String: Any]] = lines.enumerated().map { index, line in
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            let runFonts: [[String: Any]] = runs.map { run in
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let font = attributes[kCTFontAttributeName as String] as? NSFont else {
                    return ["font": String(describing: attributes[kCTFontAttributeName as String])]
                }
                return ["font": font.fontName, "points": Double(font.pointSize),
                        "ascent": Double(font.ascender), "descent": Double(font.descender), "leading": Double(font.leading)]
            }
            var record: [String: Any] = ["originY": Double(origins[index].y), "width": width,
                "ascent": Double(ascent), "descent": Double(descent), "leading": Double(leading), "runs": runFonts]
            if index > 0 { record["advance"] = Double(origins[index - 1].y - origins[index].y) }
            return record
        }
        let record: [String: Any] = ["size": String(describing: size), "role": role, "recipe": recipe, "sample": sample,
            "textKitHeight": Double(layout.usedRect(for: container).height), "textKit": fragments, "coreText": coreTextLines]
        let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print("Typography native layout: \(String(decoding: json, as: UTF8.self))")
    }

    @MainActor private func diagnosticHeight<Content: View>(_ content: Content, size: DynamicTypeSize) throws -> Double {
        let renderer = ImageRenderer(content: content.fixedSize(horizontal: false, vertical: true)
            .environment(\.dynamicTypeSize, size).environment(\.colorScheme, .light).frame(width: 320))
        return Double(try XCTUnwrap(renderer.cgImage).height)
    }
    #endif

    @MainActor func testFixedNativeBodyPartnerIsNotScaledAgainByMarkdown() throws {
        let library = try OpenIntelligentUIComponents()
        var theme = OpenIntelligentUITheme()
        theme.setTextFont(PlatformFont.monospacedSystemFont(ofSize: 25, weight: .regular), for: .body)
        for size in [DynamicTypeSize.large, .accessibility2] {
            XCTAssertEqual(try height("Markdown($copy)", library: library, theme: theme, size: size),
                           try height("Text($copy)", library: library, theme: theme, size: size), accuracy: 2)
        }
    }

    func testMarkdownHeadingScaleOverridesAndHistoricalDeepLevelsRemainAvailable() {
        var theme = OpenIntelligentUITheme()
        XCTAssertTrue((1...3).allSatisfy { MarkdownTypography.usesSemanticHeading(level: $0, theme: theme) })
        theme.markdownHeadingScales = [2, 1.6, 1.2, 3, 3, 3]
        XCTAssertFalse((1...3).contains { MarkdownTypography.usesSemanticHeading(level: $0, theme: theme) })
        XCTAssertEqual((1...3).map { MarkdownTypography.headingScale(level: $0, theme: theme) }, [2, 1.6, 1.2])
        XCTAssertEqual((4...6).map { MarkdownTypography.headingScale(level: $0, theme: theme) }, [1, 0.83, 0.67])
        theme.markdownHeadingScales = [2]
        XCTAssertEqual(MarkdownTypography.headingScale(level: 2, theme: theme), 1)
    }

    @MainActor func testExplicitMarkdownScalesKeepRelativeMeaningEvenWhenValuesMatchDefaults() throws {
        let library = try OpenIntelligentUIComponents()
        var theme = OpenIntelligentUITheme()
        theme.setTextFont(PlatformFont.systemFont(ofSize: 28), for: .body)
        theme.markdownHeadingScales = [2, 1.5, 1]
        XCTAssertFalse(MarkdownTypography.usesSemanticHeading(level: 3, theme: theme))
        var expected = theme
        expected.titleFont = .system(size: 28, weight: .semibold)
        XCTAssertEqual(try height("Markdown(\"### \" + $copy)", library: library, theme: theme),
                       try height("Title($copy,\"md\")", library: library, theme: expected), accuracy: 2)

        var explicitDefaults = OpenIntelligentUITheme()
        let implicitDefaults = explicitDefaults
        explicitDefaults.markdownHeadingScales = implicitDefaults.markdownHeadingScales
        XCTAssertNotEqual(explicitDefaults, implicitDefaults, "An explicit relative policy differs from the semantic default")
        XCTAssertFalse((1...3).contains { MarkdownTypography.usesSemanticHeading(level: $0, theme: explicitDefaults) })
        explicitDefaults.setTextFont(PlatformFont.systemFont(ofSize: 28), for: .body)
        XCTAssertGreaterThan(try height("Markdown(\"# \" + $copy)", library: library, theme: explicitDefaults),
                             try height("Title($copy,\"xl\")", library: library, theme: explicitDefaults))
    }

    #if os(macOS)
    @MainActor func testMountedInlineRolesAndNativeFontPartnerSurviveThemeUpdates() throws {
        _ = NSApplication.shared
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource("""
        root = Col([Text(["caption"],"xs"),Card([Text(["body"])]),Text(["large"],"lg")])
        """)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        func content(_ theme: OpenIntelligentUITheme) -> some View {
            OpenIntelligentUIContentView(state: state, library: library)
                .openIntelligentUITheme(theme).environment(\.dynamicTypeSize, .large)
                .frame(width: 320, height: 400, alignment: .topLeading)
        }
        var theme = OpenIntelligentUITheme()
        let hosting = NSHostingView(rootView: content(theme))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
        defer { window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func settle() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            hosting.layoutSubtreeIfNeeded()
        }
        func paragraph(_ text: String) throws -> InlineNativeView {
            let matches = descendants(hosting).compactMap { $0 as? InlineNativeView }.filter { $0.string == text }
            XCTAssertEqual(matches.count, 1)
            return try XCTUnwrap(matches.first)
        }
        settle()
        let caption = try paragraph("caption"), body = try paragraph("body"), large = try paragraph("large")
        XCTAssertEqual(caption.baseFont.pointSize, NSFont.preferredFont(forTextStyle: .footnote).pointSize)
        XCTAssertEqual(body.baseFont.pointSize, NSFont.preferredFont(forTextStyle: .body).pointSize)
        XCTAssertEqual(large.baseFont.pointSize, NSFont.preferredFont(forTextStyle: .title3).pointSize)
        let revision = state.presentationRevision
        let partner = NSFont.monospacedSystemFont(ofSize: 25, weight: .regular)
        theme.setTextFont(partner, for: .body)
        hosting.rootView = content(theme)
        settle()
        XCTAssertTrue(try paragraph("body") === body, "A typography update must retain the mounted paragraph")
        XCTAssertEqual(body.baseFont.pointSize, partner.pointSize)
        XCTAssertEqual(body.baseFont.fontName, partner.fontName)
        XCTAssertEqual(state.presentationRevision, revision)
    }
    #endif
}
