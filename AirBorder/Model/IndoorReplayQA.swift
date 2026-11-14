// PROCEDURAL: Simulator-only bridge for inspecting route behavior with synthetic inputs.
#if DEBUG && targetEnvironment(simulator)
import Foundation

enum IndoorReplayQA {
    private struct Reading: Decodable {
        let level: Int
        let matchedNodeID: String
        let source: String

        var routeStep: Int? {
            guard source == "externalSignalReplay" else { return nil }
            // These IDs belong to the scripted Haneda route, not a surveyed map.
            switch (matchedNodeID, level) {
            case ("t3-transfer-security", 3), ("t3-departures-center", 3),
                 ("t3-elevator-north", 3): return 1
            case ("t3-gates-center", 4): return 2
            case ("gate-105", 4): return 3
            default: return nil
            }
        }
    }

    @MainActor
    static func run(arguments: [String], store: JourneyStore) async {
        guard arguments.contains("--uitesting"),
              let flag = arguments.firstIndex(of: "--qa-indoor-feed"),
              arguments.indices.contains(flag + 1),
              let url = URL(string: arguments[flag + 1]),
              url.scheme == "http", url.host == "127.0.0.1", url.port != nil,
              url.path == "/reading", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return }

        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        while !Task.isCancelled {
            if !store.isAirportTransfer, store.gate == SampleJourney.outbound.departureGate,
               let (data, response) = try? await session.data(for: URLRequest(url: url, timeoutInterval: 1)),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let step = (try? JSONDecoder().decode(Reading.self, from: data))?.routeStep,
               !Task.isCancelled, !store.isAirportTransfer,
               store.gate == SampleJourney.outbound.departureGate, store.routeStep != step {
                store.routeStep = step
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
#endif
