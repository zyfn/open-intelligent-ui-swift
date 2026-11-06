import SwiftUI

/// Host-supplied validation feedback; does not guess business validation rules.
struct FieldError: View {
    let message: String?
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        if let message, !message.isEmpty {
            Label(message, systemImage: "exclamationmark.circle")
                .font(theme.captionFont).foregroundStyle(theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
