import Foundation

enum FlightStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case onTime
    case delayed
    case boardingSoon
    case boarding
    case departed
    case enRoute
    case arrived
    case cancelled
    case diverted
    case unknown

    var title: String {
        return switch self {
        case .onTime: "On time"
        case .boardingSoon: "Boarding soon"
        case .enRoute: "En route"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        return switch self {
        case .scheduled, .onTime: "checkmark.circle.fill"
        case .delayed: "clock.badge.exclamationmark.fill"
        case .boardingSoon, .boarding: "figure.walk.motion"
        case .departed, .enRoute: "airplane"
        case .arrived: "flag.checkered"
        case .cancelled: "xmark.octagon.fill"
        case .diverted: "arrow.triangle.branch"
        case .unknown: "questionmark.circle"
        }
    }
}

struct Airport: Codable, Hashable, Sendable {
    let iata: String
    let icao: String?
    let name: String
    let city: String?
    let timeZone: String?
}

struct ProviderMetadata: Codable, Hashable, Sendable {
    let name: String
    let providerRecordID: String?
    let providerUpdatedAt: Date?
    let receivedAt: Date
    let isLive: Bool
    let isDemo: Bool
    let providerPolicyID: String?
    let providerPolicyVersion: String?
    let providerTrainingAllowed: Bool?
    let providerTrainingPurposes: Set<ProviderTrainingPurpose>

    init(
        name: String,
        providerRecordID: String?,
        providerUpdatedAt: Date?,
        receivedAt: Date,
        isLive: Bool,
        isDemo: Bool,
        providerPolicyID: String? = nil,
        providerPolicyVersion: String? = nil,
        providerTrainingAllowed: Bool? = nil,
        providerTrainingPurposes: Set<ProviderTrainingPurpose> = []
    ) {
        self.name = name
        self.providerRecordID = providerRecordID
        self.providerUpdatedAt = providerUpdatedAt
        self.receivedAt = receivedAt
        self.isLive = isLive
        self.isDemo = isDemo
        self.providerPolicyID = providerPolicyID
        self.providerPolicyVersion = providerPolicyVersion
        self.providerTrainingAllowed = providerTrainingAllowed
        self.providerTrainingPurposes = providerTrainingPurposes
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case providerRecordID
        case providerUpdatedAt
        case receivedAt
        case isLive
        case isDemo
        case providerPolicyID
        case providerPolicyVersion
        case providerTrainingAllowed
        case providerTrainingPurposes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        providerRecordID = try values.decodeIfPresent(String.self, forKey: .providerRecordID)
        providerUpdatedAt = try values.decodeIfPresent(Date.self, forKey: .providerUpdatedAt)
        receivedAt = try values.decode(Date.self, forKey: .receivedAt)
        isLive = try values.decode(Bool.self, forKey: .isLive)
        isDemo = try values.decode(Bool.self, forKey: .isDemo)
        providerPolicyID = try values.decodeIfPresent(String.self, forKey: .providerPolicyID)
        providerPolicyVersion = try values.decodeIfPresent(String.self, forKey: .providerPolicyVersion)
        providerTrainingAllowed = try values.decodeIfPresent(Bool.self, forKey: .providerTrainingAllowed)
        providerTrainingPurposes = try values.decodeIfPresent(Set<ProviderTrainingPurpose>.self, forKey: .providerTrainingPurposes) ?? []
    }

    static let demo = ProviderMetadata(
        name: "Example flight updates",
        providerRecordID: "demo-ax204",
        providerUpdatedAt: nil,
        receivedAt: Date(),
        isLive: false,
        isDemo: true
    )
}

struct Flight: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let flightNumber: String
    let airlineCode: String?
    let airlineName: String?
    let origin: Airport
    let destination: Airport
    var status: FlightStatus
    let scheduledDeparture: Date?
    var estimatedDeparture: Date?
    var actualDeparture: Date?
    let scheduledArrival: Date?
    var estimatedArrival: Date?
    var actualArrival: Date?
    var departureTerminal: String?
    var arrivalTerminal: String?
    var gate: String?
    var arrivalGate: String?
    var previousGate: String?
    var boardingStatus: String?
    var boardingGroup: String?
    var boardingTime: Date?
    var delayMinutes: Int?
    let aircraftType: String?
    var baggageClaim: String?
    var source: ProviderMetadata

    var effectiveDeparture: Date? {
        actualDeparture ?? estimatedDeparture ?? scheduledDeparture
    }

    var effectiveArrival: Date? {
        actualArrival ?? estimatedArrival ?? scheduledArrival
    }

    var routeLabel: String { "\(origin.iata) to \(destination.iata)" }
}

struct FlightQuery: Codable, Hashable, Sendable {
    let airlineCode: String
    let flightNumber: String
    let date: Date

    var normalizedIdentifier: String {
        let airline = airlineCode.uppercased().filter(\.isLetter)
        let number = flightNumber.uppercased().filter { $0.isLetter || $0.isNumber }
        if number.hasPrefix(airline) { return number }
        return airline + number
    }

    var cacheKey: String {
        let day = Calendar(identifier: .gregorian).startOfDay(for: date).timeIntervalSince1970
        return "flight:\(normalizedIdentifier):\(Int(day))"
    }
}

enum AirportBoardKind: String, Codable, Sendable {
    case departures
    case arrivals
}

enum DataFreshness: String, Codable, Sendable {
    case live
    case cached
    case stale
    case demo
    case unavailable

    var title: String {
        return switch self {
        case .live: "Live"
        case .cached: "Saved"
        case .stale: "Needs refresh"
        case .demo: "Example"
        case .unavailable: "Unavailable"
        }
    }
}

struct FlightRepositoryResult: Sendable {
    let flights: [Flight]
    let freshness: DataFreshness
    let fetchedAt: Date
    let warning: String?
}
