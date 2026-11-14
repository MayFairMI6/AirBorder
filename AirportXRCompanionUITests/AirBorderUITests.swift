import XCTest

final class AirBorderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState", "-skipOnboarding", "-walkingSpeed", "5.6", "-gateUpdate", "off"]
        app.launch()
    }

    func testFourTabsShowTheirScreens() {
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 5))
        app.buttons["tab-layover"].tap()
        XCTAssertTrue(app.staticTexts["Layover & transit"].waitForExistence(timeout: 2))
        app.buttons["tab-route"].tap()
        XCTAssertTrue(app.staticTexts["Route to Gate 105"].waitForExistence(timeout: 2))
        app.buttons["tab-profile"].tap()
        XCTAssertTrue(app.staticTexts["Your profile"].waitForExistence(timeout: 2))
    }

    // PROCEDURAL: exercise the tracker actions and their visible status through the native UI.
    func testJourneyDetailsCheckpointOpensJourneySteps() {
        app.buttons["journeyDetailsLink"].tap()
        let progress = app.descendants(matching: .any)["journeyProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 2))
        XCTAssertEqual(progress.label, "Step 3 of 5, Security")
        app.buttons["checkpointLine"].tap()
        XCTAssertTrue(app.staticTexts["Journey steps"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Haneda connection · Step 3 of 5"].exists)
        XCTAssertFalse(app.buttons["skip-passport"].exists)
        let completeSecurity = app.buttons["confirm-security"]
        XCTAssertEqual(completeSecurity.label, "Mark complete")
        XCTAssertGreaterThanOrEqual(completeSecurity.frame.height, 44)
        attachJourneySteps("Security current")
        completeSecurity.tap()
        XCTAssertTrue(app.buttons["undo-security"].exists)
        XCTAssertEqual(app.buttons["confirm-passport"].label, "Mark complete")
        let skipPassport = app.buttons["skip-passport"]
        XCTAssertTrue(skipPassport.isHittable)
        XCTAssertEqual(skipPassport.label, "Skip this step")
        XCTAssertGreaterThanOrEqual(skipPassport.frame.height, 44)
        XCTAssertTrue(app.staticTexts["Check with airport staff before skipping."].exists)
        attachJourneySteps("Passport control current")
        skipPassport.tap()
        let passport = app.descendants(matching: .any)["journey-step-passport"]
        XCTAssertEqual(passport.value as? String, "Skipped")
        XCTAssertTrue(app.staticTexts["Haneda connection · Step 5 of 5"].exists)
        attachJourneySteps("Passport control skipped")
        app.buttons["back"].tap()
        XCTAssertEqual(progress.label, "Step 5 of 5, Gate and boarding. Skipped: Passport control")
        app.buttons["checkpointLine"].tap()
        app.buttons["undo-passport"].tap()
        XCTAssertTrue(skipPassport.isHittable)
        app.buttons["back"].tap()
        XCTAssertEqual(progress.label, "Step 4 of 5, Passport control")
    }

    private func attachJourneySteps(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAddStopsApplySuggestionAndUndo() {
        app.buttons["tab-layover"].tap()
        app.buttons["add-cafe"].tap()
        app.buttons["add-anaLounge"].tap()
        app.buttons["tab-flight"].tap()
        app.buttons["myPlanLink"].tap()
        let suggestion = app.descendants(matching: .any)["suggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 2))
        XCTAssertTrue(suggestion.label.contains("Allow 10 more minutes for the café queue"))
        XCTAssertTrue(app.buttons["stop-anaLounge"].label.contains("28 min visit"), "Nothing changes before Apply")
        app.buttons["applySuggestion"].tap()
        XCTAssertTrue(app.buttons["undoToast"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["stop-anaLounge"].label.contains("16:43–17:01 · 18 min visit"))
        app.buttons["undoToast"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["suggestion"].waitForExistence(timeout: 2))
    }

    func testRouteStepsEndReturnsToFlight() {
        app.buttons["tab-route"].tap()
        XCTAssertTrue(app.staticTexts["Follow the Gates 105–109 sign"].waitForExistence(timeout: 2))
        app.buttons["nextStep"].tap()
        app.buttons["nextStep"].tap()
        XCTAssertTrue(app.staticTexts["Check your flight"].exists)
        app.buttons["endRoute"].tap()
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 2))
    }

    func testAppleHealthRefinesWalkingPace() {
        app.buttons["tab-profile"].tap()
        app.buttons["previousTripsRow"].tap()
        app.buttons["viewWalkingPace"].tap()
        XCTAssertTrue(app.staticTexts["4.2 km/h"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["From 3 airport walks · walking only"].exists)
        app.buttons["Connect walking data"].tap()
        app.buttons["Connect Apple Health"].tap()
        XCTAssertTrue(app.staticTexts["Walking speed and distance"].waitForExistence(timeout: 2))
        app.buttons["allowWalkingData"].tap()
        XCTAssertTrue(app.staticTexts["Speed and distance · Synced just now"].waitForExistence(timeout: 3))
        app.buttons["back"].tap()
        XCTAssertTrue(app.staticTexts["4.9 km/h"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["From 3 airport walks and Apple Health"].exists)
        let paceWords = NSPredicate(format: "label CONTAINS[c] 'slow' OR label CONTAINS[c] 'fast'")
        XCTAssertFalse(app.staticTexts.containing(paceWords).firstMatch.exists)
    }

    func testOnboardingRunsOnceThenOpensFlight() {
        app.terminate()
        app.launchArguments = ["-resetState", "-walkingSpeed", "5.6"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to\nAirBorder"].waitForExistence(timeout: 5))
        app.buttons["welcomeContinue"].tap()
        for _ in 0 ..< 3 {
            XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 2))
            app.buttons["onboardingContinue"].tap()
        }
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 3))
        app.terminate()
        app.launchArguments = ["-walkingSpeed", "5.6"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 5), "Onboarding shows only once")
    }

    func testRouteEndShowsArrivalToast() {
        app.buttons["tab-route"].tap()
        app.buttons["nextStep"].tap()
        app.buttons["nextStep"].tap()
        app.buttons["endRoute"].tap()
        let toast = app.buttons["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 2))
        XCTAssertTrue(toast.label.contains("Arrived, Gate 105, NH 106, boarding 17:00."))
    }

    func testManualFlightEntryValidatesAndSaves() {
        app.buttons["addFlight"].tap()
        app.buttons["importTicket"].tap()
        app.buttons["addManually"].tap()
        let number = app.textFields["manualNumber"]
        XCTAssertTrue(number.waitForExistence(timeout: 2))
        number.tap()
        number.typeText("JL")
        app.buttons["reviewEntered"].tap()
        XCTAssertTrue(app.staticTexts["Enter the airline code and number, like BA123."].exists)
        number.typeText("43")
        let date = app.textFields["manualDate"]
        date.tap()
        date.typeText("2026-10-15")
        app.buttons["reviewEntered"].tap()
        XCTAssertTrue(app.staticTexts["JL 43"].waitForExistence(timeout: 2))
        app.buttons["saveEntered"].tap()
        let saved = app.descendants(matching: .any)["manualFlights"]
        XCTAssertTrue(saved.waitForExistence(timeout: 2))
        XCTAssertTrue(saved.label.contains("JL 43 · 15 Oct 2026"))
    }

    func testBaggageDeclarationAndReturnFlight() {
        app.buttons["journeyDetailsLink"].tap()
        app.buttons["Baggage for this flight"].tap()
        XCTAssertTrue(app.staticTexts["1 × 32 kg"].waitForExistence(timeout: 2) || app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS '1 × 32 kg'")).firstMatch.exists)
        app.buttons["extraBaggage"].tap()
        app.buttons["saveExtraBag"].tap()
        XCTAssertTrue(app.staticTexts["Baggage updated"].waitForExistence(timeout: 2))
        app.buttons["back"].firstMatch.tap()
        app.buttons["viewReturnFlight"].tap()
        XCTAssertTrue(app.staticTexts["RETURN FLIGHT, 21 OCT"].waitForExistence(timeout: 2))
    }

    func testEditFlightDateAndSave() {
        app.buttons["tab-profile"].tap()
        app.buttons["Saved flights"].tap()
        app.buttons["Edit this flight"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS '15 Oct 2026'")).firstMatch.tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS '16 October 2026'")).firstMatch.tap()
        app.buttons["reviewCorrected"].tap()
        app.buttons["saveFlight"].tap()
        XCTAssertTrue(app.staticTexts["Flight saved"].waitForExistence(timeout: 2))
        app.buttons["View saved flights"].tap()
        XCTAssertTrue(app.staticTexts["Your flights"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS '16 Oct'")).firstMatch.exists)
    }

    func testImportPathsAreHonestAboutWhatWorks() {
        app.buttons["addFlight"].tap()
        app.buttons["importTicket"].tap()
        app.buttons["import-Camera"].tap()
        XCTAssertTrue(app.staticTexts["Scan your ticket"].waitForExistence(timeout: 2))
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 2))
        app.buttons["Other import options"].tap()
        XCTAssertTrue(app.staticTexts["Where is your ticket?"].waitForExistence(timeout: 2))
        app.buttons["import-Gmail"].tap()
        XCTAssertTrue(app.staticTexts["Connect Gmail"].waitForExistence(timeout: 2))
        app.buttons["Continue with Google"].tap()
        XCTAssertTrue(app.alerts["Google sign-in isn't available yet"].waitForExistence(timeout: 2))
    }

    func testAddToMyPlanShowsAddedPlanOnFlight() {
        app.buttons["myPlanLink"].tap()
        XCTAssertTrue(app.staticTexts["No stops added yet"].waitForExistence(timeout: 2))
        app.buttons["Add a stop"].tap()
        XCTAssertTrue(app.staticTexts["Add to my plan"].waitForExistence(timeout: 2))
        app.buttons["plan-cafe"].tap()
        app.buttons["View my plan"].tap()
        XCTAssertTrue(app.buttons["stop-cafe"].waitForExistence(timeout: 2))
        app.buttons["View route through stops"].tap()
        XCTAssertTrue(app.staticTexts["Route via Curacion Cafe"].waitForExistence(timeout: 2))
        app.buttons["back"].tap()
        app.buttons["back"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["addedPlanCard"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["addStop"].exists)
        app.buttons["Remove plan"].tap()
        XCTAssertTrue(app.buttons["addStop"].waitForExistence(timeout: 2))
    }

    func testTerminalTwoVisitAddsToPlanAndShowsRoute() {
        app.buttons["tab-layover"].tap()
        app.buttons["area-Landside"].tap()
        let deck = app.buttons["View route & return"]
        app.swipeUp()
        XCTAssertTrue(deck.waitForExistence(timeout: 2))
        deck.tap()
        XCTAssertTrue(app.staticTexts["T2 Observation Deck"].waitForExistence(timeout: 2))
        app.buttons["addT2Visit"].tap()
        XCTAssertTrue(app.buttons["Remove the visit"].waitForExistence(timeout: 2))
        app.buttons["View shuttle route"].tap()
        XCTAssertTrue(app.staticTexts["To Terminal 2"].waitForExistence(timeout: 2))
        app.buttons["Arrived at Terminal 2"].tap()
        XCTAssertTrue(app.staticTexts["At T2 Observation Deck"].waitForExistence(timeout: 2))
        app.buttons["View Journey"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["addedPlanCard"].waitForExistence(timeout: 2))
    }

    private func relaunch(_ extra: [String]) {
        app.terminate()
        app.launchArguments = ["-resetState", "-skipOnboarding", "-walkingSpeed", "5.6"] + extra
        app.launch()
    }

    func testGateUpdateArrivesAsAnAlertAndChangesTheGate() {
        relaunch(["-gateUpdate", "1"])
        XCTAssertTrue(app.descendants(matching: .any)["alertCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Gate 105 → 108A"].exists)
        app.buttons["alertRoute"].tap()
        XCTAssertTrue(app.staticTexts["Route to Gate 108A"].waitForExistence(timeout: 2))
        app.buttons["tab-flight"].tap()
        XCTAssertTrue(app.buttons["travelUpdate-flight"].label.contains("108A"))
        app.buttons["travelUpdateAction-flight"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["alertCard"].waitForExistence(timeout: 2))
    }

    // PROCEDURAL: trigger the sample feed after the app saves arrival at the old gate.
    func testGateChangeAfterArrivalReopensTrackerAndWarnsAboutBoarding() {
        app.buttons["journeyDetailsLink"].tap()
        app.buttons["checkpointLine"].tap()
        app.buttons["confirm-security"].tap()
        app.buttons["confirm-passport"].tap()
        app.buttons["confirm-gate"].tap()
        XCTAssertTrue(app.staticTexts["Haneda connection · All steps done"].exists)

        app.terminate()
        // Keep the confirmation from the first launch and deliver the gate update at 17:10.
        app.launchArguments = ["-skipOnboarding", "-walkingSpeed", "5.6", "-now", "17:10", "-gateUpdate", "0"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Boarding time is tight"].waitForExistence(timeout: 5))
        attachJourneySteps("Boarding risk after gate reassignment")
        app.buttons["back"].tap()
        let countdown = app.descendants(matching: .any)["scenarioCountdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 2))
        XCTAssertEqual(countdown.label, "15 min before Gate 108A closes.")
        app.buttons["journeyDetailsLink"].tap()
        app.buttons["checkpointLine"].tap()
        XCTAssertTrue(app.staticTexts["Haneda connection · Step 5 of 5"].exists)
        XCTAssertEqual(app.buttons["confirm-gate"].label, "Mark complete")
        XCTAssertFalse(app.buttons["confirm-security"].exists)
        XCTAssertFalse(app.buttons["confirm-passport"].exists)
        attachJourneySteps("Gate checkpoint reopened")
    }

    func testReturnNowShowsCountdownInsteadOfThePlan() {
        relaunch(["-gateUpdate", "off", "-now", "17:00"])
        XCTAssertTrue(app.staticTexts["Time to return to Gate 105"].waitForExistence(timeout: 5), "Alert opens on its own")
        app.buttons["back"].tap()
        let countdown = app.descendants(matching: .any)["scenarioCountdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 2))
        XCTAssertEqual(countdown.label, "25 min before Gate 105 closes.")
        XCTAssertFalse(app.buttons["myPlanLink"].exists)
        XCTAssertFalse(app.buttons["addStop"].exists)
    }

    func testArrivalAfterClosureOffersAssistance() {
        relaunch(["-gateUpdate", "off", "-now", "17:17"])
        let banner = app.buttons["travelUpdate-flight"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.label.contains("Arrival 4 min after closure"))
        XCTAssertTrue(app.buttons["travelUpdateAction-flight"].label.contains("Call ANA"))
        banner.tap()
        XCTAssertTrue(app.staticTexts["Boarding assistance"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Arriving 17:29"].exists)
    }

    func testChoosingNH6StartsTheNaritaTransfer() {
        app.buttons["tab-profile"].tap()
        app.buttons["Saved flights"].tap()
        app.buttons["Edit this flight"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'NH 106'")).firstMatch.tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'NH 6'")).firstMatch.tap()
        app.buttons["reviewCorrected"].tap()
        app.buttons["saveFlight"].tap()
        XCTAssertTrue(app.staticTexts["Flight saved"].waitForExistence(timeout: 2))
        app.buttons["View saved flights"].tap()
        app.buttons["back"].tap()
        app.buttons["tab-flight"].tap()
        XCTAssertTrue(app.buttons["travelUpdate-flight"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["travelUpdate-flight"].label.contains("Change airports: Haneda → Narita"))
        XCTAssertTrue(app.descendants(matching: .any)["transferCountdown"].exists)
        app.buttons["tab-route"].tap()
        XCTAssertTrue(app.staticTexts["Route to Narita"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Follow Bus signs"].exists)
    }

    func testCameraGuidanceKeepsTheStepAndFallsBackToTheMap() {
        app.terminate()
        app.resetAuthorizationStatus(for: .camera)
        app.launch()
        app.buttons["tab-route"].tap()
        app.buttons["mode-camera"].tap()
        XCTAssertTrue(app.staticTexts["Camera guidance"].waitForExistence(timeout: 2))
        app.buttons["useMapInstead"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["routeSummary"].waitForExistence(timeout: 2))
        app.buttons["nextStep"].tap()
        app.buttons["mode-camera"].tap()
        app.buttons["allowCamera"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.buttons["readSignAgain"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Gate 105 ahead"].exists, "Camera keeps the current step")
        app.buttons["readSignAgain"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["scanningSign"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Can't read the sign"].waitForExistence(timeout: 15))
        app.buttons["useMap"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["routeSummary"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Gate 105 ahead"].exists)
    }

    func testFlightOneOpensInJourneyDetails() {
        app.buttons["journeyDetailsLink"].tap()
        app.buttons["flightOne"].tap()
        XCTAssertTrue(app.staticTexts["05:15"].waitForExistence(timeout: 2), "Flight 1 shows as the full ticket")
        XCTAssertTrue(app.buttons["flightTwo"].exists)
        app.buttons["flightTwo"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticket-NH106"].waitForExistence(timeout: 2))
    }

    func testTerminalTwoTooLateSendsTravellerToTheGate() {
        relaunch(["-gateUpdate", "off", "-now", "15:00"])
        app.buttons["tab-layover"].tap()
        app.buttons["area-Landside"].tap()
        app.swipeUp()
        let deck = app.buttons["View route & return"]
        XCTAssertTrue(deck.waitForExistence(timeout: 2))
        deck.tap()
        XCTAssertTrue(app.staticTexts["Not enough time for Terminal 2"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["addT2Visit"].exists)
    }

    func testNH6BaggageShowsTheNaritaRecheck() {
        relaunch(["-gateUpdate", "off", "-flight", "NH6"])
        app.buttons["journeyDetailsLink"].tap()
        app.buttons["Baggage for this flight"].tap()
        XCTAssertTrue(app.staticTexts["Collect at Haneda T3 2F. Recheck at Narita T1 by 20:00."].waitForExistence(timeout: 2))
        app.buttons["extraBaggage"].tap()
        XCTAssertTrue(app.staticTexts["Up to 32 kg, NH 6"].waitForExistence(timeout: 2))
    }
}
