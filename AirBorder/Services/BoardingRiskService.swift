import Foundation

struct BoardingRiskInput: Sendable {
    let scheduledBoardingTime: Date?
    let estimatedBoardingTime: Date?
    let departureTime: Date?
    let flightStatus: FlightStatus
    let boardingGroup: String?
    let walkMinutes: Int
    let accessibleRouteMinutes: Int
    let useAccessibleRoute: Bool
    let securityMinutes: Int
    let immigrationMinutes: Int
    let locationConfidence: LocalizationConfidence
    let gateChanged: Bool
    let terminalChanged: Bool
    let routeUncertaintyMinutes: Int
    let providerUpdatedAt: Date
    let freshness: DataFreshness
    let extraBufferMinutes: Int
    let now: Date
}

struct BoardingRiskService: Sendable {
    func assess(_ input: BoardingRiskInput) -> JourneyAssessment {
        var alerts = Set<JourneyAlert>()
        if input.gateChanged { alerts.insert(.gateChange) }
        if input.terminalChanged { alerts.insert(.terminalChange) }
        if input.locationConfidence == .low || input.locationConfidence == .unavailable { alerts.insert(.weakLocalization) }
        // Freshness is provider-policy derived before this service is called.
        // Do not replace that source-specific expiry with a universal age.
        if input.freshness == .stale || input.freshness == .unavailable { alerts.insert(.staleData) }

        if input.flightStatus == .cancelled {
            alerts.insert(.cancellation)
            return assessment(.urgent, input, alerts, "Flight cancelled. Stop gate guidance and review disruption options.", nil)
        }
        if input.flightStatus == .diverted {
            alerts.insert(.diversion)
            return assessment(.urgent, input, alerts, "Flight diverted. Review the latest airline instructions.", nil)
        }

        // A departure time does not imply a universal boarding lead. When the
        // airline/provider does not supply boarding, keep it unknown.
        let boardingTime = input.estimatedBoardingTime ?? input.scheduledBoardingTime
        guard let boardingTime else {
            return assessment(.dataStale, input, alerts.union([.staleData]), "Boarding time is unavailable. Verify the airport displays.", nil)
        }

        let routeMinutes = input.useAccessibleRoute ? input.accessibleRouteMinutes : input.walkMinutes
        let requiredMinutes = routeMinutes + input.securityMinutes + input.immigrationMinutes
            + input.routeUncertaintyMinutes + input.extraBufferMinutes
        let leaveBy = boardingTime.addingTimeInterval(TimeInterval(-requiredMinutes * 60))
        let marginMinutes = Int(boardingTime.timeIntervalSince(input.now) / 60) - requiredMinutes

        if input.flightStatus == .boarding || input.now >= boardingTime {
            alerts.insert(.boarding)
            let gateText = input.gateChanged ? " Your gate changed; follow the recalculated route." : ""
            return assessment(.boarding, input, alerts, "Boarding has started. Proceed directly to the gate.\(gateText)", leaveBy)
        }
        if marginMinutes < 0 {
            return assessment(.likelyInsufficientTime, input, alerts, "There may not be enough time. Proceed directly and ask airport staff for help.", leaveBy)
        }
        if marginMinutes == 0 {
            return assessment(.urgent, input, alerts, "Leave now. Your route and buffer use nearly all available time.", leaveBy)
        }
        if input.gateChanged {
            return assessment(.gateChanged, input, alerts, "Your gate changed. The route has been recalculated.", leaveBy)
        }
        // "Leave soon" is contextual: it means the remaining wait before the
        // derived leave-by instant is no longer than the selected route plus
        // its sourced uncertainty, rather than an unexplained minute cutoff.
        let reorientationWindow = max(0, routeMinutes + input.routeUncertaintyMinutes)
        if marginMinutes <= reorientationWindow {
            return assessment(.leaveSoon, input, alerts, "Leave within \(marginMinutes) minutes.", leaveBy)
        }
        if alerts.contains(.staleData) {
            return assessment(.dataStale, input, alerts, "Flight information may be stale. Verify the airport displays before continuing.", leaveBy)
        }
        let accessibilityText = input.useAccessibleRoute && input.accessibleRouteMinutes > input.walkMinutes
            ? " The accessible route adds \(input.accessibleRouteMinutes - input.walkMinutes) minutes."
            : ""
        return assessment(.comfortable, input, alerts, "You have enough time. Continue when ready.\(accessibilityText)", leaveBy)
    }

    private func assessment(
        _ urgency: JourneyUrgency,
        _ input: BoardingRiskInput,
        _ alerts: Set<JourneyAlert>,
        _ message: String,
        _ leaveBy: Date?
    ) -> JourneyAssessment {
        JourneyAssessment(
            urgency: urgency,
            operationalStatus: input.flightStatus,
            freshness: input.freshness,
            localizationConfidence: input.locationConfidence,
            alerts: alerts,
            message: message,
            leaveBy: leaveBy
        )
    }
}
