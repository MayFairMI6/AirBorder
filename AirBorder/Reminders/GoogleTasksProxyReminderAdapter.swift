import Foundation

struct GoogleTasksSyncPayload: Codable, Equatable, Sendable {
    struct Reminder: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let notes: String
        let intendedActionAt: String
        let dueDate: String
        let timeZoneIdentifier: String
        let deepLink: String
        let sourceRevision: Int
    }

    let consentRevision: String
    let taskListID: String
    let scopeID: String
    let reminders: [Reminder]
}

struct GoogleTasksSyncResponse: Decodable, Sendable {
    struct Task: Decodable, Sendable {
        let reminderID: String
        let taskID: String
    }

    let tasks: [Task]
    let removedReminderIDs: [String]
    let limitations: [String]
}

enum GoogleTasksProxyRequestFactory {
    static func payload(
        intents: [CrossDeviceReminderIntent],
        taskListID: String,
        scopeID: String
    ) throws -> GoogleTasksSyncPayload {
        let reminders = try intents.sorted(by: { $0.id < $1.id }).map { intent -> GoogleTasksSyncPayload.Reminder in
            guard intent.scopeID == scopeID else { throw CrossDeviceReminderError.invalidScope }
            guard let identifier = intent.timeZoneIdentifier,
                  let timeZone = TimeZone(identifier: identifier) else {
                throw CrossDeviceReminderError.missingTimeZone(intentID: intent.id)
            }
            return GoogleTasksSyncPayload.Reminder(
                id: intent.id,
                title: intent.title,
                notes: intent.body,
                intendedActionAt: iso8601(intent.actionAt),
                dueDate: localDay(intent.actionAt, timeZone: timeZone),
                timeZoneIdentifier: identifier,
                deepLink: intent.deepLink.absoluteString,
                sourceRevision: intent.sourceRevision
            )
        }
        return GoogleTasksSyncPayload(
            consentRevision: CrossDeviceReminderPolicy.googleConsentRevision,
            taskListID: taskListID,
            scopeID: scopeID,
            reminders: reminders
        )
    }

    static func request(
        baseURL: URL,
        accessToken: String,
        payload: GoogleTasksSyncPayload
    ) throws -> URLRequest {
        guard !accessToken.isEmpty,
              !accessToken.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else {
            throw CrossDeviceReminderError.authenticationFailed
        }
        let url = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("reminders")
            .appendingPathComponent("google-tasks")
            .appendingPathComponent("sync")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = CrossDeviceReminderPolicy.proxyRequestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "X-AirportXR-Google-Tasks-Consent")
        request.setValue(CrossDeviceReminderPolicy.googleConsentRevision, forHTTPHeaderField: "X-AirportXR-Google-Tasks-Consent-Revision")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private static func localDay(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

actor GoogleTasksProxyReminderAdapter: CrossDeviceReminderProviding {
    nonisolated let destination = CrossDeviceReminderDestination.googleTasks

    private let baseURL: URL
    private let taskListID: String
    private let tokenProvider: any GoogleOAuthAccessTokenProviding
    private let session: URLSession
    private let scopes: Set<String> = [CrossDeviceReminderPolicy.googleTasksOAuthScope]

    init(
        baseURL: URL,
        taskListID: String = "@default",
        tokenProvider: any GoogleOAuthAccessTokenProviding,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.taskListID = taskListID
        self.tokenProvider = tokenProvider
        self.session = session
    }

    func authorizationState() async -> ReminderAuthorizationState {
        await tokenProvider.authorizationState(scopes: scopes)
    }

    /// Call only from a person's explicit Google Tasks opt-in action. An API
    /// key, Worker credential, or Airport XR account session cannot grant access
    /// to a person's task list.
    func requestAuthorization(consent: ReminderSyncConsent) async throws -> Bool {
        try requireConsent(consent)
        return try await tokenProvider.requestAuthorization(scopes: scopes)
    }

    func sync(
        _ intents: [CrossDeviceReminderIntent],
        scopeID: String,
        consent: ReminderSyncConsent
    ) async throws -> ReminderSyncResult {
        try requireConsent(consent)
        guard await tokenProvider.authorizationState(scopes: scopes) == .authorized else {
            throw CrossDeviceReminderError.authorizationRequired
        }
        let payload = try GoogleTasksProxyRequestFactory.payload(
            intents: intents,
            taskListID: taskListID,
            scopeID: scopeID
        )
        let token = try await tokenProvider.accessToken(scopes: scopes)
        let request = try GoogleTasksProxyRequestFactory.request(
            baseURL: baseURL,
            accessToken: token,
            payload: payload
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CrossDeviceReminderError.invalidResponse
        }
        guard data.count <= CrossDeviceReminderPolicy.maximumProxyResponseBytes else {
            throw CrossDeviceReminderError.responseTooLarge
        }
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw CrossDeviceReminderError.authenticationFailed
        case 429:
            throw CrossDeviceReminderError.rateLimited(
                retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            )
        default:
            throw CrossDeviceReminderError.server(statusCode: http.statusCode)
        }

        let decoded: GoogleTasksSyncResponse
        do {
            decoded = try JSONDecoder().decode(GoogleTasksSyncResponse.self, from: data)
        } catch {
            throw CrossDeviceReminderError.invalidResponse
        }
        return ReminderSyncResult(
            destination: destination,
            upsertedIntentIDs: decoded.tasks.map(\.reminderID).sorted(),
            removedIntentIDs: decoded.removedReminderIDs.sorted(),
            limitations: decoded.limitations
        )
    }

    func deleteAll(scopeID: String, consent: ReminderSyncConsent) async throws -> ReminderSyncResult {
        try await sync([], scopeID: scopeID, consent: consent)
    }

    private func requireConsent(_ consent: ReminderSyncConsent) throws {
        guard consent.authorizes(.googleTasks, revision: CrossDeviceReminderPolicy.googleConsentRevision) else {
            throw CrossDeviceReminderError.consentRequired
        }
    }
}
