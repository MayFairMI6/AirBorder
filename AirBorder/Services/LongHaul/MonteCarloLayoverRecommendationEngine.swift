import Foundation

struct MonteCarloLayoverRecommendationEngine: LayoverRecommendationEngine {
    let policy: SafetyPolicy

    init(policy: SafetyPolicy = .current) {
        self.policy = policy
    }

    func assess(
        itinerary: Itinerary,
        layover: LayoverContext,
        candidate: PlanCandidate,
        profile: TravelerProfile,
        snapshotRevision: String,
        seed suppliedSeed: UInt64?,
        now: Date
    ) -> FeasibilityAssessment {
        let seed = suppliedSeed ?? StableSimulationSeed.snapshot(
            itineraryID: itinerary.id,
            inputRevision: itinerary.inputRevision,
            snapshotRevision: snapshotRevision,
            policyVersion: policy.version
        )
        var traceSteps: [DerivationStep] = []
        var sources: [String] = []
        var unresolved: [String] = []

        guard let inbound = layover.inboundOnBlock,
              let gateClose = layover.onwardGateClose else {
            if layover.inboundOnBlock == nil { unresolved.append("inbound on-block time") }
            if layover.onwardGateClose == nil { unresolved.append("onward gate-close time") }
            return unresolvedAssessment(
                candidate: candidate,
                available: nil,
                seed: seed,
                unresolved: unresolved,
                steps: traceSteps,
                sources: sources,
                now: now
            )
        }

        let available = gateClose.timeIntervalSince(inbound) / 60
        traceSteps.append(DerivationStep(
            label: "Available window",
            formula: "onward gate-close - inbound on-block",
            inputRecordIDs: [layover.id],
            result: formattedMinutes(available)
        ))

        if available <= 0 {
            return fixedAssessment(
                candidate: candidate,
                status: .notRecommended,
                summary: "There isn't enough time before your next gate closes.",
                available: available,
                required: nil,
                usableRest: nil,
                latestReturn: nil,
                seed: seed,
                unresolved: [],
                steps: traceSteps,
                sources: sources,
                now: now
            )
        }

        var distributions: [EstimateDistribution] = []
        for segment in candidate.segments {
            guard let metric = segment.duration else {
                if segment.requiredForPositiveRecommendation { unresolved.append(segment.title) }
                continue
            }
            sources.append(metric.sourceRecordID)
            traceSteps.append(contentsOf: metric.derivation)
            if metric.isExpired(at: now) && segment.requiredForPositiveRecommendation {
                unresolved.append("\(segment.title) freshness")
            } else if metric.value.isValid {
                distributions.append(adjustedDistribution(metric.value, for: segment.kind, profile: profile))
            } else if segment.requiredForPositiveRecommendation {
                unresolved.append("\(segment.title) distribution")
            }
        }

        if candidate.requiresLandsideExit || candidate.place?.accessZone != .airside {
            guard let entry = candidate.entryAssessment else {
                unresolved.append("entry requirements")
                return unresolvedAssessment(candidate: candidate, available: available, seed: seed, unresolved: unresolved, steps: traceSteps, sources: sources, now: now)
            }
            sources.append(entry.sourceRecordID)
            if entry.status == .authorizationRequired {
                return fixedAssessment(
                    candidate: candidate,
                    status: .notRecommended,
                    summary: "Stay airside until you check the entry rules.",
                    available: available,
                    required: distributions.reduce(0) { $0 + $1.mostLikely },
                    usableRest: nil,
                    latestReturn: nil,
                    seed: seed,
                    unresolved: [],
                    steps: traceSteps,
                    sources: sources,
                    now: now
                )
            }
            if !entry.canSupportLandsideRecommendation(profile: profile, at: now) {
                unresolved.append(entry.isCurrent(at: now) ? "official entry-rule confirmation" : "current entry requirements")
            }
        }

        guard unresolved.isEmpty else {
            return unresolvedAssessment(candidate: candidate, available: available, seed: seed, unresolved: unresolved, steps: traceSteps, sources: sources, now: now)
        }

        var generator = ReplayableRandomNumberGenerator(seed: seed)
        var successes = 0
        for _ in 0..<policy.simulationTrials {
            let required = distributions.reduce(0) { $0 + triangularSample($1, generator: &generator) }
            if required <= available { successes += 1 }
        }
        let interval = wilsonInterval(successes: successes, trials: policy.simulationTrials)
        let status = policy.classification(for: interval, hasUnresolvedCriticalInputs: false)
        let mostLikely = distributions.reduce(0) { $0 + $1.mostLikely }
        let nonRestKinds: Set<PlanSegmentKind> = [.access, .checkIn, .returnTravel, .reentry, .security, .terminalRoute, .safety]
        let nonRest = candidate.segments.reduce(0.0) { total, segment in
            guard nonRestKinds.contains(segment.kind), let value = segment.duration?.value else { return total }
            return total + adjustedDistribution(value, for: segment.kind, profile: profile).mostLikely
        }
        let usableRest = max(0, available - nonRest)
        let returnComponents: Set<PlanSegmentKind> = [.returnTravel, .reentry, .checkIn, .security, .terminalRoute, .safety]
        let returnMinutes = candidate.segments.reduce(0.0) { total, segment in
            guard returnComponents.contains(segment.kind), let value = segment.duration?.value else { return total }
            return total + adjustedDistribution(value, for: segment.kind, profile: profile).mostLikely
        }
        let latestReturn = gateClose.addingTimeInterval(-returnMinutes * 60)

        if let lastService = candidate.latestReturnReference, lastService < latestReturn {
            traceSteps.append(DerivationStep(
                label: "Last service filter",
                formula: "last usable service >= calculated latest return departure",
                inputRecordIDs: sources,
                result: "Failed"
            ))
            return fixedAssessment(
                candidate: candidate,
                status: .notRecommended,
                summary: "The last service leaves too late for this plan.",
                available: available,
                required: mostLikely,
                usableRest: usableRest,
                latestReturn: latestReturn,
                seed: seed,
                unresolved: [],
                steps: traceSteps,
                sources: sources,
                now: now
            )
        }

        traceSteps.append(DerivationStep(
            label: "Required time",
            formula: "deplane + conditional border/bags/customs + outbound + activity + return + re-entry/security + terminal route",
            inputRecordIDs: sources,
            result: formattedMinutes(mostLikely)
        ))
        if profile.walkingPace != .typical {
            traceSteps.append(DerivationStep(
                label: "Walking pace adjustment",
                formula: "walking segments × \(profile.walkingPace.walkingMultiplier)",
                inputRecordIDs: [],
                result: profile.walkingPace.title
            ))
        }
        traceSteps.append(DerivationStep(
            label: "On-time probability",
            formula: "P(required time <= available window), triangular segment distributions, Wilson 95% interval",
            inputRecordIDs: sources,
            result: "\(percent(interval.estimate)) (95% CI \(percent(interval.lower95))-\(percent(interval.upper95)))"
        ))

        let summary: String = switch status {
        case .safe:
            "This plan leaves enough time based on the information currently available. Keep watching for travel updates."
        case .tight:
            "This plan may leave too little time. Choose an airport option or shorten the activity."
        case .requiresConfirmation:
            "Important travel information still needs confirmation."
        case .notRecommended:
            "This plan is unlikely to leave enough time for your onward flight."
        }
        return FeasibilityAssessment(
            candidateID: candidate.id,
            status: status,
            probability: interval,
            availableWindowMinutes: available,
            requiredMostLikelyMinutes: mostLikely,
            usableRestMinutes: usableRest,
            latestReturnTime: latestReturn,
            summary: summary,
            trace: CalculationTrace(
                policyVersion: policy.version,
                simulationSeed: seed,
                generatedAt: now,
                steps: traceSteps,
                sourceRecordIDs: Array(Set(sources)).sorted(),
                unresolvedInputs: []
            )
        )
    }

