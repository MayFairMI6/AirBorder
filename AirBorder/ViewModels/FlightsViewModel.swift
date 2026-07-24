import Foundation

@MainActor
final class FlightsViewModel: ObservableObject {
    @Published var airlineCode: String
    @Published var flightNumber: String
    @Published var travelDate = Date()
    @Published var airportCode: String
    @Published var boardKind: AirportBoardKind = .departures
    @Published private(set) var results: [Flight] = []
    @Published private(set) var freshness: DataFreshness = .unavailable
    @Published private(set) var warning: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: FlightSearchService

    init(service: FlightSearchService, seedDemoFields: Bool = false) {
        self.service = service
        airlineCode = seedDemoFields ? "AX" : ""
        flightNumber = seedDemoFields ? "204" : ""
        airportCode = seedDemoFields ? "SFO" : ""
    }

    func search() async {
        await load {
            try await self.service.search(airlineCode: self.airlineCode, flightNumber: self.flightNumber, date: self.travelDate)
        }
    }

    func loadBoard() async {
        await load {
            try await self.service.board(airportCode: self.airportCode, date: self.travelDate, kind: self.boardKind)
        }
    }

    private func load(operation: () async throws -> FlightRepositoryResult) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await operation()
            results = result.flights
            freshness = result.freshness
            warning = result.warning
        } catch {
            results = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Flight information is unavailable."
        }
    }
}
