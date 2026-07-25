import Foundation

/// Named demo/test fixture. None of the flight times, terminal distances, queue
/// estimates, prices, or availability in this type are production claims.
enum LongHaulReferenceScenario {
    static let fixtureVersion = "demo-bkk-hnd-lax-2026-07-14-v1"

    static func itinerary(anchor: Date = Date()) -> Itinerary {
        let bkk = Airport(iata: "BKK", icao: "VTBS", name: "Suvarnabhumi Airport", city: "Bangkok", timeZone: "Asia/Bangkok")
        let hnd = Airport(iata: "HND", icao: "RJTT", name: "Tokyo Haneda Airport", city: "Tokyo", timeZone: "Asia/Tokyo")
        let lax = Airport(iata: "LAX", icao: "KLAX", name: "Los Angeles International Airport", city: "Los Angeles", timeZone: "America/Los_Angeles")

        let source = ProviderMetadata(
            name: "Example BKK-HND-LAX trip",
            providerRecordID: fixtureVersion,
            providerUpdatedAt: anchor,
            receivedAt: anchor,
            isLive: false,
            isDemo: true
        )
        let inboundArrival = anchor.addingTimeInterval(-45 * 60)
        let inboundDeparture = inboundArrival.addingTimeInterval(-6 * 3600)
        let onwardDeparture = anchor.addingTimeInterval(6 * 3600)
        let onwardGateClose = onwardDeparture.addingTimeInterval(-35 * 60)
        let onwardArrival = onwardDeparture.addingTimeInterval(9.75 * 3600)

        let inbound = Flight(
            id: "demo-tg660-bkk-hnd",
            flightNumber: "TG 660",
            airlineCode: "TG",
            airlineName: "Thai Airways",
            origin: bkk,
            destination: hnd,
            status: .arrived,
            scheduledDeparture: inboundDeparture,
            estimatedDeparture: inboundDeparture,
            actualDeparture: inboundDeparture,
            scheduledArrival: inboundArrival,
            estimatedArrival: inboundArrival,
            actualArrival: inboundArrival,
            departureTerminal: "Main",
            arrivalTerminal: "3",
            gate: nil,
            arrivalGate: "146",
            previousGate: nil,
            boardingStatus: nil,
            boardingGroup: nil,
            boardingTime: inboundDeparture.addingTimeInterval(-40 * 60),
            delayMinutes: 0,
            aircraftType: "Boeing 787",
            baggageClaim: nil,
            source: source
        )
        let onward = Flight(
            id: "demo-nh106-hnd-lax",
            flightNumber: "NH 106",
            airlineCode: "NH",
            airlineName: "ANA",
            origin: hnd,
            destination: lax,
            status: .scheduled,
            scheduledDeparture: onwardDeparture,
            estimatedDeparture: onwardDeparture,
            actualDeparture: nil,
            scheduledArrival: onwardArrival,
            estimatedArrival: onwardArrival,
            actualArrival: nil,
            departureTerminal: "3",
            arrivalTerminal: "B",
            gate: "105",
            arrivalGate: nil,
            previousGate: nil,
            boardingStatus: "Use airport displays",
            boardingGroup: nil,
            boardingTime: onwardDeparture.addingTimeInterval(-55 * 60),
            delayMinutes: 0,
            aircraftType: "Boeing 787-9",
            baggageClaim: nil,
            source: source
        )
        let onBlock = dateMetric(
            inboundArrival,
            field: "actualArrival",
            record: "demo-tg660-on-block",
            anchor: anchor,
            label: "Inbound on-block"
        )
        let gateClose = dateMetric(
            onwardGateClose,
            field: "fixture.gateClose",
            record: "demo-nh106-gate-close",
            anchor: anchor,
            label: "Onward gate-close"
        )
        return Itinerary(
            id: UUID(uuidString: "B001C0DE-0000-4000-8000-000000000001")!,
            title: "Bangkok → Tokyo → Los Angeles",
            legs: [
                ItineraryLeg(id: UUID(uuidString: "B001C0DE-0000-4000-8000-000000000011")!, flight: inbound, onBlockTime: onBlock),
                ItineraryLeg(id: UUID(uuidString: "B001C0DE-0000-4000-8000-000000000012")!, flight: onward, gateCloseTime: gateClose)
            ],
            createdAt: anchor,
            updatedAt: anchor
        )
    }

