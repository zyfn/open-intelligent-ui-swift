import SwiftUI
import SwiftLang

/// Parent layout decisions are scoped to one rendered child. They are not
/// model-facing options, and a container supplies fresh decisions to its children.
enum IntelligentUIDimensionPolicy: Equatable { case natural, stretch, allocated }

struct IntelligentUIItemSizing {
    var width: IntelligentUIDimensionPolicy = .stretch
    var height: IntelligentUIDimensionPolicy = .natural
    var hasDefiniteHeight = false

    static func forChild(_ value: Value, width: IntelligentUIDimensionPolicy,
                         height: IntelligentUIDimensionPolicy, hasDefiniteHeight: Bool) -> Self {
        // Only these containers consume this policy and establish a new one
        // for their own children. A Card/Form/etc. must not pass an allocation
        // through to a descendant Box which is not the parent's flex item.
        guard ["Box", "Col", "Row"].contains(EditorialNode.kind(value)) else { return Self() }
        return Self(width: width, height: height, hasDefiniteHeight: hasDefiniteHeight)
    }
}

extension EnvironmentValues {
    @Entry var openIntelligentUIItemSizing = IntelligentUIItemSizing()
    @Entry var openIntelligentUIRowMediaAspectRatio: CGFloat? = nil
}

extension View {
    func openIntelligentUIStretchWidth(_ enabled: Bool) -> some View {
        IntelligentUIWidthLayout(stretches: enabled) { self }
    }
}

/// Preserve the child's proposal and identity while optionally filling width.
/// A flexible frame can re-propose the child's measured percentage height;
/// conditionally adding/removing that frame would also replace its view subtree.
private struct IntelligentUIWidthLayout: Layout {
    let stretches: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measured = subviews.first?.sizeThatFits(proposal) ?? .zero
        let available = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
        return CGSize(width: stretches ? available ?? measured.width : measured.width, height: measured.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }
}

enum FlexGeometry {
    static func length(_ value: CGFloat) -> CGFloat { value.isFinite ? max(0, value) : 0 }
    static func sum(_ values: [CGFloat]) -> CGFloat {
        values.reduce(0) { partial, value in
            let next = partial + length(value)
            return next.isFinite ? next : .greatestFiniteMagnitude
        }
    }
}

enum RowMediaKind: Equatable { case none, direct, boxed }

enum RowMediaRules {
    static func kind(_ value: Value) -> RowMediaKind {
        if ["Image", "SearchImage"].contains(EditorialNode.kind(value)) { return .direct }
        guard EditorialNode.kind(value) == "Box" else { return .none }
        let children = OpenUIRenderChild.children(of: ValueReading.field(value, "children") ?? .null)
        return children.count == 1 && ["Image", "SearchImage"].contains(EditorialNode.kind(children[0].value)) ? .boxed : .none
    }
    static func width(in row: CGFloat) -> CGFloat { min(200, max(120, FlexGeometry.length(row) * 0.33)) }
    static func hasDirectPhoto(_ children: [OpenUIRenderChild]) -> Bool { children.contains { kind($0.value) == .direct } }
}

struct IntelligentUIFlexItem {
    var grow: CGFloat?
    var numericWidth = false
    var width: IntelligentUILength?
    var height: IntelligentUILength?
    var fontUnit: CGFloat = 17
    var insets: CGFloat = 0
    var isBox = false
    var media: RowMediaKind = .none

    static func read(_ value: Value, theme: OpenIntelligentUITheme, fontUnit: CGFloat) -> Self {
        let box = EditorialNode.kind(value) == "Box"
        let grow = box ? ValueReading.number(ValueReading.field(value, "flex")).map { _ in RowFlexRules.weight(value) }
            : EditorialNode.kind(value) == "Spacer" ? CGFloat(1) : nil
        let inset = box ? theme.spacing(ValueReading.number(ValueReading.field(value, "padding")))
            + (ValueReading.field(value, "border") == .boolean(true) ? 1 : 0) : 0
        return Self(grow: grow, numericWidth: box && ValueReading.number(ValueReading.field(value, "width")) != nil,
            width: box ? IntelligentUILength.read(ValueReading.field(value, "width")) : nil,
            height: box ? IntelligentUILength.read(ValueReading.field(value, "height")) : nil,
            fontUnit: fontUnit, insets: FlexGeometry.sum([inset, inset]), isBox: box, media: RowMediaRules.kind(value))
    }
}

