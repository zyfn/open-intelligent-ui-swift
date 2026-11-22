import SwiftUI
import SwiftOpenUI

struct GalleryDesignSystemView: View {
    let system: GalleryDesignSystem
    @Binding var theme: GalleryDesignSystem.Theme
    @Binding var appearance: String
    @Binding var appliesToOpenUI: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var pageInset: CGFloat { sizeClass == .compact ? 16 : 26 }

    var body: some View {
        let tokens = system.tokens(for: theme)
        let values = tokens.openUITheme(theme, scheme: scheme).resolved()
        VStack(spacing: 0) {
            settings
                .padding(.horizontal, pageInset).padding(.vertical, 14)
                .frame(maxWidth: 1020, alignment: .leading)
                .frame(maxWidth: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 12) {
                        heading("颜色")
                        GalleryDesignColors(theme: values)
                    }
                    typography(values)
                    spacing(tokens, theme: values)
                    radii(values)
                    shadows(values)
                    charts(values)
                    Text("OpenUI 组件主题 · Muse \(system.revision.prefix(8))")
                        .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .frame(maxWidth: 968, alignment: .leading)
                .padding(.horizontal, pageInset).padding(.vertical, 22)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var settings: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                themePicker.frame(width: 232)
                appearancePicker.frame(width: 160)
                Spacer(minLength: 0)
                previewToggle.fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                themePicker.frame(maxWidth: 310)
                appearancePicker.frame(maxWidth: 310)
                previewToggle
            }
        }
    }

    private var themePicker: some View {
        Picker("OpenUI 主题", selection: $theme) {
            ForEach(GalleryDesignSystem.Theme.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel("OpenUI 主题")
    }

    private var appearancePicker: some View {
        Picker("外观", selection: $appearance) {
            ForEach(["系统", "浅色", "深色"], id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel("外观")
    }

    private var previewToggle: some View {
        Toggle("用于 OpenUI 预览", isOn: $appliesToOpenUI)
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    private func typography(_ values: OpenUIThemeValues) -> some View {
        let samples = [
            ("一级标题", values.textHeadingMd), ("二级标题", values.textHeadingSm),
            ("三级标题", values.textHeadingXs), ("大正文", values.textBodyLg), ("大正文 · 强调", values.textBodyLgHeavy),
            ("正文", values.textBodyDefault), ("正文 · 强调", values.textBodyDefaultHeavy),
            ("小正文", values.textBodySm), ("小正文 · 强调", values.textBodySmHeavy),
            ("辅助小字", values.textBodyXs), ("小标签", values.textLabelSm),
            ("小标签 · 强调", values.textLabelSmHeavy), ("标签 · 强调", values.textLabelDefaultHeavy),
            ("数字", values.textNumbersDefaultHeavy), ("代码", values.textCodeDefault)
        ] + [
            ("Markdown 强调", values.markdownEmphasisFont),
            ("表格表头", values.tableAppearance?.headerFont),
            ("表格正文", values.tableAppearance?.bodyFont)
        ].compactMap { label, font in font.map { (label, $0) } }
        return VStack(alignment: .leading, spacing: 12) {
            heading("文字")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 14)], alignment: .leading, spacing: 16) {
                ForEach(samples, id: \.0) { label, font in
                    VStack(alignment: .leading, spacing: 5) {
                        let specimen = label == "数字" ? "09:30 · 128" : label == "代码" ? "let count = 2" : label
                        Text(specimen).font(font.nativeFont())
                            .tracking(font.letterSpacing * font.size)
                        if specimen != label { Text(label).font(.caption2).foregroundStyle(.secondary) }
                        Text("\(font.size.formatted()) pt · \(fontWeight(font.weight))").font(.caption.monospacedDigit())
                        if let height = font.lineHeight {
                            Text("行高 \(height.formatted()) em").font(.caption2).foregroundStyle(.secondary)
                        } else if let spacing = font.lineSpacing {
                            Text("附加行距 \(spacing.formatted()) em").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func fontWeight(_ weight: Font.Weight) -> String {
        if weight == .semibold { return "半粗" }
        if weight == .medium { return "中等" }
        return "常规"
    }

    private func spacing(_ tokens: GalleryThemeTokens, theme: OpenUIThemeValues) -> some View {
        let scale = GalleryThemeTokens.spacingFields.compactMap { name, _ in
            tokens.spacing[name].map { (name, $0) }
        }
        return VStack(alignment: .leading, spacing: 12) {
            heading("间距")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], alignment: .leading, spacing: 14) {
                ForEach(scale, id: \.0) { name, size in
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle().fill(theme.textNeutralSecondary).frame(width: size, height: 5)
                            .accessibilityHidden(true)
                        Text(name == "markdownListItemGap" ? "Markdown 列表" : name).font(.caption)
                        Text("\(size.formatted()) pt").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func radii(_ values: OpenUIThemeValues) -> some View {
        let scale = [
            ("none", values.radiusNone), ("3xs", values.radius3xs), ("2xs", values.radius2xs),
            ("xs", values.radiusXs), ("s", values.radiusS), ("m", values.radiusM), ("l", values.radiusL),
            ("xl", values.radiusXl), ("2xl", values.radius2xl), ("3xl", values.radius3xl),
            ("4xl", values.radius4xl), ("5xl", values.radius5xl), ("6xl", values.radius6xl),
            ("7xl", values.radius7xl), ("8xl", values.radius8xl), ("9xl", values.radius9xl), ("full", values.radiusFull),
            ("Card", values.radius3xl), ("Table", values.tableAppearance?.cornerRadius ?? values.radius3xl)
        ]
        return VStack(alignment: .leading, spacing: 12) {
            heading("圆角")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 12)], alignment: .leading, spacing: 14) {
                ForEach(scale, id: \.0) { name, radius in
                    VStack(alignment: .leading, spacing: 5) {
                        let tile = RoundedRectangle(cornerRadius: radius)
                        tile.fill(Color.secondary.opacity(0.07))
                            .overlay(tile.strokeBorder(.secondary.opacity(0.32)))
                            .frame(width: 74, height: 48)
                            .accessibilityHidden(true)
                        Text(name).font(.caption.monospaced())
                        Text(name == "full" ? "全圆" : "\(radius.formatted()) pt")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func shadows(_ values: OpenUIThemeValues) -> some View {
        let scale = [("shadow0", values.shadow0), ("shadowS", values.shadowS),
                     ("shadowM", values.shadowM), ("shadowL", values.shadowL)]
        return VStack(alignment: .leading, spacing: 12) {
            heading("阴影")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach(scale, id: \.0) { label, shadow in
                    let layers = shadow.resolvedLayers(for: scheme).filter { $0.opacity > 0 }
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(values.foreground)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.secondary.opacity(0.18)))
                            .openUIShadow(shadow, cornerRadius: 8)
                            .frame(width: 74, height: 40)
                        Text(label).font(.caption.monospaced())
                        Text(layers.isEmpty ? "无阴影" : layers.map {
                            "\($0.opacity.formatted(.percent)) · \($0.blurRadius.formatted()) pt"
                        }.joined(separator: "\n"))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func charts(_ values: OpenUIThemeValues) -> some View {
        let types: [(String, String?)] = [
            ("默认", nil), ("柱状图", "BarChart"), ("横向柱状图", "HorizontalBarChart"),
            ("折线图", "LineChart"), ("面积图", "AreaChart"), ("饼图", "PieChart"),
            ("雷达图", "RadarChart"), ("径向图", "RadialChart")
        ]
        return VStack(alignment: .leading, spacing: 12) {
            heading("图表配色")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 171), spacing: 14)], alignment: .leading, spacing: 12) {
                ForEach(types, id: \.0) { label, type in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label).font(.caption)
                        let colors = values.chartColors(forSeriesCount: 6, chartType: type)
                        HStack(spacing: 2) {
                            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                                color.frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    private func heading(_ label: String) -> some View {
        Text(label).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
    }
}
