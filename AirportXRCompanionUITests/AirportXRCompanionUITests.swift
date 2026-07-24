import XCTest

final class AirportXRCompanionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testJourneyShowsNamedExampleItineraryAndCalculationTrace() {
        launch()

        XCTAssertTrue(element("longHaulJourneyDashboard").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Example itinerary"].exists)
        XCTAssertTrue(app.staticTexts["Bangkok to Los Angeles"].exists)
        XCTAssertTrue(app.staticTexts["Thai Airways"].exists)
        XCTAssertTrue(app.staticTexts["TG 660"].exists)
        XCTAssertTrue(app.staticTexts["BKK"].exists)
        XCTAssertTrue(app.staticTexts["HND"].exists)

        let why = app.buttons["Why this recommendation?"]
        scrollToElement(why)
        XCTAssertTrue(why.exists)
        why.tap()
        XCTAssertTrue(element("calculationTraceView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What we included"].exists)
    }

    func testSafestFirstActionOpensDerivedTerminalMap() {
        launch()

        let goToGate = app.buttons["goToGateButton"]
        XCTAssertTrue(goToGate.waitForExistence(timeout: 5))
        XCTAssertTrue(goToGate.label.localizedCaseInsensitiveContains("Go to Gate"))
        goToGate.tap()

        XCTAssertTrue(element("terminalMapView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routeModePicker"].exists)
        XCTAssertTrue(app.buttons["manualCalibrationMenu"].exists)
        XCTAssertTrue(element("findNearbyCard").exists)
        XCTAssertTrue(app.buttons["findNearby_restroom"].exists)
        XCTAssertTrue(app.textFields["Search for an item"].exists)
    }

    func testFlightSearchShowsPassengerFriendlyExampleResultAndDetail() {
        launch()
        selectTab("Flights")

        XCTAssertTrue(element("itineraryEditor").waitForExistence(timeout: 5))
        app.buttons["searchFlightButton"].tap()
        XCTAssertTrue(element("flightSearchResult").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Example flight updates'")
        ).firstMatch.exists)

