import XCTest
@testable import AirBorder

final class FoundationModelExplanationServiceTests: XCTestCase {
    @MainActor
    func testPromptPreservesAssessmentValuesAndMakesNoAuthorityClaim() {
        let trace = CalculationTrace(
            policyVersion: "test", simulationSeed: nil, generatedAt: .now,
            steps: [DerivationStep(label: "Gate walk", formula: "route", inputRecordIDs: ["route-1"], result: "12 min")],
            sourceRecordIDs: ["route-1"], unresolvedInputs: []
        )
        let assessment = FeasibilityAssessment(
            candidateID: UUID(), status: .tight, probability: nil,
            availableWindowMinutes: 35, requiredMostLikelyMinutes: 28, usableRestMinutes: 7,
            latestReturnTime: nil, summary: "Leave little room for delay.", trace: trace
        )

        let prompt = FoundationModelExplanationService.prompt(for: assessment)
        XCTAssertTrue(prompt.contains("Status: Tight"))
        XCTAssertTrue(prompt.contains("Available time: 35 min"))
        XCTAssertTrue(prompt.contains("Gate walk: 12 min"))
        XCTAssertTrue(FoundationModelExplanationService.instructions.contains("Do not add facts"))
        XCTAssertTrue(FoundationModelExplanationService.instructions.contains("original calculation is authoritative"))
    }
}
