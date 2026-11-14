import SwiftUI
import OpenUILang
import OpenUICore

private enum TransportCardMetrics {
    static let routeWidth: CGFloat = 88
    static let actionSlotWidth: CGFloat = 112
    static let priceSlotHeight: CGFloat = 52
    static let timeFont: Font = .title3.weight(.semibold)
}

enum TransportCardComponent {
    static var component: OpenUIComponent {
        let string = Parameter.stringSchema
        let mode: JSONValue = .object([.init(key: "type", value: .string("string")), .init(key: "enum", value: .array(TransportData.Mode.allCases.map { .string(OpenUIString($0.rawValue)) }))])
        let leg = Parameter.objectSchema([("mode", mode)] + ["id", "from", "to", "fromCity", "toCity", "departureTime", "arrivalTime", "departureDate", "arrivalDate", "departureZone", "arrivalZone", "fromCode", "toCode", "fromTerminal", "toTerminal", "carrier", "serviceNumber", "durationText", "bookingURL"].map { ($0, string) } + [("arrivalDayOffset", Parameter.numberSchema)], required: ["mode", "from", "to"])
        let connection = Parameter.objectSchema([("afterLeg", Parameter.numberSchema), ("changeStation", Parameter.booleanSchema)] + ["location", "durationText", "notice"].map { ($0, string) }, required: ["afterLeg"])
        let journey = Parameter.objectSchema([("legs", Parameter.arraySchema(leg, minimum: 1, maximum: 12)), ("connections", Parameter.arraySchema(connection, maximum: 11)), ("separateTickets", Parameter.booleanSchema), ("price", PricePresentation.schema), ("priceText", PricePresentation.legacySchema)] + ["id", "durationText", "currency", "priceNote", "badge", "bookingURL"].map { ($0, string) }, required: ["id", "legs"])
        return OpenUIComponent(name: "TransportCard", description: "One source journey/direction with ordered flight/train/bus/ferry legs from that journey's supplied segments. Separate source journeys, outbound/return or alternatives use separate cards, never a flattened legs array. Exact supplied local time/date/zone/terminal fields and connection facts are preserved. fromCity/toCity are source city names for the header; from/to are the full airport or station names below times. Never derive cities by stripping airport names; missing city fields omit that header segment. Without explicit connections the UI states segment count, not inferred transfers. Use canonical price (nonnegative number or currency/amount string), optional source currency and priceNote; priceText is legacy reader-only. Preserve quote ownership: a price on a parent result is not copied to each child journey or reinterpreted from a round URL. Independent records never share a composed option card or ordinary sibling quote/action. If a parent quote has unclear scope, leave price empty and preserve its amount and uncertainty once in the first related journey's priceNote; never omit, sum, split or duplicate it. Every card reserves a leading price slot and trailing navigation slot, including unavailable values. Missing price, duration and carrier details leave blank slots without changing the three-column skeleton; unavailable navigation leaves an empty slot. Price notes wrap inside the price slot; navigation uses a fixed 查看 capsule action. Connections, separate tickets and elapsed durations are supplied facts; calendar dates/arrivalDayOffset only label day changes. bookingURL is navigation, not an order; per-leg URLs support separate tickets.", params: [ParamDef(name: "journey", required: true, schema: journey)]) { context in
            if let journey = TransportData(context.value("journey")) { TransportCardView(context: context, journey: journey).id(journey.id) }
            else { TransportUnavailableView() }
        }
    }
}

