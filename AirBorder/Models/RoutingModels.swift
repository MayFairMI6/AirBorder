import Foundation

struct MapPoint: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
}

struct TerminalNode: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case corridor
        case gate
        case security
        case immigration
        case baggage
        case restroom
        case restaurant
        case snack
        case clothing
        case electronics
        case lounge
        case elevator
        case escalator
        case stairs
        case train
        case bus
        case marker
    }

    let id: String
    let name: String
    let point: MapPoint
    let level: Int
    let kind: Kind
}

struct TerminalEdge: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let from: String
    let to: String
    let distanceMeters: Double
    let walkingSeconds: Double
    let wheelchairAccessible: Bool
    let hasStairs: Bool
    let hasEscalator: Bool
    let hasElevator: Bool
    let narrowPassage: Bool
    let temporarilyClosed: Bool
    let crowdPenalty: Double
    let levelChange: Int
    let directionComplexity: Double
}

struct TerminalGraph: Codable, Sendable {
    let version: String
    let nodes: [TerminalNode]
    let edges: [TerminalEdge]
}

enum RouteMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case fastest
    case accessible
    case leastWalking
    case fewestLevelChanges
    case simplestDirections
    case lowCrowd

    var id: String { rawValue }

    var title: String {
        return switch self {
        case .fastest: "Fastest"
        case .accessible: "Accessible"
        case .leastWalking: "Least walking"
        case .fewestLevelChanges: "Fewest levels"
        case .simplestDirections: "Simplest"
        case .lowCrowd: "Low crowd"
        }
    }
}

struct TerminalRoute: Codable, Equatable, Sendable {
    let nodeIDs: [String]
    let edgeIDs: [String]
    let distanceMeters: Double
    let durationSeconds: Double
    let mode: RouteMode

    var durationMinutes: Int { max(1, Int(ceil(durationSeconds / 60))) }
}

enum RouteError: Error, Equatable, Sendable {
    case missingStart
    case missingDestination
    case noAccessibleRoute
    case noRoute
}
