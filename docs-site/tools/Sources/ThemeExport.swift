import Foundation
import AppKit
import SwiftUI
import SwiftOpenUI
import SwiftIntelligentUI

/// A documentation-only snapshot of the two actual native theme values.
enum ThemeExport {
    @MainActor static func write(to directory: URL) throws {
        try export(OpenUIThemeValues(), to: directory.appendingPathComponent("theme-openui.json"))
        try export(OpenIntelligentUITheme(), to: directory.appendingPathComponent("theme-intelligent-ui.json"))
    }

    @MainActor private static func export<T>(_ theme: T, to output: URL) throws {
        var colors: [String: [String: String]] = [:]
        var metrics: [String: Double] = [:]
        var fonts: [String: [String: Any]] = [:]
        for entry in Mirror(reflecting: theme).children {
            guard let key = entry.label else { continue }
            if let value = entry.value as? Color {
                if let light = hex(value, dark: false), let dark = hex(value, dark: true) {
                    colors[key] = ["light": light, "dark": dark]
                }
            }
            if let value = entry.value as? CGFloat, value.isFinite {
                metrics[key] = Double(value)
            }
            if let value = entry.value as? OpenUIFont {
                let weight: Int = value.weight == .bold ? 700 :
                    value.weight == .semibold ? 600 :
                    value.weight == .medium ? 500 : 400
                fonts[key] = [
                    "size": Double(value.size),
                    "weight": weight,
                    "family": value.family ?? "system",
                    "lineHeight": value.lineHeight.map { Double($0) } as Any? ?? NSNull()
                ]
            }
        }
        let data = try JSONSerialization.data(
            withJSONObject: ["colors": colors, "metrics": metrics, "fonts": fonts],
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: output)
    }

    @MainActor private static func hex(_ color: Color, dark: Bool) -> String? {
        guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { return nil }
        var result: String?
        appearance.performAsCurrentDrawingAppearance {
            let base = NSColor(color)
            guard let resolved = base.usingColorSpace(.sRGB) else { return }
            let red = Int((min(1, max(0, resolved.redComponent)) * 255).rounded())
            let green = Int((min(1, max(0, resolved.greenComponent)) * 255).rounded())
            let blue = Int((min(1, max(0, resolved.blueComponent)) * 255).rounded())
            result = String(format: "#%02X%02X%02X", red, green, blue)
            if resolved.alphaComponent < 0.999 {
                result! += String(format: "%02X", Int((min(1, max(0, resolved.alphaComponent)) * 255).rounded()))
            }
        }
        return result
    }
}
