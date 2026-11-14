import SwiftUI

/// Optional host presentation for a source. Existing Lang presentation arguments take precedence.
public struct IntelligentUIImagePresentation: Equatable, Sendable {
    public enum Fit: String, Sendable { case cover, contain }
    public var aspectRatio: Double?
    public var fit: Fit?

    public init(aspectRatio: Double? = nil, fit: Fit? = nil) {
        self.aspectRatio = aspectRatio
        self.fit = fit
    }
}

extension EnvironmentValues {
    /// Change a revision when the bytes behind an otherwise identical source change.
    @Entry public var intelligentUIImageRevisions: [String: String] = [:]
    @Entry public var intelligentUIImagePresentations: [String: IntelligentUIImagePresentation] = [:]
    /// Occlusion inside the map supplied by host overlays; safe area is added by the map itself.
    @Entry public var intelligentUIMapContentInsets: EdgeInsets? = nil
}

extension View {
    public func intelligentUIImageRevisions(_ revisions: [String: String]) -> some View {
        environment(\.intelligentUIImageRevisions, revisions)
    }

    public func intelligentUIImagePresentations(_ presentations: [String: IntelligentUIImagePresentation]) -> some View {
        environment(\.intelligentUIImagePresentations, presentations)
    }

    public func intelligentUIMapContentInsets(_ insets: EdgeInsets) -> some View {
        environment(\.intelligentUIMapContentInsets, insets)
    }
}

enum ImagePixelSize {
    /// Small quantized tiers avoid new requests for every point of a resize.
    static func target(points: CGSize, scale: CGFloat, zoom: CGFloat = 1, fallback: Int = 1600) -> Int {
        let pixels = max(points.width, points.height) * max(1, scale) * max(1, zoom)
        guard pixels.isFinite, pixels > 0 else { return fallback }
        return [256, 512, 1024, 1600, 2560, 4096].first { CGFloat($0) >= pixels } ?? 4096
    }

    static func ratio(_ value: Double?, fallback: CGFloat) -> CGFloat {
        guard let value, value.isFinite else { return fallback }
        return CGFloat(min(5, max(0.2, value)))
    }
}
