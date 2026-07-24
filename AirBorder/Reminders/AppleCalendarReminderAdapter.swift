import EventKit
import Foundation

struct AppleCalendarBinding: Codable, Hashable, Sendable {
    let reminderID: String
    let eventIdentifier: String
    let actionAt: Date
}

protocol AppleCalendarEventStoring: Sendable {
    func authorizationState() async -> ReminderAuthorizationState
    func requestFullAccess() async throws -> Bool
    func upsert(
        _ intent: CrossDeviceReminderIntent,
        existing: AppleCalendarBinding?
    ) async throws -> AppleCalendarBinding
    func delete(_ binding: AppleCalendarBinding) async throws
}

protocol AppleCalendarSyncStateStoring: Sendable {
    func bindings(scopeID: String) async -> [String: AppleCalendarBinding]
    func save(_ bindings: [String: AppleCalendarBinding], scopeID: String) async throws
}

actor UserDefaultsAppleCalendarSyncStateStore: AppleCalendarSyncStateStoring {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        suiteName: String? = nil,
        storageKey: String = "AirportXR.AppleCalendarBindings.v1"
    ) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.storageKey = storageKey
    }

    func bindings(scopeID: String) -> [String: AppleCalendarBinding] {
        load()[scopeID] ?? [:]
    }

    func save(_ bindings: [String: AppleCalendarBinding], scopeID: String) throws {
        var all = load()
        if bindings.isEmpty {
            all.removeValue(forKey: scopeID)
        } else {
            all[scopeID] = bindings
        }
        defaults.set(try JSONEncoder().encode(all), forKey: storageKey)
    }

    private func load() -> [String: [String: AppleCalendarBinding]] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: AppleCalendarBinding]].self, from: data)) ?? [:]
    }
}

actor EventKitCalendarEventStore: AppleCalendarEventStoring {
    private let eventStore = EKEventStore()

    func authorizationState() -> ReminderAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            .notDetermined
        case .fullAccess, .authorized:
            .authorized
        case .writeOnly:
            // Full access is intentionally required for idempotent lookup,
            // update, and deletion of app-managed events.
            .insufficientAccess
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func upsert(
        _ intent: CrossDeviceReminderIntent,
        existing: AppleCalendarBinding?
    ) throws -> AppleCalendarBinding {
        let markerURL = Self.markerURL(reminderID: intent.id)
        let matches = matchingEvents(reminderID: intent.id, actionAt: intent.actionAt)
        let mappedEvent = existing
            .flatMap { eventStore.event(withIdentifier: $0.eventIdentifier) }
            .flatMap { $0.url == markerURL ? $0 : nil }
        let event = mappedEvent ?? matches.first ?? EKEvent(eventStore: eventStore)

        if event.calendar == nil {
            event.calendar = eventStore.defaultCalendarForNewEvents
        }
        guard event.calendar != nil else { throw CrossDeviceReminderError.calendarUnavailable }

        event.title = intent.title
        event.notes = "\(intent.body)\nOpen in Airport XR Companion: \(intent.deepLink.absoluteString)\nPolicy: \(CrossDeviceReminderPolicy.version)"
        event.url = markerURL
        event.startDate = intent.actionAt
        event.endDate = intent.actionAt.addingTimeInterval(CrossDeviceReminderPolicy.calendarActionMarkerDuration)
        event.timeZone = intent.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        event.availability = .free
        event.alarms?.forEach(event.removeAlarm)
        event.addAlarm(EKAlarm(absoluteDate: intent.actionAt))
        try eventStore.save(event, span: .thisEvent)

        // A prior interrupted sync can leave duplicate managed events. The
        // stable marker makes it safe to consolidate only this app's records.
        for duplicate in matches where duplicate.eventIdentifier != event.eventIdentifier {
            try eventStore.remove(duplicate, span: .thisEvent)
        }

        guard let identifier = event.eventIdentifier else {
            throw CrossDeviceReminderError.invalidResponse
        }
        return AppleCalendarBinding(
            reminderID: intent.id,
            eventIdentifier: identifier,
            actionAt: intent.actionAt
        )
    }

    func delete(_ binding: AppleCalendarBinding) throws {
        if let event = eventStore.event(withIdentifier: binding.eventIdentifier),
           event.url == Self.markerURL(reminderID: binding.reminderID) {
            try eventStore.remove(event, span: .thisEvent)
            return
        }
        for event in matchingEvents(reminderID: binding.reminderID, actionAt: binding.actionAt) {
            try eventStore.remove(event, span: .thisEvent)
        }
    }

    private func matchingEvents(reminderID: String, actionAt: Date) -> [EKEvent] {
        let tolerance = CrossDeviceReminderPolicy.eventLookupTolerance
        let markerURL = Self.markerURL(reminderID: reminderID)
        let predicate = eventStore.predicateForEvents(
            withStart: actionAt.addingTimeInterval(-tolerance),
            end: actionAt.addingTimeInterval(CrossDeviceReminderPolicy.calendarActionMarkerDuration + tolerance),
            calendars: nil
        )
        return eventStore.events(matching: predicate)
            .filter { $0.url == markerURL }
            .sorted { ($0.eventIdentifier ?? "") < ($1.eventIdentifier ?? "") }
    }

    private static func markerURL(reminderID: String) -> URL {
        URL(string: "airportxr://reminders/\(reminderID)")!
    }
}

