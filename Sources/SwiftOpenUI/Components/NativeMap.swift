import SwiftLang
import MapKit
import SwiftUI

enum OpenUIGeographicComponents {
    static var map: OpenUIComponent {
        OpenUIComponent(name: "Map", description: "Use when spatial relationships help the user understand content, compare locations, or plan a route. Place data and coordinates must come from reliable sources.", params: [
            OpenUIParameter.slot("points", required: true, accepting: ["MapPoint"]),
            OpenUIParameter.string("crs", required: false, values: ["wgs84", "gcj02"])
        ]) { context in
            NativeComponentHost(context: context) { context in
                if #available(iOS 17, macOS 14, *) { MainActor.assumeIsolated { NativeMap(context: context) } }
                else {
                    NativeMapPlaceholder(theme: context.theme, status: "Map requires iOS 17 or macOS 14")
                        .aspectRatio(1.1, contentMode: .fit)
                        .frame(minHeight: 320, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: context.theme.radius5xl))
                }
            }
        }
    }
    static var mapPoint: OpenUIComponent {
        OpenUIComponent(name: "MapPoint", description: "A geographically locatable place. A name, latitude, and longitude are required.", params: [
            OpenUIParameter.string("title"), OpenUIParameter.number("lat", required: true), OpenUIParameter.number("lng", required: true),
            OpenUIParameter.string("imageSrc", required: false), OpenUIParameter.string("url", required: false),
            OpenUIParameter.string("description", required: false)
        ]) { _ in EmptyView() }
    }
}

private struct NativeMapPlaceholder: View {
    let theme: OpenUIThemeValues
    let status: LocalizedStringKey

    var body: some View {
        theme.sunk.overlay {
            Image(systemName: "map")
                .openUIFont(theme.textBodyDefault)
                .foregroundStyle(theme.textNeutralSecondary.opacity(0.35))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Map", bundle: NativeControlResources.bundle))
        .accessibilityValue(Text(status, bundle: NativeControlResources.bundle))
    }
}

/// Presentation identity is derived locally; the model supplies no ids or groups.
struct NativeMapPlace: Identifiable {
    let id: String
    let number: Int
    let title: String
    let image: String?
    let imageSourceReady: Bool
    let url: String?
    let description: String?
    let coordinate: CLLocationCoordinate2D

    static func decode(_ context: OpenUIComponentContext) -> [Self] {
        let target = context.presentation.mapBasemapCRS
        guard target == nil || context.element.sourceReadiness["crs"].complete else { return [] }
        return decode(context.value("points"),
                      crs: context.presentationString("crs") ?? OpenUIMapCoordinateSystem.gcj02.rawValue,
                      target: target)
    }

    static func decode(_ values: Value?, crs: String, target: OpenUIMapCoordinateSystem? = nil) -> [Self] {
        guard let source = OpenUIMapCoordinateSystem(rawValue: crs) else { return [] }
        let displayCRS = target ?? source
        var seen = Set<String>()
        return NativeValue.array(values).compactMap { value in
            guard case .element(let element) = value, element.typeName == "MapPoint",
                  let title = PropValue.string(element, "title"), !title.isEmpty,
                  ["title", "lat", "lng"].allSatisfy({ element.sourceReadiness[$0].complete }),
                  let lat = NativeMapValue.number(element.props.last { $0.0 == "lat" }?.1), let lng = NativeMapValue.number(element.props.last { $0.0 == "lng" }?.1),
                  lat.isFinite, lng.isFinite, (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
            // Length-prefix the display name and use exact coordinate bits, not
            // an array index, so sorting or appended metadata doesn't change it.
            let declaredID = PropValue.codeUnitString(element, "id")?.wellFormedString
            let id = declaredID.flatMap { $0.isEmpty ? nil : $0 }
                ?? "\(title.utf8.count):\(title):\(lat.bitPattern):\(lng.bitPattern)"
            guard seen.insert(id).inserted else { return nil }
            let imageSourceReady = element.sourceReadiness["imageSrc"].complete
            return Self(id: id, number: seen.count, title: title,
                        image: imageSourceReady ? PropValue.string(element, "imageSrc") : nil,
                        imageSourceReady: imageSourceReady,
                        url: element.isSourceComplete ? PropValue.string(element, "url") : nil,
                        description: PropValue.string(element, "description"),
                        coordinate: NativeMapCoordinates.convert(latitude: lat, longitude: lng, from: source, to: displayCRS))
        }
    }

}

/// A mounted map reuses its ordered places for the same immutable input.
/// A change of target CRS also invalidates the derived coordinates.
final class NativeMapPlaceCache {
    private var last: (element: EvaluatedElement, target: OpenUIMapCoordinateSystem?, places: [NativeMapPlace])?

