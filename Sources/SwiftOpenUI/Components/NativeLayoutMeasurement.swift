import SwiftLang
import Foundation

/// One nonwrapping row negotiation. All measurements are local to this call;
/// no result survives source, environment, proposal, or layout changes.
enum NativeFlexRowWidths {
    static func proposals(ideal: [CGFloat], growing: [Bool], width: CGFloat, gap: CGFloat,
                          minimums: [CGFloat?] = [],
                          measure: (Int, CGFloat) -> CGFloat) -> [CGFloat] {
        guard !ideal.isEmpty else { return [] }
        let declared = ideal.indices.map { index -> CGFloat? in
            guard minimums.indices.contains(index), let value = minimums[index], value.isFinite else { return nil }
            return max(0, value)
        }
        let basis = ideal.indices.map { growing[$0] && declared[$0] != nil ? 0 : ideal[$0] }
        var proposals = basis.map { min(width, $0) }
        let flexible = ideal.indices.filter { growing[$0] }
        var measuredWidths: [CGFloat?] = flexible.isEmpty ? [] : Array(repeating: nil, count: ideal.count)
        // Declared zero-basis items reserve only their outer insets while
        // intrinsic siblings negotiate. Streaming copy must not change their
        // place in the measurement order or the space offered to a sibling.
        var remaining = max(0, width - gap * CGFloat(ideal.count - 1))
        let order = ideal.indices.sorted { basis[$0] < basis[$1] }
        for (position, index) in order.enumerated() {
            if growing[index], let minimum = declared[index] {
                remaining = max(0, remaining - minimum)
                continue
            }
            let offered = min(basis[index], remaining / CGFloat(order.count - position))
            proposals[index] = max(0, offered)
            let measured = measure(index, offered)
            remaining = max(0, remaining - measured)
            // A malformed negative/nonfinite ideal can change after clamping.
            // Only reuse a measurement when the subsequent proposal is equal.
            if !flexible.isEmpty, !growing[index], offered == proposals[index] {
                measuredWidths[index] = measured
            }
        }
        if !flexible.isEmpty {
            let intrinsicWidth = ideal.indices.filter { !growing[$0] }.reduce(CGFloat.zero) { sum, index in
                sum + (measuredWidths[index] ?? measure(index, proposals[index]))
            }
            let widths = shares(available: width - gap * CGFloat(ideal.count - 1) - intrinsicWidth,
                minimums: flexible.map { declared[$0] ?? 0 })
            for (index, value) in zip(flexible, widths) { proposals[index] = value }
        }
        return proposals
    }

    /// Equal zero-basis flex factors share outer widths. Insets constrain the
    /// result only when an equal share is too small; they are not added on top
    /// of an equal share, which would bias mixed clear/card rows.
    static func shares(available: CGFloat, minimums: [CGFloat]) -> [CGFloat] {
        var widths = minimums
        var flexible = Array(minimums.indices)
        var remaining = max(0, available)
        while !flexible.isEmpty {
            let share = remaining / CGFloat(flexible.count)
            let fixed = flexible.filter { minimums[$0] > share }
            if fixed.isEmpty {
                flexible.forEach { widths[$0] = share }
                break
            }
            for index in fixed { remaining = max(0, remaining - minimums[index]) }
            flexible.removeAll { fixed.contains($0) }
        }
        return widths
    }
}

enum NativeMediaRowAxis { case horizontal, vertical }

/// Media keeps its declared dimensions; copy wraps in the remaining space.
/// Direction is explicit rather than inferred from the length of the copy.
enum NativeMediaRowPlacement {
    struct Result {
        var media: CGRect
        var text: CGRect
        var size: CGSize
        var stacked: Bool
    }

    static func measure(width: CGFloat, media idealMedia: CGSize, gap: CGFloat,
                        axis: NativeMediaRowAxis,
                        centered: Bool, text: (CGFloat) -> CGSize) -> Result {
        let width = width.isFinite ? max(1, width) : 1
        func finite(_ value: CGFloat) -> CGFloat { value.isFinite ? max(0, value) : 0 }
        func copy(_ proposed: CGFloat) -> CGSize {
            let measured = text(max(1, proposed))
            return CGSize(width: max(max(1, proposed), finite(measured.width)), height: finite(measured.height))
        }
        let media = CGSize(width: finite(idealMedia.width), height: finite(idealMedia.height))
        let gap = media.width > 0 && media.height > 0 ? max(0, gap) : 0
        let remaining = max(0, width - media.width - gap)
        if axis == .vertical {
            let full = copy(width)
            let textFrame = CGRect(x: 0, y: media.height + gap, width: full.width, height: full.height)
            return Result(media: CGRect(origin: CGPoint(x: centered ? max(0, (width - media.width) / 2) : 0, y: 0), size: media), text: textFrame,
                          size: CGSize(width: max(width, max(media.width, full.width)), height: textFrame.maxY), stacked: true)
        }

        // Explicit horizontal layout remains horizontal. Preserve fixed media
        // dimensions and give over-constrained copy its full viewport width.
        // Scrolling then reveals that readable paragraph without a private
        // minimum width, smaller font, or automatic direction change.
        let measured: CGSize
        if remaining <= 0 {
            measured = copy(width)
        } else {
            let beside = copy(remaining)
            measured = beside.width > remaining + 0.5 ? copy(width) : beside
        }
        let height = max(media.height, measured.height)
        let mediaY = centered ? (height - media.height) / 2 : 0
        let textY = centered ? (height - measured.height) / 2 : 0
        let textFrame = CGRect(x: media.width + gap, y: textY, width: measured.width, height: measured.height)
        return Result(media: CGRect(origin: CGPoint(x: 0, y: mediaY), size: media), text: textFrame,
                      size: CGSize(width: max(width, textFrame.maxX), height: height), stacked: false)
    }
}

