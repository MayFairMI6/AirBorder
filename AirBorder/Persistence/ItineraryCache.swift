import Foundation

protocol ItineraryCaching: Sendable {
    func loadItinerary() async -> Itinerary?
    func saveItinerary(_ itinerary: Itinerary?) async throws
    func loadTicketScanResult() async -> TicketPDFScanResult?
    func saveTicketScanResult(_ result: TicketPDFScanResult?) async throws
    func loadTravelerProfile() async -> TravelerProfile
    func saveTravelerProfile(_ profile: TravelerProfile) async throws
    func clearLongHaulData() async throws
}

private struct LongHaulCacheSnapshot: Codable {
    var schemaVersion = Itinerary.currentSchemaVersion
    var providerPolicyVersion = ProviderPolicyRegistry.version
    var predictionModelVersion = 2
    var itinerary: Itinerary?
    var ticketScanResult: TicketPDFScanResult?
    var travelerProfile = TravelerProfile.incomplete
}

private struct LegacyJourneySnapshot: Decodable {
    let journey: ActiveJourney?
}

actor ItineraryCache: ItineraryCaching {
    private let fileURL: URL
    private let legacyURL: URL
    private var snapshot: LongHaulCacheSnapshot

    init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AirportXRCompanion", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("itinerary-cache-v2.json")
        legacyURL = root.appendingPathComponent("journey-cache-v1.json")
        if let loaded = Self.read(from: fileURL) {
            snapshot = loaded
        } else {
            snapshot = LongHaulCacheSnapshot()
            if let migrated = Self.readLegacy(from: legacyURL) {
                snapshot.itinerary = Itinerary.migrated(from: migrated)
                try? Self.persist(snapshot, to: fileURL)
            }
        }
    }

    func loadItinerary() async -> Itinerary? { snapshot.itinerary }

    func saveItinerary(_ itinerary: Itinerary?) async throws {
        snapshot.itinerary = itinerary
        snapshot.schemaVersion = Itinerary.currentSchemaVersion
        snapshot.providerPolicyVersion = ProviderPolicyRegistry.version
        try Self.persist(snapshot, to: fileURL)
    }

    func loadTicketScanResult() async -> TicketPDFScanResult? { snapshot.ticketScanResult }

    func saveTicketScanResult(_ result: TicketPDFScanResult?) async throws {
        snapshot.ticketScanResult = result
        try Self.persist(snapshot, to: fileURL)
    }

    func loadTravelerProfile() async -> TravelerProfile { snapshot.travelerProfile }

    func saveTravelerProfile(_ profile: TravelerProfile) async throws {
        snapshot.travelerProfile = profile
        try Self.persist(snapshot, to: fileURL)
    }

    func clearLongHaulData() async throws {
        snapshot = LongHaulCacheSnapshot()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func read(from url: URL) -> LongHaulCacheSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LongHaulCacheSnapshot.self, from: data)
    }

    private static func readLegacy(from url: URL) -> ActiveJourney? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(LegacyJourneySnapshot.self, from: data))?.journey
    }

    private static func persist(_ snapshot: LongHaulCacheSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}
