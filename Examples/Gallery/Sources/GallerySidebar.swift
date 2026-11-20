import SwiftUI
import UniformTypeIdentifiers

/// Navigation state is independent of the selected document and virtualized rows.
struct GallerySidebarState {
    private var expanded: [GalleryLibrary: Set<GalleryComponentCategory>] = [:]

    func isExpanded(_ category: GalleryComponentCategory, in library: GalleryLibrary) -> Bool {
        expanded[library, default: []].contains(category)
    }

    mutating func expand(_ category: GalleryComponentCategory, in library: GalleryLibrary) {
        expanded[library, default: []].insert(category)
    }

    mutating func toggle(_ category: GalleryComponentCategory, in library: GalleryLibrary) {
        if !expanded[library, default: []].insert(category).inserted {
            expanded[library, default: []].remove(category)
        }
    }
}

@MainActor struct GallerySidebar: View {
    @ObservedObject var model: GalleryModel
    @State private var navigation = GallerySidebarState()
    @State private var choosingMarksRepository = false
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @FocusState private var focusedID: String?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            Picker("组件库", selection: Binding(get: { model.selectedLibrary }, set: {
                model.selectLibrary($0)
            })) {
                ForEach(GalleryLibrary.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel("选择产品")
            .accessibilityHint("整体切换场景和组件库")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 14)
            Divider()
            #if os(macOS)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) { navigationItems }
                        .padding(.horizontal, 10).padding(.vertical, 12)
                }
                .onMoveCommand { direction in
                    if let id = moveSelection(direction) { proxy.scrollTo(id) }
                }
            }
            #else
            List(selection: Binding(get: { model.selectedID }, set: {
                if let id = $0 { model.select(id) }
            })) { navigationItems }
            .listStyle(.sidebar)
            #endif
        }
        // Category expansion changes structure, never the document or its identity.
        .transaction { $0.animation = nil }
        .navigationTitle("Gallery")
        .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 380)
        .fileImporter(isPresented: $choosingMarksRepository, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): model.connectMarksRepository(url)
            case .failure(let error): model.reportMarks(error)
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.reloadComponentMarks() }
        }
        .onAppear(perform: revealSelectedComponent)
        .onChange(of: model.selectedID) { _ in revealSelectedComponent() }
    }

    private var scenes: [GalleryEntry] {
        model.entries.filter { $0.section == .cases && $0.supports(model.selectedLibrary) }
    }
    private var sceneCategories: [String] {
        scenes.reduce(into: []) { result, entry in
            if !result.contains(entry.item.category) { result.append(entry.item.category) }
        }
    }
    private var categories: [GalleryComponentCategory] {
        GalleryComponentCategory.allCases.filter { category in model.components.contains { $0.category == category } }
    }
    private var componentRows: [GalleryComponentRow] {
        GalleryComponentRow.hierarchy(model.components)
    }
    private func revealSelectedComponent() {
        if let category = model.selectedComponent?.category {
            navigation.expand(category, in: model.selectedLibrary)
        }
    }

    @ViewBuilder private var navigationItems: some View {
        if model.designSystem != nil {
            item(GalleryDesignSystem.id, title: "Design System")
        }
        if !model.components.isEmpty {
            sectionTitle("组件库").padding(.top, 12)
            ForEach(categories) { category in
                categoryHeader(category)
                if navigation.isExpanded(category, in: model.selectedLibrary) {
                    ForEach(componentRows.filter { $0.component.category == category }) { row in
                        componentItem(row.component)
                            .padding(.leading, 18 + CGFloat(row.depth) * 16)
                            .transition(.identity)
                    }
                }
            }
        }
        if !scenes.isEmpty {
            sectionTitle("场景").padding(.top, 16)
            ForEach(sceneCategories, id: \.self) { category in
                Text(category)
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 3)
                    .accessibilityAddTraits(.isHeader)
                ForEach(scenes.filter { $0.item.category == category }) { entry in
                    item(entry.id, title: entry.item.title)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .accessibilityAddTraits(.isHeader)
    }

    private func categoryHeader(_ category: GalleryComponentCategory) -> some View {
        let isExpanded = navigation.isExpanded(category, in: model.selectedLibrary)
        let count = model.components.filter { $0.category == category }.count
        return Button { navigation.toggle(category, in: model.selectedLibrary) } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold)).frame(width: 10)
                Text(category.title).font(.body.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title)，\(count) 项")
        .accessibilityValue(isExpanded ? "已展开" : "已折叠")
        .accessibilityIdentifier("gallery.category.\(category.rawValue)")
    }

    private func componentItem(_ component: GalleryComponent) -> some View {
        let library = model.selectedLibrary
        let marked = model.componentMarks.contains(component.name, in: library)
        let hint = component.container.map { "在 \($0) 中查看用法" }
            ?? (component.supporting ? "查看数据定义和用法" : "")
        return item(component.id, title: component.name, hint: hint, marked: marked)
            .contextMenu {
                if model.marksRepository != nil {
                    Button(marked ? "取消划线" : "划线") {
                        model.setComponentMarked(!marked, name: component.name, library: library)
                    }
                    Divider()
                }
                Button("选择标记仓库…") { choosingMarksRepository = true }
            }
    }

    private func itemLabel(_ title: String, marked: Bool) -> some View {
        Text(title).strikethrough(marked).font(.body).lineLimit(2).multilineTextAlignment(.leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    @ViewBuilder private func item(
        _ id: String, title: String, hint: String = "", marked: Bool = false
    ) -> some View {
        #if os(macOS)
        let selected = model.selectedID == id
        Button {
            model.select(id)
            focusedID = id
        } label: {
            itemLabel(title, marked: marked)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focused($focusedID, equals: id)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(hint)
        .accessibilityValue(marked ? "已划线" : "")
        .accessibilityIdentifier("gallery.item.\(id)")
        .id(id)
        #else
        NavigationLink(value: id) { itemLabel(title, marked: marked) }
            .accessibilityHint(hint)
            .accessibilityValue(marked ? "已划线" : "")
            .accessibilityIdentifier("gallery.item.\(id)")
            .tag(id)
        #endif
    }

    #if os(macOS)
    private func moveSelection(_ direction: MoveCommandDirection) -> String? {
        guard direction == .up || direction == .down else { return nil }
        let componentIDs = categories.flatMap { category in
            navigation.isExpanded(category, in: model.selectedLibrary)
                ? componentRows.filter { $0.component.category == category }.map(\.id) : []
        }
        let sceneIDs = sceneCategories.flatMap { type in scenes.filter { $0.item.category == type }.map(\.id) }
        let ids = (model.designSystem == nil ? [] : [GalleryDesignSystem.id]) + componentIDs + sceneIDs
        guard !ids.isEmpty else { return nil }
        let current = ids.firstIndex(of: model.selectedID ?? "")
        let index = current.map { min(ids.count - 1, max(0, $0 + (direction == .down ? 1 : -1))) }
            ?? (direction == .down ? 0 : ids.count - 1)
        model.select(ids[index])
        focusedID = ids[index]
        return ids[index]
    }
    #endif
}
