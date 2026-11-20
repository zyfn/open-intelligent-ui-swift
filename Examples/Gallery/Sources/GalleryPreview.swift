import SwiftUI
import SwiftLang
import SwiftOpenUI
import SwiftIntelligentUI

/// A fixed logical viewport inside a separately scaled workbench canvas.
/// The viewport includes 20 pt of padding on each side of the SDK content.
/// Zoom applies after layout and does not change the content's available width.
@MainActor struct GalleryPreview: View {
    let session: GalleryDocumentSession
    let resources: OpenUIResourceContext
    let viewport: GalleryViewport
    let dynamicType: DynamicTypeSize
    let locale: Locale
    let direction: LayoutDirection
    let museTheme: GalleryDesignSystem.Theme
    let tokens: GalleryThemeTokens?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                document
                    .frame(width: viewport.width, height: viewport.height)
                    .background {
                        if let canvas = tokens?.colorValue("canvas", scheme: scheme)?.color {
                            Rectangle().fill(.background).overlay(canvas)
                        } else {
                            Rectangle().fill(.background)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.16)))
                    .scaleEffect(viewport.zoom, anchor: .topLeading)
                    .frame(width: viewport.scaledWidth, height: viewport.scaledHeight, alignment: .topLeading)
                    .padding(24)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .top)
            }
        }
        .background(Color.secondary.opacity(0.04))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var document: some View {
        if session.kind == .openIntelligentUI {
            ScrollView {
                program.openIntelligentUIReadingContent()
            }
            .openIntelligentUIReadingPosition(enabled: true)
        } else {
            ScrollView { program }
        }
    }

    private var program: some View {
        var presentation = OpenUIPresentation()
        presentation.viewportHeight = viewport.height
        return OpenUIView(state: session.state, library: session.library)
            .openUIResourceContext(resources)
            .openUIPresentation(presentation)
            .openUITheme(lightTheme: tokens?.openUITheme(museTheme, scheme: .light) ?? OpenUITheme(),
                         darkTheme: tokens?.openUITheme(museTheme, scheme: .dark))
            .dynamicTypeSize(dynamicType)
            .environment(\.horizontalSizeClass, viewport.horizontalSizeClass)
            .environment(\.verticalSizeClass, viewport.verticalSizeClass)
            .environment(\.locale, locale)
            .environment(\.layoutDirection, direction)
            .environment(\.openURL, OpenURLAction { url in
                session.recordLink(url)
                return .handled
            })
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GalleryViewportControls: View {
    @Binding var viewport: GalleryViewport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("画布").font(.headline)
                Spacer(minLength: 0)
                Menu {
                    ForEach(GalleryDevice.allCases) { device in
                        Button(device.rawValue) {
                            viewport.width = device.size.0
                            viewport.height = device.size.1
                        }
                    }
                } label: { Label("设备预设", systemImage: "iphone.and.ipad") }
            }
            HStack(spacing: 8) {
                dimension("宽", value: $viewport.width, minimum: 240)
                Text("×").foregroundStyle(.secondary)
                dimension("高", value: $viewport.height, minimum: 320)
                Text("pt").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { viewport.rotate() } label: { Label("横竖切换", systemImage: "rotate.right") }
                    .labelStyle(.iconOnly)
                    .help("横竖切换")
            }
            HStack {
                Text("缩放").font(.subheadline)
                Spacer(minLength: 0)
                Text("\(Int((viewport.zoom * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Slider(value: $viewport.zoom, in: 0.5...1.5, step: 0.05) { Text("画布缩放") }
                Button("100%") { viewport.zoom = 1 }
            }
        }
        .padding(16)
    }

    private func dimension(_ title: String, value: Binding<Double>, minimum: Double) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, value: Binding(
                get: { value.wrappedValue },
                set: { if $0.isFinite { value.wrappedValue = min(1600, max(minimum, $0)) } }
            ), format: .number.precision(.fractionLength(0)))
            .textFieldStyle(.roundedBorder).frame(width: 64)
            .accessibilityLabel("画布" + title + "度，单位 pt")
        }
    }
}
