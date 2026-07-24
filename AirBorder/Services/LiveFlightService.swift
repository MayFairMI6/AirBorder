import Foundation

struct LiveFlightService: Sendable {
    let repository: any FlightRepositoryProtocol

    func refresh(_ flight: Flight) async throws -> FlightRepositoryResult {
        try await repository.refresh(flight: flight)
    }
}

