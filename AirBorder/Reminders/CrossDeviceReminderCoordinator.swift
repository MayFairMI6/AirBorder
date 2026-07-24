import Foundation

enum AppleCalendarReminderRuntimeState: Equatable, Sendable {
    case off
    case permissionRequired
    case permissionDenied
    case insufficientAccess
    case syncing
    case synced(intentCount: Int, at: Date)
    case failed(String)

    var title: String {
        switch self {
        case .off:
            "Off"
        case .permissionRequired:
            "Calendar permission required"
        case .permissionDenied:
            "Calendar access denied"
        case .insufficientAccess:
            "Full Calendar access required"
        case .syncing:
            "Syncing"
        case let .synced(intentCount, _):
            intentCount == 1 ? "1 action synced" : "\(intentCount) actions synced"
        case .failed:
            "Sync needs attention"
        }
    }

    var detail: String? {
        switch self {
        case .off:
            nil
        case .permissionRequired:
            "Turn on Calendar sync again to open Apple's permission prompt. Automatic refresh never opens it."
        case .permissionDenied:
            "Allow full Calendar access in Settings, then retry. No calendar records were changed."
        case .insufficientAccess:
            "Write-only access cannot safely find, update, and remove Airport XR Companion events."
        case .syncing:
            "Updating only Airport XR Companion action events."
        case let .synced(intentCount, at):
            intentCount == 0
                ? "No eligible future sourced actions are available in the current itinerary. Last checked \(at.formatted(date: .omitted, time: .shortened))."
                : "Last synced \(at.formatted(date: .omitted, time: .shortened))."
        case let .failed(message):
            message
        }
    }

    var isBusy: Bool {
        if case .syncing = self { return true }
        return false
    }
}

/// Owns the runtime consent and synchronization boundary for Apple Calendar.
/// Routine refresh is fail-closed: it never requests system permission and it
/// never invents a reminder time when the planning input is missing.
@MainActor
final class CrossDeviceReminderCoordinator: ObservableObject {
    @Published private(set) var appleCalendarState: AppleCalendarReminderRuntimeState
    @Published private(set) var isAppleCalendarEnabled: Bool

    private let appleCalendar: any CrossDeviceReminderProviding
    private let planner: CrossDeviceReminderPlanner
    private let preferences: PreferencesStore
    private let now: @Sendable () -> Date

    init(
        appleCalendar: any CrossDeviceReminderProviding = AppleCalendarReminderAdapter(),
        planner: CrossDeviceReminderPlanner = CrossDeviceReminderPlanner(),
        preferences: PreferencesStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.appleCalendar = appleCalendar
        self.planner = planner
        self.preferences = preferences
        self.now = now
        let enabled = preferences.appleCalendarReminderConsent?.authorizes(
            .appleCalendar,
            revision: CrossDeviceReminderPolicy.appleConsentRevision
        ) == true
        isAppleCalendarEnabled = enabled
        appleCalendarState = enabled ? .permissionRequired : .off
    }

    /// The only runtime entry point that may present Apple's permission UI.
    /// It must be called directly from the person's Calendar opt-in action.
    func enableAppleCalendar(using input: CrossDeviceReminderPlanningInput?) async {
        guard !appleCalendarState.isBusy else { return }
        appleCalendarState = .syncing

        let consent = ReminderSyncConsent(
            destination: .appleCalendar,
            revision: CrossDeviceReminderPolicy.appleConsentRevision,
            grantedAt: now(),
            revokedAt: nil
        )

        do {
            let currentAuthorization = await appleCalendar.authorizationState()
            let granted: Bool
            if currentAuthorization == .authorized {
                granted = true
            } else {
                granted = try await appleCalendar.requestAuthorization(consent: consent)
            }
            guard granted else {
                preferences.setAppleCalendarReminderConsent(revoked(consent))
                isAppleCalendarEnabled = false
                appleCalendarState = .permissionDenied
                return
            }

            preferences.setAppleCalendarReminderConsent(consent)
            isAppleCalendarEnabled = true
            await synchronize(input, consent: consent)
        } catch {
            preferences.setAppleCalendarReminderConsent(revoked(consent))
            isAppleCalendarEnabled = false
            appleCalendarState = state(for: error)
        }
    }

