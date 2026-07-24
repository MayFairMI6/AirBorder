import SwiftUI
import UIKit

private enum WalkthroughTiming {
    /// Five seconds lets a viewer read a compact card. AR gets two intervals so
    /// at least two mapped position changes are visible before the next screen.
    static let screenInterval = Duration.seconds(5)
    static let arInterval = Duration.seconds(10)
}

private struct WalkthroughStep {
    let title: String
    let detail: String
    let tab: AppTab
    let interval: Duration

    static let all: [WalkthroughStep] = [
        .init(title: "Journey", detail: "Flights, layover, weather, and delay outlook", tab: .journey, interval: WalkthroughTiming.screenInterval),
        .init(title: "Layover & Transit", detail: "Facilities, city plans, transfers, and costs", tab: .transit, interval: WalkthroughTiming.screenInterval),
        .init(title: "Flights", detail: "Itinerary, baggage handling, and flight search", tab: .flights, interval: WalkthroughTiming.screenInterval),
        .init(title: "Terminal map", detail: "Route steps, landmarks, nearby needs, and shops", tab: .terminalMap, interval: WalkthroughTiming.screenInterval),
        .init(title: "AR route guidance", detail: "Optional turn guidance after you choose a route", tab: .arGuide, interval: WalkthroughTiming.arInterval),
        .init(title: "Traveler details", detail: "Adding country and document details", tab: .settings, interval: WalkthroughTiming.screenInterval),
        .init(title: "Preferences", detail: "Adding budget, recovery, and accessibility needs", tab: .settings, interval: WalkthroughTiming.screenInterval),
        .init(title: "Walkthrough complete", detail: "Use any tab or restart the tour", tab: .journey, interval: WalkthroughTiming.screenInterval)
    ]
}

