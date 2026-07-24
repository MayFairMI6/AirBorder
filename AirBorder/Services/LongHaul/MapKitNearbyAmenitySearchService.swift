import CoreLocation
import Foundation
import MapKit

struct GeographicAmenityMatch: Identifiable, Sendable {
    let id: String
    let name: String
    let category: PassengerAmenityCategory?
    let coordinate: CLLocationCoordinate2D
    let distanceFromSearchCenterMeters: Double
    let websiteURL: URL?
    let phoneNumber: String?
    let itemAvailability: ItemAvailabilityAssessment?
}

enum ItemAvailabilityState: Equatable, Sendable {
    case confirmedInStock
    case confirmedOutOfStock
    case likelySoldHereStockNotConfirmed
    case unknown

    var passengerLabel: String {
        switch self {
        case .confirmedInStock: "Confirmed in stock"
        case .confirmedOutOfStock: "Currently out of stock"
        case .likelySoldHereStockNotConfirmed: "Likely sold here — stock not confirmed"
        case .unknown: "Item availability unknown"
        }
    }
}

struct ItemAvailabilityAssessment: Equatable, Sendable {
    let state: ItemAvailabilityState
    let observedAt: Date?
    let expiresAt: Date?
}

struct MerchantInventoryQuery: Sendable {
    let itemQuery: String
    let merchantPlaceID: String
}

struct MerchantInventoryRecord: Sendable {
    let isInStock: Bool
    let observedAt: Date
    let expiresAt: Date
}

protocol MerchantInventoryProvider: Sendable {
    func inventory(for query: MerchantInventoryQuery) async throws -> MerchantInventoryRecord?
}

struct UnavailableMerchantInventoryProvider: MerchantInventoryProvider {
    func inventory(for query: MerchantInventoryQuery) async throws -> MerchantInventoryRecord? { nil }
}

struct ItemAvailabilityResolver {
    func assess(
        mapSearchMatchedExactQuery: Bool,
        inventoryRecord: MerchantInventoryRecord?,
        now: Date
    ) -> ItemAvailabilityAssessment {
        if let inventoryRecord, inventoryRecord.expiresAt > now {
            return ItemAvailabilityAssessment(
                state: inventoryRecord.isInStock ? .confirmedInStock : .confirmedOutOfStock,
                observedAt: inventoryRecord.observedAt,
                expiresAt: inventoryRecord.expiresAt
            )
        }
        return ItemAvailabilityAssessment(
            state: mapSearchMatchedExactQuery ? .likelySoldHereStockNotConfirmed : .unknown,
            observedAt: nil,
            expiresAt: nil
        )
    }
}

struct MapKitNearbyAmenitySearchService {
    /// A short list keeps the choice scannable while retaining tied nearest results.
    private static let maximumDisplayedResults = 5

    func nearest(
        category: PassengerAmenityCategory,
        center: CLLocationCoordinate2D,
        radiusMeters: Double
    ) async throws -> [GeographicAmenityMatch] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query(for: category)
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: pointOfInterestCategories(for: category))

        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate = item.placemark.coordinate
            let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard distance <= radiusMeters else { return nil }
            return GeographicAmenityMatch(
                id: "amenity-\(category.rawValue)-\(coordinate.latitude)-\(coordinate.longitude)",
                name: name,
                category: category,
                coordinate: coordinate,
                distanceFromSearchCenterMeters: distance,
                websiteURL: item.url,
                phoneNumber: item.phoneNumber,
                itemAvailability: nil
            )
        }
        .sorted {
            if $0.distanceFromSearchCenterMeters == $1.distanceFromSearchCenterMeters {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.distanceFromSearchCenterMeters < $1.distanceFromSearchCenterMeters
        }
        .prefix(Self.maximumDisplayedResults)
        .map { $0 }
    }

    func search(
        itemQuery: String,
        center: CLLocationCoordinate2D,
        radiusMeters: Double
    ) async throws -> [GeographicAmenityMatch] {
        let normalizedQuery = itemQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = normalizedQuery
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.store, .foodMarket, .pharmacy])

        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let availability = ItemAvailabilityResolver().assess(
            mapSearchMatchedExactQuery: true,
            inventoryRecord: nil,
            now: Date()
        )
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate = item.placemark.coordinate
            let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard distance <= radiusMeters else { return nil }
            return GeographicAmenityMatch(
                id: "item-\(normalizedQuery.lowercased())-\(coordinate.latitude)-\(coordinate.longitude)",
                name: name,
                category: nil,
                coordinate: coordinate,
                distanceFromSearchCenterMeters: distance,
                websiteURL: item.url,
                phoneNumber: item.phoneNumber,
                itemAvailability: availability
            )
        }
        .sorted {
            if $0.distanceFromSearchCenterMeters == $1.distanceFromSearchCenterMeters {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.distanceFromSearchCenterMeters < $1.distanceFromSearchCenterMeters
        }
        .prefix(Self.maximumDisplayedResults)
        .map { $0 }
    }

    private func query(for category: PassengerAmenityCategory) -> String {
        switch category {
        case .restroom: "public restroom"
        case .meal: "restaurant"
        case .snackDrink: "snacks and drinks"
        case .clothing: "clothing store"
        case .electronics: "electronics store"
        }
    }

    private func pointOfInterestCategories(for category: PassengerAmenityCategory) -> [MKPointOfInterestCategory] {
        switch category {
        case .restroom: [.restroom]
        case .meal: [.restaurant]
        case .snackDrink: [.cafe, .bakery, .foodMarket]
        case .clothing, .electronics: [.store]
        }
    }
}
