import SwiftLang
import Foundation
import SwiftUI
import XCTest
@testable import SwiftOpenUI
#if os(macOS)
import AppKit
#endif

final class LayoutMeasurementReductionTests: XCTestCase {
    func testFlexPlacementReusesOnlyTheMostRecentMatchingProposal() {
        var cache = OpenUIFlexLayout.Cache(), measurements = 0
        func measured(_ width: CGFloat?, _ height: CGFloat? = nil) -> [CGRect] {
            cache.resolve(.init(width: width, height: height)) {
                measurements += 1
                return [CGRect(x: 0, y: 0, width: width ?? 100, height: height ?? 40)]
            }
        }
        let first = measured(320)
        XCTAssertEqual(measured(320), first)
        XCTAssertEqual(measurements, 1, "Sizing and placement can share the same effective proposal")
        XCTAssertEqual(measured(160).first?.width, 160)
        XCTAssertEqual(measured(160, 80).first?.height, 80)
        XCTAssertEqual(measured(320), first)
        XCTAssertEqual(measurements, 4, "Different proposals replace the one cached entry")
        cache = .init()
        XCTAssertEqual(measured(320), first)
        XCTAssertEqual(measurements, 5, "A new layout/subview lifetime must measure again")
    }

    func testFlexReusesNegotiatedWidthsOnlyInsideTheCurrentCall() {
        var calls = [Int](repeating: 0, count: 3)
        let actual = NativeFlexRowWidths.proposals(ideal: [40, 200, 80], growing: [false, true, false], width: 360, gap: 10) {
            index, width in
            calls[index] += 1
            return width
        }
        XCTAssertEqual(actual, [40, 220, 80])
        XCTAssertEqual(calls, [1, 1, 1])
        var legacyCalls = 0
        let expected = legacyFlex(ideal: [40, 200, 80], growing: [false, true, false], width: 360, gap: 10) { _, width in
            legacyCalls += 1
            return width
        }
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(legacyCalls, 5)
    }

    func testFlexWithNoGrowingChildrenDoesNotAddMeasurements() {
        var count = 0
        let result = NativeFlexRowWidths.proposals(ideal: [30, 90], growing: [false, false], width: 140, gap: 10) { _, width in
            count += 1
            return width
        }
        XCTAssertEqual(result, [30, 90])
        XCTAssertEqual(count, 2)
    }

    func testFlexAllGrowingAndEmptyRows() {
        var count = 0
        let result = NativeFlexRowWidths.proposals(ideal: [20, 50, 80], growing: [true, true, true], width: 320, gap: 10) { _, width in
            count += 1
            return width
        }
        XCTAssertEqual(result, [100, 100, 100])
        XCTAssertEqual(count, 3)
        XCTAssertTrue(NativeFlexRowWidths.proposals(ideal: [], growing: [], width: 0, gap: 10) { _, _ in
            XCTFail("An empty row must not measure a child")
            return 0
        }.isEmpty)
    }

    func testFlexDifferentClampedProposalIsMeasuredAgain() {
        var offers: [CGFloat] = []
        let actual = NativeFlexRowWidths.proposals(ideal: [-10, 100], growing: [false, true], width: 200, gap: 10) { index, width in
            if index == 0 { offers.append(width) }
            return max(0, width)
        }
        XCTAssertEqual(offers, [-10, 0])
        XCTAssertEqual(actual, [0, 190])
    }

    func testFlexNewContentAndProposalCannotReusePreviousWidths() {
        var naturalWidth: CGFloat = 30
        var count = 0
        func measure(_ index: Int, _ width: CGFloat) -> CGFloat {
            count += 1
            return index == 0 ? min(naturalWidth, width) : width
        }
        let first = NativeFlexRowWidths.proposals(ideal: [200, 200], growing: [false, true], width: 400, gap: 10, measure: measure)
        naturalWidth = 90
        let second = NativeFlexRowWidths.proposals(ideal: [200, 200], growing: [false, true], width: 400, gap: 10, measure: measure)
        let resized = NativeFlexRowWidths.proposals(ideal: [200, 200], growing: [false, true], width: 160, gap: 10, measure: measure)
        XCTAssertEqual(first[1], 360)
        XCTAssertEqual(second[1], 300)
        XCTAssertEqual(resized[1], 75)
        XCTAssertEqual(count, 6)
    }

