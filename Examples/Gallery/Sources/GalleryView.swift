import SwiftUI
import UniformTypeIdentifiers
import SwiftLang

#if os(iOS)
private enum GalleryPanel: Identifiable {
    case source(GalleryDocumentSession, GalleryComponent?)
    case settings

    var id: String { title }
    var title: String {
        switch self {
        case .source: return "源码"
        case .settings: return "预览设置"
        }
    }
}
#endif

@MainActor struct GalleryView: View {
    @StateObject private var model: GalleryModel
    @State private var viewport: GalleryViewport
    @State private var appearance: String
    @State private var largeType: Bool
    @State private var localeName: String
    @State private var importing = false
    #if os(macOS)
    @State private var showsSource = false
    @State private var showsSettings = false
    #else
    @State private var panel: GalleryPanel?
    @State private var importAfterDismissal = false
    #endif
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
    }

    var body: some View {
        NavigationSplitView {
            GallerySidebar(model: model)
        } detail: {
            detail
                .navigationTitle(model.selectedComponent?.name ?? model.session?.title ?? model.selectedEntry?.item.title ?? "选择案例")
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
        .sheet(item: $panel, onDismiss: {
            if importAfterDismissal {
                importAfterDismissal = false
                importing = true
            }
        }) { selected in
            NavigationStack {
                Group {
                    switch selected {
                    case .source(let session, let component):
                        GallerySourceEditor(session: session, component: component)
                    case .settings:
                        previewSettings
                    }
                }
                .navigationTitle(selected.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { panel = nil } } }
            }
        }
        #endif
        .onDisappear { model.session?.interrupt() }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if let failure = model.failure ?? model.marksFailure {
                Text(failure).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            if let session = model.session, let resources = model.resources {
                #if os(macOS)
                HSplitView {
                    preview(session: session, resources: resources).frame(minWidth: 280)
                    if showsSource {
                        GallerySourceEditor(session: session, component: model.selectedComponent)
                            .id(session.id)
                            .frame(minWidth: 280, idealWidth: 360, maxWidth: 520)
                    }
                }
                #else
                preview(session: session, resources: resources)
                #endif
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.3.group").font(.title).foregroundStyle(.secondary)
                    Text("选择场景或组件开始预览").foregroundStyle(.secondary)
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

    private var previewSettings: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let entry = model.selectedEntry {
                    Text(entry.item.summary).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    Divider()
                }
                GalleryViewportControls(viewport: $viewport)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    Text("显示").font(.headline)
                    Picker("外观", selection: $appearance) {
                        ForEach(["系统", "浅色", "深色"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("辅助功能大字号", isOn: $largeType)
                    Picker("文案与方向", selection: $localeName) {
                        Text("跟随系统").tag("system")
                        Text("简体中文").tag("zh-Hans")
                        Text("English").tag("en")
                        Text("العربية · RTL").tag("ar")
                    }
                    .pickerStyle(.menu)
                }
                .font(.callout)
                .padding(16)
                Divider()
                Button(action: importSource) {
                    Label("导入源码", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity)
        }
    }

    private func importSource() {
        #if os(macOS)
        showsSettings = false
        importing = true
        #else
        // Present the file importer after the settings sheet has finished closing.
        importAfterDismissal = true
        panel = nil
        #endif
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                #if os(macOS)
                showsSource.toggle()
                #else
                if let session = model.session { panel = .source(session, model.selectedComponent) }
                #endif
            } label: { Label("源码", systemImage: "chevron.left.forwardslash.chevron.right") }
            .disabled(model.session == nil)
            .help("显示或隐藏源码")
        }
        if let session = model.session {
            ToolbarItem {
                GalleryPlaybackControls(session: session)
            }
        }
        ToolbarItem {
            Button {
                #if os(macOS)
                showsSettings.toggle()
                #else
                panel = .settings
                #endif
            } label: { Label("预览设置", systemImage: "slider.horizontal.3") }
            .help("预览设置")
            #if os(macOS)
            .popover(isPresented: $showsSettings, arrowEdge: .top) {
                previewSettings.frame(width: 320, height: 560)
            }
            #endif
        }
    }
}
