import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum CarouselComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Carousel", description: "Adaptive equal-height horizontal collection with native item snapping on iOS 17/macOS 14+ and desktop navigation. itemWidth is preferred width (theme default 288), gap defaults to 3 theme units. Optional selected is bidirectional; itemIds must be unique and match children in order, otherwise default ids are zero-based index strings. Share ids/selected with Map to link markers and cards. Large text uses available width; earlier platforms retain native scrolling.", params: [
            OpenUIParameter.slot("children", required: true), Parameter.number("itemWidth", minimum: 120, maximum: 600), Parameter.number("gap", minimum: 0, maximum: 24),
            OpenUIParameter.selection("selected", required: false),
            Parameter.array("itemIds", items: .object([.init(key: "type", value: .string("string"))]), required: false)
        ]) { CarouselView(context: $0) }
    }
}

enum CarouselMetrics {
    static func width(preferred: CGFloat, available: CGFloat, accessibility: Bool, peek: CGFloat = 32) -> CGFloat {
        let preferred = preferred.isFinite ? min(600, max(120, preferred)) : 288
        guard available > 0 else { return preferred }
        return accessibility ? available : min(preferred, max(min(120, available), available * 0.85))
    }
}

struct CarouselView: View {
    let context: OpenUIComponentContext
    private let projectedChildren: [OpenUIRenderChild]?
    private let projectedIDs: [String]?
    private let projectedSelection: Binding<String>?
    init(context: OpenUIComponentContext, children: [OpenUIRenderChild]? = nil, itemIDs: [String]? = nil, selection: Binding<String>? = nil) {
        self.context = context
        projectedChildren = children; projectedIDs = itemIDs; projectedSelection = selection
    }
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var available: CGFloat = 0
    @State private var current = 0
    @State private var coordinateSpace = UUID()
    @State private var synchronizing: String?
    @State private var selectionReady = false
    @State private var userScrolling = false
    @State private var mediaActivationBlocked = false
    @State private var synchronizedLayout: CarouselLayoutIdentity?
    @EnvironmentObject private var state: OpenUIState
    private var selectedID: String? { projectedSelection?.wrappedValue ?? ValueReading.boundString(context, "selected") }
    private func itemIDs(count: Int) -> [String]? {
        let supplied = projectedIDs.map { Value.array(OpenUIArray($0.map { .string(OpenUIString($0)) })) } ?? context.value("itemIds")
        return CarouselSelection.ids(count: count, supplied: supplied)
    }
    private func setSelection(_ id: String) {
        if let projectedSelection { projectedSelection.wrappedValue = id }
        else { context.binding("selected")?.wrappedValue = .string(OpenUIString(id)) }
    }