    func places(for context: OpenUIComponentContext) -> [NativeMapPlace] {
        let target = context.presentation.mapBasemapCRS
        if let last, last.element === context.element, last.target == target { return last.places }
        let places = NativeMapPlace.decode(context)
        last = (context.element, target, places)
        return places
    }
}

@available(iOS 17, macOS 14, *)
private struct NativeMap: View {
    let context: OpenUIComponentContext
    @State private var prepared = NativeMapPlaceCache()

    var body: some View {
        NativeMapView(context: context, places: prepared.places(for: context))
    }
}

@available(iOS 17, macOS 14, *)
private struct NativeMapView: View {
    let context: OpenUIComponentContext
    let places: [NativeMapPlace]
    @State private var localSelection: String?
    @State private var hasUserSelection = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var fullscreenCamera: MapCameraPosition = .automatic
    @State private var expanded = false
    @State private var expandedSourceRevision: Int?
    @ScaledMetric(relativeTo: NativeTextRole.title.textStyle) private var titleScale: CGFloat = 1
    @ScaledMetric(relativeTo: NativeTextRole.caption.textStyle) private var captionScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openUIResourceContext) private var resources
    @Environment(\.openURL) private var openURL
    private var surfaceColor: Color {
        context.theme.foreground
    }
    private var selectedPlace: NativeMapPlace? {
        if let binding = context.presentationBinding("value") {
            guard case .string(let value) = binding.wrappedValue else { return nil }
            return places.first { OpenUIString($0.id) == value }
        }
        return places.first(where: { $0.id == localSelection }) ?? places.first
    }
    private func select(_ id: String) {
        guard context.canInteract, let place = places.first(where: { $0.id == id }) else { return }
        localSelection = id
        hasUserSelection = true
        if let binding = context.presentationBinding("value"), binding.wrappedValue != .string(id) {
            binding.wrappedValue = .string(id)
        }
        context.recordUserInteraction()
        // Use a consistent neighborhood context instead of reusing a region
        // reported by the other (inline/fullscreen) map instance.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            focus(place)
        }
    }
    private func focus(_ place: NativeMapPlace) {
        let position = MapCameraPosition.region(MKCoordinateRegion(center: place.coordinate,
            latitudinalMeters: 1600, longitudinalMeters: 1600))
        camera = position; fullscreenCamera = position
    }
    private func moveSelection(_ offset: Int) {
        let index = (selectedPlace?.number ?? 0) - 1 + offset
        guard places.indices.contains(index) else { return }
        select(places[index].id)
    }
    private func restoreInlineOverview() {
        guard context.isCurrentPresentation,
            expandedSourceRevision == context.presentationSourceRevision else { return }
        expandedSourceRevision = nil
        // Preserve a deliberate selection when returning from the preview.
        camera = .automatic
    }
    private func fitPlaces() {
        if places.count == 1, let place = places.first {
            focus(place)
        } else { camera = .automatic; fullscreenCamera = .automatic }
    }
    private var placeTitleStyle: NativeTextStyle {
        let theme = context.theme
        return .init(font: theme.textBodyDefaultHeavy, color: theme.textNeutralPrimary,
                     role: .title, emphasisWeight: theme.textBodyDefaultHeavy.weight)
    }
    private var textBlockHeight: CGFloat {
        placeTitleStyle.font.measuredLineHeight(scale: titleScale) * 2
            + context.theme.componentStyle.titleDetailGap
            + context.theme.textStyle(.caption).font.measuredLineHeight(scale: captionScale)
    }
    private var cardBaseHeight: CGFloat { max(80, textBlockHeight + 24) }
    var body: some View {
        Group {
            if !places.isEmpty || context.isStreaming {
                Color.clear.aspectRatio(1.1, contentMode: .fit)
                    .frame(minHeight: 320, maxHeight: 360)
                    .overlay {
                        if !places.isEmpty {
                            surface(fullscreen: false)
                        } else {
                            NativeMapPlaceholder(theme: context.theme, status: "Loading")
                                .accessibilityIdentifier("openui.map.pending")
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: context.theme.radius5xl))
                    .overlay(RoundedRectangle(cornerRadius: context.theme.radius5xl).stroke(.primary.opacity(0.06)))
                    .accessibilityIdentifier("openui.map")
                #if os(iOS)
                .fullScreenCover(isPresented: $expanded, onDismiss: restoreInlineOverview) { surface(fullscreen: true) }
                #else
                .sheet(isPresented: $expanded, onDismiss: restoreInlineOverview) { surface(fullscreen: true) }
                #endif
            } else {
                NativeMapPlaceholder(theme: context.theme, status: "No valid locations")
                    .aspectRatio(1.1, contentMode: .fit)
                    .frame(minHeight: 320, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: context.theme.radius5xl))
                    .accessibilityIdentifier("openui.map.empty")
            }
        }
        .onChange(of: selectedPlace?.id, initial: true) { _, id in
            guard context.presentationBinding("value") != nil else { return }
            if let place = places.first(where: { $0.id == id }) { focus(place) }
            else { fitPlaces() }
        }
        .onChange(of: places.map(\.id), initial: true) { _, _ in
            if !places.contains(where: { $0.id == localSelection }) {
                localSelection = context.presentationBinding("value") == nil ? places.first?.id : nil
                hasUserSelection = false
            }
            if context.presentationBinding("value") != nil {
                if selectedPlace == nil { fitPlaces() }
            } else if !hasUserSelection {
                fitPlaces()
            }
        }
        .onChange(of: context.presentationSourceRevision) { _, _ in
            localSelection = context.presentationBinding("value") == nil ? places.first?.id : nil
            hasUserSelection = false
            expanded = false
            expandedSourceRevision = nil
            if context.presentationBinding("value") != nil,
               let place = selectedPlace { focus(place) }
            else { fitPlaces() }
        }
    }
    private func pointMenu(selectedID: String?) -> some View {
        Menu {
            Button { fitPlaces() } label: {
                Label { Text("Show all places", bundle: NativeControlResources.bundle) } icon: { Image(systemName: "scope") }
            }
            ForEach(places) { place in
                Button { select(place.id) } label: {
                    if selectedID == place.id {
                        Label("\(place.number). \(place.title)", systemImage: "checkmark")
                    } else { Text("\(place.number). \(place.title)") }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.body.weight(.medium)).frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(Text("Choose a place", bundle: NativeControlResources.bundle))
        .disabled(!context.canInteract)
    }
    private func groupButton(_ title: LocalizedStringKey, icon: String, disabled: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.medium))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(Text(title, bundle: NativeControlResources.bundle)).disabled(disabled)
    }
    private func capsuleGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0, content: content)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
    }
    private func mapButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.medium))
                .frame(width: 44, height: 44)
                .background(surfaceColor, in: Circle())
                .overlay(Circle().stroke(.primary.opacity(0.06)))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
        }
        .buttonStyle(.plain).accessibilityLabel(Text(title, bundle: NativeControlResources.bundle))
    }
    private func controls(fullscreen: Bool, selection: NativeMapPlace?) -> some View {
        let selectedNumber = selection?.number ?? 0
        return HStack(spacing: 8) {
            if fullscreen {
                mapButton("Close map", icon: "xmark") { expanded = false }
                Spacer(minLength: 0)
                capsuleGroup {
                    groupButton("Previous place", icon: "arrow.left", disabled: selectedNumber <= 1 || !context.canInteract) { moveSelection(-1) }
                    groupButton("Next place", icon: "arrow.right", disabled: selectedNumber >= places.count || !context.canInteract) { moveSelection(1) }
                }
                capsuleGroup {
                    groupButton("Recenter on selection", icon: "location", disabled: selection == nil || !context.canInteract) {
                        if let selection { select(selection.id) }
                    }
                    pointMenu(selectedID: selection?.id)
                }
            } else {
                Spacer(minLength: 8)
                mapButton("Expand map", icon: "arrow.up.left.and.arrow.down.right") {
                    expandedSourceRevision = context.presentationSourceRevision
                    fullscreenCamera = camera; expanded = true
                }
            }
        }.padding(.horizontal, 14).padding(.top, 14)
    }
    private func marker(_ place: NativeMapPlace, selected: Bool) -> some View {
        let width: CGFloat = selected ? 36 : 29
        let height = width * 228 / 200
        let ink = selected ? Color.black : Color.white
        let pin = NativeMapPinShape()
        return Button { select(place.id) } label: {
            ZStack(alignment: .top) {
                pin.fill(selected ? Color.white : Color.black)
                    .overlay(pin.stroke(ink, lineWidth: 1.5))
                Text("\(place.number)")
                    .font(.system(size: selected ? 16 : 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .frame(width: width, height: width)
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .frame(width: 44, height: 48, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!context.canInteract)
        .accessibilityLabel(place.title)
        .accessibilityValue(Text(selected ? "Selected" : "Not selected", bundle: NativeControlResources.bundle))
    }
    private func surface(fullscreen: Bool) -> some View {
        let selection = selectedPlace
        return Map(position: fullscreen ? $fullscreenCamera : $camera, interactionModes: fullscreen ? .all : [.zoom]) {
            ForEach(places) { place in
                Annotation(place.title, coordinate: place.coordinate, anchor: .bottom) {
                    marker(place, selected: selection?.id == place.id)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .safeAreaInset(edge: .top, spacing: 0) { controls(fullscreen: fullscreen, selection: selection) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selection { pages(selectedID: selection.id).padding(.bottom, 12) }
        }
    }
    private func pages(selectedID: String) -> some View {
        MapPlaceCarousel(places: places, selectedID: selectedID, minimumHeight: cardBaseHeight,
                         surfaceColor: surfaceColor, onSelect: select) { page($0, width: $1) }
    }
    private func page(_ place: NativeMapPlace, width: CGFloat) -> some View {
        let side = min(72, max(48, width * 0.20))
        let rowHeight = max(side, textBlockHeight)
        return HStack(spacing: 10) {
            NativeMapPlaceArtwork(source: place.image, title: place.title, side: side)
                .environment(\.openUIMediaSourceReady, place.imageSourceReady)
            VStack(alignment: .leading, spacing: context.theme.componentStyle.titleDetailGap) {
                Text(place.title).nativeTextStyle(placeTitleStyle).lineLimit(2)
                if let description = place.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(description).nativeTextStyle(context.theme.textStyle(.caption)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: rowHeight, alignment: .leading)
            .clipped()
            if let address = place.url, let url = NativeMapValue.url(address, baseURL: resources.baseURL) {
                Button {
                    guard context.canInteract else { return }
                    openURL(url)
                } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold))
                        .foregroundStyle(.secondary).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!context.canInteract)
                .accessibilityLabel(Text("Details for \(place.title)", bundle: NativeControlResources.bundle))
                .accessibilityIdentifier("openui.map.details")
            } else {
                // Reserve the URL action's space while optional metadata arrives.
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true).allowsHitTesting(false)
            }
        }
        // Reserve the same row for every card. Streaming or long descriptions
        // can change text, never the card's geometry or the photo column.
        .frame(maxWidth: .infinity).frame(height: rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("openui.map.place-card." + place.id)
    }

}

private struct NativeMapPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Match the Creative marker's 200 × 228 SVG silhouette.
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 200,
                    y: rect.minY + rect.height * y / 228)
        }
        var path = Path()
        path.move(to: point(99.5556, 0))
        path.addCurve(to: point(0, 99.0293), control1: point(44.5724, 0.071111), control2: point(0, 44.3733))
        path.addCurve(to: point(92.5724, 226.361), control1: point(0, 177.607), control2: point(71.3956, 217.173))
        path.addCurve(to: point(98.3182, 227.556), control1: point(94.4071, 227.157), control2: point(96.3698, 227.556))
        path.addCurve(to: point(99.5556, 227.428), control1: point(98.7307, 227.556), control2: point(99.1431, 227.47))
        path.addCurve(to: point(100.793, 227.556), control1: point(99.968, 227.456), control2: point(100.38, 227.556))
        path.addCurve(to: point(106.539, 226.361), control1: point(102.741, 227.556), control2: point(104.704, 227.157))
        path.addCurve(to: point(199.111, 99.0293), control1: point(127.716, 217.188), control2: point(199.111, 177.607))
        path.addCurve(to: point(99.5556, 0), control1: point(199.111, 44.3733), control2: point(154.553, 0.071111))
        path.closeSubpath()
        return path
    }
}

