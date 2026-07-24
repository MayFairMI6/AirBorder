import Foundation

struct FlightStatusRefreshService: Sendable {
    func recommendedInterval(for flight: Flight, now: Date, consecutiveFailures: Int = 0, retryAfter: TimeInterval? = nil) -> TimeInterval {
        if let retryAfter { return min(max(retryAfter, 60), 6 * 3600) }

        let base: TimeInterval
        if [.arrived, .cancelled, .diverted].contains(flight.status) {
            base = 3600
        } else if flight.status == .boarding || flight.status == .boardingSoon {
            base = 60
        } else if let departure = flight.effectiveDeparture {
            let remaining = departure.timeIntervalSince(now)
            if remaining > 24 * 3600 { base = 6 * 3600 }
            else if remaining > 3 * 3600 { base = 30 * 60 }
            else { base = 5 * 60 }
        } else {
            base = 30 * 60
        }

        let multiplier = pow(2.0, Double(min(max(consecutiveFailures, 0), 6)))
        return min(base * multiplier, 6 * 3600)
    }

    func isStale(lastUpdated: Date, flight: Flight, now: Date) -> Bool {
        now.timeIntervalSince(lastUpdated) > recommendedInterval(for: flight, now: now) * 2
    }
}

