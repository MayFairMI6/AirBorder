import Foundation

struct CachedFlightCollection: Codable, Sendable {
    let flights: [Flight]
    let storedAt: Date
}

protocol FlightCaching: Sendable {
    func flights(for key: String) async -> CachedFlightCollection?
    func save(flights: [Flight], for key: String, at date: Date) async throws
    func activeJourney() async -> ActiveJourney?
    func save(activeJourney: ActiveJourney?) async throws
    func clear() async throws
}

private struct FlightCacheSnapshot: Codable {
    var searches: [String: CachedFlightCollection] = [:]
    var journey: ActiveJourney?
}

actor FlightCache: FlightCaching {
    private let fileURL: URL
    private var snapshot: FlightCacheSnapshot

    init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AirportXRCompanion", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("journey-cache-v1.json")
        snapshot = Self.readSnapshot(from: fileURL)
    }

    func flights(for key: String) async -> CachedFlightCollection? {
        snapshot.searches[key]
    }

    func save(flights: [Flight], for key: String, at date: Date) async throws {
        snapshot.searches[key] = CachedFlightCollection(flights: flights, storedAt: date)
        try persist()
    }

    func activeJourney() async -> ActiveJourney? { snapshot.journey }

    func save(activeJourney: ActiveJourney?) async throws {
        snapshot.journey = activeJourney
        try persist()
    }

    func clear() async throws {
        snapshot = FlightCacheSnapshot()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = fileURL
        try? mutableURL.setResourceValues(values)
    }

    private static func readSnapshot(from url: URL) -> FlightCacheSnapshot {
        guard let data = try? Data(contentsOf: url) else { return FlightCacheSnapshot() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(FlightCacheSnapshot.self, from: data)) ?? FlightCacheSnapshot()
    }
}