struct IntelligentUIFlexItemKey: LayoutValueKey { static let defaultValue: IntelligentUIFlexItem? = nil }
struct ColumnGapBefore: LayoutValueKey { static let defaultValue: CGFloat = 0 }

/// Outer flex bases include padding/border. Only the content portion shrinks.
/// The rules mirror flex-grow / flex-shrink / flex-basis, including fractional
/// grow factors below one and an explicitly supplied zero grow factor.
struct FlexBasis {
    var basis: CGFloat
    var minimum: CGFloat = 0
    var grow: CGFloat = 0
    var shrink: CGFloat = 1
    var insets: CGFloat = 0
}

enum FlexDistribution {
    static func lengths(_ supplied: [FlexBasis], available: CGFloat) -> [CGFloat] {
        let items = supplied.map { FlexBasis(basis: FlexGeometry.length($0.basis), minimum: FlexGeometry.length($0.minimum),
            grow: FlexGeometry.length($0.grow), shrink: FlexGeometry.length($0.shrink), insets: FlexGeometry.length($0.insets)) }
        let available = FlexGeometry.length(available)
        let hypothetical = items.map { max($0.basis, $0.minimum) }
        let growing = FlexGeometry.sum(hypothetical) < available
        var result = items.map(\.basis)
        var pending: [Int] = []
        for index in items.indices {
            let factor = growing ? items[index].grow : items[index].shrink
            if factor == 0 || (!growing && items[index].basis < hypothetical[index]) { result[index] = hypothetical[index] }
            else { pending.append(index) }
        }
        let initiallyActive = Set(pending)
        let initialFree = available - FlexGeometry.sum(items.indices.map { initiallyActive.contains($0) ? items[$0].basis : result[$0] })
        while !pending.isEmpty {
            let active = Set(pending)
            var free = available - FlexGeometry.sum(items.indices.map { active.contains($0) ? items[$0].basis : result[$0] })
            let factors = pending.map { growing ? items[$0].grow : items[$0].shrink }
            let factorSum = FlexGeometry.sum(factors)
            if growing && factorSum < 1 && abs(initialFree * factorSum) < abs(free) { free = initialFree * factorSum }
            let weights = pending.map { index in
                growing ? items[index].grow : items[index].shrink * max(0, items[index].basis - items[index].insets)
            }
            let largest = weights.max() ?? 0
            guard largest > 0, largest.isFinite else {
                for index in pending { result[index] = max(items[index].minimum, items[index].basis) }
                break
            }
            let normalized = weights.map { $0 / largest }
            let total = normalized.reduce(0, +)
            var constrained = Set<Int>()
            for (offset, index) in pending.enumerated() {
                let target = items[index].basis + free * normalized[offset] / total
                result[index] = max(items[index].minimum, target.isFinite ? target : items[index].basis)
                if target < items[index].minimum { constrained.insert(index) }
            }
            if constrained.isEmpty { break }
            pending.removeAll { constrained.contains($0) }
        }
        return result
    }
}

/// Columns distribute vertical flex only when an ancestor established a finite
/// height. An ordinary message Col keeps natural height in a tall window.
struct IntelligentUIColumnLayout: Layout {
    var alignment = "stretch"
    var justification = "start"
    var gap: CGFloat = 0
    var wraps = false
    var boundedHeight = false
    var viewport: CGSize?

    static var layoutProperties: LayoutProperties {
        var value = LayoutProperties(); value.stackOrientation = .vertical; return value
    }

