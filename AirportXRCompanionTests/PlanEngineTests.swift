@testable import AirBorder
import XCTest

final class PlanEngineTests: XCTestCase {
    private let both = Plan(stops: [.cafe, .anaLounge])

    func testNoStopsLeavesInTimeToArriveAtTarget() {
        let schedule = PlanEngine.schedule(Plan(), pace: .average)
        XCTAssertEqual(schedule.leave.description, "16:53")
        XCTAssertEqual(schedule.arriveAtGate.description, "17:05")
        XCTAssertEqual(durationText(schedule.leave - SampleJourney.now), "4h 53m")
    }

    func testCafeThenLoungeMatchesMyPlan() {
        let schedule = PlanEngine.schedule(both, pace: .average)
        XCTAssertEqual(PlanText.timing(schedule.stops[0]), "16:00–16:28 · 8 min wait + 20 min visit")
        XCTAssertEqual(PlanText.timing(schedule.stops[1]), "16:33–17:01 · 28 min visit")
        XCTAssertEqual(PlanText.walk(schedule.stops[1]), "5 min walk from the café")
        XCTAssertEqual(PlanText.arrivalTitle(schedule), "Arrive at your gate by 17:05")
        XCTAssertEqual(PlanText.arrivalDetail(schedule), "Leave ANA LOUNGE at 17:01. Gate closes at 17:25.")
    }

    func testShorterCafeAndReorderRecompute() {
        var shorter = both
        shorter.stops[0].visitMinutes = 15
        let first = PlanEngine.schedule(shorter, pace: .average)
        XCTAssertEqual(first.stops[1].start.description, "16:28")
        XCTAssertEqual(first.arriveAtGate.description, "17:00")

        let reordered = Plan(stops: [.anaLounge, .cafe])
        let second = PlanEngine.schedule(reordered, pace: .average)
        XCTAssertEqual(second.stops[0].start.description, "16:05")
        XCTAssertEqual(second.stops[1].end.description, "17:06")
        XCTAssertEqual(second.arriveAtGate.description, "17:14")
    }

    func testQueueUpdateSuggestsShorteningTheLaterSelectedStop() throws {
        let update = QueueUpdate(stopID: .cafe, waitMinutes: 18)
        let suggestion = try XCTUnwrap(PlanEngine.suggestion(for: both, update: update, pace: .average))
        XCTAssertEqual(suggestion.title, "Allow 10 more minutes for the café queue")
        XCTAssertEqual(suggestion.detail, "Shorten ANA LOUNGE to 18 min to still arrive by 17:05.")
        let applied = PlanEngine.schedule(suggestion.proposed, pace: .average)
        XCTAssertEqual(PlanText.timing(applied.stops[0]), "16:00–16:38 · 18 min for the queue + 20 min visit")
        XCTAssertEqual(PlanText.timing(applied.stops[1]), "16:43–17:01 · 18 min visit")
        XCTAssertEqual(applied.arriveAtGate.description, "17:05")
        // The proposal never touches stops that were not in the selected plan.
        XCTAssertEqual(suggestion.proposed.stops.map(\.id), both.stops.map(\.id))
    }

    func testNoSuggestionWhenNothingLaterCanAbsorbTheDelay() {
        let cafeLast = Plan(stops: [.anaLounge, .cafe])
        XCTAssertNil(PlanEngine.suggestion(for: cafeLast, update: QueueUpdate(stopID: .cafe, waitMinutes: 18), pace: .average))
        XCTAssertNil(PlanEngine.suggestion(for: Plan(stops: [.cafe]), update: QueueUpdate(stopID: .cafe, waitMinutes: 18), pace: .average))
    }

    func testPersonalPaceScalesWalkingTimes() {
        XCTAssertEqual(WalkingTimes.minutes(average: 12, pace: .average), 12)
        XCTAssertEqual(WalkingTimes.minutes(average: 12, pace: .personal(kmh: 4.2)), 12)
        XCTAssertEqual(WalkingTimes.minutes(average: 12, pace: .personal(kmh: 5.6)), 9)
        XCTAssertEqual(WalkingTimes.minutes(average: 12, pace: .personal(kmh: 3.0)), 17)
        // Implausible readings fall back to average times.
        XCTAssertEqual(WalkingTimes.minutes(average: 12, pace: .personal(kmh: 0.2)), 12)
        XCTAssertEqual(PaceText.kmh(4.64), "4.6 km/h")
    }

