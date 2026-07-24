import Foundation

protocol PredictionLearning: Sendable {
    func learn(from flights: [Flight], authorization: ProviderTrainingAuthorization?) async
}

extension PredictionLearning {
    /// Calls without an explicit, provenance-bound authorization are denied.
    func learn(from flights: [Flight]) async {
        await learn(from: flights, authorization: nil)
    }
}

protocol JourneyPredicting: PredictionLearning {
    func predictDelay(for flight: Flight) async -> JourneyPrediction
    func predictDelay(for flight: Flight, weatherContext: String) async -> JourneyPrediction
    func learnWalkingTime(actualMinutes: Int, routeMode: RouteMode, terminalVersion: String) async
    func predictWalkingTime(baselineMinutes: Int, routeMode: RouteMode, terminalVersion: String) async -> DurationPrediction
    func learnTransitTime(actualMinutes: Int, option: TransitOption) async
    func learnUserReportedDelay(actualMinutes: Int, flight: Flight) async
    func learnUserReportedDelay(actualMinutes: Int, flight: Flight, weatherContext: String) async
    func recordRecommendationFeedback(context: String, accepted: Bool) async
    func predictRecommendationPreference(context: String) async -> PreferencePrediction
    func setLearningEnabled(_ enabled: Bool) async
    func eraseLearnedModel() async
}

private struct RunningStatistic: Codable, Sendable {
    var count = 0
    var mean = 0.0
    var squaredDifference = 0.0
    var lastUpdated: Date?

    mutating func add(_ value: Double, at date: Date) {
        count += 1
        let delta = value - mean
        mean += delta / Double(count)
        squaredDifference += delta * (value - mean)
        lastUpdated = date
    }

    var sampleStandardDeviation: Double? {
        guard count > 1 else { return nil }
        return sqrt(squaredDifference / Double(count - 1))
    }
}

private struct LearnedModelState: Codable, Sendable {
    var delayContexts: [String: RunningStatistic] = [:]
    var weatherDelayContexts: [String: RunningStatistic] = [:]
    var walkingContexts: [String: RunningStatistic] = [:]
    var transitContexts: [String: RunningStatistic] = [:]
    var recommendationContexts: [String: RunningStatistic] = [:]
    var seenFlightObservations: Set<String> = []
    var modelVersion = PersonalizationPolicy.current.modelVersion
}

struct PersonalizationPolicy: Codable, Hashable, Sendable {
    static let current = PersonalizationPolicy(
        version: "on-device-personalization-2026-07-14-v2",
        modelVersion: 2,
        mediumConfidenceSamples: 5,
        highConfidenceSamples: 20,
        mediumMaximumAgeDays: 180,
        highMaximumAgeDays: 90
    )

    let version: String
    let modelVersion: Int
    let mediumConfidenceSamples: Int
    let highConfidenceSamples: Int
    let mediumMaximumAgeDays: Int
    let highMaximumAgeDays: Int
}

