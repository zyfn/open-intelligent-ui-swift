import SwiftUI
import MapKit
import SwiftLang

private enum MapMetrics {
    static let inlineHeight: CGFloat = 400
    static let minimumHeight: CGFloat = 300
    static let maximumHeight: CGFloat = 400
    static let labelWidth: CGFloat = 140
}

enum MapMarkerComponent {
    static var component: OpenUIComponent {
        var lat = Parameter.number("lat", minimum: -90, maximum: 90); lat.required = true
        var lng = Parameter.number("lng", minimum: -180, maximum: 180); lng.required = true
        return OpenUIComponent(name: "MapMarker", description: "A named coordinate with optional category and one emoji icon. Without an emoji the pin shows its sequence number.", params: [OpenUIParameter.string("label"), lat, lng, OpenUIParameter.string("category", required: false), OpenUIParameter.string("icon", required: false)]) { MapMarkerView(context: $0) }
    }
}

private struct MapMarkerView: View {
    let context: OpenUIComponentContext
    @Environment(\.locale) private var locale
    var body: some View { Label(context.string("label") ?? SDKStrings.text("map.place", locale: locale), systemImage: "mappin") }
}

enum MapComponent {
    static var component: OpenUIComponent {
        var selected = OpenUIParameter.selection("selected", required: false); selected.isBindable = true
        return OpenUIComponent(name: "Map", description: "Street map with internal category filtering, selectable place cards and native expanded view. selected holds the clicked marker label; empty means overview. Marker/card selection stays synchronized across expansion. route draws a schematic line in marker order, not road directions. No user location or invented coordinates.", params: [
            OpenUIParameter.slot("markers", required: true, accepting: ["MapMarker"]), OpenUIParameter.flag("route"), selected,
            Parameter.number("height", minimum: 160, maximum: 800)
        ]) { NativeMapView(context: $0) }
    }
}

