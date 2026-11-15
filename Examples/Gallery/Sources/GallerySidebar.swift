import SwiftUI

/// Navigation state is independent of the selected document and virtualized rows.
struct GallerySidebarState {
    private var expanded: [GalleryLibrary: Set<String>] = [:]

    func isExpanded(_ category: String, in library: GalleryLibrary) -> Bool {
        expanded[library, default: []].contains(category)
    }

    mutating func toggle(_ category: String, in library: GalleryLibrary) {
        if !expanded[library, default: []].insert(category).inserted {
            expanded[library, default: []].remove(category)
        }
    }
}

@MainActor struct GallerySidebar: View {
    @ObservedObject var model: GalleryModel
    @State private var navigation = GallerySidebarState()
    #if os(macOS)
    @FocusState private var focusedID: String?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("产品").font(.body).foregroundStyle(.secondary)
                    Picker("产品", selection: Binding(get: { model.selectedLibrary }, set: {
                        model.selectLibrary($0)
                    })) {
                        ForEach(GalleryLibrary.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel("选择产品")
                    .accessibilityHint("整体切换场景和组件库")
                    .frame(maxWidth: .infinity)
                }

            }
            .padding(14)
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
    }

    private var scenes: [GalleryEntry] {
        model.entries.filter { $0.section == .cases && $0.supports(model.selectedLibrary) }
    }
    private var sceneCategories: [String] {
        scenes.reduce(into: []) { result, entry in
            if !result.contains(entry.item.category) { result.append(entry.item.category) }
        }
    }
    private var categories: [String] {
        GalleryComponent.categories.filter { category in model.components.contains { $0.category == category } }
    }
    private var rowFont: Font {
        #if os(macOS)
        .system(size: 14)
        #else
        .body
        #endif
    }

    @ViewBuilder private var navigationItems: some View {
        if scenes.isEmpty && model.components.isEmpty {
            Text("没有可浏览的内容").font(.headline).padding(10)
        } else {
            if !scenes.isEmpty {
                sectionTitle("场景", count: scenes.count)
                ForEach(sceneCategories, id: \.self) { category in
                    Text(category)
                        .font(rowFont.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 3)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(scenes.filter { $0.item.category == category }) { entry in
                        item(entry.id, title: entry.item.title).padding(.leading, 14)
                    }
                }
            }
            if !model.components.isEmpty {
                sectionTitle("组件库", count: model.components.count)
                    .padding(.top, scenes.isEmpty ? 0 : 16)
                let supporting = model.components.filter(\.supporting).count
                if supporting > 0 {
                    Text("\(model.components.count - supporting) 个可视 · \(supporting) 个结构 / 数据")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.bottom, 5)
                }
                ForEach(categories, id: \.self) { category in
                    categoryHeader(category)
                    if navigation.isExpanded(category, in: model.selectedLibrary) {
                        ForEach(model.components.filter { $0.category == category }) { component in
                            item(component.id, title: component.name, supporting: component.supporting)
                                .padding(.leading, 14)
                                .transition(.identity)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            Text("\(count)")
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private func categoryHeader(_ category: String) -> some View {
        let isExpanded = navigation.isExpanded(category, in: model.selectedLibrary)
        let count = model.components.filter { $0.category == category }.count
        return Button { navigation.toggle(category, in: model.selectedLibrary) } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold)).frame(width: 10)
                Text(category).font(rowFont.weight(.medium))
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category) 组件，\(count) 项")
        .accessibilityValue(isExpanded ? "已展开" : "已折叠")
        .accessibilityIdentifier("gallery.category.\(category)")
    }

    private func itemLabel(_ title: String, supporting: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title).font(rowFont).lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if supporting { Text("子项").font(.caption).opacity(0.7) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func item(_ id: String, title: String, supporting: Bool = false) -> some View {
        #if os(macOS)
        let selected = model.selectedID == id
        Button {
            model.select(id)
            focusedID = id
        } label: {
            itemLabel(title, supporting: supporting)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focused($focusedID, equals: id)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("gallery.item.\(id)")
        .id(id)
        #else
        NavigationLink(value: id) { itemLabel(title, supporting: supporting) }.tag(id)
        #endif
    }

    #if os(macOS)
    private func moveSelection(_ direction: MoveCommandDirection) -> String? {
        guard direction == .up || direction == .down else { return nil }
        let ids = sceneCategories.flatMap { type in scenes.filter { $0.item.category == type }.map(\.id) } + categories.flatMap { category in
            navigation.isExpanded(category, in: model.selectedLibrary)
                ? model.components.filter { $0.category == category }.map(\.id) : []
        }
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
