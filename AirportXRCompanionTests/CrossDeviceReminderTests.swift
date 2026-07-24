import Foundation
import XCTest
@testable import AirBorder

final class CrossDeviceReminderTests: XCTestCase {
    private let anchor = ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z")!

    func testPlannerUsesOnlyDerivedKnownTimesAndStableIDs() throws {
        var itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)
        itinerary.legs[itinerary.legs.count - 1].gateCloseTime = try currentMetric(
            XCTUnwrap(itinerary.legs.last?.gateCloseTime)
        )
        let activeLeg = try XCTUnwrap(itinerary.legs.last)
        let layover = try XCTUnwrap(itinerary.layovers.first)
        let latestReturn = anchor.addingTimeInterval(2 * 3_600)
        let assessment = safeAssessment(latestReturn: latestReturn)
        let journeyAssessment = JourneyAssessment(
            urgency: .comfortable,
            operationalStatus: .scheduled,
            freshness: .live,
            localizationConfidence: .high,
            alerts: [],
            message: "Known inputs",
            leaveBy: anchor.addingTimeInterval(3_600)
        )
        let planner = CrossDeviceReminderPlanner()
        let first = planner.intents(from: CrossDeviceReminderPlanningInput(
            itinerary: itinerary,
            activeLegID: activeLeg.id,
            journeyAssessment: journeyAssessment,
            latestReturn: LatestReturnReminderSource(
                layoverID: layover.id,
                candidateTitle: "Tokyo recovery plan",
                assessment: assessment,
                criticalInputsAreCurrent: true
            )
        ), now: anchor)

        XCTAssertEqual(first.map(\.kind), [.goToGate, .latestReturn, .gateClose])
        XCTAssertEqual(first[0].actionAt, journeyAssessment.leaveBy)
        XCTAssertEqual(first[1].actionAt, latestReturn)
        XCTAssertEqual(first[1].timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertTrue(first.allSatisfy { !$0.derivation.isEmpty })

        itinerary.inputRevision += 1
        let replay = planner.intents(from: CrossDeviceReminderPlanningInput(
            itinerary: itinerary,
            activeLegID: activeLeg.id,
            journeyAssessment: journeyAssessment,
            latestReturn: LatestReturnReminderSource(
                layoverID: layover.id,
                candidateTitle: "Tokyo recovery plan",
                assessment: assessment,
                criticalInputsAreCurrent: true
            )
        ), now: anchor)

        XCTAssertEqual(first.map(\.id), replay.map(\.id), "A live revision updates stable provider records instead of duplicating them")
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
        XCTAssertEqual(replay.map(\.sourceRevision), [2, 2, 2])
    }

    func testUnknownExpiredUnsafeAndPastInputsDoNotCreateFabricatedTimes() {
        let source = LongHaulReferenceScenario.itinerary(anchor: anchor)
        let noGateTimes = Itinerary(
            id: source.id,
            inputRevision: source.inputRevision,
            title: source.title,
            legs: source.legs.map {
                ItineraryLeg(id: $0.id, flight: $0.flight, onBlockTime: $0.onBlockTime, gateCloseTime: nil)
            },
            createdAt: source.createdAt,
            updatedAt: source.updatedAt
        )
        let pastJourneyAssessment = JourneyAssessment(
            urgency: .dataStale,
            operationalStatus: .unknown,
            freshness: .stale,
            localizationConfidence: .unavailable,
            alerts: [.staleData],
            message: "Unknown",
            leaveBy: anchor.addingTimeInterval(-1)
        )
        let intents = CrossDeviceReminderPlanner().intents(
            from: CrossDeviceReminderPlanningInput(
                itinerary: noGateTimes,
                journeyAssessment: pastJourneyAssessment,
                latestReturn: LatestReturnReminderSource(
                    layoverID: noGateTimes.layovers.first?.id ?? "unknown",
                    candidateTitle: "Unresolved plan",
                    assessment: unresolvedAssessment(),
                    criticalInputsAreCurrent: false
                )
            ),
            now: anchor
        )
        XCTAssertTrue(intents.isEmpty)
    }

