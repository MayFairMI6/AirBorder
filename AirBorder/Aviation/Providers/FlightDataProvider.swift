import Foundation

protocol FlightDataProvider: Sendable {
    var providerID: String { get }
    var providerName: String { get }

    func searchFlights(query: FlightQuery) async throws -> [Flight]
    func airportBoard(airportCode: String, date: Date, kind: AirportBoardKind) async throws -> [Flight]
    func flightStatus(id: String) async throws -> Flight
}

