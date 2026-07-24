import Foundation
import UIKit
import Vision

struct TravelerDocumentPrefill: Sendable {
    var nationalityCountryCode: String?
    var residenceCountryCode: String?
    var passportType: PassportType?
}

enum TravelerDocumentPrefillError: LocalizedError {
    case unreadableImage
    case noRecognizedText

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "Choose a clear photo of the document."
        case .noRecognizedText: "No readable details were found. You can enter them manually."
        }
    }
}

/// Reads an image locally to propose a small set of traveler-profile fields.
/// The selected image is never persisted, uploaded, or attached to the profile.
struct TravelerDocumentPrefillService: Sendable {
    func prefill(from imageData: Data) async throws -> TravelerDocumentPrefill {
        guard let image = UIImage(data: imageData)?.cgImage else {
            throw TravelerDocumentPrefillError.unreadableImage
        }
        let task = Task.detached(priority: .userInitiated) { () throws -> TravelerDocumentPrefill in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TravelerDocumentPrefillError.noRecognizedText
            }
            return TravelerDocumentPrefill(
                nationalityCountryCode: TravelerDocumentPrefillService.country(after: "NATIONALITY", in: text),
                residenceCountryCode: TravelerDocumentPrefillService.country(after: "RESIDENCE", in: text),
                passportType: text.uppercased().contains("DIPLOMATIC") ? .diplomatic : nil
            )
        }
        return try await task.value
    }

    private static func country(after label: String, in text: String) -> String? {
        let pattern = #"\#(label)\s*[:\-]?\s*([A-Z]{2})\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).uppercased()
    }
}
