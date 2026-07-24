import Foundation

/// Multi-objective indoor routing without hidden scalar penalties.
///
/// Every edge contributes physical attributes to a `RouteCostVector`. Labels that
/// are worse in every attribute are removed (Pareto filtering). The requested
/// route mode then orders the remaining labels lexicographically. This keeps the
/// trade-off visible and prevents an arbitrary multiplier from turning, for
/// example, one level change into a fabricated number of walking seconds.
struct TerminalRouter: Sendable {
    func route(
        in graph: TerminalGraph,
        from startID: String,
        to destinationID: String,
        mode: RouteMode,
        preferences: AccessibilityPreferences = .default
    ) throws -> TerminalRoute {
        let nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        guard nodesByID[startID] != nil else { throw RouteError.missingStart }
        guard nodesByID[destinationID] != nil else { throw RouteError.missingDestination }

        let adjacency = makeAdjacency(graph: graph)
        let initial = RouteLabel(nodeID: startID, nodeIDs: [startID], edges: [], cost: .zero)
        var frontier = [initial]
        var labelsByNode: [String: [RouteLabel]] = [startID: [initial]]

        while !frontier.isEmpty {
            frontier.sort { preferred($0, over: $1, mode: mode, preferences: preferences) }
            let current = frontier.removeFirst()

            for item in adjacency[current.nodeID, default: []] {
                guard !current.nodeIDs.contains(item.neighbor),
                      isAllowed(item.edge, mode: mode, preferences: preferences) else { continue }

                let candidate = current.appending(item.edge, destination: item.neighbor)
                let existing = labelsByNode[item.neighbor, default: []]
                if existing.contains(where: { $0.cost.dominates(candidate.cost) || $0.cost == candidate.cost }) {
                    continue
                }

                let survivors = existing.filter { !candidate.cost.dominates($0.cost) }
                labelsByNode[item.neighbor] = survivors + [candidate]
                frontier.removeAll { label in
                    label.nodeID == item.neighbor && candidate.cost.dominates(label.cost)
                }
                frontier.append(candidate)
            }
        }

        guard let selected = labelsByNode[destinationID]?.min(by: {
            preferred($0, over: $1, mode: mode, preferences: preferences)
        }) else {
            if mode == .accessible || preferences.wheelchairRouting { throw RouteError.noAccessibleRoute }
            throw RouteError.noRoute
        }

        return TerminalRoute(
            nodeIDs: selected.nodeIDs,
            edgeIDs: selected.edges.map(\.id),
            distanceMeters: selected.cost.distanceMeters,
            durationSeconds: selected.cost.durationSeconds,
            mode: mode
        )
    }

    private func makeAdjacency(graph: TerminalGraph) -> [String: [(neighbor: String, edge: TerminalEdge)]] {
        var result: [String: [(neighbor: String, edge: TerminalEdge)]] = [:]
        for edge in graph.edges where !edge.temporarilyClosed {
            result[edge.from, default: []].append((edge.to, edge))
            result[edge.to, default: []].append((edge.from, edge))
        }
        for key in result.keys {
            result[key]?.sort {
                $0.neighbor == $1.neighbor ? $0.edge.id < $1.edge.id : $0.neighbor < $1.neighbor
            }
        }
        return result
    }

    private func isAllowed(_ edge: TerminalEdge, mode: RouteMode, preferences: AccessibilityPreferences) -> Bool {
        let accessibilityRequired = mode == .accessible || preferences.wheelchairRouting
        if accessibilityRequired && (!edge.wheelchairAccessible || edge.hasStairs) { return false }
        if preferences.avoidStairs && edge.hasStairs { return false }
        if preferences.avoidEscalators && edge.hasEscalator { return false }
        return true
    }

    private func preferred(
        _ lhs: RouteLabel,
        over rhs: RouteLabel,
        mode: RouteMode,
        preferences: AccessibilityPreferences
    ) -> Bool {
        let left = lhs.cost.lexicographicValues(mode: mode, preferences: preferences)
        let right = rhs.cost.lexicographicValues(mode: mode, preferences: preferences)
        for (a, b) in zip(left, right) where a != b { return a < b }
        let leftKey = lhs.edges.map(\.id).joined(separator: "|")
        let rightKey = rhs.edges.map(\.id).joined(separator: "|")
        return leftKey < rightKey
    }
}

private struct RouteLabel: Equatable {
    let nodeID: String
    let nodeIDs: [String]
    let edges: [TerminalEdge]
    let cost: RouteCostVector

    func appending(_ edge: TerminalEdge, destination: String) -> RouteLabel {
        RouteLabel(
            nodeID: destination,
            nodeIDs: nodeIDs + [destination],
            edges: edges + [edge],
            cost: cost.adding(edge)
        )
    }
}

private struct RouteCostVector: Equatable {
    var durationSeconds: Double
    var distanceMeters: Double
    var levelChanges: Double
    var directionComplexity: Double
    var crowdExposure: Double
    var elevatorGaps: Double
    var narrowPassages: Double

    static let zero = RouteCostVector(
        durationSeconds: 0,
        distanceMeters: 0,
        levelChanges: 0,
        directionComplexity: 0,
        crowdExposure: 0,
        elevatorGaps: 0,
        narrowPassages: 0
    )

    func adding(_ edge: TerminalEdge) -> RouteCostVector {
        RouteCostVector(
            durationSeconds: durationSeconds + edge.walkingSeconds,
            distanceMeters: distanceMeters + edge.distanceMeters,
            levelChanges: levelChanges + Double(abs(edge.levelChange)),
            directionComplexity: directionComplexity + edge.directionComplexity,
            crowdExposure: crowdExposure + edge.crowdPenalty,
            elevatorGaps: elevatorGaps + ((edge.levelChange != 0 && !edge.hasElevator) ? 1 : 0),
            narrowPassages: narrowPassages + (edge.narrowPassage ? 1 : 0)
        )
    }

    func dominates(_ other: RouteCostVector) -> Bool {
        let left = allValues
        let right = other.allValues
        return zip(left, right).allSatisfy { $0 <= $1 }
            && zip(left, right).contains { $0 < $1 }
    }

    func lexicographicValues(mode: RouteMode, preferences: AccessibilityPreferences) -> [Double] {
        var priorities: [Double] = []
        if preferences.preferElevators { priorities.append(elevatorGaps) }
        if preferences.reduceWalking { priorities.append(distanceMeters) }

        let modePriorities: [Double] = switch mode {
        case .fastest:
            [durationSeconds, distanceMeters, levelChanges, directionComplexity, crowdExposure]
        case .accessible:
            [elevatorGaps, narrowPassages, durationSeconds, levelChanges, distanceMeters, directionComplexity, crowdExposure]
        case .leastWalking:
            [distanceMeters, durationSeconds, levelChanges, directionComplexity, crowdExposure]
        case .fewestLevelChanges:
            [levelChanges, durationSeconds, distanceMeters, directionComplexity, crowdExposure]
        case .simplestDirections:
            [directionComplexity, levelChanges, durationSeconds, distanceMeters, crowdExposure]
        case .lowCrowd:
            [crowdExposure, durationSeconds, distanceMeters, levelChanges, directionComplexity]
        }
        priorities += modePriorities
        return priorities
    }

    private var allValues: [Double] {
        [durationSeconds, distanceMeters, levelChanges, directionComplexity, crowdExposure, elevatorGaps, narrowPassages]
    }
}
