import Foundation

struct InterAirportArrivalTarget: Equatable, Sendable {
    let onwardAirportCode: String
    let gateClose: Date?
    let arriveBy: Date?
    let timeZoneIdentifier: String
    let unresolvedInputs: [String]

    var isCalculable: Bool { arriveBy != nil && unresolvedInputs.isEmpty }
}

@MainActor
final class LongHaulExperienceViewModel: ObservableObject {
    @Published private(set) var itinerary: Itinerary?
    @Published private(set) var activeLayover: LayoverContext?
    @Published private(set) var travelerProfile = TravelerProfile.incomplete
    @Published private(set) var entryAssessment: EntryAssessment?
    @Published private(set) var facilities: [AirportFacilityRecord] = []
    @Published private(set) var discoveredPlaces: [LayoverPlace] = []
    @Published private(set) var affordabilityOptions: [AffordabilityOption] = []
    @Published private(set) var currencyRateQuote: CurrencyRateQuote?
    @Published private(set) var weatherSummary: SourcedMetric<String>?
    @Published private(set) var transferWeatherSummary: SourcedMetric<String>?
    @Published private(set) var destinationWeatherSummary: SourcedMetric<String>?
    @Published private(set) var delayOutlook: JourneyPrediction?
    @Published private(set) var ticketScanResult: TicketPDFScanResult?
    @Published private(set) var ticketConnectionStatuses: [TicketConnectionStatus] = []
    @Published private(set) var ticketScanMessage: String?
    @Published private(set) var isScanningTicketPDF = false
    @Published private(set) var isRefreshingWeather = false
    @Published private(set) var weatherRefreshMessage: String?
    @Published private(set) var isRefreshingAffordability = false
    @Published private(set) var candidates: [PlanCandidate] = []
    @Published private(set) var assessments: [UUID: FeasibilityAssessment] = [:]
    @Published private(set) var interAirportTransferPlan: InterAirportTransferPlan?
    @Published private(set) var personalizationSamples: [UUID: Int] = [:]
    @Published private(set) var freshness: DataFreshness = .unavailable
    @Published private(set) var terminalRoute: TerminalRoute?
    @Published private(set) var currentNodeID = "t3-transfer-security"
    @Published private(set) var destinationNodeID: String?
    @Published private(set) var terminalRouteTitle = "Gate"
    @Published var selectedZone: AccessZone = .airside
    @Published var selectedCategories: Set<LayoverPlaceCategory> = []
    @Published var selectedCandidateID: UUID?
    @Published var statusMessage: String?
    @Published var isRefreshing = false
    @Published var routeMode: RouteMode
    @Published var transferFlow: TransferFlow = .standardConnection

    let launchContext: AppLaunchContext
    let terminalGraph: TerminalGraph

    /// App-level integrations can observe when the fully rebuilt, safety-
    /// assessed snapshot is ready. The callback carries no data and must read
    /// the public snapshot, so partial provider updates are never synchronized.
    var reminderInputsDidChange: (@MainActor @Sendable () -> Void)?

    private let cache: any ItineraryCaching
    private let entryProvider: any EntryRequirementProvider
    private let facilityProvider: any AirportFacilityProvider
    private let recommendationEngine: any LayoverRecommendationEngine
    private let placeProvider: any PlaceProvider
    private let interAirportTransferProvider: any InterAirportTransferProvider
    private let flightService: LiveFlightService
    private let preferences: PreferencesStore
    private let predictor: any JourneyPredicting
    private let currencyRateProvider: any CurrencyRateProvider
    private let weatherProvider: any WeatherContextProvider
    private let now: @Sendable () -> Date
    private let fixtureAnchor: @Sendable () -> Date
    private var lastWeatherRefreshAttempt: Date?
    /// Freshness describes how each leg entered this in-memory itinerary. Provider
    /// metadata alone cannot distinguish a live response from a cache fallback.
    private var legFreshness: [UUID: DataFreshness] = [:]
    private let router = TerminalRouter()

    init(
        launchContext: AppLaunchContext,
        cache: any ItineraryCaching,
        entryProvider: any EntryRequirementProvider,
        facilityProvider: any AirportFacilityProvider,
        recommendationEngine: any LayoverRecommendationEngine,
        placeProvider: any PlaceProvider = MapKitNearbyPlaceProvider(),
        interAirportTransferProvider: any InterAirportTransferProvider = UnavailableInterAirportTransferProvider(),
        flightService: LiveFlightService,
        preferences: PreferencesStore,
        predictor: any JourneyPredicting,
        currencyRateProvider: any CurrencyRateProvider = FrankfurterCurrencyRateProvider(),
        weatherProvider: any WeatherContextProvider = UnavailableWeatherContextProvider(),
        terminalGraph: TerminalGraph = SampleTerminalGraph.hanedaTerminal3Demo,
        now: @escaping @Sendable () -> Date = { Date() },
        fixtureAnchor: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.launchContext = launchContext
        self.cache = cache
        self.entryProvider = entryProvider
        self.facilityProvider = facilityProvider
        self.recommendationEngine = recommendationEngine
        self.placeProvider = placeProvider
        self.interAirportTransferProvider = interAirportTransferProvider
        self.flightService = flightService
        self.preferences = preferences
        self.predictor = predictor
        self.currencyRateProvider = currencyRateProvider
        self.weatherProvider = weatherProvider
        self.terminalGraph = terminalGraph
        self.now = now
        self.fixtureAnchor = fixtureAnchor
        routeMode = preferences.accessibility.wheelchairRouting ? .accessible : .fastest
    }

    var activeAirport: Airport? { activeLayover?.airport }

