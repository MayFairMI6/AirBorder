import MapKit
import SwiftUI

/// Test-only city-scale map used by the inter-airport practice driver.
/// It keeps the traffic choice visible without presenting it as live traffic.
struct CityTransferMapCard: View {
    let origin: String
    let destination: String
    let traffic: String
    let configuration: CityTransferPracticeMapConfiguration
    @State private var lookAroundScene: MKLookAroundScene?

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: configuration.center,
            span: MKCoordinateSpan(latitudeDelta: configuration.latitudeDelta, longitudeDelta: configuration.longitudeDelta)
        )
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("City transfer", systemImage: "arrow.triangle.swap")
                        .font(.headline)
                    Spacer()
                    Label(trafficTitle, systemImage: trafficSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trafficColor)
                }
                Map(initialPosition: .region(region)) {
                    Marker(origin, coordinate: configuration.originCoordinate)
                        .tint(.teal)
                    Marker("Recommended stop", coordinate: configuration.stopCoordinate)
                        .tint(.orange)
                    Marker(destination, coordinate: configuration.destinationCoordinate)
                        .tint(.green)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                if let lookAroundScene {
                    LookAroundPreview(initialScene: lookAroundScene)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Street-level view near the recommended stop")
                }
                Text("\(origin) → recommended stop → \(destination)")
                    .font(.subheadline.weight(.semibold))
                Text("Choose light, typical, or heavy traffic to compare transfer times.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("cityTransferMapCard")
        .task(id: configuration.stopCoordinate.latitude) {
            lookAroundScene = try? await MKLookAroundSceneRequest(coordinate: configuration.stopCoordinate).scene
        }
    }

    private var trafficTitle: String {
        switch traffic {
        case "light": "Light traffic"
        case "heavy": "Heavy traffic"
        default: "Typical traffic"
        }
    }

    private var trafficSymbol: String {
        switch traffic {
        case "light": "car.fill"
        case "heavy": "car.fill"
        default: "car"
        }
    }

    private var trafficColor: Color {
        switch traffic {
        case "light": .green
        case "heavy": .red
        default: .orange
        }
    }
}
