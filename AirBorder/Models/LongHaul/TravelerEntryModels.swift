import Foundation

enum PassportType: String, Codable, CaseIterable, Identifiable, Sendable {
    case ordinary
    case diplomatic
    case official
    case refugeeTravelDocument
    case other
    var id: String { rawValue }
}

enum TravelPurpose: String, Codable, CaseIterable, Identifiable, Sendable {
    case transit
    case tourism
    case business
    case study
    case work
    case other
    var id: String { rawValue }
}

enum LuggagePlan: String, Codable, CaseIterable, Identifiable, Sendable {
    case cabinOnly
    case checkedThrough
    case collectAndRecheck
    case unknown
    var id: String { rawValue }
}

enum BudgetPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case economy
    case moderate
    case flexible
    var id: String { rawValue }
}

enum RecoveryPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case maximizeRest
    case balance
    case maximizeExploration
    var id: String { rawValue }
}

/// A deliberately simple, user-controlled starting point for route timing.
/// It can be refined by the existing on-device completed-route learning, but
/// the user remains able to see and change the assumption at any time.
enum WalkingPacePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case slower
    case typical
    case faster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slower: "Allow extra walking time"
        case .typical: "Typical walking pace"
        case .faster: "Faster walking pace"
        }
    }

    /// Applies only to walking-related itinerary segments. Border, baggage,
    /// check-in, and security estimates must never be shortened by this choice.
    var walkingMultiplier: Double {
        switch self {
        case .slower: 1.25
        case .typical: 1
        case .faster: 0.9
        }
    }
}

struct DeclaredTravelAuthorization: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var countryCode: String
    var kind: String
    var expiresAt: Date?

    init(id: UUID = UUID(), countryCode: String, kind: String, expiresAt: Date? = nil) {
        self.id = id
        self.countryCode = countryCode
        self.kind = kind
        self.expiresAt = expiresAt
    }
}

struct TravelerProfile: Codable, Hashable, Sendable {
    var nationalityCountryCode: String
    var residenceCountryCode: String
    var passportType: PassportType
    var declaredAuthorizations: [DeclaredTravelAuthorization]
    var purpose: TravelPurpose
    var luggage: LuggagePlan
    var budget: BudgetPreference
    var recoveryPreference: RecoveryPreference
    var walkingPace: WalkingPacePreference = .typical
    var accessibilityNeeds: String
    var hasConfirmedOfficialEntryRules: Bool
    var anonymousSharingConsent: Bool

    static let incomplete = TravelerProfile(
        nationalityCountryCode: "",
        residenceCountryCode: "",
        passportType: .ordinary,
        declaredAuthorizations: [],
        purpose: .transit,
        luggage: .unknown,
        budget: .moderate,
        recoveryPreference: .balance,
        accessibilityNeeds: "",
        hasConfirmedOfficialEntryRules: false,
        anonymousSharingConsent: false
    )

    var hasMinimumEntryFacts: Bool {
        nationalityCountryCode.count == 2 && residenceCountryCode.count == 2
    }

    static let minimalDemo = TravelerProfile(
        nationalityCountryCode: "US",
        residenceCountryCode: "US",
        passportType: .ordinary,
        declaredAuthorizations: [],
        purpose: .transit,
        luggage: .checkedThrough,
        budget: .moderate,
        recoveryPreference: .balance,
        accessibilityNeeds: "",
        hasConfirmedOfficialEntryRules: false,
        anonymousSharingConsent: false
    )
}

struct EntryRequirementQuery: Codable, Hashable, Sendable {
    let nationalityCountryCode: String
    let residenceCountryCode: String
    let passportType: PassportType
    let declaredAuthorizations: [DeclaredTravelAuthorization]
    let originCountryCode: String
    let transitCountryCode: String
    let onwardCountryCode: String
    let originAirportCode: String
    let transitArrivalAirportCode: String
    let onwardDepartureAirportCode: String
    let onwardDestinationAirportCode: String
    let originDeparture: Date
    let arrival: Date
    let departure: Date
    let onwardArrival: Date
    let originTimeZoneIdentifier: String
    let transitTimeZoneIdentifier: String
    let onwardTimeZoneIdentifier: String
    let plannedLandsideExit: Bool
    let luggage: LuggagePlan
    let purpose: TravelPurpose
}