actor AppleCalendarReminderAdapter: CrossDeviceReminderProviding {
    nonisolated let destination = CrossDeviceReminderDestination.appleCalendar

    private let eventStore: any AppleCalendarEventStoring
    private let stateStore: any AppleCalendarSyncStateStoring

    init(
        eventStore: any AppleCalendarEventStoring = EventKitCalendarEventStore(),
        stateStore: any AppleCalendarSyncStateStoring = UserDefaultsAppleCalendarSyncStateStore()
    ) {
        self.eventStore = eventStore
        self.stateStore = stateStore
    }

    func authorizationState() async -> ReminderAuthorizationState {
        await eventStore.authorizationState()
    }

    /// Call only from a person's explicit Apple Calendar opt-in action. Routine
    /// automatic sync never invokes the system permission prompt.
    func requestAuthorization(consent: ReminderSyncConsent) async throws -> Bool {
        guard consent.authorizes(.appleCalendar, revision: CrossDeviceReminderPolicy.appleConsentRevision) else {
            throw CrossDeviceReminderError.consentRequired
        }
        return try await eventStore.requestFullAccess()
    }

    func sync(
        _ intents: [CrossDeviceReminderIntent],
        scopeID: String,
        consent: ReminderSyncConsent
    ) async throws -> ReminderSyncResult {
        try requireConsent(consent)
        guard await eventStore.authorizationState() == .authorized else {
            throw CrossDeviceReminderError.authorizationRequired
        }
        guard intents.allSatisfy({ $0.scopeID == scopeID }) else {
            throw CrossDeviceReminderError.invalidScope
        }

        var bindings = await stateStore.bindings(scopeID: scopeID)
        let desiredIDs = Set(intents.map(\.id))
        let staleIDs = bindings.keys.filter { !desiredIDs.contains($0) }.sorted()
        for reminderID in staleIDs {
            guard let binding = bindings.removeValue(forKey: reminderID) else { continue }
            try await eventStore.delete(binding)
        }

        for intent in intents.sorted(by: { $0.id < $1.id }) {
            bindings[intent.id] = try await eventStore.upsert(intent, existing: bindings[intent.id])
        }
        try await stateStore.save(bindings, scopeID: scopeID)

        return ReminderSyncResult(
            destination: destination,
            upsertedIntentIDs: desiredIDs.sorted(),
            removedIntentIDs: staleIDs,
            limitations: [
                "Cross-device delivery depends on the calendar account selected on this device being synchronized to the person's other devices."
            ]
        )
    }

    func deleteAll(scopeID: String, consent: ReminderSyncConsent) async throws -> ReminderSyncResult {
        try requireConsent(consent)
        guard await eventStore.authorizationState() == .authorized else {
            throw CrossDeviceReminderError.authorizationRequired
        }
        let bindings = await stateStore.bindings(scopeID: scopeID)
        for binding in bindings.values.sorted(by: { $0.reminderID < $1.reminderID }) {
            try await eventStore.delete(binding)
        }
        try await stateStore.save([:], scopeID: scopeID)
        return ReminderSyncResult(
            destination: destination,
            upsertedIntentIDs: [],
            removedIntentIDs: bindings.keys.sorted(),
            limitations: []
        )
    }

    private func requireConsent(_ consent: ReminderSyncConsent) throws {
        guard consent.authorizes(.appleCalendar, revision: CrossDeviceReminderPolicy.appleConsentRevision) else {
            throw CrossDeviceReminderError.consentRequired
        }
    }
}