    static func hanedaToNaritaItinerary(anchor: Date = Date()) -> Itinerary {
        let bkk = Airport(iata: "BKK", icao: "VTBS", name: "Suvarnabhumi Airport", city: "Bangkok", timeZone: "Asia/Bangkok")
        let hnd = Airport(iata: "HND", icao: "RJTT", name: "Tokyo Haneda Airport", city: "Tokyo", timeZone: "Asia/Tokyo")
        let nrt = Airport(iata: "NRT", icao: "RJAA", name: "Narita International Airport", city: "Tokyo region", timeZone: "Asia/Tokyo")
        let lax = Airport(iata: "LAX", icao: "KLAX", name: "Los Angeles International Airport", city: "Los Angeles", timeZone: "America/Los_Angeles")
        let source = ProviderMetadata(name: "Example HND-NRT transfer", providerRecordID: "demo-hnd-nrt-v1", providerUpdatedAt: anchor, receivedAt: anchor, isLive: false, isDemo: true)
        let arrival = anchor.addingTimeInterval(-30 * 60)
        let departure = anchor.addingTimeInterval(9 * 3600)
        let gateClose = departure.addingTimeInterval(-40 * 60)
        let inbound = Flight(
            id: "demo-bkk-hnd-transfer",
            flightNumber: "TG 660",
            airlineCode: "TG",
            airlineName: "Thai Airways",
            origin: bkk,
            destination: hnd,
            status: .arrived,
            scheduledDeparture: arrival.addingTimeInterval(-6 * 3600),
            estimatedDeparture: arrival.addingTimeInterval(-6 * 3600),
            actualDeparture: arrival.addingTimeInterval(-6 * 3600),
            scheduledArrival: arrival,
            estimatedArrival: arrival,
            actualArrival: arrival,
            departureTerminal: "Main",
            arrivalTerminal: "3",
            gate: nil,
            arrivalGate: "146",
            previousGate: nil,
            boardingStatus: nil,
            boardingGroup: nil,
            boardingTime: nil,
            delayMinutes: 0,
            aircraftType: "Boeing 787",
            baggageClaim: "Confirm through-check status",
            source: source
        )
        let onward = Flight(
            id: "demo-nrt-lax-transfer",
            flightNumber: "NH 6",
            airlineCode: "NH",
            airlineName: "ANA",
            origin: nrt,
            destination: lax,
            status: .scheduled,
            scheduledDeparture: departure,
            estimatedDeparture: departure,
            actualDeparture: nil,
            scheduledArrival: departure.addingTimeInterval(10 * 3600),
            estimatedArrival: departure.addingTimeInterval(10 * 3600),
            actualArrival: nil,
            departureTerminal: "1",
            arrivalTerminal: "B",
            gate: nil,
            arrivalGate: nil,
            previousGate: nil,
            boardingStatus: "Use Narita airport displays",
            boardingGroup: nil,
            boardingTime: departure.addingTimeInterval(-60 * 60),
            delayMinutes: 0,
            aircraftType: "Boeing 787-9",
            baggageClaim: nil,
            source: source
        )
        let onBlock = SourcedMetric(
            value: arrival,
            unit: MetricUnit.dateTime,
            provider: "Example HND-NRT transfer",
            providerField: "actualArrival",
            sourceRecordID: "demo-hnd-nrt-on-block",
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: nil,
            uncertainty: "Example timing",
            derivation: []
        )
        let close = SourcedMetric(
            value: gateClose,
            unit: MetricUnit.dateTime,
            provider: "Example HND-NRT transfer",
            providerField: "gateClose",
            sourceRecordID: "demo-nrt-lax-gate-close",
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: nil,
            uncertainty: "Example timing",
            derivation: []
        )
        return Itinerary(
            id: UUID(uuidString: "B001C0DE-0000-4000-8000-000000000002")!,
            title: "Bangkok → Haneda ⇢ Narita → Los Angeles",
            legs: [
                ItineraryLeg(id: UUID(uuidString: "B001C0DE-0000-4000-8000-000000000021")!, flight: inbound, onBlockTime: onBlock),
                ItineraryLeg(id: UUID(uuidString: "B001C0DE-0000-4000-8000-000000000022")!, flight: onward, gateCloseTime: close)
            ],
            createdAt: anchor,
            updatedAt: anchor
        )
    }

