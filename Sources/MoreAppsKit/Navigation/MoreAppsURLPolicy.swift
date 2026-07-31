import Foundation

enum MoreAppsURLPolicy {
    private static let blockedDeepLinkSchemes: Set<String> = [
        "about",
        "app-prefs",
        "data",
        "facetime",
        "facetime-audio",
        "file",
        "http",
        "itms-services",
        "javascript",
        "mailto",
        "prefs",
        "sms",
        "tel",
        "telprompt"
    ]

    static func allowedDeepLink(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              !scheme.isEmpty,
              !blockedDeepLinkSchemes.contains(scheme) else {
            return nil
        }
        return url
    }

    static func allowedAppStoreURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "itms-apps",
              let host = url.host?.lowercased(),
              host == "apps.apple.com"
                || host == "itunes.apple.com"
                || host.hasSuffix(".itunes.apple.com") else {
            return nil
        }
        return url
    }
}
