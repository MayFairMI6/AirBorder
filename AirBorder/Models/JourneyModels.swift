import Foundation

enum JourneyUrgency: String, Codable, CaseIterable, Sendable {
    case comfortable
    case leaveSoon
    case urgent
    case likelyInsufficientTime
    case boarding
    case gateChanged
    case dataStale

    var title: String {
        return switch self {
        case .comfortable: "Comfortable"
        case .leaveSoon: "Leave soon"
        case .urgent: "Urgent"
        case .likelyInsufficientTime: "Time may be insufficient"
        case .boarding: "Boarding"
        case .gateChanged: "Gate changed"
        case .dataStale: "Verify flight information"
        }
    }
}

enum ConnectionRisk: String, Codable, Sendable {
    case comfortable
    case tight
    case atRisk
    case insufficientData

    var title: String {
        return switch self {
        case .comfortable: "Connection comfortable"
        case .tight: "Connection is tight"
        case .atRisk: "Connection at risk"
        case .insufficientData: "Connection risk unknown"
        }
    }
}

enum LocalizationConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
    case unavailable
}

enum JourneyAlert: String, Codable, Hashable, Sendable {
    case gateChange
    case terminalChange
    case boarding
    case delay
    case cancellation
    case diversion
    case connectionRisk
    case staleData
    case weakLocalization
}

struct JourneyAssessment: Codable, Sendable {
    let urgency: JourneyUrgency
    let operationalStatus: FlightStatus
    let freshness: DataFreshness
    let localizationConfidence: LocalizationConfidence
    let alerts: Set<JourneyAlert>
    let message: String
    let leaveBy: Date?
}

struct ActiveJourney: Identifiable, Codable, Sendable {
    let id: UUID
    var flight: Flight
    var linkedAt: Date
    var lastSuccessfulRefresh: Date
    var freshness: DataFreshness
    var routeMode: RouteMode
    var currentNodeID: String
    var destinationNodeID: String
    var walkMinutes: Int
    var accessibleWalkMinutes: Int
    var distanceMeters: Double
    var securityMinutes: Int
    var immigrationMinutes: Int
    var locationConfidence: LocalizationConfidence

    static func demo(now: Date = Date()) -> ActiveJourney {
        let flight = DemoData.flight(now: now)
        return ActiveJourney(
            id: UUID(),
            flight: flight,
            linkedAt: now,
            lastSuccessfulRefresh: now,
            freshness: .demo,
            routeMode: .accessible,
            currentNodeID: "security-exit",
            destinationNodeID: "gate-c12",
            walkMinutes: 6,
            accessibleWalkMinutes: 9,
            distanceMeters: 320,
            securityMinutes: 4,
            immigrationMinutes: 0,
            locationConfidence: .high
        )
    }
}

enum DemoData {
    static func flight(now: Date = Date()) -> Flight {
        let boarding = now.addingTimeInterval(18 * 60)
        let departure = now.addingTimeInterval(48 * 60)
        return Flight(
            id: "demo-ax204-\(Int(now.timeIntervalSince1970))",
            flightNumber: "AX 204",
            airlineCode: "AX",
            airlineName: "Aurora Air",
            origin: Airport(iata: "SFO", icao: "KSFO", name: "San Francisco International", city: "San Francisco", timeZone: "America/Los_Angeles"),
            destination: Airport(iata: "JFK", icao: "KJFK", name: "John F. Kennedy International", city: "New York", timeZone: "America/New_York"),
            status: .boardingSoon,
            scheduledDeparture: departure,
            estimatedDeparture: departure,
            actualDeparture: nil,
            scheduledArrival: departure.addingTimeInterval(5.5 * 3600),
            estimatedArrival: departure.addingTimeInterval(5.5 * 3600),
            actualArrival: nil,
            departureTerminal: "2",
            arrivalTerminal: "5",
            gate: "C12",
            arrivalGate: nil,
            previousGate: "C8",
            boardingStatus: "Boarding begins soon",
            boardingGroup: "4",
            boardingTime: boarding,
            delayMinutes: 0,
            aircraftType: "A321neo",
            baggageClaim: nil,
            source: .demo
        )
    }
}
