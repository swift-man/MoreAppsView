import Foundation

/// An analytics-neutral event emitted by ``MoreAppsView``.
public enum MoreAppsEvent: Equatable, Sendable {
    /// A card became visible for the first time in the current data session.
    case impression(appID: String)

    /// The user selected a card.
    case selected(appID: String)

    /// The app's deep link opened successfully.
    case openedApp(appID: String)

    /// The app's App Store page opened successfully.
    case openedAppStore(appID: String)

    /// Neither the deep link nor the App Store URL opened successfully.
    case failedToOpen(appID: String)

    /// A provider failed to load an app catalog.
    case loadingFailed(message: String)
}
