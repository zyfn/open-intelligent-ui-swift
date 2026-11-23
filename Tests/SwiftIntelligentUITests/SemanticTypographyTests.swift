import XCTest
import SwiftUI
import SwiftLang
@testable import SwiftIntelligentUI
#if os(macOS)
import AppKit
#endif

final class SemanticTypographyTests: XCTestCase {
    private let copy = "Readable content keeps its role when a layout wraps it. 中文正文应保持相同层级，并随系统字号自然换行。"

    @MainActor private func height(_ component: String, library: OpenIntelligentUIComponents,
                                   theme: OpenIntelligentUITheme = .init(), size: DynamicTypeSize = .large,
                                   scheme: ColorScheme = .light, copyText: String? = nil) throws -> Double {
        let state = library.makeState()
        let literal = String(decoding: try JSONEncoder().encode(copyText ?? copy), as: UTF8.self)
        state.setSource("root = Col([\(component)])\n$copy = \(literal)")
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
            XCTAssertEqual(try height("Markdown($copy)", library: library, size: size),
                           try height("Text($copy)", library: library, size: size), accuracy: 2, "body at \(size)")
            for (prefix, titleSize) in [("# ", "xl"), ("## ", "lg"), ("### ", "md")] {
                XCTAssertEqual(try height("Markdown(\"\(prefix)\" + $copy)", library: library, size: size),
                               try height("Title($copy,\"\(titleSize)\")", library: library, size: size), accuracy: 2, "heading \(prefix) at \(size)")
            }
        }
    }

    @MainActor func testLongMarkdownHeadingsKeepTitleMetricsAcrossColdAndWarmRendering() throws {
        let library = try OpenIntelligentUIComponents()
        let longCopy = Array(repeating: copy, count: 3).joined(separator: " ")
        for size in [DynamicTypeSize.large, .accessibility2] {
            for text in [copy, longCopy] {
                for (prefix, titleSize) in [("# ", "xl"), ("## ", "lg"), ("### ", "md")] {
                    #if os(macOS)
                    MarkdownTypography.headingSpacingCache.removeAll()
                    #endif
                    let component = "Markdown(\"\(prefix)\" + $copy)"
                    let first = try height(component, library: library, size: size, copyText: text)
                    let title = try height("Title($copy,\"\(titleSize)\")", library: library, size: size, copyText: text)
                    let context = "heading \(prefix), \(size), characters=\(text.count)"
                    XCTAssertEqual(first, title, accuracy: 2, context)
                    #if os(macOS)
                    XCTAssertFalse(MarkdownTypography.headingSpacingCache.isEmpty,
                                   "Cold SDK rendering must resolve both fonts synchronously: \(context)")
                    #endif
                    XCTAssertEqual(try height(component, library: library, size: size, copyText: text),
                                   first, "Cached metrics must preserve the first rendered height: \(context)")
                }
            }
        }
    }

    @MainActor func testFixedNativeBodyPartnerIsNotScaledAgainByMarkdown() throws {
        let library = try OpenIntelligentUIComponents()
        var theme = OpenIntelligentUITheme()
        theme.setTextFont(PlatformFont.monospacedSystemFont(ofSize: 25, weight: .regular), for: .body)
        for size in [DynamicTypeSize.large, .accessibility2] {
            XCTAssertEqual(try height("Markdown($copy)", library: library, theme: theme, size: size),
                           try height("Text($copy)", library: library, theme: theme, size: size), accuracy: 2)
        }
    }

    @MainActor func testFixedNativeBodyPartnerKeepsMarkdownBodyBlocksStableAcrossDynamicType() throws {
        let library = try OpenIntelligentUIComponents()
        var theme = OpenIntelligentUITheme()
        theme.setTextFont(PlatformFont.monospacedSystemFont(ofSize: 25, weight: .regular), for: .body)
        let samples = [
            ("paragraph", "Reading content keeps its fixed font. 中文正文。"),
            ("quote", "> Reading content\n>\n> More quoted content"),
            ("bulleted list", "- Reading content\n- More content\n  - Nested content"),
            ("ordered list", "1. Reading content\n2. More content\n   1. Nested content"),
            ("task list", "- [ ] Reading content\n- [x] Completed content"),
            ("table header", "| Header |\n| --- |"),
            ("table body", "| Header |\n| --- |\n| Reading content |\n| More content |"),
            ("inline code", "Reading `let value = 42` after code")
        ]
        for (name, markdown) in samples {
            let standard = try height("Markdown($copy)", library: library, theme: theme,
                                      size: .large, copyText: markdown)
            let accessible = try height("Markdown($copy)", library: library, theme: theme,
                                        size: .accessibility2, copyText: markdown)
            XCTAssertEqual(accessible, standard, accuracy: 2,
                           "\(name) must retain the supplied 25-point body font, including its inherited and relative styles")
        }
    }

    @MainActor func testMarkdownCodeBlocksKeepTheirIndependentDynamicCodeFontWithFixedBody() throws {
        let library = try OpenIntelligentUIComponents()
        var theme = OpenIntelligentUITheme()
        theme.setTextFont(PlatformFont.monospacedSystemFont(ofSize: 25, weight: .regular), for: .body)
        // CommonMark retains the code line's terminating newline.
        let code = "let value = 42\n"
        var codeHeights: [Double] = []
        for size in [DynamicTypeSize.large, .accessibility2] {
            let markdown = try height("Markdown($copy)", library: library, theme: theme,
                                      size: size, copyText: "```swift\n\(code)```")
            let native = try height("Code($copy,\"swift\")", library: library, theme: theme,
                                    size: size, copyText: code)
            XCTAssertEqual(markdown, native, accuracy: 2,
                           "A fenced block must retain the native Code component's font and controls at \(size)")
            codeHeights.append(markdown)
        }
        #if os(iOS)
        XCTAssertGreaterThan(codeHeights[1], codeHeights[0],
                             "Fixing the body font must not freeze the code block's semantic Dynamic Type font")
        #endif
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
    @MainActor func testMarkdownHeadingMetricsSurviveColdAndRepeatedNativeFitting() throws {
        let library = try OpenIntelligentUIComponents()
        let longCopy = Array(repeating: copy, count: 3).joined(separator: " ")
        for size in [DynamicTypeSize.large, .accessibility2] {
            for scale in [CGFloat(1), CGFloat(2)] {
                for text in [copy, longCopy] {
                    func host(_ component: String) -> (NSHostingView<AnyView>, OpenUIState) {
                        let state = library.makeState()
                        state.setSource("root = Col([\(component)])\n$copy = \"\(text)\"")
                        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
                        let content = OpenIntelligentUIContentView(state: state, library: library)
                            .openIntelligentUITheme(.init())
                            .environment(\.dynamicTypeSize, size)
                            .environment(\.displayScale, scale)
                            .environment(\.colorScheme, .light)
                            .frame(width: 320)
                        return (NSHostingView(rootView: AnyView(content)), state)
                    }
                    for (prefix, titleSize) in [("# ", "xl"), ("## ", "lg"), ("### ", "md")] {
                        MarkdownTypography.headingSpacingCache.removeAll()
                        let (markdown, state) = host("Markdown(\"\(prefix)\" + $copy)")
                        let revision = state.presentationRevision
                        let first = markdown.fittingSize.height
                        let cachedKeys = Set(MarkdownTypography.headingSpacingCache.keys)
                        let (title, _) = host("Title($copy,\"\(titleSize)\")")
                        let expected = title.fittingSize.height
                        let context = "heading \(prefix), \(size), scale=\(scale), characters=\(text.count)"
                        XCTAssertGreaterThan(first, 0, context)
                        XCTAssertFalse(cachedKeys.isEmpty,
                                       "Cold native fitting must resolve both fonts synchronously: \(context)")
                        XCTAssertEqual(first, expected, accuracy: 2, context)
                        for _ in 0..<3 {
                            XCTAssertEqual(markdown.fittingSize.height, first, accuracy: 0.001, context)
                        }
                        XCTAssertEqual(Set(MarkdownTypography.headingSpacingCache.keys), cachedKeys, context)
                        XCTAssertEqual(state.presentationRevision, revision,
                                       "Font measurement must not publish SDK state: \(context)")
                    }
                }
            }
        }
    }

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
