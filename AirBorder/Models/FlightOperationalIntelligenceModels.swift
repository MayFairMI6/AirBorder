import Foundation

// MARK: - Delay context

enum FlightDelayFeatureCategory: String, Codable, Hashable, Sendable {
    case weather
    case weatherDisruptionNews
    case congestion
    case inboundRotation
    case schedule
}

enum FlightDelayFeatureKind: String, Codable, CaseIterable, Hashable, Sendable {
    case departureWindGust
    case arrivalWindGust
    case departureVisibility
    case arrivalVisibility
    case departureCeiling
    case arrivalCeiling
    case departurePrecipitationRate
    case arrivalPrecipitationRate
    case departureConvectiveWeatherProbability
    case arrivalConvectiveWeatherProbability
    case airportWeatherDisruptionReportProbability
    case departureAirportDelay
    case arrivalAirportDelay
    case departureDemandToCapacityRatio
    case arrivalDemandToCapacityRatio
    case departureGroundDelayProgram
    case arrivalGroundDelayProgram
    case inboundAircraftArrivalDelay
    case scheduledTurnSlack
    case aircraftSwap
    case scheduledBlockTime

    var category: FlightDelayFeatureCategory {
        switch self {
        case .departureWindGust, .arrivalWindGust,
             .departureVisibility, .arrivalVisibility,
             .departureCeiling, .arrivalCeiling,
             .departurePrecipitationRate, .arrivalPrecipitationRate,
             .departureConvectiveWeatherProbability, .arrivalConvectiveWeatherProbability:
            .weather
        case .airportWeatherDisruptionReportProbability:
            .weatherDisruptionNews
        case .departureAirportDelay, .arrivalAirportDelay,
             .departureDemandToCapacityRatio, .arrivalDemandToCapacityRatio,
             .departureGroundDelayProgram, .arrivalGroundDelayProgram:
            .congestion
        case .inboundAircraftArrivalDelay, .scheduledTurnSlack, .aircraftSwap:
            .inboundRotation
        case .scheduledBlockTime:
            .schedule
        }
    }
}

enum FlightDelayFeatureUnit: String, Codable, Hashable, Sendable {
    case knots
    case meters
    case feet
    case millimetersPerHour
    case minutes
    case probability
    case ratio
    case binaryIndicator
}

/// A single model feature with enough provenance to reject stale or
/// untraceable inputs. Provider adapters retain their source units rather than
/// hiding conversions in unnamed constants.
struct SourcedFlightDelayFeature: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: FlightDelayFeatureKind
    let value: Double
    let unit: FlightDelayFeatureUnit
    let provider: String
    let providerField: String
    let sourceRecordID: String
    let observedAt: Date
    let receivedAt: Date
    let expiresAt: Date?
    let uncertainty: String?
    let derivation: [DerivationStep]

    init(
        id: String? = nil,
        kind: FlightDelayFeatureKind,
        value: Double,
        unit: FlightDelayFeatureUnit,
        provider: String,
        providerField: String,
        sourceRecordID: String,
        observedAt: Date,
        receivedAt: Date,
        expiresAt: Date?,
        uncertainty: String? = nil,
        derivation: [DerivationStep] = []
    ) {
        self.id = id ?? "\(sourceRecordID)|\(providerField)|\(kind.rawValue)"
        self.kind = kind
        self.value = value
        self.unit = unit
        self.provider = provider
        self.providerField = providerField
        self.sourceRecordID = sourceRecordID
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.expiresAt = expiresAt
        self.uncertainty = uncertainty
        self.derivation = derivation
    }

    var isSemanticallyValid: Bool {
        guard value.isFinite,
              !provider.isEmpty,
              !providerField.isEmpty,
              !sourceRecordID.isEmpty,
              observedAt <= receivedAt else {
            return false
        }

        switch unit {
        case .probability:
            return (0...1).contains(value)
        case .binaryIndicator:
            return value == 0 || value == 1
        case .knots, .meters, .feet, .millimetersPerHour, .ratio:
            return value >= 0
        case .minutes:
            return true
        }
    }

    /// Operational features must carry a provider-defined expiry. An absent
    /// expiry is unknown freshness, not an invitation to cache indefinitely.
    func isCurrent(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return observedAt <= date && receivedAt <= date && expiresAt > date
    }
}

