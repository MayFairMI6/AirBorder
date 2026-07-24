import CoreLocation

/// Coordinates used only by the city-transfer practice driver. Keeping them
/// out of the map view prevents a Tokyo fixture from becoming product logic.
struct CityTransferPracticeMapConfiguration: Sendable {
    let originCoordinate: CLLocationCoordinate2D
    let stopCoordinate: CLLocationCoordinate2D
    let destinationCoordinate: CLLocationCoordinate2D
    let center: CLLocationCoordinate2D
    let latitudeDelta: CLLocationDegrees
    let longitudeDelta: CLLocationDegrees

    static func matching(origin: String, destination: String) -> CityTransferPracticeMapConfiguration? {
        guard origin.uppercased() == "HND", destination.uppercased() == "NRT" else { return nil }
        return CityTransferPracticeMapConfiguration(
            originCoordinate: CLLocationCoordinate2D(latitude: 35.5494, longitude: 139.7798),
            stopCoordinate: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            destinationCoordinate: CLLocationCoordinate2D(latitude: 35.7720, longitude: 140.3929),
            center: CLLocationCoordinate2D(latitude: 35.66, longitude: 140.05),
            latitudeDelta: 0.42,
            longitudeDelta: 0.95
        )
    }
}