private struct NativeMapView: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openIntelligentUIMapContentInsets) private var contentInsets
    @Environment(\.layoutDirection) private var direction
    @State private var localSelection = ""
    @State private var cameraState = MapCameraState()
    @State private var expandedCameraState = MapCameraState()
    @State private var category: String?
    @State private var fitRevision = 0
    @State private var expanded = false
    @State private var trayHeight: CGFloat = 100
    @State private var expandedTrayHeight: CGFloat = 100

    private var allPoints: [MapPoint] { MapPoint.decode(context.value("markers")) }
    private var categories: [String] { Array(Set(allPoints.map(\.category).filter { !$0.isEmpty })).sorted() }
    private var points: [MapPoint] { allPoints.filter { category == nil || $0.category == category } }
    private var selection: String {
        MapPoint.validSelection(ValueReading.boundString(context, "selected") ?? localSelection, in: points)
    }
    private var height: CGFloat {
        let minimum: CGFloat = typeSize.isAccessibilitySize ? 440 : MapMetrics.minimumHeight
        return min(800, max(minimum, CGFloat(context.number("height") ?? Double(MapMetrics.inlineHeight)), trayHeight + 200))
    }

    var body: some View {
        Group {
            if allPoints.isEmpty {
                mapEmpty
            } else {
                scene(expanded: false)
                    .frame(height: height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
        #if os(iOS)
        .fullScreenCover(isPresented: $expanded) { scene(expanded: true).background(theme.canvas) }
        #else
        .sheet(isPresented: $expanded) {
            scene(expanded: true)
                .frame(minWidth: 640, idealWidth: 880, minHeight: 600, idealHeight: 760)
                .background(theme.canvas)
        }
        #endif
        .onAppear(perform: reconcileSelection)
        .onChange(of: points.map(\.id)) { _ in reconcileSelection() }
        .onChange(of: categories) { items in
            if let category, !items.contains(category) { self.category = nil }
        }
        .onChange(of: context.canInteract) { ready in if ready { reconcileSelection() } }
    }

    private var mapEmpty: some View {
        VStack(spacing: theme.innerSpacing) {
            Image(systemName: "map").font(.title2).foregroundStyle(theme.secondaryText)
            Text(SDKStrings.text(context.element.isSourceComplete ? "map.no_coordinates" : "map.preparing", locale: locale))
                .font(theme.secondaryFont).foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity).frame(height: height).background(theme.surface)
    }

    private func scene(expanded isExpanded: Bool) -> some View {
        let camera = isExpanded ? expandedCameraState : cameraState
        let bottom = isExpanded ? expandedTrayHeight : trayHeight
        return GeometryReader { geometry in
            ZStack {
                MapSurface(points: points, route: context.flag("route") == true, selected: selection,
                           allowsPan: true,
                           focusOnSelection: !selection.isEmpty && camera.previousSelection != selection,
                           cameraState: camera,
                           bottomInset: bottom + theme.innerSpacing * 2 + (contentInsets?.bottom ?? 0),
                           topInset: max(64, theme.minimumControlHeight + theme.innerSpacing * 2) + (contentInsets?.top ?? 0),
                           leftInset: (direction == .rightToLeft ? contentInsets?.trailing : contentInsets?.leading) ?? 0,
                           rightInset: (direction == .rightToLeft ? contentInsets?.leading : contentInsets?.trailing) ?? 0,
                           reduceMotion: reduceMotion, fitRevision: fitRevision, displayScale: displayScale,
                           font: theme.labelFont, captionFont: theme.captionFont, targetHeight: theme.minimumControlHeight,
                           typeSize: typeSize, colorScheme: colorScheme, onSelect: select)
                    .allowsHitTesting(context.canInteract)
                VStack(spacing: 0) {
                    controls(expanded: isExpanded)
                    Spacer(minLength: 8)
                    placeCards(width: geometry.size.width)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { value in
                            guard value.isFinite, value > 0 else { return }
                            if isExpanded {
                                if abs(value - expandedTrayHeight) > 1 { expandedTrayHeight = value }
                            } else if abs(value - trayHeight) > 1 { trayHeight = value }
                        }
                }
            }
        }
        .accessibilityIdentifier(isExpanded ? "intelligent-map-expanded" : "intelligent-map-inline")
    }

    private func controls(expanded isExpanded: Bool) -> some View {
        HStack(spacing: theme.innerSpacing) {
            if !categories.isEmpty { filterMenu() }
            else {
                Text(SDKStrings.text("map.place_count", locale: locale, points.count))
                    .font(theme.secondaryFont.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
            Spacer(minLength: 8)
            mapButton(SDKStrings.text("map.overview", locale: locale), symbol: "scope") {
                select("")
                fitRevision += 1
            }
            if isExpanded {
                mapButton(SDKStrings.text("map.close", locale: locale), symbol: "xmark") { expanded = false }
            } else {
                mapButton(SDKStrings.text("map.expand", locale: locale), symbol: "arrow.up.left.and.arrow.down.right") { expanded = true }
            }
        }
        .padding(theme.innerSpacing)
    }

    private func placeCards(width: CGFloat) -> some View {
        let cardWidth = max(120, min(typeSize.isAccessibilitySize ? width : 260, width - theme.innerSpacing * 2))
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: theme.innerSpacing) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        Button { select(point.id) } label: {
                            HStack(alignment: .center, spacing: theme.innerSpacing) {
                                Text(MapPoint.displayIcon(point.icon) ?? String(index + 1))
                                    .font(theme.labelFont).frame(width: 32, height: 32)
                                    .background(theme.surface, in: Circle())
                                VStack(alignment: .leading, spacing: theme.spacingUnit) {
                                    if !point.category.isEmpty {
                                        Text(point.category).font(theme.captionFont).foregroundStyle(theme.secondaryText)
                                    }
                                    Text(point.label).font(theme.labelFont).foregroundStyle(theme.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                if selection == point.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.primaryText)
                                }
                            }
                            .padding(12)
                            .frame(width: cardWidth, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: theme.controlRadius + 4))
                            .overlay(RoundedRectangle(cornerRadius: theme.controlRadius + 4)
                                .strokeBorder(selection == point.id ? theme.primaryText : theme.fieldBorder,
                                              lineWidth: selection == point.id ? 1.5 : 0.5))
                            .contentShape(RoundedRectangle(cornerRadius: theme.controlRadius + 4))
                        }
                        .buttonStyle(.plain)
                        .disabled(!context.canInteract)
                        .accessibilityLabel(point.label)
                        .accessibilityValue(selection == point.id ? SDKStrings.text("map.selected", locale: locale) : point.category)
                        .accessibilityIdentifier("intelligent-map-place-" + point.id)
                        .id(point.id)
                    }
                }
                .padding(.horizontal, theme.innerSpacing)
                .padding(.vertical, theme.innerSpacing)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { id in
                guard !id.isEmpty else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .leading) }
            }
            .onChange(of: category) { _ in
                if let first = points.first { proxy.scrollTo(first.id, anchor: .leading) }
            }
        }
    }

    private func select(_ id: String) {
        guard context.canInteract else { return }
        if let binding = context.binding("selected") {
            if ValueReading.string(binding.wrappedValue) != id { binding.wrappedValue = .string(OpenUIString(id)) }
        } else { localSelection = id }
    }

    private func reconcileSelection() {
        guard context.canInteract else { return }
        let requested = ValueReading.boundString(context, "selected") ?? localSelection
        if MapPoint.validSelection(requested, in: points) != requested { select("") }
    }

    private func filterMenu() -> some View {
        Menu {
            Button(SDKStrings.text("map.all_places", locale: locale)) { changeCategory(nil) }
            ForEach(categories, id: \.self) { item in
                Button(item) { changeCategory(item) }
            }
        } label: {
            HStack(spacing: theme.innerSpacing) {
                Text(category ?? SDKStrings.text("map.all_places", locale: locale)).font(theme.secondaryFont).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: max(36, theme.minimumControlHeight))
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.fieldBorder, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .foregroundStyle(theme.primaryText)
        .disabled(!context.canInteract)
        .accessibilityLabel(SDKStrings.text("map.filter_category", locale: locale))
    }

    private func changeCategory(_ value: String?) {
        category = value
        select("")
        fitRevision += 1
    }

    private func mapButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(theme.secondaryFont.weight(.medium))
                .frame(minWidth: max(36, theme.minimumControlHeight), minHeight: max(36, theme.minimumControlHeight))
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(theme.fieldBorder, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(theme.primaryText)
        .accessibilityLabel(label).disabled(!context.canInteract)
    }
}

