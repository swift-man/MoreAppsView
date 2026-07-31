import Testing
import UIKit
@testable import MoreAppsKit

@MainActor
@Suite
struct MoreAppsViewTests {
    @Test
    func testHidesWhenEmptyAndShowsWhenDisplayable() async {
        let view = MoreAppsView(
            configuration: .init(hidesWhenEmpty: true)
        )

        #expect(view.isHidden)

        view.setApps([TestFixtures.app(platforms: [.iOS])])
        await Task.yield()

        #if os(iOS)
        #expect(!view.isHidden)
        #elseif os(tvOS)
        #expect(view.isHidden)
        #endif
    }

    @Test
    func testCanRemainVisibleWhenEmpty() {
        let view = MoreAppsView(
            configuration: .init(hidesWhenEmpty: false)
        )

        #expect(!view.isHidden)
    }

    @Test
    func testConfigurationChangesAreAppliedAfterCreation() {
        let view = MoreAppsView(
            configuration: .init(hidesWhenEmpty: true)
        )

        #expect(view.isHidden)

        view.update(
            configuration: .init(
                showsTitle: false,
                hidesWhenEmpty: false,
                cardSpacing: 24,
                maximumNumberOfItems: 1,
                showsSubtitle: false
            )
        )

        #expect(!view.isHidden)
    }

    @Test
    func testVisibleViewHidesAfterCatalogBecomesEmpty() async {
        let view = MoreAppsView(
            configuration: .init(hidesWhenEmpty: true)
        )

        view.setApps([TestFixtures.app(platforms: [.current])])
        await Task.yield()
        #expect(!view.isHidden)

        view.setApps([])
        await Task.yield()
        #expect(view.isHidden)
    }

    @Test
    func testProviderLoadDisplaysCurrentPlatformCatalog() async {
        let view = MoreAppsView(
            configuration: .init(hidesWhenEmpty: true)
        )
        let provider = StaticMoreAppsProvider(
            apps: [TestFixtures.app(platforms: [.current])]
        )

        await view.load(using: provider)
        await Task.yield()

        #expect(!view.isHidden)
    }

    @Test
    func testReloadReusesProviderAndIsANoOpBeforeInitialLoad() async {
        let view = MoreAppsView(
            configuration: .init(hidesWhenEmpty: true)
        )
        let provider = CountingProvider(
            apps: [TestFixtures.app(platforms: [.current])]
        )

        await view.reload()
        #expect(view.isHidden)

        await view.load(using: provider)
        await view.reload()
        let fetchCount = await provider.count

        #expect(fetchCount == 2)
        #expect(!view.isHidden)
    }

    @Test
    func testCardExposesCombinedAccessibilityAction() {
        let cell = MoreAppCardCell(frame: .zero)
        cell.configure(
            with: TestFixtures.app(),
            configuration: .default,
            imageLoader: .shared
        )

        #expect(cell.isAccessibilityElement)
        #expect(cell.accessibilityTraits.contains(.button))
        #expect(cell.accessibilityLabel?.contains("Sample") == true)
        #expect(cell.accessibilityLabel?.contains("Subtitle") == true)
        #expect(cell.accessibilityHint?.isEmpty == false)
    }

    @Test
    func testCardReuseClearsHighlightPresentation() {
        let cell = MoreAppCardCell(frame: .zero)
        cell.isHighlighted = true

        cell.prepareForReuse()

        #expect(cell.contentView.alpha == 1)
        #expect(cell.contentView.transform == .identity)
    }

    @Test
    func testEventsWaitForAHandlerBeforeDelivery() async {
        let view = MoreAppsView()
        view.setApps([TestFixtures.app(platforms: [.current])])
        await Task.yield()

        let collectionView = view.subviews
            .compactMap { $0 as? UICollectionView }
            .first!
        view.collectionView(
            collectionView,
            willDisplay: UICollectionViewCell(),
            forItemAt: IndexPath(item: 0, section: 0)
        )
        await Task.yield()

        var events: [MoreAppsEvent] = []
        view.onEvent = { events.append($0) }
        for _ in 0..<5 {
            await Task.yield()
        }

        #expect(events == [.impression(appID: "sample")])
    }
}

private actor CountingProvider: MoreAppsProviding {
    private let apps: [MoreApp]
    private(set) var count = 0

    init(apps: [MoreApp]) {
        self.apps = apps
    }

    func fetchApps() async throws -> [MoreApp] {
        count += 1
        return apps
    }
}
