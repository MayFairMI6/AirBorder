import Foundation

enum SampleTerminalGraph {
    /// Clearly labeled QA/demo graph. Distances and walking durations are fixture
    /// observations, not claims about Haneda's production indoor geometry.
    static let hanedaTerminal3Demo = TerminalGraph(
        version: "demo-hnd-t3-graph-v1",
        nodes: [
            TerminalNode(id: "t3-transfer-security", name: "International Transfer Security", point: MapPoint(x: 0.10, y: 0.55), level: 3, kind: .security),
            TerminalNode(id: "t3-departures-center", name: "Departures Center", point: MapPoint(x: 0.30, y: 0.55), level: 3, kind: .corridor),
            TerminalNode(id: "t3-elevator-north", name: "North Elevator", point: MapPoint(x: 0.46, y: 0.72), level: 3, kind: .elevator),
            TerminalNode(id: "t3-escalator-north", name: "North Escalator", point: MapPoint(x: 0.46, y: 0.36), level: 3, kind: .escalator),
            TerminalNode(id: "t3-gates-center", name: "International Gates", point: MapPoint(x: 0.65, y: 0.55), level: 4, kind: .corridor),
            TerminalNode(id: "gate-105", name: "Gate 105", point: MapPoint(x: 0.87, y: 0.34), level: 4, kind: .gate),
            TerminalNode(id: "gate-108", name: "Gate 108", point: MapPoint(x: 0.88, y: 0.66), level: 4, kind: .gate),
            TerminalNode(id: "t3-work-pod", name: "Work Pod Area", point: MapPoint(x: 0.34, y: 0.82), level: 3, kind: .lounge),
            TerminalNode(id: "t3-shower", name: "Shower Rooms", point: MapPoint(x: 0.67, y: 0.79), level: 4, kind: .marker)
        ],
        edges: [
            demoEdge("h1", "t3-transfer-security", "t3-departures-center", meters: 92, seconds: 104),
            TerminalEdge(id: "h2-elevator", from: "t3-departures-center", to: "t3-elevator-north", distanceMeters: 78, walkingSeconds: 128, wheelchairAccessible: true, hasStairs: false, hasEscalator: false, hasElevator: true, narrowPassage: false, temporarilyClosed: false, crowdPenalty: 0.18, levelChange: 1, directionComplexity: 0.15),
            TerminalEdge(id: "h2-escalator", from: "t3-departures-center", to: "t3-escalator-north", distanceMeters: 62, walkingSeconds: 82, wheelchairAccessible: false, hasStairs: false, hasEscalator: true, hasElevator: false, narrowPassage: false, temporarilyClosed: false, crowdPenalty: 0.31, levelChange: 1, directionComplexity: 0.12),
            demoEdge("h3-elevator", "t3-elevator-north", "t3-gates-center", meters: 91, seconds: 112),
            demoEdge("h3-escalator", "t3-escalator-north", "t3-gates-center", meters: 84, seconds: 96),
            demoEdge("h4", "t3-gates-center", "gate-105", meters: 146, seconds: 164),
            demoEdge("h5", "t3-gates-center", "gate-108", meters: 172, seconds: 193),
            demoEdge("h6", "t3-departures-center", "t3-work-pod", meters: 74, seconds: 86),
            demoEdge("h7", "t3-gates-center", "t3-shower", meters: 88, seconds: 101)
        ]
    )

