import SwiftUI
import SwiftLang

enum CarouselComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Carousel", description: "Horizontal collection with adaptive widths and native snapping on iOS 17/macOS 14+ and desktop navigation. Comparable product/transport cards retain equal heights; general content retains its natural height. itemWidth is the preferred width (default 240), gap uses 4-point units.", params: [
            OpenUIParameter.slot("children", required: true), Parameter.number("itemWidth"), Parameter.number("gap")
        ]) { CarouselView(context: $0) }
    }
}

enum CarouselMetrics {
    static func trailingSpace(available: CGFloat, itemWidth: CGFloat) -> CGFloat {
        guard available.isFinite, itemWidth.isFinite else { return 0 }
        return max(0, available - itemWidth)
    }
    static func comparable(_ values: [Value]) -> Bool {
        guard let first = values.first else { return false }
        func surfaceKind(_ value: Value) -> String {
            if EditorialNode.kind(value) == "Card" {
                let children = ValueReading.array(ValueReading.field(value, "children"))
                if children.count == 1 { return EditorialNode.kind(children[0]) }
            }
            return EditorialNode.kind(value)
        }
        let kind = surfaceKind(first)
        return kind == "ProductCard" && values.allSatisfy { surfaceKind($0) == kind }
    }
    static func width(preferred: CGFloat, available: CGFloat, accessibility: Bool) -> CGFloat {
        let preferred = preferred.isFinite ? min(640, max(80, preferred)) : 240
        guard available.isFinite, available > 0 else { return preferred }
        return accessibility ? available : min(preferred, max(min(80, available), available * 0.85))
    }
    static func index(offset: CGFloat, itemWidth: CGFloat, gap: CGFloat, count: Int) -> Int {
        guard count > 0, offset.isFinite, itemWidth.isFinite, gap.isFinite else { return 0 }
        return Int(min(CGFloat(count - 1), max(0, (offset / max(1, itemWidth + gap)).rounded())))
    }
    static func currentIndex(current: Int, previousIDs: [String], newIDs: [String]) -> Int {
        guard !newIDs.isEmpty else { return 0 }
        if previousIDs.indices.contains(current), let index = newIDs.firstIndex(of: previousIDs[current]) { return index }
        return min(newIDs.count - 1, max(0, current))
    }
}

private struct CarouselView: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction
    @State private var available: CGFloat = 0
    @State private var current = 0
    @State private var previousIDs: [String] = []
    @State private var coordinateSpace = UUID()

    var body: some View {
        let children = context.children()
        let itemWidth = CarouselMetrics.width(preferred: CGFloat(context.number("itemWidth") ?? 240), available: available, accessibility: typeSize.isAccessibilitySize)
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: theme.innerSpacing) {
                scroll(children: children, itemWidth: itemWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAction(named: Text(SDKStrings.text("common.next", locale: locale))) { move(to: current + 1, children: children, proxy: proxy) }
                    .accessibilityAction(named: Text(SDKStrings.text("common.previous", locale: locale))) { move(to: current - 1, children: children, proxy: proxy) }
                #if os(macOS)
                if children.count > 1 {
                    HStack(spacing: theme.innerSpacing) {
                        Spacer()
                        Button { move(to: current - 1, children: children, proxy: proxy) } label: { Image(systemName: "chevron.backward") }
                            .accessibilityLabel(SDKStrings.text("common.previous", locale: locale)).disabled(current <= 0)
                        Button { move(to: current + 1, children: children, proxy: proxy) } label: { Image(systemName: "chevron.forward") }
                            .accessibilityLabel(SDKStrings.text("common.next", locale: locale)).disabled(current >= children.count - 1)
                    }.buttonStyle(.borderless).tint(theme.actionAccent)
                }
                #endif
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                guard width.isFinite, width > 0, width != available else { return }
                available = width
            }
            .onAppear { previousIDs = children.map(\.id) }
            .onChange(of: children.map(\.id)) { ids in reconcile(ids: ids, proxy: proxy) }
            .accessibilityScrollAction { edge in
                if edge == .trailing { move(to: current + 1, children: children, proxy: proxy) }
                else if edge == .leading { move(to: current - 1, children: children, proxy: proxy) }
            }
        }
    }

    @ViewBuilder private func scroll(children: [OpenUIRenderChild], itemWidth: CGFloat) -> some View {
        if #available(iOS 17, macOS 14, *) {
            ScrollView(.horizontal) { items(children, itemWidth: itemWidth).scrollTargetLayout() }
                .coordinateSpace(name: coordinateSpace)
                .scrollTargetBehavior(.viewAligned).scrollIndicators(.hidden, axes: .horizontal)
        } else {
            ScrollView(.horizontal) { items(children, itemWidth: itemWidth) }
                .coordinateSpace(name: coordinateSpace)
                .scrollIndicators(.hidden, axes: .horizontal)
        }
    }

    private func items(_ children: [OpenUIRenderChild], itemWidth: CGFloat) -> some View {
        EqualHeightCarouselLayout(itemWidth: itemWidth, gap: theme.spacing(context.number("gap"), fallback: 3),
            equalizesHeights: CarouselMetrics.comparable(children.map(\.value))) {
            ForEach(Array(children.enumerated()), id: \.element.id) { _, child in
                context.render(child.value)
                    .frame(width: itemWidth)
                    .id(child.id)
            }
        }
            // Let the final item reach the same leading alignment as every
            // other item. Without this space a short final viewport can never
            // produce the final logical index.
            .padding(.trailing, CarouselMetrics.trailingSpace(available: available, itemWidth: itemWidth))
            .padding(.bottom, theme.innerSpacing)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(coordinateSpace)) } action: { frame in
                let gap = theme.spacing(context.number("gap"), fallback: 3)
                let offset = direction == .rightToLeft ? frame.maxX - available : -frame.minX
                let index = CarouselMetrics.index(offset: offset, itemWidth: itemWidth, gap: gap, count: children.count)
                if current != index { current = index }
            }
            .environment(\.openIntelligentUIImageAlbum, ImageAlbumItem.collect(children.map(\.value)))
    }

    private func reconcile(ids: [String], proxy: ScrollViewProxy) {
        guard ids != previousIDs else { return }
        current = CarouselMetrics.currentIndex(current: current, previousIDs: previousIDs, newIDs: ids)
        previousIDs = ids
        guard !ids.isEmpty else { return }
        let id = ids[current]
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: direction == .rightToLeft ? .trailing : .leading) }
    }
    private func move(to index: Int, children: [OpenUIRenderChild], proxy: ScrollViewProxy) {
        guard context.canInteract, !children.isEmpty else { return }
        current = min(children.count - 1, max(0, index))
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(children[current].id, anchor: direction == .rightToLeft ? .trailing : .leading) }
    }
}

private struct EqualHeightCarouselLayout: Layout {
    let itemWidth: CGFloat
    let gap: CGFloat
    var equalizesHeights = true
    static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties(); properties.stackOrientation = .horizontal; return properties
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.init(width: itemWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: CGFloat(subviews.count) * itemWidth + CGFloat(max(0, subviews.count - 1)) * gap, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, view) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(index) * (itemWidth + gap)
            let height = equalizesHeights ? bounds.height : view.sizeThatFits(.init(width: itemWidth, height: nil)).height
            view.place(at: .init(x: x, y: bounds.minY), anchor: .topLeading, proposal: .init(width: itemWidth, height: height))
        }
    }
}
