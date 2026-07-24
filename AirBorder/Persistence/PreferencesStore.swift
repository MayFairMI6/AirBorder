import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var accessibility: AccessibilityPreferences {
        didSet { save() }
    }
    @Published var cloudVisionOptIn: Bool {
        didSet { defaults.set(cloudVisionOptIn, forKey: Keys.cloudVisionOptIn) }
    }
    @Published var privateNotificationContent: Bool {
        didSet { defaults.set(privateNotificationContent, forKey: Keys.privateNotificationContent) }
    }
    @Published var journeyAlertsEnabled: Bool {
        didSet { defaults.set(journeyAlertsEnabled, forKey: Keys.journeyAlertsEnabled) }
    }
    @Published var selectedPlaceAlertsEnabled: Bool {
        didSet { defaults.set(selectedPlaceAlertsEnabled, forKey: Keys.selectedPlaceAlertsEnabled) }
    }
    @Published var personalizedPredictionsEnabled: Bool {
        didSet { defaults.set(personalizedPredictionsEnabled, forKey: Keys.personalizedPredictionsEnabled) }
    }
    @Published private(set) var appleCalendarReminderConsent: ReminderSyncConsent?
    @Published private(set) var appleCalendarReminderScopeID: String?
    @Published private(set) var appleCalendarReminderLastSyncAt: Date?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.accessibility),
           let stored = try? JSONDecoder().decode(AccessibilityPreferences.self, from: data) {
            accessibility = stored
        } else {
            accessibility = .default
        }
        cloudVisionOptIn = defaults.bool(forKey: Keys.cloudVisionOptIn)
        privateNotificationContent = defaults.object(forKey: Keys.privateNotificationContent) as? Bool ?? true
        journeyAlertsEnabled = defaults.object(forKey: Keys.journeyAlertsEnabled) as? Bool ?? true
        selectedPlaceAlertsEnabled = defaults.object(forKey: Keys.selectedPlaceAlertsEnabled) as? Bool ?? true
        personalizedPredictionsEnabled = defaults.object(forKey: Keys.personalizedPredictionsEnabled) as? Bool ?? true
        appleCalendarReminderConsent = defaults.data(forKey: Keys.appleCalendarReminderConsent)
            .flatMap { try? JSONDecoder().decode(ReminderSyncConsent.self, from: $0) }
        appleCalendarReminderScopeID = defaults.string(forKey: Keys.appleCalendarReminderScopeID)
        appleCalendarReminderLastSyncAt = defaults.object(forKey: Keys.appleCalendarReminderLastSyncAt) as? Date
    }

    func setAppleCalendarReminderConsent(_ consent: ReminderSyncConsent?) {
        appleCalendarReminderConsent = consent
        if let consent, let data = try? JSONEncoder().encode(consent) {
            defaults.set(data, forKey: Keys.appleCalendarReminderConsent)
        } else {
            defaults.removeObject(forKey: Keys.appleCalendarReminderConsent)
        }
    }

    func setAppleCalendarReminderScopeID(_ scopeID: String?) {
        appleCalendarReminderScopeID = scopeID
        if let scopeID {
            defaults.set(scopeID, forKey: Keys.appleCalendarReminderScopeID)
        } else {
            defaults.removeObject(forKey: Keys.appleCalendarReminderScopeID)
        }
    }

    func setAppleCalendarReminderLastSyncAt(_ date: Date?) {
        appleCalendarReminderLastSyncAt = date
        if let date {
            defaults.set(date, forKey: Keys.appleCalendarReminderLastSyncAt)
        } else {
            defaults.removeObject(forKey: Keys.appleCalendarReminderLastSyncAt)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accessibility) {
            defaults.set(data, forKey: Keys.accessibility)
        }
    }

    private enum Keys {
        static let accessibility = "accessibility-preferences-v1"
        static let cloudVisionOptIn = "cloud-vision-opt-in"
        static let privateNotificationContent = "private-notification-content"
        static let journeyAlertsEnabled = "journey-alerts-enabled"
        static let selectedPlaceAlertsEnabled = "selected-place-alerts-enabled"
        static let personalizedPredictionsEnabled = "personalized-predictions-enabled"
        static let appleCalendarReminderConsent = "apple-calendar-reminder-consent-v1"
        static let appleCalendarReminderScopeID = "apple-calendar-reminder-scope-v1"
        static let appleCalendarReminderLastSyncAt = "apple-calendar-reminder-last-sync-v1"
    }
}
