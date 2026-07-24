import Foundation
import XCTest
@testable import AirBorder

final class RiskAndRoutingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_721_000_000)

    func testBoardingRiskComfortableAndAccessibilityImpact() {
        let assessment = BoardingRiskService().assess(input(boardingInMinutes: 60, accessible: true, updatedAgo: 60))
        XCTAssertEqual(assessment.urgency, .comfortable)
        XCTAssertTrue(assessment.message.contains("accessible route adds 3 minutes"))
    }

    func testBoardingRiskLeaveSoonBoundary() {
        let assessment = BoardingRiskService().assess(input(boardingInMinutes: 22, accessible: true, updatedAgo: 60))
        XCTAssertEqual(assessment.urgency, .leaveSoon)
        XCTAssertNotNil(assessment.leaveBy)
    }

    func testBoardingStartedOverridesGateChange() {
        var value = input(boardingInMinutes: -1, accessible: true, updatedAgo: 60, gateChanged: true)
        value = BoardingRiskInput(
            scheduledBoardingTime: value.scheduledBoardingTime,
            estimatedBoardingTime: value.estimatedBoardingTime,
            departureTime: value.departureTime,
            flightStatus: .boarding,
            boardingGroup: value.boardingGroup,
            walkMinutes: value.walkMinutes,
            accessibleRouteMinutes: value.accessibleRouteMinutes,
            useAccessibleRoute: value.useAccessibleRoute,
            securityMinutes: value.securityMinutes,
            immigrationMinutes: value.immigrationMinutes,
            locationConfidence: value.locationConfidence,
            gateChanged: value.gateChanged,
            terminalChanged: value.terminalChanged,
            routeUncertaintyMinutes: value.routeUncertaintyMinutes,
            providerUpdatedAt: value.providerUpdatedAt,
            freshness: value.freshness,
            extraBufferMinutes: value.extraBufferMinutes,
            now: value.now
        )
        let assessment = BoardingRiskService().assess(value)
        XCTAssertEqual(assessment.urgency, .boarding)
        XCTAssertTrue(assessment.alerts.contains(.gateChange))
    }

    func testStaleDataIsExplicit() {
        let assessment = BoardingRiskService().assess(input(boardingInMinutes: 90, accessible: false, updatedAgo: 20 * 60))
        XCTAssertEqual(assessment.urgency, .dataStale)
        XCTAssertTrue(assessment.alerts.contains(.staleData))
    }

    func testConnectionRiskCalculation() {
        let assessment = ConnectionRiskService().assess(ConnectionRiskInput(
            inboundEstimatedArrival: now.addingTimeInterval(30 * 60),
            onwardBoardingCutoff: now.addingTimeInterval(60 * 60),
            inboundDelayMinutes: 15,
            arrivalTerminal: "2",
            connectionTerminal: "5",
            immigrationMinutes: 0,
            securityRescreenMinutes: 5,
            airportTransferMinutes: 10,
            walkingMinutes: 15,
            minimumConnectionMinutes: 35,
            accessibilityImpactMinutes: 8,
            now: now
        ))
        XCTAssertEqual(assessment.risk, .atRisk)
        XCTAssertEqual(assessment.availableMinutes, 30)
    }

    func testAccessibleRouteUsesElevator() throws {
        let route = try TerminalRouter().route(in: SampleTerminalGraph.terminal2, from: "security-exit", to: "gate-c12", mode: .accessible, preferences: .default)
        XCTAssertTrue(route.edgeIDs.contains("e2-elevator"))
        XCTAssertFalse(route.edgeIDs.contains("e2-stairs"))
    }

    func testFastestRouteCanUseStairs() throws {
        var preferences = AccessibilityPreferences.default
        preferences.wheelchairRouting = false
        preferences.avoidStairs = false
        preferences.preferElevators = false
        let route = try TerminalRouter().route(in: SampleTerminalGraph.terminal2, from: "security-exit", to: "gate-c12", mode: .fastest, preferences: preferences)
        XCTAssertTrue(route.edgeIDs.contains("e2-stairs"))
        XCTAssertLessThan(route.durationSeconds, 400)
    }

    func testClosureAvoidanceAndGateChangeReroute() throws {
        var preferences = AccessibilityPreferences.default
        preferences.wheelchairRouting = false
        preferences.avoidStairs = false
        let router = TerminalRouter()
        let c8 = try router.route(in: SampleTerminalGraph.terminal2, from: "security-exit", to: "gate-c8", mode: .fastest, preferences: preferences)
        let c12 = try router.route(in: SampleTerminalGraph.terminal2, from: "security-exit", to: "gate-c12", mode: .fastest, preferences: preferences)
        XCTAssertNotEqual(c8.nodeIDs.last, c12.nodeIDs.last)
        XCTAssertFalse(c12.edgeIDs.contains("construction"))
    }

    func testAmenityLocatorReturnsAllEquallyNearCurrentLevelRestrooms() {
        let graph = TerminalGraph(
            version: "amenity-tie-test",
            nodes: [
                TerminalNode(id: "start", name: "Current point", point: MapPoint(x: 0.5, y: 0.5), level: 2, kind: .corridor),
                TerminalNode(id: "east", name: "East Restroom", point: MapPoint(x: 0.8, y: 0.5), level: 2, kind: .restroom),
                TerminalNode(id: "west", name: "West Restroom", point: MapPoint(x: 0.2, y: 0.5), level: 2, kind: .restroom)
            ],
            edges: [
                amenityEdge(id: "east-route", from: "start", to: "east", meters: 80),
                amenityEdge(id: "west-route", from: "start", to: "west", meters: 80)
            ]
        )

        let result = TerminalAmenityLocator().nearest(
            category: .restroom,
            in: graph,
            from: "start",
            preferences: .default
        )

        XCTAssertTrue(result.usesCurrentLevel)
        XCTAssertTrue(result.hasDistanceTie)
        XCTAssertEqual(Set(result.matches.map(\.node.id)), Set(["east", "west"]))
        XCTAssertEqual(result.matches.compactMap(\.routeDistanceMeters), [80, 80])
    }

    func testAmenityLocatorPrefersMappedCurrentLevelBeforeAnotherLevel() {
        let graph = TerminalGraph(
            version: "amenity-level-test",
            nodes: [
                TerminalNode(id: "start", name: "Current point", point: MapPoint(x: 0.5, y: 0.5), level: 2, kind: .corridor),
                TerminalNode(id: "same-level", name: "Concourse Restaurant", point: MapPoint(x: 0.8, y: 0.5), level: 2, kind: .restaurant),
                TerminalNode(id: "other-level", name: "Lower Restaurant", point: MapPoint(x: 0.5, y: 0.3), level: 1, kind: .restaurant)
            ],
            edges: [
                amenityEdge(id: "same-route", from: "start", to: "same-level", meters: 200),
                amenityEdge(id: "other-route", from: "start", to: "other-level", meters: 20)
            ]
        )

        let result = TerminalAmenityLocator().nearest(
            category: .meal,
            in: graph,
            from: "start",
            preferences: .default
        )

        XCTAssertTrue(result.usesCurrentLevel)
        XCTAssertEqual(result.matches.map(\.node.id), ["same-level"])
        XCTAssertEqual(result.matches.first?.routeDistanceMeters, 200)
    }

    func testItemAvailabilityNeverClaimsInventoryFromMapSearchAlone() {
        let result = ItemAvailabilityResolver().assess(
            mapSearchMatchedExactQuery: true,
            inventoryRecord: nil,
            now: now
        )
        XCTAssertEqual(result.state, .likelySoldHereStockNotConfirmed)
        XCTAssertNil(result.observedAt)
        XCTAssertNil(result.expiresAt)
    }

    func testItemAvailabilityRequiresCurrentMerchantRecordForConfirmedStock() {
        let current = MerchantInventoryRecord(
            isInStock: true,
            observedAt: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(300)
        )
        let expired = MerchantInventoryRecord(
            isInStock: true,
            observedAt: now.addingTimeInterval(-600),
            expiresAt: now.addingTimeInterval(-1)
        )

        XCTAssertEqual(
            ItemAvailabilityResolver().assess(mapSearchMatchedExactQuery: true, inventoryRecord: current, now: now).state,
            .confirmedInStock
        )
        XCTAssertEqual(
            ItemAvailabilityResolver().assess(mapSearchMatchedExactQuery: true, inventoryRecord: expired, now: now).state,
            .likelySoldHereStockNotConfirmed
        )
    }

    private func amenityEdge(id: String, from: String, to: String, meters: Double) -> TerminalEdge {
        TerminalEdge(
            id: id,
            from: from,
            to: to,
            distanceMeters: meters,
            walkingSeconds: meters,
            wheelchairAccessible: true,
            hasStairs: false,
            hasEscalator: false,
            hasElevator: false,
            narrowPassage: false,
            temporarilyClosed: false,
            crowdPenalty: 0,
            levelChange: 0,
            directionComplexity: 0
        )
    }

    func testElevatorOutageProducesNoAccessibleRoute() {
        let graph = TerminalGraph(
            version: "outage",
            nodes: SampleTerminalGraph.terminal2.nodes,
            edges: SampleTerminalGraph.terminal2.edges.map { edge in
                TerminalEdge(
                    id: edge.id,
                    from: edge.from,
                    to: edge.to,
                    distanceMeters: edge.distanceMeters,
                    walkingSeconds: edge.walkingSeconds,
                    wheelchairAccessible: edge.wheelchairAccessible,
                    hasStairs: edge.hasStairs,
                    hasEscalator: edge.hasEscalator,
                    hasElevator: edge.hasElevator,
                    narrowPassage: edge.narrowPassage,
                    temporarilyClosed: edge.temporarilyClosed || edge.hasElevator,
                    crowdPenalty: edge.crowdPenalty,
                    levelChange: edge.levelChange,
                    directionComplexity: edge.directionComplexity
                )
            }
        )
        XCTAssertThrowsError(try TerminalRouter().route(in: graph, from: "security-exit", to: "gate-c12", mode: .accessible, preferences: .default)) { error in
            XCTAssertEqual(error as? RouteError, .noAccessibleRoute)
        }
    }

    func testRandomizedAccessibleRoutesNeverUseStairsOrClosures() throws {
        let seed = ProcessInfo.processInfo.environment["AIRPORTXR_TEST_SEED"].flatMap(UInt64.init) ?? UInt64.random(in: 1...UInt64.max)
        var generator = SplitMix64(seed: seed)
        for iteration in 0..<100 {
            let edges = SampleTerminalGraph.terminal2.edges.map { edge in
                TerminalEdge(
                    id: edge.id,
                    from: edge.from,
                    to: edge.to,
                    distanceMeters: edge.distanceMeters,
                    walkingSeconds: edge.walkingSeconds,
                    wheelchairAccessible: edge.wheelchairAccessible,
                    hasStairs: edge.hasStairs,
                    hasEscalator: edge.hasEscalator,
                    hasElevator: edge.hasElevator,
                    narrowPassage: edge.narrowPassage,
                    temporarilyClosed: edge.temporarilyClosed,
                    crowdPenalty: Double.random(in: 0...1, using: &generator),
                    levelChange: edge.levelChange,
                    directionComplexity: Double.random(in: 0...1, using: &generator)
                )
            }
            let graph = TerminalGraph(version: "fuzz-\(iteration)", nodes: SampleTerminalGraph.terminal2.nodes, edges: edges)
            let route = try TerminalRouter().route(in: graph, from: "security-exit", to: "gate-c12", mode: .accessible, preferences: .default)
            let selected = edges.filter { route.edgeIDs.contains($0.id) }
            XCTAssertFalse(selected.contains(where: { $0.hasStairs || $0.temporarilyClosed || !$0.wheelchairAccessible }), "Randomized safety invariant failed; replay with AIRPORTXR_TEST_SEED=\(seed)")
        }
    }

    private func input(boardingInMinutes: Int, accessible: Bool, updatedAgo: TimeInterval, gateChanged: Bool = false) -> BoardingRiskInput {
        BoardingRiskInput(
            scheduledBoardingTime: now.addingTimeInterval(TimeInterval(boardingInMinutes * 60)),
            estimatedBoardingTime: nil,
            departureTime: now.addingTimeInterval(TimeInterval((boardingInMinutes + 30) * 60)),
            flightStatus: .scheduled,
            boardingGroup: "4",
            walkMinutes: 6,
            accessibleRouteMinutes: 9,
            useAccessibleRoute: accessible,
            securityMinutes: 0,
            immigrationMinutes: 0,
            locationConfidence: .high,
            gateChanged: gateChanged,
            terminalChanged: false,
            routeUncertaintyMinutes: 0,
            providerUpdatedAt: now.addingTimeInterval(-updatedAgo),
            freshness: updatedAgo > 15 * 60 ? .stale : .live,
            extraBufferMinutes: 5,
            now: now
        )
    }
}

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