    func testEstimatesStartFromAirportWalksAndAppleHealthRefinesThem() {
        let walks = SampleJourney.airportWalks
        XCTAssertEqual(WalkingEstimate.kmh(walks: walks), 4.2)
        XCTAssertEqual(WalkingEstimate.pace(walks: walks, healthKmh: nil), .personal(kmh: 4.2))
        guard case let .personal(blended) = WalkingEstimate.pace(walks: walks, healthKmh: 5.6) else { return XCTFail("Expected a personal pace") }
        XCTAssertEqual(PaceText.kmh(blended), "4.9 km/h")
        XCTAssertEqual(WalkingEstimate.pace(walks: [], healthKmh: nil), .average)
        XCTAssertEqual(WalkingEstimate.pace(walks: [], healthKmh: 5.0), .personal(kmh: 5.0))
    }
}

final class JourneyChecklistTests: XCTestCase {
    func testNowIsFirstUnconfirmedStep() {
        let checklist = JourneyChecklist.haneda
        XCTAssertEqual(checklist.current?.title, "Security")
        XCTAssertEqual(checklist.next?.title, "Passport control")
        XCTAssertEqual(checklist.status(of: checklist.steps[2]), "Current step")
        XCTAssertEqual(checklist.status(of: checklist.steps[3]), "Upcoming")
    }

    // PROCEDURAL: verify that reaching a checkpoint gates its skip action and that Undo restores it.
    func testConfirmSkipAndUndo() {
        var checklist = JourneyChecklist.haneda
        XCTAssertFalse(checklist.canConfirm("passport"), "Only the current step can be confirmed")
        XCTAssertFalse(checklist.canSkip("passport"), "An upcoming step cannot be skipped")
        checklist.skip("passport")
        XCTAssertEqual(checklist.next?.title, "Passport control")
        checklist.confirm("security")
        XCTAssertEqual(checklist.current?.title, "Passport control")
        XCTAssertTrue(checklist.canUndo("security"))
        XCTAssertTrue(checklist.canSkip("passport"))
        checklist.skip("passport")
        XCTAssertEqual(checklist.current?.title, "Gate and boarding")
        XCTAssertEqual(checklist.status(of: checklist.steps[3]), "Skipped")
        checklist.undo()
        XCTAssertEqual(checklist.current?.title, "Passport control")
        XCTAssertFalse(JourneyChecklist.narita.canSkip("passport"), "Passport control remains required for the airport transfer")
    }

    func testCompletes() {
        var checklist = JourneyChecklist.haneda
        checklist.confirm("security")
        checklist.skip("passport")
        checklist.confirm("gate", departureGate: "105")
        XCTAssertTrue(checklist.isComplete)
        XCTAssertNil(checklist.current)
    }
}

@MainActor
final class JourneyStoreTests: XCTestCase {
    private func makeStore(kmh: Double? = nil) -> JourneyStore {
        let defaults = UserDefaults(suiteName: "JourneyStoreTests-\(UUID().uuidString)")!
        return JourneyStore(walkingData: FixedWalkingData(kmh: kmh), defaults: defaults)
    }

    func testSuggestionAppliesOnlyAfterApplyAndCanBeUndone() {
        let store = makeStore()
        store.add(.cafe)
        store.add(.anaLounge)
        XCTAssertNotNil(store.suggestion)
        XCTAssertEqual(store.plan.stops[1].visitMinutes, 28, "Nothing changes before Apply")
        store.applySuggestion()
        XCTAssertEqual(store.plan.stops[1].visitMinutes, 18)
        XCTAssertNil(store.suggestion)
        store.undoSuggestion()
        XCTAssertEqual(store.plan.stops[1].visitMinutes, 28)
        XCTAssertNotNil(store.suggestion)
    }

    func testKeepPlanKeepsStopsButCountsTheQueue() {
        let store = makeStore()
        store.add(.cafe)
        store.add(.anaLounge)
        store.keepPlan()
        XCTAssertEqual(store.plan.stops[1].visitMinutes, 28)
        XCTAssertEqual(store.plan.stops[0].waitMinutes, 18)
        XCTAssertEqual(store.schedule.arriveAtGate.description, "17:15")
    }

    func testPlanChangeDropsStaleSuggestion() {
        let store = makeStore()
        store.add(.cafe)
        store.add(.anaLounge)
        store.remove(.anaLounge)
        XCTAssertNil(store.suggestion)
    }

