import SwiftUI
import SwiftLang

enum JourneyLineComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(
            name: "JourneyLine",
            description: "A horizontal transport connector between two endpoint groups. Draws a dashed line, endpoint markers and a mode icon. Keep times, places, duration, transfers, prices and actions in ordinary sibling components.",
            params: [OpenUIParameter.string("mode", values: ["flight", "train", "bus", "taxi"])]
        ) { JourneyLineView(context: $0) }
    }

    static func symbol(for mode: String?) -> String? {
        switch mode {
        case "flight": return "airplane"
        case "train": return "tram.fill"
        case "bus": return "bus.fill"
        case "taxi": return "car.fill"
        default: return nil
        }
    }
}

private struct JourneyLineView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme

    var body: some View {
        HStack(spacing: theme.innerSpacing) {
            Circle().strokeBorder(theme.secondaryText.opacity(0.75), lineWidth: 1.5).frame(width: 9, height: 9)
            dash
            Group {
                if let symbol = JourneyLineComponent.symbol(for: context.presentationString("mode")) {
                    Image(systemName: symbol).font(theme.labelFont).foregroundStyle(theme.primaryText)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
            }
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
            dash
            Circle().strokeBorder(theme.secondaryText.opacity(0.75), lineWidth: 1.5).frame(width: 9, height: 9)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .accessibilityLabel("交通行程")
    }

    private var dash: some View {
        GeometryReader { geometry in
            Path { path in
                let y = geometry.size.height / 2
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: geometry.size.width, y: y))
            }
            .stroke(theme.separator, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .frame(height: 1.5)
    }
}
