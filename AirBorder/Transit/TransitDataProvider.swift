import Foundation

protocol TransitDataProvider: Sendable {
    var providerName: String { get }
    func options(from airportCode: String, to destination: String, at date: Date) async throws -> [TransitOption]
}

struct BundledTransitDataProvider: TransitDataProvider {
    let providerName = "Bundled GTFS sample"
    var now: @Sendable () -> Date = { Date() }

    func options(from airportCode: String, to destination: String, at date: Date) async throws -> [TransitOption] {
        let departure = max(date, now()).addingTimeInterval(8 * 60)
        return [
            TransitOption(
                id: "sample-rail",
                title: "AirTrain + Regional Rail",
                mode: .airportRail,
                destination: destination,
                departureTime: departure,
                arrivalTime: departure.addingTimeInterval(48 * 60),
                durationMinutes: 48,
                cost: Decimal(string: "18.40"),
                currencyCode: "USD",
                transfers: 1,
                walkingMeters: 240,
                wheelchairAccessible: true,
                luggageSuitability: "Good for luggage",
                disruption: nil,
                firstService: Calendar.current.startOfDay(for: departure).addingTimeInterval(5 * 3600),
                lastService: Calendar.current.startOfDay(for: departure).addingTimeInterval(25 * 3600),
                source: providerName,
                isLive: false
            ),
            TransitOption(
                id: "sample-express-bus",
                title: "Airport Express Bus",
                mode: .expressBus,
                destination: destination,
                departureTime: departure.addingTimeInterval(7 * 60),
                arrivalTime: departure.addingTimeInterval(67 * 60),
                durationMinutes: 60,
                cost: Decimal(string: "16.00"),
                currencyCode: "USD",
                transfers: 0,
                walkingMeters: 90,
                wheelchairAccessible: true,
                luggageSuitability: "Dedicated luggage racks",
                disruption: "Travel time varies with traffic",
                firstService: nil,
                lastService: nil,
                source: providerName,
                isLive: false
            ),
            TransitOption(
                id: "sample-taxi",
                title: "Taxi estimate",
                mode: .taxi,
                destination: destination,
                departureTime: date,
                arrivalTime: date.addingTimeInterval(55 * 60),
                durationMinutes: 55,
                cost: Decimal(string: "75.00"),
                currencyCode: "USD",
                transfers: 0,
                walkingMeters: 40,
                wheelchairAccessible: nil,
                luggageSuitability: "Confirm vehicle capacity",
                disruption: "Estimate only; traffic and fare may vary",
                firstService: nil,
                lastService: nil,
                source: providerName,
                isLive: false
            )
        ]
    }
}

