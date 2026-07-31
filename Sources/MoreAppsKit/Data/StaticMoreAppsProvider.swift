import Foundation

/// A provider that returns app metadata supplied directly in code.
public struct StaticMoreAppsProvider: MoreAppsProviding {
    private let apps: [MoreApp]

    /// Creates a static provider.
    ///
    /// - Parameter apps: The unfiltered app catalog to return.
    public init(apps: [MoreApp]) {
        self.apps = apps
    }

    /// Returns the catalog supplied at initialization.
    public func fetchApps() async throws -> [MoreApp] {
        apps
    }
}
