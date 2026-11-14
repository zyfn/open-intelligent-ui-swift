import SwiftUI
import UniformTypeIdentifiers
import OpenUICore

private enum GalleryPanel: String, Identifiable {
    case source = "源码", inspector = "诊断"
    var id: String { rawValue }
}

@MainActor struct GalleryView: View {
    @StateObject private var model: GalleryModel
    @State private var viewport: GalleryViewport
    @State private var appearance: String
    @State private var largeType: Bool
    @State private var localeName: String
    @State private var panel: GalleryPanel?
    @State private var search = ""
    @State private var importing = false
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
        #if os(macOS)
        _panel = State(initialValue: .source)
        #else
        _panel = State(initialValue: nil)
        #endif
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.selectedID }, set: { if let id = $0 { model.select(id) } })) {
                ForEach(GallerySection.allCases) { section in
                    Section(section.title) {
                        ForEach(filtered(section)) { entry in
                            NavigationLink(value: entry.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.item.title).font(.subheadline.weight(.medium))
                                    Text(entry.item.category).font(.caption).foregroundStyle(.secondary)
                                    if !entry.supports(model.selectedLibrary) {
                                        Text("当前组件库无此诊断").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                            .tag(entry.id)
                            .disabled(!entry.supports(model.selectedLibrary))
                        }
                    }
                }
            }
            .navigationTitle("OpenUI Gallery")
            .navigationSplitViewColumnWidth(min: 190, ideal: 240, max: 300)
            .searchable(text: $search, prompt: "案例、能力或标签")
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

    private func filtered(_ section: GallerySection) -> [GalleryEntry] {
        model.entries.filter { entry in
            entry.section == section && (search.isEmpty ||
                ([entry.item.title, entry.item.summary, entry.item.category] + entry.item.tags)
                    .joined(separator: " ").localizedCaseInsensitiveContains(search))
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if let entry = model.selectedEntry {
                HStack {
                    Text(entry.item.summary).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            if let failure = model.failure {
                Text(failure).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            if let session = model.session, let resources = model.resources {
                GalleryViewportControls(viewport: $viewport)
                GalleryPlaybackControls(session: session)
                Divider()
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
                    Text("选择匹配组件库的案例，或导入源码。")
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
            case .source: GallerySourceEditor(session: session)
            case .inspector: GalleryInspector(session: session, state: session.state)
            }
        }
        .id(session.id)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker("组件库", selection: Binding(get: { model.selectedLibrary }, set: { model.selectLibrary($0) })) {
                ForEach(GalleryLibrary.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
        }
        ToolbarItem {
            Button { importing = true } label: { Label("导入程序", systemImage: "square.and.arrow.down") }
        }
        ToolbarItem {
            Menu {
                Button("查看/编辑源码") { panel = .source }
                Button("诊断、状态与动作") { panel = .inspector }
                #if os(macOS)
                Button("隐藏侧栏") { panel = nil }
                #endif
            } label: { Label("调试面板", systemImage: "sidebar.right") }
        }
        ToolbarItem {
            Menu {
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
            } label: { Label("展示环境", systemImage: "slider.horizontal.3") }
        }
    }
}