    func testAppleHealthRefinesAirportWalkEstimate() async {
        let store = makeStore(kmh: 5.6)
        XCTAssertEqual(store.pace, .personal(kmh: 4.2), "Airport walks come first")
        XCTAssertEqual(store.gateWalkMinutes, 12)
        await store.connectHealth()
        XCTAssertEqual(store.gateWalkMinutes, 11, "Apple Health refines the estimate")
        store.removeHealth()
        XCTAssertEqual(store.health, .removed)
        XCTAssertEqual(store.pace, .personal(kmh: 4.2))
    }

    func testStepFreePreferenceSelectsStepFreeRoute() {
        let store = makeStore()
        store.stepFreeRoutes = true
        XCTAssertEqual(store.routeChoice, .stepFree)
        XCTAssertEqual(store.gateWalkMinutes, 16)
    }
}

final class TicketReaderTests: XCTestCase {
    func testReadsFlightDateAndRouteFromItineraryText() {
        let text = """
        ANA itinerary
        Flight NH 106  HND → LAX
        Departure 15 Oct 2026 18:00 Terminal 3
        """
        let ticket = TicketReader.parse(text, source: "ANA-itinerary.pdf")
        XCTAssertEqual(ticket?.number, "NH 106")
        XCTAssertEqual(ticket?.date, "2026-10-15")
        XCTAssertEqual(ticket?.route, "HND → LAX")
    }

    func testReadsBoardingPassStyleText() {
        let ticket = TicketReader.parse("BOARDING PASS JL043 21OCT LAX TO HND SEAT 3A", source: "Your ticket photo", defaultYear: 2026)
        XCTAssertEqual(ticket?.number, "JL 43")
        XCTAssertEqual(ticket?.date, "2026-10-21")
        XCTAssertEqual(ticket?.from, "LAX")
    }

    func testNoFlightNumberMeansUnreadable() {
        XCTAssertNil(TicketReader.parse("Thank you for shopping with us", source: "receipt.pdf"))
    }

    func testRejectsImpossibleDates() {
        XCTAssertNil(TicketReader.date(in: "2026-02-31", defaultYear: 2026))
        XCTAssertNil(TicketReader.date(in: "45 OCT 2026", defaultYear: 2026))
    }
}

/// Situations come only from their conditions (Figma scenarios: gate change, return, at risk, assistance, transfer).
final class JourneyConditionTests: XCTestCase {
    private func inputs(now: ClockTime, feedGate: String? = nil, closes: ClockTime? = ClockTime(17, 25), atGate: Bool = false, transfer: Bool = false) -> ConditionInputs {
        ConditionInputs(
            now: now,
            ticketGate: "105",
            feed: feedGate.map { FlightFeed(gate: $0, receivedAt: ClockTime(12, 0)) },
            gateCloses: closes,
            walkToGate: 12,
            leaveBy: ClockTime(16, 53),
            atGate: atGate,
            departsFromAnotherAirport: transfer
        )
    }

    func testNothingToReportAtNoon() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(12, 0))), [])
    }

    func testGateChangeComesFromTheFeed() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(12, 0), feedGate: "108A")), [.gateChanged(from: "105", to: "108A")])
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(12, 0), feedGate: "105")), [], "Same gate is not a change")
    }

    func testReturnNowAtFigmaTime() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 0))), [.returnNow(closesIn: 25, walk: 12)])
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(16, 52))), [], "Not before the leave time")
    }

    func testBoardingAtRiskAtFigmaTime() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 10))), [.boardingAtRisk(closesIn: 15, walk: 12)])
    }

    func testArrivalAfterClosureAtFigmaTime() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 17))), [.arrivesAfterClosure(arrival: ClockTime(17, 29), minutesLate: 4)])
    }

    func testMostUrgentFirstWhenSeveralHold() {
        let found = JourneyConditions.evaluate(inputs(now: ClockTime(17, 10), feedGate: "108A"))
        XCTAssertEqual(found, [.boardingAtRisk(closesIn: 15, walk: 12), .gateChanged(from: "105", to: "108A")])
    }

    func testNoTimingSituationOnceAtTheGateOrWhenClosingTimeIsUnknown() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 17), atGate: true)), [])
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 17), closes: nil)), [], "Unknown closing time is never treated as late or fine")
    }

    func testTransferReplacesHanedaSituations() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 10), feedGate: "108A", transfer: true)), [.airportTransfer])
    }

    func testReminderOnlyWhenSeenAndNotActedOn() {
        let seen = Date(timeIntervalSince1970: 0)
        var record = AlertRecord(issuedAt: ClockTime(12, 0), firstSeen: seen)
        XCTAssertFalse(record.isReminder(at: seen.addingTimeInterval(60)))
        XCTAssertTrue(record.isReminder(at: seen.addingTimeInterval(AlertRecord.reminderInterval)))
        record.acknowledged = true
        XCTAssertFalse(record.isReminder(at: seen.addingTimeInterval(3600)))
        XCTAssertFalse(AlertRecord(issuedAt: ClockTime(12, 0)).isReminder(at: seen), "Never shown, so no reminder")
    }
}

