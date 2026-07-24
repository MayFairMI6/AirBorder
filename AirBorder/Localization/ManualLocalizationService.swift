import Combine
import CoreLocation
import Foundation

enum IndoorLocationSource: String, Codable, Sendable {
    case manualLandmark
    case routeReplay
    case externalSignalReplay
    case coreLocationReplay
    case venuePositioning
    case beaconProximity
    case ultraWideband
}

/// QA-only WGS84 projection for exercising Apple's Core Location delivery in
/// Simulator. The footprint is a named synthetic fixture around the airport
/// reference point; it is not an airport survey or production indoor map.
enum HNDCoreLocationQAFixture {
    static let version = "hnd-core-location-qa-v1"
    static let anchorLatitude = 35.549678
    static let anchorLongitude = 139.786958
    static let eastWestExtentMeters = 240.0
    static let northSouthExtentMeters = 180.0
    static let metersPerLatitudeDegree = 111_320.0
    static let maximumNodeSnapMeters = 45.0

    static func coordinate(for point: MapPoint) -> CLLocationCoordinate2D {
        let northMeters = (point.y - 0.5) * northSouthExtentMeters
        let eastMeters = (point.x - 0.5) * eastWestExtentMeters
        let latitude = anchorLatitude + northMeters / metersPerLatitudeDegree
        let longitudeScale = metersPerLatitudeDegree * cos(anchorLatitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: latitude,
            longitude: anchorLongitude + eastMeters / longitudeScale
        )
    }

    static func point(for coordinate: CLLocationCoordinate2D) -> MapPoint {
        let northMeters = (coordinate.latitude - anchorLatitude) * metersPerLatitudeDegree
        let longitudeScale = metersPerLatitudeDegree * cos(anchorLatitude * .pi / 180)
        let eastMeters = (coordinate.longitude - anchorLongitude) * longitudeScale
        return MapPoint(
            x: 0.5 + eastMeters / eastWestExtentMeters,
            y: 0.5 + northMeters / northSouthExtentMeters
        )
    }

    static func reading(
        from location: CLLocation,
        graph: TerminalGraph,
        observedAt: Date? = nil
    ) -> IndoorLocationReading? {
        let localPoint = point(for: location.coordinate)
        guard let nearest = graph.nodes.min(by: {
            distanceMeters(from: localPoint, to: $0.point)
                < distanceMeters(from: localPoint, to: $1.point)
        }), distanceMeters(from: localPoint, to: nearest.point) <= maximumNodeSnapMeters else {
            return nil
        }
        let heading = location.course >= 0 ? location.course : 0
        return IndoorLocationReading(
            point: localPoint,
            level: nearest.level,
            matchedNodeID: nearest.id,
            headingDegrees: heading,
            observedAt: observedAt ?? location.timestamp,
            source: .coreLocationReplay
        )
    }

    private static func distanceMeters(from lhs: MapPoint, to rhs: MapPoint) -> Double {
        let east = (lhs.x - rhs.x) * eastWestExtentMeters
        let north = (lhs.y - rhs.y) * northSouthExtentMeters
        return hypot(east, north)
    }
}

@MainActor
final class CoreLocationIndoorQAService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var reading: IndoorLocationReading?
    @Published private(set) var status = "Waiting for Apple location signal"

    private let manager = CLLocationManager()
    private var graph: TerminalGraph?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func start(graph: TerminalGraph) {
        self.graph = graph
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        graph = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let graph, let location = locations.last else { return }
        guard let mapped = HNDCoreLocationQAFixture.reading(from: location, graph: graph) else {
            status = "Move the test location onto the terminal route"
            return
        }
        reading = mapped
        status = "Apple location signal connected"
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "Apple location signal unavailable"
    }
}

struct IndoorLocationReading: Codable, Equatable, Sendable {
    let point: MapPoint
    let level: Int
    let matchedNodeID: String
    let headingDegrees: Double
    let observedAt: Date
    let source: IndoorLocationSource
}

enum LocalIndoorSignalFeedError: Error, Equatable {
    case nonLoopbackEndpoint
    case invalidResponse
}

struct LocalIndoorSignalFeedClient: Sendable {
    let endpoint: URL

    init(endpoint: URL) throws {
        let host = endpoint.host?.lowercased()
        guard endpoint.scheme?.lowercased() == "http",
              host == "127.0.0.1" || host == "localhost" else {
            throw LocalIndoorSignalFeedError.nonLoopbackEndpoint
        }
        self.endpoint = endpoint
    }

    func latestReading() async throws -> IndoorLocationReading {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LocalIndoorSignalFeedError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IndoorLocationReading.self, from: data)
    }
}

/// Produces repeatable indoor coordinates in the venue's local map space.
/// It intentionally does not pretend that latitude/longitude can locate a
/// traveler inside a terminal or across floors.
struct TerminalRouteLocationEmulator: Sendable {
    let graph: TerminalGraph
    let route: TerminalRoute

    func readings(
        samplesPerSegment: Int,
        startingAt start: Date,
        sampleInterval: TimeInterval
    ) -> [IndoorLocationReading] {
        let nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        let routeNodes = route.nodeIDs.compactMap { nodesByID[$0] }
        guard let finalNode = routeNodes.last else { return [] }

        let sampleCount = max(1, samplesPerSegment)
        var output: [IndoorLocationReading] = []
        for pair in zip(routeNodes, routeNodes.dropFirst()) {
            let (from, to) = pair
            let heading = atan2(to.point.x - from.point.x, to.point.y - from.point.y) * 180 / .pi
            for sampleIndex in 0..<sampleCount {
                let progress = Double(sampleIndex) / Double(sampleCount)
                output.append(
                    IndoorLocationReading(
                        point: MapPoint(
                            x: from.point.x + ((to.point.x - from.point.x) * progress),
                            y: from.point.y + ((to.point.y - from.point.y) * progress)
                        ),
                        level: progress < 0.5 ? from.level : to.level,
                        matchedNodeID: from.id,
                        headingDegrees: heading,
                        observedAt: start.addingTimeInterval(Double(output.count) * sampleInterval),
                        source: .routeReplay
                    )
                )
            }
        }

        output.append(
            IndoorLocationReading(
                point: finalNode.point,
                level: finalNode.level,
                matchedNodeID: finalNode.id,
                headingDegrees: output.last?.headingDegrees ?? 0,
                observedAt: start.addingTimeInterval(Double(output.count) * sampleInterval),
                source: .routeReplay
            )
        )
        return output
    }
}

@MainActor
final class ManualLocalizationService: ObservableObject {
    @Published private(set) var currentNodeID = "security-exit"
    @Published private(set) var confidence: LocalizationConfidence = .high

    func calibrate(to nodeID: String) {
        currentNodeID = nodeID
        confidence = .high
    }

    func trackingBecameUncertain() {
        confidence = .low
    }
}
