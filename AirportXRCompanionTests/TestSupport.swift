import Foundation
import XCTest
@testable import AirBorder

enum StubBehavior: Sendable {
    case flights([Flight])
    case failure(FlightAPIError)
}

struct StubFlightProvider: FlightDataProvider {
    let providerID: String
    let providerName: String
    let behavior: StubBehavior

    init(id: String = "stub", name: String = "Stub", behavior: StubBehavior) {
        providerID = id
        providerName = name
        self.behavior = behavior
    }

    func searchFlights(query: FlightQuery) async throws -> [Flight] { try resolve() }
    func airportBoard(airportCode: String, date: Date, kind: AirportBoardKind) async throws -> [Flight] { try resolve() }
    func flightStatus(id: String) async throws -> Flight {
        guard let first = try resolve().first else { throw FlightAPIError.notFound }
        return first
    }

    private func resolve() throws -> [Flight] {
        switch behavior {
        case .flights(let flights): return flights
        case .failure(let error): throw error
        }
    }
}

actor InMemoryFlightCache: FlightCaching {
    var collections: [String: CachedFlightCollection] = [:]
    var journey: ActiveJourney?

    func flights(for key: String) async -> CachedFlightCollection? { collections[key] }
    func save(flights: [Flight], for key: String, at date: Date) async throws { collections[key] = CachedFlightCollection(flights: flights, storedAt: date) }
    func activeJourney() async -> ActiveJourney? { journey }
    func save(activeJourney: ActiveJourney?) async throws { journey = activeJourney }
    func clear() async throws { collections = [:]; journey = nil }
}

actor RecordingNotificationScheduler: NotificationScheduling {
    var scheduled: [JourneyNotificationPlan] = []
    func requestAuthorization() async throws -> Bool { true }
    func schedule(_ plans: [JourneyNotificationPlan]) async throws { scheduled += plans }
    func cancelJourneyNotifications(journeyID: UUID) async {}
}

func makeFlight(
    now: Date = Date(timeIntervalSince1970: 1_721_000_000),
    gate: String = "C12",
    previousGate: String? = nil,
    status: FlightStatus = .scheduled,
    live: Bool = true,
    actualDeparture: Date? = nil,
    delayMinutes: Int? = 0,
    id: String = "flight-1"
) -> Flight {
    let scheduled = now.addingTimeInterval(3600)
    return Flight(
        id: id,
        flightNumber: "AX 204",
        airlineCode: "AX",
        airlineName: "Aurora Air",
        origin: Airport(iata: "SFO", icao: "KSFO", name: "San Francisco International", city: "San Francisco", timeZone: "America/Los_Angeles"),
        destination: Airport(iata: "JFK", icao: "KJFK", name: "John F. Kennedy International", city: "New York", timeZone: "America/New_York"),
        status: status,
        scheduledDeparture: scheduled,
        estimatedDeparture: scheduled.addingTimeInterval(TimeInterval((delayMinutes ?? 0) * 60)),
        actualDeparture: actualDeparture,
        scheduledArrival: scheduled.addingTimeInterval(5 * 3600),
        estimatedArrival: scheduled.addingTimeInterval(5 * 3600),
        actualArrival: nil,
        departureTerminal: "2",
        arrivalTerminal: "5",
        gate: gate,
        arrivalGate: nil,
        previousGate: previousGate,
        boardingStatus: nil,
        boardingGroup: "4",
        boardingTime: scheduled.addingTimeInterval(-30 * 60),
        delayMinutes: delayMinutes,
        aircraftType: "A321",
        baggageClaim: nil,
        source: ProviderMetadata(name: live ? "Test Live" : "Demo", providerRecordID: id, providerUpdatedAt: now, receivedAt: now, isLive: live, isDemo: !live)
    )
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("AirportXRTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