    func testFlexProposalsMatchPreviousAlgorithmAcrossNegotiationCases() {
        for count in 1...12 {
            for width: CGFloat in [0, 1, 40, 160, 375, 1024] {
                for gap: CGFloat in [-4, 0, 8, 24] {
                    for mode in 0..<4 {
                        let ideal = (0..<count).map { CGFloat(($0 * 73 + count * 17) % 240) }
                        let growing = (0..<count).map { mode == 0 ? false : mode == 1 ? true : ($0 + mode) % 3 == 0 }
                        let measure: (Int, CGFloat) -> CGFloat = { index, offered in
                            switch mode {
                            case 0: return offered
                            case 1: return min(offered, ideal[index] / 2)
                            case 2: return max(offered, CGFloat(index * 9))
                            default: return min(ideal[index], max(0, offered - 7))
                            }
                        }
                        let actual = NativeFlexRowWidths.proposals(ideal: ideal, growing: growing, width: width, gap: gap, measure: measure)
                        let expected = legacyFlex(ideal: ideal, growing: growing, width: width, gap: gap, measure: measure)
                        XCTAssertEqual(actual, expected, "count=\(count), width=\(width), gap=\(gap), mode=\(mode)")
                    }
                }
            }
        }
    }

    func testVerticalMediaOnlyMeasuresFullWidthCopy() {
        var offers: [CGFloat] = []
        let result = NativeMediaRowPlacement.measure(width: 320, media: CGSize(width: 80, height: 60), gap: 12,
                                                     axis: .vertical, centered: false) { width in
            offers.append(width)
            return CGSize(width: width, height: 40)
        }
        XCTAssertEqual(offers, [320])
        XCTAssertEqual(result.text, CGRect(x: 0, y: 72, width: 320, height: 40))
        XCTAssertTrue(result.stacked)
    }

    func testFittingHorizontalMediaOnlyMeasuresRemainingWidth() {
        var offers: [CGFloat] = []
        let result = NativeMediaRowPlacement.measure(width: 320, media: CGSize(width: 80, height: 60), gap: 12,
                                                     axis: .horizontal, centered: true) { width in
            offers.append(width)
            return CGSize(width: width, height: 40)
        }
        XCTAssertEqual(offers, [228])
        XCTAssertEqual(result.text, CGRect(x: 92, y: 10, width: 228, height: 40))
        XCTAssertFalse(result.stacked)
    }

    func testRejectedHorizontalWidthStillFallsBackToFullViewport() {
        var offers: [CGFloat] = []
        let result = NativeMediaRowPlacement.measure(width: 320, media: CGSize(width: 80, height: 60), gap: 12,
                                                     axis: .horizontal, centered: false) { width in
            offers.append(width)
            return CGSize(width: max(280, width), height: 40)
        }
        XCTAssertEqual(offers, [228, 320])
        XCTAssertEqual(result.text.width, 320)
        XCTAssertEqual(result.size.width, 412)
        XCTAssertFalse(result.stacked)
    }

    func testNoRemainingWidthSkipsTheUnusedMinimumWidthProbe() {
        var offers: [CGFloat] = []
        let result = NativeMediaRowPlacement.measure(width: 40, media: CGSize(width: 80, height: 60), gap: 12,
                                                     axis: .horizontal, centered: false) { width in
            offers.append(width)
            return CGSize(width: width, height: 40)
        }
        XCTAssertEqual(offers, [40])
        XCTAssertEqual(result.size.width, 132)
        XCTAssertFalse(result.stacked)
    }

    func testMediaNewContentIsMeasuredOnEveryCall() {
        var height: CGFloat = 20
        var count = 0
        func measure(_ width: CGFloat) -> CGSize {
            count += 1
            return CGSize(width: width, height: height)
        }
        let first = NativeMediaRowPlacement.measure(width: 320, media: .zero, gap: 12, axis: .vertical, centered: false, text: measure)
        height = 90
        let second = NativeMediaRowPlacement.measure(width: 320, media: .zero, gap: 12, axis: .vertical, centered: false, text: measure)
        XCTAssertEqual(first.size.height, 20)
        XCTAssertEqual(second.size.height, 90)
        XCTAssertEqual(count, 2)
    }

