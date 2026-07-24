import Foundation

struct TransitRoutePlanner: Sendable {
    func ranked(_ options: [TransitOption], requireAccessibility: Bool, preferLowWalking: Bool) -> [TransitOption] {
        options
            .filter { !requireAccessibility || $0.wheelchairAccessible == true }
            .sorted { lhs, rhs in
                let left = score(lhs, preferLowWalking: preferLowWalking)
                let right = score(rhs, preferLowWalking: preferLowWalking)
                return left == right ? lhs.id < rhs.id : left < right
            }
    }

    private func score(_ option: TransitOption, preferLowWalking: Bool) -> Int {
        option.durationMinutes + option.transfers * 12 + (preferLowWalking ? option.walkingMeters / 10 : option.walkingMeters / 40) + (option.disruption == nil ? 0 : 8)
    }
}

