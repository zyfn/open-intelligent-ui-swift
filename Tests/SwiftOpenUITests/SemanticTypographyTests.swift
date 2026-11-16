import SwiftUI
import XCTest
@testable import SwiftOpenUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class SemanticTypographyTests: XCTestCase {
    func testReadingRolesShareTheirNativeAndMarkdownRecipes() {
        let theme = OpenUIThemeValues()
        #if os(iOS)
        XCTAssertEqual(theme.pageTitleStyle().font.size, 22)
        XCTAssertEqual(theme.sectionTitleStyle().font.size, 20)
        XCTAssertEqual(theme.objectTitleStyle().font.size, 17)
        XCTAssertEqual(theme.textStyle(.body).font.size, 17)
        XCTAssertEqual(theme.textStyle(.supporting).font.size, 15)
        XCTAssertEqual(theme.textStyle(.caption).font.size, 13)
        #else
        XCTAssertEqual(theme.pageTitleStyle().font.size, 26)
        XCTAssertEqual(theme.objectTitleStyle().font.size, 18)
        XCTAssertEqual(theme.textStyle(.body).font.size, 16)
        #endif
        for (level, style) in [(1, theme.pageTitleStyle()), (2, theme.sectionTitleStyle()), (3, theme.objectTitleStyle())] {
            XCTAssertEqual(theme.markdownHeadingStyle(level).font, style.font)
            XCTAssertEqual(theme.markdownHeadingStyle(level).role, style.role)
        }
        XCTAssertEqual(theme.inlineFont("sm"), theme.inlineFont("md"),
            "The accepted Lang size aliases must not acquire different meanings")
        XCTAssertEqual(theme.textStyle(.compactBody).font, theme.textStyle(.supporting).font)
        XCTAssertEqual(theme.textStyle(.compactBody).color, theme.textNeutralPrimary)
        XCTAssertEqual(theme.textStyle(.supporting).color, theme.textNeutralSecondary,
            "Information priority belongs to the slot, not its point size")
        XCTAssertEqual(theme.inlineTextStyle("lg").role, .largeBody)
        for size in ["large", "large-heavy"] {
            XCTAssertEqual(NativeRichTextStyle.textContent(size, theme: theme).role, .largeBody)
        }
    }

    func testExplicitAndInheritedFontsKeepAllTheirParameters() {
        var inherited = OpenUIFont(size: 23, weight: .light, family: "Custom body", design: .serif,
            lineSpacing: 0.4, lineHeight: 1.8, letterSpacing: 0.06)
        inherited.monospacedDigits = true
        var emphasized = OpenUIFont(size: 27, weight: .black, family: "Custom emphasis", design: .rounded,
            lineSpacing: 0.3, lineHeight: 1.7, letterSpacing: 0.02)
        emphasized.monospacedDigits = true
        var overrides = OpenUITheme()
        overrides.textBodyDefault = inherited
        overrides.textBodyDefaultHeavy = emphasized
        let theme = overrides.resolved()
        XCTAssertEqual(theme.textBodyDefault, inherited)
        XCTAssertEqual(theme.inlineFont("sm", emphasized: true), emphasized)
        XCTAssertEqual(NativeRichTextStyle.textContent(nil, theme: theme)
            .resolvedFont(theme: theme, inherited: inherited), inherited)
        XCTAssertEqual(NativeRichTextStyle(font: emphasized, role: .title)
            .resolvedFont(theme: theme, inherited: inherited), emphasized)
        XCTAssertEqual(theme.pageTitleStyle().font, OpenUIThemeValues().pageTitleStyle().font,
            "Body overrides must not silently rewrite independent heading tokens")
    }

    #if os(iOS) || os(macOS)
    @MainActor func testMarkdownAndNativeTextScaleTogetherWithoutDoubling() {
        let theme = OpenUIThemeValues()
        let styles = [theme.pageTitleStyle(), theme.sectionTitleStyle(), theme.objectTitleStyle(),
            theme.textStyle(.body), theme.textStyle(.largeBody), theme.textStyle(.supporting), theme.textStyle(.caption)]
        for size in [DynamicTypeSize.large, .accessibility2] {
            for style in styles {
                let native = measuredHeight(Text("Reading").nativeTextStyle(style), size: size)
                let markdown = measuredHeight(NativeMarkdownText(text: "Reading", mode: .inline,
                    style: style.richText()), size: size)
                XCTAssertEqual(markdown, native, accuracy: 2,
                    "MarkdownUI's body scaling must be compensated for the \(style.role) role at \(size)")
            }
        }
    }

    @MainActor func testMarkdownHeadingsKeepTheirRoleWhileBodyFontChanges() {
        let theme = OpenUIThemeValues()
        for size in [DynamicTypeSize.large, .accessibility2] {
            for (prefix, style) in [("#", theme.pageTitleStyle()), ("##", theme.sectionTitleStyle()), ("###", theme.objectTitleStyle())] {
                let expected = measuredHeight(Text("Heading").nativeTextStyle(style), size: size)
                for bodySize in [CGFloat(17), 34] {
                    let actual = measuredHeight(NativeMarkdownText(text: prefix + " Heading")
                        .openUIFont(OpenUIFont(size: bodySize)), size: size)
                    XCTAssertEqual(actual, expected, accuracy: 2,
                        "An inherited body font must not rescale the Markdown heading")
                }
            }
        }
    }

    @MainActor private func measuredHeight<V: View>(_ content: V, size: DynamicTypeSize) -> CGFloat {
        let view = content.environment(\.dynamicTypeSize, size).frame(width: 600)
        #if os(iOS)
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: 600, height: 10_000)).height
        #else
        _ = NSApplication.shared
        return NSHostingView(rootView: view).fittingSize.height
        #endif
    }
    #endif

    #if os(iOS)
    @MainActor func testDefaultRoleFontsFollowPlatformTextStylesAtLargerSizes() {
        let theme = OpenUIThemeValues()
        let pairs: [(NativeTextStyle, Font)] = [
            (theme.pageTitleStyle(), .title2.weight(.semibold)),
            (theme.sectionTitleStyle(), .title3.weight(.semibold)),
            (theme.objectTitleStyle(), .headline),
            (theme.textStyle(.body), .body),
            (theme.textStyle(.largeBody), .title3),
            (theme.textStyle(.supporting), .subheadline),
            (theme.textStyle(.caption), .footnote),
        ]
        for size in [DynamicTypeSize.large, .accessibility2] {
            for (style, systemFont) in pairs {
                let native = measuredHeight(Text("Reading").nativeTextStyle(style), size: size)
                let system = measuredHeight(Text("Reading").font(systemFont), size: size)
                XCTAssertEqual(native, system, accuracy: 2,
                    "\(style.role) must follow its platform text style, including its Dynamic Type curve")
            }
        }
        let page = measuredHeight(Text("Reading").nativeTextStyle(theme.pageTitleStyle()), size: .accessibility5)
        let largeBody = measuredHeight(Text("Reading").nativeTextStyle(theme.textStyle(.largeBody)), size: .accessibility5)
        XCTAssertGreaterThanOrEqual(page, largeBody,
            "Large body copy must not overtake the page-title scale at the largest accessibility size")
    }
    #endif
}