@MainActor
final class JourneySituationStoreTests: XCTestCase {
    private func makeStore(defaults: UserDefaults = UserDefaults(suiteName: "JourneySituationStoreTests-\(UUID().uuidString)")!) -> JourneyStore {
        return JourneyStore(walkingData: FixedWalkingData(kmh: nil), defaults: defaults)
    }

    func testGateUpdateRaisesOneAlertAndChangesTheGateEverywhere() {
        let store = makeStore()
        XCTAssertEqual(store.gate, "105")
        store.receive(FlightFeed(gate: "108A", receivedAt: ClockTime(12, 0)))
        XCTAssertEqual(store.gate, "108A")
        XCTAssertEqual(store.alertToPresent, .gateChange)
        XCTAssertEqual(store.alerts[.gateChange]?.issuedAt, ClockTime(12, 0))
        store.alertToPresent = nil
        store.receive(FlightFeed(gate: "108A", receivedAt: ClockTime(12, 5)))
        XCTAssertNil(store.alertToPresent, "The same update does not alert twice")
        store.acknowledge(.gateChange)
        XCTAssertEqual(store.alerts[.gateChange]?.acknowledged, true)
    }

    // PROCEDURAL: reproduce the stale gate confirmation with a controlled feed update.
    func testDifferentGateReopensGateStepAndRestoresBoardingRisk() {
        let store = makeStore()
        let updateTime = ClockTime(17, 10)
        store.confirmStep("security")
        store.confirmStep("passport")
        store.confirmStep("gate")
        store.setNow(updateTime)

        XCTAssertEqual(store.gate, "105")
        XCTAssertTrue(store.checklist.isComplete)
        XCTAssertTrue(store.conditionInputs.atGate)
        XCTAssertFalse(store.hasTimingSituation)
        let previousSteps = store.checklist.steps.dropLast()

        store.receive(FlightFeed(gate: "108A", receivedAt: updateTime))

        XCTAssertEqual(store.gate, "108A")
        XCTAssertTrue(store.conditions.contains(.gateChanged(from: "105", to: "108A")))
        XCTAssertEqual(store.checklist.steps.dropLast(), previousSteps)
        XCTAssertEqual(store.checklist.current?.id, "gate", "The new gate needs its own confirmation")
        XCTAssertFalse(store.conditionInputs.atGate, "Confirmation at 105 cannot confirm arrival at 108A")
        XCTAssertEqual(store.primaryCondition, .boardingAtRisk(closesIn: 15, walk: 12))
        XCTAssertEqual(store.alertToPresent, .boardingAtRisk)
        XCTAssertFalse(store.checklist.canUndo("gate"))

        store.confirmStep("gate")
        XCTAssertTrue(store.checklist.isComplete)
        XCTAssertTrue(store.conditionInputs.atGate)
        XCTAssertFalse(store.hasTimingSituation)
    }

    func testSameGateAndMissingGatePreservePersistedConfirmation() {
        let defaults = UserDefaults(suiteName: "JourneySituationStoreTests-\(UUID().uuidString)")!
        let store = makeStore(defaults: defaults)
        store.confirmStep("security")
        store.skipStep("passport")
        let update = FlightFeed(gate: "108A", receivedAt: ClockTime(12, 0))
        store.receive(update)
        store.confirmStep("gate")

        let restored = makeStore(defaults: defaults)
        XCTAssertTrue(restored.conditionInputs.atGate)
        restored.receive(update)
        restored.receive(FlightFeed(gate: nil, receivedAt: ClockTime(12, 10)))
        XCTAssertEqual(restored.feed, update)
        XCTAssertTrue(restored.checklist.isComplete)
        XCTAssertTrue(restored.conditionInputs.atGate)

        // An identifier with the same number and a different suffix is a different gate.
        restored.receive(FlightFeed(gate: "108B", receivedAt: ClockTime(12, 15)))
        XCTAssertEqual(restored.checklist.current?.id, "gate")
        XCTAssertFalse(restored.conditionInputs.atGate)
        XCTAssertEqual(restored.checklist.steps.first { $0.id == "passport" }?.state, .skipped)
        XCTAssertEqual(makeStore(defaults: defaults).checklist.current?.id, "gate")
    }

