import CryptoKit
import Foundation
import PDFKit
import Vision

enum TicketPDFScanError: LocalizedError {
    case unreadablePDF
    case noReadableText

    var errorDescription: String? {
        switch self {
        case .unreadablePDF: "Choose a readable PDF ticket or boarding pass."
        case .noReadableText: "No readable ticket details were found in this PDF."
        }
    }
}

struct TicketPDFScanService: Sendable {
    func scanPDF(data: Data, fileName: String, at date: Date = Date()) throws -> TicketPDFScanResult {
        guard let document = PDFDocument(data: data) else {
            throw TicketPDFScanError.unreadablePDF
        }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index) {
                let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                pages.append(text.isEmpty ? recognize(page: page) : text)
            }
        }
        return try Self.scanText(pages.joined(separator: "\n"), fileName: fileName, at: date)
    }

    static func scanText(_ text: String, fileName: String = "ticket.pdf", at date: Date = Date()) throws -> TicketPDFScanResult {
        let normalized = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TicketPDFScanError.noReadableText }

        let fingerprint = SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return TicketPDFScanResult(
            fileName: fileName,
            textFingerprint: fingerprint,
            routeAirportCodes: routeAirportCodes(in: normalized),
            flightNumbers: flightNumbers(in: normalized),
            baggageSignals: baggageSignals(in: normalized),
            scannedAt: date,
            sourceRecordID: "ticket-pdf|\(fingerprint.prefix(16))"
        )
    }

    func scanImage(data: Data, fileName: String, at date: Date = Date()) throws -> TicketPDFScanResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(data: data, options: [:])
        try handler.perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        return try Self.scanText(text, fileName: fileName, at: date)
    }

    private static func routeAirportCodes(in text: String) -> [String] {
        let uppercased = text.uppercased()
        let expression = try? NSRegularExpression(pattern: #"\b[A-Z]{3}\b"#)
        let matches = expression?.matches(in: uppercased, range: NSRange(uppercased.startIndex..., in: uppercased)) ?? []

        var ordered: [String] = []
        var seen = Set<String>()
        for match in matches {
            guard let range = Range(match.range, in: uppercased) else { continue }
            let candidate = String(uppercased[range])
            // A ticket route normally lists airport codes in sequence. Keep
            // codes that occur around travel language as well as known points.
            guard !["THE", "AND", "FOR", "BAG", "TAG", "TKT", "PNR"].contains(candidate), !seen.contains(candidate) else { continue }
            ordered.append(candidate)
            seen.insert(candidate)
        }
        return ordered
    }

    private static func flightNumbers(in text: String) -> [String] {
        let expression = try? NSRegularExpression(pattern: #"\b([A-Z0-9]{2,3})\s?(\d{1,4})\b"#)
        let range = NSRange(text.startIndex..., in: text)
        var values: [String] = []
        for match in expression?.matches(in: text.uppercased(), range: range) ?? [] {
            guard let codeRange = Range(match.range(at: 1), in: text.uppercased()),
                  let numberRange = Range(match.range(at: 2), in: text.uppercased()) else { continue }
            let value = "\(text.uppercased()[codeRange]) \(text.uppercased()[numberRange])"
            if !values.contains(value) { values.append(value) }
        }
        return values
    }

    private func recognize(page: PDFPage) -> String {
        let image = page.thumbnail(of: CGSize(width: 2_000, height: 2_000), for: .mediaBox)
        guard let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func baggageSignals(in text: String) -> [TicketScanBaggageSignal] {
        let uppercased = text.uppercased()
        var signals: [TicketScanBaggageSignal] = []

        if containsAny(uppercased, ["NO CHECKED BAG", "CABIN BAG ONLY", "HAND BAGGAGE ONLY"]) {
            signals.append(.noCheckedBag)
        }
        if containsAny(uppercased, ["SELF TRANSFER", "SEPARATE TICKET", "SEPARATE TICKETS"]) {
            signals.append(.selfTransfer)
        }
        if containsAny(uppercased, ["AUTO TRANSFER", "AUTOMATIC TRANSFER", "THROUGH TRANSFER", "PROTECTED CONNECTION"]) {
            signals.append(.automaticTransfer)
        }
        if containsAny(uppercased, ["RECHECK", "RE-CHECK", "COLLECT BAG", "CLAIM BAG", "RECLAIM BAG", "BAGGAGE CLAIM"]) {
            signals.append(.collectAndRecheck)
        }

        let destinationPatterns = [
            #"BAG(?:GAGE)?\s*TAG\s*DESTINATION\s*[:\-]?\s*([A-Z]{3})\b"#,
            #"BAG(?:GAGE)?\s*(?:TAG|DESTINATION|FINAL DESTINATION|CHECKED TO|THROUGH TO)\s*[:\-]?\s*([A-Z]{3})\b"#,
            #"BAGS?\s*(?:CHECKED|THROUGH|TAGGED)\s*(?:TO)?\s*[:\-]?\s*([A-Z]{3})\b"#,
            #"CHECKED\s*BAGS?\s*TO\s*([A-Z]{3})\b"#
        ]
        for pattern in destinationPatterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in expression.matches(in: uppercased, range: NSRange(uppercased.startIndex..., in: uppercased)) {
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: uppercased) else { continue }
                signals.append(.bagTagDestination(String(uppercased[range])))
            }
        }

        guard !signals.isEmpty else { return [.unknown] }
        var unique: [TicketScanBaggageSignal] = []
        for signal in signals where !unique.contains(signal) {
            unique.append(signal)
        }
        return unique
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

struct TicketConnectionStatusService: Sendable {
    func statuses(
        for itinerary: Itinerary,
        scan: TicketPDFScanResult,
        travelerProfile: TravelerProfile,
        entryAssessment: EntryAssessment?,
        now: Date
    ) -> [TicketConnectionStatus] {
        guard itinerary.legs.count > 1 else { return [] }
        return (0..<(itinerary.legs.count - 1)).map { index in
            let inbound = itinerary.legs[index]
            let outbound = itinerary.legs[index + 1]
            let assessment = baggageAssessment(
                itinerary: itinerary,
                inbound: inbound,
                outbound: outbound,
                scan: scan,
                now: now
            )
            return TicketConnectionStatus(
                id: StableEntityID.uuid("ticket-connection|\(scan.sourceRecordID)|\(inbound.id.uuidString)|\(outbound.id.uuidString)"),
                inboundLegID: inbound.id,
                outboundLegID: outbound.id,
                connectionLabel: "\(inbound.flight.flightNumber) → \(outbound.flight.flightNumber)",
                transferFlow: transferFlow(for: assessment.state, changesAirport: inbound.flight.destination.iata != outbound.flight.origin.iata),
                baggageAssessment: assessment,
                requiredSegments: requiredSegments(
                    state: assessment.state,
                    changesAirport: inbound.flight.destination.iata != outbound.flight.origin.iata
                ),
                transitStatus: transitStatus(profile: travelerProfile, entryAssessment: entryAssessment, now: now),
                scannedAt: scan.scannedAt,
                sourceRecordID: scan.sourceRecordID
            )
        }
    }

    private func transferFlow(for state: ConnectionBaggageState, changesAirport: Bool) -> TransferFlow {
        if changesAirport { return .airportChange }
        return state == .selfTransferSeparateTicket ? .selfTransfer : .standardConnection
    }

    private func baggageAssessment(
        itinerary: Itinerary,
        inbound: ItineraryLeg,
        outbound: ItineraryLeg,
        scan: TicketPDFScanResult,
        now: Date
    ) -> ConnectionBaggageAssessment {
        let finalDestination = itinerary.legs.last?.flight.destination.iata
        let connectionAirport = inbound.flight.destination.iata
        let explicitDestination = scan.baggageSignals.compactMap { signal -> String? in
            if case let .bagTagDestination(code) = signal { return code }
            return nil
        }.last

        let state: ConnectionBaggageState
        if scan.baggageSignals.contains(.noCheckedBag) || scan.baggageSignals.contains(.automaticTransfer) {
            state = .throughChecked
        } else if scan.baggageSignals.contains(.selfTransfer) {
            state = .selfTransferSeparateTicket
        } else if scan.baggageSignals.contains(.collectAndRecheck) {
            state = .reclaimImmigrationCustomsRecheck
        } else if let explicitDestination,
                  explicitDestination == finalDestination,
                  explicitDestination != connectionAirport {
            state = .throughChecked
        } else if let explicitDestination,
                  explicitDestination == connectionAirport || explicitDestination == outbound.flight.origin.iata {
            state = .reclaimImmigrationCustomsRecheck
        } else {
            state = .unknown
        }

        let fact: SourcedAirlineFact<ConnectionBaggageHandling>? = {
            guard state != .unknown else { return nil }
            return SourcedAirlineFact(
                value: ConnectionBaggageHandling(
                    state: state,
                    bagTagDestinationAirportCode: explicitDestination,
                    separateTickets: state == .selfTransferSeparateTicket ? true : nil,
                    instructions: baggageInstructions(for: state, destination: explicitDestination)
                ),
                verification: .unknown,
                provider: "Local ticket PDF scan",
                providerField: "ticketText.baggage",
                sourceRecordID: scan.sourceRecordID,
                observedAt: scan.scannedAt,
                receivedAt: now,
                expiresAt: now.addingTimeInterval(12 * 60 * 60),
                isLive: false,
                derivation: [
                    DerivationStep(
                        label: "Ticket text scan",
                        formula: "route codes + baggage keywords + bag-tag destination",
                        inputRecordIDs: [
                            scan.sourceRecordID,
                            "route:\(scan.routeAirportCodes.joined(separator: "-"))",
                            "connection:\(inbound.flight.destination.iata)-\(outbound.flight.origin.iata)",
                            "bagTag:\(explicitDestination ?? "not-found")"
                        ],
                        result: state.rawValue
                    )
                ]
            )
        }()

        return ConnectionBaggageAssessment(
            itineraryID: itinerary.id,
            inboundLegID: inbound.id,
            outboundLegID: outbound.id,
            handling: fact,
            availability: fact == nil ? .unavailable : .requiresConfirmation,
            advisory: baggageAdvisory(for: state, destination: explicitDestination)
        )
    }

    private func transitStatus(
        profile: TravelerProfile,
        entryAssessment: EntryAssessment?,
        now: Date
    ) -> TicketTransitStatus {
        guard profile.hasMinimumEntryFacts else { return .addTravelerDetails }
        guard let entryAssessment else { return .notEnoughInformation }
        guard entryAssessment.isCurrent(at: now) else { return .refreshNeeded }
        switch entryAssessment.status {
        case .authorizationNotIndicated:
            return .current
        case .authorizationRequired:
            return .mayNeedAuthorization
        case .conditional:
            return .conditional
        case .cannotDetermine:
            return .notEnoughInformation
        }
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

    private func baggageInstructions(for state: ConnectionBaggageState, destination: String?) -> [String] {
        switch state {
        case .throughChecked:
            if destination != nil {
                ["Your ticket shows your bags continuing to \(destination!)."]
            } else {
                ["Your ticket shows an automatic connection."]
            }
        case .reclaimImmigrationCustomsRecheck:
            ["Ticket text indicates bag collection and recheck."]
        case .selfTransferSeparateTicket:
            ["Ticket text indicates a separate-ticket self-transfer."]
        case .confirmationRequired, .unknown:
            []
        }
    }

    private func baggageAdvisory(for state: ConnectionBaggageState, destination: String?) -> String {
        switch state {
        case .throughChecked:
            destination.map { "Your checked bag continues to \($0)." } ?? "No checked-bag collection is shown."
        case .reclaimImmigrationCustomsRecheck:
            "Collect your checked bag and check it in again."
        case .selfTransferSeparateTicket:
            "Collect your checked bag and check it in again for the next ticket."
        case .confirmationRequired, .unknown:
            "Bag instructions need confirmation."
        }
    }
}
