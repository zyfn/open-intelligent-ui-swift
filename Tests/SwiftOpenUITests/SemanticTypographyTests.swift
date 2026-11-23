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
        XCTAssertEqual(theme.inlineFont("lg"), theme.textBodyLg)
        XCTAssertEqual(theme.inlineTextStyle("lg").role, .body)
        for size in ["large", "large-heavy"] {
            let style = NativeRichTextStyle.textContent(size, theme: theme)
            XCTAssertEqual(style.font, size == "large" ? theme.textBodyLg : theme.textBodyLgHeavy)
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

    @MainActor func testMarkdownTableFontOverridesFollowDynamicTypeAndUpdatedTheme() throws {
        // Measure the glyphs, not the table frame: a scaled minimum row height
        // must not conceal a cell override that leaves the actual font fixed.
        for (slot, source) in [
            ("header", "| Reading |\n| --- |\n| |"),
            ("body", "| |\n| --- |\n| Reading |"),
        ] {
            func content(fontSize: CGFloat, typeSize: DynamicTypeSize) -> some View {
                var theme = OpenUIThemeValues()
                theme.textNeutralPrimary = .black
                let font = OpenUIFont(size: fontSize, design: .monospaced)
                theme.tableAppearance = OpenUITableAppearance(gridLine: .clear, headerBackground: .white,
                    background: .white, headerFont: font, bodyFont: font)
                return NativeMarkdownText(text: source)
                    .openUITheme(theme)
                    .environment(\.dynamicTypeSize, typeSize)
                    .environment(\.colorScheme, .light)
                    .frame(width: 600)
                    .background(Color.white)
            }

            let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
            #if os(iOS)
            let host = UIHostingController(rootView: content(fontSize: 18, typeSize: .large))
            let window = UIWindow(frame: bounds)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            #else
            _ = NSApplication.shared
            let host = NSHostingView(rootView: content(fontSize: 18, typeSize: .large))
            let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            window.orderFront(nil)
            defer { window.close() }
            #endif

            func snapshot() throws -> (image: CGImage, pixelsPerPoint: CGFloat, complete: Bool) {
                #if os(iOS)
                window.layoutIfNeeded()
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                var complete = false
                let rendered = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { context in
                    UIColor.white.setFill()
                    context.fill(host.view.bounds)
                    complete = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let image = try XCTUnwrap(rendered.cgImage)
                return (image, CGFloat(image.width) / host.view.bounds.width, complete)
                #else
                host.needsLayout = true
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let image = try XCTUnwrap(bitmap.cgImage)
                return (image, CGFloat(image.width) / host.bounds.width, true)
                #endif
            }

            func inkWidth(fontSize: CGFloat, typeSize: DynamicTypeSize, name: String) throws -> CGFloat {
                // Keep the mounted window, host and view type across updates.
                // Capture the native scrolling hierarchy through its mounted host.
                host.rootView = content(fontSize: fontSize, typeSize: typeSize)
                let deadline = Date().addingTimeInterval(3)
                var lastWidth: CGFloat?
                var stableSince = Date()
                var captured: CGImage?
                var complete = false
                repeat {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                    let result = try snapshot()
                    let width = try darkInkWidth(result.image) / result.pixelsPerPoint
                    if lastWidth != width { stableSince = Date() }
                    lastWidth = width
                    captured = result.image
                    complete = result.complete
                    if complete && width > 0 && Date().timeIntervalSince(stableSince) >= 0.15 { break }
                } while Date() < deadline
                // Save the last capture even when the view stayed blank or
                // incomplete, so a failed observation retains its evidence.
                try saveTypographyImage(try XCTUnwrap(captured), name: "table-font-\(slot)-\(name)")
                XCTAssertTrue(complete, "The \(slot) \(name) snapshot must include the complete native hierarchy")
                return try XCTUnwrap(lastWidth)
            }

            let ordinary = try inkWidth(fontSize: 18, typeSize: .large, name: "large")
            let accessible = try inkWidth(fontSize: 18, typeSize: .accessibility2, name: "accessibility2")
            let changed = try inkWidth(fontSize: 28, typeSize: .accessibility2, name: "updated-theme")
            let restored = try inkWidth(fontSize: 18, typeSize: .large, name: "restored")
            XCTAssertGreaterThan(ordinary, 20, "The \(slot) must contain actual glyphs")
            #if os(iOS)
            XCTAssertGreaterThan(accessible, ordinary * 1.25,
                "The \(slot) font override must scale its glyphs with Dynamic Type")
            #else
            XCTAssertEqual(accessible, ordinary, accuracy: 2,
                "The \(slot) must retain the native macOS font scaling behavior")
            #endif
            XCTAssertGreaterThan(changed, accessible * 1.25,
                "The \(slot) must read a changed theme font without retaining its initial size")
            XCTAssertEqual(restored, ordinary, accuracy: 2,
                "Restoring the theme and environment must restore the \(slot) glyph size")
        }
    }

    private func darkInkWidth(_ image: CGImage) throws -> CGFloat {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var first = image.width, last = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * context.bytesPerRow + x * 4
                if pixels[offset + 3] > 192 && max(pixels[offset], pixels[offset + 1], pixels[offset + 2]) < 64 {
                    first = min(first, x)
                    last = max(last, x)
                }
            }
        }
        return last >= first ? CGFloat(last - first + 1) : 0
    }

    private func saveTypographyImage(_ image: CGImage, name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"], !output.isEmpty else { return }
        let directory = URL(fileURLWithPath: output).appendingPathComponent("semantic-typography", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        let data = try XCTUnwrap(UIImage(cgImage: image).pngData())
        #else
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        #endif
        try data.write(to: directory.appendingPathComponent(name + ".png"))
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
