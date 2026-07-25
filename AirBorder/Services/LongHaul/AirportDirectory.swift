import CoreLocation
import MapKit

struct ResolvedAirportLocation: Sendable {
    let airport: Airport
    let coordinate: CLLocationCoordinate2D?
}

/// Resolves airport codes from the bundled registry first, then asks MapKit for
/// airports not yet included in the local catalog. This keeps ticket imports
/// useful offline while allowing a trip to expand beyond curated airports.
@MainActor
enum AirportDirectory {
    static func resolve(_ airportCode: String) async -> ResolvedAirportLocation {
        let code = airportCode.uppercased()
        if let reference = AirportReferencePointRegistry.referencePoint(for: code) {
            return ResolvedAirportLocation(
                airport: airport(for: code, reference: reference),
                coordinate: CLLocationCoordinate2D(latitude: reference.latitude, longitude: reference.longitude)
            )
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(code) airport"
        if let response = try? await MKLocalSearch(request: request).start(),
           let item = response.mapItems.first(where: { item in
               item.name?.uppercased().contains(code) == true
           }) ?? response.mapItems.first {
            let placemark = item.placemark
            return ResolvedAirportLocation(
                airport: Airport(
                    iata: code,
                    icao: nil,
                    name: item.name ?? "\(code) Airport",
                    city: placemark.locality,
                    timeZone: placemark.timeZone?.identifier
                ),
                coordinate: placemark.coordinate
            )
        }

        return ResolvedAirportLocation(
            airport: Airport(iata: code, icao: nil, name: "\(code) Airport", city: nil, timeZone: MetroAirportDatabase.metroArea(containing: code)?.defaultTimeZoneIdentifier),
            coordinate: nil
        )
    }

    private static func airport(for code: String, reference: AirportReferencePoint) -> Airport {
        let metro = MetroAirportDatabase.metroArea(containing: code)
        return Airport(
            iata: code,
            icao: reference.sourceRecordID,
            name: "\(code) Airport",
            city: metro?.name,
            timeZone: metro?.defaultTimeZoneIdentifier
        )
    }
}

@MainActor
final class AirportLocationStore: ObservableObject {
    @Published private(set) var locations: [String: CLLocationCoordinate2D] = [:]

    func resolve(_ codes: [String]) async {
        for code in Set(codes.map { $0.uppercased() }) where locations[code] == nil {
            let location = await AirportDirectory.resolve(code)
            if let coordinate = location.coordinate {
                locations[code] = coordinate
            }
        }
    }
}
