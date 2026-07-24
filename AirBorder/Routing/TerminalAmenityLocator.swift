import Foundation

enum PassengerAmenityCategory: String, CaseIterable, Identifiable, Sendable {
    case restroom
    case meal
    case snackDrink
    case clothing
    case electronics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restroom: "Restroom"
        case .meal: "Meal"
        case .snackDrink: "Snack or drink"
        case .clothing: "Clothing"
        case .electronics: "Electronics"
        }
    }

    var symbol: String {
        switch self {
        case .restroom: "figure.dress.line.vertical.figure"
        case .meal: "fork.knife"
        case .snackDrink: "takeoutbag.and.cup.and.straw.fill"
        case .clothing: "tshirt.fill"
        case .electronics: "headphones"
        }
    }

    var terminalKinds: Set<TerminalNode.Kind> {
        switch self {
        case .restroom: [.restroom]
        case .meal: [.restaurant]
        case .snackDrink: [.snack]
        case .clothing: [.clothing]
        case .electronics: [.electronics]
        }
    }
}

struct TerminalAmenityMatch: Identifiable, Equatable, Sendable {
    let node: TerminalNode
    let routeDistanceMeters: Double?
    var id: String { node.id }
}

struct TerminalAmenitySearchResult: Equatable, Sendable {
    let category: PassengerAmenityCategory
    let matches: [TerminalAmenityMatch]
    let usesCurrentLevel: Bool
    let hasDistanceTie: Bool
}

struct TerminalAmenityLocator {
    /// Indoor graph distances are recorded in metres. Treat results that differ
    /// by less than one recorded metre as tied instead of claiming false precision.
    private static let distanceTieToleranceMeters = 1.0

    private let router = TerminalRouter()

    func nearest(
        category: PassengerAmenityCategory,
        in graph: TerminalGraph,
        from currentNodeID: String,
        preferences: AccessibilityPreferences
    ) -> TerminalAmenitySearchResult {
        let allCandidates = graph.nodes.filter { category.terminalKinds.contains($0.kind) }
        guard let current = graph.nodes.first(where: { $0.id == currentNodeID }), !allCandidates.isEmpty else {
            return TerminalAmenitySearchResult(category: category, matches: [], usesCurrentLevel: false, hasDistanceTie: false)
        }

        let currentLevelCandidates = allCandidates.filter { $0.level == current.level }
        let candidates = currentLevelCandidates.isEmpty ? allCandidates : currentLevelCandidates
        let measured = candidates.map { node in
            let distance = try? router.route(
                in: graph,
                from: currentNodeID,
                to: node.id,
                mode: .leastWalking,
                preferences: preferences
            ).distanceMeters
            return TerminalAmenityMatch(node: node, routeDistanceMeters: distance)
        }

        let reachable = measured.compactMap { match -> TerminalAmenityMatch? in
            match.routeDistanceMeters == nil ? nil : match
        }
        guard let minimum = reachable.compactMap(\.routeDistanceMeters).min() else {
            return TerminalAmenitySearchResult(
                category: category,
                matches: measured.sorted { $0.node.name.localizedCaseInsensitiveCompare($1.node.name) == .orderedAscending },
                usesCurrentLevel: !currentLevelCandidates.isEmpty,
                hasDistanceTie: measured.count > 1
            )
        }

        let closest = reachable
            .filter { abs(($0.routeDistanceMeters ?? minimum) - minimum) < Self.distanceTieToleranceMeters }
            .sorted { $0.node.name.localizedCaseInsensitiveCompare($1.node.name) == .orderedAscending }
        return TerminalAmenitySearchResult(
            category: category,
            matches: closest,
            usesCurrentLevel: !currentLevelCandidates.isEmpty,
            hasDistanceTie: closest.count > 1
        )
    }
}
