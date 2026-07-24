import XCTest

final class FlightBookAndBagsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testExampleBKKHNDLAXShowsThroughCheckedFactAndExternalOfferPreview() {
        launchDemo()
        selectFlightsAndBookBags()

        let state = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Through-checked'")
        ).firstMatch
        scrollToElement(state)
        XCTAssertTrue(state.exists)
        XCTAssertTrue(state.label.localizedCaseInsensitiveContains("Through-checked"))
        let bagDestination = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'LAX'")
        ).firstMatch
        scrollToElement(bagDestination)
        XCTAssertTrue(bagDestination.exists)
        let demoNotice = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Trip details'")
        ).firstMatch
        scrollToElement(demoNotice)
        XCTAssertTrue(demoNotice.exists)

        let search = app.buttons["Compare fares"]
        scrollToElement(search)
        XCTAssertTrue(search.isHittable)
        search.tap()

        let offerNotice = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Example fare'")
        ).firstMatch
        XCTAssertTrue(offerNotice.waitForExistence(timeout: 5))
        let handoff = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Open Google Flights'")
        ).firstMatch
        scrollToElement(handoff)
        XCTAssertTrue(handoff.exists)
    }

    func testExampleHNDNRTShowsReclaimSequenceInterAirportStepAndBagDropCutoff() {
        launchDemo(scenario: "interAirport")
        selectFlightsAndBookBags()

        let state = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Reclaim' AND label CONTAINS[c] 'recheck'")
        ).firstMatch
        scrollToElement(state)
        XCTAssertTrue(state.exists)
        XCTAssertTrue(state.label.localizedCaseInsensitiveContains("Reclaim"))

        let interAirport = app.staticTexts["Inter-airport travel"]
        scrollToElement(interAirport)
        XCTAssertTrue(interAirport.exists)
        XCTAssertTrue(app.staticTexts["Baggage reclaim wait"].exists)
        XCTAssertTrue(app.staticTexts["Immigration / border processing"].exists)
        XCTAssertTrue(app.staticTexts["Customs processing"].exists)
        XCTAssertTrue(app.staticTexts["Bag drop and check-in"].exists)
        XCTAssertTrue(app.staticTexts["Security screening"].exists)
        XCTAssertTrue(app.staticTexts["Bag-drop/check-in cutoff"].exists)
    }

    private func launchDemo(scenario: String? = nil) {
        app.launchArguments = ["--uitesting", "--launch-mode", "demo"]
        if let scenario { app.launchArguments += ["--scenario", scenario] }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
    }

    private func selectFlightsAndBookBags() {
        let flights = app.tabBars.buttons["Flights"]
        if flights.waitForExistence(timeout: 1) {
            flights.tap()
        } else {
            app.tabBars.buttons["More"].tap()
            let item = app.tables.staticTexts["Flights"]
            XCTAssertTrue(item.waitForExistence(timeout: 3))
            item.tap()
        }
        XCTAssertTrue(element("itineraryEditor").waitForExistence(timeout: 5))
        let mode = app.segmentedControls.buttons["Book & bags"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.tap()
        XCTAssertTrue(element("bookAndBagsPanel").waitForExistence(timeout: 5))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func scrollToElement(_ element: XCUIElement, attempts: Int = 10) {
        for _ in 0..<attempts where !element.exists || !element.isHittable {
            app.swipeUp()
        }
    }
}
