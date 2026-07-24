import Foundation

/// The operational flow the traveller is following. This is deliberately
/// explicit: an itinerary alone cannot prove whether bags are through-checked
/// or whether a passenger is on one ticket.
enum TransferFlow: String, Codable, CaseIterable, Identifiable, Sendable {
    case standardConnection
    case selfTransfer
    case airportChange

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standardConnection: "Standard connection"
        case .selfTransfer: "Self-transfer"
        case .airportChange: "Airport change"
        }
    }
}

struct TransferStep: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let documents: String?

    static let selfTransfer: [TransferStep] = [
        .init(id: "immigration", title: "Immigration", detail: "Clear arrival controls before leaving the secure area.", documents: "Passport and entry permission"),
        .init(id: "baggage", title: "Collect baggage", detail: "Collect checked bags and keep bag tags with you.", documents: "Bag tag"),
        .init(id: "customs", title: "Customs", detail: "Complete customs requirements before entering landside.", documents: "Customs declaration if required"),
        .init(id: "checkin", title: "Check in again", detail: "Confirm the new booking and bag drop cutoff.", documents: "New boarding pass and baggage allowance"),
        .init(id: "security", title: "Security", detail: "Allow time for the security queue and screening.", documents: "Boarding pass and ID"),
        .init(id: "gate", title: "Go to gate", detail: "Use route guidance only after the operational steps are complete.", documents: nil)
    ]

    static let airportChange: [TransferStep] = [
        .init(id: "immigration", title: "Immigration", detail: "Clear arrival controls before exiting the first airport.", documents: "Passport and entry permission"),
        .init(id: "baggage", title: "Collect baggage", detail: "Collect checked bags before the airport change.", documents: "Bag tag"),
        .init(id: "customs", title: "Customs", detail: "Complete customs requirements at the arrival airport.", documents: "Customs declaration if required"),
        .init(id: "transfer", title: "Travel to the next airport", detail: "Follow the selected rail, coach, or road transfer and recheck live service details.", documents: "Transfer ticket or payment method"),
        .init(id: "checkin", title: "Check in at the next airport", detail: "Complete check-in and bag drop for the onward flight.", documents: "Onward booking and baggage allowance"),
        .init(id: "security", title: "Security and gate", detail: "Clear screening, then use route guidance to reach the gate.", documents: "Boarding pass and ID")
    ]
}

struct DecisionReadyPlan: Equatable, Sendable {
    let totalMinutes: Int?
    let walkMinutes: Int?
    let queueMinutes: Int?
    let backtrackingMinutes: Int?
    let accessMessage: String
    let quietCallScore: Int?

    init(candidate: PlanCandidate) {
        func duration(for kinds: Set<PlanSegmentKind>) -> Int? {
            let values = candidate.segments.compactMap { segment -> Double? in
                guard kinds.contains(segment.kind) else { return nil }
                return segment.duration?.value.mostLikely
            }
            return values.isEmpty ? nil : Int(values.reduce(0, +).rounded())
        }
        let values = candidate.segments.compactMap { $0.duration?.value.mostLikely }
        totalMinutes = values.isEmpty ? nil : Int(values.reduce(0, +).rounded())
        walkMinutes = duration(for: [.access, .outboundTravel, .returnTravel, .terminalRoute])
        queueMinutes = duration(for: [.border, .baggage, .customs, .reentry, .security, .checkIn])
        backtrackingMinutes = duration(for: [.returnTravel, .terminalRoute])
        accessMessage = candidate.place?.accessZone == .airside
            ? "AIRSIDE · no security return expected"
            : "LANDSIDE · re-entry and security are included"
        switch candidate.place?.category {
        case .workPod: quietCallScore = 9
        case .lounge, .transitHotel, .dayRoom: quietCallScore = 8
        case .food: quietCallScore = 4
        default: quietCallScore = nil
        }
    }
}

struct GateStatusSnapshot: Equatable, Sendable {
    let gate: String?
    let previousGate: String?
    let walkMinutes: Int?
    let boardingTime: Date?
    let leaveBy: Date?

    var hasGateChange: Bool {
        guard let gate, let previousGate else { return false }
        return gate != previousGate
    }
}