struct FlightDelayFeatureSnapshot: Codable, Hashable, Sendable {
    let flightID: String
    let revision: String
    let assembledAt: Date
    let features: [FlightDelayFeatureKind: SourcedFlightDelayFeature]

    var sourceRecordIDs: [String] {
        Array(Set(features.values.map(\.sourceRecordID))).sorted()
    }
}

enum FlightDelayTarget: String, Codable, Hashable, Sendable {
    case departureDelayMinutes
    case arrivalDelayMinutes
}

enum FlightDelayAlgorithmFamily: String, Codable, Hashable, Sendable {
    case quantileRegression
    case survivalModel
    case probabilisticEnsemble
    case externalProviderDistribution
}

struct FlightDelayModelDescriptor: Codable, Hashable, Sendable {
    let id: String
    let version: String
    let featureSchemaVersion: String
    let target: FlightDelayTarget
    let algorithmFamily: FlightDelayAlgorithmFamily
    let requiredFeatures: Set<FlightDelayFeatureKind>
    let trainedAt: Date?
    let calibratedThrough: Date?
    let trainingPolicyVersion: String
}

struct DelayQuantile: Codable, Hashable, Sendable {
    let probability: Double
    let minutes: Double
}

struct DelayExceedanceProbability: Codable, Hashable, Sendable {
    let thresholdMinutes: Double
    let probability: Double
}

/// A distribution is carried instead of a fabricated point estimate. Negative
/// minutes are valid and represent an early operation relative to schedule.
struct FlightDelayDistribution: Codable, Hashable, Sendable {
    let target: FlightDelayTarget
    let quantiles: [DelayQuantile]
    let meanMinutes: Double?
    let exceedanceProbabilities: [DelayExceedanceProbability]

    var isValid: Bool {
        guard !quantiles.isEmpty,
              meanMinutes.map({ $0.isFinite }) ?? true else {
            return false
        }

        var previousProbability = -Double.infinity
        var previousMinutes = -Double.infinity
        for quantile in quantiles {
            guard quantile.probability.isFinite,
                  quantile.minutes.isFinite,
                  quantile.probability > 0,
                  quantile.probability < 1,
                  quantile.probability > previousProbability,
                  quantile.minutes >= previousMinutes else {
                return false
            }
            previousProbability = quantile.probability
            previousMinutes = quantile.minutes
        }

        var previousThreshold = -Double.infinity
        var previousExceedance = Double.infinity
        for exceedance in exceedanceProbabilities {
            guard exceedance.thresholdMinutes.isFinite,
                  exceedance.probability.isFinite,
                  (0...1).contains(exceedance.probability),
                  exceedance.thresholdMinutes > previousThreshold,
                  exceedance.probability <= previousExceedance else {
                return false
            }
            previousThreshold = exceedance.thresholdMinutes
            previousExceedance = exceedance.probability
        }
        return true
    }
}

struct FlightDelayModelOutput: Codable, Hashable, Sendable {
    let flightID: String
    let distribution: FlightDelayDistribution
    let usedFeatures: Set<FlightDelayFeatureKind>
    let generatedAt: Date
    let expiresAt: Date
    let derivation: [DerivationStep]
}

enum FlightDelayPredictionAvailability: String, Codable, Hashable, Sendable {
    case available
    case unavailable
}

enum FlightDelayUnavailableReason: String, Codable, Hashable, Sendable {
    case modelNotConfigured
    case featureProviderUnavailable
    case missingRequiredFeatures
    case staleRequiredFeatures
    case invalidFeatures
    case modelFailure
    case invalidDistribution
    case flightIdentityMismatch
    case predictionExpired
    case targetNotApplicableToLayover
}

