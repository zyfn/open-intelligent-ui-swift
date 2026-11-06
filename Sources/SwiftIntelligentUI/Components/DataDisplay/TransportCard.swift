import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum TransportCardComponent {
    static var component: OpenUIComponent {
        let string = Parameter.stringSchema
        let mode: JSONValue = .object([.init(key: "type", value: .string("string")), .init(key: "enum", value: .array(TransportData.Mode.allCases.map { .string(OpenUIString($0.rawValue)) }))])
        let leg = Parameter.objectSchema([("mode", mode)] + ["id", "from", "to", "departureTime", "arrivalTime", "departureDate", "arrivalDate", "departureZone", "arrivalZone", "fromCode", "toCode", "fromTerminal", "toTerminal", "carrier", "serviceNumber", "durationText", "bookingURL"].map { ($0, string) } + [("arrivalDayOffset", Parameter.numberSchema)], required: ["mode", "from", "to"])
        let connection = Parameter.objectSchema([("afterLeg", Parameter.numberSchema), ("changeStation", Parameter.booleanSchema)] + ["location", "durationText", "notice"].map { ($0, string) }, required: ["afterLeg"])
        let journey = Parameter.objectSchema([("legs", Parameter.arraySchema(leg, minimum: 1, maximum: 12)), ("connections", Parameter.arraySchema(connection, maximum: 11)), ("separateTickets", Parameter.booleanSchema), ("price", PricePresentation.schema), ("priceText", PricePresentation.legacySchema)] + ["id", "durationText", "currency", "priceNote", "badge", "bookingURL", "actionLabel"].map { ($0, string) }, required: ["id", "legs"])
        return OpenUIComponent(name: "TransportCard", description: "One source journey/direction with ordered flight/train/bus/ferry legs from that journey's supplied segments. Separate source journeys, outbound/return or alternatives use separate cards, never a flattened legs array. Exact supplied local time/date/zone/terminal fields and connection facts are preserved. Without explicit connections the UI states segment count, not inferred transfers. Use canonical price (nonnegative number or currency/amount string), optional source currency and priceNote; priceText is legacy reader-only. Preserve quote ownership: a price on a parent result is not copied to each child journey or reinterpreted from a round URL. Keep a parent quote once in surrounding text when its scope is unspecified; never omit, sum or split it. A missing price input shows 价格待补充 instead of blank space when a price/action footer is present. Price and navigation action share a row with readable AX fallback. Connections, separate tickets and elapsed durations are supplied facts; calendar dates/arrivalDayOffset only label day changes. bookingURL is navigation, not an order; per-leg URLs support separate tickets.", params: [ParamDef(name: "journey", required: true, schema: journey)]) { context in
            if let journey = TransportData(context.value("journey")) { TransportCardView(context: context, journey: journey).id(journey.id) }
            else { Text("交通信息不完整或时间格式不正确").foregroundStyle(.secondary) }
        }
    }
}

