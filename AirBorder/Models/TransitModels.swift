import Foundation

enum TransitMode: String, Codable, CaseIterable, Sendable {
    case airportRail
    case metro
    case expressBus
    case localBus
    case taxi
    case rideshare
}

struct TransitOption: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let mode: TransitMode
    let destination: String
    let departureTime: Date?
    let arrivalTime: Date?
    let durationMinutes: Int
    let cost: Decimal?
    let currencyCode: String
    let transfers: Int
    let walkingMeters: Int
    let wheelchairAccessible: Bool?
    let luggageSuitability: String
    let disruption: String?
    let firstService: Date?
    let lastService: Date?
    let source: String
    let isLive: Bool
}

struct TransitStop: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let wheelchairBoarding: Int?
}

enum LayoverSafety: String, Codable, Sendable {
    case safe
    case tight
    case notRecommended

    var title: String {
        return switch self {
        case .safe: "Safe"
        case .tight: "Tight"
        case .notRecommended: "Not recommended"
        }
    }
}

struct LayoverAssessment: Codable, Sendable {
    let safety: LayoverSafety
    let remainingMarginMinutes: Int
    let message: String
}