struct RootTabView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var showsGateRoute = false
    @State private var walkthroughIndex = 0
    @State private var isWalkthroughRunning = false
    @State private var showsWalkthrough = true

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $container.selectedTab) {
            tabRoot { JourneyDashboardView() }
                .tabItem { Label("Journey", systemImage: "airplane.departure") }
                .tag(AppTab.journey)

            tabRoot { TransitView() }
                .tabItem { Label("Layover", systemImage: "clock.badge.checkmark") }
                .tag(AppTab.transit)

            tabRoot { FlightsView() }
                .tabItem { Label("Flights", systemImage: "magnifyingglass") }
                .tag(AppTab.flights)

            tabRoot { TerminalMapView(graph: container.terminalGraph) }
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(AppTab.terminalMap)

            tabRoot { ARGuideView() }
                .tabItem { Label("AR Route", systemImage: "viewfinder") }
                .tag(AppTab.arGuide)

            tabRoot { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(AirportXRPalette.actionTeal)
        // Keep route text from showing through the floating tab-bar material.
        // At accessibility text sizes that underlap reduces the contrast of the
        // tab labels even though their own foreground colors are compliant.
        .toolbarBackground(Color(.systemBackground), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .fullScreenCover(isPresented: $showsGateRoute) {
            NavigationStack {
                Group {
                    if container.longHaulViewModel.requiresInterAirportTransfer {
                        TransitView()
                    } else {
                        ARGuideView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { showsGateRoute = false }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if container.launchContext.usesAutomatedWalkthrough, showsWalkthrough {
                walkthroughBanner
            }
        }
        .task {
            guard container.launchContext.usesAutomatedWalkthrough else { return }
            walkthroughIndex = 0
            showsWalkthrough = true
            isWalkthroughRunning = true
            await applyWalkthroughStep()
        }
        .task(id: isWalkthroughRunning) {
            guard container.launchContext.usesAutomatedWalkthrough, isWalkthroughRunning else { return }
            while !Task.isCancelled, isWalkthroughRunning {
                let step = WalkthroughStep.all[walkthroughIndex]
                try? await Task.sleep(for: step.interval)
                guard !Task.isCancelled, isWalkthroughRunning else { break }
                await advanceWalkthrough()
            }
        }
    }

    private func tabRoot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack { content() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ReturnToGateButton {
                    showsGateRoute = true
                }
            }
    }

    private var walkthroughBanner: some View {
        let step = WalkthroughStep.all[walkthroughIndex]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tour \(walkthroughIndex + 1) of \(WalkthroughStep.all.count)")
                    .font(.caption.bold())
                    .foregroundStyle(AirportXRPalette.actionTeal)
                Spacer()
                Button("Close") {
                    isWalkthroughRunning = false
                    showsWalkthrough = false
                }
                .font(.caption.bold())
            }
            Text(step.title).font(.headline)
            Text(step.detail).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(isWalkthroughRunning ? "Pause" : "Resume") {
                    isWalkthroughRunning.toggle()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("walkthroughPauseButton")
                Button(walkthroughIndex == WalkthroughStep.all.count - 1 ? "Restart" : "Next") {
                    Task {
                        if walkthroughIndex == WalkthroughStep.all.count - 1 {
                            walkthroughIndex = 0
                            isWalkthroughRunning = true
                            await applyWalkthroughStep()
                        } else {
                            await advanceWalkthrough()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("walkthroughNextButton")
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            ProgressView(value: Double(walkthroughIndex + 1), total: Double(WalkthroughStep.all.count))
                .tint(AirportXRPalette.actionTeal)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("automatedWalkthroughBanner")
    }

    private func advanceWalkthrough() async {
        guard walkthroughIndex < WalkthroughStep.all.count - 1 else {
            isWalkthroughRunning = false
            return
        }
        walkthroughIndex += 1
        await applyWalkthroughStep()
        if walkthroughIndex == WalkthroughStep.all.count - 1 {
            isWalkthroughRunning = false
        }
    }

    private func applyWalkthroughStep() async {
        let step = WalkthroughStep.all[walkthroughIndex]
        container.selectedTab = step.tab

        if walkthroughIndex == 5 {
            var profile = TravelerProfile.minimalDemo
            profile.purpose = .tourism
            profile.luggage = .checkedThrough
            await container.longHaulViewModel.updateTravelerProfile(profile)
        } else if walkthroughIndex == 6 {
            var profile = container.longHaulViewModel.travelerProfile
            profile.budget = .economy
            profile.recoveryPreference = .balance
            profile.accessibilityNeeds = "Prefer elevators and shorter walks"
            await container.longHaulViewModel.updateTravelerProfile(profile)
        }
    }
}

private struct ReturnToGateButton: View {
    @EnvironmentObject private var viewModel: LongHaulExperienceViewModel
    let action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let urgency = GateUrgency.assess(
                latestReturn: viewModel.selectedAssessment?.latestReturnTime,
                requiresAirportTransfer: viewModel.requiresInterAirportTransfer,
                now: viewModel.currentTime
            )
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: urgency.symbol)
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.gateStatus.hasGateChange ? "Gate changed" : title(for: urgency))
                            .font(.headline)
                        Text(detail(for: urgency))
                            .font(.caption.weight(.medium))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(urgency.color)
            .accessibilityLabel(viewModel.gateStatus.hasGateChange
                ? "Gate changed from \(viewModel.gateStatus.previousGate ?? "unknown") to \(viewModel.gateStatus.gate ?? "unknown")"
                : title(for: urgency))
            .accessibilityValue(detail(for: urgency))
            .accessibilityHint(viewModel.requiresInterAirportTransfer
                ? "Opens the airport transfer route."
                : "Opens directions to your departure gate.")
            .accessibilityIdentifier("universalReturnToGateButton")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func detail(for urgency: GateUrgency) -> String {
        let status = viewModel.gateStatus
        if status.hasGateChange {
            return "\(status.previousGate ?? "—") → \(status.gate ?? "pending") · \(walkText(status))"
        }
        let destination = viewModel.requiresInterAirportTransfer
            ? "Proceed to next airport"
            : "Gate \(status.gate ?? "pending")"
        guard let latestReturn = viewModel.selectedAssessment?.latestReturnTime else {
            if viewModel.requiresInterAirportTransfer {
                if viewModel.selectedCandidate?.intent == .transferRouteStop {
                    return "Confirm transfer steps before your stop"
                }
                return "Review the HND to NRT transfer plan before setting a leave-by time"
            }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let boarding = status.boardingTime.map { "Board \(formatter.string(from: $0))" } ?? "Boarding pending"
            return "\(destination) · \(walkText(status)) · \(boarding) · Leave-by pending"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let boarding = status.boardingTime.map { "Board \(formatter.string(from: $0))" } ?? "Boarding pending"
        return "\(destination) · \(walkText(status)) · \(boarding) · \(urgency.detailPrefix) \(formatter.string(from: latestReturn))"
    }

    private func walkText(_ status: GateStatusSnapshot) -> String {
        status.walkMinutes.map { "\($0)-min walk" } ?? "Walk time pending"
    }

    private func title(for urgency: GateUrgency) -> String {
        guard urgency == .pending else { return urgency.title }
        if viewModel.selectedCandidate?.intent == .transferRouteStop {
            return "Review recommended stop"
        }
        return viewModel.requiresInterAirportTransfer
            ? "Review airport transfer"
            : "Set return plan"
    }
}

private enum GateUrgency {
    case comfortable
    case prepare
    case leaveNow
    case pending

    static func assess(latestReturn: Date?, requiresAirportTransfer: Bool, now: Date) -> GateUrgency {
        guard let latestReturn else { return .pending }
        let minutes = latestReturn.timeIntervalSince(now) / 60
        if minutes <= 0 { return .leaveNow }
        if minutes <= (requiresAirportTransfer ? 30 : 15) { return .prepare }
        return .comfortable
    }

    var title: String {
        switch self {
        case .comfortable: "Return plan is on track"
        case .prepare: "Prepare to leave"
        case .leaveNow: "Return now"
        case .pending: "Gate route ready"
        }
    }

    var detailPrefix: String {
        switch self {
        case .comfortable: "Leave by"
        case .prepare: "Leave by"
        case .leaveNow: "Deadline was"
        case .pending: ""
        }
    }

    var symbol: String {
        switch self {
        case .comfortable: "checkmark.circle.fill"
        case .prepare: "exclamationmark.circle.fill"
        case .leaveNow: "figure.walk.motion"
        case .pending: "arrow.triangle.swap"
        }
    }

    var color: Color {
        switch self {
        case .comfortable: .green
        case .prepare: .orange
        case .leaveNow: .red
        case .pending: AirportXRPalette.actionTeal
        }
    }
}
