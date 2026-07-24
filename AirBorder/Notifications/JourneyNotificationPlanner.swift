import Foundation
import UserNotifications

enum JourneyNotificationKind: String, Codable, Sendable {
    case gateChange
    case boardingSoon
    case boardingStarted
    case significantDelay
    case cancellation
    case diversion
    case terminalChange
    case connectionRisk
    case leaveNow
}

struct JourneyNotificationPlan: Equatable, Sendable {
    let id: String
    let kind: JourneyNotificationKind
    let title: String
    let body: String
    let fireDate: Date
    let deepLink: String
}

struct JourneyNotificationPlanner: Sendable {
    func plans(previous: Flight?, current: Flight, journeyID: UUID, assessment: JourneyAssessment, now: Date) -> [JourneyNotificationPlan] {
        var plans: [JourneyNotificationPlan] = []
        let prefix = journeyID.uuidString

        if let oldGate = previous?.gate, let gate = current.gate, oldGate != gate {
            plans.append(plan(prefix, .gateChange, "Gate changed to \(gate)", "Previous gate \(oldGate). Your route has been recalculated.", now, "airportxr://journey/gate-change"))
        }
        if previous?.departureTerminal != current.departureTerminal, let terminal = current.departureTerminal {
            plans.append(plan(prefix, .terminalChange, "Terminal changed", "Proceed to Terminal \(terminal) and review the updated route.", now, "airportxr://map"))
        }
        if current.status == .cancelled && previous?.status != .cancelled {
            plans.append(plan(prefix, .cancellation, "Flight cancelled", "Open the app for disruption guidance.", now, "airportxr://journey/disruption"))
        }
        if current.status == .diverted && previous?.status != .diverted {
            plans.append(plan(prefix, .diversion, "Flight diverted", "Review the latest airline information.", now, "airportxr://journey/disruption"))
        }
        if (current.delayMinutes ?? 0) >= 15 && (previous?.delayMinutes ?? 0) < 15 {
            plans.append(plan(prefix, .significantDelay, "Flight delayed", "Current delay: \(current.delayMinutes ?? 0) minutes.", now, "airportxr://journey"))
        }
        if current.status == .boarding && previous?.status != .boarding {
            plans.append(plan(prefix, .boardingStarted, "Boarding has started", "Proceed directly to Gate \(current.gate ?? "shown in the app").", now, "airportxr://guide"))
        }
        if let boarding = current.boardingTime, boarding > now {
            let reminder = boarding.addingTimeInterval(-10 * 60)
            if reminder > now {
                plans.append(plan(prefix, .boardingSoon, "Boarding soon", "Boarding begins in 10 minutes at Gate \(current.gate ?? "shown in the app").", reminder, "airportxr://journey"))
            }
        }
        if [.urgent, .likelyInsufficientTime].contains(assessment.urgency) {
            plans.append(plan(prefix, .leaveNow, "Leave now", assessment.message, now, "airportxr://guide"))
        }
        return Dictionary(grouping: plans, by: \.id).compactMap(\.value.first).sorted { $0.fireDate < $1.fireDate }
    }

    private func plan(_ prefix: String, _ kind: JourneyNotificationKind, _ title: String, _ body: String, _ fireDate: Date, _ deepLink: String) -> JourneyNotificationPlan {
        JourneyNotificationPlan(id: "\(prefix).\(kind.rawValue)", kind: kind, title: title, body: body, fireDate: fireDate, deepLink: deepLink)
    }
}

protocol NotificationScheduling: Sendable {
    func requestAuthorization() async throws -> Bool
    func schedule(_ plans: [JourneyNotificationPlan]) async throws
    func cancelJourneyNotifications(journeyID: UUID) async
}

actor SystemNotificationScheduler: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(_ plans: [JourneyNotificationPlan]) async throws {
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.userInfo = ["deepLink": plan.deepLink]
            let interval = max(1, plan.fireDate.timeIntervalSinceNow)
            let request = UNNotificationRequest(identifier: plan.id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            try await center.add(request)
        }
    }

    func cancelJourneyNotifications(journeyID: UUID) async {
        let prefix = journeyID.uuidString
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }
}

/// Keeps the traveller's selected plan actionable when the app is not open.
/// Time-based alerts are reliable even when iOS has not delivered a fresh
/// location. Proximity is deliberately limited to places the traveller has
/// selected, rather than advertising every nearby venue.
struct BackgroundJourneyAlertPlanner: Sendable {
    func plans(
        journeyID: UUID,
        leaveBy: Date?,
        gate: String?,
        selectedPlace: LayoverPlace?,
        now: Date
    ) -> [JourneyNotificationPlan] {
        let prefix = journeyID.uuidString
        var plans: [JourneyNotificationPlan] = []

        if let leaveBy, leaveBy > now {
            let reminder = max(now.addingTimeInterval(1), leaveBy.addingTimeInterval(-10 * 60))
            plans.append(JourneyNotificationPlan(
                id: "\(prefix).leave-by",
                kind: .leaveNow,
                title: "Head to Gate \(gate ?? "")".trimmingCharacters(in: .whitespaces),
                body: "Leave in 10 minutes to stay on plan.",
                fireDate: reminder,
                deepLink: "airportxr://guide"
            ))
        }

        if let selectedPlace {
            plans.append(JourneyNotificationPlan(
                id: "\(prefix).selected-place",
                kind: .connectionRisk,
                title: selectedPlace.name,
                body: "This is part of your selected plan. Keep an eye on your leave-by time.",
                fireDate: now.addingTimeInterval(2),
                deepLink: "airportxr://journey"
            ))
        }
        return plans
    }
}