actor OnDevicePredictionService: JourneyPredicting {
    private let fileURL: URL
    private var state: LearnedModelState
    private var learningEnabled: Bool
    private let now: @Sendable () -> Date

    init(directory: URL? = nil, learningEnabled: Bool = true, now: @escaping @Sendable () -> Date = { Date() }) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AirportXRCompanion", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("on-device-prediction-v2.json")
        state = Self.read(from: fileURL)
        self.learningEnabled = learningEnabled
        self.now = now
    }

    func learn(from flights: [Flight], authorization: ProviderTrainingAuthorization?) async {
        guard learningEnabled,
              let authorization,
              authorization.purpose == .flightDelayOutcome,
              !authorization.adapterProviderID.isEmpty else {
            return
        }

        var didLearn = false
        let learnedAt = now()
        for flight in flights {
            guard flight.source.isLive,
                  !flight.source.isDemo,
                  flight.source.providerPolicyID == authorization.policyID,
                  flight.source.providerPolicyVersion == authorization.policyVersion,
                  flight.source.providerTrainingAllowed == true,
                  flight.source.providerTrainingPurposes.contains(.flightDelayOutcome),
                  let recordID = flight.source.providerRecordID,
                  !recordID.isEmpty,
                  let scheduledDeparture = flight.scheduledDeparture,
                  let actualDeparture = flight.actualDeparture else {
                continue
            }

            // Persist only a deterministic, one-way observation identifier and
            // the aggregate residual. No commercial provider payload is stored.
            let observationUUID = StableEntityID.uuid([
                "licensed-provider-flight-delay",
                authorization.policyVersion,
                authorization.policyID,
                recordID,
                String(Int(scheduledDeparture.timeIntervalSince1970))
            ].joined(separator: "|"))
            let observationID = "provider-delay|\(observationUUID.uuidString.lowercased())"
            guard !state.seenFlightObservations.contains(observationID) else { continue }

            let delayMinutes = actualDeparture.timeIntervalSince(scheduledDeparture) / 60
            guard delayMinutes.isFinite else { continue }
            state.delayContexts[delayContext(for: flight), default: RunningStatistic()].add(delayMinutes, at: learnedAt)
            state.delayContexts[routeContext(for: flight), default: RunningStatistic()].add(delayMinutes, at: learnedAt)
            state.seenFlightObservations.insert(observationID)
            didLearn = true
        }

        if didLearn { try? persist() }
    }

    func predictDelay(for flight: Flight) async -> JourneyPrediction {
        let exact = state.delayContexts[delayContext(for: flight)]
        let route = state.delayContexts[routeContext(for: flight)]
        guard let statistic = exact ?? route, statistic.count > 0 else {
            return JourneyPrediction(
                expectedDelayMinutes: nil,
                confidence: .low,
                sampleCount: 0,
                lastLearnedAt: nil,
                source: .unavailable,
                recommendation: "There is not enough past flight history for this route yet."
            )
        }
        let minutes = max(0, Int(statistic.mean.rounded()))
        let confidence = confidence(for: statistic)
        let recommendation: String
        if minutes >= 30 {
            recommendation = "Past flights on this route often run later. Keep your connection and airport plans flexible."
        } else if minutes >= 15 {
            recommendation = "Allow a little extra flexibility and follow the latest airline update."
        } else {
            recommendation = "Past flights on this route show only a small delay pattern. Check the latest airline update."
        }
        return JourneyPrediction(expectedDelayMinutes: minutes, confidence: confidence, sampleCount: statistic.count, lastLearnedAt: statistic.lastUpdated, source: .onDeviceLearning, recommendation: recommendation)
    }

    func predictDelay(for flight: Flight, weatherContext: String) async -> JourneyPrediction {
        let key = weatherDelayContext(for: flight, weatherContext: weatherContext)
        guard let statistic = state.weatherDelayContexts[key], statistic.count > 0 else {
            return JourneyPrediction(
                expectedDelayMinutes: nil,
                confidence: .low,
                sampleCount: 0,
                lastLearnedAt: nil,
                source: .unavailable,
                recommendation: "There is not enough past flight history in similar weather yet."
            )
        }
        return JourneyPrediction(
            expectedDelayMinutes: max(0, Int(statistic.mean.rounded())),
            confidence: confidence(for: statistic),
            sampleCount: statistic.count,
            lastLearnedAt: statistic.lastUpdated,
            source: .onDeviceLearning,
            recommendation: "This estimate uses past flights on the same route, departure period, and weather pattern."
        )
    }

    func learnUserReportedDelay(actualMinutes: Int, flight: Flight) async {
        guard learningEnabled else { return }
        let observationID = "user-delay|\(flight.id)|\(actualMinutes)|\(Int(now().timeIntervalSince1970))"
        guard !state.seenFlightObservations.contains(observationID) else { return }
        let value = Double(actualMinutes)
        state.delayContexts[delayContext(for: flight), default: RunningStatistic()].add(value, at: now())
        state.delayContexts[routeContext(for: flight), default: RunningStatistic()].add(value, at: now())
        state.seenFlightObservations.insert(observationID)
        try? persist()
    }

    func learnUserReportedDelay(actualMinutes: Int, flight: Flight, weatherContext: String) async {
        guard learningEnabled else { return }
        let normalized = weatherContext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        let observationID = "user-weather-delay|\(flight.id)|\(actualMinutes)|\(Int(now().timeIntervalSince1970))"
        guard !state.seenFlightObservations.contains(observationID) else { return }
        state.weatherDelayContexts[weatherDelayContext(for: flight, weatherContext: normalized), default: RunningStatistic()]
            .add(Double(actualMinutes), at: now())
        state.seenFlightObservations.insert(observationID)
        try? persist()
    }

    func recordRecommendationFeedback(context: String, accepted: Bool) async {
        guard learningEnabled else { return }
        let key = "recommendation|\(context.lowercased())"
        state.recommendationContexts[key, default: RunningStatistic()].add(accepted ? 1 : 0, at: now())
        try? persist()
    }

    func predictRecommendationPreference(context: String) async -> PreferencePrediction {
        let key = "recommendation|\(context.lowercased())"
        guard let statistic = state.recommendationContexts[key], statistic.count > 0 else {
            return PreferencePrediction(acceptanceProbability: nil, confidence: .low, sampleCount: 0)
        }
        return PreferencePrediction(
            acceptanceProbability: min(1, max(0, statistic.mean)),
            confidence: confidence(for: statistic),
            sampleCount: statistic.count
        )
    }

    func learnWalkingTime(actualMinutes: Int, routeMode: RouteMode, terminalVersion: String) async {
        guard learningEnabled, (1...180).contains(actualMinutes) else { return }
        let key = "walk|\(terminalVersion)|\(routeMode.rawValue)"
        state.walkingContexts[key, default: RunningStatistic()].add(Double(actualMinutes), at: now())
        try? persist()
    }

    func predictWalkingTime(baselineMinutes: Int, routeMode: RouteMode, terminalVersion: String) async -> DurationPrediction {
        let key = "walk|\(terminalVersion)|\(routeMode.rawValue)"
        guard let statistic = state.walkingContexts[key], statistic.count > 0 else {
            return DurationPrediction(expectedMinutes: baselineMinutes, confidence: .low, sampleCount: 0, standardDeviationMinutes: nil)
        }
        return DurationPrediction(expectedMinutes: max(1, Int(statistic.mean.rounded())), confidence: confidence(for: statistic), sampleCount: statistic.count, standardDeviationMinutes: statistic.sampleStandardDeviation)
    }

    func learnTransitTime(actualMinutes: Int, option: TransitOption) async {
        guard learningEnabled, (1...600).contains(actualMinutes) else { return }
        let key = "transit|\(option.mode.rawValue)|\(option.destination.lowercased())"
        state.transitContexts[key, default: RunningStatistic()].add(Double(actualMinutes), at: now())
        try? persist()
    }

    func setLearningEnabled(_ enabled: Bool) async { learningEnabled = enabled }

    func eraseLearnedModel() async {
        state = LearnedModelState()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func confidence(for statistic: RunningStatistic) -> PredictionConfidence {
        let age = statistic.lastUpdated.map { now().timeIntervalSince($0) } ?? .infinity
        let policy = PersonalizationPolicy.current
        let day: TimeInterval = 24 * 60 * 60
        if statistic.count >= policy.highConfidenceSamples && age < Double(policy.highMaximumAgeDays) * day { return .high }
        if statistic.count >= policy.mediumConfidenceSamples && age < Double(policy.mediumMaximumAgeDays) * day { return .medium }
        return .low
    }

    private func delayContext(for flight: Flight) -> String {
        let date = flight.scheduledDeparture ?? now()
        var calendar = Calendar(identifier: .gregorian)
        if let identifier = flight.origin.timeZone, let timeZone = TimeZone(identifier: identifier) {
            calendar.timeZone = timeZone
        }
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        return "\(routeContext(for: flight))|weekday:\(weekday)|hour:\(hour)"
    }

    private func routeContext(for flight: Flight) -> String {
        "delay|\(flight.airlineCode ?? "unknown")|\(flight.origin.iata)-\(flight.destination.iata)"
    }

    private func weatherDelayContext(for flight: Flight, weatherContext: String) -> String {
        "\(delayContext(for: flight))|weather:\(weatherContext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = fileURL
        try? mutableURL.setResourceValues(values)
    }

    private static func read(from url: URL) -> LearnedModelState {
        guard let data = try? Data(contentsOf: url) else { return LearnedModelState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(LearnedModelState.self, from: data)) ?? LearnedModelState()
    }
}
