import Foundation

protocol FlightRepositoryProtocol: Sendable {
    func search(query: FlightQuery) async throws -> FlightRepositoryResult
    func board(airportCode: String, date: Date, kind: AirportBoardKind) async throws -> FlightRepositoryResult
    func refresh(flight: Flight) async throws -> FlightRepositoryResult
}

final class FlightRepository: FlightRepositoryProtocol, @unchecked Sendable {
    private let providers: [any FlightDataProvider]
    private let cache: any FlightCaching
    private let now: @Sendable () -> Date
    private let staleAfter: TimeInterval
    private let predictionLearning: (any PredictionLearning)?
    private let providerPolicyResolver: any ProviderPolicyResolving

    init(
        providers: [any FlightDataProvider],
        cache: any FlightCaching,
        predictionLearning: (any PredictionLearning)? = nil,
        providerPolicyResolver: any ProviderPolicyResolving = ProviderPolicyCatalog.current,
        staleAfter: TimeInterval = 15 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.providers = providers
        self.cache = cache
        self.staleAfter = staleAfter
        self.now = now
        self.predictionLearning = predictionLearning
        self.providerPolicyResolver = providerPolicyResolver
    }

    func search(query: FlightQuery) async throws -> FlightRepositoryResult {
        try await load(key: query.cacheKey) { provider in
            try await provider.searchFlights(query: query)
        }
    }

    func board(airportCode: String, date: Date, kind: AirportBoardKind) async throws -> FlightRepositoryResult {
        let key = "board:\(airportCode.uppercased()):\(kind.rawValue):\(Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
        return try await load(key: key) { provider in
            try await provider.airportBoard(airportCode: airportCode, date: date, kind: kind)
        }
    }

    func refresh(flight: Flight) async throws -> FlightRepositoryResult {
        let key = "status:\(flight.id)"
        return try await load(key: key) { provider in
            var updated = try await provider.flightStatus(id: flight.id)
            if let oldGate = flight.gate, let newGate = updated.gate, oldGate != newGate {
                updated.previousGate = oldGate
            } else if updated.previousGate == nil {
                updated.previousGate = flight.previousGate
            }
            return [updated]
        }
    }

    private func load(
        key: String,
        operation: @escaping @Sendable (any FlightDataProvider) async throws -> [Flight]
    ) async throws -> FlightRepositoryResult {
        var lastError: Error = FlightAPIError.unavailable

        for provider in providers {
            do {
                let flights = try await operation(provider)
                guard !flights.isEmpty else { throw FlightAPIError.notFound }
                let fetchedAt = now()
                try? await cache.save(flights: flights, for: key, at: fetchedAt)
                await learnFromLicensedProviderData(flights, adapterProviderID: provider.providerID)
                let isDemo = flights.allSatisfy(\.source.isDemo)
                return FlightRepositoryResult(
                    flights: flights,
                    freshness: isDemo ? .demo : .live,
                    fetchedAt: fetchedAt,
                    warning: isDemo ? "Showing example flight details. Connect travel updates for current results." : nil
                )
            } catch let error as FlightAPIError {
                lastError = error
                if case .rateLimited = error { break }
                if case .authenticationFailed = error { break }
            } catch {
                lastError = error
            }
        }

        if let cached = await cache.flights(for: key) {
            let age = now().timeIntervalSince(cached.storedAt)
            return FlightRepositoryResult(
                flights: cached.flights,
                freshness: age > staleAfter ? .stale : .cached,
                fetchedAt: cached.storedAt,
                warning: age > staleAfter ? "Saved flight information may be out of date. Verify airport displays." : "Offline: showing the last successful update."
            )
        }
        throw lastError
    }

    private func learnFromLicensedProviderData(_ flights: [Flight], adapterProviderID: String) async {
        guard let predictionLearning else { return }
        var authorizedBatches: [ProviderTrainingAuthorization: [Flight]] = [:]
        for flight in flights {
            guard let authorization = providerPolicyResolver.trainingAuthorization(
                adapterProviderID: adapterProviderID,
                source: flight.source,
                purpose: .flightDelayOutcome
            ) else {
                continue
            }
            authorizedBatches[authorization, default: []].append(flight)
        }

        for (authorization, batch) in authorizedBatches {
            await predictionLearning.learn(from: batch, authorization: authorization)
        }
    }
}
