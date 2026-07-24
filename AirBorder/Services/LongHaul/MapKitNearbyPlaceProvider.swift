import Foundation
import MapKit

struct NearbyDiscoveryPolicy: Codable, Hashable, Sendable {
    static let current = NearbyDiscoveryPolicy(
        version: "nearby-discovery-2026-07-14-v1",
        airportRadiusMeters: 5_000,
        cityVisitRadiusMeters: 35_000,
        rationale: "A five-kilometer airport-centered discovery area limits results to practical nearby options; actual travel time is still required before recommendation."
    )

    let version: String
    let airportRadiusMeters: Double
    let cityVisitRadiusMeters: Double
    let rationale: String
}

struct MapKitNearbyPlaceProvider: PlaceProvider {
    func places(for context: PlaceSearchContext) async throws -> [LayoverPlace] {
        let categories = pointOfInterestCategories(for: context.categories)
        let request = MKLocalPointsOfInterestRequest(
            center: CLLocationCoordinate2D(latitude: context.centerLatitude, longitude: context.centerLongitude),
            radius: context.radiusMeters
        )
        if !categories.isEmpty {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate = item.placemark.coordinate
            let category = category(for: item.pointOfInterestCategory)
            return LayoverPlace(
                id: "mapkit-\(name.lowercased())-\(coordinate.latitude)-\(coordinate.longitude)",
                name: name,
                airportCode: context.airport.iata,
                terminal: nil,
                category: category,
                accessZone: .nearby,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                summary: "Discovered with native MapKit. Terminal access, opening hours, price, room availability, and day-use claims are not supplied.",
                bookingURL: item.url,
                officialSourceURL: item.url,
                dataMode: .live
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func pointOfInterestCategories(for categories: Set<LayoverPlaceCategory>) -> [MKPointOfInterestCategory] {
        let requested = categories.isEmpty ? Set(LayoverPlaceCategory.allCases) : categories
        var result: Set<MKPointOfInterestCategory> = []
        for category in requested {
            switch category {
            case .hotel, .transitHotel, .dayRoom: result.insert(.hotel)
            case .food: result.formUnion([.restaurant, .cafe, .bakery])
            case .attraction:
                result.formUnion([.museum, .park])
                if #available(iOS 18.0, *) {
                    result.insert(.nationalMonument)
                }
            case .charging: result.insert(.evCharger)
            case .facility: result.formUnion([.pharmacy, .hospital, .publicTransport])
            case .workPod, .lounge, .shower: break
            }
        }
        return Array(result)
    }

    private func category(for category: MKPointOfInterestCategory?) -> LayoverPlaceCategory {
        switch category {
        case .hotel: .hotel
        case .restaurant, .cafe, .bakery: .food
        case .museum, .park: .attraction
        case .evCharger: .charging
        default: .facility
        }
    }
}