    func testGateCloseWithMissingExpiryOrInvalidTimestampOrderCannotCreateExternalAction() throws {
        let planner = CrossDeviceReminderPlanner()
        let noExpiry = LongHaulReferenceScenario.itinerary(anchor: anchor)
        XCTAssertTrue(planner.intents(
            from: CrossDeviceReminderPlanningInput(itinerary: noExpiry),
            now: anchor
        ).isEmpty)

        var invalidOrdering = noExpiry
        let original = try XCTUnwrap(invalidOrdering.legs.last?.gateCloseTime)
        invalidOrdering.legs[invalidOrdering.legs.count - 1].gateCloseTime = SourcedMetric(
            value: original.value,
            unit: original.unit,
            provider: original.provider,
            providerField: original.providerField,
            sourceRecordID: original.sourceRecordID,
            observedAt: anchor.addingTimeInterval(60),
            receivedAt: anchor,
            expiresAt: anchor.addingTimeInterval(600),
            uncertainty: original.uncertainty,
            derivation: original.derivation
        )
        XCTAssertTrue(planner.intents(
            from: CrossDeviceReminderPlanningInput(itinerary: invalidOrdering),
            now: anchor
        ).isEmpty)
    }

    func testAppleCalendarAdapterIsOptInIdempotentAndDeletesOnlyStaleBindings() async throws {
        let eventStore = FakeAppleCalendarEventStore()
        let stateStore = InMemoryAppleCalendarSyncStateStore()
        let adapter = AppleCalendarReminderAdapter(eventStore: eventStore, stateStore: stateStore)
        let scopeID = "scope-1"
        let first = reminder(id: "reminder-1", scopeID: scopeID, actionAt: anchor.addingTimeInterval(3_600))
        let second = reminder(id: "reminder-2", scopeID: scopeID, actionAt: anchor.addingTimeInterval(7_200))
        let consent = appleConsent()

        let granted = try await adapter.requestAuthorization(consent: consent)
        XCTAssertTrue(granted)
        _ = try await adapter.sync([first, second], scopeID: scopeID, consent: consent)
        _ = try await adapter.sync([first], scopeID: scopeID, consent: consent)
        _ = try await adapter.sync([first], scopeID: scopeID, consent: consent)

        let currentIDs = await eventStore.currentReminderIDs()
        let creations = await eventStore.creationCount()
        let deletions = await eventStore.deletedReminderIDs()
        XCTAssertEqual(currentIDs, [first.id])
        XCTAssertEqual(creations, 2)
        XCTAssertEqual(deletions, [second.id])

        let deleted = try await adapter.deleteAll(scopeID: scopeID, consent: consent)
        XCTAssertEqual(deleted.removedIntentIDs, [first.id])
        let remainingIDs = await eventStore.currentReminderIDs()
        XCTAssertTrue(remainingIDs.isEmpty)
    }

    func testAppleCalendarAdapterNeverPromptsOrWritesWithoutCurrentExplicitConsent() async throws {
        let eventStore = FakeAppleCalendarEventStore()
        let adapter = AppleCalendarReminderAdapter(
            eventStore: eventStore,
            stateStore: InMemoryAppleCalendarSyncStateStore()
        )
        let revoked = ReminderSyncConsent(
            destination: .appleCalendar,
            revision: CrossDeviceReminderPolicy.appleConsentRevision,
            grantedAt: anchor,
            revokedAt: anchor
        )

        do {
            _ = try await adapter.sync(
                [reminder(id: "reminder-1", scopeID: "scope-1", actionAt: anchor)],
                scopeID: "scope-1",
                consent: revoked
            )
            XCTFail("Revoked consent must fail closed")
        } catch {
            XCTAssertEqual(error as? CrossDeviceReminderError, .consentRequired)
        }
        let authorizationRequests = await eventStore.authorizationRequestCount()
        let currentIDs = await eventStore.currentReminderIDs()
        XCTAssertEqual(authorizationRequests, 0)
        XCTAssertTrue(currentIDs.isEmpty)
    }

