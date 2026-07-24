import Foundation

struct LayoverSafetyInput: Sendable {
    let inboundArrival: Date
    let boardingTime: Date
    let immigrationMinutes: Int
    let baggageMinutes: Int
    let airportExitMinutes: Int
    let outboundTransitMinutes: Int
    let activityMinutes: Int
    let returnTransitMinutes: Int
    let securityMinutes: Int
    let terminalTransferMinutes: Int
    let accessibilityImpactMinutes: Int
    let safetyBufferMinutes: Int
}

struct LayoverSafetyService: Sendable {
    func assess(_ input: LayoverSafetyInput) -> LayoverAssessment {
        let totalRequired = input.immigrationMinutes + input.baggageMinutes + input.airportExitMinutes
            + input.outboundTransitMinutes + input.activityMinutes + input.returnTransitMinutes
            + input.securityMinutes + input.terminalTransferMinutes + input.accessibilityImpactMinutes
            + input.safetyBufferMinutes
        let available = Int(input.boardingTime.timeIntervalSince(input.inboundArrival) / 60)
        let margin = available - totalRequired

        if margin < 0 {
            return LayoverAssessment(safety: .notRecommended, remainingMarginMinutes: margin, message: "Do not leave the airport. The plan exceeds the available layover by \(abs(margin)) minutes.")
        }
        if margin == 0 {
            return LayoverAssessment(safety: .tight, remainingMarginMinutes: margin, message: "This plan consumes the entire supplied safety buffer. Stay at the airport unless sourced conditions improve.")
        }
        return LayoverAssessment(safety: .safe, remainingMarginMinutes: margin, message: "The plan retains a \(margin)-minute return margin after all buffers.")
    }
}
