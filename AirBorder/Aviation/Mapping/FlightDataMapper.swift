import Foundation

struct ProxySourceDTO: Decodable {
    let name: String?
    let isLive: Bool?
    let receivedAt: String?
    let providerPolicy: String?
    let providerPolicyVersion: String?
    let trainingAllowed: Bool?
    let trainingPurposes: [ProviderTrainingPurpose]?

    init(
        name: String?,
        isLive: Bool?,
        receivedAt: String?,
        providerPolicy: String? = nil,
        providerPolicyVersion: String? = nil,
        trainingAllowed: Bool? = nil,
        trainingPurposes: [ProviderTrainingPurpose]? = nil
    ) {
        self.name = name
        self.isLive = isLive
        self.receivedAt = receivedAt
        self.providerPolicy = providerPolicy
        self.providerPolicyVersion = providerPolicyVersion
        self.trainingAllowed = trainingAllowed
        self.trainingPurposes = trainingPurposes
    }
}

struct ProxyFlightEnvelope: Decodable {
    let flights: [ProxyFlightDTO]
    let source: ProxySourceDTO?
}

struct ProxySingleFlightEnvelope: Decodable {
    let flight: ProxyFlightDTO
    let source: ProxySourceDTO?
}

struct ProxyFlightDTO: Decodable {
    struct AirportDTO: Decodable {
        let iata: String?
        let icao: String?
        let name: String?
        let city: String?
        let timeZone: String?
    }

    let id: String?
    let flightNumber: String?
    let airlineCode: String?
    let airlineName: String?
    let origin: AirportDTO?
    let destination: AirportDTO?
    let status: String?
    let scheduledDeparture: String?
    let estimatedDeparture: String?
    let actualDeparture: String?
    let scheduledArrival: String?
    let estimatedArrival: String?
    let actualArrival: String?
    let departureTerminal: String?
    let arrivalTerminal: String?
    let gate: String?
    let arrivalGate: String?
    let previousGate: String?
    let boardingStatus: String?
    let boardingGroup: String?
    let boardingTime: String?
    let delayMinutes: Int?
    let aircraftType: String?
    let baggageClaim: String?
    let providerUpdatedAt: String?
    let providerRecordID: String?
}

struct FlightDataMapper {
    private let iso8601 = ISO8601DateFormatter()
    private let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func map(_ dto: ProxyFlightDTO, source: ProxySourceDTO?, defaultProviderName: String) throws -> Flight {
        guard let id = nonempty(dto.id),
              let flightNumber = nonempty(dto.flightNumber),
              let originDTO = dto.origin,
              let destinationDTO = dto.destination else {
            throw FlightAPIError.decoding
        }

        let receivedAt = parseDate(source?.receivedAt) ?? Date()
        let metadata = ProviderMetadata(
            name: nonempty(source?.name) ?? defaultProviderName,
            providerRecordID: nonempty(dto.providerRecordID),
            providerUpdatedAt: parseDate(dto.providerUpdatedAt),
            receivedAt: receivedAt,
            isLive: source?.isLive ?? true,
            isDemo: false,
            providerPolicyID: nonempty(source?.providerPolicy),
            providerPolicyVersion: nonempty(source?.providerPolicyVersion),
            providerTrainingAllowed: source?.trainingAllowed,
            providerTrainingPurposes: Set(source?.trainingPurposes ?? [])
        )

        return Flight(
            id: id,
            flightNumber: flightNumber,
            airlineCode: nonempty(dto.airlineCode),
            airlineName: nonempty(dto.airlineName),
            origin: mapAirport(originDTO),
            destination: mapAirport(destinationDTO),
            status: mapStatus(dto.status),
            scheduledDeparture: parseDate(dto.scheduledDeparture),
            estimatedDeparture: parseDate(dto.estimatedDeparture),
            actualDeparture: parseDate(dto.actualDeparture),
            scheduledArrival: parseDate(dto.scheduledArrival),
            estimatedArrival: parseDate(dto.estimatedArrival),
            actualArrival: parseDate(dto.actualArrival),
            departureTerminal: nonempty(dto.departureTerminal),
            arrivalTerminal: nonempty(dto.arrivalTerminal),
            gate: nonempty(dto.gate),
            arrivalGate: nonempty(dto.arrivalGate),
            previousGate: nonempty(dto.previousGate),
            boardingStatus: nonempty(dto.boardingStatus),
            boardingGroup: nonempty(dto.boardingGroup),
            boardingTime: parseDate(dto.boardingTime),
            delayMinutes: dto.delayMinutes,
            aircraftType: nonempty(dto.aircraftType),
            baggageClaim: nonempty(dto.baggageClaim),
            source: metadata
        )
    }

    private func mapAirport(_ dto: ProxyFlightDTO.AirportDTO) -> Airport {
        Airport(
            iata: nonempty(dto.iata)?.uppercased() ?? "---",
            icao: nonempty(dto.icao)?.uppercased(),
            name: nonempty(dto.name) ?? "Unknown airport",
            city: nonempty(dto.city),
            timeZone: nonempty(dto.timeZone)
        )
    }

    private func mapStatus(_ rawValue: String?) -> FlightStatus {
        guard let normalized = rawValue?.replacingOccurrences(of: "_", with: "").lowercased() else { return .unknown }
        switch normalized {
        case "scheduled": return .scheduled
        case "ontime": return .onTime
        case "delayed": return .delayed
        case "boardingsoon": return .boardingSoon
        case "boarding": return .boarding
        case "departed": return .departed
        case "enroute", "airborne": return .enRoute
        case "arrived": return .arrived
        case "cancelled", "canceled": return .cancelled
        case "diverted": return .diverted
        default: return .unknown
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value = nonempty(value) else { return nil }
        return fractionalISO8601.date(from: value) ?? iso8601.date(from: value)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
