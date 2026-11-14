// PROCEDURAL: Asserts the app consumes the real local replay feed in Simulator.
import XCTest

final class IndoorReplayIntegrationTests: XCTestCase {
    @MainActor
    func testExternalFloorReplayUpdatesRouteAndResetRestoresIt() async throws {
        continueAfterFailure = false
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["AIRBORDER_QA_REPLAY_URL"],
                                 "Run this integration suite with Scripts/test-with-indoor-driver.py")
        let driver = try XCTUnwrap(URL(string: base))
        let app = XCUIApplication()
        app.launchArguments = ["-resetState", "-skipOnboarding", "-walkingSpeed", "5.6",
                               "-gateUpdate", "off", "--uitesting", "--qa-indoor-feed",
                               driver.appendingPathComponent("reading").absoluteString]
        app.launch()
        defer { app.terminate() }
        let route = app.buttons["tab-route"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()
        let instruction = app.staticTexts["routeInstruction"]
        let initial = "Follow the Gates 105–109 sign"
        await expectInstruction(instruction, initial)

        // Advance the external clock; never tap the app's Next step control.
        // The upper-floor landmark is sample 9 of this scripted route.
        for _ in 0..<9 { try await control(driver, "next") }
        await expectInstruction(instruction, "Gate 105 ahead")
        for _ in 0..<3 { try await control(driver, "next") }
        await expectInstruction(instruction, "Check your flight")
        XCTAssertTrue(app.buttons["endRoute"].exists)
        try await control(driver, "reset")
        await expectInstruction(instruction, initial)
    }

    @MainActor
    private func expectInstruction(_ instruction: XCUIElement, _ label: String) async {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", label), object: instruction
        )
        await fulfillment(of: [expectation], timeout: 8)
    }

    private func control(_ driver: URL, _ action: String) async throws {
        var request = URLRequest(url: driver.appendingPathComponent("control").appendingPathComponent(action),
                                 timeoutInterval: 3)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
}
