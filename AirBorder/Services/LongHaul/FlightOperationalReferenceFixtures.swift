import Foundation

/// Named demo/test data for Flights and connection-planning previews. Values
/// are generated from a recorded seed and must never be labeled live or used as
/// an operational claim.
struct FlightOperationalReferenceFixture: Sendable {
    let seed: UInt64
    let dataMode: DataFreshness
    let itinerary: Itinerary
    let connectionQuery: ConnectionBaggageQuery
    let baggageHandling: SourcedAirlineFact<ConnectionBaggageHandling>
    let planningInputs: ConnectionPlanningInputs
    let offerSearch: FlightOfferSearchQuery
    let pricedOffer: SourcedAirlineFact<PricedFlightOffer>
    let externalHandoff: SourcedAirlineFact<ExternalBookingHandoff>
}

enum FlightOperationalReferenceFixtures {
    static let hndNrtVersion = "demo-hnd-nrt-operational-intelligence-v1"
    static let hndNrtSeed = StableSimulationSeed.digest(hndNrtVersion)

    static func hndToNrt(
        anchor: Date = Date(),
        seed: UInt64 = hndNrtSeed
    ) -> FlightOperationalReferenceFixture {
        let itinerary = LongHaulReferenceScenario.hanedaToNaritaItinerary(anchor: anchor)
        let layover = itinerary.layovers[0]
        var generator = ReplayableRandomNumberGenerator(seed: seed)

        func distribution(
            namedFixtureCenter: Double,
            kind: ConnectionPlanningSegmentKind
        ) -> SourcedMetric<EstimateDistribution> {
            let relativeSpread = 0.25 + generator.unitInterval() * 0.20
            let lower = max(1, namedFixtureCenter * (1 - relativeSpread))
            let upper = namedFixtureCenter * (1 + relativeSpread)
            return SourcedMetric(
                value: EstimateDistribution(
                    lower: lower,
                    mostLikely: namedFixtureCenter,
                    upper: upper,
                    unit: .minutes
                ),
                unit: .minutes,
                provider: "Example HND-NRT trip",
                providerField: kind.rawValue,
                sourceRecordID: "\(hndNrtVersion)|\(seed)|\(kind.rawValue)",
                observedAt: anchor,
                receivedAt: anchor,
                expiresAt: nil,
                uncertainty: "Example timing range",
                derivation: [
                    DerivationStep(
                        label: "Example interval",
                        formula: "route center × timing spread",
                        inputRecordIDs: [hndNrtVersion, String(seed)],
                        result: "\(Int(lower.rounded()))–\(Int(upper.rounded())) min"
                    )
                ]
            )
        }

        // These centers are named UI/test-fixture assumptions, not live HND or
        // NRT claims. Production adapters must replace every metric.
        let centers: [ConnectionPlanningSegmentKind: Double] = [
            .baggageWait: 24,
            .borderProcessing: 32,
            .customsProcessing: 12,
            .landsideTransfer: 15,
            .bagDropAndCheckIn: 18,
            .securityScreening: 28,
            .interAirportTravel: 95
        ]
        let durations = Dictionary(uniqueKeysWithValues: centers.map { kind, center in
            (kind, distribution(namedFixtureCenter: center, kind: kind))
        })
        let cutoff = SourcedMetric(
            value: anchor.addingTimeInterval(7 * 3_600),
            unit: MetricUnit.dateTime,
            provider: "Example HND-NRT trip",
            providerField: "bagDropClosesAt",
            sourceRecordID: "\(hndNrtVersion)|\(seed)|bag-drop-cutoff",
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: nil,
            uncertainty: "Example cutoff",
            derivation: []
        )
        let baggage = SourcedAirlineFact(
            value: ConnectionBaggageHandling(
                state: .reclaimImmigrationCustomsRecheck,
                bagTagDestinationAirportCode: "HND",
                separateTickets: false,
                instructions: ["Reclaim at HND and check in again for the NRT departure"]
            ),
            verification: .verifiedAirlineOrder,
            provider: "Example HND-NRT trip",
            providerField: "fixture.connectionBaggage",
            sourceRecordID: "\(hndNrtVersion)|\(seed)|baggage",
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: nil,
            isLive: false,
            derivation: []
        )

        let offerExpiry = anchor.addingTimeInterval(30 * 60)
        let offeredLeg = OfferedFlightLeg(
            id: "demo-offer-nrt-lax",
            marketingCarrierCode: "NH",
            operatingCarrierCode: "NH",
            flightNumber: "6",
            originAirportCode: "NRT",
            destinationAirportCode: "LAX",
            scheduledDeparture: itinerary.legs[1].flight.scheduledDeparture ?? anchor,
            scheduledArrival: itinerary.legs[1].flight.scheduledArrival ?? anchor,
            cabin: "Economy",
            bookingClass: "Economy"
        )
        let offer = SourcedAirlineFact(
            value: PricedFlightOffer(
                id: "demo-hnd-nrt-offer",
                legs: [offeredLeg],
                totalPrice: FlightOfferPrice(decimalAmount: "842.35", currencyCode: "USD"),
                fareBrand: "External offer",
                quotedBaggageAllowance: nil,
                providerOfferExpiresAt: offerExpiry,
                bookingRole: .externalHandoffOnly
            ),
            verification: .verifiedNDCOffer,
            provider: "Example HND-NRT trip",
            providerField: "fixture.pricedOffer",
            sourceRecordID: "\(hndNrtVersion)|\(seed)|offer",
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: offerExpiry,
            isLive: false,
            derivation: []
        )
        let handoff = demoHandoff(
            offerID: offer.value.id,
            anchor: anchor,
            expiresAt: offerExpiry,
            seed: seed
        )

        return FlightOperationalReferenceFixture(
            seed: seed,
            dataMode: .demo,
            itinerary: itinerary,
            connectionQuery: ConnectionBaggageQuery(
                itineraryID: itinerary.id,
                inboundLegID: layover.inboundLegID,
                outboundLegID: layover.onwardLegID,
                inboundArrivalAirportCode: "HND",
                outboundDepartureAirportCode: "NRT",
                orderSession: nil
            ),
            baggageHandling: baggage,
            planningInputs: ConnectionPlanningInputs(
                durations: durations,
                deadlines: [.bagDropAndCheckIn: cutoff],
                additionalRequiredSegments: []
            ),
            offerSearch: FlightOfferSearchQuery(
                routes: [
                    FlightOfferRouteRequest(
                        originAirportCode: "NRT",
                        destinationAirportCode: "LAX",
                        departureDate: offeredLeg.scheduledDeparture
                    )
                ],
                travelers: FlightOfferTravelerCounts(adults: 1, children: 0, lapInfants: 0),
                requestedCabin: "Economy",
                currencyCode: "USD"
            ),
            pricedOffer: offer,
            externalHandoff: handoff
        )
    }

