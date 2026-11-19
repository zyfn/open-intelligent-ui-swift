import SwiftLang
import SwiftUI
import Combine


enum NativeTabsVariant {
    case pending, standard, date

    init(_ context: OpenUIComponentContext) {
        if context.layoutConfigurationReady {
            self = context.presentationString("variant") == "date" ? .date : .standard
        } else if context.hasInterruptedData || (!context.isStreaming && !context.hasPendingData) {
            self = .standard
        } else {
            self = .pending
        }
    }
}

struct NativeTabPanel: Identifiable, Equatable {
    let id: OpenUIString
    let label: String
    let content: Value
    var dayNumber: Int? = nil

    private static let dateFormat = Date.ISO8601FormatStyle().year().month().day()

    static func read(_ children: [OpenUIRenderChild], variant: NativeTabsVariant = .standard) -> [NativeTabPanel] {
        var seen = Set<OpenUIString>()
        return children.compactMap { child in
            guard case .element(let item) = child.value, item.typeName == "TabItem",
                  item.sourceReadiness["value"].complete,
                  let key = PropValue.codeUnitString(item, "value") else { return nil }
            let label = PropValue.string(item, "trigger")
            var dayNumber: Int?
            if variant == .date {
                guard item.sourceReadiness["trigger"].complete, let label, !label.isEmpty,
                      let day = dayOfMonth(key) else { return nil }
                dayNumber = day
            }
            guard seen.insert(key).inserted else { return nil }
            return NativeTabPanel(id: key, label: label ?? key.displayString,
                                  content: PropValue.value(item, "content") ?? .null, dayNumber: dayNumber)
        }
    }

    // Round-trip to reject incomplete keys and invalid dates normalized by Foundation.
    static func dayOfMonth(_ key: OpenUIString) -> Int? {
        guard key.count == 10, let text = key.wellFormedString,
              let date = try? dateFormat.parse(text), dateFormat.format(date) == text else { return nil }
        return Int(text.suffix(2))
    }
}

/// Selection observes stable keys and the declared array order. Changes to
/// the body of a tab are ordinary view updates, with no effect on navigation.
struct NativeTabChoices: Equatable {
    let ids: [OpenUIString]
    let first: OpenUIString?
    let settled: Bool

    static func read(_ context: OpenUIComponentContext, children: [OpenUIRenderChild],
                     panels: [NativeTabPanel], variant: NativeTabsVariant) -> Self {
        let ids = panels.map(\.id)
        let source = context.element.sourceReadiness["items"]
        let settled = !context.hasPendingData && (!context.isStreaming || source.complete)
        guard !settled, let candidate = ids.first else {
            return Self(ids: ids, first: ids.first, settled: settled)
        }
        // A later declaration can resolve first, even though an earlier
        // reference is still missing from the materialized list.
        let prefixLength = source.valueIndices?.prefix { $0 != nil }.count ?? children.count
        for child in children.prefix(prefixLength) {
            guard case .element(let item) = child.value, item.typeName == "TabItem" else { continue }
            guard item.sourceReadiness["value"].complete else { break }
            if variant == .date && !item.sourceReadiness["trigger"].complete { break }
            if PropValue.codeUnitString(item, "value") == candidate {
                return Self(ids: ids, first: candidate, settled: false)
            }
        }
        return Self(ids: ids, first: nil, settled: false)
    }
}

struct NativeTabsSelection {
    private(set) var selected: OpenUIString?

    mutating func choose(_ value: OpenUIString) { selected = value }

    mutating func reconcile(_ choices: NativeTabChoices) {
        if let selected, !choices.settled || choices.ids.contains(selected) { return }
        if selected != choices.first { selected = choices.first }
    }
}

struct NativeTabsView: View {
    let context: OpenUIComponentContext

    var body: some View {
        let variant = NativeTabsVariant(context)
        let children = context.children("items")
        let panels = NativeTabPanel.read(children, variant: variant)
        let choices = NativeTabChoices.read(context, children: children, panels: panels, variant: variant)
        NativeTabsContent(context: context, panels: panels, variant: variant, choices: choices)
            .id(context.presentationSourceRevision)
    }
}

