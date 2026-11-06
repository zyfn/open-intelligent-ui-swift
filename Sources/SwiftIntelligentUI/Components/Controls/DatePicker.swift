import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum CalendarDate {
    static func parse(_ text: String?) -> Date? {
        guard let text, text.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil else { return nil }
        let formatter = formatter()
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }
    static func string(_ date: Date) -> String { formatter().string(from: date) }
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
private struct DateFieldView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @EnvironmentObject private var state: OpenUIState
    private var raw: String { InputEditing.text(context.binding("value")?.wrappedValue ?? context.value("value") ?? .null) }
    var body: some View {
        let low = CalendarDate.parse(context.string("min")) ?? .distantPast
        let high = CalendarDate.parse(context.string("max")) ?? .distantFuture
        VStack(alignment: .leading, spacing: theme.innerSpacing) {
            if low <= high && (context.string("min") == nil || CalendarDate.parse(context.string("min")) != nil) && (context.string("max") == nil || CalendarDate.parse(context.string("max")) != nil) {
                DatePicker(context.string("label") ?? "日期", selection: Binding(
                    get: { min(high, max(low, CalendarDate.parse(raw) ?? Date())) },
                    set: { context.binding("value")?.wrappedValue = .string(OpenUIString(CalendarDate.string($0))) }
                ), in: low...high, displayedComponents: .date)
                .datePickerStyle(.compact)
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                .environment(\.calendar, Calendar(identifier: .gregorian))
                .disabled(!context.canInteract || context.binding("value") == nil)
                if CalendarDate.parse(raw) == nil { Text("尚未选择有效日期").font(theme.captionFont).foregroundStyle(theme.secondaryText) }
            } else { Text("日期范围无效").foregroundStyle(.secondary) }
        }
    }
}
