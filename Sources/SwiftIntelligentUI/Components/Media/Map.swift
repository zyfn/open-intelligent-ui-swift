import SwiftUI
import MapKit
import OpenUILang
import OpenUISwiftUI

enum MapMarkerComponent {
    static var component: OpenUIComponent {
        var lat = Parameter.number("lat", minimum: -90, maximum: 90); lat.required = true
        var lng = Parameter.number("lng", minimum: -180, maximum: 180); lng.required = true
        return OpenUIComponent(name: "MapMarker", description: "A named coordinate with optional category, icon, stable id and badge text. Selection uses id when supplied, otherwise the label. Badge text is caller data, never an inferred rating.", params: [OpenUIParameter.string("label"), lat, lng, OpenUIParameter.string("category", required: false), OpenUIParameter.string("icon", required: false, values: IconCatalog.names), OpenUIParameter.string("id", required: false), OpenUIParameter.string("badge", required: false)]) { context in
            Label(context.string("label") ?? "地点", systemImage: IconCatalog.symbol(context.string("icon")) ?? "mappin")
        }
    }
}
enum MapComponent {
    static var component: OpenUIComponent {
        var selected = OpenUIParameter.selection("selected", required: false); selected.isBindable = true
        var visible = ParamDef(name: "visibleIds", required: false, schema: .object([.init(key: "anyOf", value: .array([
            Parameter.arraySchema(Parameter.stringSchema), .object([.init(key: "type", value: .string("null"))])
        ]))])); visible.isBindable = true
        return OpenUIComponent(name: "Map", description: "Compact map with supplied markers and linked summary cards. Use one entity source to derive markers, supplied card carousels and matching ids. Omitted custom content uses built-in marker-fact cards inside the map. Share selected and optional visibleIds array binding with outside collections. Built-in previous/next and filter menu change visible markers/cards, selection and fit together. A literal id array is fixed/read-only; omitted/null unbound ids use local filtering. A null binding is unfiltered and an empty array hides all points. Custom content needs Carousel itemIds matching marker ids; incomplete/unlinked content falls back to marker-fact summaries rather than mismatching cards. route=true draws schematic straight connectors; optional routeIds specifies an actual visit-order subset (repeated visits allowed), never all unvisited alternatives or road directions. Inline default360, bounded300–400/AX400; summaries stay inside, with64pt thumbnails. Fit, expand/close, reading-scroll priority and expanded panning remain. No invented coordinates, photos or orders.", params: [
            OpenUIParameter.slot("markers", required: true, accepting: ["MapMarker"]), OpenUIParameter.flag("route"), selected, Parameter.number("height", minimum: 160, maximum: 800),
            OpenUIParameter.slot("content", required: false), OpenUIParameter.flag("expandable"), visible,
            Parameter.array("routeIds", items: Parameter.stringSchema, required: false)
        ]) { NativeMapView(context: $0) }
    }
}
private struct NativeMapView: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var displayScale
    @State private var localSelection = ""
    @State private var localVisibleIDs: Set<String>?
    @State private var expanded = false
    @State private var fitRevision = 0
    @State private var inlineContentHeight: CGFloat = 180
    @State private var expandedContentHeight: CGFloat = 180
    private var allPoints: [MapPoint] { MapPoint.decode(context.value("markers")) }
    private var fixedVisibility: Bool {
        guard context.binding("visibleIds") == nil else { return false }
        if case .array = context.value("visibleIds") { return true }
        return false
    }
    private var visibleIDs: Set<String> {
        if let binding = context.binding("visibleIds") {
            if case .array(let ids) = binding.wrappedValue { return Set(ids.map { ValueReading.string($0) }) }
            return Set(allPoints.map(\.id))
        }
        if case .array(let ids) = context.value("visibleIds") { return Set(ids.map { ValueReading.string($0) }) }
        return localVisibleIDs ?? Set(allPoints.map(\.id))
    }
    private var points: [MapPoint] { allPoints.filter { visibleIDs.contains($0.id) } }
    private var routeIDs: [String]? {
        guard context.value("routeIds") != nil else { return nil }
        return ValueReading.array(context.value("routeIds")).map { ValueReading.string($0) }
    }
    private var hasCustomContent: Bool { !context.children("content").isEmpty }
    private var selection: String {
        MapSelection.resolve(ids: points.map(\.id), requested: ValueReading.boundString(context, "selected") ?? localSelection)
    }
    private var height: CGFloat {
        let minimum = typeSize.isAccessibilitySize ? theme.mapInlineMaximumHeight : theme.mapInlineMinimumHeight
        return min(theme.mapInlineMaximumHeight, max(minimum, CGFloat(context.number("height") ?? Double(theme.mapInlineHeight))))
    }
    private var cardLimit: CGFloat { typeSize.isAccessibilitySize ? theme.mapCardAccessibilityHeight : theme.mapCardMaximumHeight }
    var body: some View {
        Group {
            if allPoints.isEmpty { Text("暂无有效地点坐标").foregroundStyle(theme.secondaryText) }
            else if points.isEmpty { emptySelection(fullscreen: false).frame(height: height) }
            else { scene(fullscreen: false).frame(height: height) }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
        .onChange(of: allPoints.map(\.id)) { _ in if context.binding("visibleIds") == nil && !fixedVisibility { localVisibleIDs = nil } }
        #if os(iOS)
        .fullScreenCover(isPresented: $expanded) { expandedContent.dynamicTypeSize(typeSize) }
        #else
        .sheet(isPresented: $expanded) { expandedContent.dynamicTypeSize(typeSize).frame(minWidth: 720, minHeight: 600) }
        #endif
    }
    private var expandedContent: some View {
        GeometryReader { geometry in
            if points.isEmpty { emptySelection(fullscreen: true).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { scene(fullscreen: true, maximumContentHeight: min(cardLimit, max(88, geometry.size.height * 0.35))) }
        }.background(theme.canvas)
    }
    private func scene(fullscreen: Bool, maximumContentHeight: CGFloat? = nil) -> some View {
        let contentHeight = fullscreen ? expandedContentHeight : inlineContentHeight
        let visibleContentHeight = min(contentHeight, maximumContentHeight ?? cardLimit)
        return ZStack(alignment: .bottom) {
            MapSurface(points: points, route: context.flag("route") == true, routeIDs: routeIDs, selected: selection,
                       allowsPan: fullscreen || context.flag("expandable") == false,
                       bottomInset: visibleContentHeight + theme.innerSpacing * 2,
                       topInset: theme.minimumControlHeight + theme.innerSpacing * 2 + 24,
                       fitRevision: fitRevision, showsCallout: false, displayScale: displayScale,
                       font: theme.labelFont, targetHeight: theme.minimumControlHeight, typeSize: typeSize, onSelect: select)
                .ignoresSafeArea(.container, edges: fullscreen ? .all : [])
            VStack {
                HStack(spacing: theme.innerSpacing) {
                    if fullscreen { mapButton("关闭地图", symbol: "xmark") { expanded = false } }
                    if points.count > 1 {
                        HStack(spacing: 0) {
                            navigationButton(forward: false)
                            navigationButton(forward: true)
                        }.background(.regularMaterial, in: Capsule())
                    }
                    Spacer()
                    filterMenu
                    mapButton("适配当前地点", symbol: "scope") { fitRevision += 1 }
                    if !fullscreen && context.flag("expandable") != false {
                        mapButton("展开地图", symbol: "arrow.up.left.and.arrow.down.right") { expanded = true }
                    }
                }.padding(theme.innerSpacing)
                Spacer()
            }
            ScrollView(.vertical) { placeContent(fullscreen: fullscreen) }
            .frame(height: visibleContentHeight)
            .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
            .padding(theme.innerSpacing)
        }
    }
    private func placeContent(fullscreen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasCustomContent, let values = MapContentProjection.filtered(context.value("content"), visible: visibleIDs, known: Set(allPoints.map(\.id)), selected: selection) {
                ForEach(OpenUIRenderChild.children(of: .array(OpenUIArray(values)))) { context.render($0.value) }
            }
            else {
                CarouselView(context: context, children: MapFallback.cards(points: points), itemIDs: points.map(\.id),
                             selection: Binding(get: { selection }, set: { select($0) }))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.intelligentUIContentBackground, theme.canvas)
        .environment(\.intelligentUIMapContent, true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { value in
            guard value.isFinite, value > 0 else { return }
            if fullscreen {
                if value != expandedContentHeight { expandedContentHeight = value }
            } else if value != inlineContentHeight { inlineContentHeight = value }
        }
    }
    private func select(_ id: String) {
        guard context.canInteract else { return }
        if let binding = context.binding("selected") { if ValueReading.string(binding.wrappedValue) != id { binding.wrappedValue = .string(OpenUIString(id)) } }
        else { localSelection = id }
    }
    private func setVisible(_ ids: Set<String>) {
        guard context.canInteract else { return }
        let ordered = allPoints.map(\.id).filter { ids.contains($0) }
        if let binding = context.binding("visibleIds") { binding.wrappedValue = .array(OpenUIArray(ordered.map { .string(OpenUIString($0)) })) }
        else if !fixedVisibility { localVisibleIDs = Set(ordered) }
        else { return }
        let requested = ValueReading.boundString(context, "selected") ?? localSelection
        if !ordered.contains(requested) { select(ordered.first ?? "") }
        fitRevision += 1
    }
    private func navigationButton(forward: Bool) -> some View {
        let index = points.firstIndex { $0.id == selection } ?? 0
        return Button {
            let target = index + (forward ? 1 : -1)
            if points.indices.contains(target) { select(points[target].id) }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left").font(theme.secondaryFont.weight(.medium))
                .frame(width: theme.minimumControlHeight, height: theme.minimumControlHeight)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(theme.primaryText)
            .disabled(!context.canInteract || (forward ? index >= points.count - 1 : index <= 0))
            .accessibilityLabel(forward ? "下一个地点" : "上一个地点")
    }
    private var filterMenu: some View {
        Menu {
            Button("显示全部") { setVisible(Set(allPoints.map(\.id))) }.modifier(KeepMapMenuOpen())
            Divider()
            ForEach(allPoints, id: \.id) { point in
                Button {
                    var ids = visibleIDs
                    if !ids.insert(point.id).inserted { ids.remove(point.id) }
                    setVisible(ids)
                } label: {
                    Label(point.label, systemImage: visibleIDs.contains(point.id) ? "checkmark.square.fill" : "square")
                }.modifier(KeepMapMenuOpen())
            }
            Divider()
            Button("完成") {}
        } label: { controlSymbol("line.3.horizontal.decrease") }
        .disabled(!context.canInteract || fixedVisibility)
        .accessibilityLabel("筛选地点")
    }
    private func emptySelection(fullscreen: Bool) -> some View {
        VStack(spacing: theme.groupSpacing) {
            Text("未选择显示的地点").font(theme.bodyFont).foregroundStyle(theme.secondaryText)
            filterMenu
            if fullscreen { Button("关闭地图") { expanded = false }.tint(theme.actionAccent) }
        }.frame(maxWidth: .infinity).background(theme.surface)
    }
    private func controlSymbol(_ symbol: String) -> some View {
        Image(systemName: symbol).font(theme.secondaryFont.weight(.medium))
            .frame(width: 32, height: 32).background(.regularMaterial, in: Circle())
            .frame(minWidth: theme.minimumControlHeight, minHeight: theme.minimumControlHeight)
            .contentShape(Rectangle()).foregroundStyle(theme.primaryText)
    }
    private func mapButton(_ label: String, symbol: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            controlSymbol(symbol)
        }
            .buttonStyle(.plain).foregroundStyle(theme.primaryText)
            .accessibilityLabel(label).disabled(disabled)
    }
}
private struct KeepMapMenuOpen: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) { content.menuActionDismissBehavior(.disabled) }
        else { content }
        #else
        content
        #endif
    }
}

