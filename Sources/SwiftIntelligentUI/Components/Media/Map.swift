import SwiftUI
import MapKit
import SwiftLang

enum MapMetrics {
    static let inlineHeight: CGFloat = 400
    static let minimumHeight: CGFloat = 200
    static let maximumHeight: CGFloat = 720
    static let labelWidth: CGFloat = 140

    /// Upstream: min(clamp(200, height ?? 400, 720), max(280, 82vw)).
    /// The renderer supplies its viewport; a standalone map uses its proposal.
    static func height(_ requested: Double?, viewportWidth: CGFloat?) -> CGFloat {
        let value = requested.flatMap { $0.isFinite ? CGFloat($0) : nil } ?? inlineHeight
        let bounded = min(maximumHeight, max(minimumHeight, value))
        guard let width = viewportWidth, width.isFinite, width > 0 else { return bounded }
        return min(bounded, max(280, width * 0.82))
    }
}

private struct MapHeightLayout: Layout {
    let requestedHeight: Double?
    let viewportWidth: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposedWidth = proposal.width.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let viewport = viewportWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let width: CGFloat
        if let knownWidth = proposedWidth ?? viewport { width = knownWidth }
        else {
            let idealWidth = subviews.first?.sizeThatFits(.unspecified).width ?? 0
            width = idealWidth.isFinite ? max(0, idealWidth) : 0
        }
        return CGSize(width: width, height: MapMetrics.height(requestedHeight, viewportWidth: viewport ?? proposedWidth))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

/// Literal selection seeds local state; a binding remains the source of truth.
/// Filtering, fitting and disappearing markers never rewrite that selection.
@MainActor
struct MapSelectionState {
    private(set) var local: String?

    func requested(in context: OpenUIComponentContext) -> String {
        if let binding = context.binding("selected") {
            guard case .string(let value) = binding.wrappedValue else { return "" }
            return value.displayString
        }
        return local ?? context.string("selected") ?? ""
    }

    @discardableResult
    mutating func select(_ label: String, in context: OpenUIComponentContext, points: [MapPoint]) -> Bool {
        guard context.canInteract, points.contains(where: { $0.label == label }) else { return false }
        if let binding = context.binding("selected") {
            let value = Value.string(OpenUIString(label))
            if binding.wrappedValue != value { binding.wrappedValue = value }
        } else { local = label }
        return true
    }

