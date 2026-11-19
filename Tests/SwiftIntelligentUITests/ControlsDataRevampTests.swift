import XCTest
import SwiftUI
import SwiftLang
@testable import SwiftIntelligentUI

final class ControlsDataRevampTests: XCTestCase {
    func testNumericDraftReportsUnappliedValueBeforeLosingFocus() {
        var draft = NumericInputDraft()
        XCTAssertFalse(draft.isPending(current: .number(100)))
        XCTAssertNil(draft.edit("1e"))
        XCTAssertTrue(draft.isPending(current: .number(100)))
        XCTAssertFalse(draft.needsReview, "Editing feedback does not require blur or show an error state")
        XCTAssertEqual(draft.text, "1e")
        XCTAssertEqual(draft.edit("12"), .number(12))
        XCTAssertTrue(draft.isPending(current: .number(100)))
        XCTAssertFalse(draft.isPending(current: .number(12)))
        XCTAssertFalse(draft.needsReview)
        XCTAssertEqual(draft.text, "12", "Checking pending state does not consume or rewrite the draft")
    }

    func testInvalidNumericDraftSurvivesBlurAndExternalValueChange() {
        var draft = NumericInputDraft()
        XCTAssertNil(draft.edit("1e"))
        draft.finish(current: .number(100))
        XCTAssertEqual(draft.text, "1e")
        XCTAssertTrue(draft.needsReview)
        draft.externalValueChanged(to: .number(200))
        XCTAssertEqual(draft.text, "1e")
        XCTAssertNil(draft.parsed)
        draft.discard()
        XCTAssertNil(draft.text)
        XCTAssertFalse(draft.needsReview)
    }

    func testExternalReplacementDoesNotSilentlyDiscardAValidDraft() {
        var draft = NumericInputDraft()
        XCTAssertEqual(draft.edit("12"), .number(12))
        draft.externalValueChanged(to: .number(99))
        draft.finish(current: .number(99))
        XCTAssertEqual(draft.text, "12")
        XCTAssertEqual(draft.parsed, .number(12))
        XCTAssertTrue(draft.needsReview)
        // The user's explicit acceptance can update the existing binding to 12.
        draft.finish(current: .number(12))
        XCTAssertNil(draft.text)
    }

    func testNumericGroupingErrorsNeverBecomeDifferentCommittedNumbers() {
        for input in ["1,2", "1,,2", ",12", "12,", "1 234", "nan", "1e9999"] {
            XCTAssertNil(InputEditing.numericValue(input), input)
        }
        XCTAssertEqual(InputEditing.numericValue("-1,234.50"), .number(-1234.5))
        XCTAssertEqual(InputEditing.numericValue(".5"), .number(0.5))
        XCTAssertEqual(InputEditing.numericValue("1."), .number(1))
        XCTAssertEqual(InputEditing.numericValue("1e2"), .number(100))
        XCTAssertEqual(InputEditing.numericValue("  "), .null)
    }

    func testCalendarProposalDoesNotReplaceAnUnsetOrOutOfRangeValue() throws {
        let minimum = try XCTUnwrap(CalendarDate.parse("2026-11-13"))
        let now = try XCTUnwrap(CalendarDate.parse("2026-11-01"))
        let empty = CalendarDateSelection(raw: "", minimum: "2026-11-13", maximum: "2026-11-20")
        XCTAssertTrue(empty.validRange)
        XCTAssertFalse(empty.validSelection)
        XCTAssertEqual(empty.proposal(now: now), minimum)
        XCTAssertEqual(empty.raw, "")
        let outside = CalendarDateSelection(raw: "2026-11-10", minimum: "2026-11-13", maximum: nil)
        XCTAssertFalse(outside.validSelection)
        XCTAssertNotNil(outside.message)
        XCTAssertEqual(outside.proposal(now: now), minimum)
        XCTAssertEqual(outside.raw, "2026-11-10")
        XCTAssertEqual(outside.date.map(CalendarDate.string), "2026-11-10")
        XCTAssertFalse(CalendarDateSelection(raw: "2026-11-13", minimum: "2026-11-20", maximum: "2026-11-10").validRange)
    }