private struct NativeTabsContent: View {
    let context: OpenUIComponentContext
    let panels: [NativeTabPanel]
    let variant: NativeTabsVariant
    let choices: NativeTabChoices
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.layoutDirection) private var direction
    @Environment(\.openUIUserInteraction) private var parentInteraction
    @Environment(\.openUIFormValidation) private var validation
    @State private var local = NativeTabsSelection()
    @State private var width: CGFloat = 0
    @Namespace private var viewport
    private var selected: OpenUIString? {
        if let binding = context.presentationBinding("value") {
            if case .string(let key) = binding.wrappedValue { return key }
            return choices.first
        }
        return local.selected ?? choices.first
    }
    private var active: NativeTabPanel? { panels.first { $0.id == selected } }
    private var nativeSelection: Binding<OpenUIString> {
        Binding(
            get: { active?.id ?? "" },
            set: {
                local.choose($0)
                if let binding = context.presentationBinding("value") { binding.wrappedValue = .string($0) }
                parentInteraction?()
            })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: context.theme.spacing("l")) {
            if !panels.isEmpty {
                selector
                    .accessibilityIdentifier(
                        "openui.tabs.\(context.element.statementId ?? "tabs")")
            }
            if let active {
                context.render(active.content).id(active.id)
                    .environment(\.openUIUserInteraction, {
                        local.choose(active.id); parentInteraction?()
                    })
                    .simultaneousGesture(TapGesture().onEnded { local.choose(active.id); parentInteraction?() })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { reconcileSelection(choices) }
        .onChange(of: choices) { next in reconcileSelection(next) }
        .onReceive(validation?.$focusRequest.eraseToAnyPublisher() ?? Empty<NativeFormValidation.FocusRequest?, Never>().eraseToAnyPublisher()) { request in
            guard let name = request?.name, let panel = panels.first(where: { NativeFormValidation.containsField(name, in: $0.content) }) else { return }
            if selected != panel.id { nativeSelection.wrappedValue = panel.id }
        }
    }
    private func reconcileSelection(_ next: NativeTabChoices) {
        if context.presentationBinding("value") == nil { local.reconcile(next) }
    }
    private var selector: some View {
        let selectedID = selected
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: variant == .date ? context.theme.spaceS : context.theme.space2xs) {
                    ForEach(panels) { panel in
                        Button { nativeSelection.wrappedValue = panel.id } label: {
                            tabLabel(panel, selected: selectedID == panel.id)
                        }
                        .buttonStyle(NativeQuietButtonStyle(theme: context.theme))
                        .accessibilityAddTraits(selectedID == panel.id ? .isSelected : [])
                        .accessibilityIdentifier("openui.tab." + panel.id.displayString)
                        .id(panel.id)
                    }
                }
            }
            .onChange(of: selected) { value in
                if let value { proxy.scrollTo(value, anchor: .center) }
            }
            .background(GeometryReader { geometry in
                Color.clear.preference(key: NativeTabsWidthKey.self, value: [viewport: geometry.size.width])
            })
            .onPreferenceChange(NativeTabsWidthKey.self) { sizes in
                if let next = sizes[viewport], next.isFinite, next > 0, abs(next - width) > 0.5 { width = next }
            }
            .task(id: NativeTabsLayoutKey(labels: panels.map(\.label), width: width,
                textSize: textSize, rightToLeft: direction == .rightToLeft)) {
                // Wait for the changed font/container proposal to enter layout.
                // Scroll offsets are deliberately not a task input: users can
                // browse other labels without being pulled back to selection.
                await Task.yield()
                if !Task.isCancelled, let active { proxy.scrollTo(active.id, anchor: .center) }
            }
        }
    }

    @ViewBuilder private func tabLabel(_ panel: NativeTabPanel, selected: Bool) -> some View {
        let theme = context.theme
        let maximumWidth = NativeTabsLayout.maximumLabelWidth(viewportWidth: width, horizontalPadding: theme.spaceM)
        if let day = panel.dayNumber {
            NativeBoundedLabelLayout(maximumWidth: maximumWidth) {
                VStack(spacing: theme.space2xs) {
                    Text(verbatim: panel.label).openUIFont(theme.textBodyXs, role: .caption)
                        .lineLimit(textSize.isAccessibilitySize ? nil : 2)
                    Text(verbatim: String(day)).openUIFont(theme.textHeadingSm, role: .title)
                        .monospacedDigit()
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(selected ? theme.foreground : theme.textNeutralSecondary)
            .padding(.horizontal, theme.spaceS).padding(.vertical, theme.spaceXs)
            .frame(minWidth: 58, minHeight: 56)
            .background(selected ? theme.textNeutralPrimary : Color.clear,
                        in: RoundedRectangle(cornerRadius: theme.radiusXl, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(panel.label) \(panel.id.displayString)"))
        } else {
            NativeBoundedLabelLayout(maximumWidth: maximumWidth) {
                Text(panel.label)
                    .openUIFont(theme.textLabelDefaultHeavy, role: .control)
                    .foregroundStyle(selected ? theme.textNeutralPrimary : theme.textNeutralSecondary)
                    .lineLimit(textSize.isAccessibilitySize ? nil : 2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, theme.spaceM)
            .padding(.vertical, theme.spaceS)
            .openUIControlTarget()
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(variant == .standard && selected ? theme.textNeutralPrimary : .clear)
                    .frame(height: theme.space3xs)
                    .padding(.horizontal, theme.spaceM)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct NativeTabsLayoutKey: Hashable {
    let labels: [String]
    let width: CGFloat
    let textSize: DynamicTypeSize
    let rightToLeft: Bool
}
private struct NativeTabsWidthKey: PreferenceKey {
    static let defaultValue: [Namespace.ID: CGFloat] = [:]
    static func reduce(value: inout [Namespace.ID: CGFloat], nextValue: () -> [Namespace.ID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}
enum NativeTabsLayout {
    static func maximumLabelWidth(viewportWidth: CGFloat, horizontalPadding: CGFloat) -> CGFloat {
        guard viewportWidth.isFinite, viewportWidth > 0 else { return 232 }
        return min(232, max(1, viewportWidth - 2 * max(0, horizontalPadding)))
    }
}
