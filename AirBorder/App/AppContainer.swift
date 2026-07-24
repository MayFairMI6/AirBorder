import Foundation

enum AppTab: Hashable, Sendable {
    case journey
    case flights
    case arGuide
    case terminalMap
    case transit
    case settings
}

@MainActor
final class AppContainer: ObservableObject {
    @Published var selectedTab: AppTab = .journey

    let configuration: AppConfiguration
    let launchContext: AppLaunchContext
    let preferences: PreferencesStore
    let networkMonitor: NetworkMonitor
    let flightsViewModel: FlightsViewModel
    let predictor: OnDevicePredictionService
    let longHaulViewModel: LongHaulExperienceViewModel
    let crossDeviceReminders: CrossDeviceReminderCoordinator
    private let notificationScheduler = SystemNotificationScheduler()
    let backgroundJourneyMonitor: BackgroundJourneyMonitor
    let terminalGraph = SampleTerminalGraph.hanedaTerminal3Demo
    private let entryRequirementCache: EntryRequirementCache
    private let flightCache: FlightCache

    private(set) var started = false

    init() {
        let configuration = AppConfiguration.load()
        let launchContext = AppLaunchContext.current()
        if launchContext.qaTrafficLevel != nil {
            selectedTab = .terminalMap
        }
        let preferences = PreferencesStore()
        let networkMonitor = NetworkMonitor()
        let cache = FlightCache()
        let predictor = OnDevicePredictionService(learningEnabled: preferences.personalizedPredictionsEnabled)
        let crossDeviceReminders = CrossDeviceReminderCoordinator(preferences: preferences)
        // Bundled scenarios are available only to an explicit UI-test launch.
        // Normal live/offline launches never inject fixture providers.
        let usesNamedDemoFixture = launchContext.isUITest
            && (launchContext.mode == .demo || launchContext.mode == .stochastic)

        var providers: [any FlightDataProvider] = []
        if launchContext.mode == .live, let url = configuration.aviationProxyBaseURL {
            providers.append(ProxyFlightDataProvider(baseURL: url, providerName: configuration.aviationProviderLabel))
        }
        // Demo data is opt-in by launch mode. A live launch with no proxy must
        // report unavailable rather than silently changing its evidence mode.
        if usesNamedDemoFixture {
            providers.append(DemoFlightDataProvider())
        }

        // Provider learning is default-deny. The repository forwards only a
        // resolved outcome whose source policy and bundled license policy both
        // permit the exact model use. User-owned outcomes remain independent.
        let repository = FlightRepository(providers: providers, cache: cache, predictionLearning: predictor)
        let liveService = LiveFlightService(repository: repository)
        let trafficMultiplier: Double = switch launchContext.qaTrafficLevel {
        case "light": 0.85
        case "heavy": 1.35
        default: 1
        }
        let transferProvider: any InterAirportTransferProvider = usesNamedDemoFixture
            ? TokyoInterAirportDemoTransferProvider(trafficMultiplier: trafficMultiplier)
            : UnavailableInterAirportTransferProvider()
        let fallbackEntry = InformationalEntryRequirementProvider()
        let fallbackFacilities = HNDOfficialFacilityProvider()
        let uncachedEntryProvider: any EntryRequirementProvider
        let facilityProvider: any AirportFacilityProvider
        if launchContext.mode != .offline, let url = configuration.aviationProxyBaseURL {
            uncachedEntryProvider = FallbackEntryRequirementProvider(
                primary: ProxyEntryRequirementProvider(baseURL: url),
                fallback: fallbackEntry
            )
            facilityProvider = FallbackAirportFacilityProvider(
                primary: ProxyAirportFacilityProvider(baseURL: url),
                fallback: fallbackFacilities
            )
        } else {
            uncachedEntryProvider = fallbackEntry
            facilityProvider = fallbackFacilities
        }
        let entryRequirementCache = EntryRequirementCache()
        let entryProvider = CachedEntryRequirementProvider(
            upstream: uncachedEntryProvider,
            cache: entryRequirementCache,
            refreshPolicy: launchContext.mode == .offline ? .cacheOnly : .refreshThenCache
        )
        self.configuration = configuration
        self.launchContext = launchContext
        self.preferences = preferences
        self.networkMonitor = networkMonitor
        self.predictor = predictor
        self.crossDeviceReminders = crossDeviceReminders
        self.backgroundJourneyMonitor = BackgroundJourneyMonitor(scheduler: notificationScheduler)
        self.entryRequirementCache = entryRequirementCache
        self.flightCache = cache
        self.flightsViewModel = FlightsViewModel(
            service: FlightSearchService(repository: repository),
            seedDemoFields: usesNamedDemoFixture
        )
        let qaClock: @Sendable () -> Date = {
            Date().addingTimeInterval(TimeInterval(launchContext.qaClockOffsetMinutes * 60))
        }
        let weatherProvider: any WeatherContextProvider
        if launchContext.isUITest,
           let rawScenario = launchContext.qaWeatherScenario,
           let scenario = QAFixtureWeatherContextProvider.Scenario(rawValue: rawScenario) {
            weatherProvider = QAFixtureWeatherContextProvider(scenario: scenario)
        } else if launchContext.mode == .offline {
            weatherProvider = UnavailableWeatherContextProvider()
        } else {
            weatherProvider = CompositeWeatherContextProvider(
                general: OpenMeteoWeatherContextProvider(),
                aviation: AviationWeatherMETARContextProvider()
            )
        }
        self.longHaulViewModel = LongHaulExperienceViewModel(
            launchContext: launchContext,
            cache: ItineraryCache(),
            entryProvider: entryProvider,
            facilityProvider: facilityProvider,
            recommendationEngine: MonteCarloLayoverRecommendationEngine(),
            placeProvider: MapKitNearbyPlaceProvider(),
            interAirportTransferProvider: transferProvider,
            flightService: liveService,
            preferences: preferences,
            predictor: predictor,
            weatherProvider: weatherProvider,
            terminalGraph: SampleTerminalGraph.hanedaTerminal3Demo,
            now: qaClock,
            fixtureAnchor: { Date() }
        )
        self.longHaulViewModel.reminderInputsDidChange = { [weak self] in
            guard let self else { return }
            let input = self.crossDeviceReminderPlanningInput()
            Task {
                await self.crossDeviceReminders.syncIfEnabled(using: input)
                await self.refreshJourneyAlerts()
            }
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        await longHaulViewModel.start()
        await refreshJourneyAlerts()
    }

    func handle(_ url: URL) {
        guard url.scheme == "airportxr" else { return }
        switch url.host {
        case "guide": selectedTab = .arGuide
        case "map": selectedTab = .terminalMap
        case "flights": selectedTab = .flights
        case "transit": selectedTab = .transit
        default: selectedTab = .journey
        }
    }

    func returnToGate() {
        let destination: AppTab = longHaulViewModel.requiresInterAirportTransfer ? .transit : .arGuide
        if selectedTab == .transit || selectedTab == .settings {
            // iOS hosts overflow tabs inside the system More navigation stack.
            // Leave that stack first, then select the route destination.
            selectedTab = .journey
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.selectedTab = destination
            }
        } else {
            selectedTab = destination
        }
    }