enum EntryAssessmentStatus: String, Codable, CaseIterable, Sendable {
    case authorizationNotIndicated
    case authorizationRequired
    case conditional
    case cannotDetermine

    var title: String {
        switch self {
        case .authorizationNotIndicated: "Authorization not indicated"
        case .authorizationRequired: "Authorization may be required"
        case .conditional: "Conditional"
        case .cannotDetermine: "More info needed"
        }
    }
}

enum EntryEvidenceKind: String, Codable, CaseIterable, Sendable {
    /// A contract-backed requirements provider returned a normalized result.
    /// The traveler must still confirm the result through an official source.
    case structuredProvider

    /// Search or an AI tool found links on a deployment-controlled allowlist of
    /// official government domains. This evidence can never authorize entry.
    case officialSourceDiscovery

    /// A bundled link or other non-personalized informational fallback.
    case informationalFallback

    var title: String {
        switch self {
        case .structuredProvider: "Current travel-rule check"
        case .officialSourceDiscovery: "Official links found"
        case .informationalFallback: "General guidance"
        }
    }

    var canSupportLandsideRecommendation: Bool {
        self == .structuredProvider
    }
}

struct EntryAssessment: Codable, Hashable, Sendable {
    let status: EntryAssessmentStatus
    let summary: String
    let provider: String
    let providerChain: [String]
    let evidenceKind: EntryEvidenceKind
    let sourceRecordID: String
    let observedAt: Date
    let receivedAt: Date
    let expiresAt: Date
    let officialVerificationURLs: [URL]
    let isDemo: Bool

    init(
        status: EntryAssessmentStatus,
        summary: String,
        provider: String,
        providerChain: [String] = [],
        evidenceKind: EntryEvidenceKind = .structuredProvider,
        sourceRecordID: String,
        observedAt: Date,
        receivedAt: Date,
        expiresAt: Date,
        officialVerificationURLs: [URL],
        isDemo: Bool
    ) {
        self.status = status
        self.summary = summary
        self.provider = provider
        self.providerChain = providerChain.isEmpty ? [provider] : providerChain
        self.evidenceKind = evidenceKind
        self.sourceRecordID = sourceRecordID
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.expiresAt = expiresAt
        self.officialVerificationURLs = officialVerificationURLs
        self.isDemo = isDemo
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case summary
        case provider
        case providerChain
        case evidenceKind
        case sourceRecordID
        case observedAt
        case receivedAt
        case expiresAt
        case officialVerificationURLs
        case isDemo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(EntryAssessmentStatus.self, forKey: .status)
        summary = try container.decode(String.self, forKey: .summary)
        provider = try container.decode(String.self, forKey: .provider)
        providerChain = try container.decodeIfPresent([String].self, forKey: .providerChain) ?? [provider]
        // Older protected cache records predate the evidence boundary. Treat
        // them as informational until they are refreshed by a current proxy.
        evidenceKind = try container.decodeIfPresent(EntryEvidenceKind.self, forKey: .evidenceKind) ?? .informationalFallback
        sourceRecordID = try container.decode(String.self, forKey: .sourceRecordID)
        observedAt = try container.decode(Date.self, forKey: .observedAt)
        receivedAt = try container.decode(Date.self, forKey: .receivedAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        officialVerificationURLs = try container.decode([URL].self, forKey: .officialVerificationURLs)
        isDemo = try container.decode(Bool.self, forKey: .isDemo)
    }

    func isCurrent(at date: Date) -> Bool { expiresAt > date }

    func canSupportLandsideRecommendation(profile: TravelerProfile, at date: Date) -> Bool {
        isCurrent(at: date)
            && evidenceKind.canSupportLandsideRecommendation
            && status == .authorizationNotIndicated
            && profile.hasConfirmedOfficialEntryRules
            && !officialVerificationURLs.isEmpty
    }
}
