import UIKit

/// Visual and behavioral options for ``MoreAppsView``.
public struct MoreAppsConfiguration: Equatable {
    /// An optional title override. `nil` uses the package-localized title.
    public var title: String?

    /// Whether the title is visible.
    public var showsTitle: Bool

    /// Whether the entire view hides itself when no apps are displayable.
    public var hidesWhenEmpty: Bool

    /// The corner radius applied to each app card.
    public var cardCornerRadius: CGFloat

    /// The horizontal spacing between cards.
    public var cardSpacing: CGFloat

    /// Insets around the scrolling card content.
    public var contentInsets: NSDirectionalEdgeInsets

    /// An optional maximum number of displayed apps.
    public var maximumNumberOfItems: Int?

    /// Whether app subtitles are visible.
    public var showsSubtitle: Bool

    /// Custom URL schemes that may be opened as deep links.
    ///
    /// HTTPS Universal Links are always eligible. All non-HTTPS schemes are
    /// denied unless their scheme name appears in this set.
    public var allowedCustomDeepLinkSchemes: Set<String>

    /// The SF Symbol shown while an icon is unavailable.
    public var placeholderSystemImageName: String

    /// Creates a More Apps presentation configuration.
    ///
    /// - Parameters:
    ///   - title: An optional title override. `nil` uses package localization.
    ///   - showsTitle: Whether the title is visible.
    ///   - hidesWhenEmpty: Whether the view hides when the filtered list is empty.
    ///   - cardCornerRadius: The card corner radius.
    ///   - cardSpacing: The distance between cards.
    ///   - contentInsets: Insets around the horizontal list.
    ///   - maximumNumberOfItems: An optional result limit.
    ///   - showsSubtitle: Whether subtitles are visible.
    ///   - allowedCustomDeepLinkSchemes: Non-HTTPS schemes explicitly trusted
    ///     by the host app. Scheme matching is case-insensitive.
    ///   - placeholderSystemImageName: The fallback SF Symbol name.
    public init(
        title: String? = nil,
        showsTitle: Bool = true,
        hidesWhenEmpty: Bool = true,
        cardCornerRadius: CGFloat = 16,
        cardSpacing: CGFloat = 12,
        contentInsets: NSDirectionalEdgeInsets = .init(
            top: 8,
            leading: 16,
            bottom: 8,
            trailing: 16
        ),
        maximumNumberOfItems: Int? = nil,
        showsSubtitle: Bool = true,
        allowedCustomDeepLinkSchemes: Set<String> = [],
        placeholderSystemImageName: String = "app.dashed"
    ) {
        self.title = title
        self.showsTitle = showsTitle
        self.hidesWhenEmpty = hidesWhenEmpty
        self.cardCornerRadius = cardCornerRadius
        self.cardSpacing = cardSpacing
        self.contentInsets = contentInsets
        self.maximumNumberOfItems = maximumNumberOfItems
        self.showsSubtitle = showsSubtitle
        self.allowedCustomDeepLinkSchemes = allowedCustomDeepLinkSchemes
        self.placeholderSystemImageName = placeholderSystemImageName
    }

    /// The default App Store-style card configuration.
    public static let `default` = MoreAppsConfiguration()
}
