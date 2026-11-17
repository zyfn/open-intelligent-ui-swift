import SwiftUI
import MarkdownUI
import CoreText

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
        if !usesSystemFamily, PlatformFont(name: font.fontName, size: font.pointSize)?.fontName == font.fontName {
            // Only an explicit host override with a resolvable named face uses
            // the custom-family path. Default system fonts stay semantic.
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
    /// MarkdownUI scales its root size relative to body. The supplied native
    /// font already reflects Dynamic Type (or an explicit fixed font partner).
    static func rootSize(_ size: CGFloat, bodyScale: CGFloat) -> CGFloat {
        size / max(bodyScale, .leastNonzeroMagnitude)
    }

    static func usesSemanticHeading(level: Int, theme: OpenIntelligentUITheme) -> Bool {
        (1...3).contains(level) && !theme.hasCustomMarkdownHeadingScales
    }

    #if os(macOS)
    @MainActor static func measureHeadingFont(_ font: Font, size: DynamicTypeSize,
                                              displayScale: CGFloat? = nil, text: String = "Ag\nAg") -> HeadingFontMeasurement {
        let result = HeadingFontMeasurementBox()
        let content = HeadingFontMeasurementLayout(result: result) {
            Text(verbatim: text).font(font).lineSpacing(0).fixedSize()
        }.environment(\.dynamicTypeSize, size)
        let view = displayScale.map { AnyView(content.environment(\.displayScale, $0)) } ?? AnyView(content)
        let host = NSHostingView(rootView: view)
        let fitted = host.fittingSize
        var measured = result.value
        measured.fittingHeight = fitted.height
        return measured
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
struct HeadingFontMeasurement {
    var firstBaseline: CGFloat = 0
    var lastBaseline: CGFloat = 0
    var fittingHeight: CGFloat = 0
    var advance: CGFloat { lastBaseline - firstBaseline }
}

private final class HeadingFontMeasurementBox {
    var value = HeadingFontMeasurement()
}

private struct HeadingFontMeasurementLayout: Layout {
    let result: HeadingFontMeasurementBox

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let dimensions = text.dimensions(in: .unspecified)
        result.value.firstBaseline = dimensions[.firstTextBaseline]
        result.value.lastBaseline = dimensions[.lastTextBaseline]
        return CGSize(width: dimensions.width, height: dimensions.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
    }
}
#endif