    func setPredictionLearningEnabled(_ enabled: Bool) {
        preferences.personalizedPredictionsEnabled = enabled
        Task { await predictor.setLearningEnabled(enabled) }
    }

    func setJourneyAlertsEnabled(_ enabled: Bool) async {
        preferences.journeyAlertsEnabled = enabled
        guard enabled else { return }
        backgroundJourneyMonitor.enable()
        _ = try? await notificationScheduler.requestAuthorization()
        await refreshJourneyAlerts()
    }

    func refreshJourneyAlerts() async {
        guard preferences.journeyAlertsEnabled,
              let layover = longHaulViewModel.activeLayover else { return }
        let selectedPlace = longHaulViewModel.selectedCandidate?.place
        let referenceAirport = longHaulViewModel.requiresInterAirportTransfer
            ? AirportReferencePointRegistry.referencePoint(for: layover.onwardAirport.iata)
            : AirportReferencePointRegistry.referencePoint(for: layover.airport.iata)
        await backgroundJourneyMonitor.configure(
            journeyID: StableEntityID.uuid("background-alert|\(layover.id)"),
            airport: referenceAirport,
            gate: longHaulViewModel.activeGate,
            leaveBy: longHaulViewModel.selectedAssessment?.latestReturnTime,
            selectedPlace: selectedPlace,
            includeSelectedPlace: preferences.selectedPlaceAlertsEnabled
        )
    }

