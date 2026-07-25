import Foundation
import XCTest
@testable import AirBorder

private enum OperationalIntelligenceTestError: Error {
    case unavailable
}

private struct StubDelayFeatureProvider: FlightDelayFeatureProvider {
    let providerID = "delay-feature-test"
    let snapshot: FlightDelayFeatureSnapshot

    func features(for flight: Flight, at date: Date) async throws -> FlightDelayFeatureSnapshot {
        snapshot
    }
}

private struct StubDelayModel: FlightDelayModel {
    let descriptor: FlightDelayModelDescriptor
    let output: FlightDelayModelOutput
    var shouldFail = false

    func predict(
        flight: Flight,
        features: FlightDelayFeatureSnapshot,
        at date: Date
    ) async throws -> FlightDelayModelOutput {
        if shouldFail { throw OperationalIntelligenceTestError.unavailable }
        return output
    }
}

private struct StubAirlineFactsProvider: AirlineCommercialFactsProvider {
    let providerID = "airline-facts-test"
    let snapshot: AirlineCommercialFactsSnapshot

    func facts(
        for query: AirlineCommercialFactsQuery,
        at date: Date
    ) async throws -> AirlineCommercialFactsSnapshot {
        snapshot
    }
}

private struct StubFlightOfferProvider: PricedFlightOfferProvider {
    let providerID = "offer-test"
    let response: [SourcedAirlineFact<PricedFlightOffer>]

    func offers(
        for query: FlightOfferSearchQuery,
        at date: Date
    ) async throws -> [SourcedAirlineFact<PricedFlightOffer>] {
        response
    }
}

private struct StubBookingHandoffProvider: ExternalBookingHandoffProvider {
    let providerID = "handoff-test"
    let response: SourcedAirlineFact<ExternalBookingHandoff>

    func handoff(
        for offer: SourcedAirlineFact<PricedFlightOffer>,
        at date: Date
    ) async throws -> SourcedAirlineFact<ExternalBookingHandoff> {
        response
    }
}

private struct StubConnectionBaggageProvider: ConnectionBaggageProvider {
    let providerID = "connection-baggage-test"
    let response: SourcedAirlineFact<ConnectionBaggageHandling>

    func baggageHandling(
        for query: ConnectionBaggageQuery,
        at date: Date
    ) async throws -> SourcedAirlineFact<ConnectionBaggageHandling> {
        response
    }
}

