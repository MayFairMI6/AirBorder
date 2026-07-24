import Foundation

protocol FlightDelayFeatureProvider: Sendable {
    var providerID: String { get }
    func features(for flight: Flight, at date: Date) async throws -> FlightDelayFeatureSnapshot
}

protocol FlightDelayModel: Sendable {
    var descriptor: FlightDelayModelDescriptor { get }
    func predict(
        flight: Flight,
        features: FlightDelayFeatureSnapshot,
        at date: Date
    ) async throws -> FlightDelayModelOutput
}

protocol FlightDelayContextProviding: Sendable {
    func prediction(for flight: Flight, at date: Date) async -> FlightDelayPrediction
}

struct FlightDelayContextService: FlightDelayContextProviding, Sendable {
    let featureProvider: any FlightDelayFeatureProvider
    let model: (any FlightDelayModel)?

    init(featureProvider: any FlightDelayFeatureProvider, model: (any FlightDelayModel)? = nil) {
        self.featureProvider = featureProvider
        self.model = model
    }

    func prediction(for flight: Flight, at date: Date) async -> FlightDelayPrediction {
        guard let model else {
            return unavailable(
                flightID: flight.id,
                reason: .modelNotConfigured,
                model: nil,
                generatedAt: date,
                advisory: "No calibrated delay model is configured. Continue using the official flight status."
            )
        }

        let snapshot: FlightDelayFeatureSnapshot
        do {
            snapshot = try await featureProvider.features(for: flight, at: date)
        } catch {
            return unavailable(
                flightID: flight.id,
                reason: .featureProviderUnavailable,
                model: model.descriptor,
                generatedAt: date,
                advisory: "Delay context is unavailable because current operational inputs could not be obtained."
            )
        }

        guard snapshot.flightID == flight.id else {
            return unavailable(
                flightID: flight.id,
                reason: .flightIdentityMismatch,
                model: model.descriptor,
                featureRevision: snapshot.revision,
                generatedAt: date,
                sourceRecordIDs: snapshot.sourceRecordIDs,
                advisory: "The operational feature snapshot belongs to a different flight."
            )
        }

        let required = model.descriptor.requiredFeatures
        let missing = required.filter { snapshot.features[$0] == nil }.sorted { $0.rawValue < $1.rawValue }
        guard missing.isEmpty else {
            return unavailable(
                flightID: flight.id,
                reason: .missingRequiredFeatures,
                model: model.descriptor,
                featureRevision: snapshot.revision,
                generatedAt: date,
                sourceRecordIDs: snapshot.sourceRecordIDs,
                missingFeatures: missing,
                advisory: "Required weather, congestion, rotation, or schedule inputs are missing."
            )
        }

        let invalid = required.filter {
            guard let feature = snapshot.features[$0] else { return false }
            return feature.kind != $0 || !feature.isSemanticallyValid
        }
            .sorted { $0.rawValue < $1.rawValue }
        guard invalid.isEmpty else {
            return unavailable(
                flightID: flight.id,
                reason: .invalidFeatures,
                model: model.descriptor,
                featureRevision: snapshot.revision,
                generatedAt: date,
                sourceRecordIDs: snapshot.sourceRecordIDs,
                missingFeatures: invalid,
                advisory: "One or more required inputs failed semantic or provenance validation."
            )
        }

        let stale = required.filter { snapshot.features[$0]?.isCurrent(at: date) != true }
            .sorted { $0.rawValue < $1.rawValue }
        guard stale.isEmpty else {
            return unavailable(
                flightID: flight.id,
                reason: .staleRequiredFeatures,
                model: model.descriptor,
                featureRevision: snapshot.revision,
                generatedAt: date,
                sourceRecordIDs: snapshot.sourceRecordIDs,
                staleFeatures: stale,
                advisory: "Required operational inputs are stale or have unknown freshness."
            )
        }

        let output: FlightDelayModelOutput
        do {
            output = try await model.predict(flight: flight, features: snapshot, at: date)
        } catch {
            return unavailable(
                flightID: flight.id,
                reason: .modelFailure,
                model: model.descriptor,
                featureRevision: snapshot.revision,
                generatedAt: date,
                sourceRecordIDs: snapshot.sourceRecordIDs,
                advisory: "The calibrated model did not produce a usable result."
            )
        }

        guard output.flightID == flight.id else {
            return unavailable(
                flightID: flight.id,
                reason: .flightIdentityMismatch,
                model: model.descriptor,
                featureRevision: snapshot.revision,
                generatedAt: date,
                sourceRecordIDs: snapshot.sourceRecordIDs,
                advisory: "The model output belongs to a different flight."
            )
        }

        let outputMissing = output.usedFeatures.filter { snapshot.features[$0] == nil }
        let outputStale = output.usedFeatures.filter { snapshot.features[$0]?.isCurrent(at: date) != true }
        let outputInvalid = output.usedFeatures.filter {
            guard let feature = snapshot.features[$0] else { return false }
            return feature.kind != $0 || !feature.isSemanticallyValid
        }
        guard output.usedFeatures.isSuperset(of: required),
              outputMissing.isEmpty,
              outputStale.isEmpty,
              outputInvalid.isEmpty else {
            return unavailable(
                flightID: flight.id,
                reason: !outputMissing.isEmpty
                    ? .missingRequiredFeatures
                    : (!outputInvalid.isEmpty ? .invalidFeatures : .staleRequiredFeatures),
                model: model.descriptor,
                featureRevision: snapshot.revision,
                generatedAt: date,
                sourceRecordIDs: snapshot.sourceRecordIDs,
                missingFeatures: Array(outputMissing).sorted { $0.rawValue < $1.rawValue },
                staleFeatures: Array(outputStale).sorted { $0.rawValue < $1.rawValue },
                advisory: "The model output did not retain a complete, current feature lineage."
            )
        }

        guard output.distribution.target == model.descriptor.target,
              output.distribution.isValid else {
            return unavailable(
                flightID: flight.id,
                reason: .invalidDistribution,
                model: model.descriptor,
                featureRevision: snapshot.revision,
                generatedAt: date,
                sourceRecordIDs: snapshot.sourceRecordIDs,
                advisory: "The model distribution failed monotonicity, probability, or target validation."
            )
        }

        guard output.expiresAt > date else {
            return unavailable(
                flightID: flight.id,
                reason: .predictionExpired,
                model: model.descriptor,
                featureRevision: snapshot.revision,
                generatedAt: date,
                sourceRecordIDs: snapshot.sourceRecordIDs,
                advisory: "The model output expired before it could be used."
            )
        }

        let usedSourceIDs = output.usedFeatures.compactMap { snapshot.features[$0]?.sourceRecordID }
        return FlightDelayPrediction(
            flightID: flight.id,
            availability: .available,
            unavailableReason: nil,
            distribution: output.distribution,
            model: model.descriptor,
            featureRevision: snapshot.revision,
            generatedAt: output.generatedAt,
            expiresAt: output.expiresAt,
            sourceRecordIDs: Array(Set(usedSourceIDs)).sorted(),
            missingFeatures: [],
            staleFeatures: [],
            trace: output.derivation,
            advisory: "Probabilistic planning context only. Official airline and airport status remains authoritative."
        )
    }

