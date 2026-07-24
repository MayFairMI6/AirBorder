import Foundation

struct TransitRepository: Sendable {
    let providers: [any TransitDataProvider]

    func options(from airportCode: String, to destination: String, at date: Date) async throws -> [TransitOption] {
        var lastError: Error?
        for provider in providers {
            do {
                let results = try await provider.options(from: airportCode, to: destination, at: date)
                if !results.isEmpty { return results }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return []
    }
}

