import SwiftUI

enum AirportXRPalette {
    /// #00666F keeps the teal identity while exceeding WCAG AA contrast with white text.
    static let actionTeal = Color(red: 0, green: 0.4, blue: 0.435)
}

enum AirportXRLayout {
    /// Apple platform minimum comfortable touch target; also keeps scroll content clear of the floating tab bar.
    static let minimumTouchTarget: CGFloat = 44
    static let primaryActionMinimumHeight: CGFloat = 52
    /// Three touch targets cover the floating tab bar plus its material margin at accessibility sizes.
    static let floatingTabBarClearance = minimumTouchTarget * 3
}

struct SurfaceCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(contrast == .increased ? Color.primary.opacity(0.42) : Color.primary.opacity(0.08), lineWidth: contrast == .increased ? 2 : 1)
            }
    }
}

struct AirlineFlightSummary: View {
    let flight: Flight
    let legNumber: Int
    let legCount: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FLIGHT \(legNumber) OF \(legCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AirportXRPalette.actionTeal)
                    Text(flight.airlineName ?? flight.flightNumber)
                        .font(.subheadline.weight(.semibold))
                    if flight.airlineName != nil {
                        Text(flight.flightNumber)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                StatusPill(status: flight.status)
            }

            if dynamicTypeSize.isAccessibilitySize {
                verticalRoute
            } else {
                horizontalRoute
            }

