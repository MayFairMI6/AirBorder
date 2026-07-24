import Foundation
import UIKit
import Vision

struct SeatbackOCRResult: Sendable {
    let lines: [String]
    let meanConfidence: Double
    let progressPercent: Double?
    let capturedAt: Date
}

enum SeatbackOCRError: LocalizedError {
    case invalidImage
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage: "The selected file is not a readable image."
        case .noText: "No display text was recognized. Try a sharper, glare-free crop."
        }
    }
}

struct SeatbackDisplayOCRService: Sendable {
    func recognize(imageData: Data) async throws -> SeatbackOCRResult {
        guard let image = UIImage(data: imageData)?.cgImage else { throw SeatbackOCRError.invalidImage }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            let candidates = (request.results ?? []).compactMap { observation -> (String, Double)? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return (candidate.string, Double(candidate.confidence))
            }
            guard !candidates.isEmpty else { throw SeatbackOCRError.noText }
            let lines = candidates.map(\.0)
            let confidence = candidates.reduce(0) { $0 + $1.1 } / Double(candidates.count)
            let joined = lines.joined(separator: " ")
            let progress = Self.parseProgress(from: joined)
            return SeatbackOCRResult(lines: lines, meanConfidence: confidence, progressPercent: progress, capturedAt: Date())
        }.value
    }

    private static func parseProgress(from text: String) -> Double? {
        guard let expression = try? NSRegularExpression(pattern: #"\b(\d{1,3})\s*%"#),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]),
              (0...100).contains(value) else { return nil }
        return value
    }
}
