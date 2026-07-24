import SwiftUI

private enum ARWalkPreviewPolicy {
    /// Fast enough to demonstrate changing guidance without skipping the text
    /// a tester needs to verify. This affects only explicit QA preview launches.
    static let stepInterval = Duration.seconds(2)
    /// Two readings per graph edge show motion between landmarks without
    /// inventing an indoor GPS precision claim.
    static let samplesPerSegment = 2
    static let sampleIntervalSeconds: TimeInterval = 2
    static let externalFeedPollInterval = Duration.milliseconds(500)
}

struct ARGuideView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var viewModel: LongHaulExperienceViewModel
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sessionManager = ARSessionManager()
    @StateObject private var coreLocationQA = CoreLocationIndoorQAService()
    @State private var isSimulatedWalkRunning = false
    @State private var simulatedReadings: [IndoorLocationReading] = []
    @State private var simulatedReadingIndex = 0
    @State private var externalReading: IndoorLocationReading?
    @State private var externalFeedStatus = "Waiting for indoor position"

    var body: some View {
        Group {
            if let layover = viewModel.activeLayover, layover.isInterAirportTransfer {
                outdoorGuide(
                    title: "Transfer to \(layover.onwardAirport.iata)",
                    subtitle: "Follow your selected coach, rail, or road route.",
                    symbol: "arrow.triangle.swap",
                    actionTitle: "Open transfer plan"
                )
            } else if let place = cityGuidePlace {
                outdoorGuide(
                    title: place.name,
                    subtitle: "Follow the route to your selected stop.",
                    symbol: "building.2.fill",
                    actionTitle: "Open stop plan"
                )
            } else if viewModel.activeGate == nil {
                ContentUnavailableView(
                    "Gate not available",
                    systemImage: "questionmark.diamond.fill",
                    description: Text("Check the airport display, then refresh your flight.")
                )
            } else if viewModel.terminalRoute == nil {
                ContentUnavailableView(
                    "Terminal route unavailable",
                    systemImage: "map.fill",
                    description: Text("This gate isn't on the terminal map yet.")
                )
            } else {
                guide
            }
        }
        .navigationTitle("AR Guide")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel.launchContext.usesSimulatedTerminalWalk {
                if viewModel.launchContext.externalIndoorSignalURL == nil,
                   !viewModel.launchContext.usesCoreLocationIndoorQA {
                    prepareSimulatedWalk()
                    isSimulatedWalkRunning = true
                }
            }
        }
    }

    private var cityGuidePlace: LayoverPlace? {
        guard let place = viewModel.selectedCandidate?.place,
              place.accessZone == .nearby || place.accessZone == .city else { return nil }
        return place
    }

    private func outdoorGuide(
        title: String,
        subtitle: String,
        symbol: String,
        actionTitle: String
    ) -> some View {
        ZStack(alignment: .top) {
            ARViewContainer(
                sessionManager: sessionManager,
                indicator: .forward,
                largeIndicators: preferences.accessibility.largerARIndicators
            )
            .ignoresSafeArea(edges: .bottom)
            .accessibilityHidden(true)

            LinearGradient(colors: [.black.opacity(0.62), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
                .allowsHitTesting(false)

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AR CITY GUIDE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.teal)
                        Text(title).font(.title2.bold())
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

                Spacer()

                Button {
                    container.selectedTab = .transit
                } label: {
                    Label(actionTitle, systemImage: "map.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)

                Label("Keep your phone down while walking.", systemImage: "eye.fill")
                    .font(.caption)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
            }
            .padding()
        }
        .accessibilityIdentifier("arOutdoorGuide")
    }

    private var guide: some View {
        ZStack(alignment: .top) {
            Text("AR Guide")
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier("arGuideView")

            ARViewContainer(
                sessionManager: sessionManager,
                indicator: relativeIndicator,
                largeIndicators: preferences.accessibility.largerARIndicators
            )
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)

            LinearGradient(colors: [.black.opacity(0.62), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 210)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                if !viewModel.launchContext.usesSimulatedTerminalWalk {
                    LaunchDataModeBanner(context: viewModel.launchContext, freshness: viewModel.freshness)
                }

                maneuverCard
                if viewModel.launchContext.usesSimulatedTerminalWalk {
                    simulatedWalkControls
                    mapFallbackButton
                }
                Spacer()
                if viewModel.launchContext.usesAutomatedWalkthrough {
                    Label("Look up while walking.", systemImage: "eye.fill")
                        .font(.caption)
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                } else {
                    controls
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
        .animation(reduceMotion ? nil : .easeInOut, value: viewModel.currentNodeID)
        .task(id: isSimulatedWalkRunning) {
            guard isSimulatedWalkRunning,
                  viewModel.launchContext.externalIndoorSignalURL == nil else { return }
            while !Task.isCancelled, isSimulatedWalkRunning {
                try? await Task.sleep(for: ARWalkPreviewPolicy.stepInterval)
                guard !Task.isCancelled, isSimulatedWalkRunning else { break }
                if !advanceSimulatedWalk() {
                    isSimulatedWalkRunning = false
                }
            }
        }
        .task(id: viewModel.launchContext.externalIndoorSignalURL) {
            guard let endpoint = viewModel.launchContext.externalIndoorSignalURL,
                  let client = try? LocalIndoorSignalFeedClient(endpoint: endpoint) else { return }
            while !Task.isCancelled {
                do {
                    let reading = try await client.latestReading()
                    externalReading = reading
                    externalFeedStatus = "Indoor position connected"
                    applyExternalReading(reading)
                } catch {
                    externalFeedStatus = "Waiting for indoor position"
                }
                try? await Task.sleep(for: ARWalkPreviewPolicy.externalFeedPollInterval)
            }
        }
        .task(id: viewModel.launchContext.usesCoreLocationIndoorQA) {
            guard viewModel.launchContext.usesCoreLocationIndoorQA else { return }
            coreLocationQA.start(graph: viewModel.terminalGraph)
        }
        .onChange(of: coreLocationQA.reading) { _, reading in
            guard let reading else { return }
            applyExternalReading(reading)
        }
        .onDisappear {
            if viewModel.launchContext.usesCoreLocationIndoorQA {
                coreLocationQA.stop()
            }
        }
    }

    private var maneuverCard: some View {
        let maneuver = viewModel.currentManeuver
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(maneuver?.instruction ?? "Confirm your location").font(.title.bold())
                Text(maneuver.map { "\($0.destinationName) • \(Int($0.distanceMeters.rounded())) m" } ?? "Open the map and choose a known landmark")
                Text(maneuver.map { "Step \($0.stepNumber) of \($0.stepCount) • \(viewModel.routeMode.title)" } ?? viewModel.routeMode.title)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: maneuver?.systemImage ?? "location.slash")
                .font(.system(size: preferences.accessibility.largerARIndicators ? 42 : 32, weight: .bold))
                .foregroundStyle(.teal)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(maneuverAccessibilityLabel)
                .accessibilityIdentifier("arManeuverCard")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(maneuverAccessibilityLabel)
    }

    private var maneuverAccessibilityLabel: String {
        viewModel.currentManeuver.map {
            "\($0.instruction) in \(Int($0.distanceMeters.rounded())) meters. Step \($0.stepNumber) of \($0.stepCount)."
        } ?? "Location is not confirmed. Use the terminal map."
    }

    private var relativeIndicator: RouteEntityKind {
        guard let maneuver = viewModel.currentManeuver else { return .warning }
        return switch maneuver.kind {
        case .depart: .forward
        case .continueStraight: .continueStraight
        case .slightLeft: .slightLeft
        case .left: .left
        case .sharpLeft: .sharpLeft
        case .slightRight: .slightRight
        case .right: .right
        case .sharpRight: .sharpRight
        case .uTurn: .uTurn
        case .elevator: .elevator
        case .escalator: .escalator
        case .levelChange: .stairs
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Label(sessionManager.trackingLabel, systemImage: sessionManager.isSupported ? "location.viewfinder" : "iphone.and.arrow.forward")
                .font(.caption.weight(.medium))
            Label("Set your location for turn-by-turn directions.", systemImage: "location.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    sessionManager.isPaused ? sessionManager.resume() : sessionManager.pause()
                } label: {
                    Label(sessionManager.isPaused ? "Resume" : "Pause", systemImage: sessionManager.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                Button {
                    sessionManager.recenter()
                } label: {
                    Label("Recenter", systemImage: "scope").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            mapFallbackButton

            Label("Look up while walking.", systemImage: "eye.fill")
                .font(.caption).foregroundStyle(.secondary)

            DisclosureGroup("Route steps") {
                RouteStepList(graph: viewModel.terminalGraph, route: viewModel.terminalRoute)
            }
            .font(.subheadline)
        }
        .padding(14)
        .background(.regularMaterial)
        .accessibilityAction(named: "Return to Gate") {
            container.returnToGate()
        }
    }

    private var mapFallbackButton: some View {
        Button {
            container.selectedTab = .terminalMap
            dismiss()
        } label: {
            Label("Open accessible directions", systemImage: "list.bullet.rectangle.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.teal)
        .accessibilityIdentifier("arMapFallbackButton")
    }

    private var simulatedWalkControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                isExternallyDrivenWalk ? "Indoor position" : "Route preview",
                systemImage: "figure.walk.motion"
            )
                .font(.subheadline.bold())
            Text(simulatedPositionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("simulatedWalkPosition")
            if isExternallyDrivenWalk {
                Label(
                    externalSignalStatus,
                    systemImage: currentSimulatedReading == nil ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(externalReading == nil ? .orange : .green)
                .accessibilityIdentifier("externalIndoorSignalStatus")
            } else {
                HStack(spacing: 10) {
                    Button {
                        if simulatedReadingIndex >= simulatedReadings.count - 1 {
                            prepareSimulatedWalk()
                        }
                        isSimulatedWalkRunning.toggle()
                    } label: {
                        Label(
                            isSimulatedWalkRunning ? "Stop" : "Start walking",
                            systemImage: isSimulatedWalkRunning ? "stop.fill" : "play.fill"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("simulatedWalkToggle")

                    Button {
                        isSimulatedWalkRunning = false
                        _ = advanceSimulatedWalk()
                    } label: {
                        Label("Next point", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.currentManeuver == nil)
                    .accessibilityIdentifier("simulatedWalkNextPoint")
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("simulatedWalkControls")
    }

    private var currentNodeName: String {
        let nodeID = currentSimulatedReading?.matchedNodeID ?? viewModel.currentNodeID
        return viewModel.terminalGraph.nodes.first(where: { $0.id == nodeID })?.name ?? "Unknown"
    }

    private var simulatedPositionLabel: String {
        guard let reading = currentSimulatedReading else { return "Position unavailable" }
        return "Position: \(currentNodeName) · Level \(reading.level)"
    }

    private var currentSimulatedReading: IndoorLocationReading? {
        if viewModel.launchContext.usesCoreLocationIndoorQA { return coreLocationQA.reading }
        if let externalReading { return externalReading }
        guard simulatedReadings.indices.contains(simulatedReadingIndex) else { return nil }
        return simulatedReadings[simulatedReadingIndex]
    }

    private var isExternallyDrivenWalk: Bool {
        viewModel.launchContext.externalIndoorSignalURL != nil
            || viewModel.launchContext.usesCoreLocationIndoorQA
    }

    private var externalSignalStatus: String {
        viewModel.launchContext.usesCoreLocationIndoorQA ? coreLocationQA.status : externalFeedStatus
    }

    private func prepareSimulatedWalk() {
        viewModel.restartRoutePreview()
        guard let route = viewModel.terminalRoute else {
            simulatedReadings = []
            simulatedReadingIndex = 0
            return
        }
        simulatedReadings = TerminalRouteLocationEmulator(
            graph: viewModel.terminalGraph,
            route: route
        ).readings(
            samplesPerSegment: ARWalkPreviewPolicy.samplesPerSegment,
            startingAt: Date(),
            sampleInterval: ARWalkPreviewPolicy.sampleIntervalSeconds
        )
        simulatedReadingIndex = 0
        applyCurrentSimulatedReading()
    }

    @discardableResult
    private func advanceSimulatedWalk() -> Bool {
        let nextIndex = simulatedReadingIndex + 1
        guard simulatedReadings.indices.contains(nextIndex) else { return false }
        simulatedReadingIndex = nextIndex
        applyCurrentSimulatedReading()
        return true
    }

    private func applyCurrentSimulatedReading() {
        guard let reading = currentSimulatedReading,
              reading.matchedNodeID != viewModel.currentNodeID else { return }
        viewModel.calibrateLocation(to: reading.matchedNodeID)
    }

    private func applyExternalReading(_ reading: IndoorLocationReading) {
        guard reading.source == .externalSignalReplay || reading.source == .coreLocationReplay,
              viewModel.terminalGraph.nodes.contains(where: { $0.id == reading.matchedNodeID }) else { return }
        viewModel.calibrateLocation(to: reading.matchedNodeID)
    }
}

struct RouteStepList: View {
    let graph: TerminalGraph
    let route: TerminalRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array((route?.nodeIDs.dropLast() ?? []).enumerated()), id: \.element) { _, id in
                if let maneuver = RouteManeuverBuilder().currentManeuver(
                    graph: graph,
                    route: route,
                    currentNodeID: id
                ) {
                    Label(
                        "\(maneuver.stepNumber). \(maneuver.instruction) · \(Int(maneuver.distanceMeters.rounded())) m",
                        systemImage: maneuver.systemImage
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

}
