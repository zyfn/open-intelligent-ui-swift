import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI
#if os(macOS)
import AppKit
#endif

final class ReadingControlPresentationTests: XCTestCase {
    @MainActor func testFieldHintsFollowParsedRulesAndSelectionMode() throws {
        let library = try OpenUIComponents.library()
        let cases: [(String, Bool, String?)] = [
            ("root=Input(\"email\",null,\"email\",{required:true,email:true})", true, nil),
            ("root=Input(\"email\",null,\"email\",{required:false,email:true})", false, nil),
            ("root=OptionCards(\"choice\",\"multiple\",[OptionCard(\"a\",\"A\")])", false, "Select one or more"),
            ("root=OptionCards(\"choice\",\"single\",[OptionCard(\"a\",\"A\")])", false, nil),
            ("root=SwitchGroup(\"settings\",[SwitchItem(\"Updates\",null,\"updates\",true)])", false, nil),
        ]
        for (source, required, hint) in cases {
            let state = OpenUIState(schema: library.library.toSchema())
            state.setSource(source)
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
            let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.registry, state: state)
            let field = NativeFieldState(context: context)
            XCTAssertEqual(field.isRequired, required, source)
            XCTAssertEqual(field.selectionHint, hint, source)
        }
    }

    @MainActor func testReturnKeyOrderUsesMountedFieldsAndReplacementOwners() {
        let validation = NativeFormValidation()
        validation.setDeclarations(["first", "second", "last"].map {
            (OpenUIString($0), NativeFormValidation.Field(rules: [], value: { .string("valid") }))
        })
        let first = UUID(), second = UUID(), last = UUID()
        // Mount order can differ from source order. The second field is not
        // registered as focusable while it is disabled or in a hidden panel.
        for (name, owner) in [("last", last), ("second", second), ("first", first)] {
            validation.register(OpenUIString(name), owner: owner, rules: [], value: { .string("valid") })
        }
        validation.registerFocusableField("last", owner: last)
        validation.registerFocusableField("first", owner: first)
        XCTAssertEqual(validation.focusableFields, ["first", "last"])
        XCTAssertEqual(validation.nextFocusableField(after: "first"), "last")
        XCTAssertTrue(validation.requestNextFieldFocus(after: "first"))
        XCTAssertEqual(validation.focusRequest?.name, "last")
        XCTAssertFalse(validation.requestNextFieldFocus(after: "last"))

        let replacement = UUID()
        validation.register("second", owner: replacement, rules: [], value: { .string("valid") })
        validation.registerFocusableField("second", owner: replacement)
        validation.unregister("second", owner: second)
        validation.unregisterFocusableField("second", owner: second)
        XCTAssertEqual(validation.focusableFields, ["first", "second", "last"])
        XCTAssertEqual(validation.nextFocusableField(after: "first"), "second")
        validation.unregisterFocusableField("second", owner: replacement)
        XCTAssertEqual(validation.nextFocusableField(after: "first"), "last")
        XCTAssertTrue(validation.validateAll(), "Keyboard navigation does not alter validation or field values")
    }

    @MainActor func testRemovingAKeyboardTargetKeepsDeclaredValidation() {
        let validation = NativeFormValidation()
        let owner = UUID()
        let rules = [ParsedRule(type: "required")]
        validation.setDeclarations([("email", .init(rules: rules, value: { .string("") }))])
        validation.register("email", owner: owner, rules: rules, value: { .string("") })
        validation.registerFocusableField("email", owner: owner)
        validation.unregister("email", owner: owner)
        XCTAssertTrue(validation.focusableFields.isEmpty)
        XCTAssertFalse(validation.validateAll())
        XCTAssertNotNil(validation.errors["email"])
        validation.requestInvalidFieldFocus()
        XCTAssertEqual(validation.focusRequest?.name, "email", "A hidden invalid field must still be revealable by Tabs")
    }

    func testTabLabelBoundLeavesRoomForItsOwnPadding() {
        let label = NativeTabsLayout.maximumLabelWidth(viewportWidth: 200, horizontalPadding: 12)
        XCTAssertEqual(label + 24, 200)
        XCTAssertEqual(NativeTabsLayout.maximumLabelWidth(viewportWidth: 600, horizontalPadding: 12), 232)
        XCTAssertGreaterThan(NativeTabsLayout.maximumLabelWidth(viewportWidth: 10, horizontalPadding: 12), 0)
    }

    func testRangeEditingAndSummaryKeepBothDatesVisible() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let locale = Locale(identifier: "en_US")
        let start = try XCTUnwrap(NativeCalendarDate.parse(.string("2026-11-10"), timeZone: zone))
        let end = try XCTUnwrap(NativeCalendarDate.parse(.string("2026-11-20"), timeZone: zone))
        let partial = NativeCalendarDate.setting(start, part: .from, in: .null, calendar: calendar, timeZone: zone)
        XCTAssertTrue(NativeCalendarDate.hasRangeSelection(partial, timeZone: zone),
                      "Clear range remains available when the other endpoint is empty")
        XCTAssertNil(NativeCalendarDate.rangeSummary(partial, locale: locale, calendar: calendar, timeZone: zone))
        let complete = NativeCalendarDate.setting(end, part: .to, in: partial, calendar: calendar, timeZone: zone)
        let summary = try XCTUnwrap(NativeCalendarDate.rangeSummary(complete, locale: locale, calendar: calendar, timeZone: zone))
        XCTAssertTrue(summary.contains("10"))
        XCTAssertTrue(summary.contains("20"))
        let earlier = try XCTUnwrap(NativeCalendarDate.parse(.string("2026-11-05"), timeZone: zone))
        let clamped = NativeCalendarDate.setting(earlier, part: .to, in: complete, calendar: calendar, timeZone: zone)
        guard case .object(let values) = clamped else { return XCTFail("Expected a range") }
        XCTAssertEqual(values["from"], NativeCalendarDate.encode(earlier))
        XCTAssertEqual(values["to"], NativeCalendarDate.encode(earlier))
        XCTAssertFalse(NativeCalendarDate.hasRangeSelection(.null, timeZone: zone))
        XCTAssertNil(NativeCalendarDate.rangeSummary(.null, locale: locale, calendar: calendar, timeZone: zone))
    }

    func testRangeEndpointLabelsDistinguishMinimumFromMaximum() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(NativeSliderEndpointText.label(field: "Budget", index: 0, count: 2, locale: locale), "Budget, Minimum")
        XCTAssertEqual(NativeSliderEndpointText.label(field: "Budget", index: 1, count: 2, locale: locale), "Budget, Maximum")
        XCTAssertEqual(NativeSliderEndpointText.label(field: "Budget", index: 0, count: 1, locale: locale), "Budget")
    }

    #if os(macOS)
    @MainActor func testRangeEndpointsStackWhenTheirReadingSpaceDoesNotFit() {
        _ = NSApplication.shared
        func height(width: CGFloat, force: Bool = false) -> CGFloat {
            NSHostingView(rootView: NativeSliderEndpointsLayout(minimumWidth: 88, gap: 8, forceVertical: force) {
                Color.clear.frame(height: 40)
                Color.clear.frame(height: 60)
            }.frame(width: width)).fittingSize.height
        }
        XCTAssertEqual(height(width: 320), 60, accuracy: 1)
        XCTAssertEqual(height(width: 180), 108, accuracy: 1)
        XCTAssertEqual(height(width: 320, force: true), 108, accuracy: 1)
    }

    @MainActor func testRangeEndpointPlacementUsesSwiftUIMirroring() throws {
        _ = NSApplication.shared
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            for width in [CGFloat(320), CGFloat(180)] {
                let host = NSHostingView(rootView:
                    NativeSliderEndpointsLayout(minimumWidth: 88, gap: 8) {
                        Color.clear.frame(height: 40).background(ReadingEndpointMarker(name: "minimum"))
                        Color.clear.frame(height: 60).background(ReadingEndpointMarker(name: "maximum"))
                    }
                    .environment(\.layoutDirection, direction)
                    .frame(width: width)
                )
                let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 120),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.setFrameOrigin(.init(x: -10000, y: -10000))
                window.orderFront(nil)
                defer { window.close() }
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                host.layoutSubtreeIfNeeded()
                func marker(_ name: String, in view: NSView) -> NSView? {
                    if view.identifier?.rawValue == name { return view }
                    return view.subviews.lazy.compactMap { marker(name, in: $0) }.first
                }
                let minimumView = try XCTUnwrap(marker("minimum", in: host))
                let maximumView = try XCTUnwrap(marker("maximum", in: host))
                let minimum = minimumView.convert(minimumView.bounds, to: host)
                let maximum = maximumView.convert(maximumView.bounds, to: host)
                for frame in [minimum, maximum] {
                    XCTAssertGreaterThanOrEqual(frame.minX, -1)
                    XCTAssertLessThanOrEqual(frame.maxX, width + 1)
                }
                if width == 320 {
                    if direction == .leftToRight { XCTAssertLessThan(minimum.midX, maximum.midX) }
                    else { XCTAssertGreaterThan(minimum.midX, maximum.midX) }
                } else {
                    XCTAssertEqual(minimum.midX, maximum.midX, accuracy: 1)
                    if host.isFlipped { XCTAssertLessThan(minimum.midY, maximum.midY) }
                    else { XCTAssertGreaterThan(minimum.midY, maximum.midY) }
                }
            }
        }
    }

    @MainActor func testChoiceDefaultAndHostOverrideKeepWidthDrivenColumns() {
        _ = NSApplication.shared
        func height(width: CGFloat, minimum: CGFloat, secondHeight: CGFloat = 40, single: Bool = false) -> CGFloat {
            NSHostingView(rootView: NativeChoiceCardsLayout(minimumWidth: minimum, gap: 12, singleColumn: single) {
                Color.clear.frame(height: 40)
                Color.clear.frame(height: secondHeight)
                Color.clear.frame(height: 60)
            }.frame(width: width)).fittingSize.height
        }
        let minimum = OpenUIPresentation().minimumChoiceWidth
        XCTAssertEqual(height(width: 318, minimum: minimum), 112, accuracy: 1)
        XCTAssertEqual(height(width: 398, minimum: minimum), 112, accuracy: 1)
        XCTAssertEqual(height(width: 412, minimum: minimum), 112, accuracy: 1)
        XCTAssertEqual(height(width: 432, minimum: minimum), 60, accuracy: 1)
        XCTAssertEqual(height(width: 412, minimum: minimum, secondHeight: 200), 272, accuracy: 1)
        XCTAssertEqual(height(width: 318, minimum: 200), 164, accuracy: 1, "Hosts may request wider choices without changing content")
        XCTAssertEqual(height(width: 800, minimum: minimum, single: true), 164, accuracy: 1)
    }

    @MainActor func testMountedInputFocusOrderTracksDisabledControls() throws {
        _ = NSApplication.shared
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        state.setSource("root=Stack([Input(\"first\"),Input(\"second\"),Input(\"last\")])")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let inputs = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertEqual(inputs.count, 3)
        let contexts = inputs.map { OpenUIComponentContext(element: $0, registry: library.registry, state: state, formName: "focus") }
        let validation = NativeFormValidation()
        validation.setFieldOrder(["first", "second", "last"])
        func content(secondDisabled: Bool) -> some View {
            VStack {
                OpenUINativeField(context: contexts[0], kind: .input)
                OpenUINativeField(context: contexts[1], kind: .input).disabled(secondDisabled)
                OpenUINativeField(context: contexts[2], kind: .input)
            }.environmentObject(state).environment(\.openUIFormValidation, validation).frame(width: 320)
        }
        let host = NSHostingView(rootView: content(secondDisabled: true))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(.init(x: -10000, y: -10000))
        window.orderFront(nil)
        defer { window.close() }
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
        }
        settle()
        XCTAssertEqual(validation.focusableFields, ["first", "last"])
        host.rootView = content(secondDisabled: false)
        settle()
        XCTAssertEqual(validation.focusableFields, ["first", "second", "last"])
        host.rootView = content(secondDisabled: true)
        settle()
        XCTAssertEqual(validation.focusableFields, ["first", "last"])
    }
    #endif
}

#if os(macOS)
private struct ReadingEndpointMarker: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(name)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
#endif
