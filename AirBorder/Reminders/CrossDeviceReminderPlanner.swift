import Foundation

struct CrossDeviceReminderPlanner: Sendable {
    func intents(from input: CrossDeviceReminderPlanningInput, now: Date) -> [CrossDeviceReminderIntent] {
        let itinerary = input.itinerary
        let scopeID = itinerary.id.uuidString.lowercased()
        var intents: [CrossDeviceReminderIntent] = []

        if let activeAssessment = input.journeyAssessment,
           let leaveBy = activeAssessment.leaveBy,
           leaveBy >= now {
            let activeLeg = input.activeLegID.flatMap { legID in
                itinerary.legs.first(where: { $0.id == legID })
            }
            let gateSuffix = activeLeg?.flight.gate.map { " \($0)" } ?? ""
            let sourceIDs = activeLeg?.flight.source.providerRecordID.map { [$0] } ?? []
            intents.append(intent(
                scopeID: scopeID,
                stableComponent: "go-to-gate|\(input.activeLegID?.uuidString ?? "active")",
                kind: .goToGate,
                title: "Go to Gate\(gateSuffix)",
                body: "This action time comes from the current boarding, route, processing, accessibility, and safety inputs.",
                actionAt: leaveBy,
                timeZoneIdentifier: activeLeg?.flight.origin.timeZone,
                deepLink: URL(string: "airportxr://guide")!,
                sourceRevision: itinerary.inputRevision,
                derivation: [DerivationStep(
                    label: "Go-to-gate action time",
                    formula: "boarding time - personalized route - required processing - route uncertainty - safety buffer",
                    inputRecordIDs: sourceIDs,
                    result: Self.iso8601.string(from: leaveBy)
                )]
            ))
        }

        for leg in itinerary.legs {
            guard let gateCloseMetric = leg.gateCloseTime,
                  gateCloseMetric.value >= now,
                  gateCloseMetric.isEligibleForExternalAction(at: now) else { continue }
            intents.append(intent(
                scopeID: scopeID,
                stableComponent: "gate-close|\(leg.id.uuidString)",
                kind: .gateClose,
                title: "Gate closes for \(leg.flight.flightNumber)",
                body: "This is the sourced gate-close outer bound, not an airport-arrival target.",
                actionAt: gateCloseMetric.value,
                timeZoneIdentifier: leg.flight.origin.timeZone,
                deepLink: URL(string: "airportxr://journey")!,
                sourceRevision: itinerary.inputRevision,
                derivation: gateCloseMetric.derivation + [DerivationStep(
                    label: "Gate-close reminder",
                    formula: "action time = sourced onward gate-close",
                    inputRecordIDs: [gateCloseMetric.sourceRecordID],
                    result: Self.iso8601.string(from: gateCloseMetric.value)
                )]
            ))
        }

        if let latestReturn = input.latestReturn,
           latestReturn.criticalInputsAreCurrent,
           latestReturn.assessment.status == .safe,
           latestReturn.assessment.trace.unresolvedInputs.isEmpty,
           let actionAt = latestReturn.assessment.latestReturnTime,
           actionAt >= now,
           let layover = itinerary.layovers.first(where: { $0.id == latestReturn.layoverID }) {
            intents.append(intent(
                scopeID: scopeID,
                stableComponent: "latest-return|\(latestReturn.assessment.candidateID.uuidString)",
                kind: .latestReturn,
                title: "Return now for your onward flight",
                body: "Latest return for \(latestReturn.candidateTitle), calculated from current return travel, re-entry, security, terminal route, and safety inputs.",
                actionAt: actionAt,
                timeZoneIdentifier: itinerary.legs.first(where: { $0.id == layover.inboundLegID })?.flight.destination.timeZone,
                deepLink: URL(string: "airportxr://transit")!,
                sourceRevision: itinerary.inputRevision,
                derivation: latestReturn.assessment.trace.steps + [DerivationStep(
                    label: "Latest-return reminder",
                    formula: "onward gate-close - return travel - re-entry - security - terminal route - safety",
                    inputRecordIDs: latestReturn.assessment.trace.sourceRecordIDs,
                    result: Self.iso8601.string(from: actionAt)
                )]
            ))
        }

        return Dictionary(grouping: intents, by: \CrossDeviceReminderIntent.id)
            .compactMap(\.value.first)
            .sorted { left, right in
                if left.actionAt != right.actionAt { return left.actionAt < right.actionAt }
                return left.id < right.id
            }
    }

    private func intent(
        scopeID: String,
        stableComponent: String,
        kind: CrossDeviceReminderKind,
        title: String,
        body: String,
        actionAt: Date,
        timeZoneIdentifier: String?,
        deepLink: URL,
        sourceRevision: Int,
        derivation: [DerivationStep]
    ) -> CrossDeviceReminderIntent {
        let stableID = StableEntityID.uuid("reminder|\(scopeID)|\(stableComponent)").uuidString.lowercased()
        return CrossDeviceReminderIntent(
            id: stableID,
            scopeID: scopeID,
            kind: kind,
            title: title,
            body: body,
            actionAt: actionAt,
            timeZoneIdentifier: timeZoneIdentifier,
            deepLink: deepLink,
            sourceRevision: sourceRevision,
            derivation: derivation
        )
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
