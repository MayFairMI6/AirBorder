import MapKit
import SwiftUI

struct TransitView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var viewModel: LongHaulExperienceViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedNearbyPlaceID: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                LaunchDataModeBanner(context: viewModel.launchContext, freshness: viewModel.freshness)
                if viewModel.activeLayover == nil {
                    transitSetup
                } else {
                    if let layover = viewModel.activeLayover, layover.isInterAirportTransfer {
                        interAirportTransferCard(layover)
                    } else {
                        selfTransferCard
                    }
                    zonePicker
                    categoryFilters
                    if viewModel.selectedCategories.isEmpty {
                        zonePlans
                        affordabilityLayer
                    }
                    facilityResults
                    if viewModel.selectedZone == .nearby {
                        nearbyResults
                    }
                    if let message = viewModel.statusMessage {
                        InlineNotice(message: message)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Layover & Transit")
        .task(id: viewModel.selectedZone) {
            if viewModel.selectedZone == .nearby { await viewModel.discoverNearbyPlaces() }
        }
        .task(id: viewModel.activeAirport?.iata) {
            await viewModel.refreshAffordability()
        }
        .onChange(of: viewModel.discoveredPlaces.map(\.id)) { _, ids in
            if let selectedNearbyPlaceID, !ids.contains(selectedNearbyPlaceID) {
                self.selectedNearbyPlaceID = nil
            }
        }
        .accessibilityIdentifier("layoverTransitView")
    }

    private var transitSetup: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Add an itinerary to plan your layover", systemImage: "airplane.connection")
                    .font(.title3.bold())
                Text("Add your arriving and onward flights to plan a layover.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    container.selectedTab = .flights
                } label: {
                    Label("Add flights", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AirportXRPalette.actionTeal)
                .accessibilityIdentifier("transitAddFlightsButton")
            }
        }
        .accessibilityIdentifier("transitSetupCard")
    }

    private func interAirportTransferCard(_ layover: LayoverContext) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 11) {
                Label("Airport transfer", systemImage: "arrow.left.arrow.right.circle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
                if layover.airportChangeAssessment.metroArea != nil {
                    LabeledContent("Your route", value: "\(layover.airport.iata) → \(layover.onwardAirport.iata)")
                        .font(.caption)
                } else {
                    Text("This connection uses two airports. Plan time to travel between them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Reach your next airport before adding a stop.")
                    .font(.subheadline)
                arrivalTarget(layover)
                transferChecklist
                if let plan = viewModel.interAirportTransferPlan {
                    if let selected = plan.selected {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Quickest direct route")
                                    .font(.caption.weight(.bold)).foregroundStyle(.teal)
                                Text(selected.title).font(.headline)
                                Text(selected.duration.map { "About \(Int($0.value.mostLikely.rounded())) min" } ?? "Travel time unavailable")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "tram.fill").foregroundStyle(.teal)
                        }
                    } else {
                        InlineNotice(
                            message: "We don't have enough information to choose the fastest transfer yet.",
                            symbol: "questionmark.circle.fill",
                            color: .orange
                        )
                    }
                    DisclosureGroup("Other ways to travel") {
                        ForEach(plan.ranked) { option in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title).font(.subheadline.weight(.semibold))
                                Text(option.duration.map { "About \(Int($0.value.mostLikely.rounded())) min" } ?? "Travel time unavailable")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(option.luggageNotes).font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(transferAccessibilityLabel(option))
                        }
                    }
                }
                Button {
                    viewModel.startInterAirportTransfer()
                } label: {
                    Label("Start \(layover.airport.iata) → \(layover.onwardAirport.iata) transfer", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .accessibilityHint("Selects the mandatory transfer-first plan. Verify live service details before departure.")
                .accessibilityIdentifier("startInterAirportTransferButton")
            }
        }
        .accessibilityIdentifier("interAirportTransferCard")
    }

    private var transferChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AIRPORT-CHANGE STEPS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
            ForEach(Array(TransferStep.airportChange.enumerated()), id: \.element.id) { index, step in
                checklistRow("\(index + 1)", "\(step.title): \(step.detail)")
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("interAirportTransferChecklist")
    }

    private var selfTransferCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 11) {
                Label("Connection type", systemImage: "arrow.triangle.swap")
                    .font(.title3.bold())
                Text(viewModel.transferFlow.title)
                    .font(.subheadline.weight(.semibold))
                if let ticketStatus = viewModel.activeTicketConnectionStatus {
                    Text(ticketStatus.baggageAssessment.advisory)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if viewModel.transferFlow == .selfTransfer {
                    Text("SELF-TRANSFER STEPS")
                        .font(.caption.weight(.bold)).foregroundStyle(.orange)
                    Text("Separate bookings can require re-entry, baggage collection, and a new check-in. Verify each airline's cutoff.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(Array(TransferStep.selfTransfer.enumerated()), id: \.element.id) { index, step in
                        VStack(alignment: .leading, spacing: 2) {
                            checklistRow("\(index + 1)", "\(step.title): \(step.detail)")
                            if let documents = step.documents {
                                Text("Bring: \(documents)").font(.caption).foregroundStyle(.secondary).padding(.leading, 29)
                            }
                        }
                    }
                } else {
                    Text("Your connection steps are shown below as they become available.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("selfTransferFlowCard")
    }

    private func checklistRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.orange, in: Circle())
            Text(text).font(.footnote)
        }
    }

    @ViewBuilder
    private func arrivalTarget(_ layover: LayoverContext) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("NEXT AIRPORT")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
            if let target = viewModel.interAirportArrivalTarget {
                if let arriveBy = target.arriveBy {
                    LabeledContent(
                        "Arrive at \(target.onwardAirportCode) by",
                        value: localTime(arriveBy, timeZoneIdentifier: target.timeZoneIdentifier)
                    )
                    .font(.headline)
                    Text("This leaves time for check-in, security, and reaching your gate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Your recommended arrival time is not ready yet", systemImage: "questionmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    if let gateClose = target.gateClose {
                        Text("Your next gate closes at \(localTime(gateClose, timeZoneIdentifier: target.timeZoneIdentifier)).")
                            .font(.subheadline)
                    }
                    Text("We don't have enough information to set a return time yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("interAirportArrivalTarget")
    }

    private var zonePicker: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Choose an access layer", systemImage: "square.3.layers.3d")
                    .font(.headline)
                if dynamicTypeSize.isAccessibilitySize {
                    Picker("Access layer", selection: $viewModel.selectedZone) {
                        ForEach(AccessZone.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } else {
                    Picker("Access layer", selection: $viewModel.selectedZone) {
                        ForEach(AccessZone.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Text(zoneExplanation)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var categoryFilters: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                ForEach(LayoverPlaceCategory.allCases) { category in
                    categoryFilter(category, fillsWidth: true)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LayoverPlaceCategory.allCases) { category in
                        categoryFilter(category, fillsWidth: false)
                    }
                }
            }
        }
    }

    private func categoryFilter(_ category: LayoverPlaceCategory, fillsWidth: Bool) -> some View {
        Button {
            viewModel.toggleCategory(category)
            if viewModel.selectedZone == .nearby {
                Task { await viewModel.discoverNearbyPlaces() }
            }
        } label: {
            Label(category.title, systemImage: PlaceCategorySymbol.name(for: category))
                .font(.caption.weight(.semibold))
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 11)
                .foregroundStyle(viewModel.selectedCategories.contains(category) ? Color.white : Color.primary)
                .background(viewModel.selectedCategories.contains(category) ? Color.teal : Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(viewModel.selectedCategories.contains(category) ? "Selected" : "Not selected")
        .accessibilityIdentifier("layoverCategoryFilter_\(category.rawValue)")
    }

    @ViewBuilder private var zonePlans: some View {
        let matching = viewModel.candidates.filter { candidate in
            guard candidate.place?.accessZone == viewModel.selectedZone else { return false }
            return viewModel.selectedCategories.isEmpty
                || candidate.place.map { viewModel.selectedCategories.contains($0.category) } == true
        }
        if matching.isEmpty {
            SurfaceCard {
                Label("No calculated plan in this layer", systemImage: "info.circle")
                    .font(.headline)
                Text("Browse facilities while we wait for your flight times.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } else {
            ForEach(matching) { candidate in
                if let assessment = viewModel.assessments[candidate.id] {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.title).font(.headline)
                                    Text(candidate.place?.name ?? "Layover plan").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                FeasibilityPill(status: assessment.status)
                            }
                            Text(assessment.summary).font(.subheadline)
                            decisionMetrics(candidate: candidate, assessment: assessment)
                            if let latest = assessment.latestReturnTime {
                                Label("Latest return target: \(latest.formatted(date: .omitted, time: .shortened))", systemImage: "alarm.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(spacing: 8) { planActions(candidate: candidate, assessment: assessment) }
                            } else {
                                HStack(spacing: 8) { planActions(candidate: candidate, assessment: assessment) }
                            }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if viewModel.selectedCandidateID == candidate.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.teal)
                                .padding(8)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityIdentifier("layoverPlanCard")
                }
            }
        }
    }

    private func decisionMetrics(candidate: PlanCandidate, assessment: FeasibilityAssessment) -> some View {
        let decision = DecisionReadyPlan(candidate: candidate)
        return VStack(alignment: .leading, spacing: 5) {
            Text("PLAN AT A GLANCE")
                .font(.caption.bold()).foregroundStyle(.teal)
            if let total = decision.totalMinutes {
                LabeledContent("Time away from the gate", value: "\(total) min")
            }
            if let walk = decision.walkMinutes { LabeledContent("Walking time", value: "\(walk) min") }
            if let score = decision.quietCallScore {
                Label(score >= 7 ? "Good for a quiet call" : "May be busy", systemImage: "video.fill")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(10)
        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func planActions(candidate: PlanCandidate, assessment: FeasibilityAssessment) -> some View {
        Button {
            viewModel.selectCandidate(candidate.id)
        } label: {
            Label(viewModel.selectedCandidateID == candidate.id ? "Plan selected" : "Use this plan", systemImage: "checkmark.circle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.teal)
        .accessibilityIdentifier("selectLayoverPlanButton")

        NavigationLink {
            CalculationTraceView(candidate: candidate, assessment: assessment)
        } label: {
            Label("See why this plan fits", systemImage: "info.circle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("openCalculationTraceLink")
    }

    @ViewBuilder private var affordabilityLayer: some View {
        let options = viewModel.affordabilityOptions
        if !options.isEmpty {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Plan your spend", systemImage: "wallet.pass.fill")
                                .font(.title3.bold())
                        }
                        Spacer()
                        Button {
                            Task { await viewModel.refreshAffordability() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Update currency conversion")
                        .accessibilityIdentifier("refreshAffordabilityButton")
                    }

                    if let quote = viewModel.currencyRateQuote {
                        Text(conversionDescription(quote))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.teal)
                            .accessibilityIdentifier("currencyConversionStatus")
                    } else if viewModel.isRefreshingAffordability {
                        Label("Updating currency conversion…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Currency conversion is unavailable right now. Local prices are still shown.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    ForEach(AffordabilityCategory.allCases) { category in
                        let entries = options.filter { $0.category == category }
                        if !entries.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                Label(category.title, systemImage: category.symbol)
                                    .font(.subheadline.weight(.semibold))
                                ForEach(entries) { option in
                                    affordabilityRow(option)
                                }
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("affordabilityLayer")
        } else if let airport = viewModel.activeAirport {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Spend options are not available yet", systemImage: "wallet.pass.fill")
                        .font(.headline)
                    Text("Local price estimates are not available for \(airport.iata) yet. Currency conversion appears when local prices are available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("affordabilityUnavailableCard")
        }
    }

    private func affordabilityRow(_ option: AffordabilityOption) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title).font(.subheadline.weight(.semibold))
                Text(option.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(localPrice(option)).font(.subheadline.weight(.bold)).monospacedDigit()
                if let converted = convertedPrice(option) {
                    Text(converted).font(.caption).foregroundStyle(.teal).monospacedDigit()
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func localPrice(_ option: AffordabilityOption) -> String {
        guard let minimum = option.minimumLocalAmount, let maximum = option.maximumLocalAmount else { return "Ask venue" }
        if option.isFree { return "Free" }
        return price(minimum, currency: option.currencyCode) == price(maximum, currency: option.currencyCode)
            ? price(minimum, currency: option.currencyCode)
            : "\(price(minimum, currency: option.currencyCode))–\(price(maximum, currency: option.currencyCode))"
    }

    private func convertedPrice(_ option: AffordabilityOption) -> String? {
        guard let quote = viewModel.currencyRateQuote,
              quote.baseCurrencyCode == option.currencyCode,
              let minimum = option.minimumLocalAmount,
              let maximum = option.maximumLocalAmount,
              !option.isFree else { return nil }
        let low = minimum * quote.rate
        let high = maximum * quote.rate
        return price(low, currency: quote.quoteCurrencyCode) == price(high, currency: quote.quoteCurrencyCode)
            ? price(low, currency: quote.quoteCurrencyCode)
            : "≈ \(price(low, currency: quote.quoteCurrencyCode))–\(price(high, currency: quote.quoteCurrencyCode))"
    }

    private func conversionDescription(_ quote: CurrencyRateQuote) -> String {
        "1 \(quote.baseCurrencyCode) ≈ \(exchangeRate(quote.rate, currency: quote.quoteCurrencyCode)) · reference rate updated \(quote.rateDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private func price(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = amount >= 100 ? 0 : 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(currency)"
    }

    private func exchangeRate(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(currency)"
    }

    @ViewBuilder private var facilityResults: some View {
        let results = viewModel.visibleFacilities
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Airport services").font(.title3.bold())
                ForEach(results) { record in
                    facilityCard(record)
                }
            }
        } else if viewModel.selectedZone != .nearby {
            ContentUnavailableView(
                "No matching official records",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Clear one or more filters, or choose another access layer.")
            )
        }
    }

    private func facilityCard(_ record: AirportFacilityRecord) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    Label(record.place.name, systemImage: PlaceCategorySymbol.name(for: record.place.category))
                        .font(.headline)
                    Spacer()
                    Text(record.place.category.title)
                        .font(.caption.weight(.semibold)).foregroundStyle(.teal)
                }
                Text(record.place.summary).font(.subheadline).foregroundStyle(.secondary)
                if let terminal = record.place.terminal {
                    LabeledContent("Terminal", value: terminal)
                }
                LabeledContent("Access zone", value: record.place.accessZone.title)
                LabeledContent("Hours", value: record.hoursRequireConfirmation ? "Confirm with operator" : openLabel(record))
                if let restriction = record.accessRestrictions {
                    Label(restriction, systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                HStack {
                    if let source = record.place.officialSourceURL {
                        InAppBrowserLink(url: source) {
                            Text("Airport details")
                        }
                    }
                    if let booking = record.place.bookingURL {
                        Spacer()
                        InAppBrowserLink(url: booking) {
                            Text("Book or view")
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .accessibilityIdentifier("facilityRecord")
    }

    @ViewBuilder private var nearbyResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Places nearby").font(.title3.bold())
                    Text("Hotels, food, and things to do around \(viewModel.activeAirport?.iata ?? "the airport")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await viewModel.discoverNearbyPlaces() }
                } label: { Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly) }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Refresh nearby places")
            }

            if viewModel.discoveredPlaces.contains(where: { $0.coordinate != nil }) {
                NearbyPlacesMapView(
                    places: viewModel.discoveredPlaces,
                    selectedPlaceID: $selectedNearbyPlaceID
                )
                .frame(height: 310)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.primary.opacity(0.1))
                }
                .accessibilityIdentifier("nearbyPlacesMap")
            }

            if let selectedNearbyPlace {
                selectedNearbyPlaceCard(selectedNearbyPlace)
            }

            ForEach(viewModel.discoveredPlaces) { place in
                Button {
                    selectedNearbyPlaceID = place.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: PlaceCategorySymbol.name(for: place.category))
                            .foregroundStyle(AirportXRPalette.actionTeal)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.name).font(.headline).foregroundStyle(.primary)
                            Text(place.category.title).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedNearbyPlaceID == place.id ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(selectedNearbyPlaceID == place.id ? AirportXRPalette.actionTeal : .secondary)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nearbyPlace")
            }
        }
    }

    private var selectedNearbyPlace: LayoverPlace? {
        guard let selectedNearbyPlaceID else { return nil }
        return viewModel.discoveredPlaces.first { $0.id == selectedNearbyPlaceID }
    }

    private func selectedNearbyPlaceCard(_ place: LayoverPlace) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(place.name, systemImage: PlaceCategorySymbol.name(for: place.category))
                    .font(.headline)
                Text("\(place.category.title) · Near \(place.airportCode)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if place.coordinate != nil {
                        Button {
                            openInMaps(place)
                        } label: {
                            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AirportXRPalette.actionTeal)
                    }
                    if let url = place.officialSourceURL {
                        InAppBrowserLink(url: url) {
                            Label("Website", systemImage: "safari")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .accessibilityIdentifier("selectedNearbyPlace")
    }

    private func openInMaps(_ place: LayoverPlace) {
        guard let coordinate = place.coordinate else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = place.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    private var zoneExplanation: String {
        switch viewModel.selectedZone {
        case .airside: "Stay inside security while exploring services near your gate."
        case .airportLandside: "Check entry requirements and allow time to pass through security again."
        case .nearby: "Explore places around the airport. Confirm availability and access before you go."
        case .city: "See whether there is enough time to visit the city and return comfortably for your flight."
        }
    }

    private func openLabel(_ record: AirportFacilityRecord) -> String {
        guard let open = record.isOpen(at: Date()) else { return "Unknown" }
        return open ? "Listed as open" : "Listed as closed"
    }

    private func transferOptionHeading(plan: InterAirportTransferPlan, selected: InterAirportTransferOption) -> String {
        switch selected.freshness {
        case .demo: "Recommended route"
        case .live where plan.canClaimFastest: "Leading current option"
        case .live: "Current route · compare before leaving"
        case .cached: "Saved route · refresh before leaving"
        case .stale: "Needs refresh"
        case .unavailable: "Timing unavailable"
        }
    }

    private func transferAccessibilityLabel(_ option: InterAirportTransferOption) -> String {
        let duration = option.duration.map {
            "\(Int($0.value.lower.rounded())) to \(Int($0.value.upper.rounded())) minutes, most likely \(Int($0.value.mostLikely.rounded()))"
        } ?? "duration unknown"
        let transfers = option.transfers.map { "\($0) transfers" } ?? "transfers unknown"
        let walking = option.walkingMeters.map { "\(Int($0.value.rounded())) meters walking" } ?? "walking distance unknown"
        let access = option.wheelchairAccessible.map { $0 ? "wheelchair accessibility confirmed" : "not wheelchair accessible" } ?? "accessibility unconfirmed"
        return "\(option.title), \(option.freshness.title), \(duration), \(transfers), \(walking), \(access)"
    }

    private func localTime(_ date: Date, timeZoneIdentifier: String) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        if let timeZone = TimeZone(identifier: timeZoneIdentifier) { style.timeZone = timeZone }
        return date.formatted(style)
    }
}