    static func bkkHndLax(
        anchor: Date = Date(),
        seed: UInt64 = StableSimulationSeed.digest("demo-bkk-hnd-lax-operational-intelligence-v1")
    ) -> FlightOperationalReferenceFixture {
        let version = "demo-bkk-hnd-lax-operational-intelligence-v1"
        let itinerary = LongHaulReferenceScenario.itinerary(anchor: anchor)
        let layover = itinerary.layovers[0]
        let offerExpiry = anchor.addingTimeInterval(30 * 60)
        let baggage = SourcedAirlineFact(
            value: ConnectionBaggageHandling(
                state: .throughChecked,
                bagTagDestinationAirportCode: "LAX",
                separateTickets: false,
                instructions: ["Check that the printed bag tag says LAX at BKK check-in"]
            ),
            verification: .verifiedAirlineOrder,
            provider: "Example BKK-HND-LAX trip",
            providerField: "fixture.connectionBaggage",
            sourceRecordID: "\(version)|\(seed)|baggage",
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: nil,
            isLive: false,
            derivation: []
        )
        let offeredLegs = itinerary.legs.map { leg in
            OfferedFlightLeg(
                id: "demo-offer-\(leg.id.uuidString.lowercased())",
                marketingCarrierCode: leg.flight.airlineCode ?? "AX",
                operatingCarrierCode: leg.flight.airlineCode,
                flightNumber: leg.flight.flightNumber,
                originAirportCode: leg.flight.origin.iata,
                destinationAirportCode: leg.flight.destination.iata,
                scheduledDeparture: leg.flight.scheduledDeparture ?? anchor,
                scheduledArrival: leg.flight.scheduledArrival ?? anchor,
                cabin: "Economy",
                bookingClass: "Economy"
            )
        }
        let offer = SourcedAirlineFact(
            value: PricedFlightOffer(
                id: "demo-bkk-hnd-lax-offer",
                legs: offeredLegs,
                totalPrice: FlightOfferPrice(decimalAmount: "1264.80", currencyCode: "USD"),
                fareBrand: "Multi-carrier itinerary",
                quotedBaggageAllowance: TravelerBaggageAllowance(
                    appliesToTicketedTraveler: false,
                    limits: [],
                    conditions: ["Verify allowance with both operating airlines"]
                ),
                providerOfferExpiresAt: offerExpiry,
                bookingRole: .externalHandoffOnly
            ),
            verification: .verifiedNDCOffer,
            provider: "Example BKK-HND-LAX trip",
            providerField: "fixture.pricedOffer",
            sourceRecordID: "\(version)|\(seed)|offer",
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: offerExpiry,
            isLive: false,
            derivation: []
        )
        let handoff = demoHandoff(
            offerID: offer.value.id,
            anchor: anchor,
            expiresAt: offerExpiry,
            seed: seed
        )

        return FlightOperationalReferenceFixture(
            seed: seed,
            dataMode: .demo,
            itinerary: itinerary,
            connectionQuery: ConnectionBaggageQuery(
                itineraryID: itinerary.id,
                inboundLegID: layover.inboundLegID,
                outboundLegID: layover.onwardLegID,
                inboundArrivalAirportCode: "HND",
                outboundDepartureAirportCode: "HND",
                orderSession: nil
            ),
            baggageHandling: baggage,
            planningInputs: ConnectionPlanningInputs(
                durations: [:],
                deadlines: [:],
                additionalRequiredSegments: []
            ),
            offerSearch: FlightOfferSearchQuery(
                routes: [
                    FlightOfferRouteRequest(
                        originAirportCode: "BKK",
                        destinationAirportCode: "LAX",
                        departureDate: offeredLegs[0].scheduledDeparture
                    )
                ],
                travelers: FlightOfferTravelerCounts(adults: 1, children: 0, lapInfants: 0),
                requestedCabin: "Economy",
                currencyCode: "USD"
            ),
            pricedOffer: offer,
            externalHandoff: handoff
        )
    }

    private static func demoHandoff(
        offerID: String,
        anchor: Date,
        expiresAt: Date,
        seed: UInt64
    ) -> SourcedAirlineFact<ExternalBookingHandoff> {
        SourcedAirlineFact(
            value: ExternalBookingHandoff(
                offerID: offerID,
                providerName: "Airport XR booking link",
                url: URL(string: "https://example.com/airportxr-demo-booking")!,
                expiresAt: expiresAt,
                bookingRole: .externalHandoffOnly
            ),
            verification: .verifiedNDCOffer,
            provider: "Airport XR booking link",
            providerField: "fixture.externalHandoff",
            sourceRecordID: "demo-external-handoff|\(seed)|\(offerID)",
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: expiresAt,
            isLive: false,
            derivation: []
        )
    }
}
