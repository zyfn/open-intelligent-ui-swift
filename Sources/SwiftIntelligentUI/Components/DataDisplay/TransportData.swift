import Foundation
import OpenUILang

struct TransportData {
    enum Mode: String, CaseIterable {
        case flight, train, bus, ferry, other
        var symbol: String {
            switch self { case .flight: return "airplane"; case .train: return "tram.fill"; case .bus: return "bus.fill"; case .ferry: return "ferry.fill"; case .other: return "arrow.right" }
        }
        var label: String {
            switch self { case .flight: return "航班"; case .train: return "列车"; case .bus: return "巴士"; case .ferry: return "轮渡"; case .other: return "交通" }
        }
    }
    struct Leg: Identifiable {
        let id: String
        let mode: Mode
        let from: String
        let to: String
        let fromCity: String?
        let toCity: String?
        let departureTime: String?
        let arrivalTime: String?
        let departureDate: String?
        let arrivalDate: String?
        let departureZone: String?
        let arrivalZone: String?
        let fromCode: String?
        let toCode: String?
        let fromTerminal: String?
        let toTerminal: String?
        let carrier: String?
        let serviceNumber: String?
        let durationText: String?
        let bookingURL: String?
        let arrivalDayOffset: Int?
        var serviceText: String { [carrier, serviceNumber].compactMap { $0 }.joined(separator: " · ") }
        var temporalText: String {
            let dates = departureDate == arrivalDate ? [departureDate].compactMap { $0 }.joined() : [departureDate, arrivalDate].compactMap { $0 }.joined(separator: " → ")
            let zones = departureZone == arrivalZone ? [departureZone].compactMap { $0 }.joined() : [departureZone, arrivalZone].compactMap { $0 }.joined(separator: " → ")
            return [dates, zones, durationText ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }
    struct Connection {
        let afterLeg: Int
        let location: String?
        let durationText: String?
        let notice: String?
        let changeStation: Bool
    }
    let id: String
    let legs: [Leg]
    let connections: [Connection]
    let durationText: String?
    let price: PricePresentation
    var priceText: String? { price.canonical ? price.text : price.legacyText }
    let priceNote: String?
    let badge: String?
    let bookingURL: String?
    let separateTickets: Bool

    init?(_ value: Value?) {
        guard let id = Self.text(value, "id"), case .array(let values) = ValueReading.field(value, "legs"), !values.isEmpty, values.count <= 12 else { return nil }
        var legs: [Leg] = [], ids = Set<String>()
        for (index, leg) in values.enumerated() {
            guard let mode = Self.text(leg, "mode").flatMap(Mode.init(rawValue:)), let from = Self.text(leg, "from"), let to = Self.text(leg, "to") else { return nil }
            let legID = Self.text(leg, "id") ?? String(index)
            guard ids.insert(legID).inserted else { return nil }
            let departureTime = Self.text(leg, "departureTime"), arrivalTime = Self.text(leg, "arrivalTime")
            let departureDate = Self.text(leg, "departureDate"), arrivalDate = Self.text(leg, "arrivalDate")
            guard [departureTime, arrivalTime].compactMap({ $0 }).allSatisfy(Self.validTime),
                  [departureDate, arrivalDate].compactMap({ $0 }).allSatisfy({ CalendarDate.parse($0) != nil }) else { return nil }
            let explicit = ValueReading.number(ValueReading.field(leg, "arrivalDayOffset"))
            if let explicit, explicit != explicit.rounded() || abs(explicit) > 366 { return nil }
            let calendarOffset = Self.dayOffset(from: departureDate, to: arrivalDate)
            if let explicit, let calendarOffset, Int(explicit) != calendarOffset { return nil }
            legs.append(Leg(id: legID, mode: mode, from: from, to: to, fromCity: Self.text(leg, "fromCity"), toCity: Self.text(leg, "toCity"), departureTime: departureTime, arrivalTime: arrivalTime,
                            departureDate: departureDate, arrivalDate: arrivalDate, departureZone: Self.text(leg, "departureZone"), arrivalZone: Self.text(leg, "arrivalZone"),
                            fromCode: Self.text(leg, "fromCode"), toCode: Self.text(leg, "toCode"), fromTerminal: Self.text(leg, "fromTerminal"), toTerminal: Self.text(leg, "toTerminal"),
                            carrier: Self.text(leg, "carrier"), serviceNumber: Self.text(leg, "serviceNumber"), durationText: Self.text(leg, "durationText"), bookingURL: Self.text(leg, "bookingURL"), arrivalDayOffset: explicit.map(Int.init) ?? calendarOffset))
        }
        var connections: [Connection] = [], positions = Set<Int>()
        for connection in ValueReading.array(ValueReading.field(value, "connections")) {
            guard let index = ValueReading.number(ValueReading.field(connection, "afterLeg")), index == index.rounded(), index >= 0, index < Double(legs.count - 1), positions.insert(Int(index)).inserted else { return nil }
            connections.append(Connection(afterLeg: Int(index), location: Self.text(connection, "location"), durationText: Self.text(connection, "durationText"), notice: Self.text(connection, "notice"), changeStation: ValueReading.field(connection, "changeStation") == .boolean(true)))
        }
        self.id = id; self.legs = legs; self.connections = connections
        durationText = Self.text(value, "durationText"); price = PricePresentation(value); priceNote = Self.text(value, "priceNote")
        badge = Self.text(value, "badge"); bookingURL = Self.text(value, "bookingURL")
        separateTickets = ValueReading.field(value, "separateTickets") == .boolean(true)
    }
    var hasCompleteConnections: Bool { legs.count > 1 && connections.count == legs.count - 1 }
    var routeLabel: String { legs.count == 1 ? "直达" : hasCompleteConnections ? "\(connections.count)次中转" : "\(legs.count)段行程" }
    var modeLabel: String { Set(legs.map(\.mode)).count == 1 ? legs[0].mode.label : hasCompleteConnections ? "联程" : "交通" }
    var primaryBookingURL: String? { bookingURL ?? (legs.count == 1 ? legs[0].bookingURL : nil) }
    var displayDurationText: String? { durationText ?? (legs.count == 1 ? legs[0].durationText : nil) }
    var summaryServices: String {
        var seen = Set<String>()
        let carriers = legs.compactMap(\.carrier).filter { seen.insert($0).inserted }.joined(separator: " / ")
        let services = legs.compactMap(\.serviceNumber).joined(separator: " · ")
        return [carriers, services].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    static func validTime(_ value: String) -> Bool { value.range(of: #"^(?:[01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil }
    static func dayOffset(from: String?, to: String?) -> Int? {
        guard let from = CalendarDate.parse(from), let to = CalendarDate.parse(to) else { return nil }
        return Int((to.timeIntervalSince(from) / 86400).rounded())
    }
    static func offsetText(_ offset: Int?) -> String? {
        guard let offset, offset != 0 else { return nil }
        return offset > 0 ? "+\(offset)天" : "\(offset)天"
    }
    private static func text(_ value: Value?, _ key: String) -> String? {
        guard case .string(let text) = ValueReading.field(value, key), !text.displayString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text.displayString
    }
}