struct MapPoint: Equatable {
    let id: String
    let label: String
    let latitude: Double
    let longitude: Double
    let category: String
    let icon: String
    static func validSelection(_ requested: String, in points: [MapPoint]) -> String {
        points.contains(where: { $0.id == requested }) ? requested : ""
    }
    struct Geometry: Equatable {
        let id: String
        let latitude: Double
        let longitude: Double
        init(_ point: MapPoint) { id = point.id; latitude = point.latitude; longitude = point.longitude }
    }
    static func displayIcon(_ value: String) -> String? {
        guard value.count == 1, value.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value == 0x20E3 }) else { return nil }
        return value
    }
    static func decode(_ value: Value?) -> [Self] {
        var labels = Set<String>()
        return ValueReading.array(value).compactMap { item in
            let label = ValueReading.string(ValueReading.field(item, "label"))
            guard !label.isEmpty, let lat = ValueReading.number(ValueReading.field(item, "lat")), let lng = ValueReading.number(ValueReading.field(item, "lng")), (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
            guard labels.insert(label).inserted else { return nil }
            return Self(id: label, label: label, latitude: lat, longitude: lng, category: ValueReading.string(ValueReading.field(item, "category")), icon: ValueReading.string(ValueReading.field(item, "icon")))
        }
    }
    static func duplicateLabels(_ value: Value?) -> [String] {
        var labels = Set<String>(), duplicates = Set<String>()
        for item in ValueReading.array(value) {
            let label = ValueReading.string(ValueReading.field(item, "label"))
            guard !label.isEmpty, let lat = ValueReading.number(ValueReading.field(item, "lat")), let lng = ValueReading.number(ValueReading.field(item, "lng")), (-90...90).contains(lat), (-180...180).contains(lng) else { continue }
            if !labels.insert(label).inserted { duplicates.insert(label) }
        }
        return duplicates.sorted()
    }
}