struct FlightDelayPrediction: Codable, Hashable, Sendable {
    let flightID: String
    let availability: FlightDelayPredictionAvailability
    let unavailableReason: FlightDelayUnavailableReason?
    let distribution: FlightDelayDistribution?
    let model: FlightDelayModelDescriptor?
    let featureRevision: String?
    let generatedAt: Date
    let expiresAt: Date?
    let sourceRecordIDs: [String]
    let missingFeatures: [FlightDelayFeatureKind]
    let staleFeatures: [FlightDelayFeatureKind]
    let trace: [DerivationStep]
    let advisory: String
}

enum PredictionOperationalRole: String, Codable, Hashable, Sendable {
    case scenarioContextOnly
}

/// Feed-ready timing context for the layover engine. The official status and
/// official effective arrival remain present and authoritative; the predicted
/// arrival-offset distribution is optional scenario context only.
struct LayoverFlightDelayScenarioInput: Codable, Hashable, Sendable {
    let flightID: String
    let officialStatus: FlightStatus
    let officialEffectiveArrival: Date?
    let officialProviderName: String
    let predictionRole: PredictionOperationalRole
    let predictedArrivalDelay: FlightDelayDistribution?
    let predictionAvailability: FlightDelayPredictionAvailability
    let unavailableReason: FlightDelayUnavailableReason?
    let predictionExpiresAt: Date?
    let sourceRecordIDs: [String]
}

// MARK: - Airline order, capacity, and baggage facts

enum AirlineFactVerification: String, Codable, Hashable, Sendable {
    case verifiedAirlineOperations
    case verifiedAirlineOrder
    case verifiedAirlinePNR
    case verifiedAirlineOffer
    case verifiedNDCOffer
    case verifiedAirlinePolicy
    case carrierMatchProxy
    case fareInventoryProxy
    case seatMapProxy
    case thirdPartyEstimate
    case unknown

    var isTravelerOrderEvidence: Bool {
        self == .verifiedAirlineOrder || self == .verifiedAirlinePNR
    }

    var isAirlineOperationalEvidence: Bool {
        self == .verifiedAirlineOperations
    }
}

struct SourcedAirlineFact<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    let value: Value
    let verification: AirlineFactVerification
    let provider: String
    let providerField: String
    let sourceRecordID: String
    let observedAt: Date
    let receivedAt: Date
    let expiresAt: Date?
    let isLive: Bool
    let derivation: [DerivationStep]

    func isCurrent(at date: Date) -> Bool {
        guard isLive,
              observedAt <= receivedAt,
              observedAt <= date,
              receivedAt <= date,
              let expiresAt else {
            return false
        }
        return expiresAt > date
    }

    func replacingValue(_ value: Value) -> SourcedAirlineFact<Value> {
        SourcedAirlineFact(
            value: value,
            verification: verification,
            provider: provider,
            providerField: providerField,
            sourceRecordID: sourceRecordID,
            observedAt: observedAt,
            receivedAt: receivedAt,
            expiresAt: expiresAt,
            isLive: isLive,
            derivation: derivation
        )
    }
}

enum BaggageCategory: String, Codable, Hashable, Sendable {
    case personalItem
    case cabinBag
    case checkedBag
}

struct BaggageDimensionLimit: Codable, Hashable, Sendable {
    let lengthCentimeters: Double
    let widthCentimeters: Double
    let heightCentimeters: Double
}

struct BaggageLimit: Codable, Hashable, Sendable {
    let category: BaggageCategory
    let pieceCount: Int?
    let maximumWeightKilograms: Double?
    let maximumDimensions: BaggageDimensionLimit?
}

struct TravelerBaggageAllowance: Codable, Hashable, Sendable {
    let appliesToTicketedTraveler: Bool
    let limits: [BaggageLimit]
    let conditions: [String]
}

