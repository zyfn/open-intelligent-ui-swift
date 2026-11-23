#if os(macOS)
import AppKit
import SwiftUI
import SwiftLang
import WebKit
import XCTest
@testable import SwiftIntelligentUI

final class SVGLayoutTests: XCTestCase {
    @MainActor func testMountedSVGUsesItsViewBoxRatioAndOfficialWidthLimits() async throws {
        // Svg.tsx/svg.styles.ts at c531b0d: height:auto; the omitted width
        // fills its column up to max(280, viewBoxWidth * 1.5). An authored
        // width is still bounded by the containing column's max-width:100%.
        let cases: [(name: String, column: CGFloat, viewBox: String, dimensions: String, expected: CGSize)] = [
            ("wide narrow", 280, "0 0 400 200", "", CGSize(width: 280, height: 140)),
            ("wide regular", 350, "0 0 400 200", "", CGSize(width: 350, height: 175)),
            ("portrait", 280, "0 0 400 800", "", CGSize(width: 280, height: 560)),
            ("short", 280, "0 0 400 20", "", CGSize(width: 280, height: 14)),
            ("fallback ratio", 200, "", "", CGSize(width: 200, height: 200)),
            ("small natural cap", 390, "0 0 100 100", "", CGSize(width: 280, height: 280)),
            ("viewBox natural cap", 800, "0 0 400 200", "", CGSize(width: 600, height: 300)),
            ("explicit width", 350, "0 0 400 200", ",120", CGSize(width: 120, height: 60)),
            ("explicit width cap", 280, "0 0 400 200", ",640", CGSize(width: 280, height: 140)),
            ("explicit percentage", 280, "0 0 400 200", ",\"50%\"", CGSize(width: 140, height: 70)),
            ("explicit full width", 390, "0 0 100 100", ",\"100%\"", CGSize(width: 390, height: 390)),
            ("explicit height", 280, "0 0 400 200", ",null,240", CGSize(width: 280, height: 240)),
            ("explicit auto height", 280, "0 0 400 200", ",null,\"auto\"", CGSize(width: 280, height: 140))
        ]
        let library = try OpenIntelligentUIComponents()
        for item in cases {
            let source = "root=Col([Svg([Rect(0,0,100,100,\"info\")],\"\(item.viewBox)\",\"Size fixture\"\(item.dimensions))])"
            let result = try await mounted(source, width: item.column, library: library)
            XCTAssertEqual(result.canvas.width, item.expected.width, accuracy: 0.5, item.name)
            XCTAssertEqual(result.canvas.height, item.expected.height, accuracy: 0.5, item.name)
            XCTAssertEqual(result.documentHeight, item.expected.height, accuracy: 1, item.name)
            XCTAssertEqual(result.canvas.midX, item.column / 2, accuracy: 0.5,
                           "The capped or authored canvas remains centered: \(item.name)")
            XCTAssertFalse(result.allowsContentJavaScript, item.name)
        }
    }

    @MainActor func testAccessibilityTextRemainsCompleteOutsideTheNaturallySizedCanvas() async throws {
        let labels = [
            "室外空气中的热量由低温制冷剂吸收，经过压缩机升温加压后送到室内。",
            "室内换热器释放热量，制冷剂再经过降压降温回到室外，形成完整循环。",
            "这些说明保持完整，辅助阅读时使用原生正文，不依赖图中的固定坐标字号。"
        ]
        let shapes = labels.enumerated().map { "SvgText(\"\($0.element)\",10,\(20 + $0.offset * 20),14)" }.joined(separator: ",")
        let source = "root=Col([Svg([\(shapes)],\"0 0 400 200\",\"完整热泵循环\")])"
        let library = try OpenIntelligentUIComponents()
        let regular = try await mounted(source, width: 320, library: library)
        let accessible = try await mounted(source, width: 320, typeSize: .accessibility3, library: library)
        XCTAssertEqual(regular.canvas.size, accessible.canvas.size,
                       "Accessibility text must not stretch the drawing's viewBox")
        XCTAssertEqual(accessible.canvas.height, 160, accuracy: 0.5)
        XCTAssertEqual(regular.documentHeight, 160, accuracy: 1)

        let reference = ImageRenderer(content: Text(labels.joined(separator: " · "))
            .font(OpenIntelligentUITheme().bodyFont).fixedSize(horizontal: false, vertical: true)
            .frame(width: 320).environment(\.dynamicTypeSize, .accessibility3))
        reference.scale = 1
        let nativeTextHeight = CGFloat(try XCTUnwrap(reference.cgImage).height)
        XCTAssertGreaterThan(nativeTextHeight, 30)
        XCTAssertEqual(accessible.documentHeight, 160 + OpenIntelligentUITheme().innerSpacing + nativeTextHeight,
                       accuracy: 2, "Every label remains in the separate native text block without clipping")
        XCTAssertFalse(accessible.allowsContentJavaScript)
    }

    private struct MountedResult {
        let canvas: CGRect
        let documentHeight: CGFloat
        let allowsContentJavaScript: Bool
    }

    @MainActor private func mounted(_ source: String, width: CGFloat, typeSize: DynamicTypeSize = .large,
                                    library: OpenIntelligentUIComponents) async throws -> MountedResult {
        _ = NSApplication.shared
        let state = library.makeState()
        defer { state.reset() }
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertTrue(state.isComplete)
        let revision = state.sourceRevision
        var theme = OpenIntelligentUITheme()
        theme.readingWidth = 1000
        let host = NSHostingView(rootView: OpenIntelligentUIContentView(state: state, library: library)
            .openIntelligentUITheme(theme).environment(\.dynamicTypeSize, typeSize)
            .frame(width: width).fixedSize(horizontal: false, vertical: true))
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: width, height: 1600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }

        // Measure the actual registered renderer and its native WebKit surface.
        // This is geometry evidence; Gallery's snapshot tests check the pixels.
        let deadline = Date().addingTimeInterval(5)
        var previous: CGRect?
        var previousHeight: CGFloat?
        repeat {
            host.layoutSubtreeIfNeeded()
            let height = host.fittingSize.height
            if let web = descendants(host).compactMap({ $0 as? WKWebView }).first {
                let frame = web.convert(web.bounds, to: host)
                if frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0,
                   height.isFinite, frame == previous, height == previousHeight {
                    XCTAssertEqual(state.sourceRevision, revision)
                    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
                    return MountedResult(canvas: frame, documentHeight: height,
                        allowsContentJavaScript: web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
                }
                previous = frame
                previousHeight = height
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        } while Date() < deadline
        throw NSError(domain: "SVGLayoutTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "The mounted SVG did not obtain a finite, stable canvas"])
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
#endif