private final class MapCameraState {
    var previousSelection: String?
    var fitRevision = -1
    var bottomInset: CGFloat = 0
    var topInset: CGFloat = 84
    enum Mode { case overview, focused, manual }
    var mode: Mode = .overview
    var currentRect: MKMapRect?
    var displayedPoints: [MapPoint] = []
    var overviewRect: MKMapRect?
    var fittedSize: CGSize = .zero
    var leftInset: CGFloat = 0
    var rightInset: CGFloat = 0
}

enum MapCameraGeometry {
    static func visibleArea(size: CGSize, top: CGFloat, bottom: CGFloat, left: CGFloat = 0, right: CGFloat = 0) -> CGRect? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              top.isFinite, bottom.isFinite, left.isFinite, right.isFinite else { return nil }
        let side = min(40, size.width / 4)
        let width = size.width - 2 * side - max(0, left) - max(0, right)
        let height = size.height - max(0, top) - max(0, bottom) - 32
        guard width > 0, height > 32 else { return nil }
        return CGRect(x: side + max(0, left), y: max(0, top), width: width, height: height)
    }
    static func fit(_ content: MKMapRect, size: CGSize, visible: CGRect) -> MKMapRect? {
        guard !content.isNull, content.width > 0, content.height > 0, visible.width > 0, visible.height > 0 else { return nil }
        let scale = max(content.width / Double(visible.width), content.height / Double(visible.height))
        guard scale.isFinite, scale > 0 else { return nil }
        return MKMapRect(x: content.midX - Double(visible.midX) * scale,
                         y: content.midY - Double(visible.midY) * scale,
                         width: Double(size.width) * scale, height: Double(size.height) * scale)
    }
    static func focus(_ point: MKMapPoint, overview: MKMapRect, size: CGSize, visible: CGRect) -> MKMapRect? {
        guard point.x.isFinite, point.y.isFinite, !overview.isNull, overview.width > 0, overview.height > 0,
              size.width > 0, size.height > 0, visible.width > 0, visible.height > 0 else { return nil }
        let scale = overview.width / Double(size.width) * 0.5
        guard scale.isFinite, scale > 0 else { return nil }
        return MKMapRect(x: point.x - Double(visible.midX) * scale,
                         y: point.y - Double(visible.midY) * scale,
                         width: Double(size.width) * scale, height: Double(size.height) * scale)
    }
}

private final class MapCanvas: MKMapView {
    var onViewportChange: ((MKMapView) -> Void)?
    private var observedSize: CGSize = .zero
    #if os(iOS)
    private var observedInsets = UIEdgeInsets.zero
    override func layoutSubviews() { super.layoutSubviews(); reportViewport() }
    #else
    override func layout() { super.layout(); reportViewport() }
    #endif
    private func reportViewport() {
        #if os(iOS)
        guard bounds.size != observedSize || safeAreaInsets != observedInsets else { return }
        observedInsets = safeAreaInsets
        #else
        guard bounds.size != observedSize else { return }
        #endif
        observedSize = bounds.size
        onViewportChange?(self)
    }
}

private final class MapPin: MKPointAnnotation {
    var id = ""
    var label = ""
    var category = ""
    var icon = ""
    var order = 0
}

private struct MapPinAppearance: Equatable {
    let text: String
    let label: String
    let category: String
    let showsLabel: Bool
    let selected: Bool
    let font: Font
    let captionFont: Font
    let targetHeight: CGFloat
    let typeSize: DynamicTypeSize
    let colorScheme: ColorScheme
    let displayScale: CGFloat
}
private final class MapPinView: MKAnnotationView {
    var pinAppearance: MapPinAppearance?
    var fullLabelSize = CGSize(width: 140, height: 88)
}