    static func candidates(
        layover: LayoverContext,
        entry: EntryAssessment?,
        anchor: Date,
        stochasticSeed: UInt64? = nil
    ) -> [PlanCandidate] {
        var generator = ReplayableRandomNumberGenerator(seed: stochasticSeed ?? StableSimulationSeed.digest(fixtureVersion))
        func jitter(_ value: Double) -> Double {
            guard stochasticSeed != nil else { return value }
            let proportionalShift = (generator.unitInterval() - 0.5) * 0.30
            return max(1, value * (1 + proportionalShift))
        }
        let workPod = HNDOfficialFacilityRegistry.records.first(where: { $0.place.category == .workPod })!.place
        let garden = HNDOfficialFacilityRegistry.records.first(where: { $0.place.id == "hnd-airport-garden" })!.place
        let city = HNDOfficialFacilityRegistry.records.first(where: { $0.place.id == "tokyo-edo-koji-city-plan" })!.place
        let airsideNearGate = LayoverPlace(
            id: "demo-airside-near-gate-105",
            name: "Airside area near Gate 105",
            airportCode: "HND",
            terminal: "3",
            category: .facility,
            accessZone: .airside,
            latitude: nil,
            longitude: nil,
            summary: "Planning anchor only; it does not claim a bookable service or opening hours.",
            bookingURL: nil,
            officialSourceURL: nil,
            dataMode: .demo
        )
        return [
            PlanCandidate(
                title: "Stay airside near Gate 105",
                place: airsideNearGate,
                segments: [
                    segment(.access, "Route to an airside rest area", low: jitter(4), mode: jitter(7), high: jitter(12), source: "demo-hnd-terminal-route", anchor: anchor),
                    segment(.activity, "Rest near the gate", low: 75, mode: 90, high: 120, source: "user-selected-activity", anchor: anchor),
                    segment(.terminalRoute, "Return route to Gate 105", low: jitter(7), mode: jitter(11), high: jitter(18), source: "demo-hnd-terminal-route-return", anchor: anchor),
                    segment(.safety, "Personal accessibility margin", low: 0, mode: 0, high: jitter(8), source: "traveler-profile-margin", anchor: anchor)
                ],
                entryAssessment: nil
            ),
            PlanCandidate(
                title: "Terminal 3 work cubicle",
                place: workPod,
                segments: [
                    segment(.border, "Border processing", distribution: nil, source: "queue-provider-not-configured", anchor: anchor),
                    segment(.outboundTravel, "Route to general-area work cubicle", low: jitter(9), mode: jitter(14), high: jitter(22), source: "demo-hnd-public-area-route", anchor: anchor),
                    segment(.activity, "Focused work", low: 45, mode: 60, high: 90, source: "user-selected-activity", anchor: anchor),
                    segment(.security, "Re-entry security", distribution: nil, source: "queue-provider-not-configured", anchor: anchor),
                    segment(.terminalRoute, "Terminal route to Gate 105", low: jitter(7), mode: jitter(11), high: jitter(18), source: "demo-hnd-terminal-route-return", anchor: anchor)
                ],
                entryAssessment: entry
            ),
            PlanCandidate(
                title: "Haneda Airport Garden visit",
                place: garden,
                segments: [
                    segment(.border, "Border processing", distribution: nil, source: "queue-provider-not-configured", anchor: anchor),
                    segment(.baggage, "Baggage handling", low: 0, mode: 0, high: 0, source: "demo-checked-through", anchor: anchor),
                    segment(.outboundTravel, "Walk to Airport Garden", low: jitter(10), mode: jitter(14), high: jitter(22), source: "demo-hnd-walk", anchor: anchor),
                    segment(.activity, "Airport Garden visit", low: 60, mode: 90, high: 120, source: "user-selected-activity", anchor: anchor),
                    segment(.returnTravel, "Return to Terminal 3", low: jitter(10), mode: jitter(14), high: jitter(22), source: "demo-hnd-walk-return", anchor: anchor),
                    segment(.security, "Re-entry security", distribution: nil, source: "queue-provider-not-configured", anchor: anchor),
                    segment(.terminalRoute, "Terminal route to Gate 105", low: jitter(7), mode: jitter(11), high: jitter(18), source: "demo-hnd-terminal-route-return", anchor: anchor)
                ],
                entryAssessment: entry
            ),
            PlanCandidate(
                title: "Short Tokyo visit",
                place: city,
                segments: [
                    segment(.deplane, "Deplane and orient", low: jitter(8), mode: jitter(14), high: jitter(25), source: "demo-user-outcome-prior", anchor: anchor),
                    segment(.border, "Border processing", distribution: nil, source: "queue-provider-not-configured", anchor: anchor),
                    segment(.customs, "Customs exit", distribution: nil, source: "queue-provider-not-configured", anchor: anchor),
                    segment(.outboundTravel, "Rail to central Tokyo", low: jitter(28), mode: jitter(38), high: jitter(58), source: "demo-gtfs-static-not-live", anchor: anchor),
                    segment(.activity, "City activity", low: 60, mode: 90, high: 120, source: "user-selected-activity", anchor: anchor),
                    segment(.returnTravel, "Rail return to HND", low: jitter(30), mode: jitter(40), high: jitter(65), source: "demo-gtfs-static-not-live", anchor: anchor),
                    segment(.security, "Security and border re-entry", distribution: nil, source: "queue-provider-not-configured", anchor: anchor),
                    segment(.terminalRoute, "Terminal route to Gate 105", low: jitter(7), mode: jitter(11), high: jitter(18), source: "demo-hnd-terminal-route-return", anchor: anchor)
                ],
                entryAssessment: entry
            )
        ]
    }

