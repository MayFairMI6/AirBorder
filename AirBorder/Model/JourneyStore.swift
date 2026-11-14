import Foundation
import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case flight, layover, route, profile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .flight: return "Flight"
        case .layover: return "Layover"
        case .route: return "Route"
        case .profile: return "Profile"
        }
    }
}

/// Figma "Choose a route" options. Minutes are the average walking times for each route.
enum RouteChoice: String, CaseIterable, Codable {
    case direct, stepFree, lessCrowded

    var title: String {
        switch self {
        case .direct: return "Direct"
        case .stepFree: return "Step-free"
        case .lessCrowded: return "Less crowded"
        }
    }

    var detail: String {
        switch self {
        case .direct: return "Shortest walking route"
        case .stepFree: return "Use lifts and level corridors"
        case .lessCrowded: return "Avoid the busy central corridor"
        }
    }

    var averageMinutes: Int {
        switch self {
        case .direct: return 12
        case .stepFree: return 16
        case .lessCrowded: return 15
        }
    }
}

enum HealthConnection: String, Codable {
    case notConnected, connected, removed
}

/// App state for the traveller's journey: selected plan, checkpoints, preferences and walking data.
@MainActor
final class JourneyStore: ObservableObject {
    @Published var tab: AppTab = .flight
    @Published private(set) var plan: Plan { didSet { persist() } }
    @Published private(set) var checklist: JourneyChecklist { didSet { persist() } }
    @Published private(set) var suggestion: PlanSuggestion?
    @Published private(set) var undoPlan: Plan?
    @Published var stepFreeRoutes: Bool {
        didSet {
            persist()
            routeChoice = stepFreeRoutes ? .stepFree : .direct
        }
    }
    @Published var routeChoice: RouteChoice = .direct
    @Published var onboardingSeen: Bool { didSet { persist() } }
    @Published var firstName: String { didSet { persist() } }
    @Published var lastName: String { didSet { persist() } }
    @Published var baggagePreference: BaggagePreference { didSet { persist() } }
    @Published var profilePhoto: UIImage? { didSet { ProfilePhotoStore.save(profilePhoto) } }
    @Published private(set) var toast: ToastMessage?
    /// The traveller's saved trip flight as they last confirmed it (Edit flight details).
    @Published private(set) var tripFlight: TripFlight { didSet { persist() } }
    /// Edits in progress on Edit flight details, applied on Save flight.
    @Published var flightDraft: TripFlight
    /// Flights the traveller typed in on Add a flight › Add manually.
    @Published private(set) var manualFlights: [ManualFlight] { didSet { persist() } }
    /// "+1 checked bag" declared on Extra baggage.
    @Published var extraBagDeclared: Bool { didSet { persist() } }
    /// A 30-minute visit to the Terminal 2 Observation Deck (landside).
    @Published var t2VisitPlanned: Bool { didSet { persist() } }
    private var toastAction: (() -> Void)?
    @Published private(set) var health: HealthConnection { didSet { persist() } }
    @Published private(set) var walkingSpeedKmh: Double?
    @Published private(set) var lastHealthSync: Date?
    @Published var routeStep = 1

    /// Airport local time the journey is shown at. The sample journey stays at 12:00.
    @Published private(set) var now: ClockTime = SampleJourney.now
    /// Latest departure-flight report from the flight-status feed.
    @Published private(set) var feed: FlightFeed? { didSet { persist() } }
    /// Alerts the traveller has been shown, keyed by kind.
    @Published private(set) var alerts: [AlertKind: AlertRecord] { didSet { persist() } }
    /// Set when a new alert should open the Alerts screen.
    @Published var alertToPresent: AlertKind?

    /// Seeded queue report for Curacion Cafe in the sample journey: the wait is now about 18 min.
    let cafeQueueUpdate = QueueUpdate(stopID: .cafe, waitMinutes: 18)
    private var queueUpdateHandled: Bool { didSet { persist() } }

    private let walkingData: WalkingDataSource
    private let defaults: UserDefaults
    private static let stateKey = "journeyState.v1"

