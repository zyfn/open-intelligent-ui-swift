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
        XCTAssertEqual(theme.pageTitleStyle().font.size, 26)
        XCTAssertEqual(theme.sectionTitleStyle().font.size, 20)
        XCTAssertEqual(theme.objectTitleStyle().font.size, 18)
        XCTAssertEqual(theme.textStyle(.body).font.size, 16)
        XCTAssertEqual(theme.textStyle(.supporting).font.size, 14)
        XCTAssertEqual(theme.textStyle(.caption).font.size, 13)
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
        XCTAssertEqual(theme.inlineFont("lg").size, 18)
        XCTAssertEqual(theme.inlineTextStyle("lg").role, .body)
        for size in ["large", "large-heavy"] {
            let style = NativeRichTextStyle.textContent(size, theme: theme)
            XCTAssertEqual(style.font?.size, 18)
            XCTAssertEqual(style.role, .body,
                "Large copy keeps the same reading and Dynamic Type baseline as ordinary body text")
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
    @MainActor func testMarkdownAndNativeTextShareBaselineScalingAndLeading() {
        let theme = OpenUIThemeValues()
        let styles = readingStyles(theme: theme) + [NativeRichTextStyle(
            font: OpenUIFont(size: 19, weight: .medium, design: .monospaced, lineHeight: 1.7, letterSpacing: 0.03),
            role: .title)]
        for size in [DynamicTypeSize.large, .accessibility2] {
            for style in styles {
                let font = style.resolvedFont(theme: theme, inherited: nil)
                let native = measuredHeight(Text("Reading\nReading").openUIFont(font, role: style.role), size: size)
                let markdown = measuredHeight(NativeMarkdownText(text: "Reading\nReading", mode: .inline,
                    style: style), size: size)
                XCTAssertEqual(markdown, native, accuracy: 2,
                    "Native and Markdown text must apply the same body scale and resolved leading for \(style.role) at \(size)")
            }
        }
    }

    @MainActor func testMarkdownHeadingsKeepTheirRoleWhileBodyFontChanges() {
        let theme = OpenUIThemeValues()
        for size in [DynamicTypeSize.large, .accessibility2] {
            for (prefix, style) in [("#", theme.pageTitleStyle()), ("##", theme.sectionTitleStyle()), ("###", theme.objectTitleStyle())] {
                let expected = measuredHeight(Text("Heading").nativeTextStyle(style), size: size)
                for bodySize in [CGFloat(16), 32] {
                    let actual = measuredHeight(NativeMarkdownText(text: prefix + " Heading")
                        .openUIFont(OpenUIFont(size: bodySize)), size: size)
                    XCTAssertEqual(actual, expected, accuracy: 2,
                        "An inherited body font must not rescale the Markdown heading")
                }
            }
        }
    }

    private func readingStyles(theme: OpenUIThemeValues) -> [NativeRichTextStyle] {
        [theme.pageTitleStyle().richText(), theme.sectionTitleStyle().richText(), theme.objectTitleStyle().richText(),
         theme.textStyle(.body).richText(), NativeRichTextStyle.textContent("large", theme: theme),
         theme.textStyle(.supporting).richText(), theme.textStyle(.caption).richText()]
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
    @MainActor func testDefaultFontsKeepTheEstablishedBodyScalingAtAccessibilitySizes() {
        let theme = OpenUIThemeValues()
        let sizes: [(DynamicTypeSize, UIContentSizeCategory)] = [
            (.large, .large),
            (.accessibility2, .accessibilityLarge),
            (.accessibility5, .accessibilityExtraExtraExtraLarge),
        ]
        for (size, category) in sizes {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            for style in readingStyles(theme: theme) {
                let font = style.resolvedFont(theme: theme, inherited: nil)
                let pointSize = UIFontMetrics(forTextStyle: .body).scaledValue(for: font.size, compatibleWith: traits)
                let native = measuredHeight(Text("Reading").openUIFont(font, role: style.role), size: size)
                let expected = measuredHeight(Text("Reading")
                    .font(.system(size: pointSize, weight: font.weight, design: font.design)), size: size)
                XCTAssertEqual(native, expected, accuracy: 2,
                    "\(style.role) must keep the established body curve at \(size)")
            }
        }
        let page = measuredHeight(Text("Reading").nativeTextStyle(theme.pageTitleStyle()), size: .accessibility5)
        let largeBody = measuredHeight(Text("Reading").openUIFont(theme.textBodyLg), size: .accessibility5)
        let body = measuredHeight(Text("Reading").nativeTextStyle(theme.textStyle(.body)), size: .accessibility5)
        XCTAssertGreaterThan(page, largeBody,
            "Large body copy must not overtake the page-title scale at the largest accessibility size")
        XCTAssertGreaterThan(largeBody, body,
            "The established large-body size must remain larger than ordinary body text")
    }
    #endif
}