    func testMediaGeometryMatchesPreviousAlgorithmIncludingOverflowAndInvalidSizes() {
        let mediaSizes: [CGSize] = [.zero, .init(width: 90, height: 70), .init(width: 500, height: 150),
                                   .init(width: -10, height: 70), .init(width: CGFloat.nan, height: CGFloat.infinity)]
        for width: CGFloat in [.nan, -.infinity, -100, 0, 1, 40, 160, 375, 1024, .infinity] {
            for media in mediaSizes {
                for gap: CGFloat in [-5, 0, 10, 25] {
                    for axis: NativeMediaRowAxis in [.horizontal, .vertical] {
                        for centered in [false, true] {
                            for mode in 0..<4 {
                                let text: (CGFloat) -> CGSize = { offered in
                                    switch mode {
                                    case 0: return CGSize(width: offered, height: ceil(900 / offered) * 17)
                                    case 1: return CGSize(width: max(250, offered), height: 45)
                                    case 2: return CGSize(width: offered + 0.5, height: 0)
                                    default: return CGSize(width: CGFloat.nan, height: CGFloat.infinity)
                                    }
                                }
                                let actual = NativeMediaRowPlacement.measure(width: width, media: media, gap: gap, axis: axis, centered: centered, text: text)
                                let expected = legacyMedia(width: width, media: media, gap: gap, axis: axis, centered: centered, text: text)
                                XCTAssertEqual(actual.media, expected.media)
                                XCTAssertEqual(actual.text, expected.text)
                                XCTAssertEqual(actual.size, expected.size)
                                XCTAssertEqual(actual.stacked, expected.stacked)
                            }
                        }
                    }
                }
            }
        }
    }

    // Baseline implementations from FlowLayout.swift at 4803d11. These reference
    // algorithms deliberately retain the redundant probes for differential tests.
    private func legacyFlex(ideal: [CGFloat], growing: [Bool], width: CGFloat, gap: CGFloat,
                            measure: (Int, CGFloat) -> CGFloat) -> [CGFloat] {
        var proposals = ideal.map { min(width, $0) }
        var remaining = max(0, width - gap * CGFloat(ideal.count - 1))
        let order = ideal.indices.sorted { ideal[$0] < ideal[$1] }
        for (position, index) in order.enumerated() {
            let offered = min(ideal[index], remaining / CGFloat(order.count - position))
            proposals[index] = max(0, offered)
            remaining = max(0, remaining - measure(index, offered))
        }
        let flexible = ideal.indices.filter { growing[$0] }
        if !flexible.isEmpty {
            let intrinsicWidth = ideal.indices.filter { !growing[$0] }.reduce(CGFloat.zero) { sum, index in
                sum + measure(index, proposals[index])
            }
            let share = max(0, width - gap * CGFloat(ideal.count - 1) - intrinsicWidth) / CGFloat(flexible.count)
            for index in flexible { proposals[index] = share }
        }
        return proposals
    }

    private func legacyMedia(width: CGFloat, media idealMedia: CGSize, gap: CGFloat,
                             axis: NativeMediaRowAxis, centered: Bool,
                             text: (CGFloat) -> CGSize) -> NativeMediaRowPlacement.Result {
        let width = width.isFinite ? max(1, width) : 1
        func finite(_ value: CGFloat) -> CGFloat { value.isFinite ? max(0, value) : 0 }
        func copy(_ proposed: CGFloat) -> CGSize {
            let measured = text(max(1, proposed))
            return CGSize(width: max(max(1, proposed), finite(measured.width)), height: finite(measured.height))
        }
        let full = copy(width)
        let media = CGSize(width: finite(idealMedia.width), height: finite(idealMedia.height))
        let gap = media.width > 0 && media.height > 0 ? max(0, gap) : 0
        let remaining = max(0, width - media.width - gap)
        let beside = copy(remaining)
        if axis == .vertical {
            let textFrame = CGRect(x: 0, y: media.height + gap, width: full.width, height: full.height)
            return .init(media: CGRect(origin: CGPoint(x: centered ? max(0, (width - media.width) / 2) : 0, y: 0), size: media), text: textFrame,
                         size: CGSize(width: max(width, max(media.width, full.width)), height: textFrame.maxY), stacked: true)
        }
        let overflows = remaining <= 0 || beside.width > remaining + 0.5
        let measured = overflows ? full : beside
        let height = max(media.height, measured.height)
        let textFrame = CGRect(x: media.width + gap, y: centered ? (height - measured.height) / 2 : 0,
                               width: measured.width, height: measured.height)
        return .init(media: CGRect(origin: CGPoint(x: 0, y: centered ? (height - media.height) / 2 : 0), size: media), text: textFrame,
                     size: CGSize(width: max(width, textFrame.maxX), height: height), stacked: false)
    }
}

