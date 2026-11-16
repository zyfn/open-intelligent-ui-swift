import SwiftLang
import SwiftUI
import Combine


struct NativeTabPanel: Identifiable, Equatable {
    let id: OpenUIString
    let label: String
    let content: Value
    static func read(_ children: [OpenUIRenderChild]) -> [NativeTabPanel] {
        var seen = Set<OpenUIString>()
        return children.compactMap { child in
            guard case .element(let item) = child.value,
                item.typeName == "TabItem",
                let key = PropValue.codeUnitString(item, "value"), seen.insert(key).inserted
            else { return nil }
            return NativeTabPanel(
                id: key, label: PropValue.string(item, "trigger") ?? key.displayString,
                content: PropValue.value(item, "content") ?? .null)
        }
    }
}

/// Follow the reference's last-growing-content rule until a native button tap
/// records user intent, including a tap on the currently selected tab. Initial
/// complete renders follow growth too. Removing a manually selected value does
/// not invent a fallback absent from the upstream controlled Tabs.
struct NativeTabsSelection {
    private(set) var selected: OpenUIString?
    private var userHasInteracted = false
    private var previousContentSizes: [OpenUIString: Int] = [:]
    mutating func choose(_ value: OpenUIString) {
        userHasInteracted = true
        guard value != selected else { return }
        selected = value
    }
    mutating func reconcile(_ panels: [NativeTabPanel]) {
        if selected == nil || selected == "" { selected = panels.first?.id }
        guard !userHasInteracted else { return }
        var candidate: OpenUIString?
        var nextSizes: [OpenUIString: Int] = [:]
        for panel in panels {
            let size = panel.content.jsonStringifyUTF16Length() ?? 0
            nextSizes[panel.id] = size
            if size > previousContentSizes[panel.id, default: 0] { candidate = panel.id }
        }
        previousContentSizes = nextSizes
        if let candidate { selected = candidate }
    }
}

struct NativeTabsView: View {
    let context: OpenUIComponentContext
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.layoutDirection) private var direction
    @Environment(\.openUIUserInteraction) private var parentInteraction
    @Environment(\.openUIFormValidation) private var validation
    @State private var local = NativeTabsSelection()
    @State private var width: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var overflow = NativeTabsOverflow()
    @StateObject private var measurements = NativeTabsMeasurements()
    @Namespace private var viewport
    private var panels: [NativeTabPanel] { NativeTabPanel.read(context.children("items")) }
    private var selected: OpenUIString? {
        if let binding = context.presentationBinding("value") {
            if case .string(let key) = binding.wrappedValue { return key }
            return panels.first?.id
        }
        return local.selected
    }
    private var active: NativeTabPanel? { panels.first { $0.id == selected } }
    private var showsOverflowHint: Bool {
        NativeTabsOverflow.shouldShowHint(contentWidth: contentWidth, viewportWidth: width)
    }
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
        .onAppear { if context.presentationBinding("value") == nil { local.reconcile(panels) } }
        .onChange(of: panels) { updated in
            if context.presentationBinding("value") == nil { local.reconcile(updated) }
        }
        .onReceive(validation?.$focusRequest.eraseToAnyPublisher() ?? Empty<NativeFormValidation.FocusRequest?, Never>().eraseToAnyPublisher()) { request in
            guard let name = request?.name, let panel = panels.first(where: { NativeFormValidation.containsField(name, in: $0.content) }) else { return }
            if selected != panel.id { nativeSelection.wrappedValue = panel.id }
        }
    }
    private var selector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: context.theme.space2xs) {
                    ForEach(panels) { panel in
                        Button { nativeSelection.wrappedValue = panel.id } label: {
                            NativeBoundedLabelLayout(maximumWidth: NativeTabsOverflow.maximumLabelWidth(
                                viewportWidth: width, horizontalPadding: context.theme.spaceM)) {
                              Text(panel.label)
                                .openUIFont(context.theme.textLabelDefaultHeavy, role: .control)
                                .foregroundStyle(active?.id == panel.id ? context.theme.textNeutralPrimary : context.theme.textNeutralSecondary)
                                .lineLimit(textSize.isAccessibilitySize ? nil : 2)
                                .truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
                            }
                                .padding(.horizontal, context.theme.spaceM)
                                .padding(.vertical, context.theme.spaceS)
                                .background(active?.id == panel.id ? context.theme.componentStyle.selectedSurface : .clear,
                                  in: Capsule(style: .continuous))
                                .overlay(
                                  Capsule(style: .continuous).strokeBorder(
                                    active?.id == panel.id ? context.theme.componentStyle.selectedBorder : .clear,
                                    lineWidth: context.presentation.borderWidth))
                                .openUIControlTarget()
                        }
                        .buttonStyle(NativeQuietButtonStyle(theme: context.theme, cornerRadius: context.theme.radiusFull))
                        .accessibilityAddTraits(active?.id == panel.id ? .isSelected : [])
                        .accessibilityIdentifier("openui.tab." + panel.id.displayString)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: NativeTabsFramesKey.self,
                                value: [panel.id: geometry.frame(in: .named(viewport))])
                        })
                        .id(panel.id)
                    }
                }.background(GeometryReader { geometry in
                    Color.clear.preference(key: NativeTabsContentWidthKey.self, value: [viewport: geometry.size.width])
                })
                // Measure actual tabs before adding edge room. The hint cannot
                // keep itself alive by counting its own padding as overflow.
                .padding(.horizontal, showsOverflowHint ? context.presentation.minimumControlTargetSize : 0)
            }
            .coordinateSpace(name: viewport)
            .overlay(alignment: .leading) {
                if showsOverflowHint, let target = overflow.earlier {
                    overflowButton(earlier: true) { proxy.scrollTo(target, anchor: .center) }
                }
            }
            .overlay(alignment: .trailing) {
                if showsOverflowHint, let target = overflow.later {
                    overflowButton(earlier: false) { proxy.scrollTo(target, anchor: .center) }
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
            .onPreferenceChange(NativeTabsContentWidthKey.self) { sizes in
                if let next = sizes[viewport], next.isFinite, next >= 0, abs(next - contentWidth) > 0.5 { contentWidth = next }
            }
            .onPreferenceChange(NativeTabsFramesKey.self) { frames in
                // Raw scrolling coordinates do not become View state. Only an
                // edge/target change invalidates the selector and its panel.
                measurements.frames = frames
                updateOverflow()
            }
            .onChange(of: width) { _ in updateOverflow() }
            .onChange(of: direction) { _ in updateOverflow() }
            .task(id: NativeTabsLayoutKey(labels: panels.map(\.label), width: width, textSize: textSize)) {
                // Wait for the changed font/container proposal to enter layout.
                // Scroll offsets are deliberately not a task input: users can
                // browse other labels without being pulled back to selection.
                await Task.yield()
                if !Task.isCancelled, let active { proxy.scrollTo(active.id, anchor: .center) }
            }
        }
    }
    private func updateOverflow() {
        let next = NativeTabsOverflow.visibility(ids: panels.map(\.id), frames: measurements.frames,
            viewportWidth: width, rightToLeft: direction == .rightToLeft)
        if next != overflow { overflow = next }
    }
    private func overflowButton(earlier: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: NativeTabsOverflow.chevron(earlier: earlier, rightToLeft: direction == .rightToLeft))
                .openUIFont(context.theme.textLabelSmHeavy, role: .control)
                .foregroundStyle(context.theme.textNeutralSecondary)
                .frame(width: context.presentation.minimumControlTargetSize,
                       height: context.presentation.minimumControlTargetSize)
                .background(context.theme.foreground, in: Circle())
        }.buttonStyle(NativeQuietButtonStyle(theme: context.theme, cornerRadius: context.theme.radiusFull))
            .accessibilityLabel(earlier ? Text("Earlier tabs", bundle: NativeControlResources.bundle)
                : Text("Later tabs", bundle: NativeControlResources.bundle))
            .accessibilityIdentifier(earlier ? "openui.tabs.overflow.earlier" : "openui.tabs.overflow.later")
    }
}

