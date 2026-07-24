import Foundation

enum FlightAPIError: Error, Equatable, Sendable {
    case notConfigured
    case invalidRequest
    case authenticationFailed
    case rateLimited(retryAfter: TimeInterval?)
    case notFound
    case offline
    case server(statusCode: Int)
    case invalidResponse
    case responseTooLarge
    case decoding
    case unavailable
}

extension FlightAPIError: LocalizedError {
    var errorDescription: String? {
        return switch self {
        case .notConfigured: "Live flight provider is not configured."
        case .invalidRequest: "Check the flight number and travel date."
        case .authenticationFailed: "The live flight service could not authenticate."
        case .rateLimited: "The live flight service is temporarily rate limited."
        case .notFound: "No matching flight was found."
        case .offline: "The network is unavailable."
        case .server: "The live flight service returned an error."
        case .invalidResponse, .decoding: "The live flight response could not be read."
        case .responseTooLarge: "The live flight response exceeded the safe size limit."
        case .unavailable: "Live flight information is temporarily unavailable."
        }
    }
}
