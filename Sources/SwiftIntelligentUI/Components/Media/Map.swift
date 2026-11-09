import SwiftUI
import MapKit
import OpenUILang
import OpenUISwiftUI

private enum MapMetrics {
    static let inlineHeight: CGFloat = 360
    static let minimumHeight: CGFloat = 300
    static let maximumHeight: CGFloat = 400
    static let labelWidth: CGFloat = 140
}

enum MapMarkerComponent {
    static var component: OpenUIComponent {
        var lat = Parameter.number("lat", minimum: -90, maximum: 90); lat.required = true
        var lng = Parameter.number("lng", minimum: -180, maximum: 180); lng.required = true
        return OpenUIComponent(name: "MapMarker", description: "A named coordinate with optional category and one emoji icon. Without an emoji the pin shows its sequence number.", params: [OpenUIParameter.string("label"), lat, lng, OpenUIParameter.string("category", required: false), OpenUIParameter.string("icon", required: false)]) { context in
            Label(context.string("label") ?? "地点", systemImage: "mappin")
        }
    }
}

enum MapComponent {
    static var component: OpenUIComponent {
        var selected = OpenUIParameter.selection("selected", required: false); selected.isBindable = true
        return OpenUIComponent(name: "Map", description: "Street map fitted to supplied markers. selected holds the clicked marker label. Filter by supplied category or fit all markers. Host-presented maps up to 800pt enable panning when height exceeds 400pt. route draws a schematic line in marker order, not road directions. No user location or invented coordinates.", params: [
            OpenUIParameter.slot("markers", required: true, accepting: ["MapMarker"]), OpenUIParameter.flag("route"), selected,
            Parameter.number("height", minimum: 160, maximum: 800)
        ]) { NativeMapView(context: $0) }
    }
}