enum SeatAvailabilityState: String, Codable, Hashable, Sendable {
    case travelerSeatConfirmed
    case travelerReservationConfirmed
    case offerAvailable
    case seatMapObserved
    case offerUnavailable
    case unknown
}

struct SeatAvailabilityObservation: Codable, Hashable, Sendable {
    let state: SeatAvailabilityState
    let observedAvailableSeatCount: Int?
    let assignedSeat: String?
    let cabinOrBookingClass: String?
}

enum OverbookingState: String, Codable, Hashable, Sendable {
    case airlineConfirmedOversold
    case airlineConfirmedNotOversold
    case possibleProxySignal
    case unknown
}

struct OverbookingObservation: Codable, Hashable, Sendable {
    let state: OverbookingState
    let note: String
}

enum CabinBinSpaceState: String, Codable, Hashable, Sendable {
    case airlineGuaranteedForTraveler
    case airlineReportedAvailable
    case estimatedAvailable
    case estimatedLimited
    case unknown
}

struct CabinBinSpaceObservation: Codable, Hashable, Sendable {
    let state: CabinBinSpaceState
    let probability: Double?
    let explicitlyGuaranteedByAirline: Bool
    let note: String
}

struct AirlineCommercialFactsSnapshot: Codable, Hashable, Sendable {
    let flightID: String
    let revision: String
    let baggageAllowance: SourcedAirlineFact<TravelerBaggageAllowance>?
    let seatAvailability: SourcedAirlineFact<SeatAvailabilityObservation>?
    let overbooking: SourcedAirlineFact<OverbookingObservation>?
    let cabinBinSpace: SourcedAirlineFact<CabinBinSpaceObservation>?
}

enum AirlineCapacityAvailability: String, Codable, Hashable, Sendable {
    case available
    case partial
    case unavailable
}

enum AirlineCapacityUnavailableReason: String, Codable, Hashable, Sendable {
    case providerNotConfigured
    case providerFailure
    case staleFacts
    case noVerifiedFacts
}

struct AirlineCapacityAssessment: Codable, Hashable, Sendable {
    let flightID: String
    let availability: AirlineCapacityAvailability
    let unavailableReason: AirlineCapacityUnavailableReason?
    let baggageAllowance: SourcedAirlineFact<TravelerBaggageAllowance>?
    let seatAvailability: SourcedAirlineFact<SeatAvailabilityObservation>?
    let overbooking: SourcedAirlineFact<OverbookingObservation>?
    let cabinBinSpace: SourcedAirlineFact<CabinBinSpaceObservation>?
    let unresolvedFacts: [String]
    let advisory: String
}

/// An in-memory, short-lived reference issued by the server integration. It is
/// intentionally not Codable so an app cache cannot accidentally persist a raw
/// booking reference or airline session credential.
struct EphemeralAirlineOrderSession: Hashable, Sendable {
    let opaqueHandle: String
    let expiresAt: Date

    func isCurrent(at date: Date) -> Bool {
        !opaqueHandle.isEmpty && expiresAt > date
    }
}

struct AirlineCommercialFactsQuery: Hashable, Sendable {
    let flightID: String
    let airlineCode: String?
    let orderSession: EphemeralAirlineOrderSession?
}

// MARK: - Priced offers and external booking handoff

struct FlightOfferRouteRequest: Codable, Hashable, Sendable {
    let originAirportCode: String
    let destinationAirportCode: String
    let departureDate: Date
}

struct FlightOfferTravelerCounts: Codable, Hashable, Sendable {
    let adults: Int
    let children: Int
    let lapInfants: Int

    var isValid: Bool {
        adults > 0 && children >= 0 && lapInfants >= 0 && lapInfants <= adults
    }
}

struct FlightOfferSearchQuery: Codable, Hashable, Sendable {
    let routes: [FlightOfferRouteRequest]
    let travelers: FlightOfferTravelerCounts
    let requestedCabin: String?
    let currencyCode: String

