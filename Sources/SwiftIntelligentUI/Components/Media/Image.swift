import SwiftUI
import SwiftLang

enum ImageComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Image", description: "Image from a supplied HTTP(S) URL or exact caller-provided image key. Optional aspectRatio, radius and fit control framing; defaults are a 3:2 cover and lg radius. A direct Row photo or a Row's photo-only Box uses the library's responsive media width and 4:3 ratio. Loading and retryable failure preserve geometry. Never invent a source URL; no implicit search or substitution.", params: [
            OpenUIParameter.string("src"), OpenUIParameter.string("alt"),
            Parameter.number("aspectRatio"),
            Parameter.radius(),
            OpenUIParameter.string("fit", required: false, values: ["cover", "contain"])
        ]) { context in
            SourceImageComponentView(context: context)
        }
    }
}

private struct SourceImageComponentView: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIEditorial) private var editorial
    @Environment(\.openIntelligentUIRowMediaAspectRatio) private var rowMediaRatio
    @Environment(\.openIntelligentUIInteractiveContent) private var interactive
    @Environment(\.openIntelligentUIImagePresentations) private var presentations
    private var presentation: OpenIntelligentUIImagePresentation? { presentations[context.string("src") ?? ""] }
    private var ratio: CGFloat {
        rowMediaRatio ?? ImagePixelSize.ratio(context.number("aspectRatio") ?? presentation?.aspectRatio,
                                              fallback: editorial.mediaRatio ?? theme.coverImageAspectRatio)
    }
    var body: some View {
        SourceImage(source: context.string("src"), alt: context.string("alt") ?? SDKStrings.text("image.default_label", locale: locale),
                    ratio: ratio,
                    radius: theme.radius(named: context.string("radius"), points: context.number("radius"), fallback: theme.radiusLG),
                    fit: (context.string("fit") ?? presentation?.fit?.rawValue) == "contain" ? .fit : .fill,
                    allowsPreview: !interactive, sourceReady: context.element.isSourceComplete)
    }
}

extension EnvironmentValues {
    @Entry public var openIntelligentUIImages: [String: Image] = [:]
}

extension View {
    /// Exact source-key overrides supplied by the caller, scoped to this view.
    public func openIntelligentUIImages(_ images: [String: Image]) -> some View {
        environment(\.openIntelligentUIImages, images)
    }
}