    var body: some View {
        let children = projectedChildren ?? context.children()
        let ids = itemIDs(count: children.count)
        let scrollIDs = ids ?? children.indices.map(String.init)
        // Read sizing dependencies in this body, before escaping Reader/Scroll builders.
        // The scroll viewport and every item consume the same immutable sizing snapshot.
        let viewportWidth = available
        let accessibility = typeSize.isAccessibilitySize
        let itemWidth = CarouselMetrics.width(preferred: CGFloat(context.number("itemWidth") ?? Double(theme.carouselItemWidth)), available: viewportWidth, accessibility: accessibility, peek: theme.carouselPeekWidth)
        let _ = LayoutTrace.record("carousel-body", "node=\(coordinateSpace) available=\(LayoutTrace.number(viewportWidth)) itemW=\(LayoutTrace.number(itemWidth)) ax=\(accessibility) count=\(children.count)")
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: theme.innerSpacing) {
                observedScroll(children: children, ids: ids, scrollIDs: scrollIDs, itemWidth: itemWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .intelligentUILayoutTrace("carousel-scroll-viewport", "node=\(coordinateSpace)")
                    .coordinateSpace(name: coordinateSpace)
                    .onPreferenceChange(CarouselOffsets.self) { offsets in
                        if let nearest = offsets.min(by: { abs($0.value.minX) < abs($1.value.minX) }), let index = scrollIDs.firstIndex(of: nearest.key) {
                            current = index
                            if context.canInteract, selectionReady, userScrolling, let ids, ids.indices.contains(current) {
                                if synchronizing == ids[current] { synchronizing = nil }
                                else if synchronizing == nil, selectedID != ids[current] {
                                    setSelection(ids[current])
                                }
                            }
                        }
                        // A new list can be published before its scroll targets
                        // exist. Reconcile the existing logical selection only
                        // after geometry acknowledges every new id/position.
                        let layout = CarouselLayoutIdentity(ids: scrollIDs, itemWidth: itemWidth)
                        if CarouselSelection.layoutReady(ids: scrollIDs, width: itemWidth, frames: offsets), synchronizedLayout != layout {
                            synchronizedLayout = layout
                            synchronize(ids: ids, proxy: proxy, animated: false)
                        }
                    }
                    .accessibilityAction(named: "下一个") { move(to: current + 1, count: children.count, proxy: proxy) }
                    .accessibilityAction(named: "上一个") { move(to: current - 1, count: children.count, proxy: proxy) }
                #if os(macOS)
                if children.count > 1 {
                    HStack(spacing: theme.innerSpacing) {
                        Spacer()
                        Button { move(to: current - 1, count: children.count, proxy: proxy) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("上一个").disabled(current <= 0)
                        Button { move(to: current + 1, count: children.count, proxy: proxy) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("下一个").disabled(current >= children.count - 1)
                    }.buttonStyle(.borderless).tint(theme.actionAccent)
                }
                #endif
            }
            .intelligentUILayoutTrace("carousel-stack-natural", "node=\(coordinateSpace)")
            .frame(maxWidth: .infinity, alignment: .leading)
            .intelligentUILayoutTrace("carousel-stack-frame", "node=\(coordinateSpace)")
            // Observe the laid-out viewport directly. During cold accessibility
            // layout, preference propagation can retain a transient narrow size.
            .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in
                LayoutTrace.record("carousel-viewport-geometry", "node=\(coordinateSpace) origin=stack-frame measuredW=\(LayoutTrace.number(width)) oldAvailable=\(LayoutTrace.number(available))")
                guard width.isFinite, width > 0, width != available else { return }
                available = width
            }
            .onDisappear { selectionReady = false; userScrolling = false; synchronizedLayout = nil }
            .task(id: userScrolling) {
                guard !userScrolling else { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, !userScrolling else { return }
                mediaActivationBlocked = false
            }
            .accessibilityScrollAction { edge in
                if edge == .trailing { move(to: current + 1, count: children.count, proxy: proxy) }
                else if edge == .leading { move(to: current - 1, count: children.count, proxy: proxy) }
            }
            .task {
                await Task.yield()
                synchronize(ids: ids, proxy: proxy, animated: false)
                selectionReady = true
            }
            .onChange(of: selectedID) { _ in synchronize(ids: ids, proxy: proxy, animated: true) }
            .onChange(of: ids) { _ in synchronize(ids: ids, proxy: proxy, animated: false) }
            .onChange(of: available) { _ in synchronize(ids: ids, proxy: proxy, animated: false) }
            .onAppear { traceMetrics(itemWidth: itemWidth, accessibility: accessibility, count: children.count) }
            .onChange(of: itemWidth) { value in traceMetrics(itemWidth: value, accessibility: accessibility, count: children.count) }
            .onChange(of: accessibility) { value in traceMetrics(itemWidth: itemWidth, accessibility: value, count: children.count) }
            .task(id: synchronizing) {
                guard let target = synchronizing else { return }
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled, synchronizing == target else { return }
                synchronizing = nil
            }
        }.intelligentUILayoutTrace("carousel-reader", "node=\(coordinateSpace)")
    }

    private func traceMetrics(itemWidth: CGFloat, accessibility: Bool, count: Int) {
        LayoutTrace.record("carousel-metrics", "node=\(coordinateSpace) available=\(LayoutTrace.number(available)) itemW=\(LayoutTrace.number(itemWidth)) preferred=\(context.number("itemWidth") ?? Double(theme.carouselItemWidth)) ax=\(accessibility) count=\(count)")
    }

    @ViewBuilder private func observedScroll(children: [OpenUIRenderChild], ids: [String]?, scrollIDs: [String], itemWidth: CGFloat) -> some View {
        if #available(iOS 18, macOS 15, *) {
            scroll(children: children, scrollIDs: scrollIDs, itemWidth: itemWidth).onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating { userScrolling = true; mediaActivationBlocked = true; synchronizing = nil }
                else if phase == .idle { commit(ids); userScrolling = false }
            }
        } else {
            scroll(children: children, scrollIDs: scrollIDs, itemWidth: itemWidth).simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in userScrolling = true; mediaActivationBlocked = true; synchronizing = nil }.onEnded { _ in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    commit(ids); userScrolling = false
                }
            })
        }
    }
    private func commit(_ ids: [String]?) {
        guard selectionReady, userScrolling, context.canInteract, let ids, ids.indices.contains(current), selectedID != ids[current] else { return }
        setSelection(ids[current])
    }
    @ViewBuilder private func scroll(children: [OpenUIRenderChild], scrollIDs: [String], itemWidth: CGFloat) -> some View {
        if #available(iOS 17, macOS 14, *) {
            ScrollView(.horizontal) { items(children, scrollIDs: scrollIDs, itemWidth: itemWidth).scrollTargetLayout() }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden, axes: .horizontal)
        } else {
            ScrollView(.horizontal) { items(children, scrollIDs: scrollIDs, itemWidth: itemWidth) }.scrollIndicators(.hidden, axes: .horizontal)
        }
    }

    private func items(_ children: [OpenUIRenderChild], scrollIDs: [String], itemWidth: CGFloat) -> some View {
        EqualHeightCarouselLayout(itemWidth: itemWidth, gap: CGFloat(min(24, max(0, context.number("gap") ?? 3))) * theme.spacingUnit, traceID: coordinateSpace.uuidString) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                context.render(child.value)
                    .environment(\.intelligentUIEditorial, EditorialContext(compactContent: EditorialNode.kind(child.value) == "Col"))
                    .intelligentUILayoutTrace("carousel-item-content", "node=\(coordinateSpace) index=\(index)")
                    .frame(width: itemWidth)
                    .intelligentUILayoutTrace("carousel-item-frame", "node=\(coordinateSpace) index=\(index) itemW=\(LayoutTrace.number(itemWidth))")
                    .id(scrollIDs[index])
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: CarouselOffsets.self, value: [scrollIDs[index]: CarouselItemFrame(index: index, frame: geometry.frame(in: .named(coordinateSpace)))])
                    })
            }
        }.padding(.bottom, theme.innerSpacing)
            .environment(\.intelligentUIScrolling, mediaActivationBlocked || userScrolling)
            .environment(\.intelligentUIImageAlbum, ImageAlbumItem.collect(children.map(\.value)))
    }

    private func move(to index: Int, count: Int, proxy: ScrollViewProxy) {
        guard context.canInteract, count > 0 else { return }
        let index = min(count - 1, max(0, index))
        if let ids = itemIDs(count: count) {
            synchronizing = ids[index]
            setSelection(ids[index])
        }
        let target = itemIDs(count: count)?[index] ?? String(index)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .leading) }
    }
    private func synchronize(ids: [String]?, proxy: ScrollViewProxy, animated: Bool) {
        guard let ids, let selection = selectedID, let index = ids.firstIndex(of: selection) else { return }
        synchronizing = selection
        withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.2) : nil) { proxy.scrollTo(ids[index], anchor: .leading) }
    }
}

