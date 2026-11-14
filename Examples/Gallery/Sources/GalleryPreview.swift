import SwiftUI
import OpenUICore
import OpenIntelligentSwiftUI

/// A fixed logical viewport inside a separately scaled workbench canvas.
/// The SDK sees viewport.width, never viewport.width * zoom.
@MainActor struct GalleryPreview: View {
    let session: GalleryDocumentSession
    let resources: OpenUIResourceContext
    let viewport: GalleryViewport
    let dynamicType: DynamicTypeSize
    let locale: Locale
    let direction: LayoutDirection

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            document
                .frame(width: viewport.width, height: viewport.height)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
                .scaleEffect(viewport.zoom, anchor: .topLeading)
                .frame(width: viewport.scaledWidth, height: viewport.scaledHeight, alignment: .topLeading)
                .padding(24)
        }
        .background(Color.secondary.opacity(0.07))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var document: some View {
        if session.kind == .intelligent {
            ScrollView {
                program.intelligentUIReadingContent()
            }
            .intelligentUIReadingPosition(enabled: true)
        } else {
            ScrollView { program }
        }
    }

    private var program: some View {
        OpenUIView(state: session.state, library: session.library)
            .openUIResourceContext(resources)
            .dynamicTypeSize(dynamicType)
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
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                Menu {
                    ForEach(GalleryDevice.allCases) { device in
                        Button(device.rawValue) {
                            viewport.width = device.size.0
                            viewport.height = device.size.1
                        }
                    }
                } label: { Label("画布预设", systemImage: "iphone.and.ipad") }
                dimension("宽", value: $viewport.width)
                Text("×").foregroundStyle(.secondary)
                dimension("高", value: $viewport.height)
                Text("pt").font(.caption).foregroundStyle(.secondary)
                Button { viewport.rotate() } label: { Label("横竖切换", systemImage: "rotate.right") }
                    .labelStyle(.iconOnly)
                Divider().frame(height: 20)
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                Slider(value: $viewport.zoom, in: 0.5...1.5, step: 0.05) { Text("画布缩放") }
                    .frame(width: 112)
                Text("\(Int((viewport.zoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).frame(width: 42)
                Button("100%") { viewport.zoom = 1 }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }

    private func dimension(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, value: Binding(
                get: { value.wrappedValue },
                set: { if $0.isFinite { value.wrappedValue = min(1600, max(240, $0)) } }
            ), format: .number.precision(.fractionLength(0)))
            .textFieldStyle(.roundedBorder).frame(width: 64)
            .accessibilityLabel("画布" + title + "度，单位 pt")
        }
    }
}