enum MapLabelLayout {
    struct Candidate {
        let id: String
        let order: Int
        let selected: Bool
        let rect: CGRect
    }
    private struct Cell: Hashable { let x: Int; let y: Int }
    static func visible(_ candidates: [Candidate]) -> Set<String> {
        var cells: [Cell: [CGRect]] = [:], result = Set<String>()
        for candidate in candidates.sorted(by: { $0.selected == $1.selected ? $0.order < $1.order : $0.selected }) {
            let rect = candidate.rect.insetBy(dx: -3, dy: -3)
            guard [rect.minX, rect.maxX, rect.minY, rect.maxY].allSatisfy({ $0.isFinite && abs($0) < 1_000_000_000 }),
                  rect.width > 0, rect.height > 0, rect.width <= 10_000, rect.height <= 10_000 else { continue }
            let xs = Int(floor(rect.minX / 160))...Int(floor(rect.maxX / 160))
            let ys = Int(floor(rect.minY / 160))...Int(floor(rect.maxY / 160))
            var keys: [Cell] = []
            for x in xs { for y in ys { keys.append(Cell(x: x, y: y)) } }
            let crowded = keys.contains { cells[$0]?.contains(where: { $0.intersects(rect) }) == true }
            if !crowded || candidate.selected {
                result.insert(candidate.id)
                for key in keys { cells[key, default: []].append(rect) }
            }
        }
        return result
    }
}