    func testCalendarProposalPreservesAnExistingDayAndInclusiveBounds() throws {
        let now = try XCTUnwrap(CalendarDate.parse("2026-12-01"))
        for day in ["2026-11-13", "2026-11-15", "2026-11-20"] {
            let selection = CalendarDateSelection(raw: day, minimum: "2026-11-13", maximum: "2026-11-20")
            XCTAssertTrue(selection.validSelection)
            XCTAssertNil(selection.message)
            XCTAssertEqual(CalendarDate.string(selection.proposal(now: now)), day,
                           "Reopening the field starts at its current day, including either bound")
            XCTAssertEqual(selection.raw, day, "A proposal must not commit a replacement value")
        }
        let empty = CalendarDateSelection(raw: "", minimum: "2026-11-13", maximum: "2026-11-20")
        XCTAssertEqual(CalendarDate.string(empty.proposal(now: now)), "2026-11-20")
        XCTAssertEqual(empty.raw, "")
        let invalid = CalendarDateSelection(raw: "2026-02-30", minimum: "2026-11-13", maximum: "2026-11-20")
        XCTAssertEqual(CalendarDate.string(invalid.proposal(now: now)), "2026-11-20")
        XCTAssertEqual(invalid.raw, "2026-02-30")
        XCTAssertEqual(invalid.message, "controls.date.invalid_format")
    }

    func testCalendarProposalKeepsTheUTCDayAcrossLocalMidnight() throws {
        let utcDay = try XCTUnwrap(CalendarDate.parse("2026-11-15"))
        let nearUTCMidnight = utcDay.addingTimeInterval(30 * 60)
        let local = DateFormatter()
        local.calendar = Calendar(identifier: .gregorian)
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone(secondsFromGMT: -8 * 60 * 60)
        local.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(local.string(from: nearUTCMidnight), "2026-11-14")
        let selection = CalendarDateSelection(raw: "", minimum: nil, maximum: nil)
        XCTAssertEqual(selection.proposal(now: nearUTCMidnight), utcDay)
        XCTAssertEqual(CalendarDate.string(nearUTCMidnight), "2026-11-15")
        XCTAssertEqual(selection.raw, "")
    }

    func testCalendarDisplayLocalizesWithoutChangingTheUTCDay() throws {
        let day = try XCTUnwrap(CalendarDate.parse("2026-11-15"))
        for instant in [day, day.addingTimeInterval(23.5 * 60 * 60)] {
            XCTAssertEqual(CalendarDate.display(instant, locale: Locale(identifier: "en_US")), "Nov 15, 2026")
            XCTAssertEqual(CalendarDate.display(instant, locale: Locale(identifier: "zh_CN")), "2026年11月15日")
            XCTAssertEqual(CalendarDate.string(instant), "2026-11-15", "Localized labels do not change the stored format")
        }
    }

