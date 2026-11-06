import SwiftUI
import OpenUILang

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
    @Entry var intelligentUIImageAlbum: [ImageAlbumItem] = []
}

struct ImagePreview: View {
    let image: Image
    let alt: String
    var source: String? = nil
    var album: [ImageAlbumItem] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.intelligentUITheme) private var theme
    @State private var zoom: CGFloat = 1
    @State private var startingZoom: CGFloat = 1
    @Environment(\.intelligentUIImages) private var images
    @State private var selectedSource: String?
    @State private var decoded: CGImage?
    @State private var decodedSource: String?
    @State private var failed = false
    @State private var retry = 0
    private var currentSource: String? { selectedSource ?? source }
    private var currentAlt: String { album.first { $0.source == currentSource }?.alt ?? alt }
    private var index: Int? { album.firstIndex { $0.source == currentSource } }
    private var currentImage: Image? {
        if currentSource == source { return image }
        if let currentSource, let supplied = images[currentSource] { return supplied }
        if let decoded, decodedSource == currentSource { return Image(decorative: decoded, scale: 1) }
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
                        .accessibilityValue("\(Int(zoom * 100))%")
                        .accessibilityAction(named: "还原大小") { setZoom(1) }
                        .gesture(MagnificationGesture().onChanged { zoom = min(4, max(1, startingZoom * $0)) }.onEnded { _ in startingZoom = zoom })
                        .onTapGesture(count: 2) { setZoom(zoom > 1 ? 1 : 2) }
                  } else if failed { ImageFailurePlaceholder(alt: currentAlt, status: "图片暂不可用", retry: { retry += 1 }).frame(width: geometry.size.width, height: geometry.size.height) }
                  else { ImageLoadingPlaceholder(alt: currentAlt, surface: theme.surface).frame(width: geometry.size.width, height: geometry.size.height) }
                }
            }
            .background(theme.canvas)
            .navigationTitle(currentAlt)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }.accessibilityLabel("关闭大图")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if album.count > 1, let index {
                        Button { selectedSource = album[index - 1].source } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("上一张图片").disabled(index == 0)
                        Button { selectedSource = album[index + 1].source } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("下一张图片").disabled(index == album.count - 1)
                    }
                    Button { setZoom(zoom - 0.5) } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("缩小图片").disabled(zoom <= 1)
                    Button { setZoom(zoom + 0.5) } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("放大图片").disabled(zoom >= 4)
                }
            }
            .tint(theme.actionAccent)
            .task(id: (currentSource ?? "") + "#" + String(retry)) {
                setZoom(1); failed = false; decoded = nil; decodedSource = nil
                guard let currentSource, currentSource != source, images[currentSource] == nil else { return }
                guard let url = URL(string: currentSource), ["http", "https"].contains(url.scheme ?? "") else { failed = true; return }
                do {
                    let result = try await ImagePipeline.shared.load(url)
                    guard !Task.isCancelled else { return }
                    decoded = result; decodedSource = currentSource
                } catch { if !Task.isCancelled { failed = true } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
    private func setZoom(_ value: CGFloat) { zoom = min(4, max(1, value)); startingZoom = zoom }
}
