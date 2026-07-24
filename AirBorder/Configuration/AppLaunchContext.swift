import Foundation

enum AppLaunchMode: String, Codable, CaseIterable, Sendable {
    case live
    case demo
    case offline
    case stochastic
}

struct AppLaunchContext: Equatable, Sendable {
    let mode: AppLaunchMode
    let simulationSeed: UInt64?
    let isUITest: Bool
    let scenario: String?
    let usesSimulatedTerminalWalk: Bool
    let usesAutomatedWalkthrough: Bool
    let externalIndoorSignalURL: URL?
    let usesCoreLocationIndoorQA: Bool
    /// Test-only clock movement. This is deliberately unavailable to normal
    /// launches so a practice scenario can never alter a real trip's timing.
    let qaClockOffsetMinutes: Int
    /// Test-only fixed weather state used to exercise the presentation without
    /// making a network request.
    let qaWeatherScenario: String?
    let qaTrafficLevel: String?
    let qaWalkingPace: WalkingPacePreference?

    init(
        mode: AppLaunchMode,
        simulationSeed: UInt64?,
        isUITest: Bool,
        scenario: String? = nil,
        usesSimulatedTerminalWalk: Bool = false,
        usesAutomatedWalkthrough: Bool = false,
        externalIndoorSignalURL: URL? = nil,
        usesCoreLocationIndoorQA: Bool = false,
        qaClockOffsetMinutes: Int = 0,
        qaWeatherScenario: String? = nil,
        qaTrafficLevel: String? = nil,
        qaWalkingPace: WalkingPacePreference? = nil
    ) {
        self.mode = mode
        self.simulationSeed = simulationSeed
        self.isUITest = isUITest
        self.scenario = scenario
        self.usesSimulatedTerminalWalk = usesSimulatedTerminalWalk
        self.usesAutomatedWalkthrough = usesAutomatedWalkthrough
        self.externalIndoorSignalURL = externalIndoorSignalURL
        self.usesCoreLocationIndoorQA = usesCoreLocationIndoorQA
        self.qaClockOffsetMinutes = qaClockOffsetMinutes
        self.qaWeatherScenario = qaWeatherScenario
        self.qaTrafficLevel = qaTrafficLevel
        self.qaWalkingPace = qaWalkingPace
    }

    var badgeTitle: String {
        switch mode {
        case .live: "Current trip"
        case .demo: "Example itinerary"
        case .offline: "Saved trip"
        case .stochastic: "Practice itinerary"
        }
    }

    var badgeDetail: String? {
        nil
    }

    static func current(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppLaunchContext {
        let isUITest = arguments.contains("--uitesting")
        let requested: AppLaunchMode = {
            guard let index = arguments.firstIndex(of: "--launch-mode"),
                  arguments.indices.contains(index + 1),
                  let mode = AppLaunchMode(rawValue: arguments[index + 1].lowercased()) else {
                return .live
            }
            return mode
        }()

        // Demo/stochastic modes are reserved for explicit UI-test launches.
        // Ordinary app launches cannot silently fall back to bundled fixtures;
        // legacy requests therefore resolve to live mode unless the test
        // harness explicitly opts in with --uitesting.
        let mode: AppLaunchMode = isUITest ? requested : ((requested == .demo || requested == .stochastic) ? .live : requested)

        let scenario: String? = {
            guard isUITest,
                  let index = arguments.firstIndex(of: "--scenario"),
                  arguments.indices.contains(index + 1) else { return nil }
            let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }()

        let seed: UInt64? = nil
        let qaClockOffsetMinutes: Int = {
            guard isUITest,
                  let index = arguments.firstIndex(of: "--qa-clock-offset-minutes"),
                  arguments.indices.contains(index + 1) else { return 0 }
            return Int(arguments[index + 1]) ?? 0
        }()
        let qaWeatherScenario: String? = {
            guard isUITest,
                  let index = arguments.firstIndex(of: "--qa-weather"),
                  arguments.indices.contains(index + 1) else { return nil }
            let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return value.isEmpty ? nil : value
        }()
        let qaTrafficLevel: String? = {
            guard isUITest,
                  let index = arguments.firstIndex(of: "--qa-traffic"),
                  arguments.indices.contains(index + 1) else { return nil }
            let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["light", "normal", "heavy"].contains(value) ? value : nil
        }()
        let qaWalkingPace: WalkingPacePreference? = {
            guard isUITest,
                  let index = arguments.firstIndex(of: "--qa-walking-pace"),
                  arguments.indices.contains(index + 1) else { return nil }
            return WalkingPacePreference(rawValue: arguments[index + 1].lowercased())
        }()
        let usesCoreLocationIndoorQA = isUITest && arguments.contains("--qa-core-location-indoor")
        let externalIndoorSignalURL: URL? = {
            guard isUITest,
                  let index = arguments.firstIndex(of: "--qa-indoor-feed"),
                  arguments.indices.contains(index + 1),
                  let url = URL(string: arguments[index + 1]),
                  (try? LocalIndoorSignalFeedClient(endpoint: url)) != nil else { return nil }
            return url
        }()
        return AppLaunchContext(
            mode: mode,
            simulationSeed: seed,
            isUITest: isUITest,
            scenario: scenario,
            usesSimulatedTerminalWalk: isUITest && (
                arguments.contains("--qa-simulated-walk")
                    || arguments.contains("--qa-walkthrough")
                    || externalIndoorSignalURL != nil
                    || usesCoreLocationIndoorQA
            ),
            usesAutomatedWalkthrough: isUITest && arguments.contains("--qa-walkthrough"),
            externalIndoorSignalURL: externalIndoorSignalURL,
            usesCoreLocationIndoorQA: usesCoreLocationIndoorQA,
            qaClockOffsetMinutes: qaClockOffsetMinutes,
            qaWeatherScenario: qaWeatherScenario,
            qaTrafficLevel: qaTrafficLevel,
            qaWalkingPace: qaWalkingPace
        )
    }
}
