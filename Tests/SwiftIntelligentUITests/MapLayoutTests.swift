import XCTest
import SwiftUI
import SwiftLang
import MapKit
@testable import SwiftIntelligentUI
#if os(macOS)
import AppKit
#endif

final class MapLayoutTests: XCTestCase {
    func testInlineHeightMatchesTheOfficialRequestedAndViewportBounds() {
        // 53df45b src/lib/components/map/map.tsx:
        // min(clamp(height ?? 400, 200, 720), max(280, 82vw)).
        XCTAssertEqual(MapMetrics.height(nil, viewportWidth: 1000), 400)
        XCTAssertEqual(MapMetrics.height(160, viewportWidth: 1000), 200)
        XCTAssertEqual(MapMetrics.height(-10, viewportWidth: 1000), 200)
        XCTAssertEqual(MapMetrics.height(1000, viewportWidth: 1000), 720)
        XCTAssertEqual(MapMetrics.height(nil, viewportWidth: 320), 280)
        XCTAssertEqual(MapMetrics.height(160, viewportWidth: 320), 200)
        XCTAssertEqual(MapMetrics.height(270, viewportWidth: 320), 270)
        XCTAssertEqual(MapMetrics.height(720, viewportWidth: 400), 328, accuracy: 0.000001)
        XCTAssertEqual(MapMetrics.height(nil, viewportWidth: 104), 280)
    }

    func testUnknownOrInvalidViewportDoesNotProduceNonfiniteHeight() {
        XCTAssertEqual(MapMetrics.height(nil, viewportWidth: nil), 400)
        XCTAssertEqual(MapMetrics.height(.nan, viewportWidth: 320), 280)
        XCTAssertEqual(MapMetrics.height(.infinity, viewportWidth: 1000), 400)
        for width in [CGFloat(0), -1, .nan, .infinity] {
            XCTAssertEqual(MapMetrics.height(160, viewportWidth: width), 200)
        }
    }

    #if os(macOS)
    @MainActor func testMountedMapUsesOfficialHeightWithoutReservingRoomForCards() throws {
        // Measure the registered Map through the renderer, not just MapMetrics.
        // This catches an extra minimumHeight/frame left in the native path.
        _ = NSApplication.shared
        let library = try OpenIntelligentUIComponents()
        for (width, requested, expectedHeight) in [
            (320.0, 160.0, 200.0), (320.0, 400.0, 280.0),
            (400.0, 720.0, 328.0), (1000.0, 1000.0, 720.0)
        ] {
            let state = library.makeState()
            defer { state.reset() }
            state.setSource("root=Map([MapMarker(\"A\",30,120)],false,null,\(requested))")
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
            let size = CGSize(width: width, height: 900)
            let host = NSHostingView(rootView: OpenIntelligentUIContentView(state: state, library: library)
                .frame(width: size.width, height: size.height, alignment: .topLeading))
            let window = mount(host, size: size)
            defer { window.close() }
            settle(host)
            let map = try XCTUnwrap(descendants(host).compactMap { $0 as? MKMapView }.first)
            XCTAssertEqual(map.bounds.height, CGFloat(expectedHeight), accuracy: 1)
            XCTAssertEqual(map.bounds.width, min(CGFloat(width), OpenIntelligentUITheme().readingWidth), accuracy: 1)
            XCTAssertEqual(map.annotations.filter { !($0 is MKUserLocation) }.count, 1)
        }
    }

