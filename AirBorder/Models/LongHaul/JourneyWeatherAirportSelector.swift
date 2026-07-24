import Foundation

enum JourneyWeatherAirportSelector {
    static func destination(activeAirport: Airport?, onwardLeg: ItineraryLeg?) -> Airport? {
        guard let destination = onwardLeg?.flight.destination,
              destination.iata.uppercased() != activeAirport?.iata.uppercased() else {
            return nil
        }
        return destination
    }
}