    func clearAllAppData() async {
        await crossDeviceReminders.disableAppleCalendar()
        await longHaulViewModel.clearAllData()
        try? await entryRequirementCache.clear()
        try? await flightCache.clear()
        await predictor.eraseLearnedModel()
    }

    /// Returns no external-sync input for demo or stochastic fixtures. Live and
    /// cached/offline itineraries must contain no demo flight records; the
    /// planner then independently rejects expired, unsafe, or unresolved times.
    func crossDeviceReminderPlanningInput() -> CrossDeviceReminderPlanningInput? {
        guard launchContext.mode != .demo,
              launchContext.mode != .stochastic,
              let itinerary = longHaulViewModel.itinerary,
              !itinerary.legs.contains(where: { $0.flight.source.isDemo }) else {
            return nil
        }

        let latestReturn: LatestReturnReminderSource?
        if let layover = longHaulViewModel.activeLayover,
           let candidate = longHaulViewModel.selectedCandidate,
           let assessment = longHaulViewModel.selectedAssessment,
           assessment.status == .safe,
           assessment.trace.unresolvedInputs.isEmpty {
            let currentTime = Date()
            latestReturn = LatestReturnReminderSource(
                layoverID: layover.id,
                candidateTitle: candidate.title,
                assessment: assessment,
                criticalInputsAreCurrent: latestReturnInputsAreCurrent(
                    itinerary: itinerary,
                    layover: layover,
                    candidate: candidate,
                    at: currentTime
                )
            )
        } else {
            latestReturn = nil
        }

        return CrossDeviceReminderPlanningInput(
            itinerary: itinerary,
            activeLegID: longHaulViewModel.onwardLeg?.id,
            journeyAssessment: nil,
            latestReturn: latestReturn
        )
    }

    private func latestReturnInputsAreCurrent(
        itinerary: Itinerary,
        layover: LayoverContext,
        candidate: PlanCandidate,
        at date: Date
    ) -> Bool {
        guard candidate.latestReturnReference == nil,
              let inboundLeg = itinerary.legs.first(where: { $0.id == layover.inboundLegID }),
              let onwardLeg = itinerary.legs.first(where: { $0.id == layover.onwardLegID }),
              let onBlock = inboundLeg.onBlockTime,
              let gateClose = onwardLeg.gateCloseTime,
              onBlock.isEligibleForExternalAction(at: date),
              gateClose.isEligibleForExternalAction(at: date) else {
            return false
        }

        let requiredSegments = candidate.segments.filter(\.requiredForPositiveRecommendation)
        guard !requiredSegments.isEmpty,
              requiredSegments.allSatisfy({ segment in
                  guard let metric = segment.duration else { return false }
                  return metric.value.isValid && metric.isEligibleForExternalAction(at: date)
              }) else {
            return false
        }

        if let place = candidate.place, place.accessZone != .airside {
            guard let entry = candidate.entryAssessment,
                  entry.isCurrent(at: date),
                  entry.canSupportLandsideRecommendation(
                      profile: longHaulViewModel.travelerProfile,
                      at: date
                  ) else {
                return false
            }
        }
        return true
    }
}