    private func unavailable(
        flightID: String,
        reason: FlightDelayUnavailableReason,
        model: FlightDelayModelDescriptor?,
        featureRevision: String? = nil,
        generatedAt: Date,
        sourceRecordIDs: [String] = [],
        missingFeatures: [FlightDelayFeatureKind] = [],
        staleFeatures: [FlightDelayFeatureKind] = [],
        advisory: String
    ) -> FlightDelayPrediction {
        FlightDelayPrediction(
            flightID: flightID,
            availability: .unavailable,
            unavailableReason: reason,
            distribution: nil,
            model: model,
            featureRevision: featureRevision,
            generatedAt: generatedAt,
            expiresAt: nil,
            sourceRecordIDs: sourceRecordIDs,
            missingFeatures: missingFeatures,
            staleFeatures: staleFeatures,
            trace: [],
            advisory: advisory
        )
    }
}

extension FlightDelayPrediction {
    func layoverScenarioInput(officialFlight: Flight) -> LayoverFlightDelayScenarioInput {
        guard flightID == officialFlight.id else {
            return LayoverFlightDelayScenarioInput(
                flightID: officialFlight.id,
                officialStatus: officialFlight.status,
                officialEffectiveArrival: officialFlight.effectiveArrival,
                officialProviderName: officialFlight.source.name,
                predictionRole: .scenarioContextOnly,
                predictedArrivalDelay: nil,
                predictionAvailability: .unavailable,
                unavailableReason: .flightIdentityMismatch,
                predictionExpiresAt: nil,
                sourceRecordIDs: []
            )
        }

        let isArrivalPrediction = distribution?.target == .arrivalDelayMinutes
        return LayoverFlightDelayScenarioInput(
            flightID: officialFlight.id,
            officialStatus: officialFlight.status,
            officialEffectiveArrival: officialFlight.effectiveArrival,
            officialProviderName: officialFlight.source.name,
            predictionRole: .scenarioContextOnly,
            predictedArrivalDelay: isArrivalPrediction ? distribution : nil,
            predictionAvailability: isArrivalPrediction ? availability : .unavailable,
            unavailableReason: isArrivalPrediction ? unavailableReason : .targetNotApplicableToLayover,
            predictionExpiresAt: isArrivalPrediction ? expiresAt : nil,
            sourceRecordIDs: isArrivalPrediction ? sourceRecordIDs : []
        )
    }
}