    private func adjustedDistribution(
        _ distribution: EstimateDistribution,
        for kind: PlanSegmentKind,
        profile: TravelerProfile
    ) -> EstimateDistribution {
        let walkingKinds: Set<PlanSegmentKind> = [.access, .outboundTravel, .returnTravel, .terminalRoute]
        guard walkingKinds.contains(kind), profile.walkingPace != .typical else { return distribution }
        let multiplier = profile.walkingPace.walkingMultiplier
        return EstimateDistribution(
            lower: distribution.lower * multiplier,
            mostLikely: distribution.mostLikely * multiplier,
            upper: distribution.upper * multiplier,
            unit: distribution.unit
        )
    }

    private func triangularSample(
        _ distribution: EstimateDistribution,
        generator: inout ReplayableRandomNumberGenerator
    ) -> Double {
        guard distribution.upper > distribution.lower else { return distribution.lower }
        let unit = generator.unitInterval()
        let span = distribution.upper - distribution.lower
        let split = (distribution.mostLikely - distribution.lower) / span
        if unit < split {
            return distribution.lower + sqrt(unit * span * (distribution.mostLikely - distribution.lower))
        }
        return distribution.upper - sqrt((1 - unit) * span * (distribution.upper - distribution.mostLikely))
    }

    private func wilsonInterval(successes: Int, trials: Int) -> ProbabilityInterval {
        let n = Double(trials)
        let observed = Double(successes) / n
        let z = policy.normalCriticalValue
        let denominator = 1 + (z * z / n)
        let center = (observed + z * z / (2 * n)) / denominator
        let radius = z * sqrt(observed * (1 - observed) / n + z * z / (4 * n * n)) / denominator
        return ProbabilityInterval(
            estimate: observed,
            lower95: max(0, center - radius),
            upper95: min(1, center + radius),
            trials: trials
        )
    }

    private func unresolvedAssessment(
        candidate: PlanCandidate,
        available: Double?,
        seed: UInt64,
        unresolved: [String],
        steps: [DerivationStep],
        sources: [String],
        now: Date
    ) -> FeasibilityAssessment {
        fixedAssessment(
            candidate: candidate,
            status: .requiresConfirmation,
            summary: "We don't have enough information yet.",
            available: available,
            required: nil,
            usableRest: nil,
            latestReturn: nil,
            seed: seed,
            unresolved: unresolved,
            steps: steps,
            sources: sources,
            now: now
        )
    }

    private func fixedAssessment(
        candidate: PlanCandidate,
        status: FeasibilityStatus,
        summary: String,
        available: Double?,
        required: Double?,
        usableRest: Double?,
        latestReturn: Date?,
        seed: UInt64,
        unresolved: [String],
        steps: [DerivationStep],
        sources: [String],
        now: Date
    ) -> FeasibilityAssessment {
        FeasibilityAssessment(
            candidateID: candidate.id,
            status: status,
            probability: nil,
            availableWindowMinutes: available,
            requiredMostLikelyMinutes: required,
            usableRestMinutes: usableRest,
            latestReturnTime: latestReturn,
            summary: summary,
            trace: CalculationTrace(
                policyVersion: policy.version,
                simulationSeed: seed,
                generatedAt: now,
                steps: steps,
                sourceRecordIDs: Array(Set(sources)).sorted(),
                unresolvedInputs: unresolved
            )
        )
    }

    private func formattedMinutes(_ value: Double) -> String {
        "\(Int(value.rounded())) min"
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
