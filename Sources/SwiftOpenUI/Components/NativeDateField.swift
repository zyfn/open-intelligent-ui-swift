import SwiftLang
import SwiftUI

/// Same JSON boundary as the reference's Date / DateRange values.
enum NativeCalendarDate {
    static func parse(_ value: Value?, timeZone: TimeZone = .current) -> Date? {
        guard case .string(let raw) = value, let text = raw.wellFormedString else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        if text.count == 10, let date = formatter.date(from: text), formatter.string(from: date) == text {
            return date
        }
        let timestamp = ISO8601DateFormatter()
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return timestamp.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    static func encode(_ date: Date) -> Value {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return .string(formatter.string(from: date))
    }
    static func setting(_ date: Date, part: NativeDatePart, in value: Value,
                        calendar: Calendar, timeZone: TimeZone) -> Value {
        var calendar = calendar
        calendar.timeZone = timeZone
        let selected = calendar.startOfDay(for: date)
        guard let key = part.key else { return encode(selected) }
        var values: [ObjectField] = []
        if case .object(let object) = value { values = Array(object).filter { $0.key != key } }
        values.append(ObjectField(key: key, value: encode(selected)))
        let from = values.first { $0.key == "from" }.flatMap { parse($0.value, timeZone: timeZone) }
        let to = values.first { $0.key == "to" }.flatMap { parse($0.value, timeZone: timeZone) }
        if let from, let to, from > to {
            let other = key == "from" ? "to" : "from"
            values.removeAll { $0.key == other }
            values.append(ObjectField(key: other, value: encode(selected)))
        }
        return .object(values)
    }
    static func hasRangeSelection(_ value: Value, timeZone: TimeZone) -> Bool {
        guard case .object(let object) = value else { return false }
        return parse(object["from"], timeZone: timeZone) != nil || parse(object["to"], timeZone: timeZone) != nil
    }
    static func rangeSummary(_ value: Value, locale: Locale, calendar: Calendar, timeZone: TimeZone) -> String? {
        guard case .object(let object) = value,
              let from = parse(object["from"], timeZone: timeZone),
              let to = parse(object["to"], timeZone: timeZone) else { return nil }
        let format = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone)
        return from.formatted(format) + " – " + to.formatted(format)
    }
}

enum NativeDatePart: String {
    case single, from, to
    var key: String? { self == .single ? nil : rawValue }
}
struct NativeDateRequest: Identifiable {
    let id = UUID()
    let part: NativeDatePart
    let label: String
    let date: Date
    let context: OpenUIComponentContext
}

struct NativeDateField: View {
    let context: OpenUIComponentContext
    let label: String
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.isEnabled) private var enabled
    @Environment(\.openUIFieldPresentation) private var fieldPresentation
    @State private var request: NativeDateRequest?
    private var field: NativeFieldState { .init(context: context) }
    private var range: Bool { context.string("mode") == "range" }
    private var canEdit: Bool { enabled && context.canInteract }
    private func date(_ part: NativeDatePart) -> Date? {
        if let key = part.key, case .object(let object) = field.value {
            return NativeCalendarDate.parse(object[key], timeZone: timeZone)
        }
        return NativeCalendarDate.parse(field.value, timeZone: timeZone)
    }
    private func write(_ selected: Date, part: NativeDatePart, context: OpenUIComponentContext) {
        let field = NativeFieldState(context: context)
        guard context.canInteract else { return }
        field.write(NativeCalendarDate.setting(selected, part: part, in: field.value, calendar: calendar, timeZone: timeZone))
    }
    var body: some View {
        presentation
            .onChange(of: canEdit) { active in if !active { request = nil } }
            .onChange(of: context.presentationSourceRevision) { _ in request = nil }
    }
    @ViewBuilder private var presentation: some View {
        #if os(macOS)
            content.popover(item: $request) { value in editor(value).frame(width: 360, height: 480) }
        #else
            content.sheet(item: $request) { value in editor(value).modifier(NativeCalendarPresentation()) }
        #endif
    }
    @ViewBuilder private var content: some View {
        if range {
            VStack(alignment: .leading, spacing: context.theme.spacing("s")) {
                dateControl(NativeControlText.localized("Start date", locale: locale), part: .from)
                dateControl(NativeControlText.localized("End date", locale: locale), part: .to)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Selected range", bundle: NativeControlResources.bundle))
            .accessibilityValue(NativeCalendarDate.rangeSummary(
                field.value, locale: locale, calendar: calendar, timeZone: timeZone) ?? "")
            .accessibilityIdentifier("openui.date.range.\(field.name.displayString)")
        } else {
            dateControl(label, part: .single)
        }
    }
    private func dateControl(_ title: String, part: NativeDatePart) -> some View {
        VStack(alignment: .leading, spacing: context.theme.spacing("xs")) {
            if range { Text(title).nativeTextStyle(context.theme.textStyle(.supporting)) }
            Button {
                request = NativeDateRequest(
                    part: part, label: title, date: date(part) ?? Date(), context: context)
            } label: {
                HStack(spacing: 8) {
                    if fieldPresentation == .inline { Spacer(minLength: 0) }
                    if let date = date(part) {
                        Text(
                            date.formatted(
                                Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone)))
                    } else {
                        Text("Select date", bundle: NativeControlResources.bundle)
                            .foregroundStyle(canEdit ? context.theme.textNeutralSecondary : context.theme.textNeutralTertiary)
                    }
                    if fieldPresentation != .inline { Spacer(minLength: 8) }
                    Image(systemName: "calendar").openUIFont(context.theme.textBodySm, role: .detail)
                        .foregroundStyle(canEdit ? context.theme.textNeutralSecondary : context.theme.textNeutralTertiary)
                        .accessibilityHidden(true)
                }.frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading).modifier(
                    NativeFieldSurface(theme: context.theme))
            }.buttonStyle(NativeQuietButtonStyle(theme: context.theme, cornerRadius: context.theme.radiusL))
                .disabled(!canEdit).accessibilityLabel(accessibleTitle(title, part: part))
                .accessibilityIdentifier("openui.date.\(field.name.displayString).\(part.key ?? "value")")
        }
    }
    private func accessibleTitle(_ title: String, part: NativeDatePart) -> String {
        let title = part == .single ? title : label + ", " + title
        return field.isRequired ? title + ", " + NativeControlText.localized("Required", locale: locale) : title
    }
    private var minimumHeight: CGFloat {
        #if os(iOS)
            44
        #else
            28
        #endif
    }
    private func editor(_ value: NativeDateRequest) -> some View {
        NativeCalendarEditor(
            request: value, theme: context.theme, cancel: { request = nil },
            clear: !(range ? NativeCalendarDate.hasRangeSelection(field.value, timeZone: timeZone) : date(value.part) != nil)
                ? nil
                : {
                    guard canEdit else { return }
                    NativeFieldState(context: value.context).write(.null)
                    request = nil
                },
            commit: { selected in
                guard canEdit else { return }
                write(selected, part: value.part, context: value.context)
                request = nil
            })
    }
}

