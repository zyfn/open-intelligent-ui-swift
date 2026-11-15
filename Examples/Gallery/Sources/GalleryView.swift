import SwiftUI
import UniformTypeIdentifiers
import SwiftLang

private enum GalleryPanel: String, Identifiable {
    case source = "源码"
    var id: String { rawValue }
}

@MainActor struct GalleryView: View {
    @StateObject private var model: GalleryModel
    @State private var viewport: GalleryViewport
    @State private var appearance: String
    @State private var largeType: Bool
    @State private var localeName: String
    @State private var panel: GalleryPanel?
    @State private var importing = false
    @State private var showsCanvasTools = false
    @State private var showsPlayback = false
    @Environment(\.dynamicTypeSize) private var systemType
    @Environment(\.locale) private var systemLocale
    @Environment(\.layoutDirection) private var systemDirection

    init(options: GalleryOptions) {
        // CLI values intentionally seed one window's owned settings once.
        _model = StateObject(wrappedValue: GalleryModel(options: options))
        _viewport = State(initialValue: GalleryViewport(width: options.width, height: options.height, zoom: options.zoom))
        _appearance = State(initialValue: options.dark ? "深色" : "系统")
        _largeType = State(initialValue: options.accessibility)
        _localeName = State(initialValue: options.locale)
        _panel = State(initialValue: nil)
    }

    var body: some View {
        NavigationSplitView {
            GallerySidebar(model: model)
        } detail: {
            detail
                .navigationTitle(model.session?.title ?? model.selectedEntry?.item.title ?? "选择案例")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
        }
        .preferredColorScheme(appearance == "系统" ? nil : appearance == "深色" ? .dark : .light)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .json, .data]) { result in
            switch result {
            case .success(let url): model.importProgram(url)
            case .failure(let error): model.report(error)
            }
        }
        #if os(iOS)
        .sheet(item: $panel) { selected in
            NavigationStack {
                if let session = model.session {
                    panelContent(selected, session: session)
                        .navigationTitle(selected.rawValue)
                        .toolbar { ToolbarItem { Button("完成") { panel = nil } } }
                }
            }
        }
        #endif
        .onDisappear { model.session?.interrupt() }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if let component = model.selectedComponent {
                VStack(alignment: .leading, spacing: 4) {
                    if component.supporting {
                        Text("结构 / 数据定义").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(component.container.map { "\(component.name) 由 \($0) 消费，以下展示它在父组件中的实际用法。" }
                             ?? "\(component.name) 是保留的数据定义，没有独立的原生视图；以下展示其源码用法。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(component.name) · 原生组件示例").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 10)
            }
            if let entry = model.selectedEntry {
                HStack {
                    Text(entry.item.summary).font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            if let failure = model.failure {
                Text(failure).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            if let session = model.session, let resources = model.resources {
                if showsCanvasTools { GalleryViewportControls(viewport: $viewport) }
                if showsPlayback { GalleryPlaybackControls(session: session) }
                if showsCanvasTools || showsPlayback { Divider() }
                #if os(macOS)
                HSplitView {
                    preview(session: session, resources: resources).frame(minWidth: 280)
                    if let selected = panel {
                        panelContent(selected, session: session).frame(minWidth: 280, idealWidth: 360)
                    }
                }
                #else
                preview(session: session, resources: resources)
                #endif
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.3.group").font(.largeTitle).foregroundStyle(.secondary)
                    Text("从左侧选择场景或组件。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func preview(session: GalleryDocumentSession, resources: OpenUIResourceContext) -> some View {
        GalleryPreview(session: session, resources: resources, viewport: viewport,
                       dynamicType: largeType ? .accessibility2 : systemType,
                       locale: localeName == "system" ? systemLocale : Locale(identifier: localeName),
                       direction: localeName == "system" ? systemDirection : localeName == "ar" ? .rightToLeft : .leftToRight)
            .id(session.id)
    }

    @ViewBuilder private func panelContent(_ selected: GalleryPanel, session: GalleryDocumentSession) -> some View {
        Group {
            switch selected {
            case .source: GallerySourceEditor(session: session, component: model.selectedComponent)
            }
        }
        .id(session.id)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button { panel = panel == nil ? .source : nil } label: { Label("源码", systemImage: "chevron.left.forwardslash.chevron.right") }
        }
        ToolbarItem {
            Menu {
                Toggle("画布工具", isOn: $showsCanvasTools)
                Toggle("流式工具", isOn: $showsPlayback)
                Button("导入源码") { importing = true }
                Divider()
                Picker("外观", selection: $appearance) {
                    ForEach(["系统", "浅色", "深色"], id: \.self) { Text($0).tag($0) }
                }
                Toggle("辅助功能大字号", isOn: $largeType)
                Picker("SDK 文案与方向", selection: $localeName) {
                    Text("跟随系统").tag("system")
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                    Text("العربية · RTL").tag("ar")
                }
            } label: { Label("展示设置", systemImage: "slider.horizontal.3") }
        }
    }
}
