import MapKit
import SwiftUI
import CoreLocation

struct TerminalMapView: View {
    @EnvironmentObject private var viewModel: LongHaulExperienceViewModel
    @EnvironmentObject private var preferences: PreferencesStore
    let graph: TerminalGraph
    @State private var level = 3
    @State private var showSteps = true
    @State private var selectedNodeID: String?
    @State private var selectedAmenity: PassengerAmenityCategory?
    @State private var terminalAmenityResult: TerminalAmenitySearchResult?
    @State private var geographicAmenityResults: [GeographicAmenityMatch] = []
    @State private var selectedGeographicAmenityID: String?
    @State private var selectedGeographicRoute: MKRoute?
    @State private var geographicRouteSummary: GeographicRouteSummary?
    @State private var isLoadingGeographicRoute = false
    @State private var geographicTravelMode: PassengerMapTravelMode = .transit
    @State private var destinationSearchScope: DestinationSearchScope = .airportArea
    @State private var isSearchingAroundAirport = false
    @State private var amenitySearchMessage: String?
    @State private var specificItemQuery = ""
    @State private var searchedItemQuery: String?
    @State private var maximumSpendText = ""
    @State private var showsOfficialAirportMap = false
    @State private var geographicResultsUseDeviceLocation = false
    @State private var landmarkSearch = ""
    @StateObject private var nearbyLocation = NearbySearchLocationManager()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                controls

                officialAirportMap

                findNearby

