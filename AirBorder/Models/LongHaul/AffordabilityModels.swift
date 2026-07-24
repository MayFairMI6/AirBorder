import Foundation

enum AffordabilityCategory: String, CaseIterable, Identifiable, Sendable {
    case free
    case transport
    case activity
    case food
    case shopping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Free"
        case .transport: "Getting around"
        case .activity: "Activities"
        case .food: "Food & drink"
        case .shopping: "Shops"
        }
    }

    var symbol: String {
        switch self {
        case .free: "gift"
        case .transport: "tram.fill"
        case .activity: "ticket"
        case .food: "fork.knife"
        case .shopping: "bag"
        }
    }
}

/// A price band is intentionally separate from itinerary safety calculations.
/// It can inform a traveller's choice, but never authorize a landside plan.
struct AffordabilityOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let category: AffordabilityCategory
    let minimumLocalAmount: Decimal?
    let maximumLocalAmount: Decimal?
    let currencyCode: String
    let sourceLabel: String
    let dataMode: DataFreshness

    var isFree: Bool { minimumLocalAmount == 0 && maximumLocalAmount == 0 }
    var hasKnownRange: Bool { minimumLocalAmount != nil && maximumLocalAmount != nil }
}

struct CurrencyRateQuote: Hashable, Sendable {
    let baseCurrencyCode: String
    let quoteCurrencyCode: String
    /// One unit of base currency in quote currency.
    let rate: Decimal
    let rateDate: Date
    let receivedAt: Date
    let provider: String
}

protocol CurrencyRateProvider: Sendable {
    func latestRate(from baseCurrencyCode: String, to quoteCurrencyCode: String) async throws -> CurrencyRateQuote
}

enum AirportAffordabilityCatalog {
    static func currencyCode(for airportCode: String) -> String? {
        switch airportCode.uppercased() {
        case "HND", "NRT", "KIX": "JPY"
        case "BKK", "DMK": "THB"
        case "LAX", "SFO", "JFK": "USD"
        default: nil
        }
    }

    /// Named preview fixtures. These are never presented as a live quote; live
    /// provider/venue price adapters can replace individual rows later.
    static func options(for airportCode: String) -> [AffordabilityOption] {
        guard airportCode.uppercased() == "HND" else { return [] }
        let currency = "JPY"
        let preview = DataFreshness.demo
        return [
            option("hnd-free-observation", "Observation Deck", "Airport attraction with no listed admission charge.", .free, 0, 0, currency, "HND preview fixture", preview),
            option("hnd-free-terminal-walk", "Terminal walk and gate-area rest", "A no-purchase option that stays inside the airport.", .free, 0, 0, currency, "HND preview fixture", preview),
            option("hnd-rail-local", "Local rail or monorail", "Typical local transport band; verify fare, route, and service before leaving.", .transport, 150, 600, currency, "HND preview fixture", preview),
            option("hnd-taxi-local", "Taxi to a nearby area", "Indicative fare band before tolls, traffic, or late-night supplements.", .transport, 2_500, 8_000, currency, "HND preview fixture", preview),
            option("hnd-airport-garden", "Airport Garden visit", "Browse gardens and public areas; purchases are optional.", .activity, 0, 0, currency, "HND preview fixture", preview),
            option("hnd-snack", "Snack or drink", "Typical airport concession price band.", .food, 250, 900, currency, "HND preview fixture", preview),
            option("hnd-casual-meal", "Casual restaurant meal", "Typical airport dining band; individual menus vary.", .food, 1_000, 3_000, currency, "HND preview fixture", preview),
            option("hnd-essential-shop", "Travel essentials or clothing", "Typical small essential or apparel purchase band.", .shopping, 700, 8_000, currency, "HND preview fixture", preview),
            option("hnd-electronics", "Electronic accessory", "Typical cable, adapter, or small accessory band.", .shopping, 1_000, 6_000, currency, "HND preview fixture", preview)
        ]
    }

    private static func option(
        _ id: String,
        _ title: String,
        _ detail: String,
        _ category: AffordabilityCategory,
        _ minimum: Decimal,
        _ maximum: Decimal,
        _ currency: String,
        _ source: String,
        _ dataMode: DataFreshness
    ) -> AffordabilityOption {
        AffordabilityOption(
            id: id,
            title: title,
            detail: detail,
            category: category,
            minimumLocalAmount: minimum,
            maximumLocalAmount: maximum,
            currencyCode: currency,
            sourceLabel: source,
            dataMode: dataMode
        )
    }
}

enum TravelerCurrencyResolver {
    static func displayCurrency(for profile: TravelerProfile, fallback: String) -> String {
        currency(for: profile.residenceCountryCode)
            ?? currency(for: profile.nationalityCountryCode)
            ?? fallback
    }

    private static func currency(for countryCode: String) -> String? {
        switch countryCode.uppercased() {
        case "US": "USD"
        case "GB": "GBP"
        case "JP": "JPY"
        case "CA": "CAD"
        case "AU": "AUD"
        case "NZ": "NZD"
        case "CH": "CHF"
        case "CN": "CNY"
        case "HK": "HKD"
        case "IN": "INR"
        case "KR": "KRW"
        case "SG": "SGD"
        case "TH": "THB"
        case "AE": "AED"
        case "SA": "SAR"
        case "BR": "BRL"
        case "MX": "MXN"
        case "ZA": "ZAR"
        case "SE": "SEK"
        case "NO": "NOK"
        case "DK": "DKK"
        case "PL": "PLN"
        case "TR": "TRY"
        case "ID": "IDR"
        case "MY": "MYR"
        case "PH": "PHP"
        case "VN": "VND"
        case "DE", "FR", "ES", "IT", "NL", "BE", "PT", "IE", "AT", "FI", "GR": "EUR"
        default: nil
        }
    }
}