    func testGoogleTasksRequestUsesAirportLocalDateAndKeepsOAuthTokenOutOfBody() throws {
        let scopeID = "scope-1"
        let actionAt = ISO8601DateFormatter().date(from: "2026-07-14T16:30:00Z")!
        let intent = reminder(
            id: "reminder-1",
            scopeID: scopeID,
            actionAt: actionAt,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let payload = try GoogleTasksProxyRequestFactory.payload(
            intents: [intent],
            taskListID: "@default",
            scopeID: scopeID
        )
        XCTAssertEqual(payload.reminders.first?.dueDate, "2026-07-15")
        XCTAssertEqual(payload.reminders.first?.intendedActionAt, "2026-07-14T16:30:00.000Z")

        let token = "short-lived-user-oauth-token"
        let request = try GoogleTasksProxyRequestFactory.request(
            baseURL: URL(string: "https://airportxr.example")!,
            accessToken: token,
            payload: payload
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-AirportXR-Google-Tasks-Consent"), "true")
        XCTAssertFalse(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)?.contains(token) == true)
    }

    func testGoogleTasksMissingAirportTimeZoneRemainsUnknown() throws {
        let intent = reminder(
            id: "reminder-1",
            scopeID: "scope-1",
            actionAt: anchor,
            timeZoneIdentifier: nil
        )
        XCTAssertThrowsError(try GoogleTasksProxyRequestFactory.payload(
            intents: [intent],
            taskListID: "@default",
            scopeID: "scope-1"
        )) { error in
            XCTAssertEqual(error as? CrossDeviceReminderError, .missingTimeZone(intentID: intent.id))
        }
    }

    private func safeAssessment(latestReturn: Date) -> FeasibilityAssessment {
        FeasibilityAssessment(
            candidateID: UUID(uuidString: "C0000000-0000-4000-8000-000000000010")!,
            status: .safe,
            probability: ProbabilityInterval(estimate: 0.97, lower95: 0.95, upper95: 0.98, trials: 10_000),
            availableWindowMinutes: 300,
            requiredMostLikelyMinutes: 120,
            usableRestMinutes: 180,
            latestReturnTime: latestReturn,
            summary: "Safe deterministic fixture",
            trace: CalculationTrace(
                policyVersion: SafetyPolicy.current.version,
                simulationSeed: 7,
                generatedAt: anchor,
                steps: [DerivationStep(
                    label: "Latest return",
                    formula: "gate-close - return components",
                    inputRecordIDs: ["return-record"],
                    result: latestReturn.ISO8601Format()
                )],
                sourceRecordIDs: ["return-record"],
                unresolvedInputs: []
            )
        )
    }

    private func unresolvedAssessment() -> FeasibilityAssessment {
        FeasibilityAssessment(
            candidateID: UUID(uuidString: "C0000000-0000-4000-8000-000000000011")!,
            status: .requiresConfirmation,
            probability: nil,
            availableWindowMinutes: nil,
            requiredMostLikelyMinutes: nil,
            usableRestMinutes: nil,
            latestReturnTime: nil,
            summary: "Unknown inputs",
            trace: CalculationTrace(
                policyVersion: SafetyPolicy.current.version,
                simulationSeed: nil,
                generatedAt: anchor,
                steps: [],
                sourceRecordIDs: [],
                unresolvedInputs: ["onward gate-close"]
            )
        )
    }

    private func reminder(
        id: String,
        scopeID: String,
        actionAt: Date,
        timeZoneIdentifier: String? = "Asia/Tokyo"
    ) -> CrossDeviceReminderIntent {
        CrossDeviceReminderIntent(
            id: id,
            scopeID: scopeID,
            kind: .latestReturn,
            title: "Return now",
            body: "Derived reminder",
            actionAt: actionAt,
            timeZoneIdentifier: timeZoneIdentifier,
            deepLink: URL(string: "airportxr://transit")!,
            sourceRevision: 1,
            derivation: []
        )
    }

    private func appleConsent() -> ReminderSyncConsent {
        ReminderSyncConsent(
            destination: .appleCalendar,
            revision: CrossDeviceReminderPolicy.appleConsentRevision,
            grantedAt: anchor,
            revokedAt: nil
        )
    }

    private func currentMetric(_ metric: SourcedMetric<Date>) -> SourcedMetric<Date> {
        SourcedMetric(
            value: metric.value,
            unit: metric.unit,
            provider: metric.provider,
            providerField: metric.providerField,
            sourceRecordID: metric.sourceRecordID,
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: anchor.addingTimeInterval(600),
            uncertainty: metric.uncertainty,
            derivation: metric.derivation
        )
    }
}

@MainActor
final class CrossDeviceReminderCoordinatorTests: XCTestCase {
    private let anchor = ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z")!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CrossDeviceReminderCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRoutineRefreshIsDefaultOffAndNeverRequestsPermission() async {
        let provider = FakeCrossDeviceReminderProvider()
        let preferences = PreferencesStore(defaults: defaults)
        let fixedNow = anchor
        let coordinator = CrossDeviceReminderCoordinator(
            appleCalendar: provider,
            preferences: preferences,
            now: { fixedNow }
        )