    /// The airport that must be reached before the onward flight when a
    /// connection changes airports (for example HND → NRT).
    var transferWeatherAirport: Airport? {
        guard activeLayover?.isInterAirportTransfer == true else { return nil }
        return activeLayover?.onwardAirport
    }

    var destinationWeatherAirport: Airport? {
        JourneyWeatherAirportSelector.destination(
            activeAirport: transferWeatherAirport ?? activeAirport,
            onwardLeg: onwardLeg
        )
    }

    var requiresInterAirportTransfer: Bool { activeLayover?.isInterAirportTransfer == true }

    var onwardLeg: ItineraryLeg? {
        guard let itinerary, let activeLayover else { return nil }
        return itinerary.legs.first(where: { $0.id == activeLayover.onwardLegID })
    }

    var activeGate: String? { onwardLeg?.flight.gate }
    var gateStatus: GateStatusSnapshot {
        let routeMinutes = terminalRoute.map { Int(($0.durationSeconds / 60).rounded(.up)) }
        return GateStatusSnapshot(
            gate: activeGate,
            previousGate: onwardLeg?.flight.previousGate,
            walkMinutes: routeMinutes,
            boardingTime: onwardLeg?.flight.boardingTime,
            leaveBy: selectedAssessment?.latestReturnTime
        )
    }
    /// Shared clock for the interface and the decision engine. Test drivers
    /// advance this clock so urgency colours remain faithful to the scenario.
    var currentTime: Date { now() }

    /// The latest conservative arrival target at the onward airport. This is
    /// derived only when every post-arrival safety component has a sourced
    /// distribution; missing values remain unknown instead of becoming zero.
    var interAirportArrivalTarget: InterAirportArrivalTarget? {
        guard let layover = activeLayover, layover.isInterAirportTransfer else { return nil }

        let timeZoneIdentifier = layover.onwardAirport.timeZone ?? layover.timeZoneIdentifier
        guard let gateClose = layover.onwardGateClose else {
            return InterAirportArrivalTarget(
                onwardAirportCode: layover.onwardAirport.iata,
                gateClose: nil,
                arriveBy: nil,
                timeZoneIdentifier: timeZoneIdentifier,
                unresolvedInputs: ["onward gate-close time"]
            )
        }

        let transferCandidate = candidates.first { $0.intent == .airportTransfer }
        let requiredKinds: [PlanSegmentKind] = [.checkIn, .security, .terminalRoute, .safety]
        var unresolved: [String] = []
        var conservativeProcessingMinutes = 0.0

        for kind in requiredKinds {
            let matching = transferCandidate?.segments.filter { $0.kind == kind } ?? []
            guard !matching.isEmpty else {
                unresolved.append(label(for: kind))
                continue
            }
            for segment in matching where segment.requiredForPositiveRecommendation {
                guard let metric = segment.duration,
                      metric.value.isValid,
                      !metric.isExpired(at: now()) else {
                    unresolved.append(segment.title)
                    continue
                }
                conservativeProcessingMinutes += metric.value.upper
            }
        }

        return InterAirportArrivalTarget(
            onwardAirportCode: layover.onwardAirport.iata,
            gateClose: gateClose,
            arriveBy: unresolved.isEmpty
                ? gateClose.addingTimeInterval(-conservativeProcessingMinutes * 60)
                : nil,
            timeZoneIdentifier: timeZoneIdentifier,
            unresolvedInputs: Array(Set(unresolved)).sorted()
        )
    }

    var visibleFacilities: [AirportFacilityRecord] {
        facilities.filter { record in
            record.place.accessZone == selectedZone
                && (selectedCategories.isEmpty || selectedCategories.contains(record.place.category))
        }
    }

    var selectedAssessment: FeasibilityAssessment? {
        guard let selectedCandidateID else { return nil }
        return assessments[selectedCandidateID]
    }

    var selectedCandidate: PlanCandidate? {
        guard let selectedCandidateID else { return nil }
        return candidates.first(where: { $0.id == selectedCandidateID })
    }

    var currentManeuver: RouteManeuver? {
        RouteManeuverBuilder().currentManeuver(
            graph: terminalGraph,
            route: terminalRoute,
            currentNodeID: currentNodeID
        )
    }

    var shouldReturnNow: Bool {
        assessments.values.contains { assessment in
            guard assessment.candidateID == selectedCandidateID,
                  let latest = assessment.latestReturnTime else { return false }
            return latest <= now()
        }
    }

    func start() async {
        let cachedProfile = await cache.loadTravelerProfile()
        travelerProfile = (launchContext.mode == .demo || launchContext.mode == .stochastic)
            && !cachedProfile.hasMinimumEntryFacts
            ? .minimalDemo
            : cachedProfile
        if let qaWalkingPace = launchContext.qaWalkingPace {
            travelerProfile.walkingPace = qaWalkingPace
        }
        let cached = await cache.loadItinerary()
        switch launchContext.mode {
        case .demo, .stochastic:
            itinerary = launchContext.scenario == "interAirport"
                ? LongHaulReferenceScenario.hanedaToNaritaItinerary(anchor: fixtureAnchor())
                : LongHaulReferenceScenario.itinerary(anchor: fixtureAnchor())
        case .offline:
            itinerary = cached
        case .live:
            itinerary = cached
        }
        updateFreshness()
        await rebuildContext()
        try? await cache.saveItinerary(itinerary)
    }

    func addLeg(_ flight: Flight) async {
        let leg = ItineraryLeg(flight: flight)
        if itinerary == nil {
            itinerary = Itinerary(title: flight.routeLabel, legs: [leg])
        } else {
            itinerary?.append(leg)
            itinerary?.title = itinerary?.legs.map { $0.flight.origin.iata }.joined(separator: " → ")
                .appending(" → \(flight.destination.iata)") ?? flight.routeLabel
        }
        await persistAndRebuild()
    }

