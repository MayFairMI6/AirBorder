import Foundation

enum MetricUnit: String, Codable, Hashable, Sendable {
    case minutes
    case seconds
    case meters
    case kilometers
    case probability
    case dateTime
    case count
    case text
}

struct DerivationStep: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let label: String
    let formula: String
    let inputRecordIDs: [String]
    let result: String

    init(
        id: UUID? = nil,
        label: String,
        formula: String,
        inputRecordIDs: [String],
        result: String
    ) {
        self.id = id ?? StableEntityID.uuid("derivation|\(label)|\(formula)|\(inputRecordIDs.joined(separator: "|"))|\(result)")
        self.label = label
        self.formula = formula
        self.inputRecordIDs = inputRecordIDs
        self.result = result
    }
}

struct SourcedMetric<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    let value: Value
    let unit: MetricUnit
    let provider: String
    let providerField: String
    let sourceRecordID: String
    let observedAt: Date
    let receivedAt: Date
    let expiresAt: Date?
    let uncertainty: String?
    let derivation: [DerivationStep]

    func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date
    }
}

struct EstimateDistribution: Codable, Hashable, Sendable {
    let lower: Double
    let mostLikely: Double
    let upper: Double
    let unit: MetricUnit

    var isValid: Bool {
        lower.isFinite && mostLikely.isFinite && upper.isFinite
            && lower >= 0 && lower <= mostLikely && mostLikely <= upper
    }

    static func point(_ value: Double, unit: MetricUnit = .minutes) -> EstimateDistribution {
        EstimateDistribution(lower: value, mostLikely: value, upper: value, unit: unit)
    }
}

struct CalculationTrace: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let policyVersion: String
    let simulationSeed: UInt64?
    let generatedAt: Date
    let steps: [DerivationStep]
    let sourceRecordIDs: [String]
    let unresolvedInputs: [String]

    init(
        id: UUID? = nil,
        policyVersion: String,
        simulationSeed: UInt64?,
        generatedAt: Date,
        steps: [DerivationStep],
        sourceRecordIDs: [String],
        unresolvedInputs: [String]
    ) {
        self.id = id ?? StableEntityID.uuid(
            "trace|\(policyVersion)|\(simulationSeed.map(String.init) ?? "none")|\(steps.map { $0.id.uuidString }.joined(separator: "|"))|\(unresolvedInputs.joined(separator: "|"))"
        )
        self.policyVersion = policyVersion
        self.simulationSeed = simulationSeed
        self.generatedAt = generatedAt
        self.steps = steps
        self.sourceRecordIDs = sourceRecordIDs
        self.unresolvedInputs = unresolvedInputs
    }
}
