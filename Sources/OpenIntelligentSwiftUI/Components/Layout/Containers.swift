import SwiftUI
import OpenUILang
import OpenUICore

enum DividerComponent {
    static var component: OpenUIComponent { OpenUIComponent(name: "Divider", description: "Native content separator.", params: []) { _ in Divider().layoutValue(key: RowDivider.self, value: true) } }
}
enum SpacerComponent {
    static var component: OpenUIComponent { OpenUIComponent(name: "Spacer", description: "Fills remaining horizontal space in a nonwrapping Row.", params: []) { _ in Spacer(minLength: 0).layoutValue(key: RowFlexWeight.self, value: 1) } }
}
enum FormComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Form", description: "Groups explicitly bound fields in a native form context. Related action data must be explicit; feedback is composed with ordinary components. Layout wrappers do not change group spacing.", params: [
            OpenUIParameter.slot("children", required: true)
        ]) { context in
            FormGroup(context: context)
                .environment(\.openUIInteractionScopeReady, context.canInteract)
        }
    }
}
private struct FormGroup: View {
    let context: OpenUIComponentContext
    @State private var identity = UUID().uuidString
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: theme.groupSpacing) {
            ForEach(context.children()) { child in
                context.render(child.value)
            }
        }.openUIForm(context.element.statementId ?? identity)
    }
}
enum PopoverComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Popover", description: "Native contextual popover with a plain presentation-only trigger and content-sized panel. iOS 16.4+ retains the popover on compact widths; earlier systems use platform adaptation.", params: [Parameter.textOrChildren("trigger"), Parameter.textOrChildren("content")]) { PopoverView(context: $0) }
    }
}
private struct PopoverView: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            rendered("trigger").intelligentUIPresentationOnly().contentShape(Rectangle())
        }.buttonStyle(.plain).tint(theme.actionAccent).contentShape(Rectangle())
            .accessibilityLabel(PresentationText.summary(context.value("trigger"), locale: locale).isEmpty ? SDKStrings.text("popover.open", locale: locale) : PresentationText.summary(context.value("trigger"), locale: locale))
            .disabled(!context.canInteract)
            .popover(isPresented: $presented) {
                panel
            }
    }
    @ViewBuilder private var panel: some View {
        let content = VStack(alignment: .leading, spacing: theme.innerSpacing) {
            HStack {
                Spacer()
                Button(SDKStrings.text("common.done", locale: locale)) { presented = false }.accessibilityLabel(SDKStrings.text("popover.close", locale: locale))
                    .frame(minHeight: theme.minimumControlHeight)
            }
            BoundedContentScroll(maximumHeight: 420) {
                VStack(alignment: .leading, spacing: theme.innerSpacing) { rendered("content") }
            }
        }.padding(theme.groupSpacing).frame(idealWidth: 280, maxWidth: 320, maxHeight: 480)
        if #available(iOS 16.4, macOS 13.3, *) { content.presentationCompactAdaptation(.popover) }
        else { content }
    }
    @ViewBuilder private func rendered(_ key: String) -> some View {
        if let text = context.string(key) { RichMarkdown(context: context, text: text, compact: true) } else { context.slot(key) }
    }
}

struct RowFlexWeight: LayoutValueKey { static let defaultValue: CGFloat = 0 }
struct RowDivider: LayoutValueKey { static let defaultValue = false }