private struct TransportCardView: View {
    let context: OpenUIComponentContext
    let journey: TransportData
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = false
    private var first: TransportData.Leg { journey.legs[0] }
    private var last: TransportData.Leg { journey.legs[journey.legs.count - 1] }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.controlHorizontalPadding) {
            HStack(alignment: .top, spacing: theme.innerSpacing) {
                Label(journey.modeLabel, systemImage: first.mode.symbol)
                if let date = first.departureDate { Text(date).monospacedDigit() }
                Spacer(minLength: 0)
                if let badge = journey.badge { Text(badge).fontWeight(.medium) }
            }.font(theme.captionFont).foregroundStyle(theme.secondaryText)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.innerSpacing) { endpoint(departure: true); routeSummary; endpoint(departure: false) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: theme.innerSpacing) {
                        endpoint(departure: true)
                        routeSummary.frame(maxWidth: .infinity).padding(.top, theme.innerSpacing)
                        endpoint(departure: false)
                    }.frame(minWidth: theme.transportSummaryMinimumWidth)
                    VStack(alignment: .leading, spacing: theme.innerSpacing) {
                        HStack(alignment: .top, spacing: theme.innerSpacing) {
                            endpoint(departure: true)
                            Spacer(minLength: theme.innerSpacing)
                            endpoint(departure: false)
                        }
                        routeSummary
                    }
                }
            }
            if !journey.summaryServices.isEmpty { Text(journey.summaryServices).font(theme.secondaryFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
            if journey.separateTickets { Label("分段出票", systemImage: "ticket").font(theme.captionFont).foregroundStyle(theme.secondaryText) }
            if journey.legs.count > 1 {
                DisclosureGroup("查看分段行程", isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: theme.groupSpacing) {
                        ForEach(Array(journey.legs.enumerated()), id: \.element.id) { index, leg in
                            legRow(leg)
                            if index < journey.legs.count - 1 { connection(after: index) }
                        }
                    }.padding(.top, theme.groupSpacing)
                }.font(theme.secondaryFont).tint(theme.actionAccent)
            }
            if journey.priceText != nil || journey.priceNote != nil || SourceURL.isActionable(journey.primaryBookingURL) {
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: theme.innerSpacing) { price; Spacer(minLength: theme.innerSpacing); booking }
                    VStack(alignment: .leading, spacing: theme.innerSpacing) { price; booking }
                }
            }
        }
        .padding(theme.groupSpacing).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.canvas, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.separator.opacity(0.35)))
    }
    private func endpoint(departure: Bool) -> some View {
        let leg = departure ? first : last
        return VStack(alignment: departure || typeSize.isAccessibilitySize ? .leading : .trailing, spacing: theme.spacingUnit) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacingUnit) {
                Text((departure ? leg.departureTime : leg.arrivalTime) ?? "—").font(theme.transportTimeFont).monospacedDigit().fixedSize()
                if !departure, let offset = TransportData.offsetText(journeyOffset) { Text(offset).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
            }
            Text([departure ? leg.from : leg.to, departure ? leg.fromTerminal : leg.toTerminal].compactMap { $0 }.joined(separator: " "))
                .font(theme.bodyFont).fixedSize(horizontal: false, vertical: true)
            if let code = departure ? leg.fromCode : leg.toCode { Text(code).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
            if let zone = departure ? leg.departureZone : leg.arrivalZone { Text(zone).font(theme.captionFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
        }.accessibilityElement(children: .combine)
    }
    private var journeyOffset: Int? {
        if first.id == last.id { return last.arrivalDayOffset }
        return TransportData.dayOffset(from: first.departureDate, to: last.arrivalDate)
    }
    private var routeSummary: some View {
        VStack(spacing: theme.spacingUnit) {
            if let duration = journey.displayDurationText { Text(duration).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
            HStack(spacing: theme.spacingUnit) { Rectangle().fill(theme.separator).frame(height: 1); Image(systemName: journey.legs.count > 1 ? "circle.grid.2x1" : "arrow.right").font(theme.captionFont).foregroundStyle(theme.secondaryText) }.frame(minWidth: 44)
            Text(journey.routeLabel).font(theme.captionFont).foregroundStyle(theme.secondaryText)
        }
    }
    private var price: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit) {
            Text(journey.price.text ?? PricePresentation.missingLabel)
                .font(journey.price.text == nil ? theme.secondaryFont : theme.priceFont)
                .foregroundStyle(journey.price.text == nil ? theme.secondaryText : theme.primaryText)
                .monospacedDigit().fixedSize(horizontal: journey.price.canonical, vertical: true)
            if let note = journey.priceNote { Text(note).font(theme.captionFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
        }
    }
    @ViewBuilder private var booking: some View {
        if let url = journey.primaryBookingURL, SourceURL.isActionable(url) {
            PrimaryLinkButton(context: context, label: journey.actionLabel ?? "查看票价", url: url)
        }
    }
    private func legRow(_ leg: TransportData.Leg) -> some View {
        VStack(alignment: .leading, spacing: theme.innerSpacing) {
            Label([leg.mode.label, leg.serviceText].filter { !$0.isEmpty }.joined(separator: " · "), systemImage: leg.mode.symbol).font(theme.labelFont)
            let from = [leg.from, leg.fromCode, leg.fromTerminal].compactMap { $0 }.joined(separator: " ")
            let to = [leg.to, leg.toCode, leg.toTerminal].compactMap { $0 }.joined(separator: " ")
            Text("\(leg.departureTime ?? "—") \(from) → \(leg.arrivalTime ?? "—") \(to)\(TransportData.offsetText(leg.arrivalDayOffset).map { " " + $0 } ?? "")").font(theme.bodyFont).fixedSize(horizontal: false, vertical: true)
            let facts = leg.temporalText
            if !facts.isEmpty { Text(facts).font(theme.captionFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
            if let url = leg.bookingURL, SourceURL.isActionable(url) {
                OpenUIActionSurface(context: context, action: OpenUIActions.openURL(url), useNativeStyle: true) { Text("查看该段").font(theme.captionFont) }.buttonStyle(.borderless).tint(theme.actionAccent)
            }
        }.accessibilityElement(children: .contain)
    }
    @ViewBuilder private func connection(after index: Int) -> some View {
        if let info = journey.connections.first(where: { $0.afterLeg == index }) {
            let location = info.location ?? (journey.legs[index].to == journey.legs[index + 1].from ? journey.legs[index].to : journey.legs[index].to + " → " + journey.legs[index + 1].from)
            VStack(alignment: .leading, spacing: theme.spacingUnit) {
                Label([info.changeStation ? "换站中转" : "中转", location, info.durationText].compactMap { $0 }.joined(separator: " · "), systemImage: info.changeStation ? "exclamationmark.triangle" : "arrow.triangle.swap")
                if let notice = info.notice { Text(notice) }
            }.font(theme.captionFont).foregroundStyle(info.changeStation ? theme.warning : theme.secondaryText).fixedSize(horizontal: false, vertical: true).padding(.leading, theme.groupSpacing)
        }
    }
}