struct SourceImage: View {
    @Environment(\.locale) private var locale
    let source: String?
    let alt: String
    var ratio: CGFloat = 1.5
    var radius: CGFloat = 12
    var fit: ContentMode = .fit
    var allowsPreview = true
    var fillsContainBackground = false
    var sourceReady = true
    var reloadSource: (() -> Void)? = nil
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIImages) private var images
    @Environment(\.openIntelligentUIImageRevisions) private var revisions
    @Environment(\.openUIResourceContext) private var resources
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openIntelligentUIScrolling) private var readingScroll
    @Environment(\.openIntelligentUIImageAlbum) private var album
    @Environment(\.openIntelligentUIInteractiveContent) private var interactive
    @State private var decodedImage: CGImage?
    @State private var decodedResource: ResourceKey?
    @State private var failedResource: ResourceKey?
    @State private var missingResource: ResourceKey?
    @State private var retry = 0
    @State private var localVersion = 0
    @State private var pixelTarget: Int?
    @State private var previewPresented = false
    @State private var edgeImage: CGImage?
    @State private var edgeKey: FramingKey?
    @State private var requestSnapshot: RequestSnapshot?
    private struct ResourceKey: Hashable { let target: ImageResourceTarget; let localVersion: Int }
    private struct LoadKey: Hashable {
        let resource: ResourceKey
        let dimension: Int?
        let retry: Int
        let ready: Bool
    }
    private struct RequestSnapshot {
        let resource: ResourceKey
        let retry: Int
        let request: ImageResource
    }
    private struct FramingKey: Hashable {
        let resource: ResourceKey
        let ratio: CGFloat
        let extendsEdges: Bool
        let dimension: Int?
        let image: ObjectIdentifier?
        let ready: Bool
    }
    private var extendsEdges: Bool { fit == .fit && fillsContainBackground }
    private var revision: String { revisions[source ?? ""] ?? "" }
    private var target: ImageResourceTarget { ImageResourceTarget(source: source, resources: resources, revision: revision) }
    private var resourceKey: ResourceKey { ResourceKey(target: target, localVersion: localVersion) }
    private var loadKey: LoadKey { LoadKey(resource: resourceKey, dimension: pixelTarget, retry: retry, ready: sourceReady) }
    private var framingKey: FramingKey {
        FramingKey(resource: resourceKey, ratio: ratio, extendsEdges: extendsEdges,
                   dimension: pixelTarget, image: decodedImage.map { ObjectIdentifier($0) }, ready: sourceReady)
    }
    private var suppliedImage: Image? { source.flatMap { images[$0] } }
    private var previewImage: Image? {
        guard openUIResourceScopeIsCurrent(resources.loader, authorizationScope: target.scope.authorization) else { return nil }
        if let suppliedImage { return suppliedImage }
        if let decodedImage, decodedResource == resourceKey { return Image(decorative: decodedImage, scale: 1) }
        return nil
    }
    var body: some View {
        Rectangle().fill(theme.surface)
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    Group {
                        if !sourceReady {
                            ImageLoadingPlaceholder(alt: alt, surface: theme.surface)
                        } else if let image = previewImage {
                            let displayed = extendsEdges && edgeKey == framingKey
                                ? edgeImage.map { Image(decorative: $0, scale: 1) } ?? image : image
                            picture(displayed, size: geometry.size)
                        } else if source?.isEmpty == false, missingResource != resourceKey {
                            if failedResource == resourceKey {
                                ImageFailurePlaceholder(alt: alt, status: SDKStrings.text("image.unavailable", locale: locale), retry: retryImage)
                            } else { ImageLoadingPlaceholder(alt: alt, surface: theme.surface) }
                        } else {
                            ImageFailurePlaceholder(alt: alt, status: SDKStrings.text("image.source_missing", locale: locale), retry: reloadSource)
                        }
                    }
                    .onAppear { updateTarget(geometry.size) }
                    .onChange(of: geometry.size) { updateTarget($0) }
                    .onChange(of: displayScale) { _ in updateTarget(geometry.size) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .openIntelligentUILayoutTrace("source-image", "ratio=\(LayoutTrace.number(ratio))")
            .sheet(isPresented: $previewPresented) {
                if let image = previewImage {
                    ImagePreview(image: image, alt: alt, source: source,
                                 album: album.contains(where: { $0.source == source }) ? album : [],
                                 sourceTarget: target)
                }
            }
            .onChange(of: source) { _ in previewPresented = false }
            .onChange(of: suppliedImage) { _ in localVersion &+= 1; edgeImage = nil; edgeKey = nil }
            .onDisappear {
                if !previewPresented { decodedImage = nil; decodedResource = nil; edgeImage = nil; edgeKey = nil }
            }
            .task(id: loadKey) {
                guard sourceReady else { return }
                if decodedResource != resourceKey { decodedImage = nil; decodedResource = nil }
                failedResource = nil; missingResource = nil
                guard suppliedImage == nil, let pixelTarget else { return }
                let key = resourceKey
                do {
                    let request: ImageResource
                    if let snapshot = requestSnapshot, snapshot.resource == key, snapshot.retry == retry {
                        request = snapshot.request
                    } else {
                        request = ImageResource(source: source, resources: resources, revision: revision, attempt: retry)
                        requestSnapshot = RequestSnapshot(resource: key, retry: retry, request: request)
                    }
                    guard request.id.request != nil else { missingResource = key; return }
                    let image = try await ImagePipeline.shared.load(request, maximumDimension: pixelTarget)
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        decodedImage = image; decodedResource = key
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    failedResource = key
                }
            }
            .task(id: framingKey) {
                guard sourceReady, extendsEdges else { edgeImage = nil; edgeKey = nil; return }
                let key = framingKey
                let original: CGImage?
                if let suppliedImage {
                    let renderer = ImageRenderer(content: suppliedImage.resizable().scaledToFit())
                    let pixels = CGFloat(pixelTarget ?? 1600)
                    renderer.proposedSize = .init(width: pixels, height: pixels)
                    renderer.scale = 1
                    original = renderer.cgImage
                } else { original = decodedResource == resourceKey ? decodedImage : nil }
                guard let original else { return }
                do {
                    let framed = try await ImagePipeline.shared.framed(original, target: target, loader: resources.loader, ratio: ratio)
                    guard !Task.isCancelled else { return }
                    edgeImage = framed; edgeKey = key
                } catch { /* Keep the intact source over the neutral surface if framing is cancelled. */ }
            }
    }
    private func updateTarget(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        let target = ImagePixelSize.target(points: size, scale: displayScale)
        if pixelTarget != target { pixelTarget = target }
    }
    private func retryImage() {
        if let reloadSource { reloadSource() } else { retry &+= 1 }
    }
    @ViewBuilder private func picture(_ image: Image, size: CGSize) -> some View {
        if allowsPreview && !interactive {
            Button { if !readingScroll { previewPresented = true } } label: { imageContent(image, size: size) }
                .buttonStyle(.plain)
                .accessibilityLabel(alt).accessibilityHint(SDKStrings.text("image.preview", locale: locale))
        } else {
            imageContent(image, size: size).accessibilityLabel(alt)
        }
    }
    private func imageContent(_ image: Image, size: CGSize) -> some View {
        image.resizable().aspectRatio(contentMode: fit).frame(width: size.width, height: size.height).clipped()
    }
}

struct ImageFailurePlaceholder: View {
    @Environment(\.locale) private var locale
    let alt: String
    let status: String
    var retry: (() -> Void)? = nil
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIInteractiveContent) private var interactive

    var body: some View {
        Group {
            if let retry, !interactive {
                Button(action: retry) { placeholder }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibleLabel)
                    .accessibilityValue(status)
                    .accessibilityHint(SDKStrings.text("image.retry", locale: locale))
            } else {
                placeholder
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibleLabel)
                    .accessibilityValue(status)
            }
        }
    }

    private var accessibleLabel: String {
        alt.isEmpty ? SDKStrings.text("image.default_label", locale: locale) : alt
    }

    private var placeholder: some View {
        theme.surface.overlay {
            Image(systemName: "photo")
                .font(.title3).foregroundStyle(theme.secondaryText.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

/// A static media surface shared by source images and the search stage.
/// The parent retains the final media geometry throughout every phase.
struct ImageLoadingPlaceholder: View {
    @Environment(\.locale) private var locale
    let alt: String
    let surface: Color
    var stage: String? = nil
    @Environment(\.openIntelligentUITheme) private var theme

    var body: some View {
        ZStack {
            surface
            Image(systemName: "photo")
                .font(.title3).foregroundStyle(theme.secondaryText.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(alt.isEmpty ? SDKStrings.text("image.default_label", locale: locale) : alt)
        .accessibilityValue(stage ?? SDKStrings.text("image.loading_short", locale: locale))
    }
}
