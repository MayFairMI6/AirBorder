import Foundation

/// A licensed or user-owned historical outcome. The app deliberately does not
/// infer these records from WeatherKit, airline, or place-provider payloads.
struct WeatherStateDelayOutcome: Codable, Hashable, Sendable {
    let route: String
    let airlineCode: String?
    let localDepartureHour: Int
    let weatherState: WeatherStateKey
    let arrivalDelayMinutes: Double
    let observedAt: Date
    let sourceRecordID: String
}

struct WeatherStateKey: Codable, Hashable, Sendable {
    let windBand: Int
    let visibilityBand: Int
    let precipitationBand: Int

    init?(features: FlightDelayFeatureSnapshot) {
        guard let wind = features.features[.departureWindGust]?.value,
              let visibility = features.features[.departureVisibility]?.value,
              let precipitation = features.features[.departurePrecipitationRate]?.value else {
            return nil
        }
        // These are data buckets, not hidden penalties: each index is the
        // floor of the provider's physical measurement in its stated unit.
        windBand = Int(wind / 10)
        visibilityBand = Int(visibility / 2_000)
        precipitationBand = Int(precipitation.rounded(.down))
    }
}

enum WeatherStateTrendModelError: Error {
    case weatherStateUnavailable
    case insufficientComparableHistory
}

/// Empirical, explainable arrival-delay distribution. It uses only comparable
/// route/airline/hour/weather records and requires a caller-specified minimum
/// sample count; absent history therefore remains unavailable rather than
/// becoming a fabricated prediction.
struct WeatherStateDelayTrendModel: FlightDelayModel {
    let outcomes: [WeatherStateDelayOutcome]
    let minimumComparableOutcomes: Int
    let descriptor: FlightDelayModelDescriptor

    init(outcomes: [WeatherStateDelayOutcome], minimumComparableOutcomes: Int = 20) {
        self.outcomes = outcomes
        self.minimumComparableOutcomes = minimumComparableOutcomes
        descriptor = FlightDelayModelDescriptor(
            id: "weather-state-delay-trend",
            version: "1",
            featureSchemaVersion: "weather-state-news-v1",
            target: .arrivalDelayMinutes,
            algorithmFamily: .quantileRegression,
            requiredFeatures: [.departureWindGust, .departureVisibility, .departurePrecipitationRate],
            trainedAt: nil,
            calibratedThrough: outcomes.map(\.observedAt).max(),
            trainingPolicyVersion: "user-owned-or-licensed-history-only-v1"
        )
    }

    func predict(flight: Flight, features: FlightDelayFeatureSnapshot, at date: Date) async throws -> FlightDelayModelOutput {
        guard let weatherState = WeatherStateKey(features: features),
              let departure = flight.scheduledDeparture else {
            throw WeatherStateTrendModelError.weatherStateUnavailable
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: flight.origin.timeZone ?? "UTC") ?? .gmt
        let hour = calendar.component(.hour, from: departure)
        let comparable = outcomes.filter {
            $0.route == flight.routeLabel
                && $0.airlineCode == flight.airlineCode
                && $0.localDepartureHour == hour
                && $0.weatherState == weatherState
        }
        guard comparable.count >= minimumComparableOutcomes else {
            throw WeatherStateTrendModelError.insufficientComparableHistory
        }

        let delays = comparable.map(\.arrivalDelayMinutes).sorted()
        let p10 = quantile(0.10, values: delays)
        let p50 = quantile(0.50, values: delays)
        var p90 = quantile(0.90, values: delays)
        let newsFeature = features.features[.airportWeatherDisruptionReportProbability]
        if let newsFeature, newsFeature.isCurrent(at: date) {
            // News can widen the uncertain upper tail, but cannot move the
            // central historical estimate or replace operational sources.
            p90 += max(0, p90 - p50) * newsFeature.value
        }
        let distribution = FlightDelayDistribution(
            target: .arrivalDelayMinutes,
            quantiles: [
                DelayQuantile(probability: 0.10, minutes: p10),
                DelayQuantile(probability: 0.50, minutes: p50),
                DelayQuantile(probability: 0.90, minutes: p90)
            ],
            meanMinutes: delays.reduce(0, +) / Double(delays.count),
            exceedanceProbabilities: []
        )
        let used: Set<FlightDelayFeatureKind> = newsFeature?.isCurrent(at: date) == true
            ? [.departureWindGust, .departureVisibility, .departurePrecipitationRate, .airportWeatherDisruptionReportProbability]
            : [.departureWindGust, .departureVisibility, .departurePrecipitationRate]
        return FlightDelayModelOutput(
            flightID: flight.id,
            distribution: distribution,
            usedFeatures: used,
            generatedAt: date,
            expiresAt: features.features[.departureWindGust]?.expiresAt ?? date,
            derivation: [
                DerivationStep(label: "Comparable history", formula: "same route + airline + local hour + weather state", inputRecordIDs: comparable.map(\.sourceRecordID), result: "\(comparable.count) outcomes"),
                DerivationStep(label: "Weather news", formula: "current, airport-specific disruption evidence widens only p90", inputRecordIDs: newsFeature.map { [$0.sourceRecordID] } ?? [], result: newsFeature.map { String(format: "%.0f%%", $0.value * 100) } ?? "not used")
            ]
        )
    }

    private func quantile(_ probability: Double, values: [Double]) -> Double {
        let index = Int((Double(values.count - 1) * probability).rounded())
        return values[index]
    }
}
