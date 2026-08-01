import Foundation

enum MoreAppsURLPolicy {
    static func allowedDeepLink(
        _ url: URL?,
        allowedCustomSchemes: Set<String>
    ) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              !scheme.isEmpty else {
            return nil
        }

        if scheme == "https" {
            return allowedAppStoreURL(url) == nil ? url : nil
        }

        guard scheme != "http" else { return nil }

        return allowedCustomSchemes.contains(scheme) ? url : nil
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
