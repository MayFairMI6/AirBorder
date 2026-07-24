import Foundation

struct MetroAirportRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let countryCodes: Set<String>
    let airportCodes: Set<String>
    let defaultTimeZoneIdentifier: String
    let routingAdapterIDs: [String]
    let verifiedAt: Date
    let sourceURL: URL
}

struct AirportReferencePoint: Codable, Hashable, Sendable {
    let airportCode: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let sourceRecordID: String
    let sourceURL: URL
    let verifiedAt: Date
}

enum AirportChangeKind: String, Codable, Sendable {
    case sameAirport
    case sameMetroArea
    case crossRegionSurfaceSector
}

struct AirportChangeAssessment: Codable, Hashable, Sendable {
    let kind: AirportChangeKind
    let metroArea: MetroAirportRecord?
    let originAirportCode: String
    let destinationAirportCode: String
}

/// Versioned, offline metro-airport registry. Airport codes are seeded from the
/// public-domain OurAirports dataset; the metro grouping is a curated planning
/// index and never supplies travel time. Live route adapters remain responsible
/// for schedules, disruption, accessibility, and last-service facts.
enum MetroAirportDatabase {
    static let version = "metro-airports-2026-07-14-v1"
    static let sourceURL = URL(string: "https://ourairports.com/data/")!
    private static let verifiedAt = ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z")!

    static let records: [MetroAirportRecord] = [
        record("tokyo", "Tokyo", ["JP"], ["HND", "NRT"], "Asia/Tokyo"),
        record("osaka", "Osaka–Kansai–Kobe", ["JP"], ["KIX", "ITM", "UKB"], "Asia/Tokyo"),
        record("seoul", "Seoul", ["KR"], ["ICN", "GMP"], "Asia/Seoul"),
        record("bangkok", "Bangkok", ["TH"], ["BKK", "DMK"], "Asia/Bangkok"),
        record("beijing", "Beijing", ["CN"], ["PEK", "PKX"], "Asia/Shanghai"),
        record("shanghai", "Shanghai", ["CN"], ["PVG", "SHA"], "Asia/Shanghai"),
        record("taipei", "Taipei", ["TW"], ["TPE", "TSA"], "Asia/Taipei"),
        record("kuala-lumpur", "Kuala Lumpur", ["MY"], ["KUL", "SZB"], "Asia/Kuala_Lumpur"),
        record("istanbul", "Istanbul", ["TR"], ["IST", "SAW"], "Europe/Istanbul"),
        record("london", "London", ["GB"], ["LHR", "LGW", "LCY", "LTN", "STN", "SEN"], "Europe/London"),
        record("paris", "Paris", ["FR"], ["CDG", "ORY", "BVA"], "Europe/Paris"),
        record("milan", "Milan", ["IT"], ["MXP", "LIN", "BGY"], "Europe/Rome"),
        record("rome", "Rome", ["IT"], ["FCO", "CIA"], "Europe/Rome"),
        record("stockholm", "Stockholm", ["SE"], ["ARN", "BMA", "NYO", "VST"], "Europe/Stockholm"),
        record("new-york", "New York metropolitan area", ["US"], ["JFK", "LGA", "EWR", "SWF"], "America/New_York"),
        record("washington", "Washington–Baltimore", ["US"], ["IAD", "DCA", "BWI"], "America/New_York"),
        record("chicago", "Chicago", ["US"], ["ORD", "MDW"], "America/Chicago"),
        record("san-francisco-bay", "San Francisco Bay Area", ["US"], ["SFO", "OAK", "SJC"], "America/Los_Angeles"),
        record("los-angeles", "Greater Los Angeles", ["US"], ["LAX", "BUR", "LGB", "SNA", "ONT"], "America/Los_Angeles"),
        record("south-florida", "South Florida", ["US"], ["MIA", "FLL", "PBI"], "America/New_York"),
        record("toronto", "Greater Toronto", ["CA"], ["YYZ", "YTZ", "YHM"], "America/Toronto"),
        record("sao-paulo", "São Paulo", ["BR"], ["GRU", "CGH", "VCP"], "America/Sao_Paulo"),
        record("rio-de-janeiro", "Rio de Janeiro", ["BR"], ["GIG", "SDU"], "America/Sao_Paulo"),
        record("buenos-aires", "Buenos Aires", ["AR"], ["EZE", "AEP"], "America/Argentina/Buenos_Aires"),
        record("melbourne", "Melbourne", ["AU"], ["MEL", "AVV"], "Australia/Melbourne")
    ]

    static func metroArea(containing airportCode: String) -> MetroAirportRecord? {
        let code = airportCode.uppercased()
        return records.first(where: { $0.airportCodes.contains(code) })
    }

    static func classify(from originAirportCode: String, to destinationAirportCode: String) -> AirportChangeAssessment {
        let origin = originAirportCode.uppercased()
        let destination = destinationAirportCode.uppercased()
        if origin == destination {
            return AirportChangeAssessment(kind: .sameAirport, metroArea: metroArea(containing: origin), originAirportCode: origin, destinationAirportCode: destination)
        }
        let originMetro = metroArea(containing: origin)
        let destinationMetro = metroArea(containing: destination)
        if let originMetro, originMetro.id == destinationMetro?.id {
            return AirportChangeAssessment(kind: .sameMetroArea, metroArea: originMetro, originAirportCode: origin, destinationAirportCode: destination)
        }
        return AirportChangeAssessment(kind: .crossRegionSurfaceSector, metroArea: nil, originAirportCode: origin, destinationAirportCode: destination)
    }

    private static func record(
        _ id: String,
        _ name: String,
        _ countries: Set<String>,
        _ airports: Set<String>,
        _ timeZone: String
    ) -> MetroAirportRecord {
        MetroAirportRecord(
            id: id,
            name: name,
            countryCodes: countries,
            airportCodes: airports,
            defaultTimeZoneIdentifier: timeZone,
            routingAdapterIDs: ["gtfs-static", "gtfs-realtime", "road-routing"],
            verifiedAt: verifiedAt,
            sourceURL: sourceURL
        )
    }
}

/// Versioned airport coordinates used only to center discovery requests. They
/// are source records, not routing estimates: MapKit or another place provider
/// still derives the actual results and distances for the current request.
enum AirportReferencePointRegistry {
    static let version = "ourairports-reference-points-2026-07-14-v1"
    static let sourceURL = URL(string: "https://ourairports.com/data/")!
    private static let verifiedAt = ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z")!

    static let records: [String: AirportReferencePoint] = [
        "BKK": point("BKK", countryCode: "TH", latitude: 13.6811, longitude: 100.747002, sourceRecordID: "VTBS"),
        "HND": point("HND", countryCode: "JP", latitude: 35.549678, longitude: 139.786958, sourceRecordID: "RJTT"),
        "NRT": point("NRT", countryCode: "JP", latitude: 35.76858, longitude: 140.388714, sourceRecordID: "RJAA"),
        "LAX": point("LAX", countryCode: "US", latitude: 33.942501, longitude: -118.407997, sourceRecordID: "KLAX")
    ]

    static func referencePoint(for airportCode: String) -> AirportReferencePoint? {
        records[airportCode.uppercased()]
    }

    private static func point(
        _ airportCode: String,
        countryCode: String,
        latitude: Double,
        longitude: Double,
        sourceRecordID: String
    ) -> AirportReferencePoint {
        AirportReferencePoint(
            airportCode: airportCode,
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude,
            sourceRecordID: sourceRecordID,
            sourceURL: sourceURL,
            verifiedAt: verifiedAt
        )
    }
}