    @MainActor func testEnglishDateFieldKeepsItsSurfaceHeightAndValueAfterSelection() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource("""
        root = DatePicker($date,"Departure","2026-11-13","2026-11-20")
        $date = ""
        """)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let binding = try XCTUnwrap(state.binding(for: try XCTUnwrap(state.root), prop: "value"))
        func height(at textSize: DynamicTypeSize) throws -> Double {
            let original = state.stateValue("$date")
            let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.dynamicTypeSize, textSize).frame(width: 320))
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(state.stateValue("$date"), original, "Displaying a date must never commit its proposal")
            return Double(image.height)
        }
        for textSize in [DynamicTypeSize.large, .accessibility2] {
            // This short English fixture fits on one line at 320 points.
            // Other locales and longer labels may grow naturally with Dynamic Type.
            binding.wrappedValue = .string("")
            let emptyHeight = try height(at: textSize)
            binding.wrappedValue = .string("2026-11-15")
            XCTAssertEqual(try height(at: textSize), emptyHeight, accuracy: 1,
                           "Selecting a date must keep the label, field surface and control height")
            XCTAssertEqual(state.stateValue("$date"), .string("2026-11-15"))
        }
    }

    func testDenseSliderMarksUseNonOverlappingLanes() {
        let frames = SliderMarkGeometry.frames(width: 320, sizes: Array(repeating: CGSize(width: 180, height: 40), count: 3),
                                              positions: [0.48, 0.5, 0.52], rightToLeft: false, gap: 8)
        XCTAssertEqual(frames.count, 3)
        for i in frames.indices {
            XCTAssertGreaterThanOrEqual(frames[i].minX, 0)
            XCTAssertLessThanOrEqual(frames[i].maxX, 320)
            for j in frames.indices where j > i { XCTAssertFalse(frames[i].intersects(frames[j])) }
        }
    }

    func testSliderMarkPositionsMirrorWithoutChangingTheirValues() {
        let sizes = [CGSize(width: 40, height: 20), CGSize(width: 40, height: 20)]
        let left = SliderMarkGeometry.frames(width: 320, sizes: sizes, positions: [0.2, 0.8], rightToLeft: false, gap: 8)
        let right = SliderMarkGeometry.frames(width: 320, sizes: sizes, positions: [0.2, 0.8], rightToLeft: true, gap: 8)
        XCTAssertEqual(left[0].minX, 320 - right[0].maxX, accuracy: 0.001)
        XCTAssertEqual(left[1].minX, 320 - right[1].maxX, accuracy: 0.001)
    }

    func testChartInspectionPreservesRepresentableSmallAndPreciseNumbers() {
        let locale = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(ChartData.formatted(0.004, locale: locale), "0.004")
        XCTAssertEqual(ChartData.formatted(1.23456, locale: locale), "1.23456")
        XCTAssertEqual(ChartData.formatted(0.004, kind: "percent", locale: locale), "0.004%")
    }

    func testChartMissingCategoryKeepsDomainAndBreaksOnlyItsSeries() {
        let rows: Value = .array([
            .object([.init(key: "x", value: .string("A")), .init(key: "v", value: .number(10)), .init(key: "w", value: .number(1))]),
            .object([.init(key: "x", value: .string("B")), .init(key: "v", value: .null), .init(key: "w", value: .number(2))]),
            .object([.init(key: "x", value: .string("C")), .init(key: "v", value: .number(30)), .init(key: "w", value: .number(3))])
        ])
        let data = ChartData(rows: rows, x: "x", series: .array([.string("v"), .string("w")]))
        XCTAssertEqual(data.labels, ["A", "B", "C"])
        XCTAssertEqual(data.omitted, 1)
        XCTAssertEqual(data.entries.count, 6)
        XCTAssertNil(data.entries.first { $0.label == "B" && $0.series == "v" }?.value)
        XCTAssertEqual(data.points.filter { $0.series == "v" }.map(\.segment), [0, 1])
        XCTAssertEqual(data.points.filter { $0.series == "w" }.map(\.segment), [0, 0, 0])
    }

    func testPieSelectionDistinguishesDuplicateCategoryLabels() {
        let points = [ChartData.Point(id: "first", label: "同名", x: nil, series: "v", value: 1),
                      ChartData.Point(id: "second", label: "同名", x: nil, series: "v", value: 1)]
        XCTAssertEqual(ChartInspection.sectorPoint(at: .init(x: 90, y: 50), size: .init(width: 100, height: 100), points: points, donut: false)?.id, "first")
        XCTAssertEqual(ChartInspection.sectorPoint(at: .init(x: 10, y: 50), size: .init(width: 100, height: 100), points: points, donut: false)?.id, "second")
    }

    func testPriceCurrencyRemainsDistinctWithoutChangingStoredAmount() {
        let cny = PricePresentation(.object([.init(key: "price", value: .number(0)), .init(key: "currency", value: .string("CNY"))]))
        let jpy = PricePresentation(.object([.init(key: "price", value: .number(0)), .init(key: "currency", value: .string("JPY"))]))
        XCTAssertEqual(cny.text, "¥0")
        XCTAssertEqual(jpy.text, "¥0")
        XCTAssertEqual(cny.displayText, "CNY ¥0")
        XCTAssertEqual(jpy.displayText, "JPY ¥0")
        let padded = PricePresentation(.object([.init(key: "price", value: .number(1299)), .init(key: "currency", value: .string(" CNY "))]))
        XCTAssertEqual(padded.text, "¥1299")
        XCTAssertEqual(padded.displayText, "CNY ¥1299")
        XCTAssertTrue(padded.diagnostics.isEmpty)
    }

    func testPriceReaderPreservesOddGroupingAndConflictsWithDiagnostics() {
        XCTAssertTrue(PricePresentation.valid(.string("1,2")), "Historical reader remains compatible")
        let odd = PricePresentation(.object([.init(key: "price", value: .string("1,2"))]))
        XCTAssertEqual(odd.text, "1,2")
        XCTAssertFalse(odd.diagnostics.isEmpty)
        let conflict = PricePresentation(.object([.init(key: "price", value: .string("JPY 100")), .init(key: "currency", value: .string("CNY"))]))
        XCTAssertEqual(conflict.text, "JPY 100")
        XCTAssertEqual(conflict.displayText, "JPY 100")
        XCTAssertFalse(conflict.diagnostics.isEmpty)
        XCTAssertTrue(PricePresentation.hasCanonicalGrouping("HK$1,234.50"))
        XCTAssertFalse(PricePresentation.hasCanonicalGrouping("1,,2"))
    }

    func testProductOwnsAllItsPhotosForEveryLayout() throws {
        let product = try XCTUnwrap(ProductCardData(.object([
            .init(key: "id", value: .string("product")), .init(key: "title", value: .string("商品")),
            .init(key: "images", value: .array([
                .object([.init(key: "url", value: .string("/front")), .init(key: "alt", value: .string("正面"))]),
                .object([.init(key: "url", value: .string("/back")), .init(key: "alt", value: .string("背面"))])
            ]))
        ])))
        XCTAssertEqual(product.imageAlbum.map(\.source), ["/front", "/back"])
        XCTAssertEqual(product.imageAlbum.map(\.alt), ["正面", "背面"])
    }

    func testTableMissingMarkerDoesNotChangeNumericAlignmentOrRowIdentity() {
        let identities = TableRowIdentities()
        let original = TableData(columns: .array([.string("金额")]), rows: .array([.array([.number(12)])]), identity: identities.id)
        let updated = TableData(columns: .array([.string("金额")]), rows: .array([.array([.number(12)]), .array([.string("N/A")])]), identity: identities.id)
        XCTAssertTrue(updated.columns[0].numeric)
        XCTAssertEqual(original.rows[0].id, updated.rows[0].id)
        XCTAssertEqual(updated.rows[1].cells[0], .string("N/A"))
    }

    func testTimerAcceptsLargeSourceValueWithoutHiddenClamping() {
        XCTAssertEqual(TimerReading.seconds(.number(40_000_000)), 40_000_000)
        XCTAssertEqual(TimerReading.display(40_000_000), "11111:06:40")
        XCTAssertEqual(TimerReading.display(0.5), "00:00:00.5")
        XCTAssertEqual(TimerReading.elapsed(.milliseconds(250)), 0.25, accuracy: 0.000001)
        XCTAssertNil(TimerReading.seconds(.number(-1)))
    }

    func testProgressDistinguishesUnknownFromInvalidConfiguration() {
        XCTAssertEqual(ProgressReading.state(value: nil, maximum: nil), .indeterminate)
        XCTAssertEqual(ProgressReading.state(value: .number(0), maximum: .number(10)), .determinate(0))
        XCTAssertEqual(ProgressReading.state(value: .number(20), maximum: .number(10)), .determinate(1))
        XCTAssertEqual(ProgressReading.state(value: .number(1), maximum: .number(0)), .invalid)
        XCTAssertEqual(ProgressReading.state(value: .null, maximum: nil), .invalid)
        XCTAssertEqual(ProgressReading.state(value: .number(-1), maximum: .number(10)), .invalid)
        XCTAssertEqual(ProgressReading.state(value: nil, maximum: .number(-1)), .invalid)
    }
}