    func removeLeg(id: UUID) async {
        itinerary?.removeLeg(id: id)
        await persistAndRebuild()
    }

    func moveLeg(from offsets: IndexSet, to destination: Int) async {
        itinerary?.moveLeg(from: offsets, to: destination)
        await persistAndRebuild()
    }

    func updateLeg(_ leg: ItineraryLeg) async {
        itinerary?.replaceLeg(leg)
        await persistAndRebuild()
    }

    func refreshAllLegs() async {
        guard var itinerary, !isRefreshing else { return }
        if launchContext.mode == .offline {
            freshness = .stale
            statusMessage = "Showing your saved trip offline."
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        var warnings: [String] = []
        for index in itinerary.legs.indices {
            do {
                let result = try await flightService.refresh(itinerary.legs[index].flight)
                if let flight = result.flights.first {
                    itinerary.legs[index].flight = flight
                    legFreshness[itinerary.legs[index].id] = result.freshness
                }
                if let warning = result.warning { warnings.append(warning) }
            } catch {
                warnings.append("\(itinerary.legs[index].flight.flightNumber): refresh unavailable")
            }
        }
        itinerary.inputRevision += 1
        itinerary.updatedAt = now()
        self.itinerary = itinerary
        statusMessage = warnings.isEmpty ? "Itinerary refreshed." : warnings.joined(separator: " • ")
        await persistAndRebuild()
    }

    func refreshWeather(force: Bool = false) async {
        let requestedAt = now()
        guard !isRefreshingWeather else { return }
        if !force,
           let lastWeatherRefreshAttempt,
           requestedAt.timeIntervalSince(lastWeatherRefreshAttempt) < 60 {
            weatherRefreshMessage = "Weather was updated less than a minute ago."
            return
        }
        guard launchContext.mode != .offline,
              let airport = activeAirport,
              let reference = AirportReferencePointRegistry.referencePoint(for: airport.iata) else {
            weatherSummary = nil
            transferWeatherSummary = nil
            destinationWeatherSummary = nil
            delayOutlook = nil
            weatherRefreshMessage = "Weather is unavailable offline."
            return
        }
        isRefreshingWeather = true
        lastWeatherRefreshAttempt = requestedAt
        defer { isRefreshingWeather = false }
        do {
            async let departureResult = weatherProvider.weatherSummary(
                airport: airport,
                latitude: reference.latitude,
                longitude: reference.longitude,
                at: requestedAt
            )
            async let destinationResult = destinationWeather(at: requestedAt)
            async let transferResult = transferWeather(at: requestedAt)
            weatherSummary = try await departureResult
            transferWeatherSummary = await transferResult
            destinationWeatherSummary = await destinationResult
            if let flight = onwardLeg?.flight {
                // Prefer a weather-matched outlook, but keep the route/time
                // outlook visible when the destination has no weather point or
                // the weather-specific history is still empty.
                let routeOutlook = await predictor.predictDelay(for: flight)
                if let weatherContext = currentDelayWeatherContext() {
                    let weatherOutlook = await predictor.predictDelay(for: flight, weatherContext: weatherContext)
                    delayOutlook = weatherOutlook.expectedDelayMinutes == nil ? routeOutlook : weatherOutlook
                } else {
                    delayOutlook = routeOutlook
                }
            } else {
                delayOutlook = nil
            }
            weatherRefreshMessage = weatherSummary == nil ? "No current weather observation is available for this airport." : nil
            refreshCandidateWeatherAllowance()
        } catch {
            weatherRefreshMessage = "Weather could not be refreshed."
        }
    }

    func setRouteMode(_ mode: RouteMode) {
        routeMode = mode
        calculateTerminalRoute()
    }

    func routeToGate() {
        calculateTerminalRoute(preferredDestinationNodeID: nil, title: "Gate", forceGate: true)
    }

    /// Starts the bundled terminal-route preview when the current journey is an
    /// airport change. The preview graph is a deliberate proof-of-concept, so
    /// it is kept separate from the real inter-airport transfer plan.
    func startDemoTerminalPreviewIfAvailable() {
        guard terminalGraph.version.hasPrefix("demo-"),
              let destination = demoPreviewDestinationNodeID else { return }

        destinationNodeID = destination
        terminalRouteTitle = terminalGraph.nodes.first(where: { $0.id == destination })?.name ?? "Gate"
        terminalRoute = try? router.route(
            in: terminalGraph,
            from: currentNodeID,
            to: destination,
            mode: routeMode,
            preferences: preferences.accessibility
        )
    }

    func routeToTerminalPlace(_ nodeID: String) {
        guard let node = terminalGraph.nodes.first(where: { $0.id == nodeID }) else { return }
        calculateTerminalRoute(preferredDestinationNodeID: nodeID, title: node.name)
    }

    func calibrateLocation(to nodeID: String) {
        guard terminalGraph.nodes.contains(where: { $0.id == nodeID }) else { return }
        currentNodeID = nodeID
        calculateTerminalRoute()
    }

    func advanceRouteStep() {
        guard let route = terminalRoute,
              let index = route.nodeIDs.firstIndex(of: currentNodeID),
              route.nodeIDs.indices.contains(index + 1) else { return }
        currentNodeID = route.nodeIDs[index + 1]
    }

    func restartRoutePreview() {
        guard let firstNodeID = terminalRoute?.nodeIDs.first else {
            calculateTerminalRoute()
            return
        }
        currentNodeID = firstNodeID
    }

    func updateTravelerProfile(_ profile: TravelerProfile) async {
        travelerProfile = profile
        try? await cache.saveTravelerProfile(profile)
        await rebuildContext()
    }

    func scanTicketPDF(data: Data, fileName: String) async {
        guard !isScanningTicketPDF else { return }
        isScanningTicketPDF = true
        defer { isScanningTicketPDF = false }
        do {
            let scanner = TicketPDFScanService()
            let result = fileName.lowercased().hasSuffix(".pdf")
                ? try scanner.scanPDF(data: data, fileName: fileName, at: now())
                : try scanner.scanImage(data: data, fileName: fileName, at: now())
            ticketScanResult = result
            await applyScannedTicketRoute()
        } catch {
            ticketScanMessage = error.localizedDescription
        }
    }

    func applyScannedTicketRoute() async {
        guard let scan = ticketScanResult, scan.routeAirportCodes.count >= 2 else {
            ticketScanMessage = "We need at least two airport codes to add a route."
            return
        }
        var airports: [Airport] = []
        for code in scan.routeAirportCodes {
            airports.append((await AirportDirectory.resolve(code)).airport)
        }
        // A ticket can list an airport change between two flown legs (for
        // example BKK → HND → NRT → LAX with two flight numbers). Keep that
        // ground transfer as the connection, rather than inventing HND → NRT
        // as a third flight.
        let flightPairs: [(Airport, Airport)]
        if airports.count == scan.flightNumbers.count + 2,
           airports.count >= 4 {
            flightPairs = [(airports[0], airports[1]), (airports[airports.count - 2], airports[airports.count - 1])]
        } else {
            flightPairs = zip(airports, airports.dropFirst()).map { ($0, $1) }
        }
        let legs = flightPairs.enumerated().map { index, pair in
            let flightNumber = scan.flightNumbers.indices.contains(index) ? scan.flightNumbers[index] : "Flight details needed"
            let flight = Flight(
                id: "ticket-\(scan.textFingerprint.prefix(12))-\(index)",
                flightNumber: flightNumber,
                airlineCode: nil,
                airlineName: nil,
                origin: pair.0,
                destination: pair.1,
                status: .unknown,
                scheduledDeparture: nil,
                estimatedDeparture: nil,
                actualDeparture: nil,
                scheduledArrival: nil,
                estimatedArrival: nil,
                actualArrival: nil,
                departureTerminal: nil,
                arrivalTerminal: nil,
                gate: nil,
                arrivalGate: nil,
                previousGate: nil,
                boardingStatus: nil,
                boardingGroup: nil,
                boardingTime: nil,
                delayMinutes: nil,
                aircraftType: nil,
                baggageClaim: nil,
                source: ProviderMetadata(name: "Ticket import", providerRecordID: scan.sourceRecordID, providerUpdatedAt: scan.scannedAt, receivedAt: now(), isLive: false, isDemo: false)
            )
            return ItineraryLeg(flight: flight)
        }
        itinerary = Itinerary(title: scan.routeAirportCodes.joined(separator: " → "), legs: legs, createdAt: now(), updatedAt: now())
        updateTicketConnectionStatuses()
        applyTicketConnectionFlows()
        await persistAndRebuild()
        ticketScanMessage = ticketConnectionStatuses.isEmpty
            ? "Ticket added. Add flight times when they are available."
            : "Ticket added. Your connection plan is ready."
    }

    func clearTicketScan() {
        ticketScanResult = nil
        ticketConnectionStatuses = []
        ticketScanMessage = nil
    }

    func confirmOfficialEntryReview(_ confirmed: Bool) async {
        var updated = travelerProfile
        updated.hasConfirmedOfficialEntryRules = confirmed
        await updateTravelerProfile(updated)
    }

    func selectCandidate(_ id: UUID) {
        selectedCandidateID = id
        reminderInputsDidChange?()
    }

    func startInterAirportTransfer() {
        guard let layover = activeLayover, layover.isInterAirportTransfer else { return }
        if let transferFirst = candidates.first(where: { $0.intent == .airportTransfer }) {
            selectedCandidateID = transferFirst.id
        }
        selectedZone = .nearby
        statusMessage = "Airport transfer selected."
        reminderInputsDidChange?()
    }

    func setTransferFlow(_ flow: TransferFlow) {
        guard let layover = activeLayover,
              var itinerary,
              let onwardIndex = itinerary.legs.firstIndex(where: { $0.id == layover.onwardLegID }) else { return }
        let resolved = layover.isInterAirportTransfer ? TransferFlow.airportChange : flow
        itinerary.legs[onwardIndex].transferFlow = resolved
        itinerary.inputRevision += 1
        itinerary.updatedAt = now()
        self.itinerary = itinerary
        transferFlow = resolved
        Task { await persistAndRebuild() }
    }

    func recordCandidateFeedback(candidateID: UUID, accepted: Bool) async {
        guard let candidate = candidates.first(where: { $0.id == candidateID }) else { return }
        let context = recommendationContext(candidate)
        await predictor.recordRecommendationFeedback(context: context, accepted: accepted)
        statusMessage = accepted
            ? "Preference saved."
            : "Feedback saved."
    }

    func toggleCategory(_ category: LayoverPlaceCategory) {
        if selectedCategories.contains(category) { selectedCategories.remove(category) }
        else { selectedCategories.insert(category) }
    }

    func discoverNearbyPlaces() async {
        guard let airport = activeAirport,
              let referencePoint = AirportReferencePointRegistry.referencePoint(for: airport.iata) else {
            discoveredPlaces = []
            statusMessage = "Nearby search isn't available here yet."
            return
        }
        let policy = NearbyDiscoveryPolicy.current
        let context = PlaceSearchContext(
            airport: airport,
            centerLatitude: referencePoint.latitude,
            centerLongitude: referencePoint.longitude,
            radiusMeters: policy.airportRadiusMeters,
            categories: selectedCategories,
            at: now()
        )
        do {
            discoveredPlaces = try await placeProvider.places(for: context)
            statusMessage = discoveredPlaces.isEmpty ? "No nearby places match the selected filters." : nil
        } catch {
            discoveredPlaces = []
            statusMessage = "Nearby search is unavailable. Airport services remain visible."
        }
    }

    /// Refreshes only currency conversion. Cost bands retain their source mode:
    /// a live FX rate cannot turn a preview venue price into a live price.
    func refreshAffordability() async {
        guard let airport = activeAirport,
              let localCurrency = AirportAffordabilityCatalog.currencyCode(for: airport.iata) else {
            affordabilityOptions = []
            currencyRateQuote = nil
            return
        }
        affordabilityOptions = AirportAffordabilityCatalog.options(for: airport.iata)
        let displayCurrency = TravelerCurrencyResolver.displayCurrency(
            for: travelerProfile,
            fallback: Locale.current.currency?.identifier ?? "USD"
        )
        guard displayCurrency.uppercased() != localCurrency else {
            currencyRateQuote = CurrencyRateQuote(
                baseCurrencyCode: localCurrency,
                quoteCurrencyCode: displayCurrency,
                rate: 1,
                rateDate: now(),
                receivedAt: now(),
                provider: "Same currency"
            )
            return
        }
        isRefreshingAffordability = true
        defer { isRefreshingAffordability = false }
        do {
            currencyRateQuote = try await currencyRateProvider.latestRate(
                from: localCurrency,
                to: displayCurrency
            )
        } catch {
            currencyRateQuote = nil
        }
    }

    func clearAllData() async {
        itinerary = nil
        activeLayover = nil
        facilities = []
        discoveredPlaces = []
        affordabilityOptions = []
        currencyRateQuote = nil
        weatherSummary = nil
        transferWeatherSummary = nil
        destinationWeatherSummary = nil
        delayOutlook = nil
        ticketScanResult = nil
        ticketConnectionStatuses = []
        ticketScanMessage = nil
        isScanningTicketPDF = false
        weatherRefreshMessage = nil
        lastWeatherRefreshAttempt = nil
        interAirportTransferPlan = nil
        candidates = []
        assessments = [:]
        entryAssessment = nil
        try? await cache.clearLongHaulData()
        reminderInputsDidChange?()
    }

    private func persistAndRebuild() async {
        try? await cache.saveItinerary(itinerary)
        updateFreshness()
        await rebuildContext()
    }

    private func rebuildContext() async {
        guard let itinerary else {
            activeLayover = nil
            affordabilityOptions = []
            currencyRateQuote = nil
            weatherSummary = nil
            transferWeatherSummary = nil
            destinationWeatherSummary = nil
            delayOutlook = nil
            ticketConnectionStatuses = []
            weatherRefreshMessage = nil
            return
        }
        activeLayover = itinerary.activeLayover(at: now())
        guard let layover = activeLayover else {
            facilities = []
            affordabilityOptions = []
            currencyRateQuote = nil
            weatherSummary = nil
            transferWeatherSummary = nil
            destinationWeatherSummary = nil
            delayOutlook = nil
            ticketConnectionStatuses = []
            weatherRefreshMessage = nil
            candidates = []
            assessments = [:]
            calculateTerminalRoute()
            return
        }
        transferFlow = layover.transferFlow

        // Local cost bands are a named catalog fixture, so make them available
        // with the layover snapshot. Network refresh is limited to the FX quote.
        affordabilityOptions = AirportAffordabilityCatalog.options(for: layover.airport.iata)
        currencyRateQuote = nil
        await refreshWeather()

        do {
            let arrivalFacilities = try await facilityProvider.facilities(at: layover.airport, on: now())
            let onwardFacilities = layover.isInterAirportTransfer
                ? try await facilityProvider.facilities(at: layover.onwardAirport, on: now())
                : []
            facilities = arrivalFacilities + onwardFacilities.filter { onward in
                !arrivalFacilities.contains(where: { $0.id == onward.id })
            }
        } catch {
            facilities = []
            statusMessage = "Airport facilities could not be refreshed."
        }

        if let query = entryQuery(layover: layover) {
            entryAssessment = try? await entryProvider.assessment(for: query)
        } else {
            entryAssessment = nil
        }
        updateTicketConnectionStatuses()
        if layover.isInterAirportTransfer {
            let options = (try? await interAirportTransferProvider.options(
                from: layover.airport,
                to: layover.onwardAirport,
                after: layover.inboundOnBlock ?? now()
            )) ?? []
            let transferPlan = InterAirportTransferPlanner().plan(
                options: options,
                requireAccessibility: preferences.accessibility.wheelchairRouting,
                now: now()
            )
            interAirportTransferPlan = transferPlan
            candidates = InterAirportCandidateFactory.candidates(
                layover: layover,
                transferPlan: transferPlan,
                entry: entryAssessment,
                anchor: now(),
                includeDemoOptionalActivity: launchContext.mode == .demo || launchContext.mode == .stochastic
            )
        } else {
            interAirportTransferPlan = nil
            switch launchContext.mode {
            case .demo, .stochastic:
                candidates = LongHaulReferenceScenario.candidates(
                    layover: layover,
                    entry: entryAssessment,
                    anchor: now(),
                    stochasticSeed: launchContext.simulationSeed
                )
            case .live, .offline:
                candidates = []
            statusMessage = "We don't have enough layover information yet."
            }
        }
        candidates = candidates
            .map(applyingTransferFlowRequirements)
            .map(applyingCurrentWeatherAllowance)
        assessments = Dictionary(uniqueKeysWithValues: candidates.map { candidate in
            (
                candidate.id,
                recommendationEngine.assess(
                    itinerary: itinerary,
                    layover: layover,
                    candidate: candidate,
                    profile: travelerProfile,
                    snapshotRevision: snapshotRevision(for: itinerary),
                    seed: launchContext.simulationSeed,
                    now: now()
                )
            )
        })
        var preferenceByCandidate: [UUID: PreferencePrediction] = [:]
        for candidate in candidates {
            preferenceByCandidate[candidate.id] = await predictor.predictRecommendationPreference(
                context: recommendationContext(candidate)
            )
        }
        personalizationSamples = preferenceByCandidate.mapValues(\.sampleCount)
        candidates.sort { left, right in
            let leftSafety = safetyRank(assessments[left.id]?.status)
            let rightSafety = safetyRank(assessments[right.id]?.status)
            if leftSafety != rightSafety { return leftSafety < rightSafety }
            let leftPreference = preferenceByCandidate[left.id]?.acceptanceProbability
            let rightPreference = preferenceByCandidate[right.id]?.acceptanceProbability
            if leftPreference != rightPreference {
                return (leftPreference ?? -1) > (rightPreference ?? -1)
            }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
        selectedCandidateID = selectedCandidateID.flatMap { id in candidates.contains(where: { $0.id == id }) ? id : nil }
            ?? candidates.first?.id
        calculateTerminalRoute()
        reminderInputsDidChange?()
    }

    /// Only plans that require the traveller to leave the terminal receive a
    /// weather allowance. This makes poor outdoor conditions change the plan,
    /// rather than merely adding a weather card to the screen.
    private func applyingCurrentWeatherAllowance(to candidate: PlanCandidate) -> PlanCandidate {
        let segmentsWithoutPriorAllowance = candidate.segments.filter { $0.title != "Outdoor weather allowance" }
        guard let place = candidate.place,
              place.accessZone == .airportLandside || place.accessZone == .nearby || place.accessZone == .city,
              let allowance = outdoorWeatherAllowance() else {
            return PlanCandidate(
                title: candidate.title,
                place: candidate.place,
                segments: segmentsWithoutPriorAllowance,
                entryAssessment: candidate.entryAssessment,
                latestReturnReference: candidate.latestReturnReference,
                intent: candidate.intent,
                requiresLandsideExit: candidate.requiresLandsideExit
            )
        }

        let observedAt = now()
        let metric = SourcedMetric(
            value: allowance.distribution,
            unit: .minutes,
            provider: "Current airport weather",
            providerField: "condition",
            sourceRecordID: "weather-allowance-\(allowance.id)-\(activeAirport?.iata ?? "airport")",
            observedAt: observedAt,
            receivedAt: observedAt,
            expiresAt: observedAt.addingTimeInterval(60 * 60),
            uncertainty: "Outdoor travel can take longer in current conditions.",
            derivation: [DerivationStep(
                label: "Outdoor weather allowance",
                formula: "current weather adjustment for plans outside the terminal",
                inputRecordIDs: [weatherSummary?.sourceRecordID ?? "weather"],
                result: allowance.label
            )]
        )
        return PlanCandidate(
            title: candidate.title,
            place: candidate.place,
            segments: segmentsWithoutPriorAllowance + [PlanSegment(kind: .safety, title: "Outdoor weather allowance", duration: metric)],
            entryAssessment: candidate.entryAssessment,
            latestReturnReference: candidate.latestReturnReference,
            intent: candidate.intent,
            requiresLandsideExit: candidate.requiresLandsideExit
        )
    }

    /// Self-transfer is an itinerary fact, not merely a screen preference.
    /// The conservative stages are added before every feasibility simulation.
    private func applyingTransferFlowRequirements(to candidate: PlanCandidate) -> PlanCandidate {
        guard transferFlow == .selfTransfer else { return candidate }
        let existingKinds = Set(candidate.segments.map(\.kind))
        let additions = Self.selfTransferSegments(at: now()).filter { !existingKinds.contains($0.kind) }
        return PlanCandidate(
            title: candidate.title,
            place: candidate.place,
            segments: additions + candidate.segments,
            entryAssessment: candidate.entryAssessment,
            latestReturnReference: candidate.latestReturnReference,
            intent: candidate.intent,
            requiresLandsideExit: true
        )
    }

    private static func selfTransferSegments(at date: Date) -> [PlanSegment] {
        let requirements: [(PlanSegmentKind, String, Double, Double, Double)] = [
            (.border, "Self-transfer immigration", 15, 25, 45),
            (.baggage, "Collect checked baggage", 15, 30, 50),
            (.customs, "Customs exit", 5, 12, 25),
            (.checkIn, "Check in and bag drop again", 15, 25, 45),
            (.security, "Security screening", 10, 20, 40)
        ]
        return requirements.map { kind, title, low, mode, high in
            let recordID = "user-declared-self-transfer-\(kind.rawValue)"
            let value = EstimateDistribution(lower: low, mostLikely: mode, upper: high, unit: .minutes)
            return PlanSegment(
                kind: kind,
                title: title,
                duration: SourcedMetric(
                    value: value, unit: .minutes, provider: "Traveler declaration",
                    providerField: "selfTransfer.\(kind.rawValue)", sourceRecordID: recordID,
                    observedAt: date, receivedAt: date, expiresAt: nil,
                    uncertainty: "Conservative planning allowance; replace with current airport processing data when available.",
                    derivation: [DerivationStep(label: title, formula: "user selected self-transfer conservative allowance", inputRecordIDs: [recordID], result: "\(Int(low)) / \(Int(mode)) / \(Int(high)) min")]
                )
            )
        }
    }

    private func refreshCandidateWeatherAllowance() {
        guard let itinerary, let layover = activeLayover, !candidates.isEmpty else { return }
        candidates = candidates.map(applyingCurrentWeatherAllowance)
        assessments = Dictionary(uniqueKeysWithValues: candidates.map { candidate in
            (candidate.id, recommendationEngine.assess(
                itinerary: itinerary,
                layover: layover,
                candidate: candidate,
                profile: travelerProfile,
                snapshotRevision: snapshotRevision(for: itinerary),
                seed: launchContext.simulationSeed,
                now: now()
            ))
        })
        selectedCandidateID = selectedCandidateID.flatMap { id in candidates.contains(where: { $0.id == id }) ? id : nil }
            ?? candidates.first?.id
        reminderInputsDidChange?()
    }

    private func outdoorWeatherAllowance() -> (id: String, label: String, distribution: EstimateDistribution)? {
        let condition = (weatherSummary?.value ?? "").lowercased()
        if condition.contains("thunder") || condition.contains("storm") {
            return ("storm", "Storm conditions", EstimateDistribution(lower: 15, mostLikely: 30, upper: 50, unit: .minutes))
        }
        if condition.contains("fog") {
            return ("fog", "Low visibility", EstimateDistribution(lower: 10, mostLikely: 20, upper: 35, unit: .minutes))
        }
        if condition.contains("rain") || condition.contains("snow") || condition.contains("wind") {
            return ("weather", "Weather conditions", EstimateDistribution(lower: 5, mostLikely: 12, upper: 25, unit: .minutes))
        }
        return nil
    }

    private func updateTicketConnectionStatuses() {
        guard let itinerary, let ticketScanResult else {
            ticketConnectionStatuses = []
            return
        }
        ticketConnectionStatuses = TicketConnectionStatusService().statuses(
            for: itinerary,
            scan: ticketScanResult,
            travelerProfile: travelerProfile,
            entryAssessment: entryAssessment,
            now: now()
        )
    }

    /// A scanned ticket determines the connection flow. This prevents a manual
    /// control from contradicting a separate-ticket or airport-change signal.
    private func applyTicketConnectionFlows() {
        guard var itinerary, !ticketConnectionStatuses.isEmpty else { return }
        var changed = false
        for status in ticketConnectionStatuses {
            guard let index = itinerary.legs.firstIndex(where: { $0.id == status.outboundLegID }),
                  itinerary.legs[index].transferFlow != status.transferFlow else { continue }
            itinerary.legs[index].transferFlow = status.transferFlow
            changed = true
        }
        guard changed else { return }
        itinerary.inputRevision += 1
        itinerary.updatedAt = now()
        self.itinerary = itinerary
        activeLayover = itinerary.activeLayover(at: now())
        transferFlow = activeLayover?.transferFlow ?? .standardConnection
    }

    var activeTicketConnectionStatus: TicketConnectionStatus? {
        guard let layover = activeLayover else { return nil }
        return ticketConnectionStatuses.first {
            $0.inboundLegID == layover.inboundLegID && $0.outboundLegID == layover.onwardLegID
        }
    }

    private func calculateTerminalRoute(
        preferredDestinationNodeID: String? = nil,
        title: String? = nil,
        forceGate: Bool = false
    ) {
        if requiresInterAirportTransfer {
            destinationNodeID = nil
            terminalRoute = nil
            terminalRouteTitle = "Transfer"
            return
        }
        let nodeID: String
        if let preferredDestinationNodeID {
            nodeID = preferredDestinationNodeID
        } else if let destinationNodeID, !forceGate {
            nodeID = destinationNodeID
        } else {
            guard let gate = activeGate else {
                destinationNodeID = nil
                terminalRoute = nil
                terminalRouteTitle = "Gate"
                return
            }
            nodeID = "gate-\(gate.lowercased())"
        }
        guard terminalGraph.nodes.contains(where: { $0.id == nodeID }) else {
            destinationNodeID = nil
            terminalRoute = nil
            terminalRouteTitle = "Gate"
            statusMessage = "This gate isn't on the terminal map yet."
            return
        }
        destinationNodeID = nodeID
        terminalRouteTitle = title ?? terminalGraph.nodes.first(where: { $0.id == nodeID })?.name ?? "Destination"
        terminalRoute = try? router.route(
            in: terminalGraph,
            from: currentNodeID,
            to: nodeID,
            mode: routeMode,
            preferences: preferences.accessibility
        )
    }

    private var demoPreviewDestinationNodeID: String? {
        if let gate = activeGate {
            let gateNodeID = "gate-\(gate.lowercased())"
            if terminalGraph.nodes.contains(where: { $0.id == gateNodeID }) {
                return gateNodeID
            }
        }
        return terminalGraph.nodes.first(where: { $0.kind == .gate })?.id
    }

    private func destinationWeather(at date: Date) async -> SourcedMetric<String>? {
        guard let destination = destinationWeatherAirport,
              let reference = AirportReferencePointRegistry.referencePoint(for: destination.iata) else {
            return nil
        }
        return try? await weatherProvider.weatherSummary(
            airport: destination,
            latitude: reference.latitude,
            longitude: reference.longitude,
            at: date
        )
    }

    private func transferWeather(at date: Date) async -> SourcedMetric<String>? {
        guard let transfer = transferWeatherAirport,
              let reference = AirportReferencePointRegistry.referencePoint(for: transfer.iata) else {
            return nil
        }
        return try? await weatherProvider.weatherSummary(
            airport: transfer,
            latitude: reference.latitude,
            longitude: reference.longitude,
            at: date
        )
    }

    private func currentDelayWeatherContext() -> String? {
        guard let departure = compactWeatherState(transferWeatherSummary ?? weatherSummary),
              let destination = compactWeatherState(destinationWeatherSummary) else {
            return nil
        }
        return "departure:\(departure)|destination:\(destination)"
    }

    private func compactWeatherState(_ metric: SourcedMetric<String>?) -> String? {
        guard let value = metric?.value.lowercased(), !value.isEmpty else { return nil }
        let condition = value.split(separator: ",", maxSplits: 1).first.map(String.init) ?? "conditions"
        let windBand: Int? = value.range(of: "wind ").flatMap { range in
            let suffix = value[range.upperBound...]
            let digits = suffix.prefix { $0.isNumber }
            return Int(digits).map { $0 / 10 }
        }
        return windBand.map { "\(condition)|wind-band:\($0)" } ?? condition
    }

    private func entryQuery(layover: LayoverContext) -> EntryRequirementQuery? {
        guard travelerProfile.hasMinimumEntryFacts,
              let itinerary,
              let inboundLeg = itinerary.legs.first(where: { $0.id == layover.inboundLegID }),
              let onwardLeg = itinerary.legs.first(where: { $0.id == layover.onwardLegID }),
              let originCountry = AirportReferencePointRegistry.referencePoint(for: inboundLeg.flight.origin.iata)?.countryCode,
              let transitCountry = AirportReferencePointRegistry.referencePoint(for: layover.airport.iata)?.countryCode,
              let onwardCountry = AirportReferencePointRegistry.referencePoint(for: onwardLeg.flight.destination.iata)?.countryCode,
              let originDeparture = inboundLeg.flight.effectiveDeparture,
              let arrival = layover.inboundOnBlock,
              let departure = layover.onwardDeparture,
              let onwardArrival = onwardLeg.flight.effectiveArrival,
              let originTimeZone = inboundLeg.flight.origin.timeZone,
              let transitTimeZone = layover.airport.timeZone,
              let onwardTimeZone = onwardLeg.flight.destination.timeZone else { return nil }
        return EntryRequirementQuery(
            nationalityCountryCode: travelerProfile.nationalityCountryCode,
            residenceCountryCode: travelerProfile.residenceCountryCode,
            passportType: travelerProfile.passportType,
            declaredAuthorizations: travelerProfile.declaredAuthorizations,
            originCountryCode: originCountry,
            transitCountryCode: transitCountry,
            onwardCountryCode: onwardCountry,
            originAirportCode: inboundLeg.flight.origin.iata,
            transitArrivalAirportCode: layover.airport.iata,
            onwardDepartureAirportCode: layover.onwardAirport.iata,
            onwardDestinationAirportCode: onwardLeg.flight.destination.iata,
            originDeparture: originDeparture,
            arrival: arrival,
            departure: departure,
            onwardArrival: onwardArrival,
            originTimeZoneIdentifier: originTimeZone,
            transitTimeZoneIdentifier: transitTimeZone,
            onwardTimeZoneIdentifier: onwardTimeZone,
            plannedLandsideExit: true,
            luggage: travelerProfile.luggage,
            purpose: travelerProfile.purpose
        )
    }

    private func snapshotRevision(for itinerary: Itinerary) -> String {
        let flightRecords = itinerary.legs.map { leg in
            let source = leg.flight.source
            return "\(source.name):\(source.providerRecordID ?? "unknown"):\(source.providerUpdatedAt?.timeIntervalSince1970 ?? -1)"
        }
        let facilityRecords = facilities.map { "\($0.id):\($0.verifiedAt.timeIntervalSince1970)" }
        let entryRecord = entryAssessment.map { "\($0.sourceRecordID):\($0.observedAt.timeIntervalSince1970)" } ?? "entry:unknown"
        let transferRecord = interAirportTransferPlan?.selected.map { "transfer:\($0.id):\($0.freshness.rawValue)" } ?? "transfer:unknown"
        return (["itinerary:\(itinerary.id.uuidString):\(itinerary.inputRevision)"] + flightRecords + facilityRecords + [entryRecord, transferRecord])
            .joined(separator: "|")
    }

    private func updateFreshness() {
        guard let itinerary else {
            freshness = .unavailable
            return
        }
        if launchContext.mode == .offline {
            freshness = .stale
            return
        }

        let states = itinerary.legs.map { leg in
            legFreshness[leg.id] ?? (leg.flight.source.isDemo ? .demo : .cached)
        }
        freshness = Self.combinedFreshness(states)
    }

    static func combinedFreshness(_ states: [DataFreshness]) -> DataFreshness {
        guard !states.isEmpty else { return .unavailable }
        if states.contains(.unavailable) { return .unavailable }
        if states.contains(.stale) { return .stale }
        if states.contains(.cached) { return .cached }
        if states.allSatisfy({ $0 == .demo }) { return .demo }
        return states.allSatisfy({ $0 == .live }) ? .live : .cached
    }

    private func recommendationContext(_ candidate: PlanCandidate) -> String {
        let zone = candidate.place?.accessZone.rawValue ?? "airport"
        let category = candidate.place?.category.rawValue ?? "plan"
        return "\(zone)|\(category)|\(travelerProfile.recoveryPreference.rawValue)|\(travelerProfile.budget.rawValue)"
    }

    private func safetyRank(_ status: FeasibilityStatus?) -> Int {
        switch status {
        case .safe: 0
        case .tight: 1
        case .requiresConfirmation: 2
        case .notRecommended: 3
        case nil: 4
        }
    }

    private func label(for kind: PlanSegmentKind) -> String {
        switch kind {
        case .checkIn: "onward check-in and bag-acceptance time"
        case .security: "onward security time"
        case .terminalRoute: "onward terminal-route time"
        case .safety: "onward safety margin"
        default: kind.rawValue
        }
    }
}
