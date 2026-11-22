import Foundation
import SwiftUI

/// Absolute sRGB CSS colors that can be represented without a browser or a
/// resource lookup. Unsupported color spaces, relative colors and CSS-wide
/// keywords return nil; they are never interpreted as expressions or URLs.
enum CSSColor {
    struct RGBA: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        var color: Color {
            Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
        }
    }

    static func parse(_ source: String) -> RGBA? {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "transparent" { return RGBA(red: 0, green: 0, blue: 0, alpha: 0) }
        if let hex = namedColors[value] { return rgba(hex, alpha: 1) }
        if value.hasPrefix("#") { return hexadecimal(String(value.dropFirst())) }
        guard let start = value.firstIndex(of: "("), value.hasSuffix(")") else { return nil }
        let function = String(value[..<start])
        guard ["rgb", "rgba", "hsl", "hsla"].contains(function),
              let args = arguments(String(value[value.index(after: start)..<value.index(before: value.endIndex)]))
        else { return nil }
        let opacity: Double
        if let alpha = args.alpha {
            guard let parsed = channel(alpha, scale: 1) else { return nil }
            opacity = parsed
        } else { opacity = 1 }
        if function == "rgb" || function == "rgba" {
            // The comma form cannot mix numbers with percentages. The modern
            // space-separated form permits each channel to choose either.
            let percentages = args.channels.filter { $0.hasSuffix("%") }.count
            guard !args.commas || percentages == 0 || percentages == 3,
                  let red = channel(args.channels[0], scale: 255),
                  let green = channel(args.channels[1], scale: 255),
                  let blue = channel(args.channels[2], scale: 255) else { return nil }
            return RGBA(red: red, green: green, blue: blue, alpha: opacity)
        }
        guard let hue = hue(args.channels[0]),
              args.channels[1].hasSuffix("%"), args.channels[2].hasSuffix("%"),
              let saturation = channel(args.channels[1], scale: 1),
              let lightness = channel(args.channels[2], scale: 1) else { return nil }
        let amplitude = saturation * min(lightness, 1 - lightness)
        func component(_ offset: Double) -> Double {
            let k = (offset + hue * 12).truncatingRemainder(dividingBy: 12)
            return lightness - amplitude * max(-1, min(min(k - 3, 9 - k), 1))
        }
        return RGBA(red: component(0), green: component(8), blue: component(4), alpha: opacity)
    }

    /// Matches upstream shared/color.ts: only 3/6-digit hex and the integer
    /// rgb[a] prefix participate in automatic contrast. Alpha is ignored by
    /// that rule; HSL, names and 4/8-digit hex do not acquire a new heuristic.
    static func contrastInk(on source: String) -> RGBA? {
        guard let color = parse(source) else { return nil }
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let rgb: [Double]
        if value.range(of: #"^#(?:[0-9a-f]{3}|[0-9a-f]{6})$"#,
                       options: [.regularExpression, .caseInsensitive]) != nil {
            rgb = [color.red * 255, color.green * 255, color.blue * 255]
        } else {
            guard let regex = try? NSRegularExpression(pattern: #"^rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)"#,
                                                       options: .caseInsensitive),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
            else { return nil }
            rgb = (1...3).compactMap { index in
                Range(match.range(at: index), in: value).flatMap { Double(String(value[$0])) }
            }
            guard rgb.count == 3, rgb.allSatisfy(\.isFinite) else { return nil }
        }
        let linear = rgb.map { channel -> Double in
            let value = channel / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        return luminance > 0.36 ? rgba(0x0d0d0d, alpha: 1) : rgba(0xffffff, alpha: 1)
    }

    private static func hexadecimal(_ digits: String) -> RGBA? {
        guard [3, 4, 6, 8].contains(digits.count),
              digits.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let value = UInt32(digits, radix: 16) else { return nil }
        if digits.count <= 4 {
            let alpha = digits.count == 4 ? Double(value & 15) / 15 : 1
            let rgb = digits.count == 4 ? value >> 4 : value
            return RGBA(red: Double((rgb >> 8) & 15) / 15,
                        green: Double((rgb >> 4) & 15) / 15,
                        blue: Double(rgb & 15) / 15, alpha: alpha)
        }
        return rgba(digits.count == 8 ? value >> 8 : value,
                    alpha: digits.count == 8 ? Double(value & 255) / 255 : 1)
    }

    private static func rgba(_ rgb: UInt32, alpha: Double) -> RGBA {
        RGBA(red: Double((rgb >> 16) & 255) / 255,
             green: Double((rgb >> 8) & 255) / 255,
             blue: Double(rgb & 255) / 255, alpha: alpha)
    }

    private static func arguments(_ body: String) -> (channels: [String], alpha: String?, commas: Bool)? {
        if body.contains(",") {
            guard !body.contains("/") else { return nil }
            let values = body.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard (values.count == 3 || values.count == 4), !values.contains("") else { return nil }
            return (Array(values.prefix(3)), values.count == 4 ? values[3] : nil, true)
        }
        let pieces = body.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 1 || pieces.count == 2 else { return nil }
        let channels = pieces[0].split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard channels.count == 3 else { return nil }
        let alpha = pieces.count == 2 ? pieces[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        guard alpha != "" else { return nil }
        return (channels, alpha, false)
    }

    private static func number(_ source: String) -> Double? {
        guard source.range(of: #"^[+-]?(?:[0-9]*\.)?[0-9]+(?:e[+-]?[0-9]+)?$"#,
                           options: .regularExpression) != nil,
              let number = Double(source), number.isFinite else { return nil }
        return number
    }

    private static func channel(_ source: String, scale: Double) -> Double? {
        let percentage = source.hasSuffix("%")
        guard let value = number(percentage ? String(source.dropLast()) : source) else { return nil }
        return min(1, max(0, value / (percentage ? 100 : scale)))
    }

    private static func hue(_ source: String) -> Double? {
        for (suffix, turn) in [("turn", 1.0), ("grad", 400.0), ("deg", 360.0), ("rad", 2 * Double.pi)] {
            if source.hasSuffix(suffix) {
                guard let value = number(String(source.dropLast(suffix.count))) else { return nil }
                let normalized = (value / turn).truncatingRemainder(dividingBy: 1)
                return normalized < 0 ? normalized + 1 : normalized
            }
        }
        guard let value = number(source) else { return nil }
        let normalized = (value / 360).truncatingRemainder(dividingBy: 1)
        return normalized < 0 ? normalized + 1 : normalized
    }

    // CSS Color's complete 148 named sRGB colors, including the gray/grey
    // aliases and rebeccapurple. Values are fixed by the CSS standard.
    static let namedColors: [String: UInt32] = [
        "aliceblue": 0xf0f8ff, "antiquewhite": 0xfaebd7, "aqua": 0x00ffff,
        "aquamarine": 0x7fffd4, "azure": 0xf0ffff, "beige": 0xf5f5dc,
        "bisque": 0xffe4c4, "black": 0x000000, "blanchedalmond": 0xffebcd,
        "blue": 0x0000ff, "blueviolet": 0x8a2be2, "brown": 0xa52a2a,
        "burlywood": 0xdeb887, "cadetblue": 0x5f9ea0, "chartreuse": 0x7fff00,
        "chocolate": 0xd2691e, "coral": 0xff7f50, "cornflowerblue": 0x6495ed,
        "cornsilk": 0xfff8dc, "crimson": 0xdc143c, "cyan": 0x00ffff,
        "darkblue": 0x00008b, "darkcyan": 0x008b8b, "darkgoldenrod": 0xb8860b,
        "darkgray": 0xa9a9a9, "darkgreen": 0x006400, "darkgrey": 0xa9a9a9,
        "darkkhaki": 0xbdb76b, "darkmagenta": 0x8b008b, "darkolivegreen": 0x556b2f,
        "darkorange": 0xff8c00, "darkorchid": 0x9932cc, "darkred": 0x8b0000,
        "darksalmon": 0xe9967a, "darkseagreen": 0x8fbc8f, "darkslateblue": 0x483d8b,
        "darkslategray": 0x2f4f4f, "darkslategrey": 0x2f4f4f, "darkturquoise": 0x00ced1,
        "darkviolet": 0x9400d3, "deeppink": 0xff1493, "deepskyblue": 0x00bfff,
        "dimgray": 0x696969, "dimgrey": 0x696969, "dodgerblue": 0x1e90ff,
        "firebrick": 0xb22222, "floralwhite": 0xfffaf0, "forestgreen": 0x228b22,
        "fuchsia": 0xff00ff, "gainsboro": 0xdcdcdc, "ghostwhite": 0xf8f8ff,
        "gold": 0xffd700, "goldenrod": 0xdaa520, "gray": 0x808080,
        "green": 0x008000, "greenyellow": 0xadff2f, "grey": 0x808080,
        "honeydew": 0xf0fff0, "hotpink": 0xff69b4, "indianred": 0xcd5c5c,
        "indigo": 0x4b0082, "ivory": 0xfffff0, "khaki": 0xf0e68c,
        "lavender": 0xe6e6fa, "lavenderblush": 0xfff0f5, "lawngreen": 0x7cfc00,
        "lemonchiffon": 0xfffacd, "lightblue": 0xadd8e6, "lightcoral": 0xf08080,
        "lightcyan": 0xe0ffff, "lightgoldenrodyellow": 0xfafad2, "lightgray": 0xd3d3d3,
        "lightgreen": 0x90ee90, "lightgrey": 0xd3d3d3, "lightpink": 0xffb6c1,
        "lightsalmon": 0xffa07a, "lightseagreen": 0x20b2aa, "lightskyblue": 0x87cefa,
        "lightslategray": 0x778899, "lightslategrey": 0x778899, "lightsteelblue": 0xb0c4de,
        "lightyellow": 0xffffe0, "lime": 0x00ff00, "limegreen": 0x32cd32,
        "linen": 0xfaf0e6, "magenta": 0xff00ff, "maroon": 0x800000,
        "mediumaquamarine": 0x66cdaa, "mediumblue": 0x0000cd, "mediumorchid": 0xba55d3,
        "mediumpurple": 0x9370db, "mediumseagreen": 0x3cb371, "mediumslateblue": 0x7b68ee,
        "mediumspringgreen": 0x00fa9a, "mediumturquoise": 0x48d1cc, "mediumvioletred": 0xc71585,
        "midnightblue": 0x191970, "mintcream": 0xf5fffa, "mistyrose": 0xffe4e1,
        "moccasin": 0xffe4b5, "navajowhite": 0xffdead, "navy": 0x000080,
        "oldlace": 0xfdf5e6, "olive": 0x808000, "olivedrab": 0x6b8e23,
        "orange": 0xffa500, "orangered": 0xff4500, "orchid": 0xda70d6,
        "palegoldenrod": 0xeee8aa, "palegreen": 0x98fb98, "paleturquoise": 0xafeeee,
        "palevioletred": 0xdb7093, "papayawhip": 0xffefd5, "peachpuff": 0xffdab9,
        "peru": 0xcd853f, "pink": 0xffc0cb, "plum": 0xdda0dd,
        "powderblue": 0xb0e0e6, "purple": 0x800080, "rebeccapurple": 0x663399,
        "red": 0xff0000, "rosybrown": 0xbc8f8f, "royalblue": 0x4169e1,
        "saddlebrown": 0x8b4513, "salmon": 0xfa8072, "sandybrown": 0xf4a460,
        "seagreen": 0x2e8b57, "seashell": 0xfff5ee, "sienna": 0xa0522d,
        "silver": 0xc0c0c0, "skyblue": 0x87ceeb, "slateblue": 0x6a5acd,
        "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xfffafa,
        "springgreen": 0x00ff7f, "steelblue": 0x4682b4, "tan": 0xd2b48c,
        "teal": 0x008080, "thistle": 0xd8bfd8, "tomato": 0xff6347,
        "turquoise": 0x40e0d0, "violet": 0xee82ee, "wheat": 0xf5deb3,
        "white": 0xffffff, "whitesmoke": 0xf5f5f5, "yellow": 0xffff00,
        "yellowgreen": 0x9acd32
    ]
}