    private static func segment(
        _ kind: PlanSegmentKind,
        _ title: String,
        low: Double,
        mode: Double,
        high: Double,
        source: String,
        anchor: Date
    ) -> PlanSegment {
        segment(
            kind,
            title,
            distribution: EstimateDistribution(lower: min(low, mode, high), mostLikely: mode, upper: max(low, mode, high), unit: .minutes),
            source: source,
            anchor: anchor
        )
    }

    private static func segment(
        _ kind: PlanSegmentKind,
        _ title: String,
        distribution: EstimateDistribution?,
        source: String,
        anchor: Date
    ) -> PlanSegment {
        let metric = distribution.map {
            SourcedMetric(
                value: $0,
                unit: .minutes,
                provider: "Example itinerary",
                providerField: kind.rawValue,
                sourceRecordID: source,
                observedAt: anchor,
                receivedAt: anchor,
                expiresAt: nil,
                uncertainty: "Triangular demo distribution; replace with provider/user outcome data",
                derivation: [
                    DerivationStep(label: title, formula: "fixture low / most-likely / high", inputRecordIDs: [source], result: "\(Int($0.lower.rounded())) / \(Int($0.mostLikely.rounded())) / \(Int($0.upper.rounded())) min")
                ]
            )
        }
        return PlanSegment(kind: kind, title: title, duration: metric)
    }

    private static func dateMetric(
        _ value: Date,
        field: String,
        record: String,
        anchor: Date,
        label: String
    ) -> SourcedMetric<Date> {
        SourcedMetric(
            value: value,
            unit: .dateTime,
            provider: "Example itinerary",
            providerField: field,
            sourceRecordID: record,
            observedAt: anchor,
            receivedAt: anchor,
            expiresAt: nil,
            uncertainty: "Example itinerary details",
            derivation: [DerivationStep(label: label, formula: "fixture field", inputRecordIDs: [record], result: value.ISO8601Format())]
        )
    }
}

enum HNDOfficialFacilityRegistry {
    static let registryVersion = "hnd-official-registry-2026-07-14-v1"
    private static let workPodURL = URL(string: "https://tokyo-haneda.com/en/service/facilities/work_box.html")!
    private static let hotelURL = URL(string: "https://tokyo-haneda.com/en/service/facilities/hotel.html")!
    private static let showerURL = URL(string: "https://tokyo-haneda.com/en/service/facilities/shower_room.html")!
    private static let facilityURL = URL(string: "https://tokyo-haneda.com/en/service/facilities/index.html")!
    private static let floorGuideURL = URL(string: "https://tokyo-haneda.com/site_resource/floor/pdf/floor__pdf_floor_map_t3_en.pdf")!
    private static let anchor = ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z")!