    /// Idempotent automatic refresh. This checks existing permission but never
    /// calls requestAuthorization, so background app work cannot surprise the
    /// person with a system prompt.
    func syncIfEnabled(using input: CrossDeviceReminderPlanningInput?) async {
        guard !appleCalendarState.isBusy,
              let consent = preferences.appleCalendarReminderConsent,
              consent.authorizes(.appleCalendar, revision: CrossDeviceReminderPolicy.appleConsentRevision) else {
            if !isAppleCalendarEnabled { appleCalendarState = .off }
            return
        }

        isAppleCalendarEnabled = true
        switch await appleCalendar.authorizationState() {
        case .authorized:
            appleCalendarState = .syncing
            await synchronize(input, consent: consent)
        case .notDetermined:
            appleCalendarState = .permissionRequired
        case .denied:
            appleCalendarState = .permissionDenied
        case .insufficientAccess:
            appleCalendarState = .insufficientAccess
        }
    }

    /// Removes app-managed events before revoking local consent. If system
    /// permission has already been removed, EventKit cannot perform cleanup;
    /// the local consent is still revoked and the UI explains the limitation.
    func disableAppleCalendar() async {
        guard !appleCalendarState.isBusy else { return }
        guard let consent = preferences.appleCalendarReminderConsent,
              consent.authorizes(.appleCalendar, revision: CrossDeviceReminderPolicy.appleConsentRevision) else {
            preferences.setAppleCalendarReminderConsent(nil)
            isAppleCalendarEnabled = false
            appleCalendarState = .off
            return
        }

        appleCalendarState = .syncing
        var cleanupError: Error?
        if let scopeID = preferences.appleCalendarReminderScopeID {
            do {
                _ = try await appleCalendar.deleteAll(scopeID: scopeID, consent: consent)
                preferences.setAppleCalendarReminderScopeID(nil)
            } catch {
                cleanupError = error
            }
        }

        preferences.setAppleCalendarReminderConsent(revoked(consent))
        isAppleCalendarEnabled = false
        if cleanupError == nil {
            appleCalendarState = .off
        } else {
            appleCalendarState = .failed(
                "Calendar sync is off, but existing app-managed events could not be removed because Calendar access is unavailable. Remove them in Calendar or restore access and retry."
            )
        }
    }

    func retry(using input: CrossDeviceReminderPlanningInput?) async {
        await syncIfEnabled(using: input)
    }

    private func synchronize(
        _ input: CrossDeviceReminderPlanningInput?,
        consent: ReminderSyncConsent
    ) async {
        do {
            guard let input else {
                if let previousScopeID = preferences.appleCalendarReminderScopeID {
                    _ = try await appleCalendar.deleteAll(scopeID: previousScopeID, consent: consent)
                    preferences.setAppleCalendarReminderScopeID(nil)
                }
                recordSuccessfulSync(intentCount: 0)
                return
            }

            let scopeID = input.itinerary.id.uuidString.lowercased()
            if let previousScopeID = preferences.appleCalendarReminderScopeID,
               previousScopeID != scopeID {
                _ = try await appleCalendar.deleteAll(scopeID: previousScopeID, consent: consent)
                preferences.setAppleCalendarReminderScopeID(nil)
            }

            let intents = planner.intents(from: input, now: now())
            let result = try await appleCalendar.sync(intents, scopeID: scopeID, consent: consent)
            preferences.setAppleCalendarReminderScopeID(scopeID)
            recordSuccessfulSync(intentCount: result.upsertedIntentIDs.count)
        } catch {
            appleCalendarState = state(for: error)
        }
    }

    private func recordSuccessfulSync(intentCount: Int) {
        let syncedAt = now()
        preferences.setAppleCalendarReminderLastSyncAt(syncedAt)
        appleCalendarState = .synced(intentCount: intentCount, at: syncedAt)
    }

    private func revoked(_ consent: ReminderSyncConsent) -> ReminderSyncConsent {
        ReminderSyncConsent(
            destination: consent.destination,
            revision: consent.revision,
            grantedAt: consent.grantedAt,
            revokedAt: now()
        )
    }

    private func state(for error: Error) -> AppleCalendarReminderRuntimeState {
        switch error as? CrossDeviceReminderError {
        case .authorizationRequired:
            .permissionRequired
        case .calendarUnavailable:
            .failed("No writable default calendar is available. Choose a writable calendar account and retry.")
        case .consentRequired:
            .off
        default:
            .failed("Calendar actions could not be synchronized. Your local journey and safety recommendations are unchanged.")
        }
    }
}
