import Foundation

/// Pure catalog filtering rules used by MoreAppsKit.
public enum MoreAppsFilter {
    /// Filters, de-duplicates, sorts, and optionally limits an app catalog.
    ///
    /// The first item for a duplicated ID wins. Items with equal sort orders keep
    /// their input order.
    ///
    /// - Parameters:
    ///   - apps: The unfiltered catalog.
    ///   - platform: The host platform.
    ///   - bundleIdentifier: The host app's bundle identifier, if available.
    ///   - maximumNumberOfItems: An optional maximum number of results.
    /// - Returns: Apps safe to display in ascending `sortOrder` order.
    public static func filtered(
        _ apps: [MoreApp],
        for platform: MoreAppsPlatform,
        excluding bundleIdentifier: String?,
        maximumNumberOfItems: Int? = nil
    ) -> [MoreApp] {
        var seenIDs = Set<MoreApp.ID>()

        let eligible = apps.enumerated().compactMap { index, app -> (Int, MoreApp)? in
            guard app.destination(for: platform) != nil,
                  app.bundleIdentifier != bundleIdentifier,
                  seenIDs.insert(app.id).inserted else {
                return nil
            }
            return (index, app)
        }

        let sorted = eligible.sorted { lhs, rhs in
            if lhs.1.sortOrder == rhs.1.sortOrder {
                return lhs.0 < rhs.0
            }
            return lhs.1.sortOrder < rhs.1.sortOrder
        }.map(\.1)

        guard let maximumNumberOfItems else {
            return sorted
        }
        return Array(sorted.prefix(max(0, maximumNumberOfItems)))
    }
}
