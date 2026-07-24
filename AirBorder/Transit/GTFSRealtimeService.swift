import Foundation

protocol GTFSRealtimeServing: Sendable {
    func alerts() async throws -> [String]
}

struct GTFSRealtimeService: GTFSRealtimeServing {
    let feedURL: URL?
    let session: URLSession

    init(feedURL: URL?, session: URLSession = .shared) {
        self.feedURL = feedURL
        self.session = session
    }

    func alerts() async throws -> [String] {
        guard let feedURL else { return [] }
        let (_, response) = try await session.data(from: feedURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // A production adapter decodes the official GTFS-Realtime protobuf FeedMessage.
        // The protocol boundary keeps that generated schema out of the UI and route planner.
        return []
    }
}