protocol AirlineCommercialFactsProvider: Sendable {
    var providerID: String { get }
    func facts(
        for query: AirlineCommercialFactsQuery,
        at date: Date
    ) async throws -> AirlineCommercialFactsSnapshot
}

struct AirlineCapacityService: Sendable {
    let provider: (any AirlineCommercialFactsProvider)?

    init(provider: (any AirlineCommercialFactsProvider)? = nil) {
        self.provider = provider
    }

    func assessment(
        for flight: Flight,
        orderSession: EphemeralAirlineOrderSession? = nil,
        at date: Date
    ) async -> AirlineCapacityAssessment {
        guard let provider else {
            return .unknown(
                flightID: flight.id,
                reason: .providerNotConfigured,
                advisory: "No airline order or capacity provider is configured. Baggage allowance, oversale status, and bin space remain unknown."
            )
        }

        let usableSession = orderSession?.isCurrent(at: date) == true ? orderSession : nil
        do {
            let snapshot = try await provider.facts(
                for: AirlineCommercialFactsQuery(
                    flightID: flight.id,
                    airlineCode: flight.airlineCode,
                    orderSession: usableSession
                ),
                at: date
            )
            guard snapshot.flightID == flight.id else {
                return .unknown(
                    flightID: flight.id,
                    reason: .providerFailure,
                    advisory: "The airline facts response belongs to a different flight."
                )
            }
            return AirlineCapacityNormalizer().normalize(snapshot, at: date)
        } catch {
            return .unknown(
                flightID: flight.id,
                reason: .providerFailure,
                advisory: "Airline commercial facts could not be refreshed. Check the airline directly."
            )
        }
    }
}

struct AirlineCapacityNormalizer: Sendable {
    func normalize(_ snapshot: AirlineCommercialFactsSnapshot, at date: Date) -> AirlineCapacityAssessment {
        var unresolved: [String] = []

        let baggage = normalizedBaggage(snapshot.baggageAllowance, at: date, unresolved: &unresolved)
        let seat = normalizedSeat(snapshot.seatAvailability, at: date, unresolved: &unresolved)
        let overbooking = normalizedOverbooking(snapshot.overbooking, at: date, unresolved: &unresolved)
        let binSpace = normalizedBinSpace(snapshot.cabinBinSpace, at: date, unresolved: &unresolved)

        let knownCount = [baggage != nil, seat != nil, overbooking != nil, binSpace != nil].filter { $0 }.count
        let availability: AirlineCapacityAvailability
        if knownCount == 0 {
            availability = .unavailable
        } else if knownCount == 4 {
            availability = .available
        } else {
            availability = .partial
        }

        return AirlineCapacityAssessment(
            flightID: snapshot.flightID,
            availability: availability,
            unavailableReason: knownCount == 0 ? (unresolved.isEmpty ? .noVerifiedFacts : .staleFacts) : nil,
            baggageAllowance: baggage,
            seatAvailability: seat,
            overbooking: overbooking,
            cabinBinSpace: binSpace,
            unresolvedFacts: Array(Set(unresolved)).sorted(),
            advisory: "Seat maps and fare inventory are availability signals, not proof against overbooking or a guarantee of overhead-bin space. Confirm traveler-specific facts with the operating airline."
        )
    }