    init(walkingData: WalkingDataSource, defaults: UserDefaults = .standard, reset: Bool = false) {
        self.walkingData = walkingData
        self.defaults = defaults
        if reset { defaults.removeObject(forKey: Self.stateKey) }
        let saved = defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode(SavedState.self, from: $0) }
        plan = saved?.plan ?? Plan()
        checklist = saved?.checklist ?? .haneda
        stepFreeRoutes = saved?.stepFreeRoutes ?? false
        firstName = saved?.firstName ?? ""
        lastName = saved?.lastName ?? ""
        baggagePreference = saved?.baggagePreference ?? .taggedThrough
        tripFlight = saved?.tripFlight ?? .sample
        flightDraft = saved?.tripFlight ?? .sample
        manualFlights = saved?.manualFlights ?? []
        extraBagDeclared = saved?.extraBagDeclared ?? false
        t2VisitPlanned = saved?.t2VisitPlanned ?? false
        profilePhoto = reset ? nil : ProfilePhotoStore.load()
        health = saved?.health ?? .notConnected
        queueUpdateHandled = saved?.queueUpdateHandled ?? false
        onboardingSeen = saved?.onboardingSeen ?? false
        feed = saved?.feed
        alerts = saved?.alerts ?? [:]
        routeChoice = (saved?.stepFreeRoutes ?? false) ? .stepFree : .direct
        var restoredChecklist = checklist
        restoredChecklist.reconcileGate(gate)
        if restoredChecklist != checklist {
            // Previous saves may contain a gate checkmark with no gate identifier.
            checklist = restoredChecklist
            clearGateTimingAlerts()
        }
        refreshSuggestion()
    }

    // MARK: Flight status and situations

    /// The next flight leaves from Narita (NH 6 chosen on Edit flight details).
    var isAirportTransfer: Bool { tripFlight.number == "NH 6" }

    /// The ticket's departure flight.
    var outbound: FlightLeg { isAirportTransfer ? SampleJourney.naritaOutbound : SampleJourney.outbound }

    /// Time between landing at Haneda and the next departure.
    var layoverMinutes: Int { outbound.departs - SampleJourney.inbound.arrives }

    /// The gate to show everywhere: the feed's latest gate, or the one on the ticket.
    var gate: String {
        if let reported = feed?.gate, !reported.isEmpty { return reported }
        return outbound.departureGate
    }

    var conditionInputs: ConditionInputs {
        let schedule = schedule
        let leave = schedule.stops.isEmpty ? SampleJourney.gateArrivalTarget - gateWalkMinutes : schedule.leave
        return ConditionInputs(
            now: now,
            ticketGate: outbound.departureGate,
            feed: feed,
            gateCloses: outbound.gateCloses,
            walkToGate: gateWalkMinutes,
            leaveBy: leave,
            atGate: checklist.confirmedGate == gate,
            departsFromAnotherAirport: isAirportTransfer
        )
    }

    /// Situations that hold right now, most urgent first.
    var conditions: [JourneyCondition] { JourneyConditions.evaluate(conditionInputs) }
    var primaryCondition: JourneyCondition? { conditions.first }

    /// Return now, boarding at risk or arrival after closure: the Flight tab shows the countdown instead of the plan.
    var hasTimingSituation: Bool {
        switch primaryCondition {
        case .returnNow, .boardingAtRisk, .arrivesAfterClosure: true
        default: false
        }
    }

    /// "Boarding soon" from 30 minutes before boarding.
    var flightStatus: String { now >= SampleJourney.boarding - 30 ? "Boarding soon" : outbound.status }

    /// Sets the airport time the journey is shown at (sample data and tests).
    func setNow(_ time: ClockTime) {
        now = time
        refreshAlerts()
    }

    /// A departure-flight report arrived from the feed.
    func receive(_ report: FlightFeed) {
        // A report without a gate leaves the last known gate and its observation time intact.
        guard let reportedGate = report.gate, !reportedGate.isEmpty else { return }
        if reportedGate != gate {
            checklist.reconcileGate(reportedGate)
            clearGateTimingAlerts()
        }
        feed = report
        refreshAlerts()
    }

    private func clearGateTimingAlerts() {
        alerts.removeValue(forKey: .returnNow)
        alerts.removeValue(forKey: .boardingAtRisk)
    }

    /// The sample journey's gate update: Gate 108A, reported a short while after the app opens.
    func startSampleFeed(after delay: Duration) {
        guard feed == nil else { return refreshAlerts() }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard feed == nil else { return }
            receive(FlightFeed(gate: "108A", receivedAt: now))
        }
    }

    /// Records alerts for situations that just began and asks to show the most urgent new one.
    func refreshAlerts() {
        var newest: AlertKind?
        for condition in conditions.reversed() {
            guard let kind = condition.alertKind, alerts[kind] == nil else { continue }
            let issued = kind == .gateChange ? (feed?.receivedAt ?? now) : now
            alerts[kind] = AlertRecord(issuedAt: issued)
            newest = kind
        }
        if let newest { alertToPresent = newest }
    }

    func alertSeen(_ kind: AlertKind) {
        guard var record = alerts[kind], record.firstSeen == nil else { return }
        record.firstSeen = Date()
        alerts[kind] = record
    }

    /// "Heading to the gate": the traveller acted on the alert.
    func acknowledge(_ kind: AlertKind) {
        alerts[kind]?.acknowledged = true
    }

    // MARK: Walking

    var pace: WalkingPace {
        WalkingEstimate.pace(walks: SampleJourney.airportWalks, healthKmh: health == .connected ? walkingSpeedKmh : nil)
    }

    var schedule: Schedule { PlanEngine.schedule(plan, pace: pace) }

    func walkMinutes(_ from: PlaceID, _ to: PlaceID) -> Int { WalkMatrix.minutes(from, to, pace: pace) }

    /// Walk from a venue back to the gate, as on the Layover cards and Return to gate screens (4, 6 and 8 min on average).
    func venueToGateMinutes(_ place: PlaceID) -> Int {
        let average: Int = switch place {
        case .anaLounge: 4
        case .cafe: 6
        default: 8
        }
        return WalkingTimes.minutes(average: average, pace: pace)
    }

    /// Walk from here to the gate on the chosen route.
    var gateWalkMinutes: Int { gateWalkMinutes(for: routeChoice) }

    func gateWalkMinutes(for choice: RouteChoice) -> Int {
        WalkingTimes.minutes(average: choice.averageMinutes, pace: pace)
    }

    var healthAvailable: Bool { walkingData.isAvailable }

    func connectHealth() async {
        do {
            try await walkingData.requestAccess()
            health = .connected
            await refreshWalkingSpeed()
        } catch {
            health = .notConnected
        }
    }

    func refreshWalkingSpeed() async {
        guard health == .connected else { return }
        walkingSpeedKmh = try? await walkingData.averageWalkingSpeedKmh()
        lastHealthSync = Date()
        refreshSuggestion()
    }

    func removeHealth() {
        health = .removed
        walkingSpeedKmh = nil
        lastHealthSync = nil
        refreshSuggestion()
    }

    // MARK: Plan

    func add(_ stop: PlanStop) {
        guard !plan.contains(stop.id) else { return }
        clearUndo()
        plan.stops.append(stop)
        refreshSuggestion()
        refreshAlerts()
    }

    func remove(_ id: PlaceID) {
        clearUndo()
        plan.stops.removeAll { $0.id == id }
        refreshSuggestion()
        refreshAlerts()
    }

    func replacePlan(with edited: Plan) {
        clearUndo()
        plan = edited
        refreshSuggestion()
    }

    func applySuggestion() {
        guard let suggestion, suggestion.basePlan == plan else { return refreshSuggestion() }
        undoPlan = plan
        plan = suggestion.proposed
        queueUpdateHandled = true
        self.suggestion = nil
    }

    /// Keeps the selected stops as they are. The longer queue still counts toward the timing.
    func keepPlan() {
        guard let suggestion, suggestion.basePlan == plan else { return refreshSuggestion() }
        plan = PlanEngine.applying(suggestion.update, to: plan)
        queueUpdateHandled = true
        self.suggestion = nil
    }

    func undoSuggestion() {
        guard let previous = undoPlan else { return }
        undoPlan = nil
        plan = previous
        queueUpdateHandled = false
        refreshSuggestion()
    }

    func clearUndo() { undoPlan = nil }

    /// Recomputes from the active plan; a suggestion for an older plan is dropped.
    private func refreshSuggestion() {
        guard !queueUpdateHandled, plan.contains(cafeQueueUpdate.stopID) else {
            suggestion = nil
            return
        }
        suggestion = PlanEngine.suggestion(for: plan, update: cafeQueueUpdate, pace: pace)
    }

    // MARK: Journey steps

    func confirmStep(_ id: String) { checklist.confirm(id, departureGate: gate); refreshAlerts() }
    func skipStep(_ id: String) { checklist.skip(id) }
    func undoStep() { checklist.undo() }

    // MARK: Preferences

    func resetPreferences() {
        stepFreeRoutes = false
        baggagePreference = .taggedThrough
        plan = Plan()
        undoPlan = nil
        checklist = isAirportTransfer ? .narita : .haneda
        queueUpdateHandled = false
        routeStep = 1
        refreshSuggestion()
        refreshAlerts()
        showToast(ToastMessage(text: "Trip preferences reset"))
    }

    // MARK: Saved flights

    func beginEditingFlight() { flightDraft = tripFlight }
    func saveFlightDraft() {
        let changedAirport = (flightDraft.number == "NH 6") != isAirportTransfer
        tripFlight = flightDraft
        if changedAirport {
            checklist = isAirportTransfer ? .narita : .haneda
            routeStep = 1
        }
        refreshAlerts()
    }
    func addManualFlight(_ flight: ManualFlight) { manualFlights.append(flight) }

    // MARK: Toasts (Figma section "Toasts")

    func showToast(_ message: ToastMessage, action: (() -> Void)? = nil) {
        toast = message
        toastAction = action
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if toast == message { toast = nil; toastAction = nil }
        }
    }

    func performToastAction() {
        toastAction?()
        toast = nil
        toastAction = nil
    }

    // MARK: Persistence

    private struct SavedState: Codable {
        var plan: Plan
        var checklist: JourneyChecklist
        var stepFreeRoutes: Bool
        var firstName: String?
        var lastName: String?
        var baggagePreference: BaggagePreference?
        var tripFlight: TripFlight?
        var manualFlights: [ManualFlight]?
        var extraBagDeclared: Bool?
        var t2VisitPlanned: Bool?
        var health: HealthConnection
        var queueUpdateHandled: Bool
        var onboardingSeen: Bool?
        var feed: FlightFeed?
        var alerts: [AlertKind: AlertRecord]?
    }

    private func persist() {
        let state = SavedState(
            plan: plan,
            checklist: checklist,
            stepFreeRoutes: stepFreeRoutes,
            firstName: firstName,
            lastName: lastName,
            baggagePreference: baggagePreference,
            tripFlight: tripFlight,
            manualFlights: manualFlights,
            extraBagDeclared: extraBagDeclared,
            t2VisitPlanned: t2VisitPlanned,
            health: health,
            queueUpdateHandled: queueUpdateHandled,
            onboardingSeen: onboardingSeen,
            feed: feed,
            alerts: alerts
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.stateKey)
        }
    }
}