        app.staticTexts["AX 204"].firstMatch.tap()
        XCTAssertTrue(element("flightDetailView").waitForExistence(timeout: 5))
        let exampleDetails = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Example flight details'")
        ).firstMatch
        scrollToElement(exampleDetails)
        XCTAssertTrue(exampleDetails.exists)
    }

    func testARGuidanceAndAccessibleMapAreAvailableForMappedGate() {
        launch()

        app.buttons["universalReturnToGateButton"].tap()
        XCTAssertTrue(element("arGuideView").waitForExistence(timeout: 8))

        app.buttons["arMapFallbackButton"].tap()
        XCTAssertTrue(element("terminalMapView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routeModePicker"].label.localizedCaseInsensitiveContains("accessible"))
    }

    func testReturnToGateStaysAvailableAcrossTabsAndOpensDirections() {
        launch()

        for tab in ["Journey", "Flights", "AR Guide", "Map"] {
            selectTab(tab)
            XCTAssertTrue(
                app.buttons["universalReturnToGateButton"].waitForExistence(timeout: 3),
                "Return to Gate should remain available on \(tab)"
            )
        }

        app.buttons["universalReturnToGateButton"].tap()
        XCTAssertTrue(element("arGuideView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["arMapFallbackButton"].exists)
    }

    func testARPreviewChangesGuidanceWithSimulatedPosition() {
        app.launchArguments = [
            "--uitesting", "--launch-mode", "demo", "--qa-simulated-walk"
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))

        app.buttons["universalReturnToGateButton"].tap()
        XCTAssertTrue(element("arGuideView").waitForExistence(timeout: 8))
        let maneuver = app.descendants(matching: .any)["arManeuverCard"].firstMatch
        XCTAssertTrue(maneuver.waitForExistence(timeout: 5))
        let startingInstruction = maneuver.label
        app.buttons["Next point"].tap()
        let changedManeuver = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'arManeuverCard' AND label != %@", startingInstruction)
        ).firstMatch
        XCTAssertTrue(changedManeuver.waitForExistence(timeout: 5))
    }

    func testTerminalWalkthroughCoversCoreFeaturesAndFillsTravelerDetails() {
        app.launchArguments = [
            "--uitesting", "--launch-mode", "demo", "--qa-walkthrough"
        ]
        app.launch()
        XCTAssertTrue(element("automatedWalkthroughBanner").waitForExistence(timeout: 8))
        app.buttons["walkthroughPauseButton"].tap()

        app.buttons["walkthroughNextButton"].tap()
        XCTAssertTrue(element("itineraryEditor").waitForExistence(timeout: 5))

        app.buttons["walkthroughNextButton"].tap()
        XCTAssertTrue(element("arGuideView").waitForExistence(timeout: 5))
        XCTAssertTrue(element("arManeuverCard").waitForExistence(timeout: 5))

        for _ in 0..<3 { app.buttons["walkthroughNextButton"].tap() }
        XCTAssertTrue(element("settingsView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["universalReturnToGateButton"].exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'United States'")
        ).firstMatch.exists)

        app.buttons["walkthroughNextButton"].tap()
        let accessibilityNeeds = app.textFields["Accessibility needs"]
        XCTAssertEqual(accessibilityNeeds.value as? String, "Prefer elevators and shorter walks")
    }

    func testLayoverLayersShowOfficialHanedaWorkPodAsLandsideOnly() {
        launch()

        let workPods = app.buttons["Landside work pods"]
        scrollToElement(workPods)
        XCTAssertTrue(workPods.exists)
        workPods.tap()

        XCTAssertTrue(element("layoverTransitView").waitForExistence(timeout: 5))
        scrollToElement(app.staticTexts["Terminal 3 Work Cubicles"])
        XCTAssertTrue(app.staticTexts["Terminal 3 Work Cubicles"].exists)
        let landsideLabel = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Airport Landside'")
        ).firstMatch
        scrollToElement(landsideLabel)
        XCTAssertTrue(landsideLabel.exists)
    }

    func testLayoverAffordabilityLayerShowsLocalCostsAndFreeOptions() {
        launch()

        let workPods = app.buttons["Landside work pods"]
        scrollToElement(workPods)
        XCTAssertTrue(workPods.exists)
        workPods.tap()

        XCTAssertTrue(element("layoverTransitView").waitForExistence(timeout: 5))
        let affordability = app.staticTexts["Plan your spend"]
        scrollToElement(affordability)
        XCTAssertTrue(affordability.exists)
        XCTAssertTrue(app.staticTexts["Free"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Local rail or monorail'")
        ).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Observation Deck"].exists)
    }

    func testInterAirportTransferLeadsWithPassengerFriendlyActionAndUnknownTarget() {
        launch(scenario: "interAirport")

        XCTAssertTrue(element("departureWeatherCard").waitForExistence(timeout: 5))
        XCTAssertTrue(element("transferWeatherCard").exists)
        XCTAssertTrue(element("destinationWeatherCard").exists)
        XCTAssertTrue(app.buttons["Refresh weather for HND"].exists)
        XCTAssertTrue(app.buttons["Refresh weather for NRT"].exists)
        XCTAssertTrue(app.buttons["Refresh weather for LAX"].exists)

        let journeyTransfer = app.buttons["goToGateButton"]
        XCTAssertTrue(journeyTransfer.waitForExistence(timeout: 5))
        XCTAssertTrue(journeyTransfer.label.contains("HND") && journeyTransfer.label.contains("NRT"))
        journeyTransfer.tap()

        XCTAssertTrue(element("layoverTransitView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Mandatory HND' AND label CONTAINS[c] 'NRT transfer'")
        ).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Recommended route'")
        ).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'recommended arrival time is not ready yet'")
        ).firstMatch.exists)

        let transferAction = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Start HND' AND label CONTAINS[c] 'NRT transfer'")
        ).firstMatch
        scrollToElement(transferAction)
        XCTAssertTrue(transferAction.exists)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Fastest'")).count,
            0,
            "An example transfer snapshot must never be presented as fastest"
        )
    }

    func testTravelerEntryCheckAndInFlightResearchScreensOpen() {
        launch()

        let entryCheck = app.buttons["Entry check"]
        scrollToElement(entryCheck)
        XCTAssertTrue(entryCheck.exists)
        entryCheck.tap()
        XCTAssertTrue(element("entryCheckView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Personalized entry check"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        let inFlight = app.buttons["In-flight progress"]
        scrollToElement(inFlight)
        XCTAssertTrue(inFlight.exists)
        inFlight.tap()
        XCTAssertTrue(element("inFlightProgressView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["In-flight view"].exists)
    }

    func testSettingsExposePrivacyLearningAndSecretBoundary() {
        launch()
        selectTab("Settings")

        XCTAssertTrue(element("settingsView").waitForExistence(timeout: 5))
        let appleCalendar = app.switches["appleCalendarReminderToggle"]
        scrollToElement(appleCalendar)
        XCTAssertTrue(appleCalendar.exists)
        XCTAssertFalse(appleCalendar.isEnabled, "Example itineraries must not create external calendar records")
        XCTAssertTrue(element("appleCalendarReminderStatus").exists)
        let googleTasks = element("googleTasksReminderStatus")
        scrollToElement(googleTasks)
        XCTAssertTrue(googleTasks.exists)

        let dataConnection = element("liveTravelUpdatesStatus")
        scrollToElement(dataConnection)
        XCTAssertTrue(dataConnection.exists)
        let learning = app.switches["Learn from resolved journey data"]
        scrollToElement(learning)
        XCTAssertTrue(learning.exists)
    }

    func testOfflineModeIsExplicitAndKeepsOperationalFactsStale() {
        launch()
        app.terminate()
        launch(mode: "offline")

        XCTAssertTrue(app.staticTexts["Saved trip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'out of date'")
        ).firstMatch.exists)
        XCTAssertTrue(element("longHaulJourneyDashboard").exists)
    }

    func testJourneyAccessibilityAtLargeTextAndReducedMotion() throws {
        app.launchArguments = [
            "--uitesting", "--launch-mode", "demo",
            "--qa-accessibility-xxxl"
        ]
        app.launchEnvironment["UIAccessibilityIsReduceMotionEnabled"] = "YES"
        app.launch()

        XCTAssertTrue(element("longHaulJourneyDashboard").waitForExistence(timeout: 8))
        let gateAction = app.buttons["goToGateButton"]
        scrollToElement(gateAction)
        XCTAssertTrue(gateAction.isHittable)
        // Audit at the scroll boundary where the derived tab-bar clearance keeps
        // passenger content out from under iOS 26's translucent system material.
        for _ in 0..<8 { app.swipeUp() }
        try app.performAccessibilityAudit(for: [
            .contrast,
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
            .trait
        ]) { issue in
            if issue.auditType == .contrast, issue.element == nil {
                XCTContext.runActivity(named: "Unassociated iOS simulator contrast diagnostic") { activity in
                    let evidence = "\(issue.compactDescription)\n\(issue.detailedDescription)\nThe audit supplied no XCUIElement; associated contrast issues remain test failures."
                    activity.add(XCTAttachment(string: evidence))
                }
                return true
            }
            return false
        }
    }

    func testJourneySupportsDynamicTypeAudit() throws {
        launch()
        XCTAssertTrue(element("longHaulJourneyDashboard").waitForExistence(timeout: 8))
        try app.performAccessibilityAudit(for: .dynamicType)
    }

    private func launch(mode: String = "demo", scenario: String? = nil) {
        app.launchArguments = ["--uitesting", "--launch-mode", mode]
        if let scenario { app.launchArguments += ["--scenario", scenario] }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
    }

    private func selectTab(_ name: String) {
        let direct = app.tabBars.buttons[name]
        if direct.waitForExistence(timeout: 1) {
            direct.tap()
            return
        }
        app.tabBars.buttons["More"].tap()
        let item = app.tables.staticTexts[name]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "Could not find the \(name) tab")
        item.tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func scrollToElement(_ element: XCUIElement, attempts: Int = 8) {
        guard !element.exists || !element.isHittable else { return }
        for _ in 0..<attempts where !element.exists || !element.isHittable {
            app.swipeUp()
        }
    }
}
