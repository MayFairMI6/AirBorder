import SwiftUI

@main
struct AirBorderApp: App {
    @StateObject private var container = AppContainer()
    @State private var isPreparingJourney = true
    private let forceAccessibilityText = ProcessInfo.processInfo.arguments.contains("--qa-accessibility-xxxl")

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .opacity(isPreparingJourney ? 0 : 1)

                if isPreparingJourney {
                    ContentUnavailableView(
                        "Preparing your journey",
                        systemImage: "airplane.circle.fill",
                        description: Text("Checking your itinerary and travel options."))
                }
            }
            .modifier(QAAccessibilityTextModifier(enabled: forceAccessibilityText))
            .environmentObject(container)
            .environmentObject(container.flightsViewModel)
            .environmentObject(container.longHaulViewModel)
            .environmentObject(container.preferences)
            .environmentObject(container.crossDeviceReminders)
            .environmentObject(container.networkMonitor)
            .task {
                // Let SwiftUI present the loading state before the first
                // itinerary calculation begins on the main actor.
                await Task.yield()
                await container.start()
                isPreparingJourney = false
            }
            .onOpenURL { container.handle($0) }
        }
    }
}

private struct QAAccessibilityTextModifier: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.dynamicTypeSize(.accessibility5)
        } else {
            content
        }
    }
}
