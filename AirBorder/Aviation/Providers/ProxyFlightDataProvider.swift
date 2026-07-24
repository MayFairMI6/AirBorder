import Foundation

final class ProxyFlightDataProvider: FlightDataProvider, @unchecked Sendable {
    let providerID = "secure-proxy"
    let providerName: String

    private let baseURL: URL
    private let session: URLSession
    private let mapper: FlightDataMapper
    private let maximumResponseBytes = 1_000_000

    init(baseURL: URL, providerName: String, session: URLSession = .shared, mapper: FlightDataMapper = FlightDataMapper()) {
        self.baseURL = baseURL
        self.providerName = providerName
        self.session = session
        self.mapper = mapper
    }

    func searchFlights(query: FlightQuery) async throws -> [Flight] {
        var components = URLComponents(url: endpoint("v1/flights/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "flightNumber", value: query.normalizedIdentifier),
            URLQueryItem(name: "date", value: Self.dayFormatter.string(from: query.date))
        ]
        guard let url = components?.url else { throw FlightAPIError.invalidRequest }
        let envelope: ProxyFlightEnvelope = try await request(url)
        return try envelope.flights.map { try mapper.map($0, source: envelope.source, defaultProviderName: providerName) }
    }

    func airportBoard(airportCode: String, date: Date, kind: AirportBoardKind) async throws -> [Flight] {
        let code = airportCode.uppercased().filter { $0.isLetter || $0.isNumber }
        guard (3...4).contains(code.count) else { throw FlightAPIError.invalidRequest }
        var components = URLComponents(url: endpoint("v1/airports/\(code)/\(kind.rawValue)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "date", value: Self.dayFormatter.string(from: date))]
        guard let url = components?.url else { throw FlightAPIError.invalidRequest }
        let envelope: ProxyFlightEnvelope = try await request(url)
        return try envelope.flights.map { try mapper.map($0, source: envelope.source, defaultProviderName: providerName) }
    }

    func flightStatus(id: String) async throws -> Flight {
        let safeID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard !safeID.isEmpty else { throw FlightAPIError.invalidRequest }
        let envelope: ProxySingleFlightEnvelope = try await request(endpoint("v1/flights/\(safeID)"))
        return try mapper.map(envelope.flight, source: envelope.source, defaultProviderName: providerName)
    }

    private func endpoint(_ path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
    }

    private func request<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw FlightAPIError.invalidResponse }
            guard data.count <= maximumResponseBytes else { throw FlightAPIError.responseTooLarge }
            switch http.statusCode {
            case 200..<300:
                guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("application/json") == true else {
                    throw FlightAPIError.invalidResponse
                }
            case 400: throw FlightAPIError.invalidRequest
            case 401, 403: throw FlightAPIError.authenticationFailed
            case 404: throw FlightAPIError.notFound
            case 429:
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw FlightAPIError.rateLimited(retryAfter: retry)
            default: throw FlightAPIError.server(statusCode: http.statusCode)
            }

            do { return try JSONDecoder().decode(Response.self, from: data) }
            catch { throw FlightAPIError.decoding }
        } catch let error as FlightAPIError {
            throw error
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost].contains(error.code) {
            throw FlightAPIError.offline
        } catch {
            throw FlightAPIError.unavailable
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

