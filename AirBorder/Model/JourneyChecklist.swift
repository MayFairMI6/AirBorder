import Foundation

enum StepState: String, Codable {
    case pending, confirmed, skipped
}

struct JourneyStep: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    /// A traveller can skip an applicable checklist row only when it becomes current.
    let canSkip: Bool
    var state: StepState = .pending

    /// Label under the dot in the progress strip.
    var shortTitle: String {
        switch id {
        case "gate": "Gate"
        case "narita": "Narita"
        default: title
        }
    }
}

/// Departure-to-arrival checkpoints for the Haneda connection.
///
/// The current step is the first pending checkpoint.
struct JourneyChecklist: Codable, Equatable {
    var steps: [JourneyStep]
    private(set) var lastChange: Change?
    /// Saved with the checklist so a confirmation always identifies the full departure gate.
    private(set) var confirmedGate: String? = nil

    struct Change: Codable, Equatable {
        let stepID: String
        let previous: StepState
    }

    static let haneda = JourneyChecklist(steps: [
        JourneyStep(id: "arrival", title: "Arrival", canSkip: false, state: .confirmed),
        JourneyStep(id: "connection", title: "Connection", canSkip: false, state: .confirmed),
        JourneyStep(id: "security", title: "Security", canSkip: false),
        JourneyStep(id: "passport", title: "Passport control", canSkip: true),
        JourneyStep(id: "gate", title: "Gate and boarding", canSkip: false),
    ])

    /// Haneda → Narita: entering Japan, so passport control and customs come before the bus (Figma 1041:17207).
    static let narita = JourneyChecklist(steps: [
        JourneyStep(id: "arrival", title: "Arrival", canSkip: false, state: .confirmed),
        JourneyStep(id: "passport", title: "Passport control", canSkip: false),
        JourneyStep(id: "bags", title: "Bags", canSkip: false),
        JourneyStep(id: "customs", title: "Customs", canSkip: false),
        JourneyStep(id: "narita", title: "Transfer to Narita", canSkip: false),
    ])

    var currentIndex: Int? { steps.firstIndex { $0.state == .pending } }

    var nextIndex: Int? {
        guard let current = currentIndex else { return nil }
        return steps.indices.first { $0 > current && steps[$0].state == .pending }
    }

    var current: JourneyStep? { currentIndex.map { steps[$0] } }
    var next: JourneyStep? { nextIndex.map { steps[$0] } }
    var isComplete: Bool { currentIndex == nil }

    func canConfirm(_ id: String) -> Bool { current?.id == id }

    func canSkip(_ id: String) -> Bool {
        current?.id == id && current?.canSkip == true
    }

    func canUndo(_ id: String) -> Bool { lastChange?.stepID == id }

    mutating func confirm(_ id: String, departureGate: String? = nil) {
        guard canConfirm(id) else { return }
        if id == "gate" {
            guard let departureGate, !departureGate.isEmpty else { return }
            confirmedGate = departureGate
        }
        set(id, .confirmed)
    }

    mutating func reconcileGate(_ departureGate: String) {
        guard let index = steps.firstIndex(where: { $0.id == "gate" && $0.state == .confirmed }),
              confirmedGate == nil || confirmedGate != departureGate else { return }
        steps[index].state = .pending
        confirmedGate = nil
        if lastChange?.stepID == "gate" { lastChange = nil }
    }

    mutating func skip(_ id: String) {
        guard canSkip(id) else { return }
        set(id, .skipped)
    }

    mutating func undo() {
        guard let change = lastChange, let index = steps.firstIndex(where: { $0.id == change.stepID }) else { return }
        steps[index].state = change.previous
        if change.stepID == "gate" { confirmedGate = nil }
        lastChange = nil
    }

    private mutating func set(_ id: String, _ state: StepState) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        lastChange = Change(stepID: id, previous: steps[index].state)
        steps[index].state = state
    }

    func status(of step: JourneyStep) -> String {
        switch step.state {
        case .confirmed: return "Confirmed"
        case .skipped: return "Skipped"
        case .pending: return step.id == current?.id ? "Current step" : "Upcoming"
        }
    }
}
