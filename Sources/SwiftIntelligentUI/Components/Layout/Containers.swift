import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum DividerComponent {
    static var component: OpenUIComponent { OpenUIComponent(name: "Divider", description: "Native content separator.", params: []) { _ in Divider() } }
}
enum SpacerComponent {
    static var component: OpenUIComponent { OpenUIComponent(name: "Spacer", description: "Fills remaining horizontal space in a nonwrapping Row.", params: []) { _ in Spacer(minLength: 0).layoutValue(key: RowFlexWeight.self, value: 1) } }
}
enum FormComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Form", description: "Groups fields and scopes actions. Optional status is idle/submitting/success/error and message is host-provided feedback. Submitting disables fields and actions; no success is inferred. Bind fields explicitly and supply field errors through their error parameter.", params: [
            OpenUIParameter.slot("children", required: true),
            OpenUIParameter.string("status", required: false, values: ["idle", "submitting", "success", "error"]),
            OpenUIParameter.string("message", required: false)
        ]) { FormGroup(context: $0) }
    }
}
private struct FormGroup: View {
    let context: OpenUIComponentContext
    @State private var identity = UUID().uuidString
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit * 6) {
            let children = context.children()
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                context.render(child.value).disabled(context.string("status") == "submitting")
                    .padding(.top, index > 0 && index == children.count - 1 && actionRow(child.value) ? theme.groupSpacing : 0)
            }
            if context.string("status") == "submitting" { ProgressView(context.string("message") ?? "正在提交").font(theme.secondaryFont) }
            else if let message = context.string("message"), !message.isEmpty {
                Label(message, systemImage: context.string("status") == "error" ? "exclamationmark.circle" : context.string("status") == "success" ? "checkmark.circle" : "info.circle")
                    .font(theme.secondaryFont)
                    .foregroundStyle(context.string("status") == "error" ? theme.danger : theme.primaryText)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }.openUIForm(context.element.statementId ?? identity)
    }
    private func actionRow(_ value: Value) -> Bool {
        EditorialNode.kind(value) == "Button" || (EditorialNode.kind(value) == "Row" && ValueReading.array(ValueReading.field(value, "children")).contains { EditorialNode.kind($0) == "Button" })
    }
}
enum PopoverComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Popover", description: "Native contextual popover with a plain presentation-only trigger and content-sized panel. iOS 16.4+ retains the popover on compact widths; earlier systems use platform adaptation.", params: [Parameter.textOrChildren("trigger"), Parameter.textOrChildren("content")]) { PopoverView(context: $0) }
    }
}
private struct PopoverView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: { rendered("trigger").environment(\.intelligentUIInteractiveContent, true) }.buttonStyle(.plain).tint(theme.actionAccent)
            .disabled(!context.canInteract)
            .popover(isPresented: $presented) {
                panel
            }
    }
    @ViewBuilder private var panel: some View {
        let content = ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: theme.innerSpacing) { rendered("content") }.padding(14)
            ScrollView { VStack(alignment: .leading, spacing: theme.innerSpacing) { rendered("content") }.padding(14) }
        }.frame(idealWidth: 280, maxWidth: 320, maxHeight: 480)
        if #available(iOS 16.4, macOS 13.3, *) { content.presentationCompactAdaptation(.popover) }
        else { content }
    }
    @ViewBuilder private func rendered(_ key: String) -> some View {
        if let text = context.string(key) { RichMarkdown(context: context, text: text, compact: true) } else { context.slot(key) }
    }
}

struct RowFlexWeight: LayoutValueKey { static let defaultValue: CGFloat = 0 }