@MainActor private struct MapSurface {
    let points: [MapPoint]
    let route: Bool
    let selected: String
    let allowsPan: Bool
    let focusOnSelection: Bool
    let cameraState: MapCameraState
    let bottomInset: CGFloat
    let topInset: CGFloat
    let leftInset: CGFloat
    let rightInset: CGFloat
    let reduceMotion: Bool
    let fitRevision: Int
    let displayScale: CGFloat
    let font: Font
    let captionFont: Font
    let targetHeight: CGFloat
    let typeSize: DynamicTypeSize
    let colorScheme: ColorScheme
    let onSelect: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }
    func makeMap(_ coordinator: Coordinator) -> MKMapView {
        let map = MapCanvas(); map.delegate = coordinator; map.showsUserLocation = false; map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        coordinator.map = map
        map.onViewportChange = { [weak coordinator] map in coordinator?.requestViewport(map) }
        map.register(MapPinView.self, forAnnotationViewWithReuseIdentifier: "place")
        return map
    }
    func update(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.onSelect = onSelect
        #if os(iOS)
        map.isScrollEnabled = allowsPan
        map.isPitchEnabled = false
        map.isRotateEnabled = allowsPan
        map.layoutMargins = UIEdgeInsets(top: 64, left: 16, bottom: 8, right: 16)
        #endif
        coordinator.displayScale = displayScale
        coordinator.cameraState = cameraState
        coordinator.font = font; coordinator.captionFont = captionFont; coordinator.targetHeight = targetHeight; coordinator.typeSize = typeSize; coordinator.colorScheme = colorScheme
        let pointsChanged = coordinator.points != points
        let annotationGeometryChanged = coordinator.points.map(MapPoint.Geometry.init) != points.map(MapPoint.Geometry.init)
        let geometryChanged = cameraState.displayedPoints.map(MapPoint.Geometry.init) != points.map(MapPoint.Geometry.init)
        let routeChanged = coordinator.route != route
        let explicitFit = cameraState.fitRevision != fitRevision
        let insetsChanged = abs(cameraState.bottomInset - bottomInset) > 1 || abs(cameraState.topInset - topInset) > 1
            || abs(cameraState.leftInset - leftInset) > 1 || abs(cameraState.rightInset - rightInset) > 1
        let shouldFit = geometryChanged || explicitFit || cameraState.overviewRect == nil
        coordinator.selected = selected; coordinator.bottomInset = bottomInset; coordinator.topInset = topInset
        coordinator.leftInset = leftInset; coordinator.rightInset = rightInset; coordinator.reduceMotion = reduceMotion
        cameraState.fitRevision = fitRevision; cameraState.bottomInset = bottomInset; cameraState.topInset = topInset
        cameraState.leftInset = leftInset; cameraState.rightInset = rightInset; cameraState.displayedPoints = points
        if pointsChanged {
            coordinator.points = points
            let existing = Dictionary(uniqueKeysWithValues: map.annotations.compactMap { $0 as? MapPin }.map { ($0.id, $0) })
            let ids = Set(points.map(\.id))
            map.removeAnnotations(existing.values.filter { !ids.contains($0.id) })
            var added: [MapPin] = []
            for (order, point) in points.enumerated() {
                let pin = existing[point.id] ?? MapPin()
                pin.id = point.id; pin.label = point.label; pin.category = point.category
                pin.icon = point.icon; pin.order = order
                if pin.coordinate.latitude != point.latitude || pin.coordinate.longitude != point.longitude {
                    pin.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                }
                if existing[point.id] == nil { added.append(pin) }
            }
            map.addAnnotations(added)
        }
        if annotationGeometryChanged || routeChanged {
            coordinator.route = route
            map.removeOverlays(map.overlays)
            if route && points.count > 1 {
                let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
            }
        }
        if let pin = map.annotations.compactMap({ $0 as? MapPin }).first(where: { $0.id == selected }) {
            if !map.selectedAnnotations.contains(where: { $0 === pin }) { map.selectAnnotation(pin, animated: false) }
        } else {
            for annotation in map.selectedAnnotations { map.deselectAnnotation(annotation, animated: false) }
        }
        coordinator.requestViewport(map, fit: shouldFit, focus: focusOnSelection, resize: insetsChanged)
        cameraState.previousSelection = selected
    }
    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: MKMapView?
        var points: [MapPoint] = []
        var route = false
        var selected = ""
        var bottomInset: CGFloat = 0
        var topInset: CGFloat = 84
        var leftInset: CGFloat = 0
        var rightInset: CGFloat = 0
        var reduceMotion = false
        var cameraState: MapCameraState?
        private var fitRequested = false
        private var focusRequested = false
        private var viewportRestored = false
        private var resizeRequested = false
        private var settingViewport = false
        private var viewportScheduled = false
        var displayScale: CGFloat = 2
        var font: Font = .subheadline
        var captionFont: Font = .caption
        var targetHeight: CGFloat = 44
        var typeSize: DynamicTypeSize = .large
        var colorScheme: ColorScheme = .light
        var onSelect: (String) -> Void
        init(onSelect: @escaping (String) -> Void) { self.onSelect = onSelect }
        func requestViewport(_ map: MKMapView, fit: Bool = false, focus: Bool = false, resize: Bool = false) {
            if fit {
                fitRequested = true
                focusRequested = focus && !selected.isEmpty
            } else if focus && !selected.isEmpty { focusRequested = true }
            if selected.isEmpty { focusRequested = false }
            resizeRequested = resizeRequested || resize
            guard !viewportScheduled else { return }
            viewportScheduled = true
            DispatchQueue.main.async { [weak map, weak self] in
                guard let map, let self else { return }
                defer { self.viewportScheduled = false }
                #if os(iOS)
                map.layoutIfNeeded()
                let top = self.topInset + map.safeAreaInsets.top
                let bottom = self.bottomInset + map.safeAreaInsets.bottom
                let left = self.leftInset + map.safeAreaInsets.left
                let right = self.rightInset + map.safeAreaInsets.right
                #else
                map.layoutSubtreeIfNeeded()
                let top = self.topInset, bottom = self.bottomInset
                let left = self.leftInset, right = self.rightInset
                #endif
                guard let visible = MapCameraGeometry.visibleArea(size: map.bounds.size, top: top, bottom: bottom, left: left, right: right),
                      let state = self.cameraState else { return }
                if !self.viewportRestored, !self.fitRequested, state.mode == .focused, !self.selected.isEmpty {
                    self.focusRequested = true
                }
                if self.selected.isEmpty { self.focusRequested = false }
                let resized = state.fittedSize != map.bounds.size || self.resizeRequested
                if self.fitRequested || state.overviewRect == nil {
                    state.mode = .overview
                    self.fit(map, visible: visible, apply: !self.focusRequested)
                } else if resized {
                    self.fit(map, visible: visible, apply: state.mode == .overview && !self.focusRequested)
                    if state.mode == .focused { self.focusRequested = true }
                    else if state.mode == .manual, let current = state.currentRect {
                        self.setViewport(current, on: map, animated: false)
                    }
                } else if !self.viewportRestored, !self.focusRequested, let current = state.currentRect {
                    self.setViewport(current, on: map, animated: false)
                }
                if self.focusRequested { state.mode = .focused; self.focus(map, visible: visible, animated: self.viewportRestored) }
                self.fitRequested = false; self.focusRequested = false; self.resizeRequested = false
                state.fittedSize = map.bounds.size; self.viewportRestored = true
                self.refresh(map)
            }
        }
        private func setViewport(_ rect: MKMapRect, on map: MKMapView, animated: Bool) {
            settingViewport = true
            map.setVisibleMapRect(rect, animated: animated && !reduceMotion)
            settingViewport = false
            cameraState?.currentRect = map.visibleMapRect
        }
        #if os(iOS)
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? MKAnnotationView, let pin = view.annotation as? MapPin, let map else { return }
            presentSelection(pin, map: map)
        }
        #endif
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let pin = view.annotation as? MapPin else { return }
            presentSelection(pin, map: mapView)
        }
        private func presentSelection(_ pin: MapPin, map: MKMapView) {
            guard pin.id != selected else { return }
            selected = pin.id
            onSelect(pin.id)
            refresh(map)
        }
        func refresh(_ mapView: MKMapView) {
            OpenIntelligentUIPerformance.record("map.refresh")
            let visiblePins = mapView.annotations.compactMap { $0 as? MapPin }.compactMap { pin -> (MapPin, MapPinView, CGPoint)? in
                guard let view = mapView.view(for: pin) as? MapPinView else { return nil }
                let point = OpenIntelligentUIPerformance.measure("map.projection") { mapView.convert(pin.coordinate, toPointTo: mapView) }
                guard point.x.isFinite, point.y.isFinite else { return nil }
                return (pin, view, point)
            }
            let candidates = visiblePins.map { pin, view, point in
                MapLabelLayout.Candidate(id: pin.id, order: pin.order, selected: pin.id == selected,
                    rect: CGRect(x: point.x - view.fullLabelSize.width / 2,
                                 y: point.y - max(32, targetHeight - 12) / 2 - 6,
                                 width: view.fullLabelSize.width, height: view.fullLabelSize.height))
            }
            let labels = MapLabelLayout.visible(candidates.filter(\.selected))
            for (pin, view, _) in visiblePins { style(view, pin: pin, showsLabel: labels.contains(pin.id)) }
        }
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !settingViewport && viewportRestored { cameraState?.mode = .manual }
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // A newly created MKMapView may report its default world before restoration.
            if viewportRestored || settingViewport { cameraState?.currentRect = mapView.visibleMapRect }
            refresh(mapView)
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? MapPin else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "place", for: pin)
            style(view, pin: pin)
            #if os(iOS)
            if view.gestureRecognizers?.isEmpty != false {
                view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
            }
            #endif
            return view
        }
        func style(_ view: MKAnnotationView, pin: MapPin, showsLabel: Bool = false) {
            view.canShowCallout = false
            view.detailCalloutAccessoryView = nil
            view.collisionMode = .rectangle
            view.displayPriority = .required
            view.zPriority = pin.id == selected ? .max : .defaultUnselected
            let text = MapPoint.displayIcon(pin.icon) ?? String(pin.order + 1)
            let appearance = MapPinAppearance(text: text, label: pin.label, category: pin.category, showsLabel: showsLabel,
                selected: pin.id == selected, font: font, captionFont: captionFont, targetHeight: targetHeight,
                typeSize: typeSize, colorScheme: colorScheme, displayScale: displayScale)
            if let pinView = view as? MapPinView, pinView.pinAppearance == appearance { return }
            let renderer = ImageRenderer(content: MapAnnotation(text: text, label: pin.label, showsLabel: showsLabel, selected: pin.id == selected, font: font, captionFont: captionFont, targetHeight: targetHeight).environment(\.dynamicTypeSize, typeSize).environment(\.colorScheme, colorScheme))
            renderer.scale = displayScale
            if let image = OpenIntelligentUIPerformance.measure("map.rasterize", { renderer.cgImage }) {
                if let pinView = view as? MapPinView {
                    pinView.pinAppearance = appearance
                    if showsLabel { pinView.fullLabelSize = CGSize(width: CGFloat(image.width) / displayScale, height: CGFloat(image.height) / displayScale) }
                }
                let badgeHeight = max(32, targetHeight - 12) + 12
                view.centerOffset = CGPoint(x: 0, y: max(0, (CGFloat(image.height) / displayScale - badgeHeight) / 2))
            #if os(iOS)
                view.image = UIImage(cgImage: image, scale: displayScale, orientation: .up)
                view.isAccessibilityElement = true; view.accessibilityLabel = pin.label
                view.accessibilityValue = pin.category.isEmpty ? nil : pin.category
                view.accessibilityTraits = pin.id == selected ? [.button, .selected] : [.button]
            #else
                view.image = NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / displayScale, height: CGFloat(image.height) / displayScale))
                view.setAccessibilityElement(true); view.setAccessibilityLabel(pin.label); view.setAccessibilityRole(.button)
            #endif
            }
        }
        func focus(_ map: MKMapView, visible: CGRect, animated: Bool = true) {
            guard let overviewRect = cameraState?.overviewRect, let point = points.first(where: { $0.id == selected }) else { return }
            let center = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            if let focused = MapCameraGeometry.focus(center, overview: overviewRect, size: map.bounds.size, visible: visible) {
                setViewport(focused, on: map, animated: animated)
            }
        }
        func fit(_ map: MKMapView, visible: CGRect, apply: Bool = true) {
            guard !points.isEmpty else { return }
            var rect = MKMapRect.null
            for point in points {
                let p = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                rect = rect.union(MKMapRect(x: p.x - 500, y: p.y - 500, width: 1000, height: 1000))
            }
            if let fitted = MapCameraGeometry.fit(rect, size: map.bounds.size, visible: visible) {
                cameraState?.overviewRect = fitted
                if apply { setViewport(fitted, on: map, animated: false) }
            }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line); renderer.lineWidth = 3
            #if os(iOS)
            renderer.strokeColor = .label
            #else
            renderer.strokeColor = .labelColor
            #endif
            return renderer
        }
    }
}

