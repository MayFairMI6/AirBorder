import Foundation

private enum ProxyLayoverLimit {
    static let responseBytes = 1_000_000
}

private struct ProxySourceEnvelope: Decodable {
    let provider: String?
    let dataMode: String?
    let recordID: String?
    let observedAt: String?
    let receivedAt: String?
    let expiresAt: String?
    let evidenceKind: String?
    let providerChain: [String]?
}

struct ProxyEntryRequirementProvider: EntryRequirementProvider, @unchecked Sendable {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func assessment(for query: EntryRequirementQuery) async throws -> EntryAssessment {
        let url = baseURL.appendingPathComponent("v1/entry-requirements")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(query)
        let data = try await load(request)
        let payload = try JSONDecoder().decode(EntryEnvelope.self, from: data)
        let received = Self.date(payload.source?.receivedAt) ?? Date()
        let observed = Self.date(payload.source?.observedAt) ?? received
        let expiry = Self.date(payload.source?.expiresAt) ?? received
        let status = Self.entryStatus(payload.assessment?.status)
        let evidenceKind = Self.evidenceKind(
            payload.source?.evidenceKind,
            decisionAuthority: payload.assessment?.decisionAuthority
        )
        let officialURLs = (payload.assessment?.officialVerificationLinks ?? [])
            .compactMap { Self.safeHTTPSURL($0.url) }
        return EntryAssessment(
            status: status,
            summary: payload.assessment?.reason ?? "The proxy could not determine an entry requirement.",
            provider: payload.source?.provider ?? payload.provider ?? "Secure proxy",
            providerChain: payload.source?.providerChain ?? [],
            evidenceKind: evidenceKind,
            sourceRecordID: payload.source?.recordID
                ?? "entry-\(query.nationalityCountryCode)-\(query.transitCountryCode)-\(Self.day(query.arrival))",
            observedAt: observed,
            receivedAt: received,
            expiresAt: expiry,
            officialVerificationURLs: officialURLs,
            isDemo: payload.source?.dataMode == "testCached"
        )
    }

    private func load(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard data.count <= ProxyLayoverLimit.responseBytes,
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { throw FlightAPIError.invalidResponse }
        return data
    }

    private static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return date.formatted(.iso8601.year().month().day().timeZone(separator: .omitted))
    }

    private static func date(_ value: String?) -> Date? {
        value.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    private static func entryStatus(_ value: String?) -> EntryAssessmentStatus {
        switch value {
        case "authorizationNotIndicated": .authorizationNotIndicated
        case "authorizationRequired": .authorizationRequired
        case "conditional": .conditional
        default: .cannotDetermine
        }
    }

    private static func evidenceKind(_ value: String?, decisionAuthority: String?) -> EntryEvidenceKind {
        if value == "structuredProvider", decisionAuthority == "structuredGuidance" {
            return .structuredProvider
        }
        if value == "officialSourceDiscovery" || decisionAuthority == "discoveryOnly" {
            return .officialSourceDiscovery
        }
        return .informationalFallback
    }

    private static func safeHTTPSURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else { return nil }
        return url
    }

    private struct EntryEnvelope: Decodable {
        struct Assessment: Decodable {
            struct Link: Decodable { let url: String }
            let status: String?
            let reason: String?
            let decisionAuthority: String?
            let officialVerificationLinks: [Link]?
        }
        let assessment: Assessment?
        let source: ProxySourceEnvelope?
        let provider: String?
    }
}

struct FallbackEntryRequirementProvider: EntryRequirementProvider {
    let primary: any EntryRequirementProvider
    let fallback: any EntryRequirementProvider

    func assessment(for query: EntryRequirementQuery) async throws -> EntryAssessment {
        do { return try await primary.assessment(for: query) }
        catch { return try await fallback.assessment(for: query) }
    }
}

struct ProxyAirportFacilityProvider: AirportFacilityProvider, @unchecked Sendable {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func facilities(at airport: Airport, on date: Date) async throws -> [AirportFacilityRecord] {
        let url = baseURL
            .appendingPathComponent("v1/facilities/airports")
            .appendingPathComponent(airport.iata.uppercased())
        let (data, response) = try await session.data(from: url)
        guard data.count <= ProxyLayoverLimit.responseBytes,
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { throw FlightAPIError.unavailable }
        let payload = try JSONDecoder().decode(FacilityEnvelope.self, from: data)
        let received = ISO8601DateFormatter().date(from: payload.source?.receivedAt ?? "") ?? date
        return payload.facilities.map { record in
            let category = Self.category(record.category)
            let zone = Self.zone(record.accessZone)
            return AirportFacilityRecord(
                id: record.id,
                place: LayoverPlace(
                    id: record.id,
                    name: record.name,
                    airportCode: record.airportCode,
                    terminal: record.terminal,
                    category: category,
                    accessZone: zone,
                    latitude: nil,
                    longitude: nil,
                    summary: "Official/operator registry record. Recheck access, hours, and availability before use.",
                    bookingURL: category == .hotel || category == .transitHotel ? URL(string: record.officialRecordURL) : nil,
                    officialSourceURL: URL(string: record.officialRecordURL),
                    dataMode: .cached
                ),
                accessRestrictions: zone == .airside ? "Applicable airside access and boarding pass required." : nil,
                openingWindows: [],
                hoursRequireConfirmation: true,
                sourceUpdatedAt: nil,
                verifiedAt: received
            )
        }
    }

