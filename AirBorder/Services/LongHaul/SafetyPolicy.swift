import Foundation
import CryptoKit

/// Versioned deterministic safety figures. These values are intentionally kept
/// together so they can be reviewed, tested, and reproduced.
struct SafetyPolicy: Codable, Hashable, Sendable {
    static let current = SafetyPolicy(
        version: "layover-safety-2026-07-14-v1",
        confidenceLevel: 0.95,
        normalCriticalValue: 1.959963984540054,
        safeLowerProbability: 0.90,
        notRecommendedUpperProbability: 0.70,
        targetProbabilityHalfWidth: 0.01,
        simulationTrials: 10_000
    )

    let version: String
    let confidenceLevel: Double
    let normalCriticalValue: Double
    let safeLowerProbability: Double
    let notRecommendedUpperProbability: Double
    let targetProbabilityHalfWidth: Double
    let simulationTrials: Int

    /// Worst-case binomial sample size: z² × 0.25 / e².
    var derivedWorstCaseTrialCount: Int {
        Int(ceil(pow(normalCriticalValue, 2) * 0.25 / pow(targetProbabilityHalfWidth, 2)))
    }

    func classification(for interval: ProbabilityInterval, hasUnresolvedCriticalInputs: Bool) -> FeasibilityStatus {
        if hasUnresolvedCriticalInputs { return .requiresConfirmation }
        if interval.lower95 >= safeLowerProbability { return .safe }
        if interval.upper95 < notRecommendedUpperProbability { return .notRecommended }
        return .tight
    }
}

enum StableSimulationSeed {
    static func snapshot(
        itineraryID: UUID,
        inputRevision: Int,
        snapshotRevision: String,
        policyVersion: String
    ) -> UInt64 {
        digest("\(itineraryID.uuidString)|\(inputRevision)|\(snapshotRevision)|\(policyVersion)")
    }

    static func digest(_ value: String) -> UInt64 {
        let bytes = SHA256.hash(data: Data(value.utf8))
        return bytes.prefix(MemoryLayout<UInt64>.size).reduce(UInt64.zero) { ($0 << 8) | UInt64($1) }
    }
}

enum StableEntityID {
    static func uuid(_ value: String) -> UUID {
        let hex = SHA256.hash(data: Data(value.utf8)).prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        let formatted = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: formatted)!
    }
}

struct ReplayableRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private(set) var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func unitInterval() -> Double {
        Double(next()) / Double(UInt64.max)
    }
}