private struct TransportCardView: View {
    let context: OpenUIComponentContext
    let journey: TransportData
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = false
    private var first: TransportData.Leg { journey.legs[0] }
    private var last: TransportData.Leg { journey.legs[journey.legs.count - 1] }
    private var headerText: String {
        var parts: [String] = []
        if let fromCity = first.fromCity, let toCity = last.toCity { parts.append(fromCity + " → " + toCity) }
        if let date = first.departureDate { parts.insert(date, at: 0) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.controlHorizontalPadding) {
            HStack(alignment: .top, spacing: theme.innerSpacing) {
                Label(headerText, systemImage: first.mode.symbol)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let badge = journey.badge {
                    Text(badge).fontWeight(.medium).padding(.horizontal, theme.innerSpacing).padding(.vertical, theme.spacingUnit)
                        .background(theme.surface, in: Capsule())
                }
            }.font(theme.captionFont).foregroundStyle(theme.secondaryText)
            if typeSize.isAccessibilitySize {
                stackedSummary
            } else {
                ViewThatFits(in: .horizontal) {
                    summary(timeFont: TransportCardMetrics.timeFont)
                    summary(timeFont: .headline.weight(.semibold))
                    summary(timeFont: .subheadline.weight(.semibold))
                    stackedSummary
                }
            }
            if journey.separateTickets { Label(SDKStrings.text("transport.separate_tickets", locale: locale), systemImage: "ticket").font(theme.captionFont).foregroundStyle(theme.secondaryText) }
            if journey.legs.count > 1 {
                DisclosureGroup(SDKStrings.text("transport.show_legs", locale: locale), isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: theme.groupSpacing) {
                        ForEach(Array(journey.legs.enumerated()), id: \.element.id) { index, leg in
                            legRow(leg)
                            if index < journey.legs.count - 1 { connection(after: index) }
                        }
                    }.padding(.top, theme.groupSpacing)
                }.font(theme.secondaryFont).tint(theme.actionAccent)
            }
            Text(journey.summaryServices.isEmpty ? " " : journey.summaryServices)
                .font(theme.secondaryFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(journey.summaryServices.isEmpty)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.innerSpacing) { price; bookingButton }
            } else {
                HStack(alignment: .top, spacing: theme.innerSpacing) {
                    price.frame(maxWidth: .infinity, minHeight: TransportCardMetrics.priceSlotHeight, alignment: .topLeading)
                    bookingSlot
                }
            }
        }
        .padding(theme.groupSpacing).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.canvas, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.fieldBorder))
    }
    private var stackedSummary: some View {
        VStack(alignment: .leading, spacing: theme.groupSpacing) {
            VStack(alignment: .leading, spacing: theme.spacingUnit) {
                Text(SDKStrings.text("transport.departure", locale: locale)).font(theme.captionFont).foregroundStyle(theme.secondaryText)
                timeText(departure: true, font: TransportCardMetrics.timeFont)
                placeText(departure: true, stacked: true)
            }
            Label([journey.displayDurationText, journey.localizedRouteLabel(locale: locale)].compactMap { $0 }.joined(separator: " · "), systemImage: "arrow.down")
                .font(theme.captionFont).foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: theme.spacingUnit) {
                Text(SDKStrings.text("transport.arrival", locale: locale)).font(theme.captionFont).foregroundStyle(theme.secondaryText)
                timeText(departure: false, font: TransportCardMetrics.timeFont)
                placeText(departure: false, stacked: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func summary(timeFont: Font) -> some View {
        HStack(alignment: .top, spacing: theme.innerSpacing) {
            endpoint(departure: true, timeFont: timeFont).frame(maxWidth: .infinity, alignment: .leading)
            routeSummary.frame(width: TransportCardMetrics.routeWidth)
            endpoint(departure: false, timeFont: timeFont).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    private func endpoint(departure: Bool, timeFont: Font) -> some View {
        VStack(alignment: departure ? .leading : .trailing, spacing: theme.spacingUnit) {
            timeText(departure: departure, font: timeFont)
            placeText(departure: departure)
        }
    }
    private func timeText(departure: Bool, font: Font) -> some View {
        let leg = departure ? first : last
        return HStack(alignment: .firstTextBaseline, spacing: theme.spacingUnit) {
            Text((departure ? leg.departureTime : leg.arrivalTime) ?? "—").font(font).monospacedDigit().fixedSize()
            if !departure, let offset = TransportData.offsetText(journeyOffset, locale: locale) { Text(offset).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
        }.accessibilityElement(children: .combine)
    }
    private func placeText(departure: Bool, stacked: Bool = false) -> some View {
        let leg = departure ? first : last
        return VStack(alignment: stacked || departure ? .leading : .trailing, spacing: theme.spacingUnit) {
            Text([departure ? leg.from : leg.to, departure ? leg.fromTerminal : leg.toTerminal].compactMap { $0 }.joined(separator: " "))
                .font(theme.secondaryFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            if let zone = departure ? leg.departureZone : leg.arrivalZone { Text(zone).font(theme.captionFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
        }.accessibilityElement(children: .combine)
    }
    private var journeyOffset: Int? {
        if first.id == last.id { return last.arrivalDayOffset }
        return TransportData.dayOffset(from: first.departureDate, to: last.arrivalDate)
    }
    private var routeSummary: some View {
        VStack(spacing: 2) {
            Text(journey.displayDurationText ?? " ").font(theme.captionFont).foregroundStyle(theme.secondaryText)
                .accessibilityHidden(journey.displayDurationText == nil)
            HStack(spacing: 0) {
                Circle().fill(theme.separator).frame(width: 3, height: 3)
                Rectangle().fill(theme.separator).frame(height: 1)
                Image(systemName: "arrow.right").font(theme.captionFont).foregroundStyle(theme.secondaryText)
            }
            Text(journey.localizedRouteLabel(locale: locale)).font(theme.captionFont).foregroundStyle(theme.secondaryText)
        }
    }
    private var price: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit) {
            Text(journey.price.displayText ?? " ")
                .font(journey.price.text == nil ? theme.secondaryFont : theme.priceFont)
                .foregroundStyle(journey.price.text == nil ? theme.secondaryText : theme.primaryText)
                .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(journey.price.accessibilityText(locale: locale) ?? "")
                .accessibilityHidden(journey.price.text == nil)
            if let note = journey.priceNote { Text(note).font(theme.captionFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
            ForEach(journey.price.diagnostics, id: \.self) { diagnostic in
                Label(diagnostic.message(locale: locale), systemImage: "exclamationmark.circle").font(theme.captionFont).foregroundStyle(theme.warning)
                    .fixedSize(horizontal: false, vertical: true).accessibilityHidden(journey.price.text != nil)
            }
        }
    }
    @ViewBuilder private var bookingButton: some View {
        if let url = journey.primaryBookingURL, SourceURL.isActionable(url) {
            PrimaryLinkButton(context: context, label: SDKStrings.text("transport.view", locale: locale), url: url)
        }
    }
    @ViewBuilder private var bookingSlot: some View {
        Group {
            if let url = journey.primaryBookingURL, SourceURL.isActionable(url) {
                PrimaryLinkButton(context: context, label: SDKStrings.text("transport.view", locale: locale), url: url)
            } else {
                Color.clear.accessibilityHidden(true)
            }
        }.frame(width: TransportCardMetrics.actionSlotWidth, alignment: .trailing).frame(minHeight: theme.minimumControlHeight, alignment: .top)
    }
    private func legRow(_ leg: TransportData.Leg) -> some View {
        VStack(alignment: .leading, spacing: theme.innerSpacing) {
            Label([leg.mode.localizedLabel(locale: locale), leg.serviceText].filter { !$0.isEmpty }.joined(separator: " · "), systemImage: leg.mode.symbol).font(theme.labelFont)
            let from = [leg.from, leg.fromCode, leg.fromTerminal].compactMap { $0 }.joined(separator: " ")
            let to = [leg.to, leg.toCode, leg.toTerminal].compactMap { $0 }.joined(separator: " ")
            Text("\(leg.departureTime ?? "—") \(from) → \(leg.arrivalTime ?? "—") \(to)\(TransportData.offsetText(leg.arrivalDayOffset, locale: locale).map { " " + $0 } ?? "")").font(theme.bodyFont).fixedSize(horizontal: false, vertical: true)
            let facts = leg.temporalText
            if !facts.isEmpty { Text(facts).font(theme.captionFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
            if let url = leg.bookingURL, SourceURL.isActionable(url) {
                IntelligentUIActionSurface(context: context, action: OpenUIActions.openURL(url), showsProgress: true) { Text(SDKStrings.text("transport.view_leg", locale: locale)).font(theme.compactActionFont) }
                    .buttonStyle(UpstreamButtonStyle(variant: "ghost", tint: theme.actionAccent, size: "sm")).tint(theme.actionAccent)
            }
        }.accessibilityElement(children: .contain)
    }
    @ViewBuilder private func connection(after index: Int) -> some View {
        if let info = journey.connections.first(where: { $0.afterLeg == index }) {
            let location = info.location ?? (journey.legs[index].to == journey.legs[index + 1].from ? journey.legs[index].to : journey.legs[index].to + " → " + journey.legs[index + 1].from)
            VStack(alignment: .leading, spacing: theme.spacingUnit) {
                Label([info.changeStation ? SDKStrings.text("transport.station_change", locale: locale) : SDKStrings.text("transport.transfer", locale: locale), location, info.durationText].compactMap { $0 }.joined(separator: " · "), systemImage: info.changeStation ? "exclamationmark.triangle" : "arrow.triangle.swap")
                if let notice = info.notice { Text(notice) }
            }.font(theme.captionFont).foregroundStyle(info.changeStation ? theme.warning : theme.secondaryText).fixedSize(horizontal: false, vertical: true).padding(.leading, theme.groupSpacing)
        }
    }
}

private struct TransportUnavailableView: View {
    @Environment(\.locale) private var locale
    var body: some View { Text(SDKStrings.text("transport.incomplete", locale: locale)).foregroundStyle(.secondary) }
}
