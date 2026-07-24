import Foundation

enum PredictionConfidence: String, Codable, Sendable {
    case low
    case medium
    case high
}

enum PredictionSource: String, Codable, Sendable {
    case onDeviceLearning
    case unavailable
}

struct JourneyPrediction: Codable, Sendable {
    let expectedDelayMinutes: Int?
    let confidence: PredictionConfidence
    let sampleCount: Int
    let lastLearnedAt: Date?
    let source: PredictionSource
    let recommendation: String
}

struct DurationPrediction: Codable, Sendable {
    let expectedMinutes: Int
    let confidence: PredictionConfidence
    let sampleCount: Int
    let standardDeviationMinutes: Double?

    init(expectedMinutes: Int, confidence: PredictionConfidence, sampleCount: Int, standardDeviationMinutes: Double? = nil) {
        self.expectedMinutes = expectedMinutes
        self.confidence = confidence
        self.sampleCount = sampleCount
        self.standardDeviationMinutes = standardDeviationMinutes
    }
}

struct PreferencePrediction: Codable, Sendable {
    let acceptanceProbability: Double?
    let confidence: PredictionConfidence
    let sampleCount: Int
}
