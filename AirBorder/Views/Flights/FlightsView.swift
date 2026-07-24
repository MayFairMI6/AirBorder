import SwiftUI
import UniformTypeIdentifiers

struct FlightsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case search = "Search"
        case board = "Airport board"
        case bookBags = "Book & bags"
        var id: String { rawValue }
    }

    @EnvironmentObject private var viewModel: FlightsViewModel
    @EnvironmentObject private var longHaulViewModel: LongHaulExperienceViewModel
    @EnvironmentObject private var container: AppContainer
    @State private var mode: Mode = .search
    @State private var offerOrigin = ""
    @State private var offerDestination = ""
    @State private var offerDepartureDate = Date()
    @State private var offerAdultCount = 1
    @State private var offerSearchAttempted = false
    @State private var offerInputError: String?
    @State private var initializedOfferItineraryID: UUID?
    @State private var isImportingTicketPDF = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                itineraryEditor

                Picker("Flight lookup mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .search:
                    searchForm
                case .board:
                    boardForm
                case .bookBags:
                    bookAndBags
                }

                if mode != .bookBags {
                    if let warning = viewModel.warning { InlineNotice(message: warning, symbol: "info.circle.fill", color: .purple) }
                    if let error = viewModel.errorMessage { InlineNotice(message: error, symbol: "exclamationmark.triangle.fill", color: .orange) }
                    results
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: AirportXRLayout.floatingTabBarClearance)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Flights")
        .task(id: longHaulViewModel.itinerary?.id) {
            initializeOfferFieldsIfNeeded()
        }
        .fileImporter(
            isPresented: $isImportingTicketPDF,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            importTicketPDF(result)
        }
    }

    private var itineraryEditor: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Itinerary").font(.headline)
                        Text("Your connection times update automatically in each airport’s local time.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await longHaulViewModel.refreshAllLegs() }
                    } label: {
                        if longHaulViewModel.isRefreshing { ProgressView() }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Refresh all itinerary legs")
                    .accessibilityIdentifier("refreshItineraryButton")
                }

                if let itinerary = longHaulViewModel.itinerary, !itinerary.legs.isEmpty {
                    ForEach(Array(itinerary.legs.enumerated()), id: \.element.id) { index, leg in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Flight details")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                NavigationLink {
                                    FlightLegEditorView(leg: leg)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                        .frame(minHeight: 44)
                                }
                                .accessibilityLabel("Edit leg \(index + 1)")
                            }
                            AirlineFlightSummary(
                                flight: leg.flight,
                                legNumber: index + 1,
                                legCount: itinerary.legs.count
                            )
                            HStack {
                                Button {
                                    Task { await longHaulViewModel.moveLeg(from: IndexSet(integer: index), to: index - 1) }
                                } label: { Label("Earlier", systemImage: "arrow.up") }
                                    .disabled(index == 0)
                                Button {
                                    Task { await longHaulViewModel.moveLeg(from: IndexSet(integer: index), to: index + 2) }
                                } label: { Label("Later", systemImage: "arrow.down") }
                                    .disabled(index == itinerary.legs.count - 1)
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await longHaulViewModel.removeLeg(id: leg.id) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            if index < itinerary.legs.count - 1 { Divider() }
                        }
                    }
                } else {
                    Text("No legs yet. Search below to add the first flight.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("itineraryEditor")
    }

    private var searchForm: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add an itinerary leg").font(.headline)
                HStack {
                    TextField("Airline", text: $viewModel.airlineCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 110)
                        .accessibilityLabel("Airline code")
                        .accessibilityIdentifier("airlineCodeField")
                    TextField("Flight number", text: $viewModel.flightNumber)
                        .keyboardType(.asciiCapableNumberPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("flightNumberField")
                }
                DatePicker("Travel date", selection: $viewModel.travelDate, displayedComponents: .date)
                Button {
                    Task { await viewModel.search() }
                } label: {
                    Group {
                        if viewModel.isLoading { ProgressView().tint(.white) }
                        else { Label("Search flights", systemImage: "magnifyingglass") }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(viewModel.isLoading)
                .accessibilityIdentifier("searchFlightButton")
            }
        }
    }

    private var boardForm: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Airport board").font(.headline)
                TextField("Airport code", text: $viewModel.airportCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("airportCodeField")
                Picker("Board type", selection: $viewModel.boardKind) {
                    Text("Departures").tag(AirportBoardKind.departures)
                    Text("Arrivals").tag(AirportBoardKind.arrivals)
                }
                .pickerStyle(.segmented)
                DatePicker("Date", selection: $viewModel.travelDate, displayedComponents: .date)
                Button {
                    Task { await viewModel.loadBoard() }
                } label: {
                    Label("Load \(viewModel.boardKind.rawValue)", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(viewModel.isLoading)
            }
        }
    }

    private var bookAndBags: some View {
        VStack(alignment: .leading, spacing: 16) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Connection baggage", systemImage: "suitcase.rolling.fill")
                        .font(.title3.bold())
                        .accessibilityIdentifier("bookAndBagsPanel")
                    Text("We’ll show whether your checked bag is likely to continue automatically or needs to be collected and checked again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Save your flight details here; complete bookings directly with your chosen airline or travel provider.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ticketPDFCard

            if let itinerary = longHaulViewModel.itinerary, itinerary.legs.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connections").font(.title2.bold())
                    ForEach(Array(0..<(itinerary.legs.count - 1)), id: \.self) { index in
                        connectionCard(itinerary: itinerary, index: index)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No connection yet",
                    systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                    description: Text("Add at least two flights to check connection baggage handling.")
                )
            }

            bookingOfferForm
        }
    }

    private func connectionCard(itinerary: Itinerary, index: Int) -> some View {
        let inbound = itinerary.legs[index]
        let outbound = itinerary.legs[index + 1]
        let scannedStatus = ticketConnectionStatus(inbound: inbound, outbound: outbound)
        let presentation = scannedStatus.map { scannedBaggagePresentation($0) } ?? baggagePresentation(
            itinerary: itinerary,
            inbound: inbound,
            outbound: outbound
        )
        let airportChange = inbound.flight.destination.iata != outbound.flight.origin.iata

        return SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Connection \(index + 1)")
                            .font(.headline)
                        Text("\(inbound.flight.flightNumber) → \(outbound.flight.flightNumber)")
                            .font(.subheadline)
                        Text(airportChange
                            ? "\(inbound.flight.destination.iata) → \(outbound.flight.origin.iata) airport transfer"
                            : "At \(inbound.flight.destination.iata)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(presentation.modeLabel)
                        .font(.caption2.bold())
                        .foregroundStyle(presentation.modeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(presentation.modeColor.opacity(0.12), in: Capsule())
                }

                HStack(spacing: 8) {
                    Image(systemName: presentation.state.symbol)
                        .accessibilityHidden(true)
                    Text(presentation.state.title)
                }
                    .font(.title3.bold())
                    .foregroundStyle(presentation.state.color)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(presentation.state.title)
                    .accessibilityIdentifier("connectionBaggageState-\(index)")

                if let destination = presentation.fact?.value.bagTagDestinationAirportCode {
                    LabeledContent("Bag tag destination", value: destination)
                        .font(.subheadline)
                }
                if presentation.fact?.value.separateTickets == true {
                    Label("Separate-ticket self-transfer", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                ForEach(presentation.fact?.value.instructions ?? [], id: \.self) { instruction in
                    Text(instruction)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let scannedStatus {
                    Label(scannedStatus.transitStatus.title, systemImage: scannedStatus.transitStatus.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(scannedStatus.transitStatus.color)
                        .accessibilityIdentifier("connectionTransitStatus-\(index)")
                    Text(scannedStatus.transitStatus.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        EntryCheckView()
                    } label: {
                        Label("Review entry details", systemImage: "person.text.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
                Text("What to allow time for")
                    .font(.subheadline.bold())
                if presentation.requiredSegments.isEmpty {
                    Text(presentation.state == .throughChecked
                        ? "No bag collection is shown for this connection. Border, security, and walking time are considered separately."
                        : "We need baggage instructions before estimating the time needed for this connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presentation.requiredSegments, id: \.self) { kind in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: kind.symbol)
                                .foregroundStyle(.teal)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title).font(.subheadline.weight(.semibold))
                                if let distribution = presentation.inputs?.durations[kind]?.value {
                                    Text("About \(Int(distribution.mostLikely.rounded())) min")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("We don't have enough information")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }

                if presentation.requiredSegments.contains(.bagDropAndCheckIn) {
                    if let cutoff = presentation.inputs?.deadlines[.bagDropAndCheckIn]?.value {
                        LabeledContent(
                            "Bag-drop/check-in cutoff",
                            value: cutoff.formatted(date: .abbreviated, time: .shortened)
                        )
                        .font(.subheadline.weight(.semibold))
                    } else {
                        InlineNotice(
                            message: "Confirm the bag-drop and check-in deadline before relying on this connection.",
                            symbol: "clock.badge.exclamationmark.fill",
                            color: .orange
                        )
                    }
                }

                if !presentation.unresolvedFacts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Check before you go").font(.footnote.bold())
                        ForEach(presentation.unresolvedFacts, id: \.self) { fact in
                            Text("• \(fact)").font(.footnote)
                        }
                    }
                    .foregroundStyle(.orange)
                }

                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last checked").font(.caption.bold())
                    if let observed = presentation.fact?.observedAt {
                        Text("Observed \(observed.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("connectionBaggageCard-\(index)")
    }

    private var ticketPDFCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Saved tickets", systemImage: "doc.text.viewfinder")
                            .font(.title3.bold())
                        Text("Add a ticket or boarding-pass PDF to keep its trip details with this itinerary.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if longHaulViewModel.isScanningTicketPDF {
                        ProgressView()
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }

                if let scan = longHaulViewModel.ticketScanResult {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Ticket", value: scan.fileName)
                        if !scan.routeAirportCodes.isEmpty {
                            LabeledContent("Route found", value: scan.routeAirportCodes.joined(separator: " → "))
                        }
                        if !scan.flightNumbers.isEmpty {
                            LabeledContent("Flights found", value: scan.flightNumbers.joined(separator: ", "))
                        }
                        Text(longHaulViewModel.ticketScanMessage ?? "Ticket added.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    if scan.routeAirportCodes.count >= 2 {
                        Button {
                            Task { await longHaulViewModel.applyScannedTicketRoute() }
                        } label: {
                            Label("Use this route", systemImage: "arrow.triangle.branch")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.teal)
                    }
                } else if let message = longHaulViewModel.ticketScanMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button {
                        isImportingTicketPDF = true
                    } label: {
                        Label(longHaulViewModel.ticketScanResult == nil ? "Add ticket PDF" : "Replace ticket PDF", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(longHaulViewModel.isScanningTicketPDF)
                    .accessibilityIdentifier("addTicketPDFButton")

                    if longHaulViewModel.ticketScanResult != nil {
                        Button {
                            longHaulViewModel.clearTicketScan()
                        } label: {
                            Label("Remove", systemImage: "xmark")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("removeTicketPDFButton")
                    }
                }
            }
        }
    }

    private func importTicketPDF(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            Task {
                await longHaulViewModel.scanTicketPDF(data: data, fileName: url.lastPathComponent)
            }
        } catch {
            Task {
                await longHaulViewModel.scanTicketPDF(data: Data(), fileName: "ticket.pdf")
            }
        }
    }

    private var bookingOfferForm: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("External flight offers", systemImage: "arrow.up.right.square.fill")
                    .font(.title3.bold())
                Text("Compare current flight offers, then continue with the airline or booking service to complete your purchase.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("From", text: $offerOrigin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Offer origin airport")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("To", text: $offerDestination)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Offer destination airport")
                }
                DatePicker("Departure date", selection: $offerDepartureDate, displayedComponents: .date)
                Stepper("Adult travelers: \(offerAdultCount)", value: $offerAdultCount, in: 1...9)

                Button {
                    searchBookingOffers()
                } label: {
                    Label("Compare fares", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .accessibilityIdentifier("searchBookingOffersButton")

                if let offerInputError {
                    InlineNotice(message: offerInputError, symbol: "exclamationmark.triangle.fill", color: .orange)
                }
                if offerSearchAttempted, offerInputError == nil {
                    bookingOfferResult
                }
            }
        }
    }

    @ViewBuilder private var bookingOfferResult: some View {
        if offerSearchAttempted, offerInputError == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Compare fares")
                    .font(.caption.bold())
                    .foregroundStyle(.teal)
                Text("\(offerOrigin) → \(offerDestination)")
                    .font(.headline)
                Text("\(offerDepartureDate.formatted(date: .abbreviated, time: .omitted)) · \(offerAdultCount) traveler\(offerAdultCount == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                InAppBrowserLink(url: googleFlightsURL) {
                    Label("Open Google Flights", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("googleFlightsHandoffLink")
                Text("Compare on another site")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    InAppBrowserLink(url: skyscannerURL) {
                        Label("Skyscanner", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("skyscannerHandoffLink")
                    InAppBrowserLink(url: kayakURL) {
                        Label("KAYAK", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("kayakHandoffLink")
                }
            }
            .padding(12)
            .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        } else {
            let message = bookingUnavailableMessage
            InlineNotice(message: message, symbol: "rectangle.slash.fill", color: .orange)
                .accessibilityIdentifier("bookingOfferUnavailableNotice")
        }
    }

    private var isFixtureLaunch: Bool {
        longHaulViewModel.launchContext.mode == .demo
            || longHaulViewModel.launchContext.mode == .stochastic
    }

    private var operationalFixture: FlightOperationalReferenceFixture? {
        guard isFixtureLaunch, let itinerary = longHaulViewModel.itinerary else { return nil }
        let seed = longHaulViewModel.launchContext.simulationSeed
        let anchor = itinerary.createdAt
        if itinerary.layovers.first?.isInterAirportTransfer == true {
            return FlightOperationalReferenceFixtures.hndToNrt(
                anchor: anchor,
                seed: seed ?? FlightOperationalReferenceFixtures.hndNrtSeed
            )
        }
        return FlightOperationalReferenceFixtures.bkkHndLax(
            anchor: anchor,
            seed: seed ?? StableSimulationSeed.digest("demo-bkk-hnd-lax-operational-intelligence-v1")
        )
    }

    private func baggagePresentation(
        itinerary: Itinerary,
        inbound: ItineraryLeg,
        outbound: ItineraryLeg
    ) -> ConnectionBaggagePresentation {
        if let fixture = operationalFixture,
           fixtureMatchesConnection(fixture.connectionQuery, inbound: inbound, outbound: outbound) {
            let state = fixture.baggageHandling.value.state
            return ConnectionBaggagePresentation(
                state: state,
                fact: fixture.baggageHandling,
                inputs: fixture.planningInputs,
                requiredSegments: requiredSegments(
                    state: state,
                    changesAirport: inbound.flight.destination.iata != outbound.flight.origin.iata
                ),
                unresolvedFacts: [],
                modeLabel: "Trip details",
                modeColor: .purple,
                provenance: "Review your ticket or airline app before travel."
            )
        }

        let modeLabel = longHaulViewModel.launchContext.mode == .offline ? "OFFLINE · CHECK AIRLINE" : "CHECK WITH AIRLINE"
        return ConnectionBaggagePresentation(
            state: .unknown,
            fact: nil,
            inputs: nil,
            requiredSegments: [],
            unresolvedFacts: [
                "current airline/order/PNR baggage-handling fact",
                "bag-tag destination or reclaim instruction",
                "bag-drop/check-in cutoff when recheck is required"
            ],
            modeLabel: modeLabel,
            modeColor: .orange,
            provenance: "Baggage instructions are not available for this connection."
        )
    }

    private func ticketConnectionStatus(
        inbound: ItineraryLeg,
        outbound: ItineraryLeg
    ) -> TicketConnectionStatus? {
        longHaulViewModel.ticketConnectionStatuses.first {
            $0.inboundLegID == inbound.id && $0.outboundLegID == outbound.id
        }
    }

    private func scannedBaggagePresentation(_ status: TicketConnectionStatus) -> ConnectionBaggagePresentation {
        ConnectionBaggagePresentation(
            state: status.baggageAssessment.state,
            fact: status.baggageAssessment.handling,
            inputs: nil,
            requiredSegments: status.requiredSegments,
            unresolvedFacts: status.baggageAssessment.state == .unknown ? ["bag instructions from the ticket"] : [],
            modeLabel: "TICKET",
            modeColor: .teal,
            provenance: status.sourceRecordID
        )
    }

    private func fixtureMatchesConnection(
        _ query: ConnectionBaggageQuery,
        inbound: ItineraryLeg,
        outbound: ItineraryLeg
    ) -> Bool {
        let exactLegs = query.inboundLegID == inbound.id && query.outboundLegID == outbound.id
        let sameRoute = query.inboundArrivalAirportCode.caseInsensitiveCompare(inbound.flight.destination.iata) == .orderedSame
            && query.outboundDepartureAirportCode.caseInsensitiveCompare(outbound.flight.origin.iata) == .orderedSame
        return exactLegs || sameRoute
    }

    private func requiredSegments(
        state: ConnectionBaggageState,
        changesAirport: Bool
    ) -> [ConnectionPlanningSegmentKind] {
        var kinds: [ConnectionPlanningSegmentKind]
        switch state {
        case .throughChecked, .confirmationRequired, .unknown:
            kinds = []
        case .reclaimImmigrationCustomsRecheck:
            kinds = [.baggageWait, .borderProcessing, .customsProcessing, .landsideTransfer, .bagDropAndCheckIn, .securityScreening]
        case .selfTransferSeparateTicket:
            kinds = [.baggageWait, .landsideTransfer, .bagDropAndCheckIn, .securityScreening]
        }
        if changesAirport { kinds.append(.interAirportTravel) }
        return kinds
    }

    private func initializeOfferFieldsIfNeeded() {
        guard let itinerary = longHaulViewModel.itinerary,
              initializedOfferItineraryID != itinerary.id else { return }
        initializedOfferItineraryID = itinerary.id
        let route = operationalFixture?.offerSearch.routes.first
        offerOrigin = route?.originAirportCode ?? itinerary.legs.first?.flight.origin.iata ?? ""
        offerDestination = route?.destinationAirportCode ?? itinerary.legs.last?.flight.destination.iata ?? ""
        offerDepartureDate = route?.departureDate ?? itinerary.legs.first?.flight.effectiveDeparture ?? Date()
        offerAdultCount = 1
        offerSearchAttempted = false
        offerInputError = nil
    }

    private func searchBookingOffers() {
        let origin = normalizedIATA(offerOrigin)
        let destination = normalizedIATA(offerDestination)
        guard origin.count == 3, destination.count == 3, origin != destination else {
            offerInputError = "Enter two different three-letter airport codes."
            offerSearchAttempted = false
            return
        }
        offerOrigin = origin
        offerDestination = destination
        offerInputError = nil
        offerSearchAttempted = true
    }

    private func demoOfferMatches(_ fixture: FlightOperationalReferenceFixture) -> Bool {
        guard let route = fixture.offerSearch.routes.first else { return false }
        return normalizedIATA(offerOrigin) == route.originAirportCode
            && normalizedIATA(offerDestination) == route.destinationAirportCode
            && offerAdultCount == fixture.offerSearch.travelers.adults
            && Calendar.current.isDate(offerDepartureDate, inSameDayAs: route.departureDate)
    }

    private var googleFlightsURL: URL {
        var components = URLComponents(string: "https://www.google.com/travel/flights")!
        let date = offerDepartureDate.formatted(.iso8601.year().month().day())
        components.queryItems = [
            URLQueryItem(
                name: "q",
                value: "Flights from \(offerOrigin) to \(offerDestination) on \(date) for \(offerAdultCount) adult\(offerAdultCount == 1 ? "" : "s")"
            )
        ]
        return components.url!
    }

    private var skyscannerURL: URL {
        return URL(string: "https://www.skyscanner.com/transport/flights/\(offerOrigin.lowercased())/\(offerDestination.lowercased())/\(fareDate(format: "yyMMdd"))/")!
    }

    private var kayakURL: URL {
        return URL(string: "https://www.kayak.com/flights/\(offerOrigin)-\(offerDestination)/\(fareDate(format: "yyyy-MM-dd"))")!
    }

    private func fareDate(format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: offerDepartureDate)
    }

    private var bookingUnavailableMessage: String {
        if isFixtureLaunch {
            return "No matching fare found for that route, date, and traveler count."
        }
        if longHaulViewModel.launchContext.mode == .offline {
            return "Current prices are unavailable while offline."
        }
        return "Current fares are not available in the app. Continue with the airline or booking service."
    }

    private func normalizedIATA(_ value: String) -> String {
        String(value.uppercased().filter(\.isLetter).prefix(3))
    }

    @ViewBuilder private var results: some View {
        if !viewModel.results.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(mode == .search ? "Search results" : viewModel.boardKind.rawValue.capitalized).font(.title2.bold())
                    Spacer()
                    Text(viewModel.freshness.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(viewModel.results) { flight in
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            NavigationLink {
                                FlightDetailView(flight: flight)
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(flight.flightNumber).font(.title2.bold())
                                        Text("\(flight.origin.iata) → \(flight.destination.iata)")
                                        Text(flight.effectiveDeparture?.formatted(date: .abbreviated, time: .shortened) ?? "Time not supplied")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    StatusPill(status: flight.status)
                                }
                            }
                            .buttonStyle(.plain)
                            Button("Add to itinerary") {
                                Task {
                                    await longHaulViewModel.addLeg(flight)
                                    container.selectedTab = .journey
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("addItineraryLegButton")
                        }
                    }
                    .accessibilityIdentifier("flightSearchResult")
                }
            }
        } else if !viewModel.isLoading && viewModel.errorMessage == nil {
            ContentUnavailableView("Search flights", systemImage: "airplane", description: Text("Results show whether details are current, saved, or need refresh."))
                .padding(.top, 24)
        }
    }
}

private struct ConnectionBaggagePresentation {
    let state: ConnectionBaggageState
    let fact: SourcedAirlineFact<ConnectionBaggageHandling>?
    let inputs: ConnectionPlanningInputs?
    let requiredSegments: [ConnectionPlanningSegmentKind]
    let unresolvedFacts: [String]
    let modeLabel: String
    let modeColor: Color
    let provenance: String
}

private extension ConnectionBaggageState {
    var title: String {
        switch self {
        case .throughChecked: "Through-checked"
        case .reclaimImmigrationCustomsRecheck: "Reclaim · immigration · customs · recheck"
        case .selfTransferSeparateTicket: "Self-transfer / separate ticket"
        case .confirmationRequired: "Confirmation required"
        case .unknown: "Baggage handling unknown"
        }
    }

    var symbol: String {
        switch self {
        case .throughChecked: "checkmark.circle.fill"
        case .reclaimImmigrationCustomsRecheck: "arrow.trianglehead.2.clockwise.rotate.90"
        case .selfTransferSeparateTicket: "exclamationmark.triangle.fill"
        case .confirmationRequired: "questionmark.circle.fill"
        case .unknown: "questionmark.diamond.fill"
        }
    }

    var color: Color {
        switch self {
        case .throughChecked: .green
        case .reclaimImmigrationCustomsRecheck: .blue
        case .selfTransferSeparateTicket: .orange
        case .confirmationRequired, .unknown: .orange
        }
    }
}

private extension ConnectionPlanningSegmentKind {
    var title: String {
        switch self {
        case .baggageWait: "Baggage reclaim wait"
        case .borderProcessing: "Immigration / border processing"
        case .customsProcessing: "Customs processing"
        case .landsideTransfer: "Landside connection movement"
        case .bagDropAndCheckIn: "Bag drop and check-in"
        case .securityScreening: "Security screening"
        case .interAirportTravel: "Inter-airport travel"
        }
    }

    var symbol: String {
        switch self {
        case .baggageWait: "suitcase.rolling.fill"
        case .borderProcessing: "person.text.rectangle.fill"
        case .customsProcessing: "doc.text.magnifyingglass"
        case .landsideTransfer: "figure.walk"
        case .bagDropAndCheckIn: "suitcase.cart.fill"
        case .securityScreening: "shield.checkered"
        case .interAirportTravel: "bus.fill"
        }
    }
}

private extension TicketTransitStatus {
    var symbol: String {
        switch self {
        case .current: "checkmark.shield.fill"
        case .mayNeedAuthorization, .conditional: "person.text.rectangle.fill"
        case .addTravelerDetails: "person.crop.circle.badge.plus"
        case .refreshNeeded: "arrow.clockwise.circle.fill"
        case .notEnoughInformation: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .current: .green
        case .mayNeedAuthorization, .conditional, .refreshNeeded, .notEnoughInformation, .addTravelerDetails: .orange
        }
    }
}

struct FlightLegEditorView: View {
    @EnvironmentObject private var viewModel: LongHaulExperienceViewModel
    @Environment(\.dismiss) private var dismiss
    let leg: ItineraryLeg
    @State private var flightNumber: String
    @State private var originCode: String
    @State private var destinationCode: String
    @State private var departureTerminal: String
    @State private var arrivalTerminal: String
    @State private var gate: String

    init(leg: ItineraryLeg) {
        self.leg = leg
        _flightNumber = State(initialValue: leg.flight.flightNumber)
        _originCode = State(initialValue: leg.flight.origin.iata)
        _destinationCode = State(initialValue: leg.flight.destination.iata)
        _departureTerminal = State(initialValue: leg.flight.departureTerminal ?? "")
        _arrivalTerminal = State(initialValue: leg.flight.arrivalTerminal ?? "")
        _gate = State(initialValue: leg.flight.gate ?? "")
    }

    var body: some View {
        Form {
            Section("Flight") {
                TextField("Flight number", text: $flightNumber)
                    .textInputAutocapitalization(.characters)
                TextField("Origin IATA", text: $originCode)
                    .textInputAutocapitalization(.characters)
                TextField("Destination IATA", text: $destinationCode)
                    .textInputAutocapitalization(.characters)
            }
            Section("Terminal and gate") {
                TextField("Departure terminal", text: $departureTerminal)
                TextField("Arrival terminal", text: $arrivalTerminal)
                TextField("Departure gate", text: $gate)
            }
            Section {
                Text("To update scheduled times, search for the flight again or refresh it.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Save leg") {
                    Task {
                        await viewModel.updateLeg(updatedLeg())
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .accessibilityIdentifier("saveFlightLegButton")
            }
        }
        .navigationTitle("Edit Flight Leg")
    }

    private func updatedLeg() -> ItineraryLeg {
        let existing = leg.flight
        let origin = Airport(
            iata: normalizedIATA(originCode),
            icao: existing.origin.icao,
            name: existing.origin.name,
            city: existing.origin.city,
            timeZone: existing.origin.timeZone
        )
        let destination = Airport(
            iata: normalizedIATA(destinationCode),
            icao: existing.destination.icao,
            name: existing.destination.name,
            city: existing.destination.city,
            timeZone: existing.destination.timeZone
        )
        let flight = Flight(
            id: existing.id,
            flightNumber: flightNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            airlineCode: existing.airlineCode,
            airlineName: existing.airlineName,
            origin: origin,
            destination: destination,
            status: existing.status,
            scheduledDeparture: existing.scheduledDeparture,
            estimatedDeparture: existing.estimatedDeparture,
            actualDeparture: existing.actualDeparture,
            scheduledArrival: existing.scheduledArrival,
            estimatedArrival: existing.estimatedArrival,
            actualArrival: existing.actualArrival,
            departureTerminal: departureTerminal.nilIfBlank,
            arrivalTerminal: arrivalTerminal.nilIfBlank,
            gate: gate.nilIfBlank,
            arrivalGate: existing.arrivalGate,
            previousGate: existing.previousGate,
            boardingStatus: existing.boardingStatus,
            boardingGroup: existing.boardingGroup,
            boardingTime: existing.boardingTime,
            delayMinutes: existing.delayMinutes,
            aircraftType: existing.aircraftType,
            baggageClaim: existing.baggageClaim,
            source: existing.source
        )
        return ItineraryLeg(id: leg.id, flight: flight, onBlockTime: leg.onBlockTime, gateCloseTime: leg.gateCloseTime)
    }

    private func normalizedIATA(_ value: String) -> String {
        String(value.uppercased().filter(\.isLetter).prefix(3))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct FlightDetailView: View {
    let flight: Flight

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(flight.flightNumber).font(.largeTitle.bold())
                    Text("\(flight.origin.iata) to \(flight.destination.iata)").font(.title3)
                    StatusPill(status: flight.status)
                }
                .padding(.vertical, 8)
            }
            Section("Departure") {
                LabeledContent("Scheduled", value: formatted(flight.scheduledDeparture))
                LabeledContent("Estimated", value: formatted(flight.estimatedDeparture))
                LabeledContent("Actual", value: formatted(flight.actualDeparture))
                LabeledContent("Terminal", value: flight.departureTerminal ?? "Not supplied")
                LabeledContent("Gate", value: flight.gate ?? "Not supplied")
                if let old = flight.previousGate { LabeledContent("Previous gate", value: old) }
            }
            Section("Arrival") {
                LabeledContent("Scheduled", value: formatted(flight.scheduledArrival))
                LabeledContent("Estimated", value: formatted(flight.estimatedArrival))
                LabeledContent("Terminal", value: flight.arrivalTerminal ?? "Not supplied")
                LabeledContent("Baggage claim", value: flight.baggageClaim ?? "Not supplied")
            }
            Section("Flight updates") {
                LabeledContent("Last checked", value: formatted(flight.source.providerUpdatedAt))
                Text(flight.source.isDemo ? "Practice flight details." : "Some flight details may not be available yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Flight detail")
        .accessibilityIdentifier("flightDetailView")
    }

    private func formatted(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Not supplied"
    }
}

struct DepartureBoardView: View {
    @EnvironmentObject private var viewModel: FlightsViewModel
    var body: some View { FlightsView().onAppear { viewModel.boardKind = .departures } }
}

struct ArrivalBoardView: View {
    @EnvironmentObject private var viewModel: FlightsViewModel
    var body: some View { FlightsView().onAppear { viewModel.boardKind = .arrivals } }
}
