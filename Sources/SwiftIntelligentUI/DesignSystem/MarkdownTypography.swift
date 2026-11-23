import SwiftUI
import MarkdownUI
import CoreText
import Foundation

/// MarkdownUI 2.4.1 resolves attributed fonts from FontProperties rather than
/// the surrounding SwiftUI font. Keep this adapter at that presentation edge.
struct MarkdownFontStyle: MarkdownUI.TextStyle {
    let family: FontProperties.Family
    let size: CGFloat
    let weight: Font.Weight
    let italic: Bool
    let tabular: Bool

    @MainActor init(_ font: PlatformFont, usesSystemFamily: Bool = true, size: CGFloat? = nil, weight: Font.Weight? = nil) {
        let traits = CTFontGetSymbolicTraits(font as CTFont)
        if !usesSystemFamily, !font.fontName.hasPrefix("."),
           PlatformFont(name: font.fontName, size: font.pointSize)?.fontName == font.fontName {
            // Only an explicit host override with a resolvable named face uses
            // the custom-family path. Private platform names such as .SFUI
            // are not Font.custom names even if UIFont can resolve them.
            family = .custom(font.fontName)
        } else {
            family = .system(traits.contains(.traitMonoSpace) ? .monospaced : .default)
        }
        self.size = size ?? font.pointSize
        let nativeWeight = (CTFontCopyTraits(font as CTFont) as NSDictionary)[kCTFontWeightTrait] as? NSNumber
        let candidates: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        self.weight = weight ?? candidates.min {
            abs(Double(InlineFonts.weight($0).rawValue) - (nativeWeight?.doubleValue ?? 0))
                < abs(Double(InlineFonts.weight($1).rawValue) - (nativeWeight?.doubleValue ?? 0))
        } ?? .regular
        italic = traits.contains(.traitItalic)
        let settings = CTFontCopyFeatureSettings(font as CTFont) as? [[String: Any]] ?? []
        tabular = settings.contains {
            ($0[kCTFontFeatureTypeIdentifierKey as String] as? NSNumber)?.intValue == Int(kNumberSpacingType)
                && ($0[kCTFontFeatureSelectorIdentifierKey as String] as? NSNumber)?.intValue == Int(kMonospacedNumbersSelector)
        }
    }

    func _collectAttributes(in attributes: inout AttributeContainer) {
        FontFamily(family)._collectAttributes(in: &attributes)
        FontSize(size)._collectAttributes(in: &attributes)
        FontWeight(weight)._collectAttributes(in: &attributes)
        FontStyle(italic ? .italic : .normal)._collectAttributes(in: &attributes)
        FontDigitVariant(tabular ? .monospaced : .normal)._collectAttributes(in: &attributes)
    }
}

enum MarkdownTypography {
    static func usesSemanticHeading(level: Int, theme: OpenIntelligentUITheme) -> Bool {
        (1...3).contains(level) && !theme.hasCustomMarkdownHeadingScales
    }

    #if os(macOS)
    struct HeadingMetricsKey: Hashable {
        let semanticFont: Font
        let fixedFont: Font
        let typeSize: DynamicTypeSize
        let displayScale: CGFloat
        let locale: Locale
        let legibilityWeight: LegibilityWeight?
        let layoutDirection: LayoutDirection
    }

    // Only scalar metrics survive a measurement; renderers and their content
    // are released immediately. The small bound also limits retained Fonts.
    @MainActor static var headingSpacingCache: [HeadingMetricsKey: CGFloat] = [:]
    static let maximumHeadingSpacingEntries = 32

    /// MarkdownUI rebuilds a semantic font at a rounded fixed size. Measure
    /// SwiftUI's actual baseline advance: AppKit leading alone does not include
    /// the same line-box rounding and fallback-font behavior.
    @MainActor static func semanticHeadingLineSpacing(_ font: Font, style: MarkdownFontStyle,
                                                      typeSize: DynamicTypeSize, displayScale: CGFloat,
                                                      locale: Locale, legibilityWeight: LegibilityWeight?,
                                                      layoutDirection: LayoutDirection) -> CGFloat? {
        let fixed = Font.system(size: style.size.rounded()).weight(style.weight)
        let key = HeadingMetricsKey(semanticFont: font, fixedFont: fixed, typeSize: typeSize,
                                    displayScale: displayScale, locale: locale,
                                    legibilityWeight: legibilityWeight, layoutDirection: layoutDirection)
        if let cached = headingSpacingCache[key] { return cached }

        let result = HeadingSpacingMeasurement()
        let calibration = Canvas(rendersAsynchronously: false) { context, _ in
            let area = CGSize(width: 1_000, height: 1_000)
            let semantic = context.resolve(Text(verbatim: "Heading\nHeading").font(font))
            let rebuilt = context.resolve(Text(verbatim: "Heading\nHeading").font(fixed))
            let nativeAdvance = semantic.lastBaseline(in: area) - semantic.firstBaseline(in: area)
            let fixedAdvance = rebuilt.lastBaseline(in: area) - rebuilt.firstBaseline(in: area)
            guard nativeAdvance.isFinite, fixedAdvance.isFinite,
                  nativeAdvance > 0, fixedAdvance > 0 else { return }
            result.record(max(0, nativeAdvance - fixedAdvance))
        }
        .frame(width: 1, height: 1)
        .environment(\.dynamicTypeSize, typeSize)
        .environment(\.displayScale, displayScale)
        .environment(\.locale, locale)
        .environment(\.legibilityWeight, legibilityWeight)
        .environment(\.layoutDirection, layoutDirection)
        .environment(\.lineSpacing, 0)
        let renderer = ImageRenderer(content: calibration)
        renderer.scale = displayScale
        guard renderer.cgImage != nil, let spacing = result.value else {
            return nil
        }
        if headingSpacingCache.count >= maximumHeadingSpacingEntries {
            headingSpacingCache.removeAll(keepingCapacity: true)
        }
        headingSpacingCache[key] = spacing
        return spacing
    }
    #endif

    static func headingScale(level: Int, theme: OpenIntelligentUITheme) -> Double {
        switch level {
        case 1...3: return theme.headingScale(level - 1)
        case 4: return 1
        case 5: return 0.83
        default: return 0.67
        }
    }

    static func nativeHeadingStyle(level: Int) -> PlatformFont.TextStyle {
        switch level {
        case 1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }
}

#if os(macOS)
/// This is a synchronous rendering result, not observable view or SDK state.
private final class HeadingSpacingMeasurement: @unchecked Sendable {
    private let lock = NSLock()
    private var measured: CGFloat?

    func record(_ value: CGFloat) {
        lock.lock()
        defer { lock.unlock() }
        measured = value
    }

    var value: CGFloat? {
        lock.lock()
        defer { lock.unlock() }
        return measured
    }
}
#endif