    private func normalizedBaggage(
        _ fact: SourcedAirlineFact<TravelerBaggageAllowance>?,
        at date: Date,
        unresolved: inout [String]
    ) -> SourcedAirlineFact<TravelerBaggageAllowance>? {
        guard let fact else {
            unresolved.append("baggage allowance")
            return nil
        }
        guard fact.isCurrent(at: date) else {
            unresolved.append("current baggage allowance")
            return nil
        }

        let accepted: Set<AirlineFactVerification> = [
            .verifiedAirlineOrder,
            .verifiedAirlinePNR,
            .verifiedNDCOffer,
            .verifiedAirlinePolicy
        ]
        guard accepted.contains(fact.verification) else {
            unresolved.append("verified baggage allowance")
            return nil
        }

        if fact.value.appliesToTicketedTraveler && !fact.verification.isTravelerOrderEvidence {
            return fact.replacingValue(TravelerBaggageAllowance(
                appliesToTicketedTraveler: false,
                limits: fact.value.limits,
                conditions: fact.value.conditions
            ))
        }
        return fact
    }

    private func normalizedSeat(
        _ fact: SourcedAirlineFact<SeatAvailabilityObservation>?,
        at date: Date,
        unresolved: inout [String]
    ) -> SourcedAirlineFact<SeatAvailabilityObservation>? {
        guard let fact else {
            unresolved.append("seat availability")
            return nil
        }
        guard fact.isCurrent(at: date) else {
            unresolved.append("current seat availability")
            return nil
        }

        let original = fact.value
        let normalizedState: SeatAvailabilityState
        switch original.state {
        case .travelerSeatConfirmed, .travelerReservationConfirmed:
            if fact.verification.isTravelerOrderEvidence {
                normalizedState = original.state
            } else if fact.verification == .seatMapProxy {
                normalizedState = .seatMapObserved
            } else if fact.verification == .fareInventoryProxy || fact.verification == .verifiedNDCOffer {
                normalizedState = .offerAvailable
            } else {
                normalizedState = .unknown
            }
        case .offerAvailable, .offerUnavailable:
            normalizedState = original.state
        case .seatMapObserved:
            normalizedState = .seatMapObserved
        case .unknown:
            normalizedState = .unknown
        }

        return fact.replacingValue(SeatAvailabilityObservation(
            state: normalizedState,
            observedAvailableSeatCount: original.observedAvailableSeatCount,
            assignedSeat: fact.verification.isTravelerOrderEvidence ? original.assignedSeat : nil,
            cabinOrBookingClass: original.cabinOrBookingClass
        ))
    }

    private func normalizedOverbooking(
        _ fact: SourcedAirlineFact<OverbookingObservation>?,
        at date: Date,
        unresolved: inout [String]
    ) -> SourcedAirlineFact<OverbookingObservation>? {
        guard let fact else {
            unresolved.append("overbooking status")
            return nil
        }
        guard fact.isCurrent(at: date) else {
            unresolved.append("current overbooking status")
            return nil
        }

        let state: OverbookingState
        switch fact.value.state {
        case .airlineConfirmedOversold, .airlineConfirmedNotOversold:
            state = fact.verification.isAirlineOperationalEvidence
                ? fact.value.state
                : .possibleProxySignal
        case .possibleProxySignal:
            state = .possibleProxySignal
        case .unknown:
            state = .unknown
        }
        return fact.replacingValue(OverbookingObservation(state: state, note: fact.value.note))
    }

    private func normalizedBinSpace(
        _ fact: SourcedAirlineFact<CabinBinSpaceObservation>?,
        at date: Date,
        unresolved: inout [String]
    ) -> SourcedAirlineFact<CabinBinSpaceObservation>? {
        guard let fact else {
            unresolved.append("cabin bin space")
            return nil
        }
        guard fact.isCurrent(at: date) else {
            unresolved.append("current cabin bin space")
            return nil
        }

        let sourceIsForbiddenProxy = fact.verification == .seatMapProxy || fact.verification == .fareInventoryProxy
        if sourceIsForbiddenProxy {
            return fact.replacingValue(CabinBinSpaceObservation(
                state: .unknown,
                probability: nil,
                explicitlyGuaranteedByAirline: false,
                note: "Seat-map or fare-inventory data cannot establish cabin-bin space."
            ))
        }

        let explicitOperationalGuarantee = fact.verification.isAirlineOperationalEvidence
            && fact.value.explicitlyGuaranteedByAirline
        let state: CabinBinSpaceState
        switch fact.value.state {
        case .airlineGuaranteedForTraveler:
            state = explicitOperationalGuarantee ? .airlineGuaranteedForTraveler : .airlineReportedAvailable
        case .airlineReportedAvailable, .estimatedAvailable, .estimatedLimited, .unknown:
            state = fact.value.state
        }

        let probability = fact.value.probability.flatMap { (0...1).contains($0) ? $0 : nil }
        return fact.replacingValue(CabinBinSpaceObservation(
            state: state,
            probability: probability,
            explicitlyGuaranteedByAirline: explicitOperationalGuarantee,
            note: fact.value.note
        ))
    }
}

