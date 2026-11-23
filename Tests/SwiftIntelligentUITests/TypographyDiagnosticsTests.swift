#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import CoreText
@testable import SwiftIntelligentUI

/// Temporary evidence only; this file and its workflow do not enter main.
final class TypographyDiagnosticsTests: XCTestCase {
    @MainActor func testRecordActualNativeMetrics() throws {
        guard #available(iOS 26, *) else {
            XCTFail("The diagnostic runner must provide iOS 26 FontResolutionContext")
            return
        }
        for (size, category) in [(DynamicTypeSize.large, UIContentSizeCategory.large),
                                  (.accessibility2, .accessibilityLarge),
                                  (.accessibility5, .accessibilityExtraExtraExtraLarge)] {
            let renderer = ImageRenderer(content: TypographyMetricProbe(label: String(describing: size), category: category)
                .environment(\.dynamicTypeSize, size).environment(\.displayScale, 2)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.lineSpacing, 0).frame(width: 1, height: 1))
            renderer.scale = 2
            XCTAssertNotNil(renderer.cgImage)
        }
    }
}

@available(iOS 26, *)
private struct TypographyMetricProbe: View {
    let label: String
    let category: UIContentSizeCategory
    @Environment(\.fontResolutionContext) private var fontContext
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .body) private var body16: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var body17: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var title22: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var display26: CGFloat = 26

    var body: some View {
        let theme = OpenIntelligentUITheme()
        let fonts: [(String, Font)] = [
            ("body", theme.bodyFont.weight(.regular)),
            ("heading1", TitleTypography.font(size: "xl", theme: theme)),
            ("heading2", TitleTypography.font(size: "lg", theme: theme)),
            ("heading3", TitleTypography.font(size: "md", theme: theme)),
            ("fixed-mono25", .system(size: 25, design: .monospaced))
        ]
        let metrics = UIFontMetrics(forTextStyle: .body)
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let scaled: [String: Any] = ["kind": "scaling", "typeSize": label, "unit": unit,
            "scaled16": body16, "scaled17": body17, "scaled22": title22, "scaled26": display26,
            "ui16": metrics.scaledValue(for: 16, compatibleWith: traits),
            "ui17": metrics.scaledValue(for: 17, compatibleWith: traits),
            "ui22": metrics.scaledValue(for: 22, compatibleWith: traits),
            "ui26": metrics.scaledValue(for: 26, compatibleWith: traits)]
        let _ = emitTypographyMetric(scaled)
        let resolved: [(String, Font, Font)] = fonts.map { name, font in
            let native = font.resolve(in: fontContext).ctFont as UIFont
            let style = MarkdownFontStyle(native)
            let design: Font.Design = CTFontGetSymbolicTraits(native as CTFont).contains(.traitMonoSpace) ? .monospaced : .default
            let fixed = Font.system(size: style.size.rounded(), weight: style.weight, design: design)
            emitTypographyMetric(["kind": "font", "typeSize": label, "role": name,
                "name": native.fontName, "size": native.pointSize, "ascender": native.ascender,
                "descender": native.descender, "leading": native.leading, "lineHeight": native.lineHeight,
                "rebuiltSize": style.size.rounded()])
            return (name, font, fixed)
        }
        return Canvas(rendersAsynchronously: false) { context, _ in
            let copy = "Readable content keeps its role when a layout wraps it. 中文正文应保持相同层级，并随系统字号自然换行。"
            let samples = [("single", "Heading"), ("two-lines", "Heading\nHeading"), ("mixed", copy),
                           ("long-mixed", Array(repeating: copy, count: 3).joined(separator: " "))]
            let area = CGSize(width: 320, height: 10_000)
            for (name, semantic, fixed) in resolved {
                for (sample, text) in samples {
                    let a = context.resolve(Text(verbatim: text).font(semantic))
                    let b = context.resolve(Text(verbatim: text).font(fixed))
                    emitTypographyMetric(["kind": "layout", "typeSize": label, "role": name, "sample": sample,
                        "semanticWidth": a.measure(in: area).width, "semanticHeight": a.measure(in: area).height,
                        "fixedWidth": b.measure(in: area).width, "fixedHeight": b.measure(in: area).height,
                        "semanticFirst": a.firstBaseline(in: area), "semanticLast": a.lastBaseline(in: area),
                        "fixedFirst": b.firstBaseline(in: area), "fixedLast": b.lastBaseline(in: area)])
                }
            }
        }
    }
}

private func emitTypographyMetric(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let json = String(data: data, encoding: .utf8) else { return }
    print("TYPOGRAPHY_METRIC " + json)
}
#endif
