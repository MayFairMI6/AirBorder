# Cross-device reminder design

Status: domain, EventKit adapter, Google Tasks proxy contract, and deterministic tests implemented. Settings/UI wiring and a production Google OAuth client remain integration work.

## Reminder sources

`CrossDeviceReminderPlanner` creates stable intents only from known future values:

- **Go to gate:** `JourneyAssessment.leaveBy`, already derived from boarding time, personalized route, required processing, accessibility, uncertainty, and the safety buffer.
- **Gate close:** a current `ItineraryLeg.gateCloseTime` sourced metric. The copy identifies it as an outer bound, not an airport-arrival target.
- **Latest return:** `FeasibilityAssessment.latestReturnTime` only for a selected plan classified `safe` with no unresolved trace inputs.

There is no fixed “10 minutes before” offset. A missing, expired, unresolved, unsafe, or past input creates no cross-device intent. Stable IDs omit the changing timestamp and input revision, so a revised live time updates the existing record instead of creating another one.

## Apple Calendar

The EventKit adapter is opt-in and does not request permission during background or routine sync. It requests full Calendar access only after the person enables Apple Calendar sync. Full access is necessary for the requested idempotent lookup, update, and delete behavior: Apple documents that write-only access cannot read any events, including events the app created. The app includes `NSCalendarsFullAccessUsageDescription` and confines reads/deletes to events carrying its stable `airportxr://reminders/<intent-id>` marker.

Every event starts at the already-derived action time and has an alarm at that same time. Its one-minute duration is a versioned EventKit action marker, not an estimate of travel or processing time. Stored EventKit identifiers are recoverable through the stable marker if a calendar move changes an opaque identifier. Repeated sync updates one event; removing an intent deletes only its marked event.

An event appears on other devices only when the person chooses a calendar account that those devices also synchronize (for example, iCloud or another CalDAV account). EventKit itself does not guarantee remote delivery.

Official references:

- [Apple: Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [Apple: requestFullAccessToEvents](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents())
- [Apple: eventIdentifier and lookup behavior](https://developer.apple.com/documentation/eventkit/ekevent/eventidentifier)
- [Apple: remove(_:span:)](https://developer.apple.com/documentation/eventkit/ekeventstore/remove(_:span:))

## Google Tasks

Google Tasks access is authorized by the person, not by an API key. The production app must enable the Google Tasks API, create an iOS OAuth client for `com.example.AirportXRCompanion`, use Google's current iOS sign-in SDK/installed-app flow with PKCE, and request only `https://www.googleapis.com/auth/tasks` after an explicit opt-in. The OAuth client ID is configuration, not a secret. No client secret is needed for an iOS client. Access/refresh tokens must remain in Google Sign-In/Keychain storage; they must not be placed in `Secrets.xcconfig`, the app bundle, UserDefaults, request bodies, analytics, or logs.

The iOS boundary supplies a short-lived user access token to the protected Worker route in the standard Bearer header. The Worker forwards it in memory and never stores or logs it. Before writing, it completes a bounded scan for this itinerary's stable Airport XR task markers. It updates a matching task, inserts only when no marker exists, consolidates interrupted-sync duplicates, and deletes only stale tasks in the same scope. If the list cannot be fully scanned within the named limit, it returns `409` before mutation so it cannot claim idempotency it has not established.

Google Tasks cannot provide a precise Airport XR alert time through its API: Google documents that the `due` field retains only the date and ignores the timestamp's time. The adapter derives that date in the airport time zone, while the Worker writes the exact action instant and time zone into notes. Google controls reminder timing and device delivery. Apple Calendar remains the exact-time cross-device path; adding Google Calendar would be a separate provider and consent decision.

Official references:

- [Google: OAuth 2.0 for iOS and desktop apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Google Tasks API](https://developers.google.com/workspace/tasks/reference/rest)
- [Google Tasks: tasks.insert](https://developers.google.com/workspace/tasks/reference/rest/v1/tasks/insert)
- [Google Tasks task resource and date-only due field](https://developers.google.com/workspace/tasks/reference/rest/v1/tasks)
- [Google Tasks: tasks.update](https://developers.google.com/workspace/tasks/reference/rest/v1/tasks/update)

## Remaining app integration

1. Add separate default-off settings for Apple Calendar and Google Tasks. Explain the different permission levels and Google Tasks' date-only limitation before consent.
2. Persist the versioned `ReminderSyncConsent`; when consent is revoked, delete the itinerary's managed records while authorization is still available, then revoke/disconnect provider authorization.
3. Implement `GoogleOAuthAccessTokenProviding` with Google's supported iOS SDK. Keep refresh tokens in its secure storage and pass only a short-lived access token to `GoogleTasksProxyReminderAdapter`.
4. Instantiate the adapters in `AppContainer`. Whenever a live itinerary or safety snapshot changes, re-run `CrossDeviceReminderPlanner`, then sync the resulting snapshot. Coalesce refreshes and retry bounded transient failures; never prompt for permission automatically.
5. Surface per-provider state: off, permission needed, last synchronized, date-only limitation, and error/retry action. VoiceOver must announce the provider and whether timing is exact.
6. Test on two signed-in physical devices with the selected Apple calendar account and Google account. Simulator tests validate contracts but cannot prove account-level synchronization or notification delivery.
7. A flight update that occurs while iOS has suspended the app cannot be guaranteed to reach Calendar/Tasks without a server-triggered push/background strategy. Existing synced events travel across devices, but continuously updating them requires the app to receive and process the new live snapshot.