    var isValid: Bool {
        !routes.isEmpty
            && routes.allSatisfy {
                $0.originAirportCode.count == 3
                    && $0.destinationAirportCode.count == 3
                    && $0.originAirportCode != $0.destinationAirportCode
            }
            && travelers.isValid
            && currencyCode.count == 3
    }
}

struct OfferedFlightLeg: Codable, Hashable, Sendable {
    let id: String
    let marketingCarrierCode: String
    let operatingCarrierCode: String?
    let flightNumber: String
    let originAirportCode: String
    let destinationAirportCode: String
    let scheduledDeparture: Date
    let scheduledArrival: Date
    let cabin: String?
    let bookingClass: String?

    var isValid: Bool {
        !id.isEmpty
            && !marketingCarrierCode.isEmpty
            && !flightNumber.isEmpty
            && originAirportCode.count == 3
            && destinationAirportCode.count == 3
            && scheduledArrival > scheduledDeparture
    }
}

/// The decimal string is retained exactly as normalized by the provider proxy;
/// binary floating-point rounding must not alter a displayed offer price.
struct FlightOfferPrice: Codable, Hashable, Sendable {
    let decimalAmount: String
    let currencyCode: String

    var decimalValue: Decimal? {
        Decimal(string: decimalAmount, locale: Locale(identifier: "en_US_POSIX"))
    }

    var isValid: Bool {
        guard currencyCode.count == 3,
              let decimalValue else {
            return false
        }
        return decimalValue >= 0
    }
}

enum AirportXRBookingRole: String, Codable, Hashable, Sendable {
    case externalHandoffOnly
}

struct PricedFlightOffer: Codable, Hashable, Sendable {
    let id: String
    let legs: [OfferedFlightLeg]
    let totalPrice: FlightOfferPrice
    let fareBrand: String?
    let quotedBaggageAllowance: TravelerBaggageAllowance?
    let providerOfferExpiresAt: Date
    let bookingRole: AirportXRBookingRole

    func isValid(at date: Date) -> Bool {
        !id.isEmpty
            && !legs.isEmpty
            && legs.allSatisfy(\.isValid)
            && totalPrice.isValid
            && providerOfferExpiresAt > date
            && bookingRole == .externalHandoffOnly
    }
}

struct ExternalBookingHandoff: Codable, Hashable, Sendable {
    let offerID: String
    let providerName: String
    let url: URL
    let expiresAt: Date
    let bookingRole: AirportXRBookingRole

    func isValid(at date: Date) -> Bool {
        !offerID.isEmpty
            && !providerName.isEmpty
            && url.scheme?.lowercased() == "https"
            && expiresAt > date
            && bookingRole == .externalHandoffOnly
    }
}

enum FlightOfferCatalogAvailability: String, Codable, Hashable, Sendable {
    case available
    case unavailable
}

struct FlightOfferCatalogResult: Codable, Hashable, Sendable {
    let availability: FlightOfferCatalogAvailability
    let offers: [SourcedAirlineFact<PricedFlightOffer>]
    let advisory: String
}

enum ExternalBookingHandoffAvailability: String, Codable, Hashable, Sendable {
    case available
    case unavailable
}

struct ExternalBookingHandoffResult: Codable, Hashable, Sendable {
    let availability: ExternalBookingHandoffAvailability
    let handoff: SourcedAirlineFact<ExternalBookingHandoff>?
    let advisory: String
}

// MARK: - Connection baggage handling and additive risk inputs

enum ConnectionBaggageState: String, Codable, Hashable, Sendable {
    case throughChecked
    case reclaimImmigrationCustomsRecheck
    case selfTransferSeparateTicket
    case confirmationRequired
    case unknown
}