    static let records: [AirportFacilityRecord] = [
        record("hnd-work-pod", "Terminal 3 Work Cubicles", .workPod, .airportLandside, "3", "H1TBOX and STATION BOOTH are listed in the Terminal 3 general area.", workPodURL, windows: [daily(7 * 60, 21 * 60 + 30)], confirmHours: false),
        record("hnd-transit-hotel", "The Royal Park Hotel Tokyo Haneda (Transit)", .transitHotel, .airside, "3", "Official Terminal 3 airside transit hotel. Room availability and transit eligibility require operator confirmation.", hotelURL, windows: [daily(0, 0)], confirmHours: false),
        record("hnd-shower", "Terminal 3 Shower Rooms", .shower, .airportLandside, "3", "Official 24-hour shower and refresh rooms in the Terminal 3 second-floor Arrival Lobby; reservations are not accepted.", showerURL, windows: [daily(0, 0)], confirmHours: false),
        record("hnd-lounge", "Terminal 3 Lounges", .lounge, .airside, "3", "Official facility directory; access depends on the specific lounge, airline, ticket, or payment.", facilityURL),
        record("hnd-observation-deck", "Terminal 3 Observation Deck", .attraction, .airportLandside, "3", "Airport attraction. Landside access requires a current entry assessment.", facilityURL),
        record("hnd-edo-koji", "Edo Koji", .food, .airportLandside, "3", "Japanese-style dining and shopping area in Terminal 3. Confirm individual venue hours.", facilityURL),
        record("hnd-airport-garden", "Haneda Airport Garden", .attraction, .airportLandside, nil, "Connected landside complex with hotel, food, shopping, and relaxation facilities.", facilityURL),
        record("hnd-terminal-restrooms", "Toilets and accessible toilets", .facility, .airportLandside, "3", "The official Terminal 3 floor guide shows toilet and accessible-toilet locations by floor.", floorGuideURL),
        record("hnd-terminal-snacks", "Terminal 3 food and drink", .food, .airportLandside, "3", "Use the official floor guide to find current food and drink locations; individual outlets and hours vary.", floorGuideURL),
        record("hnd-terminal-shopping", "Terminal 3 shops", .facility, .airportLandside, "3", "Use the official floor guide to find current shopping locations; stock and individual shop hours vary.", floorGuideURL),
        record("hnd-nearby-hotel", "Nearby hotel discovery", .hotel, .nearby, nil, "MapKit discovery placeholder; live room availability requires the optional accommodation provider.", facilityURL),
        record("hnd-anamori-inari", "Anamori Inari area", .attraction, .nearby, nil, "Nearby place candidate. Routing, opening details, and entry eligibility must be refreshed.", facilityURL),
        record("tokyo-edo-koji-city-plan", "Central Tokyo short visit", .attraction, .city, nil, "Research plan only until entry, queues, GTFS-Realtime, weather, and return service are current.", facilityURL)
    ]

    private static func record(
        _ id: String,
        _ name: String,
        _ category: LayoverPlaceCategory,
        _ zone: AccessZone,
        _ terminal: String?,
        _ summary: String,
        _ url: URL,
        windows: [OpeningWindow] = [],
        confirmHours: Bool = true
    ) -> AirportFacilityRecord {
        AirportFacilityRecord(
            id: id,
            place: LayoverPlace(
                id: id,
                name: name,
                airportCode: "HND",
                terminal: terminal,
                category: category,
                accessZone: zone,
                latitude: nil,
                longitude: nil,
                summary: summary,
                bookingURL: category == .hotel || category == .transitHotel ? url : nil,
                officialSourceURL: url,
                dataMode: .demo
            ),
            accessRestrictions: zone == .airside ? "Valid boarding pass and applicable airside access required." : nil,
            openingWindows: windows,
            hoursRequireConfirmation: confirmHours,
            sourceUpdatedAt: nil,
            verifiedAt: anchor
        )
    }

    private static func daily(_ start: Int, _ end: Int) -> OpeningWindow {
        OpeningWindow(weekdays: Set(1...7), startMinuteOfDay: start, endMinuteOfDay: end, timeZoneIdentifier: "Asia/Tokyo")
    }
}

struct HNDOfficialFacilityProvider: AirportFacilityProvider {
    func facilities(at airport: Airport, on date: Date) async throws -> [AirportFacilityRecord] {
        airport.iata.uppercased() == "HND" ? HNDOfficialFacilityRegistry.records : []
    }
}

