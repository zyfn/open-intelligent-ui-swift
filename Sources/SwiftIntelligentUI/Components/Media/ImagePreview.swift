import SwiftUI
import SwiftLang

struct ImageAlbumItem: Identifiable, Equatable {
    let source: String
    let alt: String
    var id: String { source }
    static func collect(_ values: [Value]) -> [Self] {
        var result: [Self] = [], seen = Set<String>()
        func visit(_ value: Value) {
            if case .array(let items) = value { for item in items { visit(item) } }
            else if case .element(let element) = value {
                if element.typeName == "Image" {
                    let source = ValueReading.string(ValueReading.field(value, "src"))
                    if !source.isEmpty && seen.insert(source).inserted { result.append(.init(source: source, alt: ValueReading.string(ValueReading.field(value, "alt")))) }
                } else if ["Col", "Row", "Grid", "Box", "Card", "Carousel"].contains(element.typeName) {
                    if let children = ValueReading.field(value, "children") { visit(children) }
                }
            }
        }
        values.forEach(visit)
        return result
    }
}

extension EnvironmentValues {
    @Entry var openIntelligentUIImageAlbum: [ImageAlbumItem] = []
}

struct ImagePreview: View {
    @Environment(\.locale) private var locale
    let image: Image
    let alt: String
    var source: String? = nil
    var album: [ImageAlbumItem] = []
    var sourceTarget: ImageResourceTarget? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openIntelligentUIImages) private var images
    @Environment(\.openIntelligentUIImageRevisions) private var revisions
    @Environment(\.openUIResourceContext) private var resources
    @State private var zoom: CGFloat = 1
    @State private var startingZoom: CGFloat = 1
    @State private var selectedSource: String?
    @State private var decoded: CGImage?
    @State private var decodedResource: ImageResourceTarget?
    @State private var failed = false
    @State private var retry = 0
    @State private var viewport: CGSize = .zero
    @State private var requestSnapshot: ImageResource?
    private var currentSource: String? { selectedSource ?? source }
    private var currentAlt: String { album.first { $0.source == currentSource }?.alt ?? alt }
    private var index: Int? { album.firstIndex { $0.source == currentSource } }
    private var revision: String { revisions[currentSource ?? ""] ?? "" }
    private var target: ImageResourceTarget { ImageResourceTarget(source: currentSource, resources: resources, revision: revision) }
    private struct LoadKey: Hashable {
        let target: ImageResourceTarget
        let dimension: Int
        let retry: Int
        let viewportReady: Bool
    }
    private var pixelTarget: Int {
        ImagePipeline.effectiveDimension(ImagePixelSize.target(points: viewport, scale: displayScale, zoom: zoom),
            limits: target.scope.limits)
    }
    private var currentImage: Image? {
        guard openUIResourceScopeIsCurrent(resources.loader, authorizationScope: target.scope.authorization) else { return nil }
        if let currentSource, let supplied = images[currentSource] { return supplied }
        if let decoded, decodedResource == target { return Image(decorative: decoded, scale: 1) }
        if currentSource == source, sourceTarget == nil || sourceTarget == target { return image }
        return nil
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    if let currentImage {
                        currentImage.resizable().scaledToFit()
                            .frame(width: max(1, geometry.size.width * zoom), height: max(1, geometry.size.height * zoom))
                            .accessibilityLabel(currentAlt)
                            .accessibilityValue(SDKStrings.text("image.zoom.value", locale: locale, Int(zoom * 100)))
                            .accessibilityAction(named: SDKStrings.text("image.zoom.reset", locale: locale)) { setZoom(1) }
                            .gesture(MagnificationGesture().onChanged { zoom = min(4, max(1, startingZoom * $0)) }.onEnded { _ in startingZoom = zoom })
                            .onTapGesture(count: 2) { setZoom(zoom > 1 ? 1 : 2) }
                            .contextMenu {
                                if failed { Button(SDKStrings.text("image.retry", locale: locale)) { retry &+= 1 } }
                            }
                            .accessibilityActions {
                                if failed { Button(SDKStrings.text("image.retry", locale: locale)) { retry &+= 1 } }
                            }
                    } else if failed {
                        ImageFailurePlaceholder(alt: currentAlt, status: SDKStrings.text("image.unavailable", locale: locale), retry: { retry &+= 1 })
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        ImageLoadingPlaceholder(alt: currentAlt, surface: theme.surface)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .id(currentSource ?? "single-image")
                .onAppear { viewport = geometry.size }
                .onChange(of: geometry.size) { viewport = $0 }
            }
            .background(theme.canvas)
            .navigationTitle(currentAlt)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SDKStrings.text("common.done", locale: locale)) { dismiss() }.accessibilityLabel(SDKStrings.text("image.preview.close", locale: locale))
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if album.count > 1, let index {
                        Button { move(by: -1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel(SDKStrings.text("image.previous", locale: locale)).disabled(index == 0)
                        Button { move(by: 1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel(SDKStrings.text("image.next", locale: locale)).disabled(index == album.count - 1)
                    }
                    Button { setZoom(zoom - 0.5) } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel(SDKStrings.text("image.zoom.out", locale: locale)).disabled(zoom <= 1)
                    Button { setZoom(zoom + 0.5) } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel(SDKStrings.text("image.zoom.in", locale: locale)).disabled(zoom >= 4)
                }
            }
            .tint(theme.actionAccent)
            .onChange(of: currentSource) { _ in
                setZoom(1); decoded = nil; decodedResource = nil; failed = false
            }
            .onChange(of: album) { items in
                if let selectedSource, !items.contains(where: { $0.source == selectedSource }) {
                    self.selectedSource = items.contains(where: { $0.source == source }) ? source : items.first?.source
                }
            }
            .task(id: LoadKey(target: target, dimension: pixelTarget, retry: retry,
                              viewportReady: viewport.width > 0 && viewport.height > 0)) {
                failed = false
                if decodedResource != target { decoded = nil; decodedResource = nil }
                guard viewport.width > 0, viewport.height > 0,
                      let currentSource, images[currentSource] == nil else { return }
                let request: ImageResource
                if let retained = requestSnapshot, retained.id.target == target,
                   retained.id.attempt == retry, retained.isCurrent {
                    request = retained
                } else {
                    request = ImageResource(source: currentSource, resources: resources, revision: revision, attempt: retry)
                    requestSnapshot = request
                }
                guard request.id.request != nil else {
                    failed = currentSource != source; return
                }
                let key = target
                do {
                    let result = try await ImagePipeline.shared.load(request, maximumDimension: pixelTarget)
                    guard !Task.isCancelled else { return }
                    decoded = result; decodedResource = key
                } catch { if !Task.isCancelled { failed = true } }
            }
            .onDisappear { decoded = nil; decodedResource = nil }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
    private func move(by offset: Int) {
        guard let index, album.indices.contains(index + offset) else { return }
        selectedSource = album[index + offset].source
    }
    private func setZoom(_ value: CGFloat) { zoom = min(4, max(1, value)); startingZoom = zoom }
}
