import XCTest
@testable import AirBorder

final class AffordabilityTests: XCTestCase {
    func testHanedaPreviewCatalogCoversFreeTransportFoodAndShoppingInLocalCurrency() {
        let options = AirportAffordabilityCatalog.options(for: "HND")

        XCTAssertEqual(AirportAffordabilityCatalog.currencyCode(for: "HND"), "JPY")
        XCTAssertTrue(options.contains { $0.category == .free && $0.isFree })
        XCTAssertTrue(options.contains { $0.category == .transport && $0.hasKnownRange })
        XCTAssertTrue(options.contains { $0.category == .food && $0.hasKnownRange })
        XCTAssertTrue(options.contains { $0.category == .shopping && $0.hasKnownRange })
        XCTAssertTrue(options.allSatisfy { $0.currencyCode == "JPY" && $0.dataMode == .demo })
    }

    func testUnknownAirportDoesNotInventCurrencyOrCosts() {
        XCTAssertNil(AirportAffordabilityCatalog.currencyCode(for: "ZZZ"))
        XCTAssertTrue(AirportAffordabilityCatalog.options(for: "ZZZ").isEmpty)
    }

    func testCurrencyQuoteKeepsProviderAndRateDateSeparateFromReceiptTime() {
        let rateDate = Date(timeIntervalSince1970: 1_700_000_000)
        let receivedAt = rateDate.addingTimeInterval(86_400)
        let quote = CurrencyRateQuote(
            baseCurrencyCode: "JPY",
            quoteCurrencyCode: "USD",
            rate: Decimal(string: "0.0067")!,
            rateDate: rateDate,
            receivedAt: receivedAt,
            provider: "Frankfurter"
        )

        XCTAssertEqual(quote.baseCurrencyCode, "JPY")
        XCTAssertEqual(quote.quoteCurrencyCode, "USD")
        XCTAssertNotEqual(quote.rateDate, quote.receivedAt)
    }
}
