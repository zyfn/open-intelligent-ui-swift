import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum CarouselComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Carousel", description: "Horizontal collection with adaptive equal-height items, native snapping on iOS 17/macOS 14+ and desktop navigation. itemWidth is the preferred width (default 240), gap uses 4-point units.", params: [
            OpenUIParameter.slot("children", required: true), Parameter.number("itemWidth", minimum: 80, maximum: 640), Parameter.number("gap", minimum: 0, maximum: 24)
        ]) { CarouselView(context: $0) }
    }
}

enum CarouselMetrics {
    static func width(preferred: CGFloat, available: CGFloat, accessibility: Bool) -> CGFloat {
        let preferred = preferred.isFinite ? min(640, max(80, preferred)) : 240
        guard available > 0 else { return preferred }
        return accessibility ? available : min(preferred, max(min(80, available), available * 0.85))
    }
    static func index(offset: CGFloat, itemWidth: CGFloat, gap: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, Int((offset / max(1, itemWidth + gap)).rounded())))
    }
    static func currentIndex(current: Int, previousIDs: [String], newIDs: [String]) -> Int {
        guard !newIDs.isEmpty else { return 0 }
        if previousIDs.indices.contains(current), let index = newIDs.firstIndex(of: previousIDs[current]) { return index }
        return min(newIDs.count - 1, max(0, current))
    }
}

private struct CarouselView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .accessibilityAction(named: "下一个") { move(to: current + 1, children: children, proxy: proxy) }
                    .accessibilityAction(named: "上一个") { move(to: current - 1, children: children, proxy: proxy) }
                #if os(macOS)
                if children.count > 1 {
                    HStack(spacing: theme.innerSpacing) {
                        Spacer()
                        Button { move(to: current - 1, children: children, proxy: proxy) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("上一个").disabled(current <= 0)
                        Button { move(to: current + 1, children: children, proxy: proxy) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("下一个").disabled(current >= children.count - 1)
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
        if #available(iOS 18, macOS 15, *) {
            ScrollView(.horizontal) { items(children, itemWidth: itemWidth).scrollTargetLayout() }
                .coordinateSpace(name: coordinateSpace)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden, axes: .horizontal)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, offset in
                    let gap = CGFloat(min(24, max(0, context.number("gap") ?? 3))) * theme.spacingUnit
                    current = CarouselMetrics.index(offset: offset, itemWidth: itemWidth, gap: gap, count: children.count)
                }
        } else if #available(iOS 17, macOS 14, *) {
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
        EqualHeightCarouselLayout(itemWidth: itemWidth, gap: CGFloat(min(24, max(0, context.number("gap") ?? 3))) * theme.spacingUnit) {
            ForEach(Array(children.enumerated()), id: \.element.id) { _, child in
                context.render(child.value)
                    .environment(\.intelligentUIEditorial, EditorialContext(compactContent: EditorialNode.kind(child.value) == "Col"))
                    .frame(width: itemWidth)
                    .id(child.id)
            }
        }.padding(.bottom, theme.innerSpacing)
            .background(GeometryReader { geometry in
                Color.clear.onChange(of: geometry.frame(in: .named(coordinateSpace)).minX) { minX in
                    let gap = CGFloat(min(24, max(0, context.number("gap") ?? 3))) * theme.spacingUnit
                    current = CarouselMetrics.index(offset: -minX, itemWidth: itemWidth, gap: gap, count: children.count)
                }
            })
            .environment(\.intelligentUIImageAlbum, ImageAlbumItem.collect(children.map(\.value)))
    }

    private func reconcile(ids: [String], proxy: ScrollViewProxy) {
        guard ids != previousIDs else { return }
        current = CarouselMetrics.currentIndex(current: current, previousIDs: previousIDs, newIDs: ids)
        previousIDs = ids
        guard !ids.isEmpty else { return }
        let id = ids[current]
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .leading) }
    }
    private func move(to index: Int, children: [OpenUIRenderChild], proxy: ScrollViewProxy) {
        guard context.canInteract, !children.isEmpty else { return }
        current = min(children.count - 1, max(0, index))
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(children[current].id, anchor: .leading) }
    }
}

private struct EqualHeightCarouselLayout: Layout {
    let itemWidth: CGFloat
    let gap: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.init(width: itemWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: CGFloat(subviews.count) * itemWidth + CGFloat(max(0, subviews.count - 1)) * gap, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, view) in subviews.enumerated() {
            view.place(at: .init(x: bounds.minX + CGFloat(index) * (itemWidth + gap), y: bounds.minY), proposal: .init(width: itemWidth, height: bounds.height))
        }
    }
}