/// The location remains useful without photography. Reuse the same resource
/// pipeline and fixed thumbnail slot for missing, pending and failed images;
/// do not guess place categories from model-authored names or descriptions.
struct NativeMapPlaceArtwork: View {
    let source: String?
    let title: String
    let side: CGFloat

    var body: some View {
        NativeRemoteImage(src: source, alt: title,
            layout: .thumbnail(CGSize(width: side, height: side)),
            fallbackSystemImage: "mappin.and.ellipse")
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("openui.map.place-artwork")
    }
}

/// Each presented map owns its own viewport. Sharing the scroll-position
/// binding between inline and fullscreen views leaves a new view at page one.
@available(iOS 17, macOS 14, *)
private struct MapPlaceCarousel<Page: View>: View {
    let places: [NativeMapPlace]
    let selectedID: String
    let minimumHeight: CGFloat
    let surfaceColor: Color
    let onSelect: (String) -> Void
    @ViewBuilder let page: (NativeMapPlace, CGFloat) -> Page
    @State private var scrolledID: String?
    @State private var pageHeights: [String: CGFloat] = [:]
    @Environment(\.openUITheme) private var theme

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: max(0, theme.radius5xl - 9))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(places) { place in
                            let width = places.count > 1 ? max(200, geometry.size.width - 56) : max(1, geometry.size.width - 28)
                            page(place, width).padding(12)
                                .frame(width: width, alignment: .leading)
                                .background(surfaceColor, in: cardShape)
                                .overlay(cardShape.stroke(.primary.opacity(0.06)))
                                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                                .fixedSize(horizontal: false, vertical: true)
                                .background(GeometryReader { card in
                                    Color.clear.preference(key: PageHeight.self, value: [place.id: card.size.height])
                                })
                                .id(place.id)
                        }
                    }.scrollTargetLayout()
                }
                .contentMargins(.horizontal, 14, for: .scrollContent)
                .scrollIndicators(.hidden).scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledID, anchor: .leading)
                .onAppear {
                    scrolledID = selectedID
                    proxy.scrollTo(selectedID, anchor: .leading)
                }
                .onChange(of: selectedID) { _, id in
                    if scrolledID != id {
                        scrolledID = id
                        proxy.scrollTo(id, anchor: .leading)
                    }
                }
                .onChange(of: places.map(\.id)) { _, _ in
                    scrolledID = selectedID
                    proxy.scrollTo(selectedID, anchor: .leading)
                }
                .onChange(of: scrolledID) { _, id in
                    if let id, id != selectedID { onSelect(id) }
                }
            }
        }
        .frame(height: min(260, max(minimumHeight, places.compactMap { pageHeights[$0.id] }.max() ?? minimumHeight)))
        .onPreferenceChange(PageHeight.self) { pageHeights.merge($0, uniquingKeysWith: { _, new in new }) }
        .accessibilityIdentifier("openui.map.placeCards")
    }
}
private struct PageHeight: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

