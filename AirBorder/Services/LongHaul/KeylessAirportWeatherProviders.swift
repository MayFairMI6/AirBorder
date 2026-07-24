import Foundation

struct OpenMeteoWeatherContextProvider: WeatherContextProvider {
    func weatherSummary(airport: Airport, latitude: Double, longitude: Double, at date: Date) async throws -> SourcedMetric<String>? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,precipitation,weather_code,wind_speed_10m,wind_gusts_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "timeformat", value: "unixtime")
        ]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let receivedAt = Date()
        let summary = "\(weatherDescription(for: payload.current.weatherCode)), \(Int(payload.current.temperature.rounded()))°C · wind \(Int(payload.current.windSpeed.rounded())) kt"
        return SourcedMetric(
            value: summary,
            unit: .text,
            provider: "Open-Meteo",
            providerField: "current.temperature_2m, weather_code, wind_speed_10m, wind_gusts_10m, precipitation",
            sourceRecordID: "open-meteo-\(airport.iata)-\(Int(payload.current.time))",
            observedAt: payload.current.observedDate,
            receivedAt: receivedAt,
            expiresAt: receivedAt.addingTimeInterval(30 * 60),
            uncertainty: "Modelled current conditions near the airport; not an aviation operational observation.",
            derivation: [DerivationStep(label: "Current airport weather", formula: "Open-Meteo current fields", inputRecordIDs: ["open-meteo-current"], result: summary)]
        )
    }

    private func weatherDescription(for code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1...3: "Cloudy"
        case 45, 48: "Fog"
        case 51...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95, 96, 99: "Thunderstorm"
        default: "Current conditions"
        }
    }
}

struct AviationWeatherMETARContextProvider: WeatherContextProvider {
    func weatherSummary(airport: Airport, latitude: Double, longitude: Double, at date: Date) async throws -> SourcedMetric<String>? {
        guard let icao = airport.icao, !icao.isEmpty else { return nil }
        var components = URLComponents(string: "https://aviationweather.gov/api/data/metar")!
        components.queryItems = [URLQueryItem(name: "ids", value: icao), URLQueryItem(name: "format", value: "json")]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("AirportXRCompanion/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let record = records.first else { return nil }
        let receivedAt = Date()
        let raw = record["rawOb"] as? String
        let summary = AviationWeatherPresentation.summary(from: record)
        return SourcedMetric(
            value: summary,
            unit: .text,
            provider: "AviationWeather.gov",
            providerField: "metar.rawOb",
            sourceRecordID: "aviationweather-metar-\(icao)-\(receivedAt.ISO8601Format())",
            observedAt: (record["obsTime"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? receivedAt,
            receivedAt: receivedAt,
            expiresAt: receivedAt.addingTimeInterval(30 * 60),
            uncertainty: "Current airport observation; availability varies by station.",
            derivation: [DerivationStep(label: "Airport observation", formula: "latest METAR for airport ICAO", inputRecordIDs: [icao], result: raw ?? summary)]
        )
    }
}

/// Converts aviation-weather fields into language that a passenger can scan.
/// The raw METAR remains provenance only; it is never placed in the visible value.
private enum AviationWeatherPresentation {
    static func summary(from record: [String: Any]) -> String {
        var parts: [String] = []

        if let category = humanFlightCategory(record["fltCat"]) {
            parts.append(category)
        } else if let cover = humanCloudCover(record["cover"]) {
            parts.append(cover)
        }

        if let temperature = number(record["temp"]) {
            parts.append("\(Int(temperature.rounded()))°C")
        }

        if let speed = number(record["wspd"]) {
            var wind = "wind \(Int(speed.rounded())) kt"
            if let gust = number(record["wgst"]), gust > speed {
                wind += ", gusts \(Int(gust.rounded())) kt"
            }
            parts.append(wind)
        }

        if let visibility = visibilityText(record["visib"]) {
            parts.append("visibility \(visibility)")
        }

        return parts.isEmpty ? "Current airport conditions" : parts.joined(separator: " · ")
    }

    private static func humanFlightCategory(_ value: Any?) -> String? {
        guard let category = string(value)?.uppercased() else { return nil }
        switch category {
        case "VFR": return "Clear flight conditions"
        case "MVFR": return "Some visibility restrictions"
        case "IFR": return "Reduced visibility"
        case "LIFR": return "Very limited visibility"
        default: return nil
        }
    }

    private static func humanCloudCover(_ value: Any?) -> String? {
        guard let cover = string(value)?.uppercased() else { return nil }
        switch cover {
        case "SKC", "CLR": return "Clear skies"
        case "FEW": return "A few clouds"
        case "SCT": return "Partly cloudy"
        case "BKN": return "Mostly cloudy"
        case "OVC": return "Overcast"
        default: return nil
        }
    }

    private static func visibilityText(_ value: Any?) -> String? {
        guard let raw = string(value), !raw.isEmpty else { return nil }
        if raw.hasSuffix("+") { return "\(raw) mi" }
        guard let miles = Double(raw) else { return nil }
        if miles >= 10 { return "10+ mi" }
        if miles.rounded() == miles { return "\(Int(miles)) mi" }
        return String(format: "%.1f mi", miles)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let value = string(value) else { return nil }
        return Double(value)
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
}

struct CompositeWeatherContextProvider: WeatherContextProvider {
    let general: any WeatherContextProvider
    let aviation: any WeatherContextProvider

    func weatherSummary(airport: Airport, latitude: Double, longitude: Double, at date: Date) async throws -> SourcedMetric<String>? {
        async let generalResult = try? general.weatherSummary(airport: airport, latitude: latitude, longitude: longitude, at: date)
        async let aviationResult = try? aviation.weatherSummary(airport: airport, latitude: latitude, longitude: longitude, at: date)
        let (generalMetric, aviationMetric) = await (generalResult, aviationResult)
        // A station observation is the clearest passenger-facing airport truth.
        // Modelled nearby conditions remain a fallback when no METAR is available.
        return aviationMetric ?? generalMetric
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let time: TimeInterval
        let temperature: Double
        let weatherCode: Int
        let windSpeed: Double

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }

        var observedDate: Date { Date(timeIntervalSince1970: time) }
    }

    let current: Current
}