        await coordinator.syncIfEnabled(using: planningInput())

        XCTAssertFalse(coordinator.isAppleCalendarEnabled)
        XCTAssertEqual(coordinator.appleCalendarState, .off)
        let authorizationRequests = await provider.authorizationRequestCount()
        let syncCount = await provider.syncCount()
        XCTAssertEqual(authorizationRequests, 0)
        XCTAssertEqual(syncCount, 0)
    }

    func testExplicitEnablePersistsVersionedConsentSyncsAndOptOutCleansUp() async {
        let provider = FakeCrossDeviceReminderProvider()
        let preferences = PreferencesStore(defaults: defaults)
        let fixedNow = anchor
        let coordinator = CrossDeviceReminderCoordinator(
            appleCalendar: provider,
            preferences: preferences,
            now: { fixedNow }
        )
        let input = planningInput()

        await coordinator.enableAppleCalendar(using: input)

        XCTAssertTrue(coordinator.isAppleCalendarEnabled)
        XCTAssertTrue(preferences.appleCalendarReminderConsent?.authorizes(
            .appleCalendar,
            revision: CrossDeviceReminderPolicy.appleConsentRevision
        ) == true)
        XCTAssertEqual(preferences.appleCalendarReminderScopeID, input.itinerary.id.uuidString.lowercased())
        let authorizationRequests = await provider.authorizationRequestCount()
        let syncCount = await provider.syncCount()
        XCTAssertEqual(authorizationRequests, 1)
        XCTAssertEqual(syncCount, 1)
        guard case let .synced(intentCount, syncedAt) = coordinator.appleCalendarState else {
            return XCTFail("Expected a successful synchronized state")
        }
        XCTAssertGreaterThan(intentCount, 0)
        XCTAssertEqual(syncedAt, anchor)

        await coordinator.disableAppleCalendar()

        XCTAssertFalse(coordinator.isAppleCalendarEnabled)
        XCTAssertEqual(coordinator.appleCalendarState, .off)
        XCTAssertNil(preferences.appleCalendarReminderScopeID)
        XCTAssertNotNil(preferences.appleCalendarReminderConsent?.revokedAt)
        let deletedScopeIDs = await provider.deletedScopeIDs()
        XCTAssertEqual(deletedScopeIDs, [input.itinerary.id.uuidString.lowercased()])
    }

    func testRestoredConsentWithUndeterminedPermissionDoesNotPromptAutomatically() async {
        let preferences = PreferencesStore(defaults: defaults)
        preferences.setAppleCalendarReminderConsent(ReminderSyncConsent(
            destination: .appleCalendar,
            revision: CrossDeviceReminderPolicy.appleConsentRevision,
            grantedAt: anchor,
            revokedAt: nil
        ))
        let provider = FakeCrossDeviceReminderProvider()
        let fixedNow = anchor
        let coordinator = CrossDeviceReminderCoordinator(
            appleCalendar: provider,
            preferences: preferences,
            now: { fixedNow }
        )

        await coordinator.syncIfEnabled(using: planningInput())

        XCTAssertTrue(coordinator.isAppleCalendarEnabled)
        XCTAssertEqual(coordinator.appleCalendarState, .permissionRequired)
        let authorizationRequests = await provider.authorizationRequestCount()
        let syncCount = await provider.syncCount()
        XCTAssertEqual(authorizationRequests, 0)
        XCTAssertEqual(syncCount, 0)
    }

