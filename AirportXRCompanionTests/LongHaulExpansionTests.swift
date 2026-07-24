import CoreLocation
import Foundation
import XCTest
@testable import AirBorder

final class LongHaulExpansionTests: XCTestCase {
    func testDecisionReadyPlanSeparatesTravelQueuesAndQuietCallSuitability() {
        let workPod = LayoverPlace(
            id: "work", name: "Work pod", airportCode: "HND", terminal: "3",
            category: .workPod, accessZone: .airside, latitude: nil, longitude: nil,
            summary: "", bookingURL: nil, officialSourceURL: nil, dataMode: .demo
        )
        let candidate = PlanCandidate(
            title: "Work", place: workPod,
            segments: [
                PlanSegment(kind: .access, title: "Walk", duration: durationMetric(id: "walk", lower: 5, mode: 7, upper: 9)),
                PlanSegment(kind: .security, title: "Security", duration: durationMetric(id: "security", lower: 3, mode: 4, upper: 6)),
                PlanSegment(kind: .terminalRoute, title: "Return", duration: durationMetric(id: "return", lower: 5, mode: 8, upper: 10))
            ], entryAssessment: nil
        )

        let decision = DecisionReadyPlan(candidate: candidate)

        XCTAssertEqual(decision.totalMinutes, 19)
        XCTAssertEqual(decision.walkMinutes, 15)
        XCTAssertEqual(decision.queueMinutes, 4)
        XCTAssertEqual(decision.backtrackingMinutes, 8)
        XCTAssertEqual(decision.accessMessage, "AIRSIDE · no security return expected")
        XCTAssertEqual(decision.quietCallScore, 9)
    }

    func testGateStatusSnapshotDetectsChangedGate() {
        let snapshot = GateStatusSnapshot(gate: "C12", previousGate: "C8", walkMinutes: 6, boardingTime: anchor, leaveBy: anchor)
        XCTAssertTrue(snapshot.hasGateChange)
    }

    func testSelfTransferIsPersistedOnTheOnwardLegAndReflectedInLayover() {
        var itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)
        let onwardID = try! XCTUnwrap(itinerary.legs.last?.id)
        let originalRevision = itinerary.inputRevision
        itinerary.legs[itinerary.legs.count - 1].transferFlow = .selfTransfer
        itinerary.inputRevision += 1

