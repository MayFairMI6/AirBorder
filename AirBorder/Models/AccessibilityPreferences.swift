import Foundation

struct AccessibilityPreferences: Codable, Equatable, Sendable {
    var wheelchairRouting = true
    var avoidStairs = true
    var preferElevators = true
    var avoidEscalators = false
    var reduceWalking = false
    var simplifiedDirections = false
    var largerARIndicators = true
    var spokenNavigation = false
    var hapticTurns = true
    var highContrast = false
    var extraBoardingBufferMinutes = 5

    static let `default` = AccessibilityPreferences()
}