    @MainActor func testNestedMapUsesHostViewportForHeightAndItsOwnParentForWidth() throws {
        // The official expression uses vw, not the width of a nested Box.
        _ = NSApplication.shared
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        defer { state.reset() }
        state.setSource(#"root=Box([Map([MapMarker("A",30,120)])],"col",0,0,null,null,false,104)"#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let size = CGSize(width: 900, height: 700)
        let host = NSHostingView(rootView: OpenIntelligentUIContentView(state: state, library: library)
            .frame(width: size.width, height: size.height, alignment: .topLeading))
        let window = mount(host, size: size)
        defer { window.close() }
        settle(host)
        let map = try XCTUnwrap(descendants(host).compactMap { $0 as? MKMapView }.first)
        XCTAssertEqual(map.bounds.width, 104, accuracy: 1)
        XCTAssertEqual(map.bounds.height, 400, accuracy: 1)
    }

    @MainActor func testMountedSceneSynchronizesSelectionAndFilteringWithoutUserCallbacks() throws {
        // 53df45b src/lib/components/map/map.tsx: selected only changes pin
        // appearance; filter/recenter do not select a place or clear the binding.
        _ = NSApplication.shared
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        defer { state.reset() }
        state.setSource("""
        root=Map([MapMarker("A",30,120,"one"),MapMarker("A",30.001,120.001,"one"),MapMarker("B",30.002,120.002,"two")],false,$selected)
        $selected="A"
        """)
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        let points = MapPoint.decode(context.value("markers"))
        let camera = MapCameraState(), routes = MapRouteModel()
        var selectedEvents: [String] = []
        var selectionState = MapSelectionState()
        let size = CGSize(width: 900, height: 640)
        func scene(_ visible: [MapPoint], selected: String, fitRevision: Int = 0) -> AnyView {
            AnyView(MapScene(context: context, points: visible, categories: MapPoint.categories(in: points),
                category: visible.count == points.count ? nil : "two", selection: selected,
                expanded: true, infoOpen: false, camera: camera, fitRevision: fitRevision, expansionRevision: 0,
                routeRequest: MapRouteRequest(points: visible, enabled: false), routes: routes,
                onSelect: { label in
                    selectedEvents.append(label)
                    return selectionState.select(label, in: context, points: visible)
                }, onCategory: { _ in }, onOverview: {}, onExpansion: {}, onInfo: {})
                .environment(\.locale, Locale(identifier: "en"))
                .environment(\.accessibilityReduceMotion, true)
                .frame(width: size.width, height: size.height))
        }
        let host = NSHostingView(rootView: scene(points, selected: "A"))
        let window = mount(host, size: size)
        defer { window.close() }
        settle(host)
        let map = try XCTUnwrap(descendants(host).compactMap { $0 as? MKMapView }.first)
        XCTAssertEqual(map.bounds.size, size, "An expanded map has no place sidebar or card tray")
        XCTAssertEqual(map.annotations.filter { !($0 is MKUserLocation) }.count, 3)
        XCTAssertTrue(map.selectedAnnotations.isEmpty, "Bound selection must not call MapKit selectAnnotation")
        XCTAssertTrue(selectedEvents.isEmpty)
        XCTAssertEqual(state.stateValue("$selected"), .string("A"))

        // Every source pin keeps its visible label, including overlapping pins.
        // Native imagery contains the badge plus the label, not only the badge.
        let badgeHeight = max(32, OpenIntelligentUITheme().minimumControlHeight - 12) + 12
        for annotation in map.annotations where !(annotation is MKUserLocation) {
            let view = try XCTUnwrap(map.view(for: annotation))
            XCTAssertGreaterThan(try XCTUnwrap(view.image).size.height, badgeHeight)
            if annotation.coordinate.latitude < 30.002 {
                XCTAssertTrue((view.accessibilityValue() as? String ?? "").contains(SDKStrings.text("map.selected", locale: Locale(identifier: "en"))))
            }
        }

        state.setState("$selected", value: .string("missing"))
        host.rootView = scene(points, selected: "missing")
        settle(host)
        XCTAssertTrue(selectedEvents.isEmpty)
        XCTAssertEqual(state.stateValue("$selected"), .string("missing"))
        for annotation in map.annotations where !(annotation is MKUserLocation) {
            let view = try XCTUnwrap(map.view(for: annotation))
            XCTAssertFalse((view.accessibilityValue() as? String ?? "").contains(SDKStrings.text("map.selected", locale: Locale(identifier: "en"))))
        }

        state.setState("$selected", value: .string("A"))
        let filtered = points.filter { $0.category == "two" }
        host.rootView = scene(filtered, selected: "A")
        settle(host)
        XCTAssertEqual(map.annotations.filter { !($0 is MKUserLocation) }.count, 1)
        XCTAssertTrue(selectedEvents.isEmpty)
        XCTAssertEqual(state.stateValue("$selected"), .string("A"))
        host.rootView = scene(filtered, selected: "A", fitRevision: 1)
        settle(host)
        XCTAssertTrue(selectedEvents.isEmpty, "An explicit recenter is a camera update")
        XCTAssertEqual(state.stateValue("$selected"), .string("A"))

        host.rootView = scene(points, selected: "A", fitRevision: 1)
        settle(host)
        let annotation = try XCTUnwrap(map.annotations.first { abs($0.coordinate.latitude - 30) < 0.0000001 })
        let view = try XCTUnwrap(map.view(for: annotation))
        let delegate = try XCTUnwrap(map.delegate)
        // Exercise the native delegate's user-selection path twice. Returning
        // true lets NativeMapView close expansion even for the same bound label.
        delegate.mapView?(map, didSelect: view)
        delegate.mapView?(map, didSelect: view)
        XCTAssertEqual(selectedEvents, ["A", "A"], "An already selected pin remains activatable after reopening")
        XCTAssertEqual(state.stateValue("$selected"), .string("A"))
        XCTAssertTrue(map.selectedAnnotations.isEmpty)
    }

    @MainActor func testMountedNarrowMapReservesTheMeasuredTwoRowControls() throws {
        _ = NSApplication.shared
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        defer { state.reset() }
        state.setSource(#"root=Map([MapMarker("A",30,120,"A long source category"),MapMarker("B",30.001,120.001,"Another source category")])"#)
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        let points = MapPoint.decode(context.value("markers"))
        let camera = MapCameraState(), routes = MapRouteModel()
        let size = CGSize(width: 320, height: 400)
        let host = NSHostingView(rootView: MapScene(context: context, points: points,
            categories: MapPoint.categories(in: points), category: nil, selection: "", expanded: false,
            infoOpen: false, camera: camera, fitRevision: 0, expansionRevision: 0,
            routeRequest: MapRouteRequest(points: points, enabled: false), routes: routes,
            onSelect: { _ in false }, onCategory: { _ in }, onOverview: {}, onExpansion: {}, onInfo: {})
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.locale, Locale(identifier: "en"))
            .frame(width: size.width, height: size.height))
        let window = mount(host, size: size)
        defer { window.close() }
        settle(host)
        let map = try XCTUnwrap(descendants(host).compactMap { $0 as? MKMapView }.first)
        XCTAssertEqual(map.bounds.size, size)
        XCTAssertGreaterThan(camera.topInset, 70, "A wrapped toolbar must reserve its measured height instead of a single-row constant")
        XCTAssertNotNil(MapCameraGeometry.visibleArea(size: size, top: camera.topInset, bottom: camera.bottomInset,
            left: camera.leftInset, right: camera.rightInset))
    }

    @MainActor private func mount<V: View>(_ host: NSHostingView<V>, size: CGSize) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        return window
    }

    @MainActor private func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        host.layoutSubtreeIfNeeded()
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    #endif
}
