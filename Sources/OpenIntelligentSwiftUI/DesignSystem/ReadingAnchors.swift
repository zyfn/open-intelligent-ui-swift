import SwiftUI
import OpenSwiftUI

struct ReadingAnchor: Hashable {
    let owner: ObjectIdentifier
    let presentation: Int
    let child: String

    @MainActor init(state: IntelligentUIState, child: String) {
        owner = ObjectIdentifier(state)
        presentation = state.presentationRevision
        self.child = child
    }
}

private enum ReadingCoordinateSpace: Hashable { case content }

private struct ReadingFrames: PreferenceKey {
    static let defaultValue: [ReadingAnchor: CGRect] = [:]
    static func reduce(value: inout [ReadingAnchor: CGRect], nextValue: () -> [ReadingAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension EnvironmentValues {
    @Entry var intelligentUIReadingAnchors = false
    @Entry var intelligentUIReadingDepth = 0
}

enum ReadingPosition {
    static func anchor(in frames: [ReadingAnchor: CGRect], visible: CGRect) -> ReadingAnchor? {
        frames.filter { $0.value.intersects(visible) && $0.value.height > 0 }
            .min { $0.value.minY < $1.value.minY }?.key
    }

    static func displacement(of anchor: ReadingAnchor?, from previous: [ReadingAnchor: CGRect], to current: [ReadingAnchor: CGRect]) -> CGFloat {
        guard let anchor, let old = previous[anchor], let new = current[anchor] else { return 0 }
        let delta = new.minY - old.minY
        return delta.isFinite ? delta : 0
    }
}

@available(iOS 18, macOS 15, *)
private struct ReadingPositionModifier: ViewModifier {
    let enabled: Bool
    @State private var position = ScrollPosition()
    @State private var frames: [ReadingAnchor: CGRect] = [:]
    @State private var anchor: ReadingAnchor?
    @State private var viewport = ReadingViewport()
    @State private var scrolling = false

    func body(content: Content) -> some View {
        content.scrollPosition($position)
            .onScrollGeometryChange(for: ReadingViewport.self) { geometry in
                ReadingViewport(offset: geometry.contentOffset.y, visible: geometry.visibleRect, topInset: geometry.contentInsets.top)
            } action: { _, new in
                viewport = new
                LayoutTrace.record("reading-viewport", "offset=\(LayoutTrace.number(new.offset)) visibleY=\(LayoutTrace.number(new.visible.minY)) inset=\(LayoutTrace.number(new.topInset))")
                if scrolling || !enabled || anchor == nil { anchor = ReadingPosition.anchor(in: frames, visible: new.visible) }
            }
            .onScrollPhaseChange { _, phase in
                scrolling = phase != .idle
                anchor = ReadingPosition.anchor(in: frames, visible: viewport.visible)
            }
            .onChange(of: enabled) { _ in anchor = ReadingPosition.anchor(in: frames, visible: viewport.visible) }
            .onPreferenceChange(ReadingFrames.self) { current in
                let delta = ReadingPosition.displacement(of: anchor, from: frames, to: current)
                frames = current
                if enabled && !scrolling && viewport.visible.height > 0 && abs(delta) > 0.5 {
                    LayoutTrace.record("reading-compensation", "delta=\(LayoutTrace.number(delta)) offset=\(LayoutTrace.number(viewport.offset)) inset=\(LayoutTrace.number(viewport.topInset))")
                    // Native point scrolling normalizes the top content inset;
                    // geometry.contentOffset (and visibleRect) does not.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { position.scrollTo(y: viewport.offset + viewport.topInset + delta) }
                } else if anchor.map({ current[$0] == nil }) ?? true {
                    anchor = ReadingPosition.anchor(in: current, visible: viewport.visible)
                }
            }
    }
}

private struct ReadingViewport: Equatable {
    var offset: CGFloat = 0
    var visible: CGRect = .zero
    var topInset: CGFloat = 0
}

extension View {
    /// Apply to the Host's vertical ScrollView content, after its padding.
    /// Positions are measured in content coordinates, independently of dragging.
    public func intelligentUIReadingContent(_ enabled: Bool = true) -> some View {
        environment(\.intelligentUIReadingAnchors, enabled)
            .coordinateSpace(name: ReadingCoordinateSpace.content)
    }

    /// Apply to the owning ScrollView. Enable while reading; disable while
    /// following the latest output. User scrolling always suspends correction.
    @ViewBuilder public func intelligentUIReadingPosition(enabled: Bool) -> some View {
        if #available(iOS 18, macOS 15, *) { modifier(ReadingPositionModifier(enabled: enabled)) }
        else { self }
    }

    func intelligentUIReadingTarget(_ anchor: ReadingAnchor?) -> some View {
        background {
            if let anchor {
                GeometryReader { geometry in
                    Color.clear.preference(key: ReadingFrames.self, value: [anchor: geometry.frame(in: .named(ReadingCoordinateSpace.content))])
                }
            }
        }
    }
}