        let layover = try! XCTUnwrap(itinerary.layovers.first)
        XCTAssertEqual(layover.onwardLegID, onwardID)
        XCTAssertEqual(layover.transferFlow, .selfTransfer)
        XCTAssertGreaterThan(itinerary.inputRevision, originalRevision)
    }

    func testCandidateRequiringLandsideExitNeedsEntryAssessmentEvenWhenPlaceIsAirside() throws {
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)
        let layover = try XCTUnwrap(itinerary.layovers.first)
        let candidate = completeCandidate(zone: .airside, entry: nil, requiresLandsideExit: true)

        let result = MonteCarloLayoverRecommendationEngine().assess(
            itinerary: itinerary, layover: layover, candidate: candidate,
            profile: confirmedProfile(), snapshotRevision: "self-transfer-entry", seed: 4, now: anchor
        )

        XCTAssertEqual(result.status, .requiresConfirmation)
        XCTAssertTrue(result.trace.unresolvedInputs.contains("entry requirements"))
    }

    func testAirportDiscoveryReferencePointsAreVersionedAndSourced() throws {
        let haneda = try XCTUnwrap(AirportReferencePointRegistry.referencePoint(for: "hnd"))
        XCTAssertEqual(AirportReferencePointRegistry.version, "ourairports-reference-points-2026-07-14-v1")
        XCTAssertEqual(haneda.sourceRecordID, "RJTT")
        XCTAssertEqual(haneda.latitude, 35.549678, accuracy: 0.000_001)
        XCTAssertEqual(haneda.longitude, 139.786958, accuracy: 0.000_001)
        XCTAssertEqual(haneda.sourceURL.host, "ourairports.com")
        XCTAssertNil(AirportReferencePointRegistry.referencePoint(for: "ZZZ"))
    }

    private let anchor = ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z")!

    func testIndoorRouteEmulatorGeneratesMappedMovementAcrossLevels() throws {
        let graph = TerminalGraph(
            version: "indoor-replay-v1",
            nodes: [
                TerminalNode(id: "start", name: "Start", point: MapPoint(x: 0, y: 0), level: 2, kind: .marker),
                TerminalNode(id: "lift", name: "Lift", point: MapPoint(x: 10, y: 0), level: 3, kind: .elevator),
                TerminalNode(id: "gate", name: "Gate", point: MapPoint(x: 10, y: 20), level: 3, kind: .gate)
            ],
            edges: []
        )
        let route = TerminalRoute(
            nodeIDs: ["start", "lift", "gate"],
            edgeIDs: [],
            distanceMeters: 30,
            durationSeconds: 30,
            mode: .accessible
        )

        let readings = TerminalRouteLocationEmulator(graph: graph, route: route).readings(
            samplesPerSegment: 2,
            startingAt: anchor,
            sampleInterval: 2
        )

        XCTAssertEqual(readings.count, 5)
        XCTAssertEqual(readings.first?.matchedNodeID, "start")
        XCTAssertEqual(readings[1].point, MapPoint(x: 5, y: 0))
        XCTAssertEqual(readings[1].level, 3)
        XCTAssertEqual(readings.last?.matchedNodeID, "gate")
        XCTAssertEqual(readings.last?.point, MapPoint(x: 10, y: 20))
        XCTAssertEqual(readings.last?.source, .routeReplay)
    }

    func testExternalIndoorFeedIsExplicitUITestOnlyAndLoopbackOnly() throws {
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:8765/reading"))
        XCTAssertNoThrow(try LocalIndoorSignalFeedClient(endpoint: endpoint))
        XCTAssertThrowsError(
            try LocalIndoorSignalFeedClient(endpoint: XCTUnwrap(URL(string: "https://example.com/reading")))
        ) { error in
            XCTAssertEqual(error as? LocalIndoorSignalFeedError, .nonLoopbackEndpoint)
        }

        let qa = AppLaunchContext.current(arguments: [
            "AirBorder", "--uitesting", "--launch-mode", "demo",
            "--qa-indoor-feed", endpoint.absoluteString
        ])
        XCTAssertEqual(qa.externalIndoorSignalURL, endpoint)
        XCTAssertTrue(qa.usesSimulatedTerminalWalk)

        let ordinary = AppLaunchContext.current(arguments: [
            "AirBorder", "--qa-indoor-feed", endpoint.absoluteString
        ])
        XCTAssertNil(ordinary.externalIndoorSignalURL)
        XCTAssertFalse(ordinary.usesSimulatedTerminalWalk)

        let coreLocationQA = AppLaunchContext.current(arguments: [
            "AirBorder", "--uitesting", "--launch-mode", "demo",
            "--qa-core-location-indoor"
        ])
        XCTAssertTrue(coreLocationQA.usesCoreLocationIndoorQA)
        XCTAssertTrue(coreLocationQA.usesSimulatedTerminalWalk)

        let ordinaryCoreLocation = AppLaunchContext.current(arguments: [
            "AirBorder", "--qa-core-location-indoor"
        ])
        XCTAssertFalse(ordinaryCoreLocation.usesCoreLocationIndoorQA)
    }

    func testBKKHNDLAXReferenceScenarioUsesAirportLocalLayoverTimeZone() throws {
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)

        XCTAssertEqual(itinerary.schemaVersion, Itinerary.currentSchemaVersion)
        XCTAssertEqual(itinerary.legs.map { $0.flight.origin.iata }, ["BKK", "HND"])
        XCTAssertEqual(itinerary.legs.map { $0.flight.destination.iata }, ["HND", "LAX"])

        let layover = try XCTUnwrap(itinerary.layovers.first)
        XCTAssertEqual(layover.airport.iata, "HND")
        XCTAssertEqual(layover.onwardAirport.iata, "HND")
        XCTAssertEqual(layover.timeZone.identifier, "Asia/Tokyo")
        XCTAssertFalse(layover.isInterAirportTransfer)
        XCTAssertEqual(try XCTUnwrap(layover.availableWindowMinutes), 370, accuracy: 0.001)
        XCTAssertTrue(layover.contains(anchor))
    }

    func testCoreLocationQAFixtureRoundTripsAndMapsToVenueNode() throws {
        let graph = SampleTerminalGraph.hanedaTerminal3Demo
        let node = try XCTUnwrap(graph.nodes.first(where: { $0.id == "t3-elevator-north" }))
        let coordinate = HNDCoreLocationQAFixture.coordinate(for: node.point)
        let roundTrip = HNDCoreLocationQAFixture.point(for: coordinate)
        XCTAssertEqual(roundTrip.x, node.point.x, accuracy: 0.000_001)
        XCTAssertEqual(roundTrip.y, node.point.y, accuracy: 0.000_001)

        let location = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 315,
            speed: 1,
            timestamp: anchor
        )
        let reading = try XCTUnwrap(
            HNDCoreLocationQAFixture.reading(from: location, graph: graph)
        )
        XCTAssertEqual(reading.matchedNodeID, node.id)
        XCTAssertEqual(reading.level, node.level)
        XCTAssertEqual(reading.headingDegrees, 315, accuracy: 0.001)
        XCTAssertEqual(reading.source, .coreLocationReplay)
    }

    func testFourLegItineraryBuildsOrderedLayoversAcrossTimeZonesAndDateLine() throws {
        let itinerary = makeFourLegDateLineItinerary()

        XCTAssertEqual(itinerary.legs.count, 4)
        XCTAssertEqual(itinerary.layovers.count, 3)
        XCTAssertEqual(itinerary.layovers.map { $0.airport.iata }, ["HND", "LAX", "JFK"])
        XCTAssertEqual(itinerary.layovers.map { $0.timeZone.identifier }, ["Asia/Tokyo", "America/Los_Angeles", "America/New_York"])
        XCTAssertTrue(itinerary.layovers.allSatisfy { ($0.availableWindowMinutes ?? -1) > 0 })

        let transPacific = itinerary.legs[1].flight
        let departure = try XCTUnwrap(transPacific.effectiveDeparture)
        let arrival = try XCTUnwrap(transPacific.effectiveArrival)
        XCTAssertGreaterThan(arrival, departure, "Absolute elapsed time must stay positive across the date line")

        let departureLocal = localComponents(departure, timeZone: "Asia/Tokyo")
        let arrivalLocal = localComponents(arrival, timeZone: "America/Los_Angeles")
        XCTAssertEqual(departureLocal.day, 14)
        XCTAssertEqual(departureLocal.hour, 12)
        XCTAssertEqual(arrivalLocal.day, 14)
        XCTAssertEqual(arrivalLocal.hour, 5, "The local clock can be earlier after an eastbound date-line crossing")
    }

    func testItineraryMutationsPreserveOrderAndIncrementInputRevision() {
        var itinerary = makeFourLegDateLineItinerary()
        let originalRevision = itinerary.inputRevision
        let firstID = itinerary.legs[0].id

        itinerary.moveLeg(from: IndexSet(integer: 0), to: itinerary.legs.count, at: anchor)

        XCTAssertEqual(itinerary.legs.last?.id, firstID)
        XCTAssertEqual(itinerary.inputRevision, originalRevision + 1)
        XCTAssertEqual(itinerary.updatedAt, anchor)
    }

    func testHNDToNRTLayoverIsDetectedAndFastestTransferIsParetoRanked() async throws {
        let itinerary = LongHaulReferenceScenario.hanedaToNaritaItinerary(anchor: anchor)
        let layover = try XCTUnwrap(itinerary.layovers.first)
        XCTAssertTrue(layover.isInterAirportTransfer)
        XCTAssertEqual(layover.airport.iata, "HND")
        XCTAssertEqual(layover.onwardAirport.iata, "NRT")

        let options = try await TokyoInterAirportDemoTransferProvider().options(
            from: layover.airport,
            to: layover.onwardAirport,
            after: anchor
        )
        let plan = InterAirportTransferPlanner().plan(options: options, requireAccessibility: false, now: anchor)

        XCTAssertEqual(plan.selected?.id, "demo-hnd-nrt-road")
        XCTAssertEqual(plan.ranked.map(\.id), ["demo-hnd-nrt-road", "demo-hnd-nrt-rail", "demo-hnd-nrt-bus"])
        XCTAssertFalse(plan.canClaimFastest, "A named demo route can be ranked but never claimed as fastest")
        XCTAssertTrue(plan.rationale.contains("Pareto"))
        XCTAssertTrue(plan.rationale.contains("No scalar penalties"))
    }

    func testHNDToNRTAccessibleTransferRequiresConfirmedAccessibility() async throws {
        let itinerary = LongHaulReferenceScenario.hanedaToNaritaItinerary(anchor: anchor)
        let layover = try XCTUnwrap(itinerary.layovers.first)
        let options = try await TokyoInterAirportDemoTransferProvider().options(
            from: layover.airport,
            to: layover.onwardAirport,
            after: anchor
        )

        let plan = InterAirportTransferPlanner().plan(options: options, requireAccessibility: true, now: anchor)

        XCTAssertEqual(plan.selected?.id, "demo-hnd-nrt-rail")
        XCTAssertEqual(plan.ranked.map(\.id), ["demo-hnd-nrt-rail"])
        XCTAssertTrue(plan.unresolvedInputs.isEmpty)
    }

    func testMissingEntryAssessmentBlocksPositiveCityRecommendation() throws {
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)
        let layover = try XCTUnwrap(itinerary.layovers.first)
        let candidate = completeCandidate(zone: .city, entry: nil)

        let result = MonteCarloLayoverRecommendationEngine().assess(
            itinerary: itinerary,
            layover: layover,
            candidate: candidate,
            profile: confirmedProfile(),
            snapshotRevision: "entry-missing-v1",
            seed: 10_001,
            now: anchor
        )

        XCTAssertEqual(result.status, .requiresConfirmation)
        XCTAssertNil(result.probability)
        XCTAssertTrue(result.trace.unresolvedInputs.contains("entry requirements"))
        XCTAssertEqual(result.summary, "We don't have enough information yet.")
    }

    func testExpiredEntryAssessmentCannotAuthorizeLandsideRecommendation() throws {
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)
        let layover = try XCTUnwrap(itinerary.layovers.first)
        let staleEntry = entryAssessment(expiresAt: anchor, status: .authorizationNotIndicated)
        let candidate = completeCandidate(zone: .airportLandside, entry: staleEntry)

        let result = MonteCarloLayoverRecommendationEngine().assess(
            itinerary: itinerary,
            layover: layover,
            candidate: candidate,
            profile: confirmedProfile(),
            snapshotRevision: "entry-stale-v1",
            seed: 10_002,
            now: anchor
        )

        XCTAssertEqual(result.status, .requiresConfirmation)
        XCTAssertNil(result.probability)
        XCTAssertTrue(result.trace.unresolvedInputs.contains("current entry requirements"))
    }

    func testDiscoveryOnlyEntryEvidenceCannotAuthorizeLandsideRecommendation() {
        let discovery = EntryAssessment(
            status: .authorizationNotIndicated,
            summary: "A search tool found an official page but did not derive eligibility.",
            provider: "Official-link discovery fixture",
            evidenceKind: .officialSourceDiscovery,
            sourceRecordID: "discovery-record",
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: anchor.addingTimeInterval(3_600),
            officialVerificationURLs: [URL(string: "https://www.mofa.go.jp/j_info/visit/visa/index.html")!],
            isDemo: true
        )

        XCTAssertTrue(discovery.isCurrent(at: anchor))
        XCTAssertFalse(discovery.canSupportLandsideRecommendation(profile: confirmedProfile(), at: anchor))
    }

    func testEntryCacheIsExactQueryKeyedAndKeepsStaleProvenanceDisplayOnly() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = EntryRequirementCache(directory: directory)
        let exactQuery = entryQuery(nationality: "US")
        let differentTravelerQuery = entryQuery(nationality: "CA")
        let staleAssessment = EntryAssessment(
            status: .authorizationNotIndicated,
            summary: "Expired structured fixture retained only for transparent display.",
            provider: "Structured entry fixture",
            providerChain: ["Primary fixture", "Backup fixture"],
            evidenceKind: .structuredProvider,
            sourceRecordID: "entry-cache-record",
            observedAt: anchor.addingTimeInterval(-7_200),
            receivedAt: anchor.addingTimeInterval(-7_100),
            expiresAt: anchor,
            officialVerificationURLs: [URL(string: "https://www.mofa.go.jp/j_info/visit/visa/index.html")!],
            isDemo: true
        )

        try await cache.save(staleAssessment, for: exactQuery)
        let cached = await cache.assessment(for: exactQuery)
        let loaded = try XCTUnwrap(cached)
        let otherTravelerCached = await cache.assessment(for: differentTravelerQuery)

        XCTAssertEqual(loaded.sourceRecordID, "entry-cache-record")
        XCTAssertEqual(loaded.providerChain, ["Primary fixture", "Backup fixture"])
        XCTAssertFalse(loaded.isCurrent(at: anchor))
        XCTAssertFalse(loaded.canSupportLandsideRecommendation(profile: confirmedProfile(), at: anchor))
        XCTAssertNil(otherTravelerCached)
        XCTAssertNotEqual(
            EntryRequirementCache.fingerprint(for: exactQuery),
            EntryRequirementCache.fingerprint(for: differentTravelerQuery)
        )
    }

    func testInformationalFallbackDoesNotOverwriteCurrentStructuredEntryCache() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = EntryRequirementCache(directory: directory)
        let query = entryQuery(nationality: "US")
        let currentStructured = EntryAssessment(
            status: .authorizationNotIndicated,
            summary: "Current structured fixture",
            provider: "Structured entry fixture",
            evidenceKind: .structuredProvider,
            sourceRecordID: "current-structured-record",
            observedAt: Date(),
            receivedAt: Date(),
            expiresAt: Date().addingTimeInterval(3_600),
            officialVerificationURLs: [URL(string: "https://www.mofa.go.jp/j_info/visit/visa/index.html")!],
            isDemo: true
        )
        try await cache.save(currentStructured, for: query)
        let provider = CachedEntryRequirementProvider(
            upstream: InformationalEntryRequirementProvider(),
            cache: cache
        )

        let result = try await provider.assessment(for: query)
        let persisted = await cache.assessment(for: query)

        XCTAssertEqual(result.sourceRecordID, "current-structured-record")
        XCTAssertEqual(persisted?.sourceRecordID, "current-structured-record")
    }

    func testMissingQueueEstimateRemainsUnknownInsteadOfBecomingZero() throws {
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)
        let layover = try XCTUnwrap(itinerary.layovers.first)
        let airside = place(zone: .airside)
        let candidate = PlanCandidate(
            title: "Airside plan with unknown queue",
            place: airside,
            segments: [
                PlanSegment(kind: .activity, title: "Recovery", duration: durationMetric(id: "activity", lower: 30, mode: 45, upper: 60)),
                PlanSegment(kind: .security, title: "Live transfer queue", duration: nil)
            ],
            entryAssessment: nil
        )

        let result = MonteCarloLayoverRecommendationEngine().assess(
            itinerary: itinerary,
            layover: layover,
            candidate: candidate,
            profile: .minimalDemo,
            snapshotRevision: "queue-missing-v1",
            seed: 10_003,
            now: anchor
        )

        XCTAssertEqual(result.status, .requiresConfirmation)
        XCTAssertNil(result.requiredMostLikelyMinutes)
        XCTAssertNil(result.probability)
        XCTAssertTrue(result.trace.unresolvedInputs.contains("Live transfer queue"))
    }

    func testExpiredQueueEstimateBlocksPositiveAirsideRecommendation() throws {
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)
        let layover = try XCTUnwrap(itinerary.layovers.first)
        let candidate = PlanCandidate(
            title: "Airside plan with stale queue",
            place: place(zone: .airside),
            segments: [
                PlanSegment(kind: .activity, title: "Recovery", duration: durationMetric(id: "fresh-activity", lower: 30, mode: 45, upper: 60)),
                PlanSegment(kind: .security, title: "Transfer queue", duration: durationMetric(id: "stale-queue", lower: 5, mode: 10, upper: 25, expiresAt: anchor))
            ],
            entryAssessment: nil
        )

        let result = MonteCarloLayoverRecommendationEngine().assess(
            itinerary: itinerary,
            layover: layover,
            candidate: candidate,
            profile: .minimalDemo,
            snapshotRevision: "queue-stale-v1",
            seed: 10_004,
            now: anchor
        )

        XCTAssertEqual(result.status, .requiresConfirmation)
        XCTAssertNil(result.probability)
        XCTAssertTrue(result.trace.unresolvedInputs.contains("Transfer queue freshness"))
    }

    func testInterAirportVisitCandidateSequencesTransferBeforeOptionalActivity() async throws {
        let itinerary = LongHaulReferenceScenario.hanedaToNaritaItinerary(anchor: anchor)
        let layover = try XCTUnwrap(itinerary.layovers.first)
        let options = try await TokyoInterAirportDemoTransferProvider().options(
            from: layover.airport,
            to: layover.onwardAirport,
            after: anchor
        )
        let transferPlan = InterAirportTransferPlanner().plan(options: options, requireAccessibility: false, now: anchor)
        let candidates = InterAirportCandidateFactory.candidates(
            layover: layover,
            transferPlan: transferPlan,
            entry: nil,
            anchor: anchor
        )
        let visit = try XCTUnwrap(candidates.first { $0.title.contains("nearby visit") })
        let transferIndex = try XCTUnwrap(visit.segments.firstIndex { $0.title == "Inter-airport transfer" })
        let activityIndex = try XCTUnwrap(visit.segments.firstIndex { $0.kind == .activity })

        XCTAssertLessThan(transferIndex, activityIndex)
        XCTAssertEqual(visit.place?.airportCode, "NRT")
        XCTAssertEqual(visit.place?.accessZone, .nearby)
        XCTAssertEqual(visit.latestReturnReference, transferPlan.selected?.lastService)
        XCTAssertNil(visit.segments.first { $0.kind == .border }?.duration)
        XCTAssertNil(visit.segments.first { $0.kind == .security }?.duration)
    }

    func testSafetyPolicyDerivesWorstCaseTrialsAndHonorsExactBoundaries() {
        let policy = SafetyPolicy.current
        XCTAssertEqual(policy.derivedWorstCaseTrialCount, 9_604)
        XCTAssertEqual(policy.simulationTrials, 10_000)
        XCTAssertGreaterThanOrEqual(policy.simulationTrials, policy.derivedWorstCaseTrialCount)

        let safeBoundary = ProbabilityInterval(estimate: 0.94, lower95: 0.90, upper95: 0.97, trials: 10_000)
        let belowNotRecommended = ProbabilityInterval(estimate: 0.65, lower95: 0.61, upper95: 0.699_999, trials: 10_000)
        let exactNotRecommendedBoundary = ProbabilityInterval(estimate: 0.67, lower95: 0.63, upper95: 0.70, trials: 10_000)

        XCTAssertEqual(policy.classification(for: safeBoundary, hasUnresolvedCriticalInputs: false), .safe)
        XCTAssertEqual(policy.classification(for: belowNotRecommended, hasUnresolvedCriticalInputs: false), .notRecommended)
        XCTAssertEqual(policy.classification(for: exactNotRecommendedBoundary, hasUnresolvedCriticalInputs: false), .tight)
        XCTAssertEqual(policy.classification(for: safeBoundary, hasUnresolvedCriticalInputs: true), .requiresConfirmation)
    }

    func testStableSnapshotSeedAndAssessmentAreExactlyReplayable() throws {
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)
        let layover = try XCTUnwrap(itinerary.layovers.first)
        let candidate = try XCTUnwrap(LongHaulReferenceScenario.candidates(layover: layover, entry: nil, anchor: anchor).first)
        let engine = MonteCarloLayoverRecommendationEngine()

        let first = engine.assess(
            itinerary: itinerary,
            layover: layover,
            candidate: candidate,
            profile: .minimalDemo,
            snapshotRevision: "snapshot-fixed-v7",
            seed: nil,
            now: anchor
        )
        let replay = engine.assess(
            itinerary: itinerary,
            layover: layover,
            candidate: candidate,
            profile: .minimalDemo,
            snapshotRevision: "snapshot-fixed-v7",
            seed: nil,
            now: anchor
        )

        XCTAssertEqual(first.trace.simulationSeed, replay.trace.simulationSeed)
        XCTAssertEqual(first.probability, replay.probability)
        XCTAssertEqual(first.status, replay.status)
        XCTAssertEqual(first.requiredMostLikelyMinutes, replay.requiredMostLikelyMinutes)
        XCTAssertEqual(first.latestReturnTime, replay.latestReturnTime)

        let differentRevisionSeed = StableSimulationSeed.snapshot(
            itineraryID: itinerary.id,
            inputRevision: itinerary.inputRevision,
            snapshotRevision: "snapshot-fixed-v8",
            policyVersion: SafetyPolicy.current.version
        )
        XCTAssertNotEqual(first.trace.simulationSeed, differentRevisionSeed)
    }

    func testReplayableGeneratorProducesIdenticalSequenceForNamedSeed() {
        let namedSeed: UInt64 = 0xA17_2026_0714
        var first = ReplayableRandomNumberGenerator(seed: namedSeed)
        var replay = ReplayableRandomNumberGenerator(seed: namedSeed)

        let firstSequence = (0..<32).map { _ in first.next() }
        let replaySequence = (0..<32).map { _ in replay.next() }

        XCTAssertEqual(firstSequence, replaySequence)
        XCTAssertEqual(first.state, replay.state)
    }

    func testUnsupportedScenarioLaunchesUseLiveModeWithoutFixtureState() {
        let context = AppLaunchContext.current(
            arguments: ["AirBorder", "--launch-mode", "demo", "--scenario", "hnd-nrt"]
        )
        XCTAssertEqual(context.mode, .live)
        XCTAssertNil(context.simulationSeed)
        XCTAssertNil(context.scenario)
    }

    func testCalculationTraceContainsEveryMetricSourceAndFormulaStep() throws {
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)
        let layover = try XCTUnwrap(itinerary.layovers.first)
        let candidate = try XCTUnwrap(LongHaulReferenceScenario.candidates(layover: layover, entry: nil, anchor: anchor).first)
        let expectedSourceIDs = Set(candidate.segments.compactMap { $0.duration?.sourceRecordID })

        for metric in candidate.segments.compactMap(\.duration) {
            XCTAssertFalse(metric.provider.isEmpty)
            XCTAssertFalse(metric.providerField.isEmpty)
            XCTAssertFalse(metric.sourceRecordID.isEmpty)
            XCTAssertFalse(metric.derivation.isEmpty)
            XCTAssertTrue(metric.derivation.allSatisfy { !$0.formula.isEmpty && !$0.result.isEmpty })
        }

        let result = MonteCarloLayoverRecommendationEngine().assess(
            itinerary: itinerary,
            layover: layover,
            candidate: candidate,
            profile: .minimalDemo,
            snapshotRevision: "provenance-v1",
            seed: 77_777,
            now: anchor
        )

        XCTAssertEqual(Set(result.trace.sourceRecordIDs), expectedSourceIDs)
        XCTAssertEqual(result.trace.policyVersion, SafetyPolicy.current.version)
        XCTAssertEqual(result.trace.simulationSeed, 77_777)
        XCTAssertTrue(result.trace.unresolvedInputs.isEmpty)
        XCTAssertTrue(result.trace.steps.contains { $0.label == "Available window" && $0.formula.contains("gate-close") })
        XCTAssertTrue(result.trace.steps.contains { $0.label == "Required time" })
        XCTAssertTrue(result.trace.steps.contains { $0.label == "On-time probability" && $0.formula.contains("Wilson 95%") })
    }

    func testDestinationWeatherSelectsOnwardArrivalAirport() {
        let active = Airport(iata: "HND", icao: "RJTT", name: "Haneda", city: "Tokyo", timeZone: "Asia/Tokyo")
        let destination = Airport(iata: "LAX", icao: "KLAX", name: "Los Angeles", city: "Los Angeles", timeZone: "America/Los_Angeles")
        let flight = Flight(
            id: "weather-destination-test",
            flightNumber: "NH106",
            airlineCode: "NH",
            airlineName: "ANA",
            origin: active,
            destination: destination,
            status: .scheduled,
            scheduledDeparture: anchor,
            estimatedDeparture: nil,
            actualDeparture: nil,
            scheduledArrival: anchor.addingTimeInterval(10 * 60 * 60),
            estimatedArrival: nil,
            actualArrival: nil,
            departureTerminal: "3",
            arrivalTerminal: nil,
            gate: nil,
            arrivalGate: nil,
            previousGate: nil,
            boardingStatus: nil,
            boardingGroup: nil,
            boardingTime: nil,
            delayMinutes: nil,
            aircraftType: nil,
            baggageClaim: nil,
            source: .demo
        )
        let selected = JourneyWeatherAirportSelector.destination(
            activeAirport: active,
            onwardLeg: ItineraryLeg(flight: flight)
        )
        XCTAssertEqual(selected?.iata, "LAX")
    }

    func testHNDOfficialFacilitiesExposeExpectedZonesAndOfficialSources() {
        let records = HNDOfficialFacilityRegistry.records
        let categories = Set(records.map { $0.place.category })

        XCTAssertTrue(categories.isSuperset(of: [.workPod, .transitHotel, .shower, .lounge, .hotel, .food, .attraction]))
        let workPod = records.first { $0.place.id == "hnd-work-pod" && $0.place.accessZone == .airportLandside }
        XCTAssertNotNil(workPod, "The official Terminal 3 work cubicles are in the general (landside) area")
        XCTAssertNotNil(records.first { $0.place.id == "hnd-airport-garden" && $0.place.accessZone == .airportLandside })
        XCTAssertNotNil(records.first { $0.place.id == "hnd-nearby-hotel" && $0.place.accessZone == .nearby })
        XCTAssertNotNil(records.first { $0.place.id == "tokyo-edo-koji-city-plan" && $0.place.accessZone == .city })
        XCTAssertTrue(records.allSatisfy { $0.place.airportCode == "HND" })
        XCTAssertTrue(records.allSatisfy { $0.place.officialSourceURL?.host == "tokyo-haneda.com" })
        let exactHoursIDs: Set<String> = ["hnd-work-pod", "hnd-transit-hotel", "hnd-shower"]
        let exactHoursRecords = records.filter { exactHoursIDs.contains($0.id) }
        XCTAssertEqual(exactHoursRecords.count, exactHoursIDs.count)
        XCTAssertTrue(exactHoursRecords.allSatisfy { !$0.hoursRequireConfirmation && $0.isOpen(at: anchor) != nil })

        let confirmationRequired = records.filter { !exactHoursIDs.contains($0.id) }
        XCTAssertTrue(confirmationRequired.allSatisfy { $0.hoursRequireConfirmation && $0.isOpen(at: anchor) == nil })
    }

    func testSyntheticOpeningWindowHandlesAirportLocalOvernightHours() {
        let overnight = OpeningWindow(
            weekdays: Set(1...7),
            startMinuteOfDay: 22 * 60,
            endMinuteOfDay: 2 * 60,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let record = AirportFacilityRecord(
            id: "synthetic-hours",
            place: place(zone: .airside),
            accessRestrictions: nil,
            openingWindows: [overnight],
            hoursRequireConfirmation: false,
            sourceUpdatedAt: anchor,
            verifiedAt: anchor
        )

        XCTAssertEqual(record.isOpen(at: isoDate("2026-07-14T13:30:00Z")), true, "22:30 at HND")
        XCTAssertEqual(record.isOpen(at: isoDate("2026-07-14T16:30:00Z")), true, "01:30 at HND after midnight")
        XCTAssertEqual(record.isOpen(at: isoDate("2026-07-14T18:00:00Z")), false, "03:00 at HND")
    }

    func testLegacyJourneyMigratesToVersionedItineraryCacheAndPersistsProfile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyJourney = ActiveJourney.demo(now: anchor)
        let legacyURL = directory.appendingPathComponent("journey-cache-v1.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(LegacyJourneyEnvelope(journey: legacyJourney)).write(to: legacyURL, options: .atomic)

        let cache = ItineraryCache(directory: directory)
        let migratedValue = await cache.loadItinerary()
        let migrated = try XCTUnwrap(migratedValue)
        XCTAssertEqual(migrated.id, legacyJourney.id)
        XCTAssertEqual(migrated.schemaVersion, Itinerary.currentSchemaVersion)
        XCTAssertEqual(migrated.legs.count, 1)
        XCTAssertEqual(migrated.legs.first?.flight.id, legacyJourney.flight.id)

        var profile = TravelerProfile.minimalDemo
        profile.nationalityCountryCode = "TH"
        profile.accessibilityNeeds = "Step-free route"
        try await cache.saveTravelerProfile(profile)
        try await cache.saveItinerary(migrated)

        let snapshotURL = directory.appendingPathComponent("itinerary-cache-v2.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL)) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, Itinerary.currentSchemaVersion)
        XCTAssertEqual(object["providerPolicyVersion"] as? String, ProviderPolicyRegistry.version)
        XCTAssertEqual(object["predictionModelVersion"] as? Int, 2)

        let reloaded = ItineraryCache(directory: directory)
        let persistedItinerary = await reloaded.loadItinerary()
        let persistedProfile = await reloaded.loadTravelerProfile()
        XCTAssertEqual(persistedItinerary?.legs.first?.flight.id, legacyJourney.flight.id)
        XCTAssertEqual(persistedProfile, profile)
    }

    func testProviderPolicyAllowsTrainingOnlyOnUserOwnedOutcomes() throws {
        let registry = ProviderPolicyRegistry.policies
        XCTAssertEqual(registry["user-outcomes"]?.trainingAllowed, true)
        XCTAssertEqual(registry.filter { $0.value.trainingAllowed }.map { $0.key }, ["user-outcomes"])

        for providerID in ["flight-data", "hotel-offers", "entry-requirements", "weatherkit", "gtfs-realtime", "google-places", "facility-registry"] {
            let policy = try XCTUnwrap(registry[providerID])
            XCTAssertFalse(policy.trainingAllowed, "\(providerID) payloads must not train the local model")
        }
        XCTAssertEqual(registry["entry-requirements"]?.cacheScope, .protectedLocal)
        XCTAssertEqual(registry["google-places"]?.cacheScope, .memory)
        XCTAssertEqual(registry["google-places"]?.persistentStorageAllowed, false)
    }

    func testTerminalRouterKeepsParetoTradeoffAndUsesLexicographicRouteMode() throws {
        let graph = paretoTradeoffGraph()
        var preferences = AccessibilityPreferences.default
        preferences.wheelchairRouting = false
        preferences.preferElevators = false

        let fastest = try TerminalRouter().route(in: graph, from: "start", to: "destination", mode: .fastest, preferences: preferences)
        let leastWalking = try TerminalRouter().route(in: graph, from: "start", to: "destination", mode: .leastWalking, preferences: preferences)

        XCTAssertEqual(fastest.edgeIDs, ["fast-1", "fast-2"])
        XCTAssertEqual(fastest.durationSeconds, 20, accuracy: 0.001)
        XCTAssertEqual(fastest.distanceMeters, 200, accuracy: 0.001)
        XCTAssertEqual(leastWalking.edgeIDs, ["short-1", "short-2"])
        XCTAssertEqual(leastWalking.durationSeconds, 40, accuracy: 0.001)
        XCTAssertEqual(leastWalking.distanceMeters, 100, accuracy: 0.001)
    }

    func testRouteManeuverComesFromSelectedGraphEdgeAndGeometry() throws {
        let nodes = [
            TerminalNode(id: "west", name: "West corridor", point: MapPoint(x: 0, y: 0), level: 1, kind: .corridor),
            TerminalNode(id: "junction", name: "Junction", point: MapPoint(x: 1, y: 0), level: 1, kind: .corridor),
            TerminalNode(id: "north", name: "North concourse", point: MapPoint(x: 1, y: 1), level: 1, kind: .corridor)
        ]
        let edges = [
            edge(id: "west-junction", from: "west", to: "junction", distance: 18, seconds: 15),
            edge(id: "junction-north", from: "junction", to: "north", distance: 42, seconds: 35)
        ]
        let graph = TerminalGraph(version: "maneuver-v1", nodes: nodes, edges: edges)
        let route = TerminalRoute(
            nodeIDs: ["west", "junction", "north"],
            edgeIDs: ["west-junction", "junction-north"],
            distanceMeters: 60,
            durationSeconds: 50,
            mode: .fastest
        )

        let maneuver = try XCTUnwrap(RouteManeuverBuilder().currentManeuver(graph: graph, route: route, currentNodeID: "junction"))
        XCTAssertEqual(maneuver.instruction, "Turn left toward North concourse")
        XCTAssertEqual(maneuver.destinationName, "North concourse")
        XCTAssertEqual(maneuver.distanceMeters, 42, accuracy: 0.001)
        XCTAssertEqual(maneuver.stepNumber, 2)
        XCTAssertEqual(maneuver.stepCount, 2)
        XCTAssertEqual(maneuver.kind, .left)
        XCTAssertEqual(maneuver.heading, .north)
        XCTAssertEqual(maneuver.systemImage, "arrow.turn.up.left")
    }

    func testRouteTurnBandsAndCompassHeadingsCoverRicherGuidance() {
        let builder = RouteManeuverBuilder()
        XCTAssertEqual(builder.turnKind(signedAngleDegrees: 0), .continueStraight)
        XCTAssertEqual(builder.turnKind(signedAngleDegrees: 16), .slightLeft)
        XCTAssertEqual(builder.turnKind(signedAngleDegrees: -16), .slightRight)
        XCTAssertEqual(builder.turnKind(signedAngleDegrees: 46), .left)
        XCTAssertEqual(builder.turnKind(signedAngleDegrees: -46), .right)
        XCTAssertEqual(builder.turnKind(signedAngleDegrees: 121), .sharpLeft)
        XCTAssertEqual(builder.turnKind(signedAngleDegrees: -121), .sharpRight)
        XCTAssertEqual(builder.turnKind(signedAngleDegrees: 165), .uTurn)

        XCTAssertEqual(CompassHeading(degrees: 0), .north)
        XCTAssertEqual(CompassHeading(degrees: 45), .northeast)
        XCTAssertEqual(CompassHeading(degrees: 90), .east)
        XCTAssertEqual(CompassHeading(degrees: 180), .south)
        XCTAssertEqual(CompassHeading(degrees: 225), .southwest)
        XCTAssertEqual(CompassHeading(degrees: 315), .northwest)
        XCTAssertEqual(CompassHeading(degrees: -45), .northwest)
    }
}

private extension LongHaulExpansionTests {
    struct LegacyJourneyEnvelope: Codable {
        let journey: ActiveJourney?
    }

    func makeFourLegDateLineItinerary() -> Itinerary {
        let bkk = airport("BKK", city: "Bangkok", timeZone: "Asia/Bangkok")
        let hnd = airport("HND", city: "Tokyo", timeZone: "Asia/Tokyo")
        let lax = airport("LAX", city: "Los Angeles", timeZone: "America/Los_Angeles")
        let jfk = airport("JFK", city: "New York", timeZone: "America/New_York")
        let cdg = airport("CDG", city: "Paris", timeZone: "Europe/Paris")

        let leg1Arrival = isoDate("2026-07-14T00:00:00Z")
        let leg2Departure = isoDate("2026-07-14T03:00:00Z")
        let leg2Arrival = isoDate("2026-07-14T12:30:00Z")
        let leg3Departure = isoDate("2026-07-14T17:00:00Z")
        let leg3Arrival = isoDate("2026-07-15T02:30:00Z")
        let leg4Departure = isoDate("2026-07-15T05:30:00Z")

        let legs = [
            ItineraryLeg(
                id: UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!,
                flight: flight(id: "leg-bkk-hnd", origin: bkk, destination: hnd, departure: isoDate("2026-07-13T18:00:00Z"), arrival: leg1Arrival),
                onBlockTime: dateMetric(leg1Arrival, id: "leg1-on-block")
            ),
            ItineraryLeg(
                id: UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!,
                flight: flight(id: "leg-hnd-lax", origin: hnd, destination: lax, departure: leg2Departure, arrival: leg2Arrival),
                onBlockTime: dateMetric(leg2Arrival, id: "leg2-on-block"),
                gateCloseTime: dateMetric(leg2Departure.addingTimeInterval(-35 * 60), id: "leg2-gate-close")
            ),
            ItineraryLeg(
                id: UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!,
                flight: flight(id: "leg-lax-jfk", origin: lax, destination: jfk, departure: leg3Departure, arrival: leg3Arrival),
                onBlockTime: dateMetric(leg3Arrival, id: "leg3-on-block"),
                gateCloseTime: dateMetric(leg3Departure.addingTimeInterval(-30 * 60), id: "leg3-gate-close")
            ),
            ItineraryLeg(
                id: UUID(uuidString: "A0000000-0000-4000-8000-000000000004")!,
                flight: flight(id: "leg-jfk-cdg", origin: jfk, destination: cdg, departure: leg4Departure, arrival: isoDate("2026-07-15T12:30:00Z")),
                gateCloseTime: dateMetric(leg4Departure.addingTimeInterval(-40 * 60), id: "leg4-gate-close")
            )
        ]
        return Itinerary(
            id: UUID(uuidString: "A0000000-0000-4000-8000-000000000010")!,
            inputRevision: 7,
            title: "Bangkok to Paris via Tokyo, Los Angeles, and New York",
            legs: legs,
            createdAt: anchor,
            updatedAt: anchor
        )
    }

    func completeCandidate(zone: AccessZone, entry: EntryAssessment?, requiresLandsideExit: Bool = false) -> PlanCandidate {
        PlanCandidate(
            id: UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!,
            title: "Complete deterministic candidate",
            place: place(zone: zone),
            segments: [
                PlanSegment(kind: .outboundTravel, title: "Outbound", duration: durationMetric(id: "outbound", lower: 15, mode: 20, upper: 30)),
                PlanSegment(kind: .activity, title: "Activity", duration: durationMetric(id: "activity", lower: 30, mode: 45, upper: 60)),
                PlanSegment(kind: .returnTravel, title: "Return", duration: durationMetric(id: "return", lower: 15, mode: 20, upper: 30)),
                PlanSegment(kind: .security, title: "Security", duration: durationMetric(id: "security", lower: 10, mode: 15, upper: 25)),
                PlanSegment(kind: .terminalRoute, title: "Gate route", duration: durationMetric(id: "gate-route", lower: 5, mode: 8, upper: 12))
            ],
            entryAssessment: entry,
            requiresLandsideExit: requiresLandsideExit
        )
    }

    func confirmedProfile() -> TravelerProfile {
        var profile = TravelerProfile.minimalDemo
        profile.hasConfirmedOfficialEntryRules = true
        return profile
    }

    func entryAssessment(expiresAt: Date, status: EntryAssessmentStatus) -> EntryAssessment {
        EntryAssessment(
            status: status,
            summary: "Synthetic entry rule for deterministic unit tests",
            provider: "Unit-test provider",
            sourceRecordID: "entry-test-record",
            observedAt: anchor.addingTimeInterval(-3_600),
            receivedAt: anchor.addingTimeInterval(-3_600),
            expiresAt: expiresAt,
            officialVerificationURLs: [URL(string: "https://www.mofa.go.jp/j_info/visit/visa/short/novisa.html")!],
            isDemo: true
        )
    }

    func entryQuery(nationality: String) -> EntryRequirementQuery {
        EntryRequirementQuery(
            nationalityCountryCode: nationality,
            residenceCountryCode: nationality,
            passportType: .ordinary,
            declaredAuthorizations: [],
            originCountryCode: "TH",
            transitCountryCode: "JP",
            onwardCountryCode: "US",
            originAirportCode: "BKK",
            transitArrivalAirportCode: "HND",
            onwardDepartureAirportCode: "NRT",
            onwardDestinationAirportCode: "LAX",
            originDeparture: anchor.addingTimeInterval(-7_200),
            arrival: anchor.addingTimeInterval(-3_600),
            departure: anchor.addingTimeInterval(3_600),
            onwardArrival: anchor.addingTimeInterval(39_600),
            originTimeZoneIdentifier: "Asia/Bangkok",
            transitTimeZoneIdentifier: "Asia/Tokyo",
            onwardTimeZoneIdentifier: "America/Los_Angeles",
            plannedLandsideExit: true,
            luggage: .checkedThrough,
            purpose: .transit
        )
    }

    func place(zone: AccessZone) -> LayoverPlace {
        LayoverPlace(
            id: "place-\(zone.rawValue)",
            name: "Synthetic \(zone.title) place",
            airportCode: "HND",
            terminal: "3",
            category: .attraction,
            accessZone: zone,
            latitude: nil,
            longitude: nil,
            summary: "Deterministic unit-test fixture",
            bookingURL: nil,
            officialSourceURL: URL(string: "https://tokyo-haneda.com/en/service/facilities/index.html"),
            dataMode: .demo
        )
    }

    func durationMetric(id: String, lower: Double, mode: Double, upper: Double, expiresAt: Date? = nil) -> SourcedMetric<EstimateDistribution> {
        SourcedMetric(
            value: EstimateDistribution(lower: lower, mostLikely: mode, upper: upper, unit: .minutes),
            unit: .minutes,
            provider: "Deterministic unit-test fixture",
            providerField: id,
            sourceRecordID: "source-\(id)",
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: expiresAt,
            uncertainty: "Synthetic triangular distribution",
            derivation: [
                DerivationStep(
                    label: id,
                    formula: "unit-test lower / most-likely / upper",
                    inputRecordIDs: ["source-\(id)"],
                    result: "\(lower) / \(mode) / \(upper) min"
                )
            ]
        )
    }

    func dateMetric(_ date: Date, id: String) -> SourcedMetric<Date> {
        SourcedMetric(
            value: date,
            unit: .dateTime,
            provider: "Deterministic unit-test fixture",
            providerField: id,
            sourceRecordID: id,
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: nil,
            uncertainty: nil,
            derivation: [DerivationStep(label: id, formula: "fixed ISO-8601 fixture", inputRecordIDs: [id], result: date.ISO8601Format())]
        )
    }

    func airport(_ code: String, city: String, timeZone: String) -> Airport {
        Airport(iata: code, icao: nil, name: "\(city) Airport", city: city, timeZone: timeZone)
    }

    func flight(id: String, origin: Airport, destination: Airport, departure: Date, arrival: Date) -> Flight {
        Flight(
            id: id,
            flightNumber: id,
            airlineCode: "TS",
            airlineName: "Test Scenario",
            origin: origin,
            destination: destination,
            status: .scheduled,
            scheduledDeparture: departure,
            estimatedDeparture: departure,
            actualDeparture: nil,
            scheduledArrival: arrival,
            estimatedArrival: arrival,
            actualArrival: nil,
            departureTerminal: nil,
            arrivalTerminal: nil,
            gate: nil,
            arrivalGate: nil,
            previousGate: nil,
            boardingStatus: nil,
            boardingGroup: nil,
            boardingTime: nil,
            delayMinutes: nil,
            aircraftType: nil,
            baggageClaim: nil,
            source: ProviderMetadata(
                name: "Deterministic unit-test fixture",
                providerRecordID: id,
                providerUpdatedAt: anchor,
                receivedAt: anchor,
                isLive: false,
                isDemo: true
            )
        )
    }

    func localComponents(_ date: Date, timeZone: String) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirportXRLongHaulTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func paretoTradeoffGraph() -> TerminalGraph {
        TerminalGraph(
            version: "pareto-tradeoff-v1",
            nodes: [
                TerminalNode(id: "start", name: "Start", point: MapPoint(x: 0, y: 0), level: 1, kind: .marker),
                TerminalNode(id: "fast", name: "Fast path", point: MapPoint(x: 1, y: 1), level: 1, kind: .corridor),
                TerminalNode(id: "short", name: "Short path", point: MapPoint(x: 1, y: -1), level: 1, kind: .corridor),
                TerminalNode(id: "destination", name: "Destination", point: MapPoint(x: 2, y: 0), level: 1, kind: .gate)
            ],
            edges: [
                edge(id: "fast-1", from: "start", to: "fast", distance: 100, seconds: 10),
                edge(id: "fast-2", from: "fast", to: "destination", distance: 100, seconds: 10),
                edge(id: "short-1", from: "start", to: "short", distance: 50, seconds: 20),
                edge(id: "short-2", from: "short", to: "destination", distance: 50, seconds: 20)
            ]
        )
    }

    func edge(id: String, from: String, to: String, distance: Double, seconds: Double) -> TerminalEdge {
        TerminalEdge(
            id: id,
            from: from,
            to: to,
            distanceMeters: distance,
            walkingSeconds: seconds,
            wheelchairAccessible: true,
            hasStairs: false,
            hasEscalator: false,
            hasElevator: false,
            narrowPassage: false,
            temporarilyClosed: false,
            crowdPenalty: 0,
            levelChange: 0,
            directionComplexity: 0
        )
    }
}
