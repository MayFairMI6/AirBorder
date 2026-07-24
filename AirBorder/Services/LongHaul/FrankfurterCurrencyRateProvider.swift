import Foundation

/// Keyless daily reference rates. The response includes the rate date so the
/// passenger UI never labels an old fixing as a real-time card-network quote.
struct FrankfurterCurrencyRateProvider: CurrencyRateProvider, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func latestRate(from baseCurrencyCode: String, to quoteCurrencyCode: String) async throws -> CurrencyRateQuote {
        let base = baseCurrencyCode.uppercased()
        let quote = quoteCurrencyCode.uppercased()
        guard base != quote else {
            return CurrencyRateQuote(baseCurrencyCode: base, quoteCurrencyCode: quote, rate: 1, rateDate: Date(), receivedAt: Date(), provider: "Identity conversion")
        }
        var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates")!
        components.queryItems = [
            URLQueryItem(name: "base", value: base),
            URLQueryItem(name: "quotes", value: quote)
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard data.count <= 64_000,
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { throw FlightAPIError.unavailable }
        let records = try JSONDecoder().decode([FrankfurterRecord].self, from: data)
        guard let record = records.first(where: { $0.base.uppercased() == base && $0.quote.uppercased() == quote }),
              let rate = Decimal(string: String(record.rate), locale: Locale(identifier: "en_US_POSIX")) else {
            throw FlightAPIError.invalidResponse
        }
        let date = try Self.dateFormatter.date(from: record.date).unwrap(or: FlightAPIError.invalidResponse)
        return CurrencyRateQuote(baseCurrencyCode: base, quoteCurrencyCode: quote, rate: rate, rateDate: date, receivedAt: Date(), provider: "Frankfurter")
    }

    private struct FrankfurterRecord: Decodable {
        let date: String
        let base: String
        let quote: String
        let rate: Double
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let self else { throw error() }
        return self
    }
}