private struct NativeMapView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var localSelection = ""
    @State private var cameraState = MapCameraState()
    @State private var category: String?
    @State private var fitRevision = 0
    private var allPoints: [MapPoint] { MapPoint.decode(context.value("markers")) }
    private var categories: [String] { Array(Set(allPoints.map(\.category).filter { !$0.isEmpty })).sorted() }
    private var points: [MapPoint] { allPoints.filter { category == nil || $0.category == category } }
    private var selection: String {
        let requested = ValueReading.boundString(context, "selected") ?? localSelection
        return points.contains(where: { $0.id == requested }) ? requested : points.first?.id ?? ""
    }
    private var height: CGFloat {
        let minimum = typeSize.isAccessibilitySize ? MapMetrics.maximumHeight : MapMetrics.minimumHeight
        return min(800, max(minimum, CGFloat(context.number("height") ?? Double(MapMetrics.inlineHeight))))
    }
    private var allowsPan: Bool { height > MapMetrics.maximumHeight }
    var body: some View {
        Group {
            if allPoints.isEmpty { Text("暂无有效地点坐标").foregroundStyle(theme.secondaryText) }
            else if points.isEmpty { emptySelection.frame(height: height) }
            else if allowsPan {
                GeometryReader { geometry in
                    let available = geometry.size.height
                    scene(fullscreen: true).frame(height: available.isFinite && available >= height ? available : height)
                }.frame(minHeight: height)
            }
            else { scene(fullscreen: false).frame(height: height) }
        }
        .clipShape(RoundedRectangle(cornerRadius: allowsPan ? 0 : theme.cornerRadius))
        .onAppear(perform: reconcileSelection)
        .onChange(of: points.map(\.id)) { _ in reconcileSelection() }
        .onChange(of: allPoints.map(\.id)) { _ in category = nil }
    }
    private func scene(fullscreen: Bool) -> some View {
        ZStack(alignment: .top) {
            MapSurface(points: points, route: context.flag("route") == true, selected: selection,
                       allowsPan: fullscreen, focusOnSelection: allowsPan && cameraState.previousSelection != nil && cameraState.previousSelection != selection,
                       cameraState: cameraState,
                       bottomInset: fullscreen ? 180 : theme.innerSpacing * 2 + 32,
                       topInset: fullscreen ? 96 : theme.minimumControlHeight + theme.innerSpacing * 2 + 24,
                       fitRevision: fitRevision, displayScale: displayScale,
                       font: theme.labelFont, captionFont: theme.captionFont, targetHeight: theme.minimumControlHeight, typeSize: typeSize, colorScheme: colorScheme, onSelect: select)
                .ignoresSafeArea(.container, edges: fullscreen ? .all : [])
            if !fullscreen {
                HStack(spacing: theme.innerSpacing) {
                    filterMenu()
                    Spacer()
                    mapButton("查看全部地点", symbol: "scope") { fitRevision += 1 }
                }.padding(theme.innerSpacing)
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
        guard !points.contains(where: { $0.id == requested }) else { return }
        let fallback = points.first?.id ?? ""
        if let binding = context.binding("selected") {
            if ValueReading.string(binding.wrappedValue) != fallback { binding.wrappedValue = .string(OpenUIString(fallback)) }
        } else { localSelection = fallback }
    }
    private func filterMenu() -> some View {
        Menu {
            Button("全部地点") { category = nil; fitRevision += 1 }
            ForEach(categories, id: \.self) { item in
                Button(item) { category = item; fitRevision += 1 }
            }
        } label: {
            HStack(spacing: 8) {
                Text(category ?? "全部地点").font(theme.secondaryFont).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.medium))
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.fieldBorder, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            .frame(minHeight: theme.minimumControlHeight)
            .contentShape(Rectangle())
        }
        .disabled(!context.canInteract || categories.isEmpty)
        .accessibilityLabel("按类别筛选")
    }
    private var emptySelection: some View {
        VStack(spacing: theme.groupSpacing) {
            Text("当前类别没有地点").font(theme.bodyFont).foregroundStyle(theme.secondaryText)
            filterMenu()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.surface)
    }
    private func controlSymbol(_ symbol: String) -> some View {
        Image(systemName: symbol).font(theme.secondaryFont.weight(.medium))
        .frame(width: 32, height: 32)
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().strokeBorder(theme.fieldBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        .frame(minWidth: theme.minimumControlHeight, minHeight: theme.minimumControlHeight)
        .contentShape(Rectangle()).foregroundStyle(theme.primaryText)
    }
    private func mapButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { controlSymbol(symbol) }
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
    var overviewRect: MKMapRect?
    var fittedSize: CGSize = .zero
}

enum MapCameraGeometry {
    static func visibleArea(size: CGSize, top: CGFloat, bottom: CGFloat) -> CGRect? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let side = min(40, size.width / 4)
        let width = size.width - 2 * side
        let height = size.height - max(0, top) - max(0, bottom) - 32
        guard width > 0, height > 32 else { return nil }
        return CGRect(x: side, y: max(0, top), width: width, height: height)
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

@MainActor private struct MapSurface {
    let points: [MapPoint]
    let route: Bool
    let selected: String
    let allowsPan: Bool
    let focusOnSelection: Bool
    let cameraState: MapCameraState
    let bottomInset: CGFloat
    let topInset: CGFloat
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
        map.onViewportChange = { [weak coordinator] map in coordinator?.requestViewport(map, fit: true) }
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "place")
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
        let pointsChanged = coordinator.points != points || coordinator.route != route
        let shouldFit = pointsChanged || cameraState.fitRevision != fitRevision || cameraState.overviewRect == nil || abs(cameraState.bottomInset - bottomInset) > 1 || abs(cameraState.topInset - topInset) > 1
        coordinator.selected = selected; coordinator.bottomInset = bottomInset; coordinator.topInset = topInset
        cameraState.fitRevision = fitRevision; cameraState.bottomInset = bottomInset; cameraState.topInset = topInset
        if pointsChanged {
            coordinator.points = points; coordinator.route = route
            map.removeAnnotations(map.annotations); map.removeOverlays(map.overlays)
            let pins = points.enumerated().map { order, point -> MapPin in
                let pin = MapPin()
                pin.id = point.id; pin.label = point.label; pin.category = point.category
                pin.icon = point.icon; pin.order = order
                pin.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                return pin
            }
            map.addAnnotations(pins)
            if route && pins.count > 1 { map.addOverlay(MKPolyline(coordinates: pins.map(\.coordinate), count: pins.count)) }
        }
        if let pin = map.annotations.compactMap({ $0 as? MapPin }).first(where: { $0.id == selected }) {
            if !map.selectedAnnotations.contains(where: { $0 === pin }) { map.selectAnnotation(pin, animated: false) }
        }
        coordinator.requestViewport(map, fit: shouldFit, focus: focusOnSelection)
        cameraState.previousSelection = selected
        coordinator.refresh(map)
    }
    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: MKMapView?
        var points: [MapPoint] = []
        var route = false
        var selected = ""
        var bottomInset: CGFloat = 0
        var topInset: CGFloat = 84
        var cameraState: MapCameraState?
        private var fitRequested = false
        private var focusRequested = false
        private var viewportRestored = false
        private var viewportScheduled = false
        var displayScale: CGFloat = 2
        var font: Font = .subheadline
        var captionFont: Font = .caption
        var targetHeight: CGFloat = 44
        var typeSize: DynamicTypeSize = .large
        var colorScheme: ColorScheme = .light
        var onSelect: (String) -> Void
        init(onSelect: @escaping (String) -> Void) { self.onSelect = onSelect }
        func requestViewport(_ map: MKMapView, fit: Bool = false, focus: Bool = false) {
            fitRequested = fitRequested || fit
            focusRequested = focusRequested || focus
            guard !viewportScheduled else { return }
            viewportScheduled = true
            DispatchQueue.main.async { [weak map, weak self] in
                guard let map, let self else { return }
                defer { self.viewportScheduled = false }
                #if os(iOS)
                map.layoutIfNeeded()
                #else
                map.layoutSubtreeIfNeeded()
                #endif
                #if os(iOS)
                let top = self.topInset + map.safeAreaInsets.top
                let bottom = self.bottomInset + map.safeAreaInsets.bottom
                #else
                let top = self.topInset, bottom = self.bottomInset
                #endif
                guard let visible = MapCameraGeometry.visibleArea(size: map.bounds.size, top: top, bottom: bottom), let cameraState = self.cameraState else { return }
                if !self.viewportRestored, cameraState.fittedSize == map.bounds.size, let overview = cameraState.overviewRect {
                    map.setVisibleMapRect(overview, animated: false)
                    self.viewportRestored = true
                }
                if self.fitRequested || cameraState.fittedSize != map.bounds.size {
                    self.fit(map, visible: visible)
                    self.fitRequested = false
                    cameraState.fittedSize = map.bounds.size
                    self.viewportRestored = true
                    if self.focusRequested { self.focus(map, visible: visible) }
                    self.focusRequested = false
                } else if self.focusRequested {
                    self.focus(map, visible: visible)
                    self.focusRequested = false
                }
                self.refresh(map)
            }
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
            guard pin.id != selected else { refresh(map); return }
            selected = pin.id
            onSelect(pin.id)
            refresh(map)
        }
        func refresh(_ mapView: MKMapView) {
            let pins = mapView.annotations.compactMap { $0 as? MapPin }
            let collisionDistance: CGFloat = typeSize.isAccessibilitySize ? 160 : 64
            for pin in pins {
                guard let view = mapView.view(for: pin) else { continue }
                let center = mapView.convert(pin.coordinate, toPointTo: mapView)
                let crowded = pin.id != selected && pins.contains { other in
                    guard other !== pin, other.id == selected || other.order < pin.order else { return false }
                    let point = mapView.convert(other.coordinate, toPointTo: mapView)
                    return hypot(center.x - point.x, center.y - point.y) < collisionDistance
                }
                style(view, pin: pin, showsLabel: !crowded)
            }
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
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
        func style(_ view: MKAnnotationView, pin: MapPin, showsLabel: Bool = true) {
            view.canShowCallout = false
            view.detailCalloutAccessoryView = nil
            view.collisionMode = .rectangle
            view.displayPriority = .required
            view.zPriority = pin.id == selected ? .max : .defaultUnselected
            let text = pin.icon.isEmpty ? String(pin.order + 1) : pin.icon
            let renderer = ImageRenderer(content: MapAnnotation(text: text, label: pin.label, showsLabel: showsLabel, selected: pin.id == selected, font: font, captionFont: captionFont, targetHeight: targetHeight).environment(\.dynamicTypeSize, typeSize).environment(\.colorScheme, colorScheme))
            renderer.scale = displayScale
            if let image = renderer.cgImage {
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
        func focus(_ map: MKMapView, visible: CGRect) {
            guard let overviewRect = cameraState?.overviewRect, let point = points.first(where: { $0.id == selected }) else { return }
            let center = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            if let focused = MapCameraGeometry.focus(center, overview: overviewRect, size: map.bounds.size, visible: visible) {
                map.setVisibleMapRect(focused, animated: true)
            }
        }
        func fit(_ map: MKMapView, visible: CGRect) {
            guard !points.isEmpty else { return }
            var rect = MKMapRect.null
            for point in points {
                let p = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                rect = rect.union(MKMapRect(x: p.x - 500, y: p.y - 500, width: 1000, height: 1000))
            }
            if let fitted = MapCameraGeometry.fit(rect, size: map.bounds.size, visible: visible) {
                cameraState?.overviewRect = fitted
                map.setVisibleMapRect(fitted, animated: false)
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
    static func dismantleUIView(_ view: MKMapView, coordinator: Coordinator) { view.delegate = nil }
}
#else
extension MapSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> MKMapView { makeMap(context.coordinator) }
    func updateNSView(_ view: MKMapView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleNSView(_ view: MKMapView, coordinator: Coordinator) { view.delegate = nil }
}
#endif