    private func geometry(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect], proposals: [ProposedViewSize]) {
        guard !subviews.isEmpty else { return (.zero, [], []) }
        let gap = FlexGeometry.length(gap)
        let intrinsic = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
            ?? intrinsic.map { FlexGeometry.length($0.width) }.max() ?? 0
        let height = boundedHeight ? proposal.height.flatMap { $0.isFinite ? max(0, $0) : nil } : nil
        let margins = subviews.map { FlexGeometry.length($0[ColumnGapBefore.self]) }
        let metadata = subviews.map { $0[IntelligentUIFlexItemKey.self] ?? IntelligentUIFlexItem() }
        let natural = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
        let items = subviews.indices.map { index -> FlexBasis in
            let item = metadata[index]
            let ideal = FlexGeometry.length(natural[index].height)
            let declared = item.height?.resolve(relativeTo: height, em: item.fontUnit, viewport: viewport)
            let minimum = max(item.insets, min(ideal, declared ?? ideal))
            // An indefinite 0% flex-basis resolves to content, not the authored
            // height. The declared size still caps the automatic minimum.
            let basis = item.grow != nil ? (height != nil ? item.insets : ideal) : declared ?? ideal
            return FlexBasis(basis: max(item.insets, basis), minimum: minimum, grow: item.grow ?? 0,
                shrink: item.grow == nil && item.numericWidth ? 0 : 1, insets: item.insets)
        }
        var columns: [[Int]] = [[]]
        var used: CGFloat = 0
        for index in subviews.indices {
            let itemHeight = max(items[index].basis, items[index].minimum) + margins[index]
            let next = used + (columns[columns.count - 1].isEmpty ? 0 : gap) + itemHeight
            if wraps, let height, next > height, !columns[columns.count - 1].isEmpty { columns.append([]); used = 0 }
            used += (columns[columns.count - 1].isEmpty ? 0 : gap) + itemHeight
            columns[columns.count - 1].append(index)
        }
        var columnWidths = columns.map { column -> CGFloat in
            guard columns.count > 1 else { return width }
            return column.map { index in
                let item = metadata[index]
                return item.width?.resolve(relativeTo: width, em: item.fontUnit, viewport: viewport)
                    ?? min(width, FlexGeometry.length(intrinsic[index].width))
            }.max() ?? 0
        }
        if columns.count > 1 {
            let spare = max(0, width - FlexGeometry.sum(columnWidths) - CGFloat(columns.count - 1) * gap)
            columnWidths = columnWidths.map { $0 + spare / CGFloat(columns.count) }
        }
        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        var proposals = Array(repeating: ProposedViewSize.unspecified, count: subviews.count)
        var x: CGFloat = 0, totalHeight: CGFloat = 0
        for (columnIndex, column) in columns.enumerated() {
            let columnWidth = columnWidths[columnIndex]
            let spacing = FlexGeometry.sum(column.map { margins[$0] }) + CGFloat(max(0, column.count - 1)) * gap
            let heights = height.map { FlexDistribution.lengths(column.map { items[$0] }, available: max(0, $0 - spacing)) }
                ?? column.map { max(items[$0].basis, items[$0].minimum) }
            let contentHeight = FlexGeometry.sum(heights) + spacing
            let usedHeight = height ?? contentHeight
            let spare = usedHeight - contentHeight
            let between = justification == "between" && column.count > 1 ? max(0, spare) / CGFloat(column.count - 1) : 0
            var y = justification == "center" ? spare / 2 : justification == "end" ? spare : 0
            for (offset, index) in column.enumerated() {
                let childProposal = ProposedViewSize(width: metadata[index].width != nil ? width : columnWidth,
                                                     height: heights[offset])
                let measured = subviews[index].sizeThatFits(childProposal)
                let childWidth = FlexGeometry.length(measured.width)
                let spareWidth = columnWidth - childWidth
                let cross = alignment == "center" ? spareWidth / 2 : alignment == "end" ? spareWidth : 0
                y += margins[index] + (offset == 0 ? 0 : gap + between)
                let left = x + cross
                frames[index] = CGRect(x: left, y: y, width: childWidth, height: heights[offset])
                proposals[index] = childProposal
                y += heights[offset]
            }
            totalHeight = max(totalHeight, usedHeight)
            x += columnWidth + gap
        }
        return (CGSize(width: width, height: totalHeight), frames, proposals)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        geometry(proposal: proposal, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = geometry(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for index in subviews.indices {
            let frame = result.frames[index]
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 anchor: .topLeading, proposal: result.proposals[index])
        }
    }
}