    mutating func literalChanged() { local = nil }
}

enum MapMarkerComponent {
    static var component: OpenUIComponent {
        var lat = Parameter.number("lat"); lat.required = true
        var lng = Parameter.number("lng"); lng.required = true
        return OpenUIComponent(name: "MapMarker", description: "A place on a Map; icon is one emoji, else the pin shows its number.", params: [
            OpenUIParameter.string("label"), lat, lng,
            OpenUIParameter.string("category", required: false), OpenUIParameter.string("icon", required: false)
        ]) { _ in EmptyView() }
    }
}

enum MapComponent {
    static var component: OpenUIComponent {
        var selected = OpenUIParameter.selection("selected", required: false); selected.isBindable = true
        return OpenUIComponent(name: "Map", description: "Street map fitted to its markers. route draws the road path in marker order; selected holds the clicked marker's label.", params: [
            Parameter.array("markers", items: .object([.init(key: "$ref", value: .string("#/$defs/MapMarker"))])),
            OpenUIParameter.flag("route"), selected, Parameter.number("height")
        ]) { NativeMapView(context: $0) }
    }
}

@MainActor private struct NativeMapView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIViewportSize) private var viewport
    @State private var selectionState = MapSelectionState()
    @State private var cameraState = MapCameraState()
    @State private var expandedCameraState = MapCameraState()
    @State private var category: String?
    @State private var fitRevision = 0
    @State private var expansionRevision = 0
    @State private var expanded = false
    @State private var infoOpen = false
    @StateObject private var routes = MapRouteModel()

    private var allPoints: [MapPoint] { MapPoint.decode(context.value("markers"), streaming: context.isStreaming) }
    private var categories: [String] { MapPoint.categories(in: allPoints) }
    private var points: [MapPoint] { allPoints.filter { category == nil || $0.category == category } }
    private var selection: String { selectionState.requested(in: context) }
    private var routeRequest: MapRouteRequest {
        MapRouteRequest(points: points, enabled: context.flag("route") == true && context.canInteract)
    }

    var body: some View {
        MapHeightLayout(requestedHeight: context.presentationNumber("height"), viewportWidth: viewport?.width) {
            scene(expanded: false)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
        #if os(iOS)
        .fullScreenCover(isPresented: $expanded, onDismiss: restoreInlineViewport) {
            scene(expanded: true).background(theme.canvas)
        }
        #else
        .sheet(isPresented: $expanded, onDismiss: restoreInlineViewport) {
            scene(expanded: true)
                .frame(minWidth: 320, idealWidth: 880, minHeight: 400, idealHeight: 760)
                .background(theme.canvas)
        }
        #endif
        .task(id: routeRequest) { routes.load(routeRequest) }
        .onChange(of: context.string("selected")) { _ in selectionState.literalChanged() }
    }

    private func scene(expanded isExpanded: Bool) -> some View {
        MapScene(context: context, points: points, categories: categories, category: category,
                 selection: selection, expanded: isExpanded, infoOpen: infoOpen,
                 camera: isExpanded ? expandedCameraState : cameraState,
                 fitRevision: fitRevision, expansionRevision: expansionRevision,
                 routeRequest: routeRequest, routes: routes,
                 onSelect: select, onCategory: changeCategory, onOverview: overview,
                 onExpansion: { changeExpansion(from: isExpanded) }, onInfo: toggleInfo)
    }

    private func select(_ label: String) -> Bool {
        guard selectionState.select(label, in: context, points: points) else { return false }
        // The public value is always the label, including for duplicate pins.
        if expanded { expanded = false }
        return true
    }

    private func changeCategory(_ value: String?) {
        guard context.canInteract else { return }
        category = value
    }

    private func overview() {
        guard context.canInteract else { return }
        fitRevision += 1
    }

    private func toggleInfo() {
        guard context.isCurrentPresentation else { return }
        infoOpen.toggle()
    }

    private func changeExpansion(from isExpanded: Bool) {
        guard context.isCurrentPresentation, isExpanded || context.canInteract else { return }
        if !isExpanded { expandedCameraState.restore(from: cameraState) }
        expanded = !isExpanded
    }

    private func restoreInlineViewport() {
        guard context.isCurrentPresentation else { return }
        cameraState.restore(from: expandedCameraState)
        expansionRevision += 1
    }
}

