import Foundation

/// Versioned presentation policy for translating route geometry into familiar
/// walking-direction language. These are angular bands, not routing or safety
/// assumptions: the graph still determines where the traveler walks.
enum RouteTurnPresentationPolicy {
    static let version = "route-turn-presentation-v1"
    static let straightMaximumDegrees = 15.0
    static let slightMaximumDegrees = 45.0
    static let standardMaximumDegrees = 120.0
    static let sharpMaximumDegrees = 165.0
}

enum CompassHeading: String, CaseIterable, Equatable, Sendable {
    case north
    case northeast
    case east
    case southeast
    case south
    case southwest
    case west
    case northwest

    init(degrees: Double) {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let sector = Int(((normalized + 22.5) / 45).rounded(.down)) % Self.allCases.count
        self = Self.allCases[sector]
    }
}

enum RouteManeuverKind: String, Equatable, Sendable {
    case depart
    case continueStraight
    case slightLeft
    case left
    case sharpLeft
    case slightRight
    case right
    case sharpRight
    case uTurn
    case elevator
    case escalator
    case levelChange

    var systemImage: String {
        switch self {
        case .depart, .continueStraight: "arrow.up"
        case .slightLeft: "arrow.up.left"
        case .left: "arrow.turn.up.left"
        case .sharpLeft: "arrow.turn.up.left"
        case .slightRight: "arrow.up.right"
        case .right: "arrow.turn.up.right"
        case .sharpRight: "arrow.turn.up.right"
        case .uTurn: "arrow.uturn.backward"
        case .elevator: "arrow.up.arrow.down.square"
        case .escalator: "figure.stairs"
        case .levelChange: "arrow.up.right"
        }
    }
}

struct RouteManeuver: Equatable, Sendable {
    let instruction: String
    let destinationName: String
    let distanceMeters: Double
    let stepNumber: Int
    let stepCount: Int
    let kind: RouteManeuverKind
    let heading: CompassHeading

    var systemImage: String { kind.systemImage }
}

/// Converts the selected graph path into an instruction using only graph
/// geometry and edge metadata. It does not invent a distance or a turn.
struct RouteManeuverBuilder: Sendable {
    func currentManeuver(
        graph: TerminalGraph,
        route: TerminalRoute?,
        currentNodeID: String
    ) -> RouteManeuver? {
        guard let route,
              let currentIndex = route.nodeIDs.firstIndex(of: currentNodeID),
              route.nodeIDs.indices.contains(currentIndex + 1) else { return nil }

        let nextID = route.nodeIDs[currentIndex + 1]
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        guard let current = nodes[currentNodeID],
              let next = nodes[nextID],
              let edge = graph.edges.first(where: {
                  ($0.from == currentNodeID && $0.to == nextID)
                      || ($0.to == currentNodeID && $0.from == nextID)
              }) else { return nil }

        let outgoingX = next.point.x - current.point.x
        let outgoingY = next.point.y - current.point.y
        let headingDegrees = atan2(outgoingX, outgoingY) * 180 / .pi
        let heading = CompassHeading(degrees: headingDegrees)
        let direction: (instruction: String, kind: RouteManeuverKind)

        if edge.levelChange != 0 {
            if edge.hasElevator {
                direction = ("Take the elevator to level \(next.level)", .elevator)
            } else if edge.hasEscalator {
                direction = ("Take the escalator to level \(next.level)", .escalator)
            } else {
                direction = ("Change to level \(next.level)", .levelChange)
            }
        } else if currentIndex > 0, let previous = nodes[route.nodeIDs[currentIndex - 1]] {
            let incomingX = current.point.x - previous.point.x
            let incomingY = current.point.y - previous.point.y
            let signedAngle = signedTurnDegrees(
                incomingX: incomingX,
                incomingY: incomingY,
                outgoingX: outgoingX,
                outgoingY: outgoingY
            )
            let kind = turnKind(signedAngleDegrees: signedAngle)
            direction = (instruction(for: kind, heading: heading, destination: next.name), kind)
        } else {
            direction = ("Head \(heading.rawValue) toward \(next.name)", .depart)
        }

        return RouteManeuver(
            instruction: direction.instruction,
            destinationName: next.name,
            distanceMeters: edge.distanceMeters,
            stepNumber: currentIndex + 1,
            stepCount: max(route.nodeIDs.count - 1, 1),
            kind: direction.kind,
            heading: heading
        )
    }

    func turnKind(signedAngleDegrees: Double) -> RouteManeuverKind {
        let magnitude = abs(signedAngleDegrees)
        if magnitude <= RouteTurnPresentationPolicy.straightMaximumDegrees { return .continueStraight }
        if magnitude >= RouteTurnPresentationPolicy.sharpMaximumDegrees { return .uTurn }

        let isLeft = signedAngleDegrees > 0
        if magnitude <= RouteTurnPresentationPolicy.slightMaximumDegrees {
            return isLeft ? .slightLeft : .slightRight
        }
        if magnitude <= RouteTurnPresentationPolicy.standardMaximumDegrees {
            return isLeft ? .left : .right
        }
        return isLeft ? .sharpLeft : .sharpRight
    }

    private func signedTurnDegrees(
        incomingX: Double,
        incomingY: Double,
        outgoingX: Double,
        outgoingY: Double
    ) -> Double {
        let cross = incomingX * outgoingY - incomingY * outgoingX
        let dot = incomingX * outgoingX + incomingY * outgoingY
        return atan2(cross, dot) * 180 / .pi
    }

    private func instruction(
        for kind: RouteManeuverKind,
        heading: CompassHeading,
        destination: String
    ) -> String {
        switch kind {
        case .continueStraight: "Continue \(heading.rawValue) toward \(destination)"
        case .slightLeft: "Bear left toward \(destination)"
        case .left: "Turn left toward \(destination)"
        case .sharpLeft: "Make a sharp left toward \(destination)"
        case .slightRight: "Bear right toward \(destination)"
        case .right: "Turn right toward \(destination)"
        case .sharpRight: "Make a sharp right toward \(destination)"
        case .uTurn: "Make a U-turn toward \(destination)"
        case .depart: "Head \(heading.rawValue) toward \(destination)"
        case .elevator: "Take the elevator toward \(destination)"
        case .escalator: "Take the escalator toward \(destination)"
        case .levelChange: "Change levels toward \(destination)"
        }
    }
}
