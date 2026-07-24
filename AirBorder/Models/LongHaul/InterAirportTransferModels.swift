import Foundation

struct InterAirportTransferOption: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let originAirportCode: String
    let destinationAirportCode: String
    let departureTime: Date?
    let arrivalTime: Date?
    let duration: SourcedMetric<EstimateDistribution>?
    let walkingMeters: SourcedMetric<Double>?
    let transfers: Int?
    let wheelchairAccessible: Bool?
    let luggageNotes: String
    let lastService: Date?
    let provider: String
    let freshness: DataFreshness
}

struct InterAirportTransferPlan: Codable, Hashable, Sendable {
    let selected: InterAirportTransferOption?
    let ranked: [InterAirportTransferOption]
    let unresolvedInputs: [String]
    let rationale: String

    var canClaimFastest: Bool {
        selected?.freshness == .live && unresolvedInputs.isEmpty
    }
}

protocol InterAirportTransferProvider: Sendable {
    func options(
        from origin: Airport,
        to destination: Airport,
        after date: Date
    ) async throws -> [InterAirportTransferOption]
}

struct UnavailableInterAirportTransferProvider: InterAirportTransferProvider {
    func options(
        from origin: Airport,
        to destination: Airport,
        after date: Date
    ) async throws -> [InterAirportTransferOption] {
        []
    }
}

struct InterAirportTransferPlanner: Sendable {
    func plan(
        options: [InterAirportTransferOption],
        requireAccessibility: Bool,
        now: Date
    ) -> InterAirportTransferPlan {
        let routeMatched = options.filter {
            $0.originAirportCode.uppercased() != $0.destinationAirportCode.uppercased()
                && ($0.lastService == nil || $0.lastService! >= now)
                && (!requireAccessibility || $0.wheelchairAccessible == true)
        }
        var unresolved: [String] = []
        let current = routeMatched.filter { option in
            guard option.freshness != .stale,
                  option.freshness != .unavailable,
                  let duration = option.duration,
                  !duration.isExpired(at: now),
                  duration.value.isValid else { return false }
            return true
        }
        if current.isEmpty {
            unresolved.append("current inter-airport travel time")
        }
        if requireAccessibility && routeMatched.isEmpty {
            unresolved.append("confirmed accessible transfer")
        }
        let pareto = paretoFront(current)
        let ranked = pareto.sorted(by: lexicographicFastest)
            + current.filter { candidate in !pareto.contains(where: { $0.id == candidate.id }) }.sorted(by: lexicographicFastest)
        return InterAirportTransferPlan(
            selected: unresolved.isEmpty ? ranked.first : nil,
            ranked: ranked,
            unresolvedInputs: unresolved,
            rationale: "Options are Pareto-filtered, then ordered by most-likely duration, transfers, walking distance, and stable provider ID. No scalar penalties are used."
        )
    }

    private func paretoFront(_ options: [InterAirportTransferOption]) -> [InterAirportTransferOption] {
        options.filter { candidate in
            !options.contains { other in
                guard other.id != candidate.id else { return false }
                return dominates(other, candidate)
            }
        }
    }

    private func dominates(_ lhs: InterAirportTransferOption, _ rhs: InterAirportTransferOption) -> Bool {
        guard let leftDuration = lhs.duration?.value.mostLikely,
              let rightDuration = rhs.duration?.value.mostLikely,
              let leftTransfers = lhs.transfers,
              let rightTransfers = rhs.transfers,
              let leftWalk = lhs.walkingMeters?.value,
              let rightWalk = rhs.walkingMeters?.value else { return false }
        let noWorse = leftDuration <= rightDuration && leftTransfers <= rightTransfers && leftWalk <= rightWalk
        let better = leftDuration < rightDuration || leftTransfers < rightTransfers || leftWalk < rightWalk
        return noWorse && better
    }

    private func lexicographicFastest(_ lhs: InterAirportTransferOption, _ rhs: InterAirportTransferOption) -> Bool {
        let left = [
            lhs.duration?.value.mostLikely ?? .infinity,
            Double(lhs.transfers ?? .max),
            lhs.walkingMeters?.value ?? .infinity
        ]
        let right = [
            rhs.duration?.value.mostLikely ?? .infinity,
            Double(rhs.transfers ?? .max),
            rhs.walkingMeters?.value ?? .infinity
        ]
        for (a, b) in zip(left, right) where a != b { return a < b }
        return lhs.id < rhs.id
    }
}
