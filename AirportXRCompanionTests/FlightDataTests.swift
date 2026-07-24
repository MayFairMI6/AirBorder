import Foundation
import XCTest
@testable import AirBorder

final class FlightDataTests: XCTestCase {
    func testFlightResponseMappingHandlesPartialProviderFields() throws {
        let json = """
        {
          "id":"fa-1","flightNumber":"AX204","airlineCode":"AX",
          "origin":{"iata":"SFO","name":"San Francisco"},
          "destination":{"iata":"JFK","name":"John F Kennedy"},
          "status":"enRoute","scheduledDeparture":"2026-07-14T10:00:00Z",
          "estimatedDeparture":"2026-07-14T10:18:00Z","gate":"C12",
          "delayMinutes":18,"providerRecordID":"fa-1"
        }
        """
        let dto = try JSONDecoder().decode(ProxyFlightDTO.self, from: Data(json.utf8))
        let flight = try FlightDataMapper().map(
            dto,
            source: ProxySourceDTO(
                name: "FlightAware",
                isLive: true,
                receivedAt: "2026-07-14T09:00:00Z",
                providerPolicy: "flightaware",
                providerPolicyVersion: ProviderPolicyRegistry.version,
                trainingAllowed: false,
                trainingPurposes: []
            ),
            defaultProviderName: "Fallback"
        )
        XCTAssertEqual(flight.status, .enRoute)
        XCTAssertEqual(flight.gate, "C12")
        XCTAssertEqual(flight.delayMinutes, 18)
        XCTAssertNil(flight.baggageClaim)
        XCTAssertEqual(flight.source.name, "FlightAware")
        XCTAssertEqual(flight.source.providerPolicyID, "flightaware")
        XCTAssertEqual(flight.source.providerPolicyVersion, ProviderPolicyRegistry.version)
        XCTAssertEqual(flight.source.providerTrainingAllowed, false)
    }

    func testProviderFallbackUsesSecondProvider() async throws {
        let cache = InMemoryFlightCache()
        let repository = FlightRepository(
            providers: [
                StubFlightProvider(id: "failed", behavior: .failure(.unavailable)),
                StubFlightProvider(id: "demo", behavior: .flights([makeFlight(live: false)]))
            ],
            cache: cache
        )
        let result = try await repository.search(query: FlightQuery(airlineCode: "AX", flightNumber: "204", date: Date()))
        XCTAssertEqual(result.freshness, .demo)
        XCTAssertEqual(result.flights.first?.flightNumber, "AX 204")
    }

    func testRateLimitStopsProviderFallback() async {
        let repository = FlightRepository(
            providers: [
                StubFlightProvider(behavior: .failure(.rateLimited(retryAfter: 120))),
                StubFlightProvider(id: "should-not-run", behavior: .flights([makeFlight(live: false)]))
            ],
            cache: InMemoryFlightCache()
        )
        do {
            _ = try await repository.search(query: FlightQuery(airlineCode: "AX", flightNumber: "204", date: Date()))
            XCTFail("Expected rate-limit error")
        } catch let error as FlightAPIError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 120))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOfflineUsesCachedDataAndMarksStale() async throws {
        let cache = InMemoryFlightCache()
        let base = Date(timeIntervalSince1970: 1_721_000_000)
        let query = FlightQuery(airlineCode: "AX", flightNumber: "204", date: base)
        let online = FlightRepository(providers: [StubFlightProvider(behavior: .flights([makeFlight(now: base)]))], cache: cache, now: { base })
        _ = try await online.search(query: query)

        let offline = FlightRepository(providers: [StubFlightProvider(behavior: .failure(.offline))], cache: cache, staleAfter: 60, now: { base.addingTimeInterval(120) })
        let result = try await offline.search(query: query)
        XCTAssertEqual(result.freshness, .stale)
        XCTAssertTrue(result.warning?.contains("out of date") == true)
    }

    func testFlightCachePersistsAndClears() async throws {
        let directory = try temporaryDirectory()
        let cache = FlightCache(directory: directory)
        let flight = makeFlight()
        try await cache.save(flights: [flight], for: "key", at: Date())
        let cachedFlights = await cache.flights(for: "key")
        XCTAssertEqual(cachedFlights?.flights.first?.id, flight.id)
        try await cache.save(activeJourney: .demo())
        let savedJourney = await cache.activeJourney()
        XCTAssertNotNil(savedJourney)
        try await cache.clear()
        let removedFlights = await cache.flights(for: "key")
        let removedJourney = await cache.activeJourney()
        XCTAssertNil(removedFlights)
        XCTAssertNil(removedJourney)
    }

    func testRefreshCadenceAndStalenessBoundaries() {
        let now = Date(timeIntervalSince1970: 1_721_000_000)
        var flight = makeFlight(now: now)
        flight.estimatedDeparture = now.addingTimeInterval(25 * 3600)
        let service = FlightStatusRefreshService()
        XCTAssertEqual(service.recommendedInterval(for: flight, now: now), 6 * 3600)
        flight.estimatedDeparture = now.addingTimeInterval(2 * 3600)
        XCTAssertEqual(service.recommendedInterval(for: flight, now: now), 5 * 60)
        flight.status = .boarding
        XCTAssertEqual(service.recommendedInterval(for: flight, now: now), 60)
        XCTAssertEqual(service.recommendedInterval(for: flight, now: now, consecutiveFailures: 2), 240)
        XCTAssertTrue(service.isStale(lastUpdated: now.addingTimeInterval(-121), flight: flight, now: now))
    }
}
