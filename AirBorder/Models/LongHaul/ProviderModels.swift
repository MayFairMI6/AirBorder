import Foundation

enum ProviderCacheScope: String, Codable, Sendable {
    case none
    case memory
    case protectedLocal
    case versionedPersistent
    case licenseDependent
}

enum ProviderExpirySource: String, Codable, Sendable {
    case responseMetadata
    case sourceTimestamp
    case feedVersion
    case offerTimestamp
    case providerContract
    case none
}

/// A provider contract must name the exact model use it permits. There is no
/// entry/visa-rule purpose: those rules are never learned or inferred by the
/// personalization model.
enum ProviderTrainingPurpose: String, Codable, CaseIterable, Hashable, Sendable {
    case flightDelayOutcome
    case walkingDurationOutcome
    case transitDurationOutcome
    case recommendationFeedback
}

struct ProviderPolicy: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let cacheScope: ProviderCacheScope
    let expirySource: ProviderExpirySource
    let persistentStorageAllowed: Bool
    let redistributionAllowed: Bool
    let permittedTrainingPurposes: Set<ProviderTrainingPurpose>
    let attribution: String
    let licenseURL: URL?

    var trainingAllowed: Bool { !permittedTrainingPurposes.isEmpty }

    func permitsTraining(for purpose: ProviderTrainingPurpose) -> Bool {
        permittedTrainingPurposes.contains(purpose)
    }
}

/// A narrow, provenance-bound authorization produced only after both the
/// bundled policy registry and the normalized provider response agree.
struct ProviderTrainingAuthorization: Hashable, Sendable {
    let adapterProviderID: String
    let policyID: String
    let policyVersion: String
    let purpose: ProviderTrainingPurpose
}

protocol ProviderPolicyResolving: Sendable {
    func trainingAuthorization(
        adapterProviderID: String,
        source: ProviderMetadata,
        purpose: ProviderTrainingPurpose
    ) -> ProviderTrainingAuthorization?
}

struct ProviderPolicyCatalog: ProviderPolicyResolving, Sendable {
    let version: String
    let policies: [String: ProviderPolicy]

    static let current = ProviderPolicyCatalog(
        version: ProviderPolicyRegistry.version,
        policies: ProviderPolicyRegistry.policies
    )

    func trainingAuthorization(
        adapterProviderID: String,
        source: ProviderMetadata,
        purpose: ProviderTrainingPurpose
    ) -> ProviderTrainingAuthorization? {
        guard source.isLive,
              !source.isDemo,
              source.providerTrainingAllowed == true,
              source.providerTrainingPurposes.contains(purpose),
              let policyID = source.providerPolicyID,
              source.providerPolicyVersion == version,
              let policy = policies[policyID],
              policy.permitsTraining(for: purpose) else {
            return nil
        }

        return ProviderTrainingAuthorization(
            adapterProviderID: adapterProviderID,
            policyID: policyID,
            policyVersion: version,
            purpose: purpose
        )
    }
}

enum ProviderPolicyRegistry {
    static let version = "provider-policy-2026-07-14-v3"

