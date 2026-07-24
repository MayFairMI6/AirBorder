import Foundation

/// Versioned constants used by reminder synchronization. Action times are never
/// shifted by a hidden lead-time; each intent fires at a time already derived by
/// the itinerary or safety engine.
enum CrossDeviceReminderPolicy {
    static let version = "cross-device-reminders-2026-07-14-v1"
    static let googleConsentRevision = "google-tasks-consent-2026-07-14-v1"
    static let appleConsentRevision = "apple-calendar-consent-2026-07-14-v1"
    static let googleTasksOAuthScope = "https://www.googleapis.com/auth/tasks"

    /// EventKit requires an end after the start for a timed event. One minute is
    /// an action-marker duration, not a travel, boarding, or safety estimate.
    static let calendarActionMarkerDuration: TimeInterval = 60

    /// Used only to recover an app-managed event if EventKit changes its opaque
    /// identifier after the person moves the event to another calendar.
    static let eventLookupTolerance: TimeInterval = 1
    static let maximumProxyResponseBytes = 256_000
    static let proxyRequestTimeout: TimeInterval = 15
}

enum CrossDeviceReminderDestination: String, Codable, Hashable, Sendable {
    case appleCalendar
    case googleTasks
}

enum CrossDeviceReminderKind: String, Codable, Hashable, Sendable {
    case goToGate
    case gateClose
    case latestReturn
}

struct CrossDeviceReminderIntent: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let scopeID: String
    let kind: CrossDeviceReminderKind
    let title: String
    let body: String
    let actionAt: Date
    let timeZoneIdentifier: String?
    let deepLink: URL
    let sourceRevision: Int
    let derivation: [DerivationStep]
}

struct LatestReturnReminderSource: Codable, Hashable, Sendable {
    let layoverID: String
    let candidateTitle: String
    let assessment: FeasibilityAssessment
    /// True only when every safety-critical source used by the assessment has
    /// an explicit, current expiry and sensible observation/receipt ordering.
    let criticalInputsAreCurrent: Bool
}

extension SourcedMetric {
    /// External actions require stronger freshness than an in-app historical
    /// display: a missing expiry is unknown, never indefinitely current.
    func isEligibleForExternalAction(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return observedAt <= receivedAt
            && receivedAt <= date
            && receivedAt < expiresAt
            && date < expiresAt
    }
}

struct CrossDeviceReminderPlanningInput: Sendable {
    let itinerary: Itinerary
    let activeLegID: UUID?
    let journeyAssessment: JourneyAssessment?
    let latestReturn: LatestReturnReminderSource?

    init(
        itinerary: Itinerary,
        activeLegID: UUID? = nil,
        journeyAssessment: JourneyAssessment? = nil,
        latestReturn: LatestReturnReminderSource? = nil
    ) {
        self.itinerary = itinerary
        self.activeLegID = activeLegID
        self.journeyAssessment = journeyAssessment
        self.latestReturn = latestReturn
    }
}

struct ReminderSyncConsent: Codable, Hashable, Sendable {
    let destination: CrossDeviceReminderDestination
    let revision: String
    let grantedAt: Date
    let revokedAt: Date?

    func authorizes(_ expectedDestination: CrossDeviceReminderDestination, revision expectedRevision: String) -> Bool {
        destination == expectedDestination && revision == expectedRevision && revokedAt == nil
    }
}

enum ReminderAuthorizationState: String, Codable, Hashable, Sendable {
    case notDetermined
    case authorized
    case denied
    case insufficientAccess
}

struct ReminderSyncResult: Codable, Hashable, Sendable {
    let destination: CrossDeviceReminderDestination
    let upsertedIntentIDs: [String]
    let removedIntentIDs: [String]
    let limitations: [String]
}

enum CrossDeviceReminderError: Error, Equatable {
    case consentRequired
    case authorizationRequired
    case invalidScope
    case missingTimeZone(intentID: String)
    case invalidResponse
    case responseTooLarge
    case authenticationFailed
    case calendarUnavailable
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int)
}

protocol CrossDeviceReminderProviding: Sendable {
    var destination: CrossDeviceReminderDestination { get }
    func authorizationState() async -> ReminderAuthorizationState
    func requestAuthorization(consent: ReminderSyncConsent) async throws -> Bool
    func sync(
        _ intents: [CrossDeviceReminderIntent],
        scopeID: String,
        consent: ReminderSyncConsent
    ) async throws -> ReminderSyncResult
    func deleteAll(scopeID: String, consent: ReminderSyncConsent) async throws -> ReminderSyncResult
}

protocol GoogleOAuthAccessTokenProviding: Sendable {
    func authorizationState(scopes: Set<String>) async -> ReminderAuthorizationState

    /// Implementations present Google's consent UI from an explicit user action.
    func requestAuthorization(scopes: Set<String>) async throws -> Bool

    /// Implementations use an interactive Google OAuth flow and return a
    /// short-lived access token for the exact requested scopes. Refresh tokens
    /// belong in Keychain/Google Sign-In storage, never source, UserDefaults, or logs.
    func accessToken(scopes: Set<String>) async throws -> String
}
