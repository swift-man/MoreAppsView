import Foundation

/// URLs used to open one promoted app on a specific platform.
public struct MoreAppDestination: Codable, Hashable, Sendable {
    /// The platform to which the URLs apply.
    public let platform: MoreAppsPlatform

    /// The App Store product URL for the app.
    public let appStoreURL: URL

    /// An optional custom-scheme or universal-link URL for opening the app.
    public let deepLinkURL: URL?

    /// Creates a platform-specific destination.
    ///
    /// - Parameters:
    ///   - platform: The platform to which the URLs apply.
    ///   - appStoreURL: The App Store product URL.
    ///   - deepLinkURL: An optional URL that opens the installed app directly.
    public init(
        platform: MoreAppsPlatform,
        appStoreURL: URL,
        deepLinkURL: URL? = nil
    ) {
        self.platform = platform
        self.appStoreURL = appStoreURL
        self.deepLinkURL = deepLinkURL
    }
}