struct InformationalEntryRequirementProvider: EntryRequirementProvider {
    func assessment(for query: EntryRequirementQuery) async throws -> EntryAssessment {
        let received = Date()
        return EntryAssessment(
            status: .cannotDetermine,
            summary: "No structured Timatic or Sherpa credential is configured. Review Japan's official guidance for this traveler and itinerary before leaving the secure transit area.",
            provider: "Informational fallback",
            evidenceKind: .informationalFallback,
            sourceRecordID: "mofa-japan-official-link",
            observedAt: received,
            receivedAt: received,
            expiresAt: received,
            officialVerificationURLs: [URL(string: "https://www.mofa.go.jp/j_info/visit/visa/short/novisa.html")!],
            isDemo: true
        )
    }
}

struct TokyoInterAirportDemoTransferProvider: InterAirportTransferProvider {
    let trafficMultiplier: Double

    init(trafficMultiplier: Double = 1) {
        self.trafficMultiplier = trafficMultiplier
    }

    func options(from origin: Airport, to destination: Airport, after date: Date) async throws -> [InterAirportTransferOption] {
        guard origin.iata.uppercased() == "HND", destination.iata.uppercased() == "NRT" else { return [] }
        return [
            option("demo-hnd-nrt-rail", "Airport rail through-service", after: date, low: 82, mode: 96, high: 125, walking: 420, transfers: 0, accessible: true),
            option("demo-hnd-nrt-bus", "Direct airport limousine bus", after: date, low: 70, mode: 100, high: 145, walking: 180, transfers: 0, accessible: nil),
            option("demo-hnd-nrt-road", "Pre-arranged road transfer", after: date, low: 60, mode: 92, high: 150, walking: 90, transfers: 0, accessible: nil)
        ]
    }

    private func option(
        _ id: String,
        _ title: String,
        after date: Date,
        low: Double,
        mode: Double,
        high: Double,
        walking: Double,
        transfers: Int,
        accessible: Bool?
    ) -> InterAirportTransferOption {
        let observed = date
        let duration = SourcedMetric(
            value: EstimateDistribution(lower: low * trafficMultiplier, mostLikely: mode * trafficMultiplier, upper: high * trafficMultiplier, unit: .minutes),
            unit: MetricUnit.minutes,
            provider: "Example HND-NRT transfer",
            providerField: "duration",
            sourceRecordID: id,
            observedAt: observed,
            receivedAt: observed,
            expiresAt: nil,
            uncertainty: "Example route timing range",
            derivation: [DerivationStep(label: title, formula: "lower / most-likely / upper", inputRecordIDs: [id], result: "\(Int(low))/\(Int(mode))/\(Int(high)) min")]
        )
        let walk = SourcedMetric(
            value: walking,
            unit: MetricUnit.meters,
            provider: "Example HND-NRT transfer",
            providerField: "walkingMeters",
            sourceRecordID: "\(id)-walk",
            observedAt: observed,
            receivedAt: observed,
            expiresAt: nil,
            uncertainty: "Example interchange walking distance",
            derivation: []
        )
        return InterAirportTransferOption(
            id: id,
            title: title,
            originAirportCode: "HND",
            destinationAirportCode: "NRT",
            departureTime: date.addingTimeInterval(20 * 60),
            arrivalTime: date.addingTimeInterval((20 + mode) * 60),
            duration: duration,
            walkingMeters: walk,
            transfers: transfers,
            wheelchairAccessible: accessible,
            luggageNotes: "Confirm baggage through-check, vehicle storage, and interchange access.",
            lastService: date.addingTimeInterval(8 * 3600),
            provider: "Example HND-NRT transfer",
            freshness: .demo
        )
    }
}