private extension AirlineCapacityAssessment {
    static func unknown(
        flightID: String,
        reason: AirlineCapacityUnavailableReason,
        advisory: String
    ) -> AirlineCapacityAssessment {
        AirlineCapacityAssessment(
            flightID: flightID,
            availability: .unavailable,
            unavailableReason: reason,
            baggageAllowance: nil,
            seatAvailability: nil,
            overbooking: nil,
            cabinBinSpace: nil,
            unresolvedFacts: ["baggage allowance", "seat availability", "overbooking status", "cabin bin space"],
            advisory: advisory
        )
    }
}

// MARK: - Priced offers and external booking

protocol PricedFlightOfferProvider: Sendable {
    var providerID: String { get }
    func offers(
        for query: FlightOfferSearchQuery,
        at date: Date
    ) async throws -> [SourcedAirlineFact<PricedFlightOffer>]
}

protocol ExternalBookingHandoffProvider: Sendable {
    var providerID: String { get }
    func handoff(
        for offer: SourcedAirlineFact<PricedFlightOffer>,
        at date: Date
    ) async throws -> SourcedAirlineFact<ExternalBookingHandoff>
}

struct FlightOfferCatalogService: Sendable {
    let provider: (any PricedFlightOfferProvider)?

    init(provider: (any PricedFlightOfferProvider)? = nil) {
        self.provider = provider
    }

    func offers(for query: FlightOfferSearchQuery, at date: Date) async -> FlightOfferCatalogResult {
        guard query.isValid, let provider else {
            return FlightOfferCatalogResult(
                availability: .unavailable,
                offers: [],
                advisory: "No valid live flight-offer provider is configured."
            )
        }

        do {
            let response = try await provider.offers(for: query, at: date)
            let permittedEvidence: Set<AirlineFactVerification> = [
                .verifiedAirlineOffer,
                .verifiedNDCOffer
            ]
            let valid = response.filter {
                permittedEvidence.contains($0.verification)
                    && $0.isCurrent(at: date)
                    && $0.value.isValid(at: date)
                    && $0.value.providerOfferExpiresAt <= ($0.expiresAt ?? .distantPast)
            }
            return FlightOfferCatalogResult(
                availability: valid.isEmpty ? .unavailable : .available,
                offers: valid,
                advisory: valid.isEmpty
                    ? "No current, verified provider offers are available."
                    : "Prices and availability are time-limited. Airport XR Companion hands booking to the provider and does not issue tickets or take payment."
            )
        } catch {
            return FlightOfferCatalogResult(
                availability: .unavailable,
                offers: [],
                advisory: "Flight offers could not be refreshed."
            )
        }
    }
}

struct ExternalBookingHandoffService: Sendable {
    let provider: (any ExternalBookingHandoffProvider)?

    init(provider: (any ExternalBookingHandoffProvider)? = nil) {
        self.provider = provider
    }

    func handoff(
        for offer: SourcedAirlineFact<PricedFlightOffer>,
        at date: Date
    ) async -> ExternalBookingHandoffResult {
        let permittedEvidence: Set<AirlineFactVerification> = [
            .verifiedAirlineOffer,
            .verifiedNDCOffer
        ]
        guard permittedEvidence.contains(offer.verification),
              offer.isCurrent(at: date),
              offer.value.isValid(at: date),
              let provider else {
            return ExternalBookingHandoffResult(
                availability: .unavailable,
                handoff: nil,
                advisory: "A current verified offer and external booking provider are required."
            )
        }

        do {
            let result = try await provider.handoff(for: offer, at: date)
            guard permittedEvidence.contains(result.verification),
                  result.isCurrent(at: date),
                  result.value.isValid(at: date),
                  result.value.offerID == offer.value.id else {
                return ExternalBookingHandoffResult(
                    availability: .unavailable,
                    handoff: nil,
                    advisory: "The external handoff failed identity, freshness, HTTPS, or provenance validation."
                )
            }
            return ExternalBookingHandoffResult(
                availability: .available,
                handoff: result,
                advisory: "Booking and payment continue on the provider's HTTPS site or app."
            )
        } catch {
            return ExternalBookingHandoffResult(
                availability: .unavailable,
                handoff: nil,
                advisory: "The external booking handoff is temporarily unavailable."
            )
        }
    }
}

