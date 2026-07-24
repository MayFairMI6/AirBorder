import SwiftUI

struct LaunchDataModeBanner: View {
    let context: AppLaunchContext
    let freshness: DataFreshness

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            bannerText
            Spacer(minLength: 0)
        }
        .padding(12)
        .foregroundStyle(.primary)
        .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var bannerText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(context.badgeTitle)
                .font(.body)
                .fontWeight(.bold)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.footnote)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)
    }

    private var detail: String {
        switch freshness {
        case .live: "Updated with current travel information"
        case .cached: "Saved from your last update"
        case .stale: "Needs refresh before planning"
        case .demo: "Your journey through Bangkok, Haneda, and Los Angeles"
        case .unavailable: "Trip information is not available yet"
        }
    }

    private var symbol: String {
        switch context.mode {
        case .live: "dot.radiowaves.left.and.right"
        case .demo: "airplane.circle.fill"
        case .offline: "wifi.slash"
        case .stochastic: "map.circle.fill"
        }
    }

    private var color: Color {
        switch freshness {
        case .live: .green
        case .cached: .blue
        case .stale, .unavailable: .orange
        case .demo: .purple
        }
    }
}

struct FeasibilityPill: View {
    let status: FeasibilityStatus

    var body: some View {
        Label(status.title, systemImage: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Plan status: \(status.title)")
    }

    private var color: Color {
        switch status {
        case .safe: .green
        case .tight: .orange
        case .requiresConfirmation: .blue
        case .notRecommended: .red
        }
    }

    private var symbol: String {
        switch status {
        case .safe: "checkmark.shield.fill"
        case .tight: "clock.badge.exclamationmark.fill"
        case .requiresConfirmation: "questionmark.circle.fill"
        case .notRecommended: "xmark.octagon.fill"
        }
    }
}

struct PlaceCategorySymbol {
    static func name(for category: LayoverPlaceCategory) -> String {
        switch category {
        case .hotel, .transitHotel, .dayRoom: "bed.double.fill"
        case .workPod: "laptopcomputer"
        case .lounge: "sofa.fill"
        case .shower: "shower.fill"
        case .charging: "bolt.fill"
        case .food: "fork.knife"
        case .facility: "building.2.fill"
        case .attraction: "camera.fill"
        }
    }
}