enum NativeMapCoordinates {
    static func convert(latitude: Double, longitude: Double, from source: OpenUIMapCoordinateSystem,
                        to target: OpenUIMapCoordinateSystem) -> CLLocationCoordinate2D {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard source != target,
              NativeMapCoordinateCoverage.contains(latitude: latitude, longitude: longitude) else {
            return coordinate
        }
        if target == .gcj02 { return gcj02(latitude: latitude, longitude: longitude) }
        var estimate = coordinate
        for _ in 0..<10 {
            let projected = gcj02(latitude: estimate.latitude, longitude: estimate.longitude)
            let deltaLat = projected.latitude - latitude, deltaLng = projected.longitude - longitude
            estimate.latitude -= deltaLat; estimate.longitude -= deltaLng
            if max(abs(deltaLat), abs(deltaLng)) < 1e-9 { break }
        }
        return estimate
    }
    private static func gcj02(latitude: Double, longitude: Double) -> CLLocationCoordinate2D {
        let x = longitude - 105, y = latitude - 35, pi = Double.pi
        var dLat = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        dLat += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3 + (20*sin(y*pi) + 40*sin(y*pi/3))*2/3 + (160*sin(y*pi/12) + 320*sin(y*pi/30))*2/3
        var dLng = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        dLng += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3 + (20*sin(x*pi) + 40*sin(x*pi/3))*2/3 + (150*sin(x*pi/12) + 300*sin(x*pi/30))*2/3
        let rad = latitude*pi/180, axis = 6378245.0, e = 0.00669342162296594323
        let magic = 1-e*sin(rad)*sin(rad)
        dLat = dLat*180/(axis*(1-e)/(magic*sqrt(magic))*pi)
        dLng = dLng*180/(axis/sqrt(magic)*cos(rad)*pi)
        return .init(latitude: latitude+dLat, longitude: longitude+dLng)
    }
}

/// Resource links are host navigation, not map selection actions.
enum NativeMapValue {
    static func number(_ value: Value?) -> Double? {
        guard case .number(let number) = value, number.isFinite else { return nil }
        return number
    }
    static func url(_ source: String, baseURL: URL?) -> URL? {
        guard let url = URL(string: source, relativeTo: baseURL)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
