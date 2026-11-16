import SwiftUI
import SwiftLang

enum CalendarDate {
    static func parse(_ text: String?) -> Date? {
        guard let text, text.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil else { return nil }
        let formatter = formatter()
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }
    static func string(_ date: Date) -> String { formatter().string(from: date) }
    static func display(_ date: Date, locale: Locale) -> String {
        let value = DateFormatter()
        value.locale = locale
        value.calendar = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)
        value.dateStyle = .medium
        value.timeStyle = .none
        return value.string(from: date)
    }
    private static func formatter() -> DateFormatter {
        let value = DateFormatter(); value.calendar = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX"); value.timeZone = TimeZone(secondsFromGMT: 0)
        value.dateFormat = "yyyy-MM-dd"; value.isLenient = false
        return value
    }
}
enum DatePickerComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "DatePicker", description: "Native date input bound to YYYY-MM-DD, with optional inclusive min/max dates. Empty value remains unselected until edited. Calendar dates use Gregorian UTC to preserve their day.", params: [
            OpenUIParameter.selection("value"), OpenUIParameter.string("label", required: false),
            OpenUIParameter.string("min", required: false), OpenUIParameter.string("max", required: false)
        ]) { DateFieldView(context: $0) }
    }
}
struct CalendarDateSelection {
    let raw: String
    let date: Date?
    let lower: Date
    let upper: Date
    let validRange: Bool
    init(raw: String, minimum: String?, maximum: String?) {
        self.raw = raw
        date = CalendarDate.parse(raw)
        lower = CalendarDate.parse(minimum) ?? .distantPast
        upper = CalendarDate.parse(maximum) ?? .distantFuture
        validRange = lower <= upper && (minimum == nil || CalendarDate.parse(minimum) != nil)
            && (maximum == nil || CalendarDate.parse(maximum) != nil)
    }
    var validSelection: Bool { validRange && date.map { (lower...upper).contains($0) } == true }
    var message: String? {
        if !validRange { return "controls.date.invalid_range" }
        if raw.isEmpty { return nil }
        if date == nil { return "controls.date.invalid_format" }
        if !validSelection { return "controls.date.outside_range" }
        return nil
    }
    func proposal(now: Date = Date()) -> Date {
        guard validRange else { return now }
        let today = CalendarDate.parse(CalendarDate.string(now)) ?? now
        return min(upper, max(lower, date ?? today))
    }
}

private struct DateFieldView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.locale) private var locale
    @EnvironmentObject private var state: OpenUIState
    @State private var choosing = false
    @State private var proposedDate = Date()
    private var raw: String { InputEditing.text(context.binding("value")?.wrappedValue ?? context.value("value") ?? .null) }
    private var selection: CalendarDateSelection { .init(raw: raw, minimum: context.string("min"), maximum: context.string("max")) }
    private var canEdit: Bool { context.canInteract && context.binding("value") != nil }
    var body: some View {
        let selection = selection
        let dateLabel = selection.validSelection ? selection.date.map { CalendarDate.display($0, locale: locale) } : nil
        VStack(alignment: .leading, spacing: theme.innerSpacing) {
            if let label = context.string("label"), !label.isEmpty { Text(label).font(theme.labelFont) }
            Button {
                guard canEdit, selection.validRange else { return }
                proposedDate = selection.proposal()
                choosing = true
            } label: {
                HStack {
                    Text(dateLabel ?? (raw.isEmpty ? SDKStrings.text("controls.date.choose", locale: locale) : raw))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: theme.innerSpacing)
                    Image(systemName: "calendar").accessibilityHidden(true)
                }.font(theme.bodyFont)
                    .foregroundStyle(raw.isEmpty ? theme.secondaryText : theme.primaryText)
                    .modifier(FieldSurface(invalid: selection.message != nil))
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietControlStyle(cornerRadius: 10_000))
            .disabled(!canEdit || !selection.validRange)
            .accessibilityLabel(context.string("label") ?? SDKStrings.text("controls.date.label", locale: locale))
            .accessibilityValue(dateLabel ?? (raw.isEmpty ? SDKStrings.text("controls.date.unset", locale: locale) : raw))
            .accessibilityHint(selection.message.map { SDKStrings.text($0, locale: locale) } ?? SDKStrings.text("controls.date.confirm_hint", locale: locale))
            .popover(isPresented: $choosing) { proposalPanel }
            if let message = selection.message {
                Label(SDKStrings.text(message, locale: locale), systemImage: "exclamationmark.circle")
                    .font(theme.captionFont).foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .environment(\.calendar, Calendar(identifier: .gregorian))
    }
    @ViewBuilder private var proposalPanel: some View {
        let selection = selection
        if selection.validRange {
            VStack(alignment: .leading, spacing: theme.groupSpacing) {
                Text(context.string("label") ?? SDKStrings.text("controls.date.choose", locale: locale)).font(theme.titleFont)
                DatePicker(SDKStrings.text("controls.date.proposal", locale: locale), selection: $proposedDate, in: selection.lower...selection.upper, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                HStack {
                    Button(SDKStrings.text("controls.date.cancel", locale: locale)) { choosing = false }
                        .buttonStyle(UpstreamButtonStyle(variant: "ghost", tint: theme.actionAccent))
                    Spacer(minLength: theme.innerSpacing)
                    Button(SDKStrings.text("controls.date.apply", locale: locale)) { write(proposedDate); choosing = false }
                        .buttonStyle(UpstreamButtonStyle(tint: theme.actionAccent))
                        .foregroundStyle(theme.actionForeground)
                        .disabled(!canEdit || !(selection.lower...selection.upper).contains(proposedDate))
                }
            }.padding(theme.groupSpacing).frame(idealWidth: 320, maxWidth: 360)
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                .environment(\.calendar, Calendar(identifier: .gregorian))
        } else {
            VStack(spacing: theme.innerSpacing) {
                Text(SDKStrings.text("controls.date.range_changed", locale: locale))
                Button(SDKStrings.text("controls.date.close", locale: locale)) { choosing = false }
            }.padding(theme.groupSpacing)
        }
    }
    private func write(_ date: Date) {
        let selection = selection
        let text = CalendarDate.string(date)
        guard canEdit, selection.validRange, let day = CalendarDate.parse(text), (selection.lower...selection.upper).contains(day) else { return }
        context.binding("value")?.wrappedValue = .string(OpenUIString(text))
    }
}