// MARK: - Connection baggage and planning segments

protocol ConnectionBaggageProvider: Sendable {
    var providerID: String { get }
    func baggageHandling(
        for query: ConnectionBaggageQuery,
        at date: Date
    ) async throws -> SourcedAirlineFact<ConnectionBaggageHandling>
}

struct ConnectionBaggageService: Sendable {
    let provider: (any ConnectionBaggageProvider)?

    init(provider: (any ConnectionBaggageProvider)? = nil) {
        self.provider = provider
    }

    func assessment(for query: ConnectionBaggageQuery, at date: Date) async -> ConnectionBaggageAssessment {
        guard let provider else {
            return unavailable(query: query, advisory: "No verified connection-baggage provider is configured.")
        }

        let usableQuery = ConnectionBaggageQuery(
            itineraryID: query.itineraryID,
            inboundLegID: query.inboundLegID,
            outboundLegID: query.outboundLegID,
            inboundArrivalAirportCode: query.inboundArrivalAirportCode,
            outboundDepartureAirportCode: query.outboundDepartureAirportCode,
            orderSession: query.orderSession?.isCurrent(at: date) == true ? query.orderSession : nil
        )

        do {
            let fact = try await provider.baggageHandling(for: usableQuery, at: date)
            return ConnectionBaggageNormalizer().normalize(fact, query: query, at: date)
        } catch {
            return unavailable(query: query, advisory: "Connection baggage handling could not be refreshed; confirm with the operating airlines.")
        }
    }

    private func unavailable(
        query: ConnectionBaggageQuery,
        advisory: String
    ) -> ConnectionBaggageAssessment {
        ConnectionBaggageAssessment(
            itineraryID: query.itineraryID,
            inboundLegID: query.inboundLegID,
            outboundLegID: query.outboundLegID,
            handling: nil,
            availability: .unavailable,
            advisory: advisory
        )
    }
}

struct ConnectionBaggageNormalizer: Sendable {
    func normalize(
        _ fact: SourcedAirlineFact<ConnectionBaggageHandling>,
        query: ConnectionBaggageQuery,
        at date: Date
    ) -> ConnectionBaggageAssessment {
        guard fact.isCurrent(at: date) else {
            return ConnectionBaggageAssessment(
                itineraryID: query.itineraryID,
                inboundLegID: query.inboundLegID,
                outboundLegID: query.outboundLegID,
                handling: nil,
                availability: .unavailable,
                advisory: "The connection baggage record is stale or has unknown freshness."
            )
        }

        let verifiedSpecificEvidence: Set<AirlineFactVerification> = [
            .verifiedAirlineOperations,
            .verifiedAirlineOrder,
            .verifiedAirlinePNR,
            .verifiedAirlineOffer,
            .verifiedNDCOffer
        ]
        let hasSpecificEvidence = verifiedSpecificEvidence.contains(fact.verification)

        let normalizedState: ConnectionBaggageState
        let availability: ConnectionBaggageAvailability
        switch fact.value.state {
        case .throughChecked, .reclaimImmigrationCustomsRecheck, .selfTransferSeparateTicket:
            if hasSpecificEvidence {
                normalizedState = fact.value.state
                availability = .verified
            } else {
                normalizedState = .confirmationRequired
                availability = .requiresConfirmation
            }
        case .confirmationRequired:
            normalizedState = .confirmationRequired
            availability = .requiresConfirmation
        case .unknown:
            normalizedState = .unknown
            availability = .unavailable
        }

        let normalized = fact.replacingValue(ConnectionBaggageHandling(
            state: normalizedState,
            bagTagDestinationAirportCode: hasSpecificEvidence ? fact.value.bagTagDestinationAirportCode : nil,
            separateTickets: hasSpecificEvidence ? fact.value.separateTickets : nil,
            instructions: fact.value.instructions
        ))
        let advisory: String
        switch normalizedState {
        case .throughChecked:
            advisory = "Your bags appear to transfer automatically. Check the bag tag at check-in."
        case .reclaimImmigrationCustomsRecheck:
            advisory = "Collect and recheck your bags before the next flight."
        case .selfTransferSeparateTicket:
            advisory = "This is a self-transfer. Collect and recheck your bags."
        case .confirmationRequired:
            advisory = "Ask the airline if your bags transfer automatically."
        case .unknown:
            advisory = "We don't have enough information about your bags."
        }

        return ConnectionBaggageAssessment(
            itineraryID: query.itineraryID,
            inboundLegID: query.inboundLegID,
            outboundLegID: query.outboundLegID,
            handling: normalized,
            availability: availability,
            advisory: advisory
        )
    }
}

