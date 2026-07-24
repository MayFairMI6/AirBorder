import CoreLocation
import Foundation
import WeatherKit

struct WeatherKitContextProvider: WeatherContextProvider {
    func weatherSummary(airport: Airport, latitude: Double, longitude: Double, at date: Date) async throws -> SourcedMetric<String>? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let weather = try await WeatherService.shared.weather(for: location, including: .current)
        let receivedAt = Date()
        let temperature = weather.temperature.converted(to: .celsius).value
        let summary = "\(weather.condition.description), \(Int(temperature.rounded()))°C"

        return SourcedMetric(
            value: summary,
            unit: .text,
            provider: "Apple WeatherKit",
            providerField: "currentWeather.condition, currentWeather.temperature",
            sourceRecordID: "weatherkit-current-\(latitude),\(longitude)",
            observedAt: receivedAt,
            receivedAt: receivedAt,
            expiresAt: receivedAt.addingTimeInterval(30 * 60),
            uncertainty: "Current local weather near the airport; it is not an aviation operational forecast.",
            derivation: [
                DerivationStep(
                    label: "Current airport weather",
                    formula: "WeatherKit current condition + temperature",
                    inputRecordIDs: ["weatherkit-current"],
                    result: summary
                )
            ]
        )
    }
}

struct UnavailableWeatherContextProvider: WeatherContextProvider {
    func weatherSummary(airport: Airport, latitude: Double, longitude: Double, at date: Date) async throws -> SourcedMetric<String>? { nil }
}