#if os(macOS)
extension LayoutMeasurementReductionTests {
    @MainActor func testMountedFlexInvalidatesForSameCountContentWidthAndFontEnvironment() {
        let inputs = FlexCacheInputs()
        withFlexHost(inputs, row: false) { height in
            let initial = height()
            inputs.childSize.height = 160
            let taller = height()
            XCTAssertEqual(taller, initial + 120, accuracy: 1,
                           "A same-count child height change must invalidate the placement")

            inputs.text = String(repeating: "Long text wraps and keeps every word visible. ", count: 12)
            let longer = height()
            XCTAssertGreaterThan(longer, taller)
            inputs.width = 160
            let narrower = height()
            XCTAssertGreaterThan(narrower, longer)
            // dynamicTypeSize does not scale macOS text. Change the inherited
            // font itself to exercise a real environment-driven size update.
            inputs.fontSize = 32
            XCTAssertGreaterThan(height(), narrower, "Environment-driven text sizing must invalidate the cache")

            inputs.text = "Short text"
            inputs.width = 320; inputs.fontSize = 16
            _ = height() // Settle parent changes before the child shrinks independently.
            inputs.childSize.height = 40
            XCTAssertEqual(height(), initial, accuracy: 1, "Returning to prior inputs must not retain a tall frame")
        }
    }

    @MainActor func testMountedFlexInvalidatesForLayoutValuesConfigurationAndChildren() {
        let inputs = FlexCacheInputs()
        withFlexHost(inputs, row: true) { height in
            XCTAssertEqual(height(), 40, accuracy: 1)
            inputs.minimumWidth = 250
            XCTAssertEqual(height(), 92, accuracy: 1, "Layout values must change wrapping at the same proposal")
            inputs.gap = 24
            XCTAssertEqual(height(), 104, accuracy: 1, "Layout parameters must invalidate the placement")
            inputs.wrap = false
            XCTAssertEqual(height(), 40, accuracy: 1)
            inputs.wrap = true; inputs.count = 3
            XCTAssertEqual(height(), 168, accuracy: 1)
            inputs.count = 1
            XCTAssertEqual(height(), 40, accuracy: 1, "Removed children must not leave cached frames")
        }
    }

    @MainActor private func withFlexHost(_ inputs: FlexCacheInputs, row: Bool,
                                        check: (() -> CGFloat) -> Void) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: FlexCacheFixture(inputs: inputs, row: row))
        let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 320, height: 1800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        check {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.height
        }
    }
}

@MainActor private final class FlexCacheInputs: ObservableObject {
    @Published var width: CGFloat = 320
    let childSize = FlexCacheChildSize()
    @Published var text = "Short text"
    @Published var fontSize: CGFloat = 16
    @Published var minimumWidth: CGFloat = 100
    @Published var gap: CGFloat = 12
    @Published var wrap = true
    @Published var count = 2
}

@MainActor private final class FlexCacheChildSize: ObservableObject {
    @Published var height: CGFloat = 40
}

private struct FlexCacheFixture: View {
    @ObservedObject var inputs: FlexCacheInputs
    let row: Bool

    var body: some View {
        OpenUIFlexLayout(direction: row ? "row" : "column", gap: inputs.gap,
                         align: "stretch", justify: "start", wrap: inputs.wrap) {
            if row {
                ForEach(0..<inputs.count, id: \.self) { _ in
                    Color.clear.frame(idealWidth: 100).frame(height: 40)
                        .layoutValue(key: OpenUIFlexGrowKey.self, value: true)
                        .layoutValue(key: OpenUIFlexMinimumWidthKey.self, value: inputs.minimumWidth)
                }
            } else {
                FlexCacheSizedChild(size: inputs.childSize)
                Text(inputs.text).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: inputs.width)
        .font(.system(size: inputs.fontSize))
    }
}

private struct FlexCacheSizedChild: View {
    @ObservedObject var size: FlexCacheChildSize
    var body: some View { Color.clear.frame(height: size.height) }
}

#endif