private struct NativeCalendarPresentation: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 500
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
            content.presentationDetents([.height(height), .large]).presentationDragIndicator(.visible)
        #else
            content
        #endif
    }
}

struct NativeCalendarEditor: View {
    let request: NativeDateRequest
    let theme: OpenUIThemeValues
    let cancel: () -> Void
    let clear: (() -> Void)?
    let commit: (Date) -> Void
    @State private var selection: Date
    init(
        request: NativeDateRequest, theme: OpenUIThemeValues, cancel: @escaping () -> Void,
        clear: (() -> Void)? = nil, commit: @escaping (Date) -> Void
    ) {
        self.request = request
        self.theme = theme
        self.cancel = cancel
        self.clear = clear
        self.commit = commit
        _selection = State(initialValue: request.date)
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: theme.spaceS) {
                Text(request.label).openUIFont(theme.textBodyDefaultHeavy, role: .title)
                    .foregroundStyle(theme.textNeutralPrimary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
                HStack(spacing: theme.spaceS) {
                    Button(action: cancel) { Text("Cancel", bundle: NativeControlResources.bundle) }
                        .buttonStyle(NativeActionButtonStyle(theme: theme, variant: "tertiary", size: "small"))
                        .keyboardShortcut(.cancelAction).accessibilityIdentifier("openui.date.cancel")
                    Spacer(minLength: 0)
                    Button { commit(selection) } label: {
                        Text("Done", bundle: NativeControlResources.bundle)
                    }
                    .buttonStyle(NativeActionButtonStyle(theme: theme, size: "small"))
                    .keyboardShortcut(.defaultAction).accessibilityIdentifier("openui.date.done")
                }
            }.padding(.horizontal, theme.spaceM).padding(.top, theme.spaceML).padding(.bottom, theme.spaceS)
            Divider()
            ScrollView {
                DatePicker(request.label, selection: $selection, displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden().tint(theme.interactiveAccentDefault).padding(16)
                if let clear {
                    Button(action: clear) {
                        if request.part == .single { Text("Clear", bundle: NativeControlResources.bundle) }
                        else { Text("Clear range", bundle: NativeControlResources.bundle) }
                    }
                        .buttonStyle(
                            NativeActionButtonStyle(theme: theme, variant: "tertiary", size: "small")
                        )
                        .accessibilityIdentifier("openui.date.clear")
                        .padding(.bottom, 12)
                }
            }
        }.openUIFont(theme.textBodyDefault).foregroundStyle(theme.textNeutralPrimary).background(theme.foreground)
    }
}
