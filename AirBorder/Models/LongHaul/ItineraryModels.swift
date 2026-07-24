import Foundation

struct ItineraryLeg: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var flight: Flight
    var onBlockTime: SourcedMetric<Date>?
    var gateCloseTime: SourcedMetric<Date>?
    /// Applies to the connection into this departing leg. An absent value
    /// preserves the historical standard-connection assumption for saved trips.
    var transferFlow: TransferFlow?

    init(
        id: UUID = UUID(),
        flight: Flight,
        onBlockTime: SourcedMetric<Date>? = nil,
        gateCloseTime: SourcedMetric<Date>? = nil,
        transferFlow: TransferFlow? = nil
    ) {
        self.id = id
        self.flight = flight
        self.onBlockTime = onBlockTime
        self.gateCloseTime = gateCloseTime
        self.transferFlow = transferFlow
    }

    var effectiveOnBlock: Date? {
        onBlockTime?.value ?? flight.effectiveArrival
    }

    var effectiveGateClose: Date? {
        gateCloseTime?.value
    }
}

struct LayoverContext: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let inboundLegID: UUID
    let onwardLegID: UUID
    let airport: Airport
    let onwardAirport: Airport
    let inboundOnBlock: Date?
    let onwardGateClose: Date?
    let onwardDeparture: Date?
    let timeZoneIdentifier: String
    let transferFlow: TransferFlow

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .gmt
    }

    var availableWindowMinutes: Double? {
        guard let inboundOnBlock, let onwardGateClose else { return nil }
        return onwardGateClose.timeIntervalSince(inboundOnBlock) / 60
    }

    var isInterAirportTransfer: Bool {
        airport.iata.uppercased() != onwardAirport.iata.uppercased()
    }

    var airportChangeAssessment: AirportChangeAssessment {
        MetroAirportDatabase.classify(from: airport.iata, to: onwardAirport.iata)
    }

    func contains(_ date: Date) -> Bool {
        guard let start = inboundOnBlock,
              let end = onwardDeparture ?? onwardGateClose else { return false }
        return start <= date && date <= end
    }
}

struct Itinerary: Identifiable, Codable, Hashable, Sendable {
    static let currentSchemaVersion = 3

    let id: UUID
    var schemaVersion: Int
    var inputRevision: Int
    var title: String
    var legs: [ItineraryLeg]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        schemaVersion: Int = Itinerary.currentSchemaVersion,
        inputRevision: Int = 1,
        title: String,
        legs: [ItineraryLeg],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.inputRevision = inputRevision
        self.title = title
        self.legs = legs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var layovers: [LayoverContext] {
        guard legs.count > 1 else { return [] }
        return zip(legs, legs.dropFirst()).map { inbound, onward in
            let airport = inbound.flight.destination
            return LayoverContext(
                id: "\(inbound.id.uuidString)-\(onward.id.uuidString)",
                inboundLegID: inbound.id,
                onwardLegID: onward.id,
                airport: airport,
                onwardAirport: onward.flight.origin,
                inboundOnBlock: inbound.effectiveOnBlock,
                onwardGateClose: onward.effectiveGateClose,
                onwardDeparture: onward.flight.effectiveDeparture,
                timeZoneIdentifier: airport.timeZone ?? "GMT",
                transferFlow: onward.transferFlow ?? (airport.iata.uppercased() == onward.flight.origin.iata.uppercased() ? .standardConnection : .airportChange)
            )
        }
    }

    func activeLayover(at date: Date) -> LayoverContext? {
        layovers.first(where: { $0.contains(date) }) ?? layovers.first
    }

    mutating func append(_ leg: ItineraryLeg, at date: Date = Date()) {
        legs.append(leg)
        markChanged(at: date)
    }

    mutating func removeLeg(id: UUID, at date: Date = Date()) {
        legs.removeAll { $0.id == id }
        markChanged(at: date)
    }

    mutating func moveLeg(from offsets: IndexSet, to destination: Int, at date: Date = Date()) {
        let moving = offsets.sorted().map { legs[$0] }
        for index in offsets.sorted(by: >) { legs.remove(at: index) }
        let removedBeforeDestination = offsets.filter { $0 < destination }.count
        let insertion = max(0, min(legs.count, destination - removedBeforeDestination))
        legs.insert(contentsOf: moving, at: insertion)
        markChanged(at: date)
    }

    mutating func replaceLeg(_ leg: ItineraryLeg, at date: Date = Date()) {
        guard let index = legs.firstIndex(where: { $0.id == leg.id }) else { return }
        legs[index] = leg
        markChanged(at: date)
    }

    private mutating func markChanged(at date: Date) {
        inputRevision += 1
        updatedAt = date
    }
}

extension Itinerary {
    static func migrated(from journey: ActiveJourney) -> Itinerary {
        Itinerary(
            id: journey.id,
            inputRevision: 1,
            title: journey.flight.routeLabel,
            legs: [ItineraryLeg(flight: journey.flight)],
            createdAt: journey.linkedAt,
            updatedAt: journey.lastSuccessfulRefresh
        )
    }
}
