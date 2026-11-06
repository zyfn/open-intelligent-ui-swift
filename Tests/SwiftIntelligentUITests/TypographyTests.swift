import XCTest
import SwiftUI
@testable import SwiftIntelligentUI
#if os(macOS)
import AppKit
#endif

final class TypographyTests: XCTestCase {
    func testInlineEmphasisKeepsItsSizeItalicAndLinkWithoutImplicitBold() throws {
        let value = InlineTypography.attributed("普通 ***[Important](https://example.com/source)***", font: .caption, emphasis: .medium)
        XCTAssertEqual(String(value.characters), "普通 Important")
        let emphasized = try XCTUnwrap(value.runs.first { $0.link != nil })
        XCTAssertEqual(emphasized.link?.absoluteString, "https://example.com/source")
        XCTAssertTrue(emphasized.inlinePresentationIntent?.contains(.emphasized) == true)
        XCTAssertFalse(emphasized.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        XCTAssertEqual(emphasized.font, Font.caption.weight(.medium))
        XCTAssertNil(value.runs.first?.font)
    }

    @MainActor func testNativeEmphasisAndTabularMediumUseTheRequestedWeights() throws {
        #if os(macOS)
        let view = InlineNativeView(frame: .zero)
        var bridge = InlineParagraphBridge(parts: [.text("**Important**")], size: "md", color: .primary, weight: "normal", lineSpacing: 4, maxLines: nil, open: { _ in })
        view.configure(bridge)
        _ = view.measure(240)
        let font = try XCTUnwrap(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font, NSFont.systemFont(ofSize: 17, weight: .medium))
        bridge.emphasisWeight = .semibold
        view.configure(bridge)
        _ = view.measure(240)
        XCTAssertEqual(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, NSFont.systemFont(ofSize: 17, weight: .semibold))

        let numeric = InlineParagraphBridge(parts: [.text("4500")], size: "md", color: .primary, weight: "medium", lineSpacing: 4, maxLines: nil, open: { _ in }, tabularNums: true)
        view.configure(numeric)
        XCTAssertEqual(view.baseFont, NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .medium))
        #endif
    }
}