enum MapContentProjection {
    static func filtered(_ value: Value?, visible: Set<String>, known: Set<String>, selected: String? = nil) -> [Value]? {
        guard let value else { return nil }
        var foundCarousel = false
        func visit(_ value: Value) -> Value? {
            switch value {
            case .array(let values):
                var result: [Value] = []
                for value in values { guard let child = visit(value) else { return nil }; result.append(child) }
                return .array(OpenUIArray(result))
            case .element(let element):
                var props = element.props
                if element.typeName == "Carousel" {
                    let children = OpenUIRenderChild.children(of: props.last(where: { $0.0 == "children" })?.1 ?? .null)
                    let ids = ValueReading.array(props.last(where: { $0.0 == "itemIds" })?.1).map { ValueReading.string($0) }
                    guard ids.count == children.count, !ids.isEmpty, Set(ids).count == ids.count, Set(ids).isSubset(of: known) else { return nil }
                    let indices = ids.indices.filter { visible.contains(ids[$0]) }
                    guard !indices.isEmpty else { return nil }
                    if let selected, !selected.isEmpty, !indices.contains(where: { ids[$0] == selected }) { return nil }
                    foundCarousel = true
                    props.removeAll { $0.0 == "children" || $0.0 == "itemIds" }
                    props.append(("children", .array(OpenUIArray(indices.map { children[$0].value }))))
                    props.append(("itemIds", .array(OpenUIArray(indices.map { .string(OpenUIString(ids[$0])) }))))
                } else {
                    for index in props.indices where ["children", "content"].contains(props[index].0) {
                        if case .object = props[index].1 { continue }
                        guard let child = visit(props[index].1) else { return nil }; props[index].1 = child
                    }
                }
                return .element(EvaluatedElement(typeName: element.typeName, props: props, statementId: element.statementId, partial: element.partial, isSourceComplete: element.isSourceComplete))
            default: return value
            }
        }
        guard let projected = visit(value), foundCarousel else { return nil }
        return OpenUIRenderChild.children(of: projected).map(\.value)
    }
}
enum MapSelection {
    static func resolve(ids: [String], requested: String?) -> String {
        if let requested, ids.contains(requested) { return requested }
        return ids.first ?? ""
    }
}
enum MapFallback {
    static func cards(points: [MapPoint]) -> [OpenUIRenderChild] {
        let cards = points.map { point -> Value in
            var fields: [ObjectField] = [
                .init(key: "title", value: .string(OpenUIString(point.label))),
                .init(key: "subtitle", value: .string(OpenUIString(point.category)))
            ]
            if !point.badge.isEmpty { fields.append(.init(key: "badge", value: .string(OpenUIString(point.badge)))) }
            let summary = Value.element(EvaluatedElement(typeName: "ImageText", props: [("content", .object(OpenUIObject(fields)))]))
            return .element(EvaluatedElement(typeName: "Card", props: [("children", .array([summary]))], statementId: "map-place:" + point.id))
        }
        return OpenUIRenderChild.children(of: .array(OpenUIArray(cards)))
    }
}
struct MapPoint: Equatable {
    let id: String
    let label: String
    let latitude: Double
    let longitude: Double
    let category: String
    let icon: String
    let badge: String
    static func decode(_ value: Value?) -> [Self] {
        var ids = Set<String>()
        return ValueReading.array(value).compactMap { item in
            let label = ValueReading.string(ValueReading.field(item, "label"))
            guard !label.isEmpty, let lat = ValueReading.number(ValueReading.field(item, "lat")), let lng = ValueReading.number(ValueReading.field(item, "lng")), (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
            let explicitId = ValueReading.string(ValueReading.field(item, "id"))
            let id = explicitId.isEmpty ? label : explicitId
            guard ids.insert(id).inserted else { return nil }
            return Self(id: id, label: label, latitude: lat, longitude: lng, category: ValueReading.string(ValueReading.field(item, "category")), icon: ValueReading.string(ValueReading.field(item, "icon")), badge: ValueReading.string(ValueReading.field(item, "badge")))
        }
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
    static func centered(_ current: MKMapRect, point: MKMapPoint, size: CGSize, visible: CGRect) -> MKMapRect? {
        guard size.width > 0, size.height > 0, !current.isNull, current.width > 0, current.height > 0 else { return nil }
        return MKMapRect(x: point.x - Double(visible.midX / size.width) * current.width,
                         y: point.y - Double(visible.midY / size.height) * current.height,
                         width: current.width, height: current.height)
    }
}
private final class MapPin: MKPointAnnotation { var id = ""; var icon = ""; var badge = "" }
@MainActor private struct MapSurface {
    let points: [MapPoint]
    let route: Bool
    let routeIDs: [String]?
    let selected: String
    let allowsPan: Bool
    let bottomInset: CGFloat
    let topInset: CGFloat
    let fitRevision: Int
    let showsCallout: Bool
    let displayScale: CGFloat
    let font: Font
    let targetHeight: CGFloat
    let typeSize: DynamicTypeSize
    let onSelect: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }
    func makeMap(_ coordinator: Coordinator) -> MKMapView {
        let map = MapCanvas(); map.delegate = coordinator; map.showsUserLocation = false; map.isPitchEnabled = false
        map.onViewportChange = { [weak coordinator] map in coordinator?.requestViewport(map, fit: true) }
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "place")
        return map
    }
    func update(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.onSelect = onSelect
        #if os(iOS)
        map.isScrollEnabled = allowsPan
        map.layoutMargins = UIEdgeInsets(top: 64, left: 16, bottom: bottomInset + 16, right: 16)
        #endif
        coordinator.showsCallout = showsCallout; coordinator.displayScale = displayScale
        coordinator.font = font; coordinator.targetHeight = targetHeight; coordinator.typeSize = typeSize
        coordinator.updating = true; defer { coordinator.updating = false }
        let shouldFit = coordinator.points != points || coordinator.route != route || coordinator.routeIDs != routeIDs || coordinator.fitRevision != fitRevision || abs(coordinator.bottomInset - bottomInset) > 1 || abs(coordinator.topInset - topInset) > 1
        let selectionChanged = coordinator.selected != selected
        coordinator.selected = selected; coordinator.bottomInset = bottomInset; coordinator.topInset = topInset; coordinator.fitRevision = fitRevision
        if coordinator.points != points || coordinator.route != route || coordinator.routeIDs != routeIDs {
            coordinator.points = points; coordinator.route = route; coordinator.routeIDs = routeIDs
            map.removeAnnotations(map.annotations); map.removeOverlays(map.overlays)
            let pins = points.map { point -> MapPin in
                let pin = MapPin(); pin.title = point.label; pin.subtitle = point.category; pin.icon = point.icon
                pin.id = point.id; pin.badge = point.badge
                pin.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                return pin
            }
            map.addAnnotations(pins)
            let routePins = routeIDs.map { ids in ids.compactMap { id in pins.first(where: { $0.id == id }) } } ?? pins
            if route && routePins.count > 1 { map.addOverlay(MKPolyline(coordinates: routePins.map(\.coordinate), count: routePins.count)) }
        }
        if let pin = map.annotations.compactMap({ $0 as? MapPin }).first(where: { $0.id == selected }) {
            if !map.selectedAnnotations.contains(where: { $0 === pin }) { map.selectAnnotation(pin, animated: false) }
        }
        coordinator.requestViewport(map, fit: shouldFit, center: selectionChanged && !shouldFit)
        if selectionChanged || shouldFit {
            for pin in map.annotations.compactMap({ $0 as? MapPin }) { if let view = map.view(for: pin) { coordinator.style(view, pin: pin) } }
        }
    }
    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        var points: [MapPoint] = []
        var route = false
        var routeIDs: [String]?
        var updating = false
        var selected = ""
        var bottomInset: CGFloat = 0
        var topInset: CGFloat = 84
        private var fitRequested = false
        private var centerRequested = false
        private var viewportScheduled = false
        private var fittedSize: CGSize = .zero
        var fitRevision = -1
        var showsCallout = false
        var displayScale: CGFloat = 2
        var font: Font = .subheadline
        var targetHeight: CGFloat = 44
        var typeSize: DynamicTypeSize = .large
        var onSelect: (String) -> Void
        init(onSelect: @escaping (String) -> Void) { self.onSelect = onSelect }
        func requestViewport(_ map: MKMapView, fit: Bool = false, center: Bool = false) {
            fitRequested = fitRequested || fit
            centerRequested = centerRequested || center
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
                guard let visible = MapCameraGeometry.visibleArea(size: map.bounds.size, top: top, bottom: bottom) else { return }
                if self.fitRequested || self.fittedSize != map.bounds.size {
                    self.fit(map, visible: visible)
                    self.fitRequested = false
                    self.centerRequested = false
                    self.fittedSize = map.bounds.size
                } else if self.centerRequested {
                    self.centerRequested = false
                    if let pin = map.annotations.compactMap({ $0 as? MapPin }).first(where: { $0.id == self.selected }),
                       let rect = MapCameraGeometry.centered(map.visibleMapRect, point: MKMapPoint(pin.coordinate), size: map.bounds.size, visible: visible) {
                        map.setVisibleMapRect(rect, animated: false)
                    }
                }
            }
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard !updating, let pin = view.annotation as? MapPin else { return }; onSelect(pin.id)
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? MapPin else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "place", for: pin)
            style(view, pin: pin)
            return view
        }
        func style(_ view: MKAnnotationView, pin: MapPin) {
            view.canShowCallout = showsCallout
            view.collisionMode = .rectangle
            view.displayPriority = pin.id == selected ? .required : .defaultHigh
            view.zPriority = pin.id == selected ? .max : .defaultUnselected
            let renderer = ImageRenderer(content: MapBadge(text: pin.badge, symbol: IconCatalog.symbol(pin.icon) ?? "mappin", selected: pin.id == selected, font: font, targetHeight: targetHeight).environment(\.dynamicTypeSize, typeSize))
            renderer.scale = displayScale
            if let image = renderer.cgImage {
            #if os(iOS)
                view.image = UIImage(cgImage: image, scale: displayScale, orientation: .up)
                view.isAccessibilityElement = true; view.accessibilityLabel = pin.title; view.accessibilityValue = pin.badge
                view.accessibilityTraits = pin.id == selected ? [.button, .selected] : [.button]
            #else
                view.image = NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / displayScale, height: CGFloat(image.height) / displayScale))
                view.setAccessibilityElement(true); view.setAccessibilityLabel(pin.title); view.setAccessibilityRole(.button)
            #endif
            }
        }
        func fit(_ map: MKMapView, visible: CGRect) {
            guard !points.isEmpty else { return }
            var rect = MKMapRect.null
            for point in points {
                let p = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                rect = rect.union(MKMapRect(x: p.x - 500, y: p.y - 500, width: 1000, height: 1000))
            }
            if let fitted = MapCameraGeometry.fit(rect, size: map.bounds.size, visible: visible) { map.setVisibleMapRect(fitted, animated: false) }
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
private struct MapBadge: View {
    let text: String
    let symbol: String
    let selected: Bool
    let font: Font
    let targetHeight: CGFloat
    var body: some View {
        HStack(spacing: 4) { Image(systemName: symbol); if !text.isEmpty { Text(text).fontWeight(.semibold) } }
            .font(font).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, 10).frame(minHeight: max(32, targetHeight - 12))
            .foregroundStyle(selected ? Color.white : .black)
            .background(selected ? Color.black : .white, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
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