    func testLegacyGateConfirmationReopensWhenRestored() throws {
        let defaults = UserDefaults(suiteName: "JourneySituationStoreTests-\(UUID().uuidString)")!
        let store = makeStore(defaults: defaults)
        store.confirmStep("security")
        store.skipStep("passport")
        store.confirmStep("gate")

        // Simulate a save from the previous version by removing the new gate field.
        let key = "journeyState.v1"
        let saved = try XCTUnwrap(defaults.data(forKey: key))
        var state = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        var checklist = try XCTUnwrap(state["checklist"] as? [String: Any])
        XCTAssertEqual(checklist.removeValue(forKey: "confirmedGate") as? String, "105")
        state["checklist"] = checklist
        defaults.set(try JSONSerialization.data(withJSONObject: state), forKey: key)

        let restored = makeStore(defaults: defaults)
        XCTAssertEqual(restored.checklist.current?.id, "gate")
        XCTAssertEqual(restored.checklist.steps.dropLast(), store.checklist.steps.dropLast())
        XCTAssertFalse(restored.conditionInputs.atGate)
        XCTAssertFalse(restored.checklist.canUndo("gate"))
    }

    func testStopsMoveTheLeaveTimeForReturnNow() {
        let store = makeStore()
        store.setNow(ClockTime(16, 40))
        XCTAssertNil(store.primaryCondition)
        store.add(.cafe)
        XCTAssertEqual(store.conditionInputs.leaveBy, store.schedule.leave)
    }

    func testChoosingNH6StartsTheNaritaTransfer() {
        let store = makeStore()
        store.beginEditingFlight()
        store.flightDraft.number = "NH 6"
        store.saveFlightDraft()
        XCTAssertTrue(store.isAirportTransfer)
        XCTAssertEqual(store.primaryCondition, .airportTransfer)
        XCTAssertEqual(store.checklist.steps.map(\.id), ["arrival", "passport", "bags", "customs", "narita"])
        XCTAssertEqual(store.layoverMinutes, 9 * 60 + 45)
        store.beginEditingFlight()
        store.flightDraft.number = "NH 106"
        store.saveFlightDraft()
        XCTAssertEqual(store.checklist, .haneda)
    }
}

final class SignMatcherTests: XCTestCase {
    func testReadsHanedaGateSignsWhateverTheDash() {
        XCTAssertTrue(SignMatcher.matches(["← 110", "↑ 105-109"], .gates105to109))
        XCTAssertTrue(SignMatcher.matches(["搭乗口 Gates 105–109"], .gates105to109))
        XCTAssertTrue(SignMatcher.matches(["105 - 109"], .gates105to109))
        XCTAssertFalse(SignMatcher.matches(["← 110", "108-149"], .gates105to109))
        XCTAssertTrue(SignMatcher.matches(["Gates 108–149"], .gates108to149))
    }

    func testReadsBusAndLoungeSignsInEnglishOrJapanese() {
        XCTAssertTrue(SignMatcher.matches(["バス乗り場"], .bus))
        XCTAssertTrue(SignMatcher.matches(["Bus"], .bus))
        XCTAssertTrue(SignMatcher.matches(["航空会社ラウンジ"], .lounges))
        XCTAssertTrue(SignMatcher.matches(["Airline Lounges"], .lounges))
        XCTAssertFalse(SignMatcher.matches(["Restrooms"], .lounges))
    }
}

final class TerminalTwoTimingTests: XCTestCase {
    func testVisitFitsOnlyUntilTheLatestStart() {
        // Leave T2 by 15:53 with a 12 min gate walk; 30 min to get there and a 30 min visit.
        XCTAssertEqual(TerminalTwo.leaveBy(gateWalk: 12), ClockTime(15, 53))
        XCTAssertTrue(TerminalTwo.hasTime(now: ClockTime(12, 0), gateWalk: 12))
        XCTAssertTrue(TerminalTwo.hasTime(now: ClockTime(14, 53), gateWalk: 12))
        XCTAssertFalse(TerminalTwo.hasTime(now: ClockTime(14, 54), gateWalk: 12))
    }
}
