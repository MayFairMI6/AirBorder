import SwiftUI

struct JourneyDashboardView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var viewModel: LongHaulExperienceViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let itinerary = viewModel.itinerary {
                dashboard(itinerary)
            } else {
                ContentUnavailableView(
                    "No itinerary",
                    systemImage: "airplane",
                    description: Text("Add a flight from Flights to begin.")
                )
            }
        }
        .navigationTitle("Journey")
        .background(Color(.systemGroupedBackground))
    }

    private func dashboard(_ itinerary: Itinerary) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                LaunchDataModeBanner(context: viewModel.launchContext, freshness: viewModel.freshness)

                activeLayoverHero

                itineraryTimeline(itinerary)

                ticketTransitOverview

                layoverOverview

                weatherCards

                delayOutlookCard

                Button {
                    container.selectedTab = viewModel.requiresInterAirportTransfer ? .transit : .terminalMap
                } label: {
                    if let layover = viewModel.activeLayover, layover.isInterAirportTransfer {
                        primaryActionLabel(
                            "Start \(layover.airport.iata) → \(layover.onwardAirport.iata) transfer",
                            systemImage: "arrow.left.arrow.right.circle.fill"
                        )
                    } else {
                        primaryActionLabel(
                            "Go to Gate \(viewModel.activeGate ?? "—")",
                            systemImage: "figure.walk.motion"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AirportXRPalette.actionTeal)
                .disabled(!viewModel.requiresInterAirportTransfer && viewModel.activeGate == nil)
                .accessibilityHint(viewModel.requiresInterAirportTransfer
                    ? "Opens your airport transfer route."
                    : "Opens directions to your departure gate.")
                .accessibilityIdentifier("goToGateButton")

                actionGrid

                if let message = viewModel.statusMessage {
                    InlineNotice(message: message)
                }

            }
            .padding()
        }
        .refreshable { await viewModel.refreshAllLegs() }
        .task(id: viewModel.activeAirport?.iata) {
            await viewModel.refreshWeather()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await viewModel.refreshWeather()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: AirportXRLayout.floatingTabBarClearance)
        }
        .accessibilityIdentifier("longHaulJourneyDashboard")
    }

    private var activeLayoverHero: some View {
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ACTIVE LAYOVER")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AirportXRPalette.actionTeal)
                        Text(activeLayoverTitle)
                            .font(.title2.bold())
                    }
                    Spacer()
                    Text(activeLayoverBadge)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.teal.opacity(0.12), in: Capsule())
                }

                if let layover = viewModel.activeLayover,
                   let minutes = layover.availableWindowMinutes {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) { activeLayoverMetrics(layover: layover, minutes: minutes) }
                    } else {
                        HStack { activeLayoverMetrics(layover: layover, minutes: minutes) }
                    }
                } else {
                    InlineNotice(
                        message: "We don't have enough flight times yet.",
                        symbol: "questionmark.diamond.fill",
                        color: .orange
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activeLayoverCard")
    }

    private var weatherCards: some View {
        VStack(spacing: 12) {
            weatherCard(
                title: "Departure airport weather",
                airportCode: viewModel.activeAirport?.iata,
                metric: viewModel.weatherSummary,
                showsRefresh: true
            )
            if let transfer = viewModel.transferWeatherAirport {
                weatherCard(
                    title: "Transfer airport weather",
                    airportCode: transfer.iata,
                    metric: viewModel.transferWeatherSummary,
                    showsRefresh: true,
                    identifier: "transferWeatherCard"
                )
            }
            if let destination = viewModel.destinationWeatherAirport {
                weatherCard(
                    title: "Final destination weather",
                    airportCode: destination.iata,
                    metric: viewModel.destinationWeatherSummary,
                    showsRefresh: true,
                    identifier: "destinationWeatherCard"
                )
            }
        }
    }

    private func weatherCard(
        title: String,
        airportCode: String?,
        metric: SourcedMetric<String>?,
        showsRefresh: Bool,
        identifier: String? = nil
    ) -> some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "cloud.sun.fill")
                    .font(.title2)
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text(airportCode.map { "\(title) · \($0)" } ?? title).font(.headline)
                    Text(metric?.value ?? "Weather is not available right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let metric {
                        Text("Observed \(relative(metric.observedAt)) · checked \(relative(metric.receivedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if showsRefresh, let message = viewModel.weatherRefreshMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if showsRefresh {
                    Button { Task { await viewModel.refreshWeather(force: true) } } label: {
                        if viewModel.isRefreshingWeather {
                            ProgressView().frame(minWidth: 44, minHeight: 44)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRefreshingWeather)
                    .accessibilityLabel("Refresh weather for \(airportCode ?? "airport")")
                    .accessibilityIdentifier("refreshWeather-\(airportCode ?? "airport")")
                }
            }
        }
        .accessibilityIdentifier(identifier ?? (showsRefresh ? "departureWeatherCard" : "destinationWeatherCard"))
    }

    private func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    private var delayOutlookCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Delay outlook", systemImage: "clock.badge.questionmark.fill")
                    .font(.headline)
                if let outlook = viewModel.delayOutlook,
                   let minutes = outlook.expectedDelayMinutes {
                    Text("About \(minutes) minutes")
                        .font(.title3.bold())
                    Text("Based on past flights on this route in similar airport weather.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not enough similar past flights yet")
                        .font(.title3.bold())
                    Text("More flight history will improve this estimate.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("delayOutlookCard")
    }

    private var activeLayoverTitle: String {
        guard let layover = viewModel.activeLayover else { return "Layover unavailable" }
        if layover.isInterAirportTransfer {
            let region = layover.airportChangeAssessment.metroArea?.name ?? "Surface sector"
            return "\(layover.airport.iata) → \(layover.onwardAirport.iata) · \(region)"
        }
        return "\(layover.airport.iata) · \(layover.airport.name)"
    }

    private var activeLayoverBadge: String {
        guard let layover = viewModel.activeLayover else { return "Gate pending" }
        if layover.isInterAirportTransfer { return "\(layover.onwardAirport.iata) first" }
        return viewModel.activeGate.map { "Gate \($0)" } ?? "Gate pending"
    }

    @ViewBuilder
    private func activeLayoverMetrics(layover: LayoverContext, minutes: Double) -> some View {
        MetricTile(title: "Time before boarding", value: duration(minutes), symbol: "clock.fill")
        MetricTile(
            title: "Current airport",
            value: airportLocalLabel(layover),
            symbol: "globe.asia.australia.fill"
        )
    }

    private func airportLocalLabel(_ layover: LayoverContext) -> String {
        let place = layover.airport.city ?? layover.airport.iata
        let abbreviation = layover.timeZone.abbreviation(for: Date())
        return abbreviation.map { "\(place) · \($0)" } ?? place
    }

    private func itineraryTimeline(_ itinerary: Itinerary) -> some View {
        let displayedLegs = dynamicTypeSize.isAccessibilitySize
            ? Array(itinerary.legs.prefix(1))
            : itinerary.legs
        let remainingLegCount = itinerary.legs.count - displayedLegs.count
        let remainingLegNoun = remainingLegCount == 1 ? "leg" : "legs"

        return SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YOUR TRIP")
                            .font(.caption2.bold())
                            .foregroundStyle(AirportXRPalette.actionTeal)
                        Text("\(itinerary.legs.first?.flight.origin.city ?? itinerary.legs.first?.flight.origin.iata ?? "Departure") to \(itinerary.legs.last?.flight.destination.city ?? itinerary.legs.last?.flight.destination.iata ?? "destination")")
                            .font(.title3.bold())
                    }
                    Spacer()
                    Text("\(itinerary.legs.count) \(itinerary.legs.count == 1 ? "flight" : "flights")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(displayedLegs.enumerated()), id: \.element.id) { index, leg in
                    if index > 0 { Divider() }
                    AirlineFlightSummary(
                        flight: leg.flight,
                        legNumber: index + 1,
                        legCount: itinerary.legs.count
                    )
                    if index < itinerary.legs.count - 1 {
                        let next = itinerary.legs[index + 1]
                        if leg.flight.destination.iata != next.flight.origin.iata {
                            Label(
                                "Change airports: \(leg.flight.destination.iata) → \(next.flight.origin.iata)",
                                systemImage: "arrow.left.arrow.right.circle.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.leading, 24)
                        }
                    }
                }
                if remainingLegCount > 0 {
                    Button {
                        container.selectedTab = .flights
                    } label: {
                        Label(
                            "View \(remainingLegCount) remaining \(remainingLegNoun) in Flights",
                            systemImage: "list.bullet.rectangle"
                        )
                        .font(.body.weight(.semibold))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: AirportXRLayout.minimumTouchTarget)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Opens the complete editable itinerary.")
                }
            }
        }
        .accessibilityIdentifier("itineraryTimeline")
    }

    @ViewBuilder
    private var ticketTransitOverview: some View {
        if let scan = viewModel.ticketScanResult {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("TICKET & TRANSIT")
                                .font(.caption2.bold())
                                .foregroundStyle(AirportXRPalette.actionTeal)
                            Text("From \(scan.fileName)")
                                .font(.headline)
                        }
                        Spacer()
                        Text(scan.scannedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.ticketConnectionStatuses.isEmpty {
                        Text("Add at least two flights to compare your ticket with the itinerary.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.ticketConnectionStatuses) { status in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: status.baggageAssessment.state.journeySymbol)
                                        .foregroundStyle(status.baggageAssessment.state.journeyColor)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(status.connectionLabel)
                                            .font(.subheadline.weight(.semibold))
                                        Text(status.baggageAssessment.advisory)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: status.transitStatus.journeySymbol)
                                        .foregroundStyle(status.transitStatus.journeyColor)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(status.transitStatus.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(status.transitStatus.message)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if status.id != viewModel.ticketConnectionStatuses.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }

                    Button {
                        container.selectedTab = .flights
                    } label: {
                        Label("Review ticket details", systemImage: "suitcase.rolling.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .accessibilityIdentifier("ticketTransitOverviewCard")
        }
    }

    private func primaryActionLabel(_ title: String, systemImage: String) -> some View {
        let layout: AnyLayout = dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 10))

        return layout {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: AirportXRLayout.primaryActionMinimumHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var layoverOverview: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Your layover plan", systemImage: "checklist.checked")
                    .font(.headline)
                if let candidate = viewModel.selectedCandidate,
                   let assessment = viewModel.selectedAssessment {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.title).font(.title3.bold())
                            Text(candidate.place?.accessZone.title ?? "Airport plan")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        FeasibilityPill(status: assessment.status)
                    }
                    Text(assessment.summary).font(.subheadline)
                    NavigationLink {
                        CalculationTraceView(candidate: candidate, assessment: assessment)
                    } label: {
                        Label("Plan details", systemImage: "info.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("whyRecommendationButton")
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) { feedbackActions(candidate: candidate) }
                    } else {
                        HStack(spacing: 8) { feedbackActions(candidate: candidate) }
                    }
                } else {
                    Text("We need a few more trip details before we can suggest a plan.")
                }
            }
        }
        .accessibilityIdentifier("layoverOverviewCard")
    }

    private var actionGrid: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 10) {
            action("Airport services", "building.2.fill") {
                viewModel.selectedZone = .airside
                viewModel.selectedCategories = []
                container.selectedTab = .transit
            }
            action("Landside work pods", "laptopcomputer") {
                viewModel.selectedZone = .airportLandside
                viewModel.selectedCategories = [.workPod]
                container.selectedTab = .transit
            }
            action("Meeting-ready space", "video.fill") {
                viewModel.selectedZone = .airside
                viewModel.selectedCategories = [.workPod, .lounge, .charging]
                container.selectedTab = .transit
            }
            action("Plan B: stay near gate", "shield.checkered") {
                viewModel.selectedZone = .airside
                viewModel.selectedCategories = [.facility, .food]
                container.selectedTab = .transit
            }
            NavigationLink {
                EntryCheckView()
            } label: {
                actionLabel("Entry check", "person.text.rectangle")
            }
            .buttonStyle(.plain)
            NavigationLink {
                InFlightProgressView()
            } label: {
                actionLabel("In-flight progress", "airplane.circle.fill")
            }
            .buttonStyle(.plain)
            action("Nearby & city", "tram.fill") {
                viewModel.selectedZone = .nearby
                viewModel.selectedCategories = []
                container.selectedTab = .transit
            }
            action("AR guide", "viewfinder") {
                container.selectedTab = .arGuide
            }
        }
    }

    private func action(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { actionLabel(title, symbol) }
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private func feedbackActions(candidate: PlanCandidate) -> some View {
        Button {
            Task { await viewModel.recordCandidateFeedback(candidateID: candidate.id, accepted: true) }
        } label: {
            Label("Use this plan", systemImage: "checkmark.circle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.teal)
        Button {
            Task { await viewModel.recordCandidateFeedback(candidateID: candidate.id, accepted: false) }
        } label: {
            Label("Not for me", systemImage: "hand.thumbsdown")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)) }
    }

    private func duration(_ minutes: Double) -> String {
        let whole = max(0, Int(minutes.rounded(.down)))
        return "\(whole / 60)h \(whole % 60)m"
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private extension ConnectionBaggageState {
    var journeySymbol: String {
        switch self {
        case .throughChecked: "checkmark.circle.fill"
        case .reclaimImmigrationCustomsRecheck: "suitcase.cart.fill"
        case .selfTransferSeparateTicket: "exclamationmark.triangle.fill"
        case .confirmationRequired, .unknown: "questionmark.circle.fill"
        }
    }

    var journeyColor: Color {
        switch self {
        case .throughChecked: .green
        case .reclaimImmigrationCustomsRecheck: .blue
        case .selfTransferSeparateTicket, .confirmationRequired, .unknown: .orange
        }
    }
}

private extension TicketTransitStatus {
    var journeySymbol: String {
        switch self {
        case .current: "checkmark.shield.fill"
        case .mayNeedAuthorization, .conditional: "person.text.rectangle.fill"
        case .addTravelerDetails: "person.crop.circle.badge.plus"
        case .refreshNeeded: "arrow.clockwise.circle.fill"
        case .notEnoughInformation: "questionmark.circle.fill"
        }
    }

    var journeyColor: Color {
        switch self {
        case .current: .green
        case .mayNeedAuthorization, .conditional, .addTravelerDetails, .refreshNeeded, .notEnoughInformation: .orange
        }
    }
}

struct CalculationTraceView: View {
    let candidate: PlanCandidate
    let assessment: FeasibilityAssessment
    @StateObject private var onDeviceExplanation = FoundationModelExplanationService()

    var body: some View {
        List {
            Section {
                HStack {
                    Text(candidate.title).font(.headline)
                    Spacer()
                    FeasibilityPill(status: assessment.status)
                }
                Text(assessment.summary).font(.subheadline)
            }
            Section("Your timing") {
                LabeledContent("Connection time", value: minutes(assessment.availableWindowMinutes))
                LabeledContent("Plan time", value: minutes(assessment.requiredMostLikelyMinutes))
                LabeledContent("Return by", value: assessment.latestReturnTime?.formatted(date: .abbreviated, time: .shortened) ?? "Check your flight details")
            }
            if !assessment.trace.unresolvedInputs.isEmpty {
                Section("Before you go") {
                    Label("Check your latest arrival, boarding, and airport information before leaving the terminal.", systemImage: "questionmark.circle.fill")
                }
            }
        }
        .navigationTitle("Plan details")
        .accessibilityIdentifier("calculationTraceView")
    }

    private func minutes(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) min" } ?? "Unknown"
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