/// The traveller's profile photo, kept in the app's Documents folder on this iPhone.
enum ProfilePhotoStore {
    private static var url: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("profile-photo.jpg")
    }

    static func load() -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage?) {
        guard let url else { return }
        if let data = image?.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .completeFileProtection)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Editable details of the saved trip flight (Figma "Edit flight details").
struct TripFlight: Codable, Equatable {
    var number: String
    var date: String
    var purpose: String

    static let sample = TripFlight(number: "NH 106", date: SampleJourney.outbound.date, purpose: "Business meetings")
    static let flights = [("NH 106", "HND → LAX"), ("NH 6", "NRT → LAX")]
    static let dates = ["2026-10-15", "2026-10-16", "2026-10-17"]
    static let purposes = ["Business meetings", "Tourism", "Transit"]

    var route: String { Self.flights.first { $0.0 == number }?.1 ?? "" }
}

/// A flight typed in by the traveller. Only what they entered is stored; no live status is shown.
struct ManualFlight: Codable, Hashable, Identifiable {
    var id = UUID()
    let number: String
    let date: String
}

enum TripDate {
    private static func parse(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: iso)
    }

    static func isValid(_ iso: String) -> Bool { parse(iso) != nil }

    /// "15 Oct", "15 Oct 2026", "15 October 2026", "15 OCT".
    static func format(_ iso: String, _ pattern: String) -> String {
        guard let date = parse(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
