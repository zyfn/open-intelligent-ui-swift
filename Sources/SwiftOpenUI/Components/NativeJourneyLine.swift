import SwiftLang
import SwiftUI

enum OpenUIJourneyComponents {
    static var journeyLine: OpenUIComponent {
        OpenUIComponent(
            name: "JourneyLine",
            description: "Dashed line with a transport icon showing the direction between two stops in a Card.",
            params: [OpenUIParameter.string("mode", values: ["flight", "train", "bus", "taxi"])]
        ) { context in
            NativeComponentHost(context: context) { NativeJourneyLine(context: $0) }
        }
    }
}

struct NativeJourneyLine: View {
    let context: OpenUIComponentContext

    /// Do not infer a transport mode while the model is still producing it.
    static func symbol(for context: OpenUIComponentContext) -> String? {
        switch context.presentationString("mode") {
        case "flight": return "airplane"
        case "train": return "tram.fill"
        case "bus": return "bus.fill"
        case "taxi": return "car.fill"
        default: return nil
        }
    }

    var body: some View {
        let symbol = Self.symbol(for: context)
        HStack(spacing: context.theme.spaceS) {
            Circle().strokeBorder(context.theme.textNeutralSecondary, lineWidth: 1.5)
                .frame(width: 9, height: 9)
            NativeJourneyDash(color: context.theme.textNeutralTertiary)
                .frame(height: 1)
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(context.theme.textNeutralPrimary)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
            }.accessibilityHidden(true)
            NativeJourneyDash(color: context.theme.textNeutralTertiary)
                .frame(height: 1)
            Circle().strokeBorder(context.theme.textNeutralSecondary, lineWidth: 1.5)
                .frame(width: 9, height: 9)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .accessibilityLabel("交通行程")
    }
}

private struct NativeJourneyDash: View {
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
    }
}