    private func planningInput() -> CrossDeviceReminderPlanningInput {
        var itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)
        if let metric = itinerary.legs.last?.gateCloseTime {
            itinerary.legs[itinerary.legs.count - 1].gateCloseTime = SourcedMetric(
                value: metric.value,
                unit: metric.unit,
                provider: metric.provider,
                providerField: metric.providerField,
                sourceRecordID: metric.sourceRecordID,
                observedAt: anchor,
                receivedAt: anchor,
                expiresAt: anchor.addingTimeInterval(600),
                uncertainty: metric.uncertainty,
                derivation: metric.derivation
            )
        }
        return CrossDeviceReminderPlanningInput(itinerary: itinerary)
    }
}

private actor InMemoryAppleCalendarSyncStateStore: AppleCalendarSyncStateStoring {
    private var records: [String: [String: AppleCalendarBinding]] = [:]

    func bindings(scopeID: String) -> [String: AppleCalendarBinding] {
        records[scopeID] ?? [:]
    }

    func save(_ bindings: [String: AppleCalendarBinding], scopeID: String) {
        records[scopeID] = bindings
    }
}

private actor FakeAppleCalendarEventStore: AppleCalendarEventStoring {
    private var state = ReminderAuthorizationState.notDetermined
    private var records: [String: AppleCalendarBinding] = [:]
    private var nextIdentifier = 1
    private var creations = 0
    private var deletions: [String] = []
    private var authorizationRequests = 0

    func authorizationState() -> ReminderAuthorizationState { state }

    func requestFullAccess() -> Bool {
        authorizationRequests += 1
        state = .authorized
        return true
    }

    func upsert(
        _ intent: CrossDeviceReminderIntent,
        existing: AppleCalendarBinding?
    ) -> AppleCalendarBinding {
        let identifier: String
        if let existing {
            identifier = existing.eventIdentifier
        } else {
            identifier = "event-\(nextIdentifier)"
            nextIdentifier += 1
            creations += 1
        }
        let binding = AppleCalendarBinding(
            reminderID: intent.id,
            eventIdentifier: identifier,
            actionAt: intent.actionAt
        )
        records[intent.id] = binding
        return binding
    }

    func delete(_ binding: AppleCalendarBinding) {
        if records.removeValue(forKey: binding.reminderID) != nil {
            deletions.append(binding.reminderID)
        }
    }

    func currentReminderIDs() -> [String] { records.keys.sorted() }
    func creationCount() -> Int { creations }
    func deletedReminderIDs() -> [String] { deletions }
    func authorizationRequestCount() -> Int { authorizationRequests }
}

private actor FakeCrossDeviceReminderProvider: CrossDeviceReminderProviding {
    nonisolated let destination = CrossDeviceReminderDestination.appleCalendar

    private var state = ReminderAuthorizationState.notDetermined
    private var authorizationRequests = 0
    private var synchronizedIntentIDs: [[String]] = []
    private var deletions: [String] = []

    func authorizationState() -> ReminderAuthorizationState { state }

    func requestAuthorization(consent: ReminderSyncConsent) throws -> Bool {
        guard consent.authorizes(
            .appleCalendar,
            revision: CrossDeviceReminderPolicy.appleConsentRevision
        ) else {
            throw CrossDeviceReminderError.consentRequired
        }
        authorizationRequests += 1
        state = .authorized
        return true
    }

    func sync(
        _ intents: [CrossDeviceReminderIntent],
        scopeID: String,
        consent: ReminderSyncConsent
    ) throws -> ReminderSyncResult {
        guard consent.authorizes(
            .appleCalendar,
            revision: CrossDeviceReminderPolicy.appleConsentRevision
        ) else {
            throw CrossDeviceReminderError.consentRequired
        }
        synchronizedIntentIDs.append(intents.map(\.id).sorted())
        return ReminderSyncResult(
            destination: destination,
            upsertedIntentIDs: intents.map(\.id).sorted(),
            removedIntentIDs: [],
            limitations: []
        )
    }

    func deleteAll(scopeID: String, consent: ReminderSyncConsent) throws -> ReminderSyncResult {
        deletions.append(scopeID)
        return ReminderSyncResult(
            destination: destination,
            upsertedIntentIDs: [],
            removedIntentIDs: [],
            limitations: []
        )
    }

    func authorizationRequestCount() -> Int { authorizationRequests }
    func syncCount() -> Int { synchronizedIntentIDs.count }
    func deletedScopeIDs() -> [String] { deletions }
}
