import SwiftUI

@main
struct AirBorderApp: App {
    @StateObject private var store: JourneyStore

    init() {
        Outfit.register()
        let arguments = ProcessInfo.processInfo.arguments
        let source: WalkingDataSource
        if let index = arguments.firstIndex(of: "-walkingSpeed"), arguments.indices.contains(index + 1) {
            source = FixedWalkingData(kmh: Double(arguments[index + 1]))
        } else {
            source = AppleHealthWalkingData()
        }
        let store = JourneyStore(walkingData: source, reset: arguments.contains("-resetState"))
        if arguments.contains("-skipOnboarding") { store.onboardingSeen = true }
        // Sample journey options: "-now 17:10" shows the trip at another airport time;
        // "-gateUpdate off|0|30" sets when the sample gate update arrives (seconds).
        if let index = arguments.firstIndex(of: "-now"), arguments.indices.contains(index + 1) {
            let parts = arguments[index + 1].split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { store.setNow(ClockTime(parts[0], parts[1])) }
        }
        // "-flight NH6" opens the trip on NH 6 from Narita (the Haneda → Narita transfer).
        if let index = arguments.firstIndex(of: "-flight"), arguments.indices.contains(index + 1), arguments[index + 1] == "NH6" {
            store.beginEditingFlight()
            store.flightDraft.number = "NH 6"
            store.saveFlightDraft()
        }
        var gateUpdateDelay: Double? = 45
        if let index = arguments.firstIndex(of: "-gateUpdate"), arguments.indices.contains(index + 1) {
            gateUpdateDelay = Double(arguments[index + 1])
        }
        if let gateUpdateDelay { store.startSampleFeed(after: .seconds(gateUpdateDelay)) }
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.refreshWalkingSpeed() }
                #if DEBUG && targetEnvironment(simulator)
                .task { await IndoorReplayQA.run(arguments: ProcessInfo.processInfo.arguments, store: store) }
                #endif
        }
    }
}
