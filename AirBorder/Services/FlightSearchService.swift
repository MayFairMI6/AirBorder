import Foundation

struct FlightSearchService: Sendable {
    let repository: any FlightRepositoryProtocol

    func search(airlineCode: String, flightNumber: String, date: Date) async throws -> FlightRepositoryResult {
        let airline = airlineCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...4).contains(airline.count), !number.isEmpty else { throw FlightAPIError.invalidRequest }
        return try await repository.search(query: FlightQuery(airlineCode: airline, flightNumber: number, date: date))
    }

    func board(airportCode: String, date: Date, kind: AirportBoardKind) async throws -> FlightRepositoryResult {
        try await repository.board(airportCode: airportCode, date: date, kind: kind)
    }
}

