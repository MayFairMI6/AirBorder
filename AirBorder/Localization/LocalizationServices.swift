import CoreGraphics
import Foundation
import UIKit
import Vision

enum LocalizationSignalKind: String, Codable, Sendable {
    case qrMarker
    case gateText
    case manual
    case cloudSign
}

struct LocalizationSignal: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: LocalizationSignalKind
    let label: String
    let nodeID: String?
    let confidence: Double
    let capturedAt: Date
}

protocol ImageLocalizationProviding: Sendable {
    func analyze(image: CGImage) async throws -> [LocalizationSignal]
}

struct VisionMarkerLocalizationService: ImageLocalizationProviding {
    func analyze(image: CGImage) async throws -> [LocalizationSignal] {
        try await Task.detached(priority: .userInitiated) {
            let barcode = VNDetectBarcodesRequest()
            barcode.symbologies = [.qr]
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .fast
            text.usesLanguageCorrection = false
            text.minimumTextHeight = 0.04

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([barcode, text])
            let now = Date()
            var signals: [LocalizationSignal] = []
            for observation in barcode.results ?? [] {
                guard let payload = observation.payloadStringValue, payload.hasPrefix("AIRPORTXR:") else { continue }
                let nodeID = String(payload.dropFirst("AIRPORTXR:".count))
                signals.append(LocalizationSignal(id: UUID(), kind: .qrMarker, label: "Airport marker \(nodeID)", nodeID: nodeID, confidence: Double(observation.confidence), capturedAt: now))
            }
            for observation in text.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let value = candidate.string.uppercased()
                if value.range(of: #"\bGATE\s*[A-Z]?\d{1,3}\b"#, options: .regularExpression) != nil
                    || value.range(of: #"\b[A-Z]\d{1,3}\b"#, options: .regularExpression) != nil {
                    signals.append(LocalizationSignal(id: UUID(), kind: .gateText, label: value, nodeID: nil, confidence: Double(candidate.confidence), capturedAt: now))
                }
            }
            return signals.sorted { $0.confidence > $1.confidence }
        }.value
    }
}

struct CloudVisionResponse: Decodable, Sendable {
    struct Result: Decodable, Sendable {
        let label: String
        let nodeID: String?
        let confidence: Double
    }
    let results: [Result]
}

struct ProxyCloudVisionService: ImageLocalizationProviding, @unchecked Sendable {
    let endpoint: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.endpoint = baseURL.appendingPathComponent("v1/scene-ocr")
        self.session = session
    }

    func analyze(image: CGImage) async throws -> [LocalizationSignal] {
        let uiImage = UIImage(cgImage: image)
        guard let data = uiImage.jpegData(compressionQuality: 0.72), data.count <= 512_000 else {
            throw CloudVisionError.imageTooLarge
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("true", forHTTPHeaderField: "X-Cloud-Vision-Consent")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Capture-ID")
        request.httpBody = data
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), responseData.count <= 256_000 else {
            throw CloudVisionError.unavailable
        }
        let payload = try JSONDecoder().decode(CloudVisionResponse.self, from: responseData)
        let now = Date()
        return payload.results.map {
            LocalizationSignal(id: UUID(), kind: .cloudSign, label: $0.label, nodeID: $0.nodeID, confidence: $0.confidence, capturedAt: now)
        }
    }
}

enum CloudVisionError: Error, Sendable {
    case imageTooLarge
    case unavailable
    case consentRequired
}

struct HybridLocalizationService: ImageLocalizationProviding {
    let local: any ImageLocalizationProviding
    let cloud: (any ImageLocalizationProviding)?
    let cloudOptIn: @Sendable () -> Bool

    func analyze(image: CGImage) async throws -> [LocalizationSignal] {
        let localResults = try await local.analyze(image: image)
        if localResults.first?.confidence ?? 0 >= 0.75 || cloud == nil { return localResults }
        guard cloudOptIn() else { return localResults }
        do {
            let cloudResults = try await cloud?.analyze(image: image) ?? []
            return (localResults + cloudResults).sorted { $0.confidence > $1.confidence }
        } catch {
            return localResults
        }
    }
}
