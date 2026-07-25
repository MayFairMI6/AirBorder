import Foundation

enum TicketScanBaggageSignal: Codable, Hashable, Sendable {
    case bagTagDestination(String)
    case collectAndRecheck
    case selfTransfer
    case automaticTransfer
    case noCheckedBag
    case unknown
}

struct TicketPDFScanResult: Codable, Hashable, Sendable {
    let fileName: String
    let textFingerprint: String
    let routeAirportCodes: [String]
    let flightNumbers: [String]
    let baggageSignals: [TicketScanBaggageSignal]
    let scannedAt: Date
    let sourceRecordID: String
}

enum TicketTransitStatus: String, Codable, Hashable, Sendable {
    case current
    case mayNeedAuthorization
    case conditional
    case addTravelerDetails
    case refreshNeeded
    case notEnoughInformation

    var title: String {
        switch self {
        case .current: "Transit documents look current"
        case .mayNeedAuthorization: "Transit authorization may be needed"
        case .conditional: "Transit documents have conditions"
        case .addTravelerDetails: "Add traveler details"
        case .refreshNeeded: "Refresh transit document check"
        case .notEnoughInformation: "We don't have enough information"
        }
    }

    var message: String {
        switch self {
        case .current:
            "Your saved traveler details and current itinerary match the latest available transit check."
        case .mayNeedAuthorization:
            "Review the entry details before planning an airport exit or airport transfer."
        case .conditional:
            "Some transit rules depend on your documents, route, timing, or airport area."
        case .addTravelerDetails:
            "Add nationality, residence, and document type to check transit requirements."
        case .refreshNeeded:
            "Rules can change. Refresh the check before relying on this itinerary."
        case .notEnoughInformation:
            "The itinerary needs current flight, traveler, and transit-rule information."
        }
    }
}

struct TicketConnectionStatus: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let inboundLegID: UUID
    let outboundLegID: UUID
    let connectionLabel: String
    let transferFlow: TransferFlow
    let baggageAssessment: ConnectionBaggageAssessment
    let requiredSegments: [ConnectionPlanningSegmentKind]
    let transitStatus: TicketTransitStatus
    let scannedAt: Date
    let sourceRecordID: String

    init(
        id: UUID,
        inboundLegID: UUID,
        outboundLegID: UUID,
        connectionLabel: String,
        transferFlow: TransferFlow,
        baggageAssessment: ConnectionBaggageAssessment,
        requiredSegments: [ConnectionPlanningSegmentKind],
        transitStatus: TicketTransitStatus,
        scannedAt: Date,
        sourceRecordID: String
    ) {
        self.id = id
        self.inboundLegID = inboundLegID
        self.outboundLegID = outboundLegID
        self.connectionLabel = connectionLabel
        self.transferFlow = transferFlow
        self.baggageAssessment = baggageAssessment
        self.requiredSegments = requiredSegments
        self.transitStatus = transitStatus
        self.scannedAt = scannedAt
        self.sourceRecordID = sourceRecordID
    }
}
