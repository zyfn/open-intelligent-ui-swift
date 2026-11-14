import SwiftUI

/// Shared field surface; the editor remains a native text input.
struct FieldSurface: ViewModifier {
    var focused = false
    var invalid = false
    var multiline = false
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, theme.fieldHorizontalPadding)
            .padding(.vertical, theme.fieldVerticalPadding)
            .frame(minHeight: theme.minimumControlHeight, alignment: .leading)
            .background(theme.canvas, in: RoundedRectangle(cornerRadius: multiline ? theme.fieldMultilineRadius : 10_000, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: multiline ? theme.fieldMultilineRadius : 10_000, style: .continuous)
                .strokeBorder(invalid ? theme.danger.opacity(0.7) : focused ? theme.actionAccent.opacity(0.6) : theme.fieldBorder, lineWidth: 1))
            .opacity(enabled ? 1 : 0.55)
    }
}
