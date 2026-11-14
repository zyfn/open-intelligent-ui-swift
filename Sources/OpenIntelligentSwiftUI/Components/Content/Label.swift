import SwiftUI
import OpenSwiftUI

enum LabelComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Label", description: "Plain field or group label.", params: [OpenUIParameter.string("text")]) {
            LabelView(context: $0)
        }
    }
}

private struct LabelView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        Text(context.string("text") ?? "").font(theme.labelFont)
            .foregroundStyle(theme.primaryText).fixedSize(horizontal: false, vertical: true)
    }
}