    static let policies: [String: ProviderPolicy] = [
        "facility-registry": ProviderPolicy(id: "facility-registry", cacheScope: .versionedPersistent, expirySource: .feedVersion, persistentStorageAllowed: true, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "Official airport/operator registry", licenseURL: nil),
        "gtfs-static": ProviderPolicy(id: "gtfs-static", cacheScope: .versionedPersistent, expirySource: .feedVersion, persistentStorageAllowed: true, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "Transit agency GTFS", licenseURL: URL(string: "https://gtfs.org/documentation/schedule/reference/")),
        "gtfs-realtime": ProviderPolicy(id: "gtfs-realtime", cacheScope: .memory, expirySource: .sourceTimestamp, persistentStorageAllowed: false, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "Transit agency GTFS-Realtime", licenseURL: URL(string: "https://gtfs.org/documentation/realtime/reference/")),
        "weatherkit": ProviderPolicy(id: "weatherkit", cacheScope: .memory, expirySource: .responseMetadata, persistentStorageAllowed: false, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "Apple Weather", licenseURL: URL(string: "https://developer.apple.com/weatherkit/")),
        "hotel-offers": ProviderPolicy(id: "hotel-offers", cacheScope: .memory, expirySource: .offerTimestamp, persistentStorageAllowed: false, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "Availability provider", licenseURL: nil),
        "entry-requirements": ProviderPolicy(id: "entry-requirements", cacheScope: .protectedLocal, expirySource: .responseMetadata, persistentStorageAllowed: true, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "Requirement provider plus official verification", licenseURL: nil),
        "sherpa-entry": ProviderPolicy(id: "sherpa-entry", cacheScope: .protectedLocal, expirySource: .responseMetadata, persistentStorageAllowed: true, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "Sherpa Requirements API plus official verification", licenseURL: URL(string: "https://docs.joinsherpa.io/requirements-api/index.html")),
        "timatic-entry": ProviderPolicy(id: "timatic-entry", cacheScope: .protectedLocal, expirySource: .responseMetadata, persistentStorageAllowed: true, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "IATA Timatic contract adapter plus official verification", licenseURL: URL(string: "https://www.iata.org/en/services/compliance/timatic/autocheck/")),
        "gemini-entry-discovery": ProviderPolicy(id: "gemini-entry-discovery", cacheScope: .protectedLocal, expirySource: .responseMetadata, persistentStorageAllowed: true, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "Gemini Google Search discovery; official-domain links only", licenseURL: URL(string: "https://ai.google.dev/gemini-api/docs/google-search")),
        "workersAIExplanation": ProviderPolicy(id: "workersAIExplanation", cacheScope: .none, expirySource: .none, persistentStorageAllowed: false, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "Cloudflare Workers AI grounded explanation ordering", licenseURL: URL(string: "https://developers.cloudflare.com/workers-ai/")),
        "google-places": ProviderPolicy(id: "google-places", cacheScope: .memory, expirySource: .providerContract, persistentStorageAllowed: false, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "Google Places", licenseURL: URL(string: "https://developers.google.com/maps/documentation/places/web-service/policies")),
        "flight-data": ProviderPolicy(id: "flight-data", cacheScope: .licenseDependent, expirySource: .providerContract, persistentStorageAllowed: false, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "Generic licensed flight provider", licenseURL: nil),
        "flightaware": ProviderPolicy(id: "flightaware", cacheScope: .licenseDependent, expirySource: .providerContract, persistentStorageAllowed: false, redistributionAllowed: false, permittedTrainingPurposes: [], attribution: "FlightAware AeroAPI", licenseURL: nil),
        "user-outcomes": ProviderPolicy(id: "user-outcomes", cacheScope: .protectedLocal, expirySource: .none, persistentStorageAllowed: true, redistributionAllowed: false, permittedTrainingPurposes: Set(ProviderTrainingPurpose.allCases), attribution: "User-owned outcomes", licenseURL: nil)
    ]
}

protocol EntryRequirementProvider: Sendable {
    func assessment(for query: EntryRequirementQuery) async throws -> EntryAssessment
}

protocol AirportFacilityProvider: Sendable {
    func facilities(at airport: Airport, on date: Date) async throws -> [AirportFacilityRecord]
}

protocol PlaceProvider: Sendable {
    func places(for context: PlaceSearchContext) async throws -> [LayoverPlace]
}

protocol AccommodationProvider: Sendable {
    func offers(for context: PlaceSearchContext, checkIn: Date, checkOut: Date) async throws -> [AccommodationOffer]
}

protocol QueueTimeProvider: Sendable {
    func queueEstimate(airport: Airport, terminal: String?, kind: PlanSegmentKind, at date: Date) async throws -> SourcedMetric<EstimateDistribution>?
}

protocol WeatherContextProvider: Sendable {
    func weatherSummary(airport: Airport, latitude: Double, longitude: Double, at date: Date) async throws -> SourcedMetric<String>?
}

protocol LayoverContextRepository: Sendable {
    func context(for layover: LayoverContext, profile: TravelerProfile, at date: Date) async -> LayoverDataSnapshot
}

protocol LayoverRecommendationEngine: Sendable {
    func assess(
        itinerary: Itinerary,
        layover: LayoverContext,
        candidate: PlanCandidate,
        profile: TravelerProfile,
        snapshotRevision: String,
        seed: UInt64?,
        now: Date
    ) -> FeasibilityAssessment
}

struct LayoverDataSnapshot: Sendable {
    let facilities: [AirportFacilityRecord]
    let places: [LayoverPlace]
    let entryAssessment: EntryAssessment?
    let revision: String
}
