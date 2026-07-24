import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// An optional on-device *presentation* layer for an already-computed assessment.
/// It receives no traveller profile data and never provides operational advice.
@MainActor
final class FoundationModelExplanationService: ObservableObject {
    enum State: Equatable {
        case idle
        case generating
        case available(String)
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle

    func summarize(_ assessment: FeasibilityAssessment) async {
        guard #available(iOS 26.0, *) else {
            state = .unavailable("On-device summary requires iOS 26 or later.")
            return
        }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            state = .unavailable("Apple Intelligence is not ready on this device. The original calculation remains below.")
            return
        }

        state = .generating
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: Self.prompt(for: assessment))
            state = .available(response.content)
        } catch {
            state = .unavailable("An on-device summary could not be generated. Review the original calculation below.")
        }
    }

    static let instructions = """
    Rewrite only the supplied, already-calculated layover assessment in one or two short sentences.
    Do not add facts, estimates, instructions, travel advice, or claims about boarding, entry, immigration, safety, or feasibility.
    Do not change the stated status or numbers. Say that the original calculation is authoritative.
    """

    static func prompt(for assessment: FeasibilityAssessment) -> String {
        let steps = assessment.trace.steps.map { "- \($0.label): \($0.result)" }.joined(separator: "\n")
        return """
        Status: \(assessment.status.title)
        Summary: \(assessment.summary)
        Available time: \(formattedMinutes(assessment.availableWindowMinutes))
        Estimated plan time: \(formattedMinutes(assessment.requiredMostLikelyMinutes))
        Time left: \(formattedMinutes(assessment.usableRestMinutes))
        Included calculation steps:
        \(steps)
        """
    }

    private static func formattedMinutes(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) min" } ?? "unknown"
    }
}