            HStack(spacing: 16) {
                if let boardingTime = flight.boardingTime {
                    compactFact(
                        title: "Boarding",
                        value: localTime(boardingTime, zone: flight.origin.timeZone),
                        symbol: "person.line.dotted.person.fill"
                    )
                }
                compactFact(
                    title: "Gate",
                    value: flight.gate ?? "Pending",
                    symbol: "door.left.hand.open"
                )
                if let group = flight.boardingGroup, !group.isEmpty {
                    compactFact(title: "Group", value: group, symbol: "person.3.fill")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("airlineFlightSummary-\(legNumber)")
    }

    private var horizontalRoute: some View {
        HStack(alignment: .top, spacing: 10) {
            endpoint(
                airport: flight.origin,
                date: flight.effectiveDeparture,
                terminal: flight.departureTerminal,
                gate: flight.gate,
                isLeading: true
            )
            routeConnector
            endpoint(
                airport: flight.destination,
                date: flight.effectiveArrival,
                terminal: flight.arrivalTerminal,
                gate: flight.arrivalGate,
                isLeading: false
            )
        }
    }

    private var verticalRoute: some View {
        VStack(spacing: 12) {
            endpointRow(
                title: "Departs",
                airport: flight.origin,
                date: flight.effectiveDeparture,
                terminal: flight.departureTerminal,
                gate: flight.gate
            )
            Divider()
            endpointRow(
                title: "Arrives",
                airport: flight.destination,
                date: flight.effectiveArrival,
                terminal: flight.arrivalTerminal,
                gate: flight.arrivalGate
            )
        }
    }

    private func endpoint(
        airport: Airport,
        date: Date?,
        terminal: String?,
        gate: String?,
        isLeading: Bool
    ) -> some View {
        VStack(alignment: isLeading ? .leading : .trailing, spacing: 2) {
            Text(airport.iata)
                .font(.title.bold())
            Text(localTime(date, zone: airport.timeZone))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(localDate(date, zone: airport.timeZone))
                .font(.caption.weight(.medium))
            Text(endpointPlace(airport: airport, terminal: terminal, gate: gate))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(isLeading ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
    }

    private func endpointRow(
        title: String,
        airport: Airport,
        date: Date?,
        terminal: String?,
        gate: String?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(airport.iata).font(.title2.bold())
                Text(airport.city ?? airport.name).font(.caption)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(localTime(date, zone: airport.timeZone))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(localDate(date, zone: airport.timeZone)).font(.caption.weight(.medium))
                Text(endpointPlace(airport: airport, terminal: terminal, gate: gate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var routeConnector: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Rectangle().fill(Color.secondary.opacity(0.35)).frame(height: 1)
                Image(systemName: "airplane")
                    .foregroundStyle(AirportXRPalette.actionTeal)
                    .accessibilityHidden(true)
                Rectangle().fill(Color.secondary.opacity(0.35)).frame(height: 1)
            }
            if let offset = arrivalDayOffset {
                Text(offset)
                    .font(.caption2.bold())
                    .foregroundStyle(AirportXRPalette.actionTeal)
            }
        }
        .frame(maxWidth: 86)
        .padding(.top, 12)
    }

    private func compactFact(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func endpointPlace(airport: Airport, terminal: String?, gate: String?) -> String {
        var parts = [airport.city ?? airport.name]
        if let terminal, !terminal.isEmpty { parts.append("Terminal \(terminal)") }
        if let gate, !gate.isEmpty { parts.append("Gate \(gate)") }
        return parts.joined(separator: " · ")
    }

    private func localTime(_ date: Date?, zone: String?) -> String {
        guard let date else { return "Time pending" }
        var style = Date.FormatStyle().hour().minute()
        if let zone, let timeZone = TimeZone(identifier: zone) { style.timeZone = timeZone }
        return date.formatted(style)
    }

    private func localDate(_ date: Date?, zone: String?) -> String {
        guard let date else { return "Date pending" }
        var style = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        if let zone, let timeZone = TimeZone(identifier: zone) { style.timeZone = timeZone }
        return date.formatted(style)
    }

    private var arrivalDayOffset: String? {
        guard let departure = flight.effectiveDeparture,
              let arrival = flight.effectiveArrival else { return nil }
        let departureDay = normalizedDay(departure, zone: flight.origin.timeZone)
        let arrivalDay = normalizedDay(arrival, zone: flight.destination.timeZone)
        guard let departureDay, let arrivalDay else { return nil }
        let offset = Calendar(identifier: .gregorian).dateComponents([.day], from: departureDay, to: arrivalDay).day ?? 0
        guard offset != 0 else { return nil }
        return offset > 0 ? "+\(offset) day" : "\(offset) day"
    }

    private func normalizedDay(_ date: Date, zone: String?) -> Date? {
        var localCalendar = Calendar(identifier: .gregorian)
        if let zone, let timeZone = TimeZone(identifier: zone) { localCalendar.timeZone = timeZone }
        let components = localCalendar.dateComponents([.year, .month, .day], from: date)
        var neutralCalendar = Calendar(identifier: .gregorian)
        neutralCalendar.timeZone = .gmt
        return neutralCalendar.date(from: components)
    }

    private var accessibilitySummary: String {
        "Flight \(flight.flightNumber), \(flight.status.title), \(flight.origin.iata) to \(flight.destination.iata). Departs \(localDate(flight.effectiveDeparture, zone: flight.origin.timeZone)) at \(localTime(flight.effectiveDeparture, zone: flight.origin.timeZone)). Arrives \(localDate(flight.effectiveArrival, zone: flight.destination.timeZone)) at \(localTime(flight.effectiveArrival, zone: flight.destination.timeZone)). Gate \(flight.gate ?? "pending")."
    }
}

struct StatusPill: View {
    let status: FlightStatus
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(statusColor)
            .background(statusColor.opacity(differentiateWithoutColor ? 0.05 : 0.14), in: Capsule())
            .overlay { Capsule().stroke(statusColor.opacity(0.42), lineWidth: differentiateWithoutColor ? 2 : 0) }
            .accessibilityLabel("Flight status: \(status.title)")
    }

    private var statusColor: Color {
        return switch status {
        case .cancelled, .diverted: .red
        case .delayed: .orange
        case .boarding, .boardingSoon: .blue
        case .arrived, .onTime: .green
        default: .teal
        }
    }
}

struct FreshnessBanner: View {
    let freshness: DataFreshness
    let updatedAt: Date
    let isOnline: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("Updated \(updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .foregroundStyle(foreground)
        .background(foreground.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if !isOnline { return "Saved flight information" }
        return switch freshness {
        case .live: "Live flight information"
        case .cached: "Saved flight information"
        case .stale: "Refresh flight information"
        case .demo: "Flight information for this itinerary"
        case .unavailable: "Live flight information unavailable"
        }
    }

    private var symbol: String {
        if !isOnline { return "wifi.slash" }
        return switch freshness {
        case .live: "dot.radiowaves.left.and.right"
        case .cached: "externaldrive.fill"
        case .stale: "clock.badge.exclamationmark"
        case .demo: "airplane.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var foreground: Color {
        return switch freshness {
        case .live: .green
        case .cached: .blue
        case .stale, .unavailable: .orange
        case .demo: .purple
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.primary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct InlineNotice: View {
    let message: String
    var symbol = "info.circle.fill"
    var color: Color = .orange

    var body: some View {
        Label {
            Text(message).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.subheadline)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(color)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}
