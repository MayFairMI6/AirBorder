import Foundation
import XCTest
@testable import AirBorder

final class TransitNotificationPredictionTests: XCTestCase {
    func testGTFSParsingSupportsQuotedNamesAndAccessibility() throws {
        let csv = """
        stop_id,stop_name,stop_lat,stop_lon,wheelchair_boarding
        A1,"Airport, Terminal 2",40.6413,-73.7781,1
        """
        let stops = try GTFSService().parseStops(csv)
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops[0].name, "Airport, Terminal 2")
        XCTAssertEqual(stops[0].wheelchairBoarding, 1)
    }

    func testGTFSStopTimesParsing() throws {
        let csv = """
        trip_id,arrival_time,departure_time,stop_id,stop_sequence
        T1,25:05:00,25:06:00,A1,2
        """
        let times = try GTFSService().parseStopTimes(csv)
        XCTAssertEqual(times.first, GTFSStopTime(tripID: "T1", arrivalTime: "25:05:00", departureTime: "25:06:00", stopID: "A1", stopSequence: 2))
    }

    func testLayoverSafetyNeverRecommendsUnsafeDeparture() {
        let now = Date(timeIntervalSince1970: 1_721_000_000)
        let assessment = LayoverSafetyService().assess(LayoverSafetyInput(
            inboundArrival: now,
            boardingTime: now.addingTimeInterval(3 * 3600),
            immigrationMinutes: 35,
            baggageMinutes: 20,
            airportExitMinutes: 15,
            outboundTransitMinutes: 45,
            activityMinutes: 60,
            returnTransitMinutes: 45,
            securityMinutes: 40,
            terminalTransferMinutes: 10,
            accessibilityImpactMinutes: 10,
            safetyBufferMinutes: 30
        ))
        XCTAssertEqual(assessment.safety, .notRecommended)
        XCTAssertLessThan(assessment.remainingMarginMinutes, 0)
    }

    func testTransitPlannerFiltersForAccessibility() async throws {
        let options = try await BundledTransitDataProvider().options(from: "JFK", to: "Manhattan", at: Date())
        let ranked = TransitRoutePlanner().ranked(options, requireAccessibility: true, preferLowWalking: true)
        XCTAssertTrue(ranked.allSatisfy { $0.wheelchairAccessible == true })
        XCTAssertFalse(ranked.contains { $0.mode == .taxi })
    }

    func testNotificationGenerationIncludesGateDelayAndCancellation() {
        let now = Date(timeIntervalSince1970: 1_721_000_000)
        let previous = makeFlight(now: now, gate: "C8", status: .scheduled, delayMinutes: 0)
        var current = makeFlight(now: now, gate: "C12", previousGate: "C8", status: .cancelled, delayMinutes: 30)
        current.boardingTime = now.addingTimeInterval(20 * 60)
        let assessment = JourneyAssessment(urgency: .urgent, operationalStatus: .cancelled, freshness: .live, localizationConfidence: .high, alerts: [.gateChange, .cancellation], message: "Cancelled", leaveBy: nil)
        let plans = JourneyNotificationPlanner().plans(previous: previous, current: current, journeyID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, assessment: assessment, now: now)
        let kinds = Set(plans.map(\.kind))
        XCTAssertTrue(kinds.contains(.gateChange))
        XCTAssertTrue(kinds.contains(.significantDelay))
        XCTAssertTrue(kinds.contains(.cancellation))
        XCTAssertTrue(kinds.contains(.leaveNow))
        XCTAssertEqual(Set(plans.map(\.id)).count, plans.count)
    }

    func testOnDevicePredictionLearnsDeduplicatesDisablesAndErases() async throws {
        let directory = try temporaryDirectory()
        let now = Date(timeIntervalSince1970: 1_721_000_000)
        let scheduled = now.addingTimeInterval(3600)
        let resolved = makeFlight(now: now, actualDeparture: scheduled.addingTimeInterval(20 * 60), id: "resolved-1")
        let service = OnDevicePredictionService(directory: directory, learningEnabled: true, now: { now })

        await service.learn(from: [resolved])
        var prediction = await service.predictDelay(for: resolved)
        XCTAssertEqual(prediction.sampleCount, 0, "Commercial provider records must not train the local model")
        XCTAssertNil(prediction.expectedDelayMinutes)
        XCTAssertEqual(prediction.source, .unavailable)

        await service.learnUserReportedDelay(actualMinutes: 20, flight: resolved)
        prediction = await service.predictDelay(for: resolved)
        XCTAssertEqual(prediction.sampleCount, 1)
        XCTAssertEqual(prediction.expectedDelayMinutes, 20)
        XCTAssertEqual(prediction.source, .onDeviceLearning)

        await service.setLearningEnabled(false)
        let second = makeFlight(now: now, actualDeparture: scheduled.addingTimeInterval(40 * 60), id: "resolved-2")
        await service.learn(from: [second])
        prediction = await service.predictDelay(for: resolved)
        XCTAssertEqual(prediction.sampleCount, 1)

        await service.eraseLearnedModel()
        prediction = await service.predictDelay(for: resolved)
        XCTAssertEqual(prediction.sampleCount, 0)
        XCTAssertEqual(prediction.source, .unavailable)
    }

    func testWeatherMatchedDelayOutlookUsesOnlySameWeatherContext() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_721_000_000)
        let flight = makeFlight(now: now, id: "weather-delay-flight")
        let service = OnDevicePredictionService(directory: directory, learningEnabled: true, now: { now })
        let rain = "departure:rain|wind-band:2|destination:cloudy|wind-band:1"
        let clear = "departure:clear|wind-band:0|destination:clear|wind-band:0"

        await service.learnUserReportedDelay(actualMinutes: 38, flight: flight, weatherContext: rain)

        let matching = await service.predictDelay(for: flight, weatherContext: rain)
        XCTAssertEqual(matching.expectedDelayMinutes, 38)
        XCTAssertEqual(matching.sampleCount, 1)

        let differentWeather = await service.predictDelay(for: flight, weatherContext: clear)
        XCTAssertNil(differentWeather.expectedDelayMinutes)
        XCTAssertEqual(differentWeather.sampleCount, 0)
    }

    func testExplicitLicensedLivePolicyLearnsResolvedOutcomeAndDeduplicatesRefreshes() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_721_000_000)
        let scheduled = now.addingTimeInterval(3600)
        var resolved = makeFlight(
            now: now,
            actualDeparture: scheduled.addingTimeInterval(24 * 60),
            id: "licensed-record-1"
        )
        let policyVersion = "deterministic-test-policy-v1"
        let policyID = "licensed-test-flight-provider"
        resolved.source = ProviderMetadata(
            name: "Licensed test provider",
            providerRecordID: "provider-record-1",
            providerUpdatedAt: now,
            receivedAt: now,
            isLive: true,
            isDemo: false,
            providerPolicyID: policyID,
            providerPolicyVersion: policyVersion,
            providerTrainingAllowed: true,
            providerTrainingPurposes: [.flightDelayOutcome]
        )
        let policy = ProviderPolicy(
            id: policyID,
            cacheScope: .licenseDependent,
            expirySource: .providerContract,
            persistentStorageAllowed: false,
            redistributionAllowed: false,
            permittedTrainingPurposes: [.flightDelayOutcome],
            attribution: "Deterministic test fixture only",
            licenseURL: nil
        )
        let predictor = OnDevicePredictionService(directory: directory, learningEnabled: true, now: { now })
        let repository = FlightRepository(
            providers: [StubFlightProvider(id: "test-adapter", behavior: .flights([resolved]))],
            cache: InMemoryFlightCache(),
            predictionLearning: predictor,
            providerPolicyResolver: ProviderPolicyCatalog(version: policyVersion, policies: [policyID: policy]),
            now: { now }
        )
        let query = FlightQuery(airlineCode: "AX", flightNumber: "204", date: now)

        _ = try await repository.search(query: query)
        _ = try await repository.search(query: query)

        let prediction = await predictor.predictDelay(for: resolved)
        XCTAssertEqual(prediction.sampleCount, 1, "The stable provider record must be learned exactly once across refreshes")
        XCTAssertEqual(prediction.expectedDelayMinutes, 24)
        XCTAssertEqual(prediction.source, .onDeviceLearning)
    }

    func testProviderLearningIsDeniedWhenExactUseOrSourcePolicyDoesNotPermitIt() async throws {
        let now = Date(timeIntervalSince1970: 1_721_000_000)
        let scheduled = now.addingTimeInterval(3600)
        var resolved = makeFlight(
            now: now,
            actualDeparture: scheduled.addingTimeInterval(24 * 60),
            id: "forbidden-record-1"
        )
        let policyVersion = "deterministic-test-policy-v1"
        let policyID = "restricted-test-flight-provider"
        resolved.source = ProviderMetadata(
            name: "Restricted test provider",
            providerRecordID: "provider-record-2",
            providerUpdatedAt: now,
            receivedAt: now,
            isLive: true,
            isDemo: false,
            providerPolicyID: policyID,
            providerPolicyVersion: policyVersion,
            providerTrainingAllowed: true,
            providerTrainingPurposes: [.flightDelayOutcome]
        )
        let transitOnlyPolicy = ProviderPolicy(
            id: policyID,
            cacheScope: .licenseDependent,
            expirySource: .providerContract,
            persistentStorageAllowed: false,
            redistributionAllowed: false,
            permittedTrainingPurposes: [.transitDurationOutcome],
            attribution: "Deterministic test fixture only",
            licenseURL: nil
        )
        let transitOnlyCatalog = ProviderPolicyCatalog(version: policyVersion, policies: [policyID: transitOnlyPolicy])
        XCTAssertNil(transitOnlyCatalog.trainingAuthorization(
            adapterProviderID: "test-adapter",
            source: resolved.source,
            purpose: .flightDelayOutcome
        ), "A broad training flag cannot substitute for exact-use permission in the bundled policy")

        let locallyAllowedPolicy = ProviderPolicy(
            id: policyID,
            cacheScope: .licenseDependent,
            expirySource: .providerContract,
            persistentStorageAllowed: false,
            redistributionAllowed: false,
            permittedTrainingPurposes: [.flightDelayOutcome],
            attribution: "Deterministic test fixture only",
            licenseURL: nil
        )
        let sourceDenied = ProviderMetadata(
            name: resolved.source.name,
            providerRecordID: resolved.source.providerRecordID,
            providerUpdatedAt: resolved.source.providerUpdatedAt,
            receivedAt: resolved.source.receivedAt,
            isLive: true,
            isDemo: false,
            providerPolicyID: policyID,
            providerPolicyVersion: policyVersion,
            providerTrainingAllowed: false,
            providerTrainingPurposes: []
        )
        XCTAssertNil(ProviderPolicyCatalog(
            version: policyVersion,
            policies: [policyID: locallyAllowedPolicy]
        ).trainingAuthorization(
            adapterProviderID: "test-adapter",
            source: sourceDenied,
            purpose: .flightDelayOutcome
        ), "A local policy cannot override a source response that denies training")

        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let predictor = OnDevicePredictionService(directory: directory, learningEnabled: true, now: { now })
        let repository = FlightRepository(
            providers: [StubFlightProvider(id: "test-adapter", behavior: .flights([resolved]))],
            cache: InMemoryFlightCache(),
            predictionLearning: predictor,
            providerPolicyResolver: transitOnlyCatalog,
            now: { now }
        )

        _ = try await repository.search(query: FlightQuery(airlineCode: "AX", flightNumber: "204", date: now))

        let prediction = await predictor.predictDelay(for: resolved)
        XCTAssertEqual(prediction.sampleCount, 0)
        XCTAssertNil(prediction.expectedDelayMinutes)
        XCTAssertEqual(prediction.source, .unavailable)
    }

    func testWalkingTimePersonalization() async throws {
        let service = OnDevicePredictionService(directory: try temporaryDirectory(), now: { Date(timeIntervalSince1970: 1_721_000_000) })
        await service.learnWalkingTime(actualMinutes: 12, routeMode: .accessible, terminalVersion: "T2-v1")
        await service.learnWalkingTime(actualMinutes: 10, routeMode: .accessible, terminalVersion: "T2-v1")
        let prediction = await service.predictWalkingTime(baselineMinutes: 9, routeMode: .accessible, terminalVersion: "T2-v1")
        XCTAssertEqual(prediction.expectedMinutes, 11)
        XCTAssertEqual(prediction.sampleCount, 2)
    }
}
