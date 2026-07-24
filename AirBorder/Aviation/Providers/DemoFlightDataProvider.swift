import Foundation

struct DemoFlightDataProvider: FlightDataProvider {
    let providerID = "bundled-demo"
    let providerName = "Example flight updates"
    var now: @Sendable () -> Date = { Date() }

    func searchFlights(query: FlightQuery) async throws -> [Flight] {
        let flight = DemoData.flight(now: now())
        if query.normalizedIdentifier == "AX204" || query.normalizedIdentifier.isEmpty {
            return [flight]
        }
        // The fallback result is intentionally labeled demo and is never represented as the requested live flight.
        return [flight]
    }

    func airportBoard(airportCode: String, date: Date, kind: AirportBoardKind) async throws -> [Flight] {
        [DemoData.flight(now: now())]
    }

    func flightStatus(id: String) async throws -> Flight {
        DemoData.flight(now: now())
    }
}