    private static func category(_ value: String) -> LayoverPlaceCategory {
        switch value {
        case "workPod": .workPod
        case "transitHotel": .transitHotel
        case "hotel": .hotel
        case "shower": .shower
        case "lounge": .lounge
        default: value.lowercased().contains("attraction") ? .attraction : .facility
        }
    }

    private static func zone(_ value: String) -> AccessZone {
        switch value {
        case "airside": .airside
        case "nearbyLandside": .nearby
        default: .airportLandside
        }
    }

    private struct FacilityEnvelope: Decodable {
        struct Record: Decodable {
            let id: String
            let airportCode: String
            let terminal: String?
            let name: String
            let category: String
            let accessZone: String
            let officialRecordURL: String
        }
        let facilities: [Record]
        let source: ProxySourceEnvelope?
    }
}

struct FallbackAirportFacilityProvider: AirportFacilityProvider {
    let primary: any AirportFacilityProvider
    let fallback: any AirportFacilityProvider

    func facilities(at airport: Airport, on date: Date) async throws -> [AirportFacilityRecord] {
        do {
            let records = try await primary.facilities(at: airport, on: date)
            return records.isEmpty ? try await fallback.facilities(at: airport, on: date) : records
        } catch {
            return try await fallback.facilities(at: airport, on: date)
        }
    }
}

struct ProxyAccommodationProvider: AccommodationProvider, @unchecked Sendable {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func offers(for context: PlaceSearchContext, checkIn: Date, checkOut: Date) async throws -> [AccommodationOffer] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/hotels/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(context.centerLatitude)),
            URLQueryItem(name: "longitude", value: String(context.centerLongitude)),
            URLQueryItem(name: "radiusKm", value: String(context.radiusMeters / 1_000)),
            URLQueryItem(name: "checkInDate", value: Self.day(checkIn)),
            URLQueryItem(name: "checkOutDate", value: Self.day(checkOut))
        ]
        guard let url = components.url else { throw FlightAPIError.invalidRequest }
        let (data, response) = try await session.data(from: url)
        guard data.count <= ProxyLayoverLimit.responseBytes,
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { throw FlightAPIError.unavailable }
        let payload = try JSONDecoder().decode(HotelEnvelope.self, from: data)
        let observed = ISO8601DateFormatter().date(from: payload.source.receivedAt ?? "") ?? Date()
        let expiry = ISO8601DateFormatter().date(from: payload.source.expiresAt ?? "") ?? observed
        return payload.hotels.compactMap { hotel in
            let offer = hotel.offers?.first
            return AccommodationOffer(
                id: hotel.id,
                place: LayoverPlace(
                    id: hotel.id,
                    name: hotel.name,
                    airportCode: context.airport.iata,
                    terminal: nil,
                    category: .hotel,
                    accessZone: .nearby,
                    latitude: hotel.coordinates?.latitude,
                    longitude: hotel.coordinates?.longitude,
                    summary: "Amadeus hotel result. Availability and price expire quickly; day use is not verified.",
                    bookingURL: nil,
                    officialSourceURL: nil,
                    dataMode: payload.source.dataMode == "live" ? .live : .demo
                ),
                totalPrice: offer?.total.flatMap { Decimal(string: $0) },
                currencyCode: offer?.currency,
                checkIn: checkIn,
                checkOut: checkOut,
                observedAt: observed,
                expiresAt: expiry,
                externalBookingURL: nil
            )
        }
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private struct HotelEnvelope: Decodable {
        struct Hotel: Decodable {
            struct Coordinates: Decodable { let latitude: Double?; let longitude: Double? }
            struct Offer: Decodable { let currency: String?; let total: String? }
            let id: String
            let name: String
            let coordinates: Coordinates?
            let offers: [Offer]?
        }
        let hotels: [Hotel]
        let source: ProxySourceEnvelope
    }
}