    static let terminal2 = TerminalGraph(
        version: "T2-synthetic-1",
        nodes: [
            TerminalNode(id: "security-exit", name: "Security Exit", point: MapPoint(x: 0.10, y: 0.52), level: 1, kind: .security),
            TerminalNode(id: "junction-a", name: "Concourse Junction", point: MapPoint(x: 0.30, y: 0.52), level: 1, kind: .corridor),
            TerminalNode(id: "stairs-c", name: "Concourse Stairs", point: MapPoint(x: 0.47, y: 0.36), level: 1, kind: .stairs),
            TerminalNode(id: "elevator-c", name: "Accessible Elevator", point: MapPoint(x: 0.48, y: 0.68), level: 1, kind: .elevator),
            TerminalNode(id: "junction-c", name: "C Gates Junction", point: MapPoint(x: 0.66, y: 0.52), level: 2, kind: .corridor),
            TerminalNode(id: "gate-c8", name: "Gate C8", point: MapPoint(x: 0.82, y: 0.32), level: 2, kind: .gate),
            TerminalNode(id: "gate-c12", name: "Gate C12", point: MapPoint(x: 0.88, y: 0.58), level: 2, kind: .gate),
            TerminalNode(id: "train", name: "Airport Train", point: MapPoint(x: 0.28, y: 0.82), level: 1, kind: .train),
            TerminalNode(id: "restroom", name: "Accessible Restroom", point: MapPoint(x: 0.65, y: 0.76), level: 2, kind: .restroom)
        ],
        edges: [
            edge("e1", "security-exit", "junction-a", 80, 90),
            TerminalEdge(id: "e2-stairs", from: "junction-a", to: "stairs-c", distanceMeters: 70, walkingSeconds: 75, wheelchairAccessible: false, hasStairs: true, hasEscalator: false, hasElevator: false, narrowPassage: false, temporarilyClosed: false, crowdPenalty: 0.2, levelChange: 1, directionComplexity: 0.2),
            TerminalEdge(id: "e3-stairs", from: "stairs-c", to: "junction-c", distanceMeters: 70, walkingSeconds: 75, wheelchairAccessible: false, hasStairs: true, hasEscalator: false, hasElevator: false, narrowPassage: false, temporarilyClosed: false, crowdPenalty: 0.2, levelChange: 0, directionComplexity: 0.2),
            TerminalEdge(id: "e2-elevator", from: "junction-a", to: "elevator-c", distanceMeters: 90, walkingSeconds: 140, wheelchairAccessible: true, hasStairs: false, hasEscalator: false, hasElevator: true, narrowPassage: false, temporarilyClosed: false, crowdPenalty: 0.1, levelChange: 1, directionComplexity: 0.1),
            TerminalEdge(id: "e3-elevator", from: "elevator-c", to: "junction-c", distanceMeters: 90, walkingSeconds: 140, wheelchairAccessible: true, hasStairs: false, hasEscalator: false, hasElevator: true, narrowPassage: false, temporarilyClosed: false, crowdPenalty: 0.1, levelChange: 0, directionComplexity: 0.1),
            edge("e4", "junction-c", "gate-c8", 85, 90),
            edge("e5", "junction-c", "gate-c12", 120, 110),
            edge("e6", "junction-a", "train", 120, 130),
            edge("e7", "junction-c", "restroom", 80, 85),
            TerminalEdge(id: "construction", from: "gate-c8", to: "gate-c12", distanceMeters: 60, walkingSeconds: 70, wheelchairAccessible: true, hasStairs: false, hasEscalator: false, hasElevator: false, narrowPassage: true, temporarilyClosed: true, crowdPenalty: 0.8, levelChange: 0, directionComplexity: 0.5)
        ]
    )

    private static func edge(_ id: String, _ from: String, _ to: String, _ meters: Double, _ seconds: Double) -> TerminalEdge {
        TerminalEdge(id: id, from: from, to: to, distanceMeters: meters, walkingSeconds: seconds, wheelchairAccessible: true, hasStairs: false, hasEscalator: false, hasElevator: false, narrowPassage: false, temporarilyClosed: false, crowdPenalty: 0.25, levelChange: 0, directionComplexity: 0.25)
    }

    private static func demoEdge(_ id: String, _ from: String, _ to: String, meters: Double, seconds: Double) -> TerminalEdge {
        TerminalEdge(
            id: id,
            from: from,
            to: to,
            distanceMeters: meters,
            walkingSeconds: seconds,
            wheelchairAccessible: true,
            hasStairs: false,
            hasEscalator: false,
            hasElevator: false,
            narrowPassage: false,
            temporarilyClosed: false,
            crowdPenalty: 0.22,
            levelChange: 0,
            directionComplexity: 0.18
        )
    }
}