enum InterAirportCandidateFactory {
    static func candidates(
        layover: LayoverContext,
        transferPlan: InterAirportTransferPlan,
        entry: EntryAssessment?,
        anchor: Date,
        includeDemoOptionalActivity: Bool = true
    ) -> [PlanCandidate] {
        let transferPlace = LayoverPlace(
            id: "transfer-\(layover.airport.iata)-\(layover.onwardAirport.iata)",
            name: "\(layover.airport.iata) to \(layover.onwardAirport.iata) airport transfer",
            airportCode: layover.airport.iata,
            terminal: nil,
            category: .facility,
            accessZone: .nearby,
            latitude: nil,
            longitude: nil,
            summary: "Mandatory regional airport transfer before any optional activity.",
            bookingURL: nil,
            officialSourceURL: nil,
            dataMode: transferPlan.selected?.freshness ?? .unavailable
        )
        let transferSegment = PlanSegment(
            kind: .outboundTravel,
            title: "Inter-airport transfer",
            duration: transferPlan.selected?.duration
        )
        let unknownBorder = PlanSegment(kind: .border, title: "Border, bags, and customs", duration: nil)
        let unknownCheckIn = PlanSegment(kind: .checkIn, title: "Onward airport check-in and bag acceptance", duration: nil)
        let unknownSecurity = PlanSegment(kind: .security, title: "Onward airport security and exit controls", duration: nil)

        let transferOnly = PlanCandidate(
            title: "Transfer to \(layover.onwardAirport.iata) first",
            place: transferPlace,
            segments: [unknownBorder, transferSegment, unknownCheckIn, unknownSecurity],
            entryAssessment: entry,
            latestReturnReference: transferPlan.selected?.lastService,
            intent: .airportTransfer
        )
        let visitPlace = LayoverPlace(
            id: "demo-hnd-nrt-on-route-stop",
            name: "Recommended stop near \(layover.onwardAirport.iata)",
            airportCode: layover.onwardAirport.iata,
            terminal: nil,
            category: .attraction,
            accessZone: .nearby,
            latitude: nil,
            longitude: nil,
            summary: "A nearby stop after arriving at the next airport.",
            bookingURL: nil,
            officialSourceURL: nil,
            dataMode: .demo
        )
        let activity = PlanSegment(
            kind: .activity,
            title: "Short stop on the transfer route",
            duration: SourcedMetric(
                value: EstimateDistribution(lower: 30, mostLikely: 45, upper: 60, unit: .minutes),
                unit: MetricUnit.minutes,
                provider: "User-selected activity",
                providerField: "activityDuration",
                sourceRecordID: "demo-post-transfer-activity",
                observedAt: anchor,
                receivedAt: anchor,
                expiresAt: nil,
                uncertainty: "User-adjustable duration",
                derivation: []
            )
        )
        let firstTransferLeg = transferPortion(
            transferPlan.selected?.duration,
            share: 0.45,
            title: "Travel from Haneda to the on-route stop"
        )
        let secondTransferLeg = transferPortion(
            transferPlan.selected?.duration,
            share: 0.55,
            title: "Continue from the stop to Narita"
        )
        let visit = PlanCandidate(
            title: "Recommended nearby visit near \(layover.onwardAirport.iata)",
            place: visitPlace,
            // The transfer is split around the stop. This prevents the
            // assessment from incorrectly adding a full HND→NRT transfer and
            // then treating the stop as a separate trip out from Narita.
            segments: [unknownBorder, firstTransferLeg, activity, secondTransferLeg, unknownCheckIn, unknownSecurity],
            entryAssessment: entry,
            latestReturnReference: transferPlan.selected?.lastService,
            intent: .transferRouteStop
        )
        return includeDemoOptionalActivity ? [transferOnly, visit] : [transferOnly]
    }

    private static func transferPortion(
        _ metric: SourcedMetric<EstimateDistribution>?,
        share: Double,
        title: String
    ) -> PlanSegment {
        guard let metric else {
            return PlanSegment(kind: .outboundTravel, title: title, duration: nil)
        }
        let duration = metric.value
        let portion = SourcedMetric(
            value: EstimateDistribution(
                lower: duration.lower * share,
                mostLikely: duration.mostLikely * share,
                upper: duration.upper * share,
                unit: duration.unit
            ),
            unit: metric.unit,
            provider: metric.provider,
            providerField: "\(metric.providerField).onRoutePortion",
            sourceRecordID: "\(metric.sourceRecordID)-portion-\(Int((share * 100).rounded()))",
            observedAt: metric.observedAt,
            receivedAt: metric.receivedAt,
            expiresAt: metric.expiresAt,
            uncertainty: "Time around the stop may vary.",
            derivation: metric.derivation + [
                DerivationStep(
                    label: "Transfer route",
                    formula: "Route split around the stop",
                    inputRecordIDs: [metric.sourceRecordID],
                    result: "Stop is on the way"
                )
            ]
        )
        return PlanSegment(kind: .outboundTravel, title: title, duration: portion)
    }
}
