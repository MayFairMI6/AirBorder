import Foundation

struct AppConfiguration: Sendable {
    let aviationProxyBaseURL: URL?
    let aviationProviderLabel: String
    let cloudVisionProxyBaseURL: URL?

    static func load(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> AppConfiguration {
        let proxyValue = environment["AVIATION_PROXY_BASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "AviationProxyBaseURL") as? String
        let provider = bundle.object(forInfoDictionaryKey: "AviationProviderLabel") as? String
            ?? "Travel updates"
        let visionValue = environment["CLOUD_VISION_PROXY_BASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "CloudVisionProxyBaseURL") as? String

        return AppConfiguration(
            aviationProxyBaseURL: validatedServiceURL(proxyValue),
            aviationProviderLabel: provider,
            cloudVisionProxyBaseURL: validatedServiceURL(visionValue)
        )
    }

    private static func validatedServiceURL(_ rawValue: String?) -> URL? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              url.host != nil else {
            return nil
        }

        #if DEBUG
        let isLocalDevelopment = scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host?.lowercased() ?? "")
        if scheme == "https" || isLocalDevelopment { return url }
        #else
        if scheme == "https" { return url }
        #endif
        return nil
    }

}
