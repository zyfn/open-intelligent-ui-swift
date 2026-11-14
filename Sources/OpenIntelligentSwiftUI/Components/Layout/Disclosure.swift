import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum DisclosureComponent {
    static var component: OpenUIComponent {
        var expanded = Parameter.boundBoolean("expanded"); expanded.required = false
        return OpenUIComponent(name: "Disclosure", description: "Native expandable details. title labels the group; children contain supporting content. Optional expanded binds a boolean, otherwise expansion stays local. No nested navigation or invented workflow.", params: [OpenUIParameter.string("title"), OpenUIParameter.slot("children", required: true), expanded]) { DisclosureView(context: $0) }
    }
}
private struct DisclosureView: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    @State private var local: Bool?
    private var expanded: Binding<Bool> {
        Binding(get: {
            if let binding = context.binding("expanded") { return binding.wrappedValue == .boolean(true) }
            return local ?? context.flag("expanded") ?? false
        }, set: { value in
            guard context.canInteract else { return }
            if let binding = context.binding("expanded") { binding.wrappedValue = .boolean(value) } else { local = value }
        })
    }
    var body: some View {
        DisclosureGroup(isExpanded: expanded) {
            VStack(alignment: .leading, spacing: theme.innerSpacing) { context.slot() }.padding(.top, theme.innerSpacing)
        } label: {
            Text(context.string("title") ?? SDKStrings.text("disclosure.details", locale: locale)).font(theme.labelFont).foregroundStyle(theme.primaryText).fixedSize(horizontal: false, vertical: true)
        }.tint(theme.actionAccent).disabled(!context.canInteract)
    }
}
