import PhotosUI
import SwiftUI

struct InFlightProgressView: View {
    @EnvironmentObject private var viewModel: LongHaulExperienceViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var ocrResult: SeatbackOCRResult?
    @State private var ocrError: String?
    @State private var isReading = false
    @State private var recordedWindowCue = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Flight progress", systemImage: "airplane.circle.fill")
                            .font(.headline)
                        RouteProgressCanvas(progress: itineraryProgress)
                            .frame(height: 150)
                            .accessibilityHidden(true)
                        HStack {
                            Text("BKK").font(.headline)
                            Spacer()
                            Text("HND").font(.headline).foregroundStyle(.teal)
                            Spacer()
                            Text("LAX").font(.headline)
                        }
                        Text("This estimate uses your itinerary times. Scan the seatback display to update it during the flight.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Seatback display scan", systemImage: "text.viewfinder")
                            .font(.headline)
                        Text("Choose a cropped photo of the seatback display. Apple Vision reads it locally; the image is not uploaded.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(isReading ? "Reading locally…" : "Choose display photo", systemImage: "photo")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .disabled(isReading)
                        .accessibilityIdentifier("seatbackOCRPicker")

                        if let result = ocrResult {
                            LabeledContent("Display progress", value: result.progressPercent.map { "\(Int($0.rounded()))%" } ?? "Not detected")
                            DisclosureGroup("Recognized text") {
                                Text(result.lines.joined(separator: "\n"))
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            Text("Your scanned display can help keep your trip progress up to date.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let ocrError { InlineNotice(message: ocrError) }
                    }
                }

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("In-flight view", systemImage: "camera.metering.center.weighted")
                            .font(.headline)
                        Text("Add what you can see from the window to enrich your trip view.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button {
                            recordedWindowCue = true
                        } label: {
                            Label(recordedWindowCue ? "View added" : "Add window view", systemImage: recordedWindowCue ? "checkmark.circle.fill" : "camera")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("In-flight Progress")
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
        .accessibilityIdentifier("inFlightProgressView")
    }

    private var itineraryProgress: Double {
        guard let itinerary = viewModel.itinerary,
              let start = itinerary.legs.first?.flight.effectiveDeparture,
              let end = itinerary.legs.last?.flight.effectiveArrival,
              end > start else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    private func read(_ item: PhotosPickerItem) async {
        isReading = true
        ocrError = nil
        defer { isReading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw SeatbackOCRError.invalidImage
            }
            ocrResult = try await SeatbackDisplayOCRService().recognize(imageData: data)
        } catch {
            ocrResult = nil
            ocrError = (error as? LocalizedError)?.errorDescription ?? "Local OCR failed."
        }
    }

}

private struct RouteProgressCanvas: View {
    let progress: Double

    var body: some View {
        Canvas { context, size in
            let start = CGPoint(x: size.width * 0.08, y: size.height * 0.72)
            let midpoint = CGPoint(x: size.width * 0.50, y: size.height * 0.28)
            let end = CGPoint(x: size.width * 0.92, y: size.height * 0.72)
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: midpoint.x, y: 0))
            context.stroke(path, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 4, dash: [8, 5]))

            let marker: CGPoint
            if progress <= 0.5 {
                let local = progress / 0.5
                marker = CGPoint(x: start.x + (midpoint.x - start.x) * local, y: start.y + (midpoint.y - start.y) * local)
            } else {
                let local = (progress - 0.5) / 0.5
                marker = CGPoint(x: midpoint.x + (end.x - midpoint.x) * local, y: midpoint.y + (end.y - midpoint.y) * local)
            }
            context.draw(Image(systemName: "airplane"), at: marker)
            for point in [start, midpoint, end] {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)), with: .color(.teal))
            }
        }
    }
}
