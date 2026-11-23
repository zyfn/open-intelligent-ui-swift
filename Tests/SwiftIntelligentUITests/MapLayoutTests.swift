import XCTest
import SwiftUI
import SwiftLang
import MapKit
@testable import SwiftIntelligentUI
#if os(macOS)
import AppKit
import ApplicationServices
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

    @MainActor func testMountedNarrowMapReservesTheMeasuredTwoRowControls() async throws {
        _ = NSApplication.shared
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        defer { state.reset() }
        state.setSource(#"root=Map([MapMarker("A",30,120,"A long source category"),MapMarker("B",30.001,120.001,"Another source category")])"#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        let points = MapPoint.decode(context.value("markers"))
        let category = "Another source category"
        let visible = points.filter { $0.category == category }
        let camera = MapCameraState(), routes = MapRouteModel()
        let size = CGSize(width: 320, height: 400)
        let wide = CGSize(width: 760, height: size.height)
        func scene(width: CGFloat) -> some View {
            MapScene(context: context, points: visible,
                categories: MapPoint.categories(in: points), category: category, selection: "", expanded: false,
                infoOpen: false, camera: camera, fitRevision: 0, expansionRevision: 0,
                routeRequest: MapRouteRequest(points: visible, enabled: false), routes: routes,
                onSelect: { _ in false }, onCategory: { _ in }, onOverview: {}, onExpansion: {}, onInfo: {})
                .environment(\.locale, Locale(identifier: "en"))
                .frame(width: width, height: size.height)
        }
        // A nil category only displays the short "All places" label. Select
        // the actual long label; macOS Dynamic Type does not enlarge text.
        let host = NSHostingView(rootView: scene(width: wide.width))
        let window = mount(host, size: wide)
        defer { window.close() }
        try await activateAccessibility(in: host)

        func controls(at expectedSize: CGSize, twoRows: Bool) async throws -> MapControlFrames {
            let deadline = Date().addingTimeInterval(3)
            var previous: MapControlFrames?
            var latest: MapControlFrames?
            var diagnostics = "No accessibility observation yet"
            repeat {
                host.layoutSubtreeIfNeeded()
                let frames = mapControlFrames(in: host, diagnostics: &diagnostics)
                let map = descendants(host).compactMap { $0 as? MKMapView }.first
                if let frames {
                    latest = frames
                    let correctRows = twoRows ? frames.hasTwoRows : frames.hasOneRow
                    // AX frames observe the rendered controls independently of
                    // MapScene's measured-height state. Wait for that height
                    // to reach MapSurface as well, not only for native layout.
                    let insetCoversControls = camera.topInset + 1 >= frames.bounds.height + 24
                    let expectedInset = twoRows ? camera.topInset > 70 : abs(camera.topInset - 70) <= 1
                    if map?.bounds.size == expectedSize, frames.filterValue == category,
                       correctRows, insetCoversControls, expectedInset, frames == previous {
                        return frames
                    }
                    previous = frames
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            } while Date() < deadline
            XCTFail("Map controls did not settle at \(expectedSize), twoRows=\(twoRows), topInset=\(camera.topInset), frames=\(String(describing: latest)), AX=\(diagnostics)")
            return try XCTUnwrap(latest, "The real map controls must be available through accessibility")
        }

        let firstRow = try await controls(at: wide, twoRows: false)
        XCTAssertTrue(firstRow.hasOneRow)
        XCTAssertEqual(firstRow.filterValue, category)
        XCTAssertEqual(camera.topInset, 70, accuracy: 1)
        let map = try XCTUnwrap(descendants(host).compactMap { $0 as? MKMapView }.first)

        host.rootView = scene(width: size.width)
        window.setContentSize(size)
        let wrapped = try await controls(at: size, twoRows: true)
        XCTAssertTrue(wrapped.hasTwoRows, "The selected filter must occupy a second row below the three buttons")
        XCTAssertGreaterThan(wrapped.bounds.height, firstRow.bounds.height)
        XCTAssertEqual(map.bounds.size, size)
        XCTAssertGreaterThan(camera.topInset, 70, "A wrapped toolbar must reserve its measured height instead of a single-row constant")
        XCTAssertGreaterThanOrEqual(camera.topInset + 1, wrapped.bounds.height + 24,
                                    "Camera fitting must leave room for the actual controls and their surrounding padding")
        XCTAssertNotNil(MapCameraGeometry.visibleArea(size: size, top: camera.topInset, bottom: camera.bottomInset,
            left: camera.leftInset, right: camera.rightInset))

        host.rootView = scene(width: wide.width)
        window.setContentSize(wide)
        let restored = try await controls(at: wide, twoRows: false)
        XCTAssertTrue(restored.hasOneRow)
        XCTAssertEqual(map.bounds.size, wide)
        XCTAssertEqual(camera.topInset, 70, accuracy: 1, "The measured inset must shrink again after the controls return to one row")
        XCTAssertTrue(descendants(host).compactMap { $0 as? MKMapView }.first === map)
    }

    private struct MapControlFrames: Equatable {
        let filter: CGRect
        let overview: CGRect
        let info: CGRect
        let expand: CGRect
        let filterValue: String

        var buttons: CGRect { overview.union(info).union(expand) }
        var bounds: CGRect { buttons.union(filter) }
        var buttonsShareRow: Bool {
            abs(overview.midY - info.midY) <= 1 && abs(overview.midY - expand.midY) <= 1
        }
        var hasOneRow: Bool { buttonsShareRow && abs(overview.midY - filter.midY) <= 1 }
        var hasTwoRows: Bool {
            buttonsShareRow && (filter.maxY <= buttons.minY || filter.minY >= buttons.maxY)
        }
    }

    @MainActor private func activateAccessibility(in host: NSView) async throws {
        NSApplication.shared.finishLaunching()
        host.layoutSubtreeIfNeeded()
        // The same-process request enables SwiftUI's lazy virtual AX tree.
        // Run it off the main actor so AppKit can answer without deadlocking.
        let request = await Task.detached {
            let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            var role: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(application, kAXRoleAttribute as CFString, &role)
            return (onMain: Thread.isMainThread, code: error.rawValue, role: role as? String)
        }.value
        guard !request.onMain, request.code == AXError.success.rawValue,
              request.role == kAXApplicationRole as String else {
            throw NSError(domain: "MapLayoutTests", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Could not observe native map controls: onMain=\(request.onMain), code=\(request.code), role=\(String(describing: request.role))"])
        }
    }

    @MainActor private func mapControlFrames(in host: NSView, diagnostics: inout String) -> MapControlFrames? {
        let names = ["intelligent-map-filter", "intelligent-map-overview", "intelligent-map-info", "intelligent-map-expand"]
        var frames: [String: CGRect] = [:]
        var filterValue = ""
        var identifiers = Set<String>()
        var visited = Set<ObjectIdentifier>(), retained: [NSObject] = []
        func attribute(_ name: String, of object: NSObject) -> AnyObject? {
            let selector = NSSelectorFromString(name)
            return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
        }
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 64, visited.count < 2048,
                  visited.insert(ObjectIdentifier(object)).inserted else { return }
            retained.append(object)
            let identifier = attribute("accessibilityIdentifier", of: object) as? String
            if let identifier, identifier.hasPrefix("intelligent-map-") { identifiers.insert(identifier) }
            if let identifier, names.contains(identifier), object.responds(to: NSSelectorFromString("accessibilityFrame")),
               // KVC boxes NSRect as NSValue; perform() is only for object returns.
               let value = object.value(forKey: "accessibilityFrame") as? NSValue {
                let frame = value.rectValue
                if frame.origin.x.isFinite, frame.origin.y.isFinite,
                   frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 {
                    frames[identifier] = frame
                    if identifier == "intelligent-map-filter" {
                        filterValue = attribute("accessibilityValue", of: object) as? String ?? ""
                    }
                }
            }
            for child in attribute("accessibilityChildren", of: object) as? [Any] ?? [] {
                if let child = child as? NSObject { visit(child, depth: depth + 1) }
            }
            if let view = object as? NSView {
                for child in view.subviews { visit(child, depth: depth + 1) }
            }
        }
        visit(host, depth: 0)
        diagnostics = "visited=\(visited.count), identifiers=\(identifiers.sorted()), filterValue=\(filterValue), frames=\(frames)"
        return withExtendedLifetime(retained) {
            guard let filter = frames[names[0]], let overview = frames[names[1]],
                  let info = frames[names[2]], let expand = frames[names[3]] else { return nil }
            return MapControlFrames(filter: filter, overview: overview, info: info, expand: expand, filterValue: filterValue)
        }
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