                if viewModel.requiresInterAirportTransfer, let layover = viewModel.activeLayover {
                    if let mapConfiguration = CityTransferPracticeMapConfiguration.matching(origin: layover.airport.iata, destination: layover.onwardAirport.iata) {
                        CityTransferMapCard(
                            origin: layover.airport.iata,
                            destination: layover.onwardAirport.iata,
                            traffic: viewModel.launchContext.qaTrafficLevel ?? "normal",
                            configuration: mapConfiguration
                        )
                    }
                } else if viewModel.itinerary != nil {
                    SurfaceCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(nodeName(viewModel.currentNodeID)) → \(viewModel.destinationNodeID.map(nodeName) ?? "Destination not mapped")").font(.headline)
                                Text(viewModel.terminalRoute.map { "\($0.durationMinutes) min • \(Int($0.distanceMeters)) m • \(viewModel.routeMode.title)" } ?? "We don't have a route yet")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text("Going to: \(viewModel.terminalRouteTitle)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AirportXRPalette.actionTeal)
                            }
                            Spacer()
                            Image(systemName: "location.fill")
                                .foregroundStyle(.teal)
                                .accessibilityHidden(true)
                        }
                    }
                }

                TerminalMapCanvas(
                    graph: graph,
                    route: viewModel.terminalRoute,
                    currentNodeID: viewModel.currentNodeID,
                    selectedNodeID: $selectedNodeID,
                    level: level
                )
                    .frame(height: 360)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.1)) }
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("terminalMapCanvas")

                mapLegend

                if let selectedNode {
                    selectedPlaceCard(selectedNode)
                } else {
                    Text("Tap a place for details.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                manualCalibration

                DisclosureGroup("Route steps", isExpanded: $showSteps) {
                    RouteStepList(graph: graph, route: viewModel.terminalRoute)
                        .padding(.top, 8)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Terminal Map")
        .onAppear { showCurrentLevel() }
        .onChange(of: viewModel.currentNodeID) { _, _ in showCurrentLevel() }
        .onChange(of: level) { _, _ in
            if selectedNode?.level != level { selectedNodeID = nil }
        }
        .onChange(of: geographicTravelMode) { _, _ in
            guard let selected = selectedGeographicAmenity else { return }
            Task { await routeToGeographicResult(selected) }
        }
        .sheet(isPresented: $showsOfficialAirportMap) {
            if let url = officialMapURL {
                InAppSafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .accessibilityIdentifier("terminalMapView")
    }

    @ViewBuilder
    private var officialAirportMap: some View {
        if officialMapURL != nil {
            Button {
                showsOfficialAirportMap = true
            } label: {
                Label("Open official airport map", systemImage: "map.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(AirportXRPalette.actionTeal)
            .accessibilityHint("Opens the airport map inside the app.")
            .accessibilityIdentifier("officialAirportMapButton")
        }
    }

    private var controls: some View {
        SurfaceCard {
            VStack(spacing: 12) {
                Picker("Terminal level", selection: $level) {
                    ForEach(Array(Set(graph.nodes.map(\.level))).sorted(), id: \.self) { value in
                        Text("Level \(value)").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Route mode", selection: Binding(
                    get: { viewModel.routeMode },
                    set: { viewModel.setRouteMode($0) }
                )) {
                    ForEach(RouteMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("routeModePicker")

                Button {
                    showCurrentLevel()
                    selectedNodeID = viewModel.currentNodeID
                } label: {
                    Label("Show my location", systemImage: "location.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                Button {
                    viewModel.routeToGate()
                    showCurrentLevel()
                } label: {
                    Label("Gate route", systemImage: "airplane.departure")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("terminalMapGateRouteButton")
                Text("Starting from: \(nodeName(viewModel.currentNodeID))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var selectedNode: TerminalNode? {
        guard let selectedNodeID else { return nil }
        return graph.nodes.first { $0.id == selectedNodeID }
    }

    private var mapLegend: some View {
        HStack(spacing: 14) {
            Label("You", systemImage: "location.fill").foregroundStyle(.blue)
            Label("Route", systemImage: "circle.fill").foregroundStyle(.teal)
            Label("Selected", systemImage: "circle.fill").foregroundStyle(.orange)
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Map legend: blue is your confirmed or manually set location, teal is the selected route, and orange is the selected place.")
    }

    private func selectedPlaceCard(_ node: TerminalNode) -> some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol(for: node.kind))
                    .font(.title2)
                    .foregroundStyle(AirportXRPalette.actionTeal)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name).font(.headline)
                    Text("Level \(node.level) · \(placeType(for: node.kind))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if node.id == viewModel.currentNodeID {
                    Label("You are here", systemImage: "location.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                } else {
                    VStack(spacing: 8) {
                        Button("Route here") {
                            viewModel.routeToTerminalPlace(node.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AirportXRPalette.actionTeal)
                        Button("Start here") { viewModel.calibrateLocation(to: node.id) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("selectedTerminalPlace")
    }

    private func showCurrentLevel() {
        guard let node = graph.nodes.first(where: { $0.id == viewModel.currentNodeID }) else { return }
        level = node.level
    }

    private func symbol(for kind: TerminalNode.Kind) -> String {
        switch kind {
        case .gate: "airplane"
        case .security: "person.badge.shield.checkmark"
        case .immigration: "person.text.rectangle"
        case .baggage: "suitcase.fill"
        case .restroom: "figure.dress.line.vertical.figure"
        case .restaurant: "fork.knife"
        case .snack: "takeoutbag.and.cup.and.straw.fill"
        case .clothing: "tshirt.fill"
        case .electronics: "headphones"
        case .lounge: "cup.and.saucer.fill"
        case .elevator: "arrow.up.arrow.down.square.fill"
        case .escalator, .stairs: "figure.stairs"
        case .train: "tram.fill"
        case .bus: "bus.fill"
        case .corridor, .marker: "mappin"
        }
    }

    private func placeType(for kind: TerminalNode.Kind) -> String {
        switch kind {
        case .gate: "Gate"
        case .security: "Security"
        case .immigration: "Immigration"
        case .baggage: "Baggage claim"
        case .restroom: "Restroom"
        case .restaurant: "Restaurant"
        case .snack: "Snack or drink"
        case .clothing: "Clothing"
        case .electronics: "Electronics"
        case .lounge: "Lounge"
        case .elevator: "Elevator"
        case .escalator: "Escalator"
        case .stairs: "Stairs"
        case .train: "Train"
        case .bus: "Bus"
        case .corridor: "Walkway"
        case .marker: "Landmark"
        }
    }

    private var manualCalibration: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Set your start point", systemImage: "mappin.and.ellipse").font(.headline)
                Text("Choose a nearby sign or landmark.").font(.subheadline).foregroundStyle(.secondary)
                Menu {
                    ForEach(matchingLandmarks) { node in
                        Button("\(node.name), Level \(node.level)") { viewModel.calibrateLocation(to: node.id) }
                    }
                } label: {
                    Label("Choose known landmark", systemImage: "location.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("manualCalibrationMenu")
                TextField("Search terminal landmark", text: $landmarkSearch)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Text("Selected: \(nodeName(viewModel.currentNodeID)), Level \(graph.nodes.first(where: { $0.id == viewModel.currentNodeID })?.level ?? level)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AirportXRPalette.actionTeal)
            }
        }
    }

    private var matchingLandmarks: [TerminalNode] {
        let query = landmarkSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return graph.nodes
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var findNearby: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Find nearby", systemImage: "magnifyingglass.circle.fill")
                    .font(.headline)
                Text("Find services, food, shops, city places, or a specific item.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Search area", selection: $destinationSearchScope) {
                    ForEach(DestinationSearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("destinationSearchScopePicker")

                Button {
                    nearbyLocation.requestCurrentLocation()
                } label: {
                    Label(nearbyLocation.location == nil ? "Use my location for nearby places" : "Nearby places use my location", systemImage: "location.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(AirportXRPalette.actionTeal)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                    ForEach(PassengerAmenityCategory.allCases) { category in
                        Button {
                            find(category)
                        } label: {
                            Label(category.title, systemImage: category.symbol)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 10)
                                .foregroundStyle(selectedAmenity == category ? Color.white : Color.primary)
                                .background(
                                    selectedAmenity == category ? AirportXRPalette.actionTeal : Color(.tertiarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("findNearby_\(category.rawValue)")
                    }
                }

                HStack(spacing: 8) {
                    TextField("Search for an item", text: $specificItemQuery, prompt: Text(destinationSearchScope.searchPlaceholder))
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { searchForSpecificItem() }
                        .accessibilityLabel("Search for an item")
                        .accessibilityHint("Examples include USB-C charger, ramen, Shibuya, observation deck, or electronics")
                        .accessibilityIdentifier("specificItemSearchField")
                    Button {
                        searchForSpecificItem()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AirportXRPalette.actionTeal)
                    .disabled(specificItemQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    .accessibilityLabel("Search for specific item")
                }
                Text(destinationSearchScope.searchHint)
                    .font(.caption).foregroundStyle(.secondary)

                if let estimate = currentSpendEstimate {
                    HStack(spacing: 8) {
                        TextField(
                            "Maximum spend (\(estimate.currencyCode))",
                            text: $maximumSpendText
                        )
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        Text("Typical \(spendText(estimate))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.teal)
                    }
                }

                if let result = terminalAmenityResult, !(result.matches.isEmpty && !matchingFacilityRecords.isEmpty) {
                    terminalResult(result)
                }

                if !matchingFacilityRecords.isEmpty {
                    Divider()
                    Text("Terminal directory").font(.subheadline.weight(.semibold))
                    ForEach(matchingFacilityRecords) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.place.name).font(.subheadline.weight(.semibold))
                            Text("View the airport’s current listing and floor guide for the location")
                                .font(.caption).foregroundStyle(.secondary)
                            if let url = record.place.officialSourceURL {
                                InAppBrowserLink(url: url) {
                                    Text("View location details").font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                }

                if isSearchingAroundAirport {
                    HStack { ProgressView(); Text("Searching around the airport…") }
                        .font(.subheadline)
                } else if !geographicAmenityResults.isEmpty {
                    geographicResults
                } else if let amenitySearchMessage {
                    Text(amenitySearchMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("findNearbyCard")
    }

    @ViewBuilder
    private func terminalResult(_ result: TerminalAmenitySearchResult) -> some View {
        if result.matches.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("This terminal map does not include a mapped location for \(result.category.title.lowercased()).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if officialMapURL != nil {
                    Button("Check the official airport map") {
                        showsOfficialAirportMap = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else {
            Divider()
            Text(result.hasDistanceTie ? "Closest mapped options" : "Closest mapped option")
                .font(.subheadline.weight(.semibold))
            if result.hasDistanceTie {
                Text("These options are the same walking distance away.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(result.matches) { match in
                Button {
                    level = match.node.level
                    selectedNodeID = match.node.id
                    viewModel.routeToTerminalPlace(match.node.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.node.name).font(.subheadline.weight(.semibold))
                            Text(terminalDistanceLabel(match, currentLevel: result.usesCurrentLevel))
                                .font(.caption).foregroundStyle(.secondary)
                            if let estimate = currentSpendEstimate {
                                Text(budgetLabel(for: estimate))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isWithinBudget(estimate) ? .teal : .orange)
                            }
                        }
                        Spacer()
                        Image(systemName: "map.fill").foregroundStyle(AirportXRPalette.actionTeal)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var matchingFacilityRecords: [AirportFacilityRecord] {
        guard let selectedAmenity else { return [] }
        return viewModel.facilities.filter { record in
            switch selectedAmenity {
            case .meal: record.place.category == .food
            case .restroom: record.id == "hnd-terminal-restrooms"
            case .snackDrink: record.id == "hnd-terminal-snacks"
            case .clothing, .electronics: record.id == "hnd-terminal-shopping"
            }
        }
    }

    private var geographicResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(geographicResultsUseDeviceLocation ? "Closest to you" : "Nearby the airport").font(.subheadline.weight(.semibold))
            if let searchedItemQuery {
                Text("Matches for “\(searchedItemQuery)”")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if geographicNearestTies.count > 1 {
                Text("\(geographicNearestTies.count) places are the same approximate distance from \(geographicResultsUseDeviceLocation ? "you" : "the airport").")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Travel mode", selection: $geographicTravelMode) {
                ForEach(PassengerMapTravelMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("geographicTravelModePicker")

            NearbyPlacesMapView(
                places: geographicMapPlaces,
                selectedPlaceID: $selectedGeographicAmenityID,
                routes: selectedGeographicRoute.map { [$0] } ?? []
            )
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if isLoadingGeographicRoute {
                HStack { ProgressView(); Text("Checking route…") }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let geographicRouteSummary {
                Label(geographicRouteSummary.label, systemImage: geographicRouteSummary.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(geographicRouteSummary.isAvailable ? AirportXRPalette.actionTeal : .secondary)
                    .accessibilityIdentifier("geographicRouteSummary")
            }
            ForEach(geographicAmenityResults) { result in
                HStack {
                    Button {
                        selectedGeographicAmenityID = result.id
                        Task { await routeToGeographicResult(result) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("About \(Int(result.distanceFromSearchCenterMeters.rounded())) m from \(geographicResultsUseDeviceLocation ? "you" : "the airport")")
                                .font(.caption).foregroundStyle(.secondary)
                            if let estimate = currentSpendEstimate {
                                Text(budgetLabel(for: estimate))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isWithinBudget(estimate) ? .teal : .orange)
                            }
                            if let availability = result.itemAvailability {
                                Text(availability.state.passengerLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(availability.state == .confirmedInStock ? .green : .secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button {
                        selectedGeographicAmenityID = result.id
                        Task { await routeToGeographicResult(result) }
                    } label: { Image(systemName: "map.fill") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Show route to \(result.name)")
                    Button {
                        openInMaps(result)
                    } label: { Image(systemName: "arrow.triangle.turn.up.right.diamond.fill") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Open directions to \(result.name)")
                    if let websiteURL = result.websiteURL {
                        InAppBrowserLink(url: websiteURL) { Image(systemName: "safari") }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Website for \(result.name)")
                    }
                    if let callURL = callURL(for: result.phoneNumber) {
                        Link(destination: callURL) { Image(systemName: "phone.fill") }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Call \(result.name)")
                    }
                }
            }
        }
    }

    private var geographicMapPlaces: [LayoverPlace] {
        geographicAmenityResults.map { result in
            LayoverPlace(
                id: result.id,
                name: result.name,
                airportCode: viewModel.activeAirport?.iata ?? "",
                terminal: nil,
                category: result.category == .meal || result.category == .snackDrink ? .food : .facility,
                accessZone: .nearby,
                latitude: result.coordinate.latitude,
                longitude: result.coordinate.longitude,
                summary: "",
                bookingURL: nil,
                officialSourceURL: result.websiteURL,
                dataMode: .live
            )
        }
    }

    private var geographicNearestTies: [GeographicAmenityMatch] {
        guard let nearest = geographicAmenityResults.first else { return [] }
        let displayedNearest = Int(nearest.distanceFromSearchCenterMeters.rounded())
        return geographicAmenityResults.filter { Int($0.distanceFromSearchCenterMeters.rounded()) == displayedNearest }
    }

    private var selectedGeographicAmenity: GeographicAmenityMatch? {
        guard let selectedGeographicAmenityID else { return nil }
        return geographicAmenityResults.first { $0.id == selectedGeographicAmenityID }
    }

    private func find(_ category: PassengerAmenityCategory) {
        selectedAmenity = category
        searchedItemQuery = nil
        selectedGeographicAmenityID = nil
        selectedGeographicRoute = nil
        geographicRouteSummary = nil
        geographicAmenityResults = []
        geographicResultsUseDeviceLocation = false
        amenitySearchMessage = nil
        terminalAmenityResult = TerminalAmenityLocator().nearest(
            category: category,
            in: graph,
            from: viewModel.currentNodeID,
            preferences: preferences.accessibility
        )
        if let first = terminalAmenityResult?.matches.first {
            level = first.node.level
            selectedNodeID = first.node.id
        }

        Task { await findAroundAirport(category) }
    }

    private func searchForSpecificItem() {
        let query = specificItemQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        selectedAmenity = nil
        terminalAmenityResult = nil
        geographicAmenityResults = []
        geographicResultsUseDeviceLocation = false
        selectedGeographicAmenityID = nil
        selectedGeographicRoute = nil
        geographicRouteSummary = nil
        amenitySearchMessage = nil
        searchedItemQuery = query
        Task { await searchAroundAirport(for: query) }
    }

    @MainActor
    private func findAroundAirport(_ category: PassengerAmenityCategory) async {
        guard viewModel.launchContext.mode != .offline else {
            amenitySearchMessage = "Around-airport search is unavailable offline."
            return
        }
        guard let airport = viewModel.activeAirport,
              let center = nearbySearchCenter(for: airport) else {
            amenitySearchMessage = "This airport does not yet have a verified map reference point."
            return
        }
        isSearchingAroundAirport = true
        defer { isSearchingAroundAirport = false }
        do {
            let radius = searchRadius(for: destinationSearchScope)
            geographicAmenityResults = try await MapKitNearbyAmenitySearchService().nearest(
                category: category,
                center: center.coordinate,
                radiusMeters: radius
            )
            geographicResultsUseDeviceLocation = center.usesDeviceLocation
            amenitySearchMessage = geographicAmenityResults.isEmpty
                ? "No current around-airport results were found for this category."
                : nil
        } catch {
            geographicAmenityResults = []
            amenitySearchMessage = "Around-airport search is temporarily unavailable."
        }
    }

    @MainActor
    private func searchAroundAirport(for itemQuery: String) async {
        guard viewModel.launchContext.mode != .offline else {
            amenitySearchMessage = "Item search is unavailable offline."
            return
        }
        guard let airport = viewModel.activeAirport,
              let center = nearbySearchCenter(for: airport) else {
            amenitySearchMessage = "This airport does not yet have a verified map reference point."
            return
        }
        isSearchingAroundAirport = true
        defer { isSearchingAroundAirport = false }
        do {
            let radius = searchRadius(for: destinationSearchScope)
            geographicAmenityResults = try await MapKitNearbyAmenitySearchService().search(
                itemQuery: itemQuery,
                center: center.coordinate,
                radiusMeters: radius
            )
            geographicResultsUseDeviceLocation = center.usesDeviceLocation
            amenitySearchMessage = geographicAmenityResults.isEmpty
                ? "No mapped seller matched this item near the airport."
                : nil
        } catch {
            geographicAmenityResults = []
            amenitySearchMessage = "Item search is temporarily unavailable."
        }
    }

    private func callURL(for phoneNumber: String?) -> URL? {
        guard let phoneNumber else { return nil }
        let allowed = phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard !allowed.isEmpty else { return nil }
        return URL(string: "tel:\(allowed)")
    }

    private func nearbySearchCenter(for airport: Airport) -> (coordinate: CLLocationCoordinate2D, usesDeviceLocation: Bool)? {
        guard let reference = AirportReferencePointRegistry.referencePoint(for: airport.iata) else { return nil }
        let airportLocation = CLLocation(latitude: reference.latitude, longitude: reference.longitude)
        if let deviceLocation = nearbyLocation.location,
           deviceLocation.distance(from: airportLocation) <= NearbyDiscoveryPolicy.current.airportRadiusMeters {
            return (deviceLocation.coordinate, true)
        }
        return (CLLocationCoordinate2D(latitude: reference.latitude, longitude: reference.longitude), false)
    }

    private func terminalDistanceLabel(_ match: TerminalAmenityMatch, currentLevel: Bool) -> String {
        let levelLabel = currentLevel ? "Current level" : "Level \(match.node.level)"
        guard let distance = match.routeDistanceMeters else { return "\(levelLabel) · Route distance unavailable" }
        return "\(levelLabel) · \(Int(distance.rounded())) m by the indoor route"
    }

    private func openInMaps(_ result: GeographicAmenityMatch) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: result.coordinate))
        item.name = result.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: geographicTravelMode.mapsLaunchMode])
    }

    @MainActor
    private func routeToGeographicResult(_ result: GeographicAmenityMatch) async {
        guard let origin = geographicRouteOrigin() else {
            selectedGeographicRoute = nil
            geographicRouteSummary = GeographicRouteSummary(
                label: "Route start unavailable",
                symbol: "location.slash",
                isAvailable: false
            )
            return
        }
        isLoadingGeographicRoute = true
        defer { isLoadingGeographicRoute = false }
        do {
            let route = try await GeographicRouteService().route(
                from: origin,
                to: result.coordinate,
                mode: geographicTravelMode
            )
            selectedGeographicRoute = route
            geographicRouteSummary = GeographicRouteSummary(
                route: route,
                mode: geographicTravelMode,
                destinationName: result.name,
                minutesUntilGateClose: minutesUntilGateClose()
            )
        } catch {
            selectedGeographicRoute = nil
            geographicRouteSummary = GeographicRouteSummary(
                label: "\(geographicTravelMode.title) route unavailable for \(result.name)",
                symbol: geographicTravelMode.symbol,
                isAvailable: false
            )
        }
    }

    private func geographicRouteOrigin() -> CLLocationCoordinate2D? {
        if let location = nearbyLocation.location {
            return location.coordinate
        }
        guard let airport = viewModel.activeAirport,
              let reference = AirportReferencePointRegistry.referencePoint(for: airport.iata) else { return nil }
        return CLLocationCoordinate2D(latitude: reference.latitude, longitude: reference.longitude)
    }

    private func searchRadius(for scope: DestinationSearchScope) -> Double {
        switch scope {
        case .airportArea:
            NearbyDiscoveryPolicy.current.airportRadiusMeters
        case .city:
            NearbyDiscoveryPolicy.current.cityVisitRadiusMeters
        }
    }

    private func minutesUntilGateClose() -> Int? {
        guard let gateClose = viewModel.activeLayover?.onwardGateClose else { return nil }
        return max(0, Int((gateClose.timeIntervalSince(Date()) / 60).rounded(.down)))
    }

    private var currentSpendEstimate: AffordabilityOption? {
        guard let airportCode = viewModel.activeAirport?.iata else { return nil }
        let options = AirportAffordabilityCatalog.options(for: airportCode)
        let query = (searchedItemQuery ?? specificItemQuery).lowercased()
        let optionID: String?
        switch selectedAmenity {
        case .meal: optionID = "hnd-casual-meal"
        case .snackDrink: optionID = "hnd-snack"
        case .clothing: optionID = "hnd-essential-shop"
        case .electronics: optionID = "hnd-electronics"
        default:
            if query.contains("charger") || query.contains("cable") || query.contains("headphone") || query.contains("electronic") {
                optionID = "hnd-electronics"
            } else if query.contains("snack") || query.contains("drink") || query.contains("food") {
                optionID = "hnd-snack"
            } else if query.contains("shirt") || query.contains("cloth") || query.contains("clothing") {
                optionID = "hnd-essential-shop"
            } else {
                optionID = nil
            }
        }
        return optionID.flatMap { id in options.first(where: { $0.id == id }) }
    }

    private func spendText(_ option: AffordabilityOption) -> String {
        guard let low = option.minimumLocalAmount, let high = option.maximumLocalAmount else { return option.currencyCode }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = option.currencyCode
        formatter.maximumFractionDigits = 0
        let lowText = formatter.string(from: low as NSDecimalNumber) ?? "\(low) \(option.currencyCode)"
        let highText = formatter.string(from: high as NSDecimalNumber) ?? "\(high) \(option.currencyCode)"
        return low == high ? lowText : "\(lowText)–\(highText)"
    }

    private func isWithinBudget(_ option: AffordabilityOption) -> Bool {
        guard let limit = Decimal(string: maximumSpendText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let maximum = option.maximumLocalAmount else { return true }
        return maximum <= limit
    }

    private func budgetLabel(for option: AffordabilityOption) -> String {
        isWithinBudget(option) ? "Typical \(spendText(option))" : "Usually above your budget · \(spendText(option))"
    }

    private func nodeName(_ id: String) -> String {
        graph.nodes.first(where: { $0.id == id })?.name ?? id
    }

    private var officialMapURL: URL? {
        guard viewModel.activeAirport?.iata == "HND" else { return nil }
        return URL(string: "https://tokyo-haneda.com/site_resource/floor/pdf/floor__pdf_floor_map_t3_en.pdf")
    }
}

private enum DestinationSearchScope: String, CaseIterable, Identifiable {
    case airportArea
    case city

    var id: String { rawValue }

    var title: String {
        switch self {
        case .airportArea: "Airport area"
        case .city: "City"
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .airportArea: "Search nearby or item"
        case .city: "Search city place"
        }
    }

    var searchHint: String {
        switch self {
        case .airportArea: "Try \"USB-C charger,\" \"snack,\" or \"electronics.\""
        case .city: "Try \"Shibuya,\" \"museum,\" \"park,\" or a restaurant name."
        }
    }
}

private enum PassengerMapTravelMode: String, CaseIterable, Identifiable {
    case transit
    case walking
    case driving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transit: "Transit"
        case .walking: "Walk"
        case .driving: "Car"
        }
    }

    var symbol: String {
        switch self {
        case .transit: "tram.fill"
        case .walking: "figure.walk"
        case .driving: "car.fill"
        }
    }

    var directionsTransportType: MKDirectionsTransportType {
        switch self {
        case .transit: .transit
        case .walking: .walking
        case .driving: .automobile
        }
    }

    var mapsLaunchMode: String {
        switch self {
        case .transit: MKLaunchOptionsDirectionsModeTransit
        case .walking: MKLaunchOptionsDirectionsModeWalking
        case .driving: MKLaunchOptionsDirectionsModeDriving
        }
    }
}

private struct GeographicRouteSummary {
    let label: String
    let symbol: String
    let isAvailable: Bool

    init(label: String, symbol: String, isAvailable: Bool) {
        self.label = label
        self.symbol = symbol
        self.isAvailable = isAvailable
    }

    init(route: MKRoute, mode: PassengerMapTravelMode, destinationName: String, minutesUntilGateClose: Int?) {
        let minutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
        let kilometers = route.distance / 1_000
        let distance = kilometers >= 10
            ? String(format: "%.0f km", kilometers)
            : String(format: "%.1f km", kilometers)
        let remaining = minutesUntilGateClose.map { " · \($0) min until gate close" } ?? ""
        label = "\(mode.title) to \(destinationName): \(minutes) min, \(distance)\(remaining)"
        symbol = mode.symbol
        isAvailable = true
    }
}

private struct GeographicRouteService {
    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        mode: PassengerMapTravelMode
    ) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = mode.directionsTransportType
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
            throw MKError(.directionsNotFound)
        }
        return route
    }
}

private struct TerminalMapCanvas: View {
    let graph: TerminalGraph
    let route: TerminalRoute?
    let currentNodeID: String?
    @Binding var selectedNodeID: String?
    let level: Int

    var body: some View {
        Canvas { context, size in
            let byID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
            let routeEdges = Set(route?.edgeIDs ?? [])

            for edge in graph.edges {
                guard let start = byID[edge.from], let end = byID[edge.to], start.level == level || end.level == level else { continue }
                var path = Path()
                path.move(to: point(start.point, size))
                path.addLine(to: point(end.point, size))
                let color: Color = edge.temporarilyClosed ? .red : routeEdges.contains(edge.id) ? .teal : .gray.opacity(0.38)
                let style = StrokeStyle(lineWidth: routeEdges.contains(edge.id) ? 8 : 5, lineCap: .round, dash: edge.temporarilyClosed ? [8, 6] : [])
                context.stroke(path, with: .color(color), style: style)
            }

            let levelNodes = graph.nodes.filter { $0.level == level }
            let routeNodeIDs = Set(route?.nodeIDs ?? [])
            for node in levelNodes {
                let center = point(node.point, size)
                let emphasized = node.id == currentNodeID || node.id == selectedNodeID
                let radius: CGFloat = emphasized ? 11 : node.kind == .gate ? 8 : 6
                let rectangle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                let color: Color = node.id == currentNodeID ? .blue : node.id == selectedNodeID ? .orange : routeNodeIDs.contains(node.id) ? .teal : node.kind == .gate ? .green : .secondary
                context.fill(Path(ellipseIn: rectangle), with: .color(color))
                if node.id == currentNodeID {
                    let confidence = CGRect(x: center.x - 28, y: center.y - 28, width: 56, height: 56)
                    context.stroke(Path(ellipseIn: confidence), with: .color(.blue.opacity(0.35)), lineWidth: 2)
                }
            }

            drawDeclutteredLabels(
                in: &context,
                size: size,
                nodes: levelNodes,
                routeNodeIDs: routeNodeIDs
            )
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            let nodes = graph.nodes.filter { $0.level == level }
            selectedNodeID = nodes
                .map { ($0.id, distance(from: location, to: point($0.point, canvasSize))) }
                .filter { $0.1 <= 30 }
                .min(by: { $0.1 < $1.1 })?.0
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: TerminalCanvasSizeKey.self, value: proxy.size)
            }
        }
        .onPreferenceChange(TerminalCanvasSizeKey.self) { canvasSize = $0 }
    }

    @State private var canvasSize: CGSize = .zero

    private func drawDeclutteredLabels(
        in context: inout GraphicsContext,
        size: CGSize,
        nodes: [TerminalNode],
        routeNodeIDs: Set<String>
    ) {
        let priorityNodes = nodes.sorted { labelPriority($0, routeNodeIDs) > labelPriority($1, routeNodeIDs) }
        var occupied: [CGRect] = []

        for node in priorityNodes where labelPriority(node, routeNodeIDs) > 0 {
            let center = point(node.point, size)
            let width = min(CGFloat(node.name.count * 7 + 16), min(150, size.width - 12))
            let proposedX = center.x - width / 2
            let clampedX = min(max(proposedX, 6), size.width - width - 6)
            let rect = CGRect(x: clampedX, y: max(center.y - 42, 6), width: width, height: 24)
            guard !occupied.contains(where: { $0.insetBy(dx: -6, dy: -4).intersects(rect) }) else { continue }
            context.fill(
                Path(roundedRect: rect, cornerRadius: 8),
                with: .color(Color(.systemBackground).opacity(0.9))
            )
            context.draw(
                Text(node.name).font(.caption2.weight(.semibold)).foregroundStyle(Color.primary),
                at: CGPoint(x: rect.midX, y: rect.midY)
            )
            occupied.append(rect)
        }
    }

    private func labelPriority(_ node: TerminalNode, _ routeNodeIDs: Set<String>) -> Int {
        if node.id == selectedNodeID { return 4 }
        if node.id == currentNodeID { return 3 }
        if routeNodeIDs.contains(node.id) { return 2 }
        if node.kind == .gate || node.kind == .security || node.kind == .train { return 1 }
        return 0
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func point(_ mapPoint: MapPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: mapPoint.x * size.width, y: mapPoint.y * size.height)
    }
}

private struct TerminalCanvasSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