final class FlightOperationalIntelligenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_784_000_000)

    func testDelayPredictionIsUnavailableWhenNoModelIsConfigured() async {
        let flight = makeFlight(now: now)
        let provider = StubDelayFeatureProvider(snapshot: snapshot(flightID: flight.id))

        let result = await FlightDelayContextService(featureProvider: provider)
            .prediction(for: flight, at: now)

        XCTAssertEqual(result.availability, .unavailable)
        XCTAssertEqual(result.unavailableReason, .modelNotConfigured)
        XCTAssertNil(result.distribution)
        XCTAssertNil(result.expiresAt)
    }

    func testStaleRequiredFeatureBlocksPrediction() async {
        let flight = makeFlight(now: now)
        let kind = FlightDelayFeatureKind.departureWindGust
        let stale = feature(
            kind: kind,
            value: 18,
            unit: .knots,
            expiresAt: now
        )
        let staleSnapshot = FlightDelayFeatureSnapshot(
            flightID: flight.id,
            revision: "stale-test",
            assembledAt: now,
            features: [kind: stale]
        )
        let model = delayModel(
            flightID: flight.id,
            requiredFeatures: [kind],
            usedFeatures: [kind]
        )

        let result = await FlightDelayContextService(
            featureProvider: StubDelayFeatureProvider(snapshot: staleSnapshot),
            model: model
        ).prediction(for: flight, at: now)

        XCTAssertEqual(result.availability, .unavailable)
        XCTAssertEqual(result.unavailableReason, .staleRequiredFeatures)
        XCTAssertEqual(result.staleFeatures, [kind])
        XCTAssertNil(result.distribution)
    }

    func testWeatherCongestionAndRotationDistributionFeedsLayoverWithoutReplacingOfficialStatus() async {
        var flight = makeFlight(now: now, status: .delayed, delayMinutes: 31)
        flight.source = ProviderMetadata(
            name: "Official status test provider",
            providerRecordID: "official-flight-record",
            providerUpdatedAt: now,
            receivedAt: now,
            isLive: true,
            isDemo: false
        )
        let kinds: Set<FlightDelayFeatureKind> = [
            .departureWindGust,
            .departureAirportDelay,
            .inboundAircraftArrivalDelay
        ]
        let features = [
            FlightDelayFeatureKind.departureWindGust: feature(
                kind: .departureWindGust,
                value: 24,
                unit: .knots
            ),
            FlightDelayFeatureKind.departureAirportDelay: feature(
                kind: .departureAirportDelay,
                value: 16,
                unit: .minutes
            ),
            FlightDelayFeatureKind.inboundAircraftArrivalDelay: feature(
                kind: .inboundAircraftArrivalDelay,
                value: 27,
                unit: .minutes
            )
        ]
        let sourceSnapshot = FlightDelayFeatureSnapshot(
            flightID: flight.id,
            revision: "weather-congestion-rotation-v1",
            assembledAt: now,
            features: features
        )
        let model = delayModel(
            flightID: flight.id,
            requiredFeatures: kinds,
            usedFeatures: kinds
        )

        let prediction = await FlightDelayContextService(
            featureProvider: StubDelayFeatureProvider(snapshot: sourceSnapshot),
            model: model
        ).prediction(for: flight, at: now)
        let layoverInput = prediction.layoverScenarioInput(officialFlight: flight)

        XCTAssertEqual(prediction.availability, .available)
        XCTAssertTrue(prediction.distribution?.isValid == true)
        XCTAssertEqual(Set(prediction.sourceRecordIDs), Set(features.values.map(\.sourceRecordID)))
        XCTAssertEqual(layoverInput.officialStatus, .delayed)
        XCTAssertEqual(layoverInput.officialEffectiveArrival, flight.effectiveArrival)
        XCTAssertEqual(layoverInput.officialProviderName, "Official status test provider")
        XCTAssertEqual(layoverInput.predictionRole, .scenarioContextOnly)
        XCTAssertEqual(layoverInput.predictedArrivalDelay, prediction.distribution)
    }

    func testCrossingDelayQuantilesAreRejected() async {
        let flight = makeFlight(now: now)
        let kind = FlightDelayFeatureKind.arrivalAirportDelay
        let sourceSnapshot = FlightDelayFeatureSnapshot(
            flightID: flight.id,
            revision: "invalid-quantiles",
            assembledAt: now,
            features: [kind: feature(kind: kind, value: 8, unit: .minutes)]
        )
        let descriptor = descriptor(requiredFeatures: [kind])
        let invalidDistribution = FlightDelayDistribution(
            target: .arrivalDelayMinutes,
            quantiles: [
                DelayQuantile(probability: 0.1, minutes: 20),
                DelayQuantile(probability: 0.9, minutes: 10)
            ],
            meanMinutes: 15,
            exceedanceProbabilities: []
        )
        let model = StubDelayModel(
            descriptor: descriptor,
            output: FlightDelayModelOutput(
                flightID: flight.id,
                distribution: invalidDistribution,
                usedFeatures: [kind],
                generatedAt: now,
                expiresAt: now.addingTimeInterval(600),
                derivation: []
            )
        )

        let result = await FlightDelayContextService(
            featureProvider: StubDelayFeatureProvider(snapshot: sourceSnapshot),
            model: model
        ).prediction(for: flight, at: now)

        XCTAssertFalse(invalidDistribution.isValid)
        XCTAssertEqual(result.availability, .unavailable)
        XCTAssertEqual(result.unavailableReason, .invalidDistribution)
        XCTAssertNil(result.distribution)
    }

    func testDepartureDelayPredictionIsNotSilentlyUsedAsArrivalLayoverDelay() async {
        let flight = makeFlight(now: now)
        let prediction = FlightDelayPrediction(
            flightID: flight.id,
            availability: .available,
            unavailableReason: nil,
            distribution: validDistribution(target: .departureDelayMinutes),
            model: descriptor(requiredFeatures: [], target: .departureDelayMinutes),
            featureRevision: "departure-only",
            generatedAt: now,
            expiresAt: now.addingTimeInterval(600),
            sourceRecordIDs: ["source"],
            missingFeatures: [],
            staleFeatures: [],
            trace: [],
            advisory: "Test"
        )

        let input = prediction.layoverScenarioInput(officialFlight: flight)

        XCTAssertNil(input.predictedArrivalDelay)
        XCTAssertEqual(input.predictionAvailability, .unavailable)
        XCTAssertEqual(input.unavailableReason, .targetNotApplicableToLayover)
        XCTAssertEqual(input.officialStatus, flight.status)
    }

    func testSeatMapAndFareInventoryCannotConfirmOversaleOrGuaranteeBinSpace() {
        let flight = makeFlight(now: now)
        let seat = fact(
            SeatAvailabilityObservation(
                state: .travelerSeatConfirmed,
                observedAvailableSeatCount: 12,
                assignedSeat: "18A",
                cabinOrBookingClass: "Economy"
            ),
            verification: .seatMapProxy,
            field: "seatAvailabilityStatus"
        )
        let overbooking = fact(
            OverbookingObservation(
                state: .airlineConfirmedNotOversold,
                note: "Derived from sale inventory in a test adapter"
            ),
            verification: .fareInventoryProxy,
            field: "bookingClassInventory"
        )
        let binSpace = fact(
            CabinBinSpaceObservation(
                state: .airlineGuaranteedForTraveler,
                probability: 1,
                explicitlyGuaranteedByAirline: true,
                note: "Invalid inference from open seats"
            ),
            verification: .seatMapProxy,
            field: "openSeats"
        )
        let snapshot = AirlineCommercialFactsSnapshot(
            flightID: flight.id,
            revision: "proxy-safety-test",
            baggageAllowance: nil,
            seatAvailability: seat,
            overbooking: overbooking,
            cabinBinSpace: binSpace
        )

        let assessment = AirlineCapacityNormalizer().normalize(snapshot, at: now)

        XCTAssertEqual(assessment.seatAvailability?.value.state, .seatMapObserved)
        XCTAssertNil(assessment.seatAvailability?.value.assignedSeat)
        XCTAssertEqual(assessment.overbooking?.value.state, .possibleProxySignal)
        XCTAssertEqual(assessment.cabinBinSpace?.value.state, .unknown)
        XCTAssertFalse(assessment.cabinBinSpace?.value.explicitlyGuaranteedByAirline == true)
    }

    func testVerifiedPNRBaggageRemainsTravelerSpecificWhileOtherFactsRemainUnknown() {
        let flight = makeFlight(now: now)
        let allowance = TravelerBaggageAllowance(
            appliesToTicketedTraveler: true,
            limits: [
                BaggageLimit(
                    category: .cabinBag,
                    pieceCount: 1,
                    maximumWeightKilograms: 10,
                    maximumDimensions: nil
                )
            ],
            conditions: ["Operating-carrier confirmation required after itinerary changes"]
        )
        let snapshot = AirlineCommercialFactsSnapshot(
            flightID: flight.id,
            revision: "pnr-baggage-test",
            baggageAllowance: fact(
                allowance,
                verification: .verifiedAirlinePNR,
                field: "order.baggageAllowance"
            ),
            seatAvailability: nil,
            overbooking: nil,
            cabinBinSpace: nil
        )

        let assessment = AirlineCapacityNormalizer().normalize(snapshot, at: now)

        XCTAssertEqual(assessment.availability, .partial)
        XCTAssertTrue(assessment.baggageAllowance?.value.appliesToTicketedTraveler == true)
        XCTAssertEqual(assessment.baggageAllowance?.value.limits.first?.maximumWeightKilograms, 10)
        XCTAssertNil(assessment.overbooking)
        XCTAssertNil(assessment.cabinBinSpace)
    }

    func testNDCOfferAllowanceIsNotPromotedToTicketedTravelerFact() {
        let flight = makeFlight(now: now)
        let quoted = TravelerBaggageAllowance(
            appliesToTicketedTraveler: true,
            limits: [BaggageLimit(category: .checkedBag, pieceCount: 1, maximumWeightKilograms: 23, maximumDimensions: nil)],
            conditions: ["Offer not yet ordered"]
        )
        let snapshot = AirlineCommercialFactsSnapshot(
            flightID: flight.id,
            revision: "ndc-offer-test",
            baggageAllowance: fact(quoted, verification: .verifiedNDCOffer, field: "offer.baggageAllowance"),
            seatAvailability: nil,
            overbooking: nil,
            cabinBinSpace: nil
        )

        let assessment = AirlineCapacityNormalizer().normalize(snapshot, at: now)

        XCTAssertNotNil(assessment.baggageAllowance)
        XCTAssertFalse(assessment.baggageAllowance?.value.appliesToTicketedTraveler == true)
    }

    func testCapacityServiceReturnsExplicitUnknownWithoutProvider() async {
        let flight = makeFlight(now: now)

        let result = await AirlineCapacityService().assessment(for: flight, at: now)

        XCTAssertEqual(result.availability, .unavailable)
        XCTAssertEqual(result.unavailableReason, .providerNotConfigured)
        XCTAssertNil(result.baggageAllowance)
        XCTAssertNil(result.seatAvailability)
        XCTAssertNil(result.overbooking)
        XCTAssertNil(result.cabinBinSpace)
    }

    func testCapacityServiceAcceptsOnlyMatchingFlightSnapshot() async {
        let flight = makeFlight(now: now)
        let wrongFlightSnapshot = AirlineCommercialFactsSnapshot(
            flightID: "another-flight",
            revision: "wrong-flight",
            baggageAllowance: nil,
            seatAvailability: nil,
            overbooking: nil,
            cabinBinSpace: nil
        )

        let result = await AirlineCapacityService(
            provider: StubAirlineFactsProvider(snapshot: wrongFlightSnapshot)
        ).assessment(for: flight, at: now)

        XCTAssertEqual(result.availability, .unavailable)
        XCTAssertEqual(result.unavailableReason, .providerFailure)
    }

    func testVerifiedPricedOfferUsesExternalHTTPSBookingHandoff() async throws {
        let offer = pricedOffer()
        let sourcedOffer = fact(offer, verification: .verifiedNDCOffer, field: "ndc.offer")
        let query = FlightOfferSearchQuery(
            routes: [
                FlightOfferRouteRequest(
                    originAirportCode: "HND",
                    destinationAirportCode: "LAX",
                    departureDate: now.addingTimeInterval(86_400)
                )
            ],
            travelers: FlightOfferTravelerCounts(adults: 1, children: 0, lapInfants: 0),
            requestedCabin: "Economy",
            currencyCode: "USD"
        )
        let catalog = await FlightOfferCatalogService(
            provider: StubFlightOfferProvider(response: [sourcedOffer])
        ).offers(for: query, at: now)

        XCTAssertEqual(catalog.availability, .available)
        XCTAssertEqual(catalog.offers.map(\.value.id), [offer.id])
        XCTAssertEqual(catalog.offers.first?.value.bookingRole, .externalHandoffOnly)

        let handoffValue = ExternalBookingHandoff(
            offerID: offer.id,
            providerName: "Test airline retailer",
            url: try XCTUnwrap(URL(string: "https://booking.example.test/offers/offer-1")),
            expiresAt: now.addingTimeInterval(300),
            bookingRole: .externalHandoffOnly
        )
        let handoff = await ExternalBookingHandoffService(
            provider: StubBookingHandoffProvider(
                response: fact(handoffValue, verification: .verifiedNDCOffer, field: "ndc.handoff")
            )
        ).handoff(for: sourcedOffer, at: now)

        XCTAssertEqual(handoff.availability, .available)
        XCTAssertEqual(handoff.handoff?.value.url.scheme, "https")
        XCTAssertEqual(handoff.handoff?.value.bookingRole, .externalHandoffOnly)
        XCTAssertTrue(handoff.advisory.contains("provider"))
    }

    func testNonHTTPSBookingHandoffIsRejected() throws {
        let handoff = ExternalBookingHandoff(
            offerID: "offer-1",
            providerName: "Unsafe test adapter",
            url: try XCTUnwrap(URL(string: "http://booking.example.test/offer-1")),
            expiresAt: now.addingTimeInterval(300),
            bookingRole: .externalHandoffOnly
        )

        XCTAssertFalse(handoff.isValid(at: now))
    }

    func testCarrierMatchingCannotAssertThroughCheckedBaggage() {
        let query = connectionQuery(arrivalAirport: "HND", departureAirport: "HND")
        let proxy = fact(
            ConnectionBaggageHandling(
                state: .throughChecked,
                bagTagDestinationAirportCode: "LAX",
                separateTickets: false,
                instructions: ["Same marketing carrier"]
            ),
            verification: .carrierMatchProxy,
            field: "matchingCarrier"
        )

        let assessment = ConnectionBaggageNormalizer().normalize(proxy, query: query, at: now)

        XCTAssertEqual(assessment.availability, .requiresConfirmation)
        XCTAssertEqual(assessment.state, .confirmationRequired)
        XCTAssertNil(assessment.handling?.value.bagTagDestinationAirportCode)
        XCTAssertNil(assessment.handling?.value.separateTickets)
    }

    func testVerifiedPNRMayAssertThroughCheckedBaggage() async {
        let query = connectionQuery(arrivalAirport: "HND", departureAirport: "HND")
        let verified = fact(
            ConnectionBaggageHandling(
                state: .throughChecked,
                bagTagDestinationAirportCode: "LAX",
                separateTickets: false,
                instructions: ["Confirm the printed bag tag at check-in"]
            ),
            verification: .verifiedAirlinePNR,
            field: "order.bagTagDestination"
        )

        let assessment = await ConnectionBaggageService(
            provider: StubConnectionBaggageProvider(response: verified)
        ).assessment(for: query, at: now)

        XCTAssertEqual(assessment.availability, .verified)
        XCTAssertEqual(assessment.state, .throughChecked)
        XCTAssertEqual(assessment.handling?.value.bagTagDestinationAirportCode, "LAX")
    }

    func testReclaimConnectionBuildsAllSourcedHNDToNRTSegments() {
        let query = connectionQuery(arrivalAirport: "HND", departureAirport: "NRT")
        let baggageFact = fact(
            ConnectionBaggageHandling(
                state: .reclaimImmigrationCustomsRecheck,
                bagTagDestinationAirportCode: "HND",
                separateTickets: false,
                instructions: ["Reclaim at HND and recheck at NRT"]
            ),
            verification: .verifiedAirlineOrder,
            field: "order.connectionBaggage"
        )
        let baggage = ConnectionBaggageNormalizer().normalize(baggageFact, query: query, at: now)
        let required = Set(ConnectionPlanningSegmentKind.allCases)
        let durations = Dictionary(uniqueKeysWithValues: required.map { kind in
            (kind, durationMetric(kind: kind))
        })
        let inputs = ConnectionPlanningInputs(
            durations: durations,
            deadlines: [.bagDropAndCheckIn: deadlineMetric()],
            additionalRequiredSegments: []
        )

        let plan = ConnectionTransferPlanBuilder().build(
            query: query,
            baggage: baggage,
            inputs: inputs,
            at: now
        )

        XCTAssertTrue(plan.canSupportPositiveRecommendation)
        XCTAssertEqual(Set(plan.segments.map(\.kind)), required)
        XCTAssertTrue(plan.segments.contains { $0.kind == .interAirportTravel })
        XCTAssertNotNil(plan.segments.first { $0.kind == .bagDropAndCheckIn }?.deadline)
        XCTAssertEqual(plan.layoverPlanSegments.count, required.count)
        XCTAssertTrue(Set(plan.sourceRecordIDs).isSuperset(of: Set(durations.values.map(\.sourceRecordID))))
        XCTAssertTrue(plan.sourceRecordIDs.contains(baggageFact.sourceRecordID))
    }

    func testMissingBagDropCutoffPreventsPositiveConnectionRecommendation() {
        let query = connectionQuery(arrivalAirport: "HND", departureAirport: "NRT")
        let baggageFact = fact(
            ConnectionBaggageHandling(
                state: .selfTransferSeparateTicket,
                bagTagDestinationAirportCode: "HND",
                separateTickets: true,
                instructions: []
            ),
            verification: .verifiedNDCOffer,
            field: "offer.selfTransfer"
        )
        let baggage = ConnectionBaggageNormalizer().normalize(baggageFact, query: query, at: now)
        let required: Set<ConnectionPlanningSegmentKind> = [
            .baggageWait,
            .landsideTransfer,
            .bagDropAndCheckIn,
            .securityScreening,
            .interAirportTravel
        ]
        let inputs = ConnectionPlanningInputs(
            durations: Dictionary(uniqueKeysWithValues: required.map { ($0, durationMetric(kind: $0)) }),
            deadlines: [:],
            additionalRequiredSegments: []
        )

        let plan = ConnectionTransferPlanBuilder().build(
            query: query,
            baggage: baggage,
            inputs: inputs,
            at: now
        )

        XCTAssertFalse(plan.canSupportPositiveRecommendation)
        XCTAssertTrue(plan.unresolvedInputs.contains("bag-drop/check-in cutoff"))
    }

    func testSeededHNDNRTFixtureReplaysExactlyAndCannotMasqueradeAsLive() {
        let seed: UInt64 = 9_041
        let first = FlightOperationalReferenceFixtures.hndToNrt(anchor: now, seed: seed)
        let replay = FlightOperationalReferenceFixtures.hndToNrt(anchor: now, seed: seed)

        XCTAssertEqual(first.seed, seed)
        XCTAssertEqual(first.dataMode, .demo)
        XCTAssertEqual(first.planningInputs, replay.planningInputs)
        XCTAssertEqual(first.baggageHandling, replay.baggageHandling)
        XCTAssertEqual(first.pricedOffer, replay.pricedOffer)
        XCTAssertEqual(first.externalHandoff, replay.externalHandoff)
        XCTAssertFalse(first.baggageHandling.isLive)
        XCTAssertFalse(first.pricedOffer.isLive)
        XCTAssertEqual(first.connectionQuery.inboundArrivalAirportCode, "HND")
        XCTAssertEqual(first.connectionQuery.outboundDepartureAirportCode, "NRT")
    }

    func testBKKHNDLAXFixtureIsDemoThroughCheckedToLAXWithExternalHTTPSOnly() {
        let seed: UInt64 = 6_601_061
        let fixture = FlightOperationalReferenceFixtures.bkkHndLax(anchor: now, seed: seed)

        XCTAssertEqual(fixture.dataMode, .demo)
        XCTAssertEqual(fixture.baggageHandling.value.state, .throughChecked)
        XCTAssertEqual(fixture.baggageHandling.value.bagTagDestinationAirportCode, "LAX")
        XCTAssertFalse(fixture.baggageHandling.isLive)
        XCTAssertFalse(fixture.pricedOffer.isLive)
        XCTAssertEqual(fixture.pricedOffer.value.legs.count, 2)
        XCTAssertEqual(fixture.pricedOffer.value.bookingRole, .externalHandoffOnly)
        XCTAssertEqual(fixture.externalHandoff.value.url.scheme, "https")
        XCTAssertEqual(fixture.externalHandoff.value.bookingRole, .externalHandoffOnly)
        XCTAssertFalse(fixture.externalHandoff.isLive)
    }

    func testTicketPDFScanExtractsRouteAndBagDestination() throws {
        let scan = try TicketPDFScanService.scanText(
            """
            ELECTRONIC TICKET
            ROUTE BKK HND LAX
            BAGS CHECKED TO LAX
            """,
            fileName: "bkk-hnd-lax.pdf",
            at: now
        )

        XCTAssertEqual(scan.fileName, "bkk-hnd-lax.pdf")
        XCTAssertEqual(scan.routeAirportCodes, ["BKK", "HND", "LAX"])
        XCTAssertTrue(scan.baggageSignals.contains(.bagTagDestination("LAX")))
        XCTAssertTrue(scan.sourceRecordID.hasPrefix("ticket-pdf|"))
    }

    func testTicketScanBuildsThroughCheckedConnectionAndTransitStatus() throws {
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: now)
        let scan = try TicketPDFScanService.scanText("ROUTE BKK HND LAX\nBAG TAG DESTINATION LAX", at: now)

        let statuses = TicketConnectionStatusService().statuses(
            for: itinerary,
            scan: scan,
            travelerProfile: .minimalDemo,
            entryAssessment: currentEntryAssessment(status: .authorizationNotIndicated),
            now: now
        )

        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses[0].baggageAssessment.state, .throughChecked)
        XCTAssertEqual(statuses[0].baggageAssessment.handling?.value.bagTagDestinationAirportCode, "LAX")
        XCTAssertTrue(statuses[0].requiredSegments.isEmpty)
        XCTAssertEqual(statuses[0].transitStatus, .current)
        XCTAssertEqual(statuses[0].transferFlow, .standardConnection)
    }

    func testAutomaticTransferTicketKeepsTheConnectionAtHaneda() throws {
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: now)
        let scan = try TicketPDFScanService.scanText(
            "ROUTE BKK HND LAX\nAUTOMATIC TRANSFER\nBAG TAG DESTINATION LAX",
            at: now
        )

        let statuses = TicketConnectionStatusService().statuses(
            for: itinerary,
            scan: scan,
            travelerProfile: .minimalDemo,
            entryAssessment: currentEntryAssessment(status: .authorizationNotIndicated),
            now: now
        )

        XCTAssertEqual(scan.routeAirportCodes, ["BKK", "HND", "LAX"])
        XCTAssertTrue(scan.baggageSignals.contains(.automaticTransfer))
        XCTAssertEqual(statuses.first?.baggageAssessment.state, .throughChecked)
        XCTAssertEqual(statuses.first?.transferFlow, .standardConnection)
    }

    func testTicketScanBuildsRecheckStatusForInterAirportConnection() throws {
        let itinerary = LongHaulReferenceScenario.hanedaToNaritaItinerary(anchor: now)
        let scan = try TicketPDFScanService.scanText(
            """
            TICKET HND NRT LAX
            BAG TAG DESTINATION HND
            COLLECT BAG AT HND AND RECHECK
            """,
            at: now
        )

        let statuses = TicketConnectionStatusService().statuses(
            for: itinerary,
            scan: scan,
            travelerProfile: .minimalDemo,
            entryAssessment: currentEntryAssessment(status: .conditional),
            now: now
        )

        XCTAssertEqual(statuses.first?.baggageAssessment.state, .reclaimImmigrationCustomsRecheck)
        XCTAssertTrue(statuses.first?.requiredSegments.contains(.interAirportTravel) == true)
        XCTAssertTrue(statuses.first?.requiredSegments.contains(.bagDropAndCheckIn) == true)
        XCTAssertEqual(statuses.first?.transitStatus, .conditional)
        XCTAssertEqual(statuses.first?.transferFlow, .airportChange)
    }

    func testSampleTicketRecognizesAirportChangeConnection() throws {
        let itinerary = LongHaulReferenceScenario.hanedaToNaritaItinerary(anchor: now)
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sample-self-transfer-ticket", withExtension: "txt"))
        let ticketText = try String(contentsOf: fixtureURL, encoding: .utf8)
        let scan = try TicketPDFScanService.scanText(ticketText, fileName: fixtureURL.lastPathComponent, at: now)

        let statuses = TicketConnectionStatusService().statuses(
            for: itinerary,
            scan: scan,
            travelerProfile: .minimalDemo,
            entryAssessment: currentEntryAssessment(status: .authorizationNotIndicated),
            now: now
        )

        XCTAssertEqual(scan.routeAirportCodes, ["BKK", "HND", "NRT", "LAX"])
        XCTAssertEqual(statuses.first?.transferFlow, .airportChange)
        XCTAssertEqual(statuses.first?.baggageAssessment.state, .selfTransferSeparateTicket)
    }

    func testTicketTransitStatusAsksForTravelerDetailsWhenProfileIsIncomplete() throws {
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: now)
        let scan = try TicketPDFScanService.scanText("ROUTE BKK HND LAX\nBAGS CHECKED TO LAX", at: now)

        let statuses = TicketConnectionStatusService().statuses(
            for: itinerary,
            scan: scan,
            travelerProfile: .incomplete,
            entryAssessment: currentEntryAssessment(status: .authorizationNotIndicated),
            now: now
        )

        XCTAssertEqual(statuses.first?.transitStatus, .addTravelerDetails)
    }

    func testWeatherStateHistoryNeedsComparableOutcomesAndNewsOnlyWidensUpperTail() async throws {
        let flight = makeFlight(now: now)
        let weatherFeatures: [FlightDelayFeatureKind: SourcedFlightDelayFeature] = [
            .departureWindGust: feature(kind: .departureWindGust, value: 24, unit: .knots),
            .departureVisibility: feature(kind: .departureVisibility, value: 6_200, unit: .meters),
            .departurePrecipitationRate: feature(kind: .departurePrecipitationRate, value: 2, unit: .millimetersPerHour)
        ]
        let baselineSnapshot = FlightDelayFeatureSnapshot(
            flightID: flight.id,
            revision: "weather-state-baseline",
            assembledAt: now,
            features: weatherFeatures
        )
        let state = try XCTUnwrap(WeatherStateKey(features: baselineSnapshot))
        var departureCalendar = Calendar(identifier: .gregorian)
        departureCalendar.timeZone = TimeZone(identifier: flight.origin.timeZone ?? "UTC") ?? .gmt
        let localDepartureHour = departureCalendar.component(.hour, from: flight.scheduledDeparture!)
        let outcomes = [4.0, 12.0, 36.0].enumerated().map { index, delay in
            WeatherStateDelayOutcome(
                route: flight.routeLabel,
                airlineCode: flight.airlineCode,
                localDepartureHour: localDepartureHour,
                weatherState: state,
                arrivalDelayMinutes: delay,
                observedAt: now.addingTimeInterval(-Double(index + 1) * 86_400),
                sourceRecordID: "owned-outcome-\(index)"
            )
        }
        let model = WeatherStateDelayTrendModel(outcomes: outcomes, minimumComparableOutcomes: 3)
        let baseline = try await model.predict(flight: flight, features: baselineSnapshot, at: now)
        var newsFeatures = weatherFeatures
        newsFeatures[.airportWeatherDisruptionReportProbability] = feature(
            kind: .airportWeatherDisruptionReportProbability,
            value: 1,
            unit: .probability
        )
        let newsSnapshot = FlightDelayFeatureSnapshot(
            flightID: flight.id,
            revision: "weather-state-news",
            assembledAt: now,
            features: newsFeatures
        )
        let withNews = try await model.predict(flight: flight, features: newsSnapshot, at: now)

        XCTAssertEqual(baseline.distribution.quantiles[1].minutes, withNews.distribution.quantiles[1].minutes)
        XCTAssertGreaterThan(withNews.distribution.quantiles[2].minutes, baseline.distribution.quantiles[2].minutes)
        XCTAssertTrue(withNews.usedFeatures.contains(.airportWeatherDisruptionReportProbability))
    }

    private func snapshot(flightID: String) -> FlightDelayFeatureSnapshot {
        let kind = FlightDelayFeatureKind.departureWindGust
        return FlightDelayFeatureSnapshot(
            flightID: flightID,
            revision: "test-snapshot",
            assembledAt: now,
            features: [kind: feature(kind: kind, value: 12, unit: .knots)]
        )
    }

    private func feature(
        kind: FlightDelayFeatureKind,
        value: Double,
        unit: FlightDelayFeatureUnit,
        expiresAt: Date? = nil
    ) -> SourcedFlightDelayFeature {
        SourcedFlightDelayFeature(
            kind: kind,
            value: value,
            unit: unit,
            provider: "Test operational source",
            providerField: kind.rawValue,
            sourceRecordID: "record-\(kind.rawValue)",
            observedAt: now.addingTimeInterval(-60),
            receivedAt: now.addingTimeInterval(-30),
            expiresAt: expiresAt ?? now.addingTimeInterval(600)
        )
    }

    private func descriptor(
        requiredFeatures: Set<FlightDelayFeatureKind>,
        target: FlightDelayTarget = .arrivalDelayMinutes
    ) -> FlightDelayModelDescriptor {
        FlightDelayModelDescriptor(
            id: "test-delay-model",
            version: "1",
            featureSchemaVersion: "test-feature-schema-v1",
            target: target,
            algorithmFamily: .quantileRegression,
            requiredFeatures: requiredFeatures,
            trainedAt: now.addingTimeInterval(-86_400),
            calibratedThrough: now.addingTimeInterval(-3_600),
            trainingPolicyVersion: "test-training-policy"
        )
    }

    private func validDistribution(
        target: FlightDelayTarget = .arrivalDelayMinutes
    ) -> FlightDelayDistribution {
        FlightDelayDistribution(
            target: target,
            quantiles: [
                DelayQuantile(probability: 0.1, minutes: 4),
                DelayQuantile(probability: 0.5, minutes: 18),
                DelayQuantile(probability: 0.9, minutes: 46)
            ],
            meanMinutes: 21,
            exceedanceProbabilities: [
                DelayExceedanceProbability(thresholdMinutes: 15, probability: 0.57),
                DelayExceedanceProbability(thresholdMinutes: 30, probability: 0.28)
            ]
        )
    }

    private func delayModel(
        flightID: String,
        requiredFeatures: Set<FlightDelayFeatureKind>,
        usedFeatures: Set<FlightDelayFeatureKind>
    ) -> StubDelayModel {
        StubDelayModel(
            descriptor: descriptor(requiredFeatures: requiredFeatures),
            output: FlightDelayModelOutput(
                flightID: flightID,
                distribution: validDistribution(),
                usedFeatures: usedFeatures,
                generatedAt: now,
                expiresAt: now.addingTimeInterval(600),
                derivation: [
                    DerivationStep(
                        label: "Test probabilistic output",
                        formula: "fixture quantiles from named test model",
                        inputRecordIDs: usedFeatures.map { "record-\($0.rawValue)" }.sorted(),
                        result: "p10/p50/p90"
                    )
                ]
            )
        )
    }

    private func fact<Value: Codable & Hashable & Sendable>(
        _ value: Value,
        verification: AirlineFactVerification,
        field: String
    ) -> SourcedAirlineFact<Value> {
        SourcedAirlineFact(
            value: value,
            verification: verification,
            provider: "Test airline source",
            providerField: field,
            sourceRecordID: "fact-\(field)",
            observedAt: now.addingTimeInterval(-60),
            receivedAt: now.addingTimeInterval(-30),
            expiresAt: now.addingTimeInterval(600),
            isLive: true,
            derivation: []
        )
    }

    private func pricedOffer() -> PricedFlightOffer {
        PricedFlightOffer(
            id: "offer-1",
            legs: [
                OfferedFlightLeg(
                    id: "offered-leg-1",
                    marketingCarrierCode: "NH",
                    operatingCarrierCode: "NH",
                    flightNumber: "106",
                    originAirportCode: "HND",
                    destinationAirportCode: "LAX",
                    scheduledDeparture: now.addingTimeInterval(86_400),
                    scheduledArrival: now.addingTimeInterval(86_400 + 36_000),
                    cabin: "Economy",
                    bookingClass: "Y"
                )
            ],
            totalPrice: FlightOfferPrice(decimalAmount: "842.35", currencyCode: "USD"),
            fareBrand: "Test flexible",
            quotedBaggageAllowance: nil,
            providerOfferExpiresAt: now.addingTimeInterval(300),
            bookingRole: .externalHandoffOnly
        )
    }

    private func connectionQuery(
        arrivalAirport: String,
        departureAirport: String
    ) -> ConnectionBaggageQuery {
        ConnectionBaggageQuery(
            itineraryID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            inboundLegID: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            outboundLegID: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            inboundArrivalAirportCode: arrivalAirport,
            outboundDepartureAirportCode: departureAirport,
            orderSession: nil
        )
    }

    private func durationMetric(
        kind: ConnectionPlanningSegmentKind
    ) -> SourcedMetric<EstimateDistribution> {
        let distribution = EstimateDistribution(lower: 5, mostLikely: 10, upper: 20, unit: .minutes)
        return SourcedMetric(
            value: distribution,
            unit: .minutes,
            provider: "Named connection test fixture",
            providerField: kind.rawValue,
            sourceRecordID: "connection-duration-\(kind.rawValue)",
            observedAt: now.addingTimeInterval(-60),
            receivedAt: now.addingTimeInterval(-30),
            expiresAt: now.addingTimeInterval(600),
            uncertainty: "Deterministic unit-test distribution",
            derivation: []
        )
    }

    private func deadlineMetric() -> SourcedMetric<Date> {
        SourcedMetric(
            value: now.addingTimeInterval(7_200),
            unit: .dateTime,
            provider: "Named airline cutoff test fixture",
            providerField: "bagDropClosesAt",
            sourceRecordID: "connection-bag-drop-cutoff",
            observedAt: now.addingTimeInterval(-60),
            receivedAt: now.addingTimeInterval(-30),
            expiresAt: now.addingTimeInterval(600),
            uncertainty: nil,
            derivation: []
        )
    }

    private func currentEntryAssessment(status: EntryAssessmentStatus) -> EntryAssessment {
        EntryAssessment(
            status: status,
            summary: "Current transit check",
            provider: "entry-test",
            evidenceKind: .structuredProvider,
            sourceRecordID: "entry-test-\(status.rawValue)",
            observedAt: now,
            receivedAt: now,
            expiresAt: now.addingTimeInterval(24 * 60 * 60),
            officialVerificationURLs: [URL(string: "https://www.mofa.go.jp/")!],
            isDemo: false
        )
    }
}