enum CarouselSelection {
    static func layoutReady(ids: [String], width: CGFloat, frames: [String: CarouselItemFrame]) -> Bool {
        guard !ids.isEmpty, ids.count == frames.count else { return false }
        return ids.enumerated().allSatisfy { index, id in
            guard let frame = frames[id] else { return false }
            return frame.index == index && abs(frame.frame.width - width) < 0.5
        }
    }
    static func ids(count: Int, supplied: Value?) -> [String]? {
        guard let supplied, supplied != .null else { return (0..<count).map(String.init) }
        let ids = ValueReading.array(supplied).map { ValueReading.string($0) }
        guard ids.count == count, !ids.contains(""), Set(ids).count == count else { return nil }
        return ids
    }
}

struct CarouselItemFrame: Equatable {
    let index: Int
    let frame: CGRect
    var minX: CGFloat { frame.minX }
}
private struct CarouselLayoutIdentity: Equatable {
    let ids: [String]
    let itemWidth: CGFloat
}
private struct CarouselOffsets: PreferenceKey {
    static var defaultValue: [String: CarouselItemFrame] = [:]
    static func reduce(value: inout [String: CarouselItemFrame], nextValue: () -> [String: CarouselItemFrame]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct EqualHeightCarouselLayout: Layout {
    let itemWidth: CGFloat
    let gap: CGFloat
    var traceID: String = ""
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.init(width: itemWidth, height: nil)).height }.max() ?? 0
        LayoutTrace.record("carousel-layout-measure", "node=\(traceID) proposalW=\(LayoutTrace.number(proposal.width)) proposalH=\(LayoutTrace.number(proposal.height)) itemW=\(LayoutTrace.number(itemWidth)) subviews=\(subviews.count) resultW=\(LayoutTrace.number(CGFloat(subviews.count) * itemWidth + CGFloat(max(0, subviews.count - 1)) * gap)) resultH=\(LayoutTrace.number(height))")
        return CGSize(width: CGFloat(subviews.count) * itemWidth + CGFloat(max(0, subviews.count - 1)) * gap, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        LayoutTrace.record("carousel-layout-place", "node=\(traceID) proposalW=\(LayoutTrace.number(proposal.width)) proposalH=\(LayoutTrace.number(proposal.height)) boundsW=\(LayoutTrace.number(bounds.width)) boundsH=\(LayoutTrace.number(bounds.height)) itemW=\(LayoutTrace.number(itemWidth)) subviews=\(subviews.count)")
        for (index, view) in subviews.enumerated() {
            view.place(at: .init(x: bounds.minX + CGFloat(index) * (itemWidth + gap), y: bounds.minY), proposal: .init(width: itemWidth, height: bounds.height))
        }
    }
}
