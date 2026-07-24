import Foundation

enum PlanSegmentKind: String, Codable, Sendable {
    case deplane
    case border
    case baggage
    case customs
    case outboundTravel
    case activity
    case returnTravel
    case reentry
    case security
    case terminalRoute
    case access
    case checkIn
    case safety
}

struct PlanSegment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: PlanSegmentKind
    let title: String
    let duration: SourcedMetric<EstimateDistribution>?
    let requiredForPositiveRecommendation: Bool

    init(
        id: UUID? = nil,
        kind: PlanSegmentKind,
        title: String,
        duration: SourcedMetric<EstimateDistribution>?,
        requiredForPositiveRecommendation: Bool = true
    ) {
        self.id = id ?? StableEntityID.uuid("segment|\(kind.rawValue)|\(title)|\(duration?.sourceRecordID ?? "unknown")")
        self.kind = kind
        self.title = title
        self.duration = duration
        self.requiredForPositiveRecommendation = requiredForPositiveRecommendation
    }
}

struct PlanCandidate: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let place: LayoverPlace?
    let segments: [PlanSegment]
    let entryAssessment: EntryAssessment?
    let latestReturnReference: Date?
    let intent: PlanCandidateIntent
    let requiresLandsideExit: Bool

    init(
        id: UUID? = nil,
        title: String,
        place: LayoverPlace?,
        segments: [PlanSegment],
        entryAssessment: EntryAssessment?,
        latestReturnReference: Date? = nil,
        intent: PlanCandidateIntent = .general,
        requiresLandsideExit: Bool = false
    ) {
        self.id = id ?? StableEntityID.uuid(
            "candidate|\(title)|\(place?.id ?? "none")|\(segments.map { $0.id.uuidString }.joined(separator: "|"))"
        )
        self.title = title
        self.place = place
        self.segments = segments
        self.entryAssessment = entryAssessment
        self.latestReturnReference = latestReturnReference
        self.intent = intent
        self.requiresLandsideExit = requiresLandsideExit
    }
}

/// Stable plan meaning for routing and display. Do not infer this from title text.
enum PlanCandidateIntent: String, Codable, Hashable, Sendable {
    case general
    case airportTransfer
    case transferRouteStop
}

enum FeasibilityStatus: String, Codable, CaseIterable, Sendable {
    case safe
    case tight
    case requiresConfirmation
    case notRecommended

    var title: String {
        switch self {
        case .safe: "Safe"
        case .tight: "Tight"
        case .requiresConfirmation: "More info needed"
        case .notRecommended: "Not recommended"
        }
    }
}

struct ProbabilityInterval: Codable, Hashable, Sendable {
    let estimate: Double
    let lower95: Double
    let upper95: Double
    let trials: Int
}

struct FeasibilityAssessment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let candidateID: UUID
    let status: FeasibilityStatus
    let probability: ProbabilityInterval?
    let availableWindowMinutes: Double?
    let requiredMostLikelyMinutes: Double?
    let usableRestMinutes: Double?
    let latestReturnTime: Date?
    let summary: String
    let trace: CalculationTrace

    init(
        id: UUID? = nil,
        candidateID: UUID,
        status: FeasibilityStatus,
        probability: ProbabilityInterval?,
        availableWindowMinutes: Double?,
        requiredMostLikelyMinutes: Double?,
        usableRestMinutes: Double?,
        latestReturnTime: Date?,
        summary: String,
        trace: CalculationTrace
    ) {
        self.id = id ?? StableEntityID.uuid("assessment|\(candidateID.uuidString)|\(status.rawValue)|\(trace.id.uuidString)")
        self.candidateID = candidateID
        self.status = status
        self.probability = probability
        self.availableWindowMinutes = availableWindowMinutes
        self.requiredMostLikelyMinutes = requiredMostLikelyMinutes
        self.usableRestMinutes = usableRestMinutes
        self.latestReturnTime = latestReturnTime
        self.summary = summary
        self.trace = trace
    }
}
