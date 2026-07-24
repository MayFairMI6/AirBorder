import Foundation

enum CountryNameResolver {
    private static let englishLocale = Locale(identifier: "en_US")
    private static let aliases: [String: String] = [
        "USA": "US",
        "UNITED STATES OF AMERICA": "US",
        "UK": "GB",
        "UNITED KINGDOM": "GB",
        "UAE": "AE",
        "SOUTH KOREA": "KR",
        "NORTH KOREA": "KP",
        "RUSSIA": "RU",
        "VIETNAM": "VN",
        "CZECHIA": "CZ",
        "BOLIVIA": "BO",
        "TANZANIA": "TZ"
    ]

    static func countryCode(for input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercased = value.uppercased()
        if Locale.isoRegionCodes.contains(uppercased) { return uppercased }
        if let alias = aliases[uppercased] { return alias }
        return Locale.isoRegionCodes.first {
            englishLocale.localizedString(forRegionCode: $0)?
                .caseInsensitiveCompare(value) == .orderedSame
        }
    }

    static func displayName(for countryCode: String) -> String {
        englishLocale.localizedString(forRegionCode: countryCode.uppercased()) ?? countryCode.uppercased()
    }
}