/// The two native presentations share selection, filters, information and the
/// component-owned route job. The scene adds no place cards or detail flow.
@MainActor struct MapScene: View {
    let context: OpenUIComponentContext
    let points: [MapPoint]
    let categories: [String]
    let category: String?
    let selection: String
    let expanded: Bool
    let infoOpen: Bool
    let camera: MapCameraState
    let fitRevision: Int
    let expansionRevision: Int
    let routeRequest: MapRouteRequest
    @ObservedObject var routes: MapRouteModel
    let onSelect: (String) -> Bool
    let onCategory: (String?) -> Void
    let onOverview: () -> Void
    let onExpansion: () -> Void
    let onInfo: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openIntelligentUIMapContentInsets) private var contentInsets
    @Environment(\.layoutDirection) private var direction
    @State private var controlsHeight: CGFloat = 0
    @AccessibilityFocusState private var expansionControlFocused: Bool

    private var phase: MapRoutePhase { routes.matches(routeRequest) ? routes.phase : .idle }
    private var drawsRoute: Bool { routes.matches(routeRequest) && !context.isStreaming }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                MapSurface(points: points, category: category, streaming: context.isStreaming,
                           routeRequest: routeRequest, routeLegs: drawsRoute ? routes.legs : [],
                           routeOverlayRevision: drawsRoute ? routes.overlayRevision : -1,
                           selected: selection, cameraState: camera,
                           bottomInset: 18 + (contentInsets?.bottom ?? 0),
                           topInset: max(70, controlsHeight + 24) + (contentInsets?.top ?? 0),
                           leftInset: min(32, max(0, (geometry.size.width - 80) / 4))
                               + ((direction == .rightToLeft ? contentInsets?.trailing : contentInsets?.leading) ?? 0),
                           rightInset: min(32, max(0, (geometry.size.width - 80) / 4))
                               + ((direction == .rightToLeft ? contentInsets?.leading : contentInsets?.trailing) ?? 0),
                           fitRevision: fitRevision, viewportRevision: expansionRevision, displayScale: displayScale,
                           font: theme.labelFont, captionFont: theme.captionFont, targetHeight: theme.minimumControlHeight,
                           typeSize: typeSize, colorScheme: colorScheme, locale: locale, onSelect: onSelect)
                    .allowsHitTesting(context.canInteract)
                VStack(alignment: .leading, spacing: 8) {
                    controls
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            if height.isFinite, height >= 0, abs(height - controlsHeight) > 0.5 { controlsHeight = height }
                        }
                    if infoOpen {
                        ScrollView(.vertical) {
                            Text(infoText).font(theme.captionFont).foregroundStyle(theme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(maxWidth: 340, maxHeight: max(0, geometry.size.height - max(44, controlsHeight) - 44))
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: theme.controlRadius))
                        .accessibilityIdentifier("intelligent-map-info-note")
                    }
                }
                .padding(12)
                if phase == .direct {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Text(SDKStrings.text("map.route.overview", locale: locale))
                                .font(theme.captionFont).foregroundStyle(theme.primaryText)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.regularMaterial, in: Capsule())
                                .accessibilityLabel(routeStatusText)
                                .accessibilityIdentifier("intelligent-map-route-overview")
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 24)
                    .allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(expanded ? "intelligent-map-expanded" : "intelligent-map-inline")
        .accessibilityAction(.escape) { if expanded { onExpansion() } }
        .onAppear { if expanded { expansionControlFocused = true } }
        .onChange(of: expansionRevision) { _ in
            if !expanded { expansionControlFocused = true }
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                if categories.count > 1 { filterMenu.fixedSize(horizontal: true, vertical: false) }
                overviewButton
                infoButton
                Spacer(minLength: 8)
                expansionButton
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    overviewButton
                    infoButton
                    Spacer(minLength: 0)
                    expansionButton
                }
                if categories.count > 1 { filterMenu }
            }
            compactControlsMenu
        }
    }

    private var overviewButton: some View {
        mapButton(SDKStrings.text("map.overview", locale: locale), symbol: "scope",
                  enabled: context.canInteract, action: onOverview)
            .accessibilityIdentifier("intelligent-map-overview")
    }

    private var infoButton: some View {
        mapButton(SDKStrings.text("map.info", locale: locale), symbol: "info.circle",
                  enabled: context.isCurrentPresentation, action: onInfo)
            .accessibilityHint(routeStatusText)
            .accessibilityAddTraits(infoOpen ? .isSelected : [])
            .accessibilityIdentifier("intelligent-map-info")
    }

    private var expansionButton: some View {
        mapButton(SDKStrings.text(expanded ? "map.close" : "map.expand", locale: locale),
                  symbol: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                  enabled: expanded || context.canInteract, action: onExpansion)
            .accessibilityFocused($expansionControlFocused)
            .accessibilityIdentifier(expanded ? "intelligent-map-close" : "intelligent-map-expand")
    }

    private var infoText: String {
        [SDKStrings.text("map.info.instructions", locale: locale), routeStatusText]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var routeStatusText: String {
        switch phase {
        case .idle: return ""
        case .loading: return SDKStrings.text("map.route.loading", locale: locale)
        case .roads: return SDKStrings.text("map.route.roads", locale: locale)
        case .direct: return SDKStrings.text("map.route.direct", locale: locale)
        }
    }

    private var filterMenu: some View {
        Menu { categoryOptions } label: {
            HStack(spacing: 8) {
                Text(category ?? SDKStrings.text("map.all_places", locale: locale)).font(theme.secondaryFont).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.medium)).accessibilityHidden(true)
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
        .foregroundStyle(theme.primaryText).disabled(!context.canInteract)
        .accessibilityLabel(SDKStrings.text("map.filter_category", locale: locale))
        .accessibilityValue(category ?? SDKStrings.text("map.all_places", locale: locale))
        .accessibilityIdentifier("intelligent-map-filter")
    }

    @ViewBuilder private var categoryOptions: some View {
        Button { onCategory(nil) } label: {
            if category == nil { Label(SDKStrings.text("map.all_places", locale: locale), systemImage: "checkmark") }
            else { Text(SDKStrings.text("map.all_places", locale: locale)) }
        }
        ForEach(categories, id: \.self) { item in
            Button { onCategory(item) } label: {
                if category == item { Label(item, systemImage: "checkmark") }
                else { Text(item) }
            }
        }
    }

    /// A very narrow nested map keeps the same actions in one native menu,
    /// leaving its map visible even at the official 200-point minimum height.
    private var compactControlsMenu: some View {
        Menu {
            if categories.count > 1 {
                Menu(SDKStrings.text("map.filter_category", locale: locale)) { categoryOptions }
                    .disabled(!context.canInteract)
            }
            Button(action: onOverview) {
                Label(SDKStrings.text("map.overview", locale: locale), systemImage: "scope")
            }
            .disabled(!context.canInteract)
            Button(action: onInfo) {
                Label(SDKStrings.text("map.info", locale: locale), systemImage: "info.circle")
            }
            Button(action: onExpansion) {
                Label(SDKStrings.text(expanded ? "map.close" : "map.expand", locale: locale),
                      systemImage: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .disabled(!expanded && !context.canInteract)
        } label: {
            Image(systemName: "ellipsis").font(theme.secondaryFont.weight(.medium))
                .frame(minWidth: max(36, theme.minimumControlHeight), minHeight: max(36, theme.minimumControlHeight))
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(theme.fieldBorder, lineWidth: 0.5))
                .contentShape(Circle())
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .foregroundStyle(theme.primaryText).disabled(!context.isCurrentPresentation)
        .accessibilityLabel(SDKStrings.text("map.controls", locale: locale))
        .accessibilityFocused($expansionControlFocused)
        .accessibilityIdentifier("intelligent-map-controls")
    }

    private func mapButton(_ label: String, symbol: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(theme.secondaryFont.weight(.medium))
                .frame(minWidth: max(36, theme.minimumControlHeight), minHeight: max(36, theme.minimumControlHeight))
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(theme.fieldBorder, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(theme.primaryText)
        .accessibilityLabel(label).disabled(!enabled)
    }
}

struct MapPoint: Equatable {
    let id: String
    let label: String
    let latitude: Double
    let longitude: Double
    let category: String
    let icon: String
    let order: Int

    init(id: String, label: String, latitude: Double, longitude: Double, category: String, icon: String, order: Int = 0) {
        self.id = id; self.label = label; self.latitude = latitude; self.longitude = longitude
        self.category = category; self.icon = icon; self.order = order
    }

    struct Geometry: Equatable {
        let latitude: Double
        let longitude: Double
        init(_ point: MapPoint) { latitude = point.latitude; longitude = point.longitude }
    }

    static func displayIcon(_ value: String) -> String? {
        guard let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        let grapheme = String(first)
        guard grapheme.range(of: "\\p{Extended_Pictographic}", options: .regularExpression) != nil else { return nil }
        return grapheme
    }

    static func decode(_ value: Value?, streaming: Bool = false) -> [Self] {
        let flattened = ValueReading.array(value).flatMap { item -> [Value] in
            if case .array(let array) = item { return array.values }; return [item]
        }
        var counts: [String: Int] = [:], keys = Set<String>()
        return flattened.enumerated().compactMap { order, item in
            guard case .element(let element) = item, !streaming || element.isSourceComplete,
                  case .string(let rawLabel) = ValueReading.field(item, "label") else { return nil }
            let label = rawLabel.displayString
            guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let lat = ValueReading.number(ValueReading.field(item, "lat")),
                  let lng = ValueReading.number(ValueReading.field(item, "lng")),
                  (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
            let occurrence = counts[label, default: 0] + 1
            counts[label] = occurrence
            let baseKey = occurrence == 1 ? label : "\(label) (\(occurrence))"
            var key = baseKey, collision = 2
            // A literal label such as "Cafe (2)" can collide with a duplicate's
            // generated key. Native annotation identity must still be unique.
            while !keys.insert(key).inserted { key = "\(baseKey) [\(collision)]"; collision += 1 }
            let category: String
            if case .string(let text) = ValueReading.field(item, "category") {
                category = text.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
            } else { category = "" }
            let icon: String
            if case .string(let text) = ValueReading.field(item, "icon") {
                icon = displayIcon(text.displayString) ?? ""
            } else { icon = "" }
            return Self(id: key, label: label, latitude: lat, longitude: lng,
                        category: category, icon: icon, order: order)
        }
    }

    static func categories(in points: [Self]) -> [String] {
        var seen = Set<String>()
        return points.compactMap { point in
            guard !point.category.isEmpty, seen.insert(point.category).inserted else { return nil }
            return point.category
        }
    }
}

final class MapCameraState {
    var fitRevision = 0
    var bottomInset: CGFloat = 0
    var topInset: CGFloat = 70
    var leftInset: CGFloat = 0
    var rightInset: CGFloat = 0
    enum Mode { case overview, manual }
    var mode: Mode = .overview
    var currentRect: MKMapRect?
    var displayedPoints: [MapPoint] = []
    var displayedCategory: String?
    var overviewRect: MKMapRect?
    var fittedSize: CGSize = .zero
    var wasStreaming = false
    var anchored = false

    func shouldFit(pointsChanged: Bool, explicitFit: Bool, streaming: Bool) -> Bool {
        explicitFit || (!streaming && mode == .overview && (overviewRect == nil || pointsChanged || wasStreaming))
    }

    /// Native expansion uses another MKMapView. Transfer only its viewport
    /// record; route and selection remain owned by the component above both.
    func restore(from other: MapCameraState) {
        mode = other.mode; currentRect = other.currentRect; overviewRect = other.overviewRect
        fittedSize = other.fittedSize; displayedPoints = other.displayedPoints
        displayedCategory = other.displayedCategory
        fitRevision = other.fitRevision; wasStreaming = other.wasStreaming; anchored = other.anchored
    }
}

enum MapCameraGeometry {
    static func contentBounds(points: [MapPoint]) -> MKMapRect? {
        guard !points.isEmpty else { return nil }
        var rect = MKMapRect.null
        for point in points {
            let location = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            rect = rect.union(MKMapRect(x: location.x - 500, y: location.y - 500, width: 1000, height: 1000))
        }
        return rect
    }

    static func visibleArea(size: CGSize, top: CGFloat, bottom: CGFloat, left: CGFloat = 0, right: CGFloat = 0) -> CGRect? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              top.isFinite, bottom.isFinite, left.isFinite, right.isFinite else { return nil }
        let side = min(40, size.width / 4)
        let width = size.width - 2 * side - max(0, left) - max(0, right)
        let height = size.height - max(0, top) - max(0, bottom) - 32
        guard width > 0, height > 0 else { return nil }
        return CGRect(x: side + max(0, left), y: max(0, top), width: width, height: height)
    }

    static func fit(_ content: MKMapRect, size: CGSize, visible: CGRect, maximumZoom: Double = 13) -> MKMapRect? {
        guard !content.isNull, content.origin.x.isFinite, content.origin.y.isFinite,
              content.width > 0, content.height > 0, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, visible.midX.isFinite, visible.midY.isFinite,
              visible.width.isFinite, visible.height.isFinite, visible.width > 0, visible.height > 0 else { return nil }
        guard let minimumScale = normalizedScale(zoom: maximumZoom) else { return nil }
        let scale = max(content.width / Double(visible.width), content.height / Double(visible.height), minimumScale)
        guard scale.isFinite, scale > 0 else { return nil }
        let x = content.midX - Double(visible.midX) * scale, y = content.midY - Double(visible.midY) * scale
        let width = Double(size.width) * scale, height = Double(size.height) * scale
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else { return nil }
        return MKMapRect(x: x, y: y, width: width, height: height)
    }

    static func anchored(at center: MKMapPoint, size: CGSize, zoom: Double = 10.5) -> MKMapRect? {
        guard center.x.isFinite, center.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, let scale = normalizedScale(zoom: zoom) else { return nil }
        let width = Double(size.width) * scale, height = Double(size.height) * scale
        guard width.isFinite, height.isFinite else { return nil }
        return MKMapRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// MapLibre's 512-point tiles define the upstream zoom convention. This
    /// normalizes that camera scale to MapKit's world, not Apple's tile styling.
    private static func normalizedScale(zoom: Double) -> Double? {
        guard zoom.isFinite else { return nil }
        let scale = MKMapRect.world.width / (512 * pow(2, zoom))
        return scale.isFinite && scale > 0 ? scale : nil
    }

    /// Preserve center and zoom when a window or presentation changes size.
    static func resized(_ rect: MKMapRect, from previousSize: CGSize, to size: CGSize) -> MKMapRect? {
        guard !rect.isNull, rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0,
              previousSize.width.isFinite, previousSize.width > 0,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let scale = rect.width / Double(previousSize.width)
        let width = Double(size.width) * scale, height = Double(size.height) * scale
        guard width.isFinite, height.isFinite else { return nil }
        return MKMapRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
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
}

@MainActor private struct MapSurface {
    let points: [MapPoint]
    let category: String?
    let streaming: Bool
    let routeRequest: MapRouteRequest
    let routeLegs: [MapRouteLeg]
    let routeOverlayRevision: Int
    let selected: String
    let cameraState: MapCameraState
    let bottomInset: CGFloat
    let topInset: CGFloat
    let leftInset: CGFloat
    let rightInset: CGFloat
    let fitRevision: Int
    let viewportRevision: Int
    let displayScale: CGFloat
    let font: Font
    let captionFont: Font
    let targetHeight: CGFloat
    let typeSize: DynamicTypeSize
    let colorScheme: ColorScheme
    let locale: Locale
    let onSelect: (String) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeMap(_ coordinator: Coordinator) -> MKMapView {
        let map = MapCanvas()
        map.delegate = coordinator
        map.showsUserLocation = false
        map.showsCompass = false
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.pointOfInterestFilter = .excludingAll
        coordinator.map = map
        map.onViewportChange = { [weak coordinator] map in coordinator?.requestViewport(map) }
        map.register(MapPinView.self, forAnnotationViewWithReuseIdentifier: "place")
        return map
    }

    func update(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.onSelect = onSelect
        #if os(iOS)
        map.layoutMargins = UIEdgeInsets(top: max(0, topInset), left: max(16, leftInset),
                                        bottom: max(8, bottomInset), right: max(16, rightInset))
        #endif
        coordinator.displayScale = displayScale
        coordinator.locale = locale
        coordinator.cameraState = cameraState
        coordinator.font = font; coordinator.captionFont = captionFont; coordinator.targetHeight = targetHeight
        coordinator.typeSize = typeSize; coordinator.colorScheme = colorScheme
        let pointsChanged = coordinator.points != points
        let geometryChanged = cameraState.displayedPoints.map(MapPoint.Geometry.init) != points.map(MapPoint.Geometry.init)
        let categoryChanged = cameraState.displayedCategory != category
        let explicitFit = cameraState.fitRevision != fitRevision
        let insetsChanged = abs(cameraState.bottomInset - bottomInset) > 1 || abs(cameraState.topInset - topInset) > 1
            || abs(cameraState.leftInset - leftInset) > 1 || abs(cameraState.rightInset - rightInset) > 1
        let routeChanged = coordinator.routeRequest != routeRequest || coordinator.routeOverlayRevision != routeOverlayRevision
        let chromeChanged = coordinator.viewportRestored && insetsChanged && !streaming && cameraState.mode == .overview
        let shouldFit = cameraState.shouldFit(pointsChanged: geometryChanged || categoryChanged || chromeChanged,
                                             explicitFit: explicitFit, streaming: streaming)
        let restore = coordinator.viewportRevision != viewportRevision
        coordinator.viewportRevision = viewportRevision
        coordinator.selected = selected
        coordinator.bottomInset = bottomInset; coordinator.topInset = topInset
        coordinator.leftInset = leftInset; coordinator.rightInset = rightInset
        cameraState.fitRevision = fitRevision; cameraState.bottomInset = bottomInset; cameraState.topInset = topInset
        cameraState.leftInset = leftInset; cameraState.rightInset = rightInset
        cameraState.displayedPoints = points; cameraState.wasStreaming = streaming
        cameraState.displayedCategory = category
        if pointsChanged {
            coordinator.points = points
            let existing = Dictionary(uniqueKeysWithValues: map.annotations.compactMap { $0 as? MapPin }.map { ($0.id, $0) })
            let ids = Set(points.map(\.id))
            map.removeAnnotations(existing.values.filter { !ids.contains($0.id) })
            var added: [MapPin] = []
            for point in points {
                let pin = existing[point.id] ?? MapPin()
                pin.id = point.id; pin.label = point.label; pin.category = point.category
                pin.icon = point.icon; pin.order = point.order
                if pin.coordinate.latitude != point.latitude || pin.coordinate.longitude != point.longitude {
                    pin.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                }
                if existing[point.id] == nil { added.append(pin) }
            }
            map.addAnnotations(added)
        }
        if routeChanged {
            coordinator.routeRequest = routeRequest
            coordinator.routeOverlayRevision = routeOverlayRevision
            coordinator.renderRoute(map, legs: routeLegs)
        }
        // Selection only changes pin appearance. MapKit's programmatic
        // selectAnnotation can pan the map, so it is not used as selection state.
        coordinator.requestViewport(map, fit: shouldFit, explicitFit: explicitFit, restore: restore, resize: insetsChanged)
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        weak var map: MKMapView?
        var points: [MapPoint] = []
        var routeRequest: MapRouteRequest?
        var routeOverlayRevision = -1
        var viewportRevision = 0
        var selected = ""
        var bottomInset: CGFloat = 0
        var topInset: CGFloat = 70
        var leftInset: CGFloat = 0
        var rightInset: CGFloat = 0
        var cameraState: MapCameraState?
        private var fitRequested = false
        private var maximumFitZoom: Double = 13
        private var restoreRequested = false
        var viewportRestored = false
        private var resizeRequested = false
        private var settingViewport = false
        private var viewportScheduled = false
        var displayScale: CGFloat = 2
        var font: Font = .subheadline
        var captionFont: Font = .caption
        var targetHeight: CGFloat = 44
        var typeSize: DynamicTypeSize = .large
        var colorScheme: ColorScheme = .light
        var locale: Locale = .current
        var onSelect: (String) -> Bool

        init(onSelect: @escaping (String) -> Bool) { self.onSelect = onSelect }

        func renderRoute(_ map: MKMapView, legs: [MapRouteLeg]) {
            map.removeOverlays(map.overlays)
            map.addOverlays(legs.map(\.polyline))
        }

        func requestViewport(_ map: MKMapView, fit: Bool = false, explicitFit: Bool = false,
                             restore: Bool = false, resize: Bool = false) {
            fitRequested = fitRequested || fit
            if explicitFit { maximumFitZoom = 14 }
            restoreRequested = restoreRequested || restore
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
                if self.fitRequested {
                    self.fit(map, visible: visible, maximumZoom: self.maximumFitZoom)
                } else if !state.anchored, let first = self.points.first {
                    // Like upstream's initial city overview, anchor the first
                    // finished marker once; later streaming pins do not reframe.
                    let center = MKMapPoint(CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude))
                    if let rect = MapCameraGeometry.anchored(at: center, size: map.bounds.size) {
                        self.setViewport(rect, on: map)
                        state.anchored = true
                    }
                } else if let current = state.currentRect,
                          !self.viewportRestored || self.restoreRequested || self.resizeRequested || state.fittedSize != map.bounds.size {
                    let rect = MapCameraGeometry.resized(current, from: state.fittedSize, to: map.bounds.size) ?? current
                    self.setViewport(rect, on: map)
                }
                self.fitRequested = false; self.restoreRequested = false; self.resizeRequested = false
                self.maximumFitZoom = 13
                state.fittedSize = map.bounds.size; self.viewportRestored = true
                self.refresh(map)
            }
        }

        private func setViewport(_ rect: MKMapRect, on map: MKMapView) {
            settingViewport = true
            map.setVisibleMapRect(rect, animated: false)
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
            // Label-based highlighting is independent of MapKit's one selected
            // annotation, and the same pin must remain clickable after reopening.
            mapView.deselectAnnotation(pin, animated: false)
        }

        private func presentSelection(_ pin: MapPin, map: MKMapView) {
            guard onSelect(pin.label) else { return }
            selected = pin.label
            refresh(map)
        }

        func refresh(_ mapView: MKMapView) {
            OpenIntelligentUIPerformance.record("map.refresh")
            for pin in mapView.annotations.compactMap({ $0 as? MapPin }) {
                if let view = mapView.view(for: pin) { style(view, pin: pin) }
            }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !settingViewport && viewportRestored { cameraState?.mode = .manual }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
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

        func style(_ view: MKAnnotationView, pin: MapPin) {
            let isSelected = pin.label == selected
            view.canShowCallout = false
            view.detailCalloutAccessoryView = nil
            view.collisionMode = .rectangle
            view.displayPriority = .required
            view.zPriority = isSelected ? .max : .defaultUnselected
            #if os(iOS)
            view.isAccessibilityElement = true; view.accessibilityLabel = pin.label
            view.accessibilityValue = pin.category.isEmpty ? nil : pin.category
            view.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
            #else
            view.setAccessibilityElement(true); view.setAccessibilityLabel(pin.label); view.setAccessibilityRole(.button)
            view.setAccessibilityValue([pin.category, isSelected ? SDKStrings.text("map.selected", locale: locale) : ""]
                .filter { !$0.isEmpty }.joined(separator: ", "))
            #endif
            let text = MapPoint.displayIcon(pin.icon) ?? String(pin.order + 1)
            let appearance = MapPinAppearance(text: text, label: pin.label, category: pin.category,
                selected: isSelected, font: font, captionFont: captionFont, targetHeight: targetHeight,
                typeSize: typeSize, colorScheme: colorScheme, displayScale: displayScale)
            if let pinView = view as? MapPinView, pinView.pinAppearance == appearance { return }
            let renderer = ImageRenderer(content: MapAnnotation(text: text, label: pin.label,
                selected: isSelected, font: font, captionFont: captionFont, targetHeight: targetHeight)
                .environment(\.dynamicTypeSize, typeSize).environment(\.colorScheme, colorScheme))
            renderer.scale = displayScale
            if let image = OpenIntelligentUIPerformance.measure("map.rasterize", { renderer.cgImage }) {
                if let pinView = view as? MapPinView {
                    pinView.pinAppearance = appearance
                }
                let badgeHeight = max(32, targetHeight - 12) + 12
                view.centerOffset = CGPoint(x: 0, y: max(0, (CGFloat(image.height) / displayScale - badgeHeight) / 2))
                #if os(iOS)
                view.image = UIImage(cgImage: image, scale: displayScale, orientation: .up)
                #else
                view.image = NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / displayScale, height: CGFloat(image.height) / displayScale))
                #endif
            }
        }

        func fit(_ map: MKMapView, visible: CGRect, maximumZoom: Double) {
            guard let rect = MapCameraGeometry.contentBounds(points: points),
                  let fitted = MapCameraGeometry.fit(rect, size: map.bounds.size, visible: visible, maximumZoom: maximumZoom) else { return }
            cameraState?.overviewRect = fitted
            cameraState?.anchored = true
            // Explicit overview does not undo the user's manual-camera policy.
            setViewport(fitted, on: map)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.lineWidth = 3.2
            renderer.lineCap = .round
            renderer.lineJoin = .round
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
    let selected: Bool
    let font: Font
    let captionFont: Font
    let targetHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(spacing: 2) {
            MapBadge(text: text, selected: selected, font: font, targetHeight: targetHeight)
            Text(label).font(captionFont).foregroundStyle(colorScheme == .dark ? Color.white : Color.black).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: MapMetrics.labelWidth).fixedSize(horizontal: false, vertical: true)
                .shadow(color: colorScheme == .dark ? .black : .white, radius: 2).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