private struct NativeTabsLayoutKey: Hashable {
    let labels: [String]
    let width: CGFloat
    let textSize: DynamicTypeSize
}
private struct NativeTabsWidthKey: PreferenceKey {
    static let defaultValue: [Namespace.ID: CGFloat] = [:]
    static func reduce(value: inout [Namespace.ID: CGFloat], nextValue: () -> [Namespace.ID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}
private struct NativeTabsContentWidthKey: PreferenceKey {
    static let defaultValue: [Namespace.ID: CGFloat] = [:]
    static func reduce(value: inout [Namespace.ID: CGFloat], nextValue: () -> [Namespace.ID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}
private struct NativeTabsFramesKey: PreferenceKey {
    static let defaultValue: [OpenUIString: CGRect] = [:]
    static func reduce(value: inout [OpenUIString: CGRect], nextValue: () -> [OpenUIString: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}
/// Last measured rectangles support container/RTL changes without publishing
/// a new document-view state for every pixel of native scrolling.
private final class NativeTabsMeasurements: ObservableObject {
    var frames: [OpenUIString: CGRect] = [:]
}
struct NativeTabsOverflow: Equatable {
    var earlier: OpenUIString?
    var later: OpenUIString?

    static func shouldShowHint(contentWidth: CGFloat, viewportWidth: CGFloat) -> Bool {
        contentWidth > viewportWidth + 1
    }
    static func maximumLabelWidth(viewportWidth: CGFloat, horizontalPadding: CGFloat) -> CGFloat {
        guard viewportWidth.isFinite, viewportWidth > 0 else { return 232 }
        return min(232, max(1, viewportWidth - 2 * max(0, horizontalPadding)))
    }
    static func visibility(ids: [OpenUIString], frames: [OpenUIString: CGRect], viewportWidth: CGFloat,
                           rightToLeft: Bool) -> Self {
        guard viewportWidth.isFinite, viewportWidth > 0 else { return .init() }
        func outside(_ id: OpenUIString, earlier: Bool) -> Bool {
            guard let frame = frames[id], frame.minX.isFinite, frame.maxX.isFinite else { return false }
            let leftEdge = earlier != rightToLeft
            return leftEdge ? frame.minX < -1 : frame.maxX > viewportWidth + 1
        }
        return .init(earlier: ids.last { outside($0, earlier: true) },
                     later: ids.first { outside($0, earlier: false) })
    }
    static func chevron(earlier: Bool, rightToLeft: Bool) -> String {
        earlier != rightToLeft ? "chevron.left" : "chevron.right"
    }
}
