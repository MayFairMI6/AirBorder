@preconcurrency import CoreLocation
import Foundation
import UserNotifications

/// Location-triggered alerts are intentionally scoped to the place a traveller
/// chose for this journey. The monitor never turns a list of nearby venues into
/// unsolicited alerts.
@MainActor
final class BackgroundJourneyMonitor: NSObject, ObservableObject, @MainActor CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private let scheduler: any NotificationScheduling
    private var leaveBy: Date?
    private var gate: String?
    private var journeyID: UUID?
    private var airport: AirportReferencePoint?

    init(scheduler: any NotificationScheduling) {
        self.scheduler = scheduler
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = true
    }

    func enable() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestAlwaysAuthorization()
        } else if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    func configure(
        journeyID: UUID,
        airport: AirportReferencePoint?,
        gate: String?,
        leaveBy: Date?,
        selectedPlace: LayoverPlace?,
        includeSelectedPlace: Bool
    ) async {
        self.journeyID = journeyID
        self.airport = airport
        self.gate = gate
        self.leaveBy = leaveBy
        await scheduler.cancelJourneyNotifications(journeyID: journeyID)

        let plans = BackgroundJourneyAlertPlanner().plans(
            journeyID: journeyID,
            leaveBy: leaveBy,
            gate: gate,
            selectedPlace: includeSelectedPlace ? selectedPlace : nil,
            now: Date()
        )
        // The selected-place message is delivered by geofence when a coordinate
        // exists. Do not schedule it as an immediate duplicate.
        let timePlans = plans.filter { $0.id.hasSuffix(".leave-by") }
        try? await scheduler.schedule(timePlans)

        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        guard includeSelectedPlace,
              let place = selectedPlace,
              let coordinate = place.coordinate,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let region = CLCircularRegion(center: coordinate, radius: 180, identifier: "airportxr.selected-place.\(place.id)")
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.allowsBackgroundLocationUpdates = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("airportxr.selected-place.") else { return }
        Task { await notify(title: "Selected stop nearby", body: "Your chosen place is nearby. Check your leave-by time before stopping.", deepLink: "airportxr://journey") }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              let leaveBy,
              leaveBy <= Date().addingTimeInterval(10 * 60),
              let airport else { return }
        let airportLocation = CLLocation(latitude: airport.latitude, longitude: airport.longitude)
        guard location.distance(from: airportLocation) > 1_200 else { return }
        Task { await notify(title: "Time to return", body: "You are still away from \(gate.map { "Gate \($0)" } ?? "the airport"). Open directions now.", deepLink: "airportxr://guide") }
    }

    private func notify(title: String, body: String, deepLink: String) async {
        guard let journeyID else { return }
        let plan = JourneyNotificationPlan(
            id: "\(journeyID.uuidString).location-risk",
            kind: .leaveNow,
            title: title,
            body: body,
            fireDate: Date(),
            deepLink: deepLink
        )
        try? await scheduler.schedule([plan])
    }
}