struct ConnectionBaggageHandling: Codable, Hashable, Sendable {
    let state: ConnectionBaggageState
    let bagTagDestinationAirportCode: String?
    let separateTickets: Bool?
    let instructions: [String]
}

struct ConnectionBaggageQuery: Hashable, Sendable {
    let itineraryID: UUID
    let inboundLegID: UUID
    let outboundLegID: UUID
    let inboundArrivalAirportCode: String
    let outboundDepartureAirportCode: String
    let orderSession: EphemeralAirlineOrderSession?
}

enum ConnectionBaggageAvailability: String, Codable, Hashable, Sendable {
    case verified
    case requiresConfirmation
    case unavailable
}

struct ConnectionBaggageAssessment: Codable, Hashable, Sendable {
    let itineraryID: UUID
    let inboundLegID: UUID
    let outboundLegID: UUID
    let handling: SourcedAirlineFact<ConnectionBaggageHandling>?
    let availability: ConnectionBaggageAvailability
    let advisory: String

    var state: ConnectionBaggageState {
        handling?.value.state ?? .unknown
    }
}

enum ConnectionPlanningSegmentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case baggageWait
    case borderProcessing
    case customsProcessing
    case landsideTransfer
    case bagDropAndCheckIn
    case securityScreening
    case interAirportTravel

    var layoverSegmentKind: PlanSegmentKind {
        switch self {
        case .baggageWait: .baggage
        case .borderProcessing: .border
        case .customsProcessing: .customs
        case .landsideTransfer: .outboundTravel
        case .bagDropAndCheckIn: .checkIn
        case .securityScreening: .security
        case .interAirportTravel: .outboundTravel
        }
    }
}

struct ConnectionPlanningInputs: Codable, Hashable, Sendable {
    let durations: [ConnectionPlanningSegmentKind: SourcedMetric<EstimateDistribution>]
    let deadlines: [ConnectionPlanningSegmentKind: SourcedMetric<Date>]
    let additionalRequiredSegments: Set<ConnectionPlanningSegmentKind>
}

struct ConnectionPlanningSegment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: ConnectionPlanningSegmentKind
    let title: String
    let duration: SourcedMetric<EstimateDistribution>?
    let deadline: SourcedMetric<Date>?
    let requiredForPositiveRecommendation: Bool

    init(
        id: UUID? = nil,
        kind: ConnectionPlanningSegmentKind,
        title: String,
        duration: SourcedMetric<EstimateDistribution>?,
        deadline: SourcedMetric<Date>?,
        requiredForPositiveRecommendation: Bool = true
    ) {
        self.id = id ?? StableEntityID.uuid(
            "connection-segment|\(kind.rawValue)|\(duration?.sourceRecordID ?? "unknown")|\(deadline?.sourceRecordID ?? "no-deadline")"
        )
        self.kind = kind
        self.title = title
        self.duration = duration
        self.deadline = deadline
        self.requiredForPositiveRecommendation = requiredForPositiveRecommendation
    }

    var layoverPlanSegment: PlanSegment {
        PlanSegment(
            kind: kind.layoverSegmentKind,
            title: title,
            duration: duration,
            requiredForPositiveRecommendation: requiredForPositiveRecommendation
        )
    }
}

struct ConnectionTransferPlanInput: Codable, Hashable, Sendable {
    let itineraryID: UUID
    let inboundLegID: UUID
    let outboundLegID: UUID
    let baggageState: ConnectionBaggageState
    let segments: [ConnectionPlanningSegment]
    let unresolvedInputs: [String]
    let sourceRecordIDs: [String]

    var canSupportPositiveRecommendation: Bool {
        unresolvedInputs.isEmpty
            && baggageState != .confirmationRequired
            && baggageState != .unknown
    }

    /// Existing layover probability engines can consume this additive view;
    /// the exact connection-specific kind remains available on `segments` for
    /// traces and UI explanations.
    var layoverPlanSegments: [PlanSegment] {
        segments.map(\.layoverPlanSegment)
    }
}
