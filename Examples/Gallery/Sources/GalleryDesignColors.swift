import SwiftUI
import SwiftOpenUI

struct GalleryDesignColors: View {
    let theme: OpenUIThemeValues
    @Environment(\.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            colors("表面与描边", [
                ("画布", theme.background), ("内容表面", theme.foreground), ("下沉表面", theme.sunk),
                ("轻下沉", theme.sunkLight), ("图片占位", theme.imagePlaceholderBackground),
                ("浮层", theme.popoverBackground), ("高亮底色", theme.highlight),
                ("边框", theme.borderDefault), ("控件边框", theme.borderInteractive),
                ("强调描边", theme.borderAccent), ("危险描边", theme.borderDanger),
                ("反色背景", theme.invertedBackground)
            ])
            colors("文字", [
                ("主要文字", theme.textNeutralPrimary), ("辅助文字", theme.textNeutralSecondary),
                ("弱化文字", theme.textNeutralTertiary), ("链接", theme.textNeutralLink),
                ("主按钮文字", theme.textAccentPrimary), ("危险按钮文字", theme.textDangerInvertedPrimary)
            ])
            colors("状态", [
                ("提示文字", theme.textInfoPrimary), ("成功文字", theme.textSuccessPrimary),
                ("警示文字", theme.textAlertPrimary), ("危险文字", theme.textDangerPrimary),
                ("弱危险文字", theme.textDangerTertiary), ("提示背景", theme.infoBackground),
                ("成功背景", theme.successBackground), ("警示背景", theme.alertBackground),
                ("危险背景", theme.dangerBackground)
            ])
            colors("主按钮", [
                ("默认", theme.interactiveAccentDefault), ("悬停", theme.interactiveAccentHover),
                ("按下", theme.interactiveAccentPressed), ("禁用", theme.interactiveAccentDisabled)
            ])
            DisclosureGroup("危险按钮") {
                VStack(alignment: .leading, spacing: 16) {
                    colors("危险主按钮", [
                        ("默认", theme.interactiveDestructiveAccentDefault), ("悬停", theme.interactiveDestructiveAccentHover),
                        ("按下", theme.interactiveDestructiveAccentPressed), ("禁用", theme.interactiveDestructiveAccentDisabled)
                    ])
                    colors("危险次按钮", [
                        ("默认", theme.interactiveDestructiveDefault), ("悬停", theme.interactiveDestructiveHover),
                        ("按下", theme.interactiveDestructivePressed), ("禁用", theme.interactiveDestructiveDisabled)
                    ])
                }
                .padding(.top, 12)
            }
            .font(.subheadline.weight(.medium))
            if let table = theme.tableAppearance {
                colors("表格", [
                    ("表格底色", table.background), ("表头底色", table.headerBackground), ("表格线", table.gridLine)
                ])
            }
        }
    }

    private func colors(_ title: String, _ samples: [(String, Color?)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(samples, id: \.0) { name, color in
                    let shape = RoundedRectangle(cornerRadius: 7)
                    VStack(alignment: .leading, spacing: 4) {
                        shape.fill(color ?? Color.secondary.opacity(0.08))
                            .overlay(shape.strokeBorder(.secondary.opacity(0.25)))
                            .frame(height: 32)
                            .accessibilityHidden(true)
                        Text(name).font(.caption)
                        if let color, let value = colorLabel(color) {
                            Text(value).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        } else if color == nil {
                            Text("自动适配").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func colorLabel(_ color: Color) -> String? {
        guard #available(macOS 14.0, iOS 17.0, *) else { return nil }
        let value = color.resolve(in: environment)
        func byte(_ unit: Float) -> Int { Int((min(1, max(0, unit)) * 255).rounded()) }
        let hex = String(format: "#%02X%02X%02X", byte(value.red), byte(value.green), byte(value.blue))
        let opacity = Double(value.opacity).formatted(.percent.precision(.fractionLength(0...2)))
        return value.opacity >= 0.999 ? hex : hex + " · " + opacity
    }
}
