import Foundation
import CoreLocation

enum AccessZone: String, Codable, CaseIterable, Identifiable, Sendable {
    case airside
    case airportLandside
    case nearby
    case city
    var id: String { rawValue }

    var title: String {
        switch self {
        case .airside: "Airside"
        case .airportLandside: "Airport Landside"
        case .nearby: "Nearby"
        case .city: "City"
        }
    }
}

enum LayoverPlaceCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case hotel
    case transitHotel
    case dayRoom
    case workPod
    case lounge
    case shower
    case charging
    case food
    case facility
    case attraction
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hotel: "Hotels"
        case .transitHotel: "Transit hotels"
        case .dayRoom: "Day rooms"
        case .workPod: "Work pods"
        case .lounge: "Lounges"
        case .shower: "Showers"
        case .charging: "Charging"
        case .food: "Food"
        case .facility: "Facilities"
        case .attraction: "Attractions"
        }
    }
}

struct OpeningWindow: Codable, Hashable, Sendable {
    /// Calendar weekday values, where 1 is Sunday and 7 is Saturday.
    let weekdays: Set<Int>
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int
    let timeZoneIdentifier: String

    func contains(_ date: Date) -> Bool {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        guard weekdays.contains(weekday) else { return false }
        if startMinuteOfDay == endMinuteOfDay { return true }
        if startMinuteOfDay <= endMinuteOfDay {
            return startMinuteOfDay <= minute && minute < endMinuteOfDay
        }
        return minute >= startMinuteOfDay || minute < endMinuteOfDay
    }
}

struct LayoverPlace: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let airportCode: String
    let terminal: String?
    let category: LayoverPlaceCategory
    let accessZone: AccessZone
    let latitude: Double?
    let longitude: Double?
    let summary: String
    let bookingURL: URL?
    let officialSourceURL: URL?
    let dataMode: DataFreshness

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct AirportFacilityRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let place: LayoverPlace
    let accessRestrictions: String?
    let openingWindows: [OpeningWindow]
    let hoursRequireConfirmation: Bool
    let sourceUpdatedAt: Date?
    let verifiedAt: Date

    func isOpen(at date: Date) -> Bool? {
        guard !openingWindows.isEmpty else { return nil }
        return openingWindows.contains { $0.contains(date) }
    }
}

struct PlaceSearchContext: Codable, Hashable, Sendable {
    let airport: Airport
    let centerLatitude: Double
    let centerLongitude: Double
    let radiusMeters: Double
    let categories: Set<LayoverPlaceCategory>
    let at: Date
}

struct AccommodationOffer: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let place: LayoverPlace
    let totalPrice: Decimal?
    let currencyCode: String?
    let checkIn: Date?
    let checkOut: Date?
    let observedAt: Date
    let expiresAt: Date
    let externalBookingURL: URL?
}
