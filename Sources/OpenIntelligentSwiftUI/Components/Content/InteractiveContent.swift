import SwiftUI
import OpenUILang
import OpenUICore

enum FlashcardComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Flashcard", description: "Tap the card to flip between front/back presentation content. Hint is optional; no separate action button. Supports reduced motion.", params: [Parameter.textOrChildren("front"), Parameter.textOrChildren("back"), OpenUIParameter.string("hint", required: false)]) { FlashcardView(context: $0) }
    }
}
private struct FlashcardView: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @State private var revealed = false
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let key = revealed ? "back" : "front"
        let summary = PresentationText.summary(context.value(key), locale: locale)
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { revealed.toggle() }
        } label: {
            // Only the visible face is mounted. Keep scrolling outside the
            // presentation-only subtree so a long answer remains reachable.
            BoundedContentScroll(maximumHeight: 420) {
                face(key).intelligentUIPresentationOnly()
            }
            .id(key)
            .frame(maxWidth: .infinity, minHeight: 168)
            .background(revealed ? theme.surface : theme.canvas, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.fieldBorder))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).contentShape(RoundedRectangle(cornerRadius: 14)).disabled(!context.canInteract)
            .accessibilityLabel(summary.isEmpty ? SDKStrings.text("flashcard.title", locale: locale) : summary)
            .accessibilityValue(SDKStrings.text(revealed ? "flashcard.back" : "flashcard.front", locale: locale)).accessibilityHint(SDKStrings.text("flashcard.flip", locale: locale))
    }
    private func face(_ key: String) -> some View {
        VStack(spacing: theme.innerSpacing) {
            if let text = context.string(key) { RichMarkdown(context: context, text: text, compact: true, isTitle: key == "front") }
            else { context.slot(key) }
            if key == "front" { Text(context.string("hint") ?? SDKStrings.text("flashcard.flip", locale: locale)).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
        }.multilineTextAlignment(.center).padding(20).environment(\.intelligentUIInteractiveContent, true)
    }
}
enum CelebrationComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Celebration", description: "A brief decorative confetti burst when when changes from false to true after streaming. Initially true does not trigger. Reduced motion suppresses the animation. No completion label or implied business success.", params: [OpenUIParameter.flag("when", required: true)]) { CelebrationView(context: $0) }
    }
}

private struct CelebrationView: View {
    let context: OpenUIComponentContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.intelligentUITheme) private var theme
    @State private var previous: Bool?
    @State private var started: Date?
    private var value: Bool { context.flag("when") == true }
    var body: some View {
        Color.clear.frame(height: 0).overlay(alignment: .top) {
            if let started, !reduceMotion {
                TimelineView(.animation) { timeline in
                    Canvas { canvas, size in
                        let elapsed = timeline.date.timeIntervalSince(started)
                        for index in 0..<50 {
                            let phase = max(0, (elapsed - Double(index % 10) * 0.04) / 1.6)
                            guard phase > 0, phase < 1 else { continue }
                            let progress = CGFloat(phase)
                            let x = size.width * (CGFloat((index * 37) % 100) / 100)
                                + CGFloat((index * 71) % 100 - 50) * progress
                            let y = size.height * progress
                            let colors = theme.chartColors.isEmpty ? [theme.primaryText] : theme.chartColors
                            canvas.fill(Path(roundedRect: .init(x: x, y: y, width: 6, height: 9), cornerRadius: 2), with: .color(colors[index % colors.count].opacity(1 - phase * 0.3)))
                        }
                    }
                }.frame(height: 320)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
            .onAppear { if context.canInteract { previous = value } }
            .onChange(of: value) { current in
                guard context.canInteract else { return }
                if previous == false && current && !reduceMotion { started = Date() }
                previous = current
            }
            .onChange(of: context.canInteract) { ready in if ready { previous = value } }
            .task(id: started) {
                guard started != nil else { return }
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                guard !Task.isCancelled else { return }; started = nil
            }
    }
}