private struct MapAnnotation: View {
    let text: String
    let label: String
    let showsLabel: Bool
    let selected: Bool
    let font: Font
    let captionFont: Font
    let targetHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(spacing: 2) {
            MapBadge(text: text, selected: selected, font: font, targetHeight: targetHeight)
            if showsLabel {
                Text(label).font(captionFont).foregroundStyle(colorScheme == .dark ? Color.white : Color.black).lineLimit(2).multilineTextAlignment(.center)
                    .frame(maxWidth: MapMetrics.labelWidth).fixedSize(horizontal: false, vertical: true)
                    .shadow(color: colorScheme == .dark ? .black : .white, radius: 2).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
    }
}

private struct MapBadge: View {
    let text: String
    let selected: Bool
    let font: Font
    let targetHeight: CGFloat
    var body: some View {
        Text(text).font(font.weight(.semibold)).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(selected ? Color.white : Color.black)
            .frame(width: max(32, targetHeight - 12), height: max(32, targetHeight - 12))
            .background(selected ? Color.black : Color.white, in: Circle())
            .overlay(Circle().strokeBorder(selected ? Color.white : Color.gray.opacity(0.3), lineWidth: selected ? 2 : 0.5))
            .shadow(color: .black.opacity(selected ? 0.24 : 0.12), radius: selected ? 4 : 2, y: 1)
            .padding(6)
    }
}

#if os(iOS)
extension MapSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView { makeMap(context.coordinator) }
    func updateUIView(_ view: MKMapView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleUIView(_ view: MKMapView, coordinator: Coordinator) { view.delegate = nil; (view as? MapCanvas)?.onViewportChange = nil }
}
#else
extension MapSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> MKMapView { makeMap(context.coordinator) }
    func updateNSView(_ view: MKMapView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleNSView(_ view: MKMapView, coordinator: Coordinator) { view.delegate = nil; (view as? MapCanvas)?.onViewportChange = nil }
}
#endif
