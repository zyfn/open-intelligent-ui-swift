import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum ImageComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Image", description: "Image from a supplied HTTP(S) URL or exact caller-provided image key. Generate Image(src, alt) only: the SDK chooses framing from its enclosing layout, never source dimensions. Loading uses shimmer; failures use quiet retry without visible text. Legacy optional presentation arguments remain readable. No search or substitution.", params: [
            OpenUIParameter.string("src"), OpenUIParameter.string("alt"),
            Parameter.number("aspectRatio", minimum: 0.2, maximum: 5),
            Parameter.radius(),
            OpenUIParameter.string("fit", required: false, values: ["cover", "contain"]),
            OpenUIParameter.flag("preview")
        ]) { context in
            SourceImageComponentView(context: context)
        }
    }
}

private struct SourceImageComponentView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.intelligentUIEditorial) private var editorial
    @Environment(\.intelligentUIInteractiveContent) private var interactive
    private var ratio: CGFloat { CGFloat(context.number("aspectRatio").map { min(5, max(0.2, $0)) } ?? Double(editorial.mediaRatio ?? theme.coverImageAspectRatio)) }
    var body: some View {
      if !context.element.isSourceComplete {
        Rectangle().fill(theme.surface).aspectRatio(ratio, contentMode: .fit)
            .overlay { ImageLoadingPlaceholder(alt: context.string("alt") ?? "图片", surface: theme.surface) }
            .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
      } else {
        SourceImage(source: context.string("src"), alt: context.string("alt") ?? "图片",
                    ratio: ratio,
                    radius: theme.radius(named: context.string("radius"), points: context.number("radius"), fallback: theme.cornerRadius),
                    fit: context.string("fit") == "contain" ? .fit : .fill,
                    allowsPreview: (context.flag("preview") ?? true) && !interactive)
      }
    }
}

extension EnvironmentValues {
    @Entry public var intelligentUIImages: [String: Image] = [:]
}

extension View {
    /// Exact source-key overrides supplied by the caller, scoped to this view.
    public func intelligentUIImages(_ images: [String: Image]) -> some View {
        environment(\.intelligentUIImages, images)
    }
}

struct SourceImage: View {
    let source: String?
    let alt: String
    var ratio: CGFloat = 1.5
    var radius: CGFloat = 12
    var fit: ContentMode = .fit
    var allowsPreview = true
    var fillsContainBackground = false
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.intelligentUIImages) private var images
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.intelligentUIScrolling) private var readingScroll
    @Environment(\.intelligentUIImageAlbum) private var album
    @Environment(\.intelligentUIInteractiveContent) private var interactive
    @State private var decodedImage: CGImage?
    @State private var decodedSource: String?
    @State private var failedSource: String?
    @State private var retry = 0
    @State private var previewPresented = false
    @State private var edgeImage: CGImage?
    @State private var edgeKey: String?
    private var extendsEdges: Bool { fit == .fit && fillsContainBackground }
    private var loadKey: String { (source ?? "") + "#" + String(retry) + "#" + String(Double(ratio)) + "#" + String(extendsEdges) }
    private var previewImage: Image? {
        if let source, let image = images[source] { return image }
        if let decodedImage, decodedSource == source { return Image(decorative: decodedImage, scale: 1) }
        return nil
    }
    private var url: URL? {
        guard let source, let url = URL(string: source),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }
    var body: some View {
        Rectangle().fill(theme.surface)
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    if let source, let image = images[source] {
                        if !extendsEdges { picture(image, size: geometry.size) }
                        else if edgeKey == loadKey { picture(edgeImage.map { Image(decorative: $0, scale: 1) } ?? image, size: geometry.size) }
                        else { ImageLoadingPlaceholder(alt: alt, surface: theme.surface) }
                    } else if url != nil {
                        if let decodedImage, decodedSource == source {
                            picture(Image(decorative: extendsEdges && edgeKey == loadKey ? edgeImage ?? decodedImage : decodedImage, scale: 1), size: geometry.size).transition(.opacity)
                        } else if failedSource == source {
                            ImageFailurePlaceholder(alt: alt, status: "图片暂不可用", retry: { retry += 1 })
                        } else { ImageLoadingPlaceholder(alt: alt, surface: theme.surface) }
                    } else {
                        placeholder("缺少有效图片来源")
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .intelligentUILayoutTrace("source-image", "ratio=\(LayoutTrace.number(ratio))")
            .sheet(isPresented: $previewPresented) {
                if let image = previewImage { ImagePreview(image: image, alt: alt, source: source, album: album) }
            }
            .onChange(of: source) { _ in previewPresented = false }
            .task(id: loadKey) {
                decodedImage = nil; decodedSource = nil; failedSource = nil
                edgeImage = nil; edgeKey = nil
                guard let source else { return }
                let key = loadKey, targetRatio = ratio
                if let image = images[source] {
                    guard extendsEdges else { return }
                    let original = ImageRenderer(content: image).cgImage
                    let framed = await Task.detached(priority: .utility) { original.flatMap { ImageFraming.contained($0, ratio: targetRatio) } }.value
                    guard !Task.isCancelled else { return }
                    edgeImage = framed; edgeKey = key
                    return
                }
                guard let url else { return }
                do {
                    let image = try await ImagePipeline.shared.load(url)
                    let framed = extendsEdges ? await Task.detached(priority: .utility) { ImageFraming.contained(image, ratio: targetRatio) }.value : nil
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        decodedImage = image; decodedSource = source
                        edgeImage = framed; edgeKey = key
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    failedSource = source
                }
            }
    }
    @ViewBuilder private func picture(_ image: Image, size: CGSize) -> some View {
        if allowsPreview && !interactive {
            Button { if !readingScroll { previewPresented = true } } label: { imageContent(image, size: size) }
                .buttonStyle(.plain)
                .accessibilityLabel(alt).accessibilityHint("查看大图")
        } else {
            imageContent(image, size: size).accessibilityLabel(alt)
        }
    }
    private func imageContent(_ image: Image, size: CGSize) -> some View {
        image.resizable().aspectRatio(contentMode: fit).frame(width: size.width, height: size.height).clipped()
    }
    private func placeholder(_ status: String) -> some View {
        ImageFailurePlaceholder(alt: alt, status: status)
    }
}

struct ImageFailurePlaceholder: View {
    let alt: String
    let status: String
    var retry: (() -> Void)? = nil
    @Environment(\.intelligentUITheme) private var theme

    var body: some View {
        Image(systemName: "photo")
            .foregroundStyle(theme.secondaryText.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(alt + "，" + status)
            .background(theme.surface)
            .overlay(alignment: .bottomTrailing) {
                if let retry {
                    Button(action: retry) { Image(systemName: "arrow.clockwise").frame(minWidth: theme.minimumControlHeight, minHeight: theme.minimumControlHeight) }
                        .buttonStyle(.borderless).tint(theme.actionAccent).accessibilityLabel("重新加载图片")
                }
            }
    }
}

struct ImageLoadingPlaceholder: View {
    let alt: String
    let surface: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            surface
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                  GeometryReader { geometry in
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                    LinearGradient(colors: [.clear, .white.opacity(colorScheme == .dark ? 0.08 : 0.5), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(70, geometry.size.width * 0.7))
                        .offset(x: geometry.size.width * (phase * 2.2 - 1))
                  }
                }
                .clipped()
            }
            ProgressView().tint(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(alt + "，正在载入图片")
    }
}