struct ConnectionTransferPlanBuilder: Sendable {
    func build(
        query: ConnectionBaggageQuery,
        baggage: ConnectionBaggageAssessment,
        inputs: ConnectionPlanningInputs,
        at date: Date
    ) -> ConnectionTransferPlanInput {
        guard baggage.itineraryID == query.itineraryID,
              baggage.inboundLegID == query.inboundLegID,
              baggage.outboundLegID == query.outboundLegID else {
            return ConnectionTransferPlanInput(
                itineraryID: query.itineraryID,
                inboundLegID: query.inboundLegID,
                outboundLegID: query.outboundLegID,
                baggageState: .unknown,
                segments: [],
                unresolvedInputs: ["matching connection baggage assessment"],
                sourceRecordIDs: []
            )
        }

        var required = inputs.additionalRequiredSegments
        switch baggage.state {
        case .throughChecked:
            break
        case .reclaimImmigrationCustomsRecheck:
            required.formUnion([
                .baggageWait,
                .borderProcessing,
                .customsProcessing,
                .landsideTransfer,
                .bagDropAndCheckIn,
                .securityScreening
            ])
        case .selfTransferSeparateTicket:
            required.formUnion([
                .baggageWait,
                .landsideTransfer,
                .bagDropAndCheckIn,
                .securityScreening
            ])
        case .confirmationRequired, .unknown:
            break
        }

        if query.inboundArrivalAirportCode != query.outboundDepartureAirportCode {
            required.insert(.interAirportTravel)
        }

        var unresolved: [String] = []
        if baggage.state == .confirmationRequired || baggage.state == .unknown {
            unresolved.append("verified connection baggage handling")
        }

        let segments = required.sorted { $0.rawValue < $1.rawValue }.map { kind in
            let duration = inputs.durations[kind]
            let deadline = inputs.deadlines[kind]
            if duration == nil {
                unresolved.append("\(title(for: kind)) duration")
            } else if duration?.isExpired(at: date) == true {
                unresolved.append("\(title(for: kind)) freshness")
            }
            if kind == .bagDropAndCheckIn {
                if deadline == nil {
                    unresolved.append("bag-drop/check-in cutoff")
                } else if deadline?.isExpired(at: date) == true {
                    unresolved.append("bag-drop/check-in cutoff freshness")
                }
            }
            return ConnectionPlanningSegment(
                kind: kind,
                title: title(for: kind),
                duration: duration,
                deadline: deadline,
                requiredForPositiveRecommendation: true
            )
        }

        var sourceRecordIDs = segments.flatMap { segment in
            [segment.duration?.sourceRecordID, segment.deadline?.sourceRecordID].compactMap { $0 }
        }
        if let baggageRecordID = baggage.handling?.sourceRecordID {
            sourceRecordIDs.append(baggageRecordID)
        }

        return ConnectionTransferPlanInput(
            itineraryID: query.itineraryID,
            inboundLegID: query.inboundLegID,
            outboundLegID: query.outboundLegID,
            baggageState: baggage.state,
            segments: segments,
            unresolvedInputs: Array(Set(unresolved)).sorted(),
            sourceRecordIDs: Array(Set(sourceRecordIDs)).sorted()
        )
    }

    private func title(for kind: ConnectionPlanningSegmentKind) -> String {
        switch kind {
        case .baggageWait: "Baggage reclaim wait"
        case .borderProcessing: "Immigration or border processing"
        case .customsProcessing: "Customs processing"
        case .landsideTransfer: "Landside connection movement"
        case .bagDropAndCheckIn: "Bag drop and check-in"
        case .securityScreening: "Security screening"
        case .interAirportTravel: "Inter-airport travel"
        }
    }
}
