import Foundation

/// Fixed, clearly labelled weather for simulator review. It is reachable only
/// through an explicit `--uitesting` launch argument and never in a live trip.
struct QAFixtureWeatherContextProvider: WeatherContextProvider {
    enum Scenario: String {
        case clear
        case rain
        case fog
        case disruption

        var summary: String {
            switch self {
            case .clear: "Clear, 22°C · wind 6 kt"
            case .rain: "Rain, 16°C · wind 14 kt"
            case .fog: "Fog, 12°C · wind 4 kt"
            case .disruption: "Thunderstorm, 18°C · wind 28 kt"
            }
        }
    }

    let scenario: Scenario

    func weatherSummary(airport: Airport, latitude: Double, longitude: Double, at date: Date) async throws -> SourcedMetric<String>? {
        let receivedAt = Date()
        return SourcedMetric(
            value: scenario.summary,
            unit: .text,
            provider: "Practice weather fixture",
            providerField: "qa.weatherScenario",
            sourceRecordID: "qa-weather-\(scenario.rawValue)-\(airport.iata)",
            observedAt: receivedAt,
            receivedAt: receivedAt,
            expiresAt: receivedAt.addingTimeInterval(60 * 60),
            uncertainty: "Practice-only fixed weather state; not a current airport observation.",
            derivation: [DerivationStep(label: "Practice weather", formula: "fixed \(scenario.rawValue) scenario", inputRecordIDs: ["qa-weather"], result: scenario.summary)]
        )
    }
}
