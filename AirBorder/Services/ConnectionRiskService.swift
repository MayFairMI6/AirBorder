import Foundation

struct ConnectionRiskInput: Sendable {
    let inboundEstimatedArrival: Date?
    let onwardBoardingCutoff: Date?
    let inboundDelayMinutes: Int
    let arrivalTerminal: String?
    let connectionTerminal: String?
    let immigrationMinutes: Int
    let securityRescreenMinutes: Int
    let airportTransferMinutes: Int
    let walkingMinutes: Int
    let minimumConnectionMinutes: Int
    let accessibilityImpactMinutes: Int
    let now: Date
}

struct ConnectionRiskAssessment: Sendable {
    let risk: ConnectionRisk
    let availableMinutes: Int?
    let requiredMinutes: Int
    let message: String
}

struct ConnectionRiskService: Sendable {
    func assess(_ input: ConnectionRiskInput) -> ConnectionRiskAssessment {
        // Terminal changes do not have a universal duration. Callers must put
        // the sourced terminal/airport movement in airportTransferMinutes and
        // walkingMinutes; an airport-code comparison cannot invent minutes.
        let required = max(
            input.minimumConnectionMinutes,
            input.immigrationMinutes + input.securityRescreenMinutes + input.airportTransferMinutes
                + input.walkingMinutes + input.accessibilityImpactMinutes
        )
        guard let arrival = input.inboundEstimatedArrival, let cutoff = input.onwardBoardingCutoff else {
            return ConnectionRiskAssessment(risk: .insufficientData, availableMinutes: nil, requiredMinutes: required, message: "Connection timing needs arrival and boarding-cutoff data.")
        }

        let available = Int(cutoff.timeIntervalSince(max(arrival, input.now)) / 60)
        if available < required {
            return ConnectionRiskAssessment(risk: .atRisk, availableMinutes: available, requiredMinutes: required, message: "Your connection may be at risk. \(available) minutes are available; about \(required) are needed.")
        }
        // The tight band scales with the actual route/accessibility work that
        // would have to be recovered after a disruption; it is not a global
        // hidden scalar penalty.
        let recoveryWindow = max(input.walkingMinutes, input.accessibilityImpactMinutes)
        if available < required + recoveryWindow {
            return ConnectionRiskAssessment(risk: .tight, availableMinutes: available, requiredMinutes: required, message: "Your connection is tight. Proceed directly after arrival.")
        }
        return ConnectionRiskAssessment(risk: .comfortable, availableMinutes: available, requiredMinutes: required, message: "Your current connection margin is comfortable.")
    }
}
