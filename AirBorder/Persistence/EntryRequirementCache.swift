import CryptoKit
import Foundation

protocol EntryRequirementCaching: Sendable {
    func assessment(for query: EntryRequirementQuery) async -> EntryAssessment?
    func save(_ assessment: EntryAssessment, for query: EntryRequirementQuery) async throws
    func clear() async throws
}

private struct EntryRequirementCacheRecord: Codable, Sendable {
    let assessment: EntryAssessment
    let storedAt: Date
}

private struct EntryRequirementCacheSnapshot: Codable, Sendable {
    var schemaVersion = 1
    var providerPolicyVersion = ProviderPolicyRegistry.version
    var records: [String: EntryRequirementCacheRecord] = [:]
}

/// Stores only a one-way fingerprint of the exact normalized query alongside
/// the provider result. An expired record remains available for transparent
/// display and provenance, but EntryAssessment's safety boundary prevents it
/// from supporting a landside or city recommendation.
actor EntryRequirementCache: EntryRequirementCaching {
    private let fileURL: URL
    private var snapshot: EntryRequirementCacheSnapshot

    init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AirportXRCompanion", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("entry-requirement-cache-v1.json")
        if let loaded = Self.read(from: fileURL),
           loaded.schemaVersion == 1,
           loaded.providerPolicyVersion == ProviderPolicyRegistry.version {
            snapshot = loaded
        } else {
            // A cache created under a different schema or provider policy
            // cannot regain authorization merely because its date is future.
            snapshot = EntryRequirementCacheSnapshot()
        }
    }

    func assessment(for query: EntryRequirementQuery) async -> EntryAssessment? {
        snapshot.records[Self.fingerprint(for: query)]?.assessment
    }

    func save(_ assessment: EntryAssessment, for query: EntryRequirementQuery) async throws {
        snapshot.records[Self.fingerprint(for: query)] = EntryRequirementCacheRecord(
            assessment: assessment,
            storedAt: Date()
        )
        snapshot.providerPolicyVersion = ProviderPolicyRegistry.version
        try Self.persist(snapshot, to: fileURL)
    }

    func clear() async throws {
        snapshot = EntryRequirementCacheSnapshot()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    static func fingerprint(for query: EntryRequirementQuery) -> String {
        let authorizations = query.declaredAuthorizations.map { authorization in
            [
                authorization.countryCode.uppercased(),
                authorization.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                authorization.expiresAt.map(dateToken) ?? "none"
            ].joined(separator: ":")
        }.sorted()
        let fields = [
            query.nationalityCountryCode.uppercased(),
            query.residenceCountryCode.uppercased(),
            query.passportType.rawValue,
            authorizations.joined(separator: ","),
            query.originCountryCode.uppercased(),
            query.transitCountryCode.uppercased(),
            query.onwardCountryCode.uppercased(),
            query.originAirportCode.uppercased(),
            query.transitArrivalAirportCode.uppercased(),
            query.onwardDepartureAirportCode.uppercased(),
            query.onwardDestinationAirportCode.uppercased(),
            dateToken(query.originDeparture),
            dateToken(query.arrival),
            dateToken(query.departure),
            dateToken(query.onwardArrival),
            query.originTimeZoneIdentifier,
            query.transitTimeZoneIdentifier,
            query.onwardTimeZoneIdentifier,
            String(query.plannedLandsideExit),
            query.luggage.rawValue,
            query.purpose.rawValue
        ]
        let digest = SHA256.hash(data: Data(fields.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func dateToken(_ date: Date) -> String {
        String(date.timeIntervalSince1970.bitPattern, radix: 16)
    }

    private static func read(from url: URL) -> EntryRequirementCacheSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(EntryRequirementCacheSnapshot.self, from: data)
    }

    private static func persist(_ snapshot: EntryRequirementCacheSnapshot, to url: URL) throws {
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

enum EntryRequirementRefreshPolicy: Sendable, Equatable {
    case refreshThenCache
    case cacheOnly
}

struct CachedEntryRequirementProvider: EntryRequirementProvider {
    let upstream: any EntryRequirementProvider
    let cache: any EntryRequirementCaching
    let refreshPolicy: EntryRequirementRefreshPolicy

    init(
        upstream: any EntryRequirementProvider,
        cache: any EntryRequirementCaching,
        refreshPolicy: EntryRequirementRefreshPolicy = .refreshThenCache
    ) {
        self.upstream = upstream
        self.cache = cache
        self.refreshPolicy = refreshPolicy
    }

    func assessment(for query: EntryRequirementQuery) async throws -> EntryAssessment {
        let existing = await cache.assessment(for: query)
        if refreshPolicy == .cacheOnly {
            guard let existing else {
                throw FlightAPIError.unavailable
            }
            return existing
        }

        do {
            let assessment = try await upstream.assessment(for: query)
            if let existing,
               existing.evidenceKind == .structuredProvider,
               assessment.evidenceKind != .structuredProvider {
                // A current structured result is stronger than a transient
                // discovery fallback. A stale structured record remains in the
                // protected cache for provenance but the fresh discovery result
                // is displayed; neither stale nor discovery evidence authorizes.
                return existing.isCurrent(at: Date()) ? existing : assessment
            }
            if assessment.evidenceKind != .informationalFallback {
                try? await cache.save(assessment, for: query)
            }
            return assessment
        } catch {
            if let existing {
                return existing
            }
            throw error
        }
    }
}
