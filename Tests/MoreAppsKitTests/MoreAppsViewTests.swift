//
//  MoreAppsViewTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import MoreAppsNetworking
import Testing
import UIKit

@testable import MoreAppsKit
@testable import MoreAppsKitCore

@MainActor
@Suite(.serialized)
struct MoreAppsViewTests {
  #if os(tvOS)
    @Test
    func testTVOSFocusUpdatesTheHostOwnedBackgroundView() async {
      let image = UIImage(systemName: "sparkles")!
      let backgroundView = MoreAppsFocusedBackgroundView(
        maximumPixelSize: 1_920,
        dimmingAlpha: 0.46,
        transitionDuration: 0,
        reduceMotionEnabled: { true },
        transitionPerformer: { _, _, changes in changes() },
        imageProvider: { _, _ in image }
      )
      let view = MoreAppsView()
      view.focusedBackgroundView = backgroundView
      view.setApps([
        TestFixtures.app(
          platforms: [.tvOS],
          backgroundImageURL: TestFixtures.backgroundImageURL
        )
      ])
      await Task.yield()

      view.updateFocusedApp(at: IndexPath(item: 0, section: 0))
      await waitForImageRequestToFinish(in: backgroundView)

      #expect(backgroundView.displayedAppID == "sample")
      #expect(backgroundView.displayedImage === image)

      let replacementBackgroundView = MoreAppsFocusedBackgroundView(
        maximumPixelSize: 1_920,
        dimmingAlpha: 0.46,
        transitionDuration: 0,
        reduceMotionEnabled: { true },
        transitionPerformer: { _, _, changes in changes() },
        imageProvider: { _, _ in image }
      )
      view.focusedBackgroundView = replacementBackgroundView
      await waitForImageRequestToFinish(in: replacementBackgroundView)
      #expect(backgroundView.displayedImage == nil)
      #expect(replacementBackgroundView.displayedAppID == "sample")

      view.focusedBackgroundView = replacementBackgroundView
      #expect(replacementBackgroundView.displayedAppID == "sample")

      view.updateFocusedApp(at: nil)
      await Task.yield()
      #expect(replacementBackgroundView.displayedImage == nil)
    }

    @Test
    func testTVOSFocusUsesTheTVOSDestinationBackground() async {
      let iOSBackgroundURL = URL(
        string: "https://example.com/ios-background.png"
      )!
      let tvOSBackgroundURL = URL(
        string: "https://example.com/tvos-background.png"
      )!
      let image = UIImage(systemName: "sparkles")!
      var requestedURL: URL?
      let backgroundView = MoreAppsFocusedBackgroundView(
        maximumPixelSize: 1_920,
        dimmingAlpha: 0.46,
        transitionDuration: 0,
        reduceMotionEnabled: { true },
        transitionPerformer: { _, _, changes in changes() },
        imageProvider: { url, _ in
          requestedURL = url
          return image
        }
      )
      let app = MoreApp(
        id: "sample",
        bundleIdentifier: "com.example.sample",
        name: "Sample",
        subtitle: "Subtitle",
        destinations: [
          MoreAppDestination(
            platform: .iOS,
            appStoreURL: TestFixtures.iOSStoreURL,
            backgroundImageURL: iOSBackgroundURL
          ),
          MoreAppDestination(
            platform: .tvOS,
            appStoreURL: TestFixtures.tvOSStoreURL,
            backgroundImageURL: tvOSBackgroundURL
          ),
        ],
        sortOrder: 0
      )
      let view = MoreAppsView()
      view.focusedBackgroundView = backgroundView
      view.setApps([app])
      await Task.yield()

      view.updateFocusedApp(at: IndexPath(item: 0, section: 0))
      await waitForImageRequestToFinish(in: backgroundView)

      #expect(backgroundView.displayedAppID == "sample")
      #expect(requestedURL == tvOSBackgroundURL)
    }

    @Test
    func testTVOSNewCatalogSessionRetriesTheSameFocusedArtwork() async {
      let image = UIImage(systemName: "sparkles")!
      var requestCount = 0
      var failureCount = 0
      let backgroundView = MoreAppsFocusedBackgroundView(
        maximumPixelSize: 1_920,
        dimmingAlpha: 0.46,
        transitionDuration: 0,
        reduceMotionEnabled: { true },
        transitionPerformer: { _, _, changes in changes() },
        imageProvider: { _, _ in
          requestCount += 1
          if requestCount == 1 {
            throw MoreAppsImageLoadingError.decodingFailed
          }
          return image
        }
      )
      backgroundView.onImageLoadingFailure = { _, _ in
        failureCount += 1
      }
      let app = TestFixtures.app(
        platforms: [.tvOS],
        backgroundImageURL: TestFixtures.backgroundImageURL
      )
      let view = MoreAppsView()
      view.focusedBackgroundView = backgroundView
      view.setApps([app])
      await Task.yield()
      view.updateFocusedApp(at: IndexPath(item: 0, section: 0))

      await waitForImageRequestToFinish(in: backgroundView)
      #expect(requestCount == 1)
      #expect(failureCount == 1)
      #expect(backgroundView.displayedImage == nil)

      view.setApps([app])
      await waitForImageRequestToFinish(in: backgroundView)

      #expect(requestCount == 2)
      #expect(backgroundView.displayedAppID == app.id)
      #expect(backgroundView.displayedImage === image)
    }

    @Test
    func testTVOSViewDeinitClearsItsHostOwnedBackground() async {
      let image = UIImage(systemName: "sparkles")!
      let backgroundView = MoreAppsFocusedBackgroundView(
        maximumPixelSize: 1_920,
        dimmingAlpha: 0.46,
        transitionDuration: 0,
        reduceMotionEnabled: { true },
        transitionPerformer: { _, _, changes in changes() },
        imageProvider: { _, _ in image }
      )
      var view: MoreAppsView? = MoreAppsView()
      weak let weakView = view
      view?.focusedBackgroundView = backgroundView
      view?.setApps([
        TestFixtures.app(
          platforms: [.tvOS],
          backgroundImageURL: TestFixtures.backgroundImageURL
        )
      ])
      await Task.yield()
      view?.updateFocusedApp(at: IndexPath(item: 0, section: 0))

      await waitForImageRequestToFinish(in: backgroundView)
      #expect(backgroundView.displayedImage === image)

      let didDetach = AsyncTestSignal()
      var detachmentSucceeded = false
      backgroundView.ownerDetachmentDidFinish = { succeeded in
        detachmentSucceeded = succeeded
        didDetach.signal()
      }
      view = nil

      #expect(weakView == nil)
      await didDetach.wait()
      #expect(detachmentSucceeded)
      #expect(backgroundView.displayedAppID == nil)
      #expect(backgroundView.displayedImage == nil)
      #expect(backgroundView.dimmingOpacity == 0)
    }

    @Test
    func testTVOSStaleViewDeinitDoesNotClearReassignedBackground() async {
      let image = UIImage(systemName: "sparkles")!
      let backgroundView = MoreAppsFocusedBackgroundView(
        maximumPixelSize: 1_920,
        dimmingAlpha: 0.46,
        transitionDuration: 0,
        reduceMotionEnabled: { true },
        transitionPerformer: { _, _, changes in changes() },
        imageProvider: { _, _ in image }
      )
      let app = TestFixtures.app(
        platforms: [.tvOS],
        backgroundImageURL: TestFixtures.backgroundImageURL
      )
      var previousView: MoreAppsView? = MoreAppsView()
      previousView?.focusedBackgroundView = backgroundView
      previousView?.setApps([app])
      await Task.yield()
      previousView?.updateFocusedApp(at: IndexPath(item: 0, section: 0))
      await waitForImageRequestToFinish(in: backgroundView)

      let currentView = MoreAppsView()
      currentView.setApps([app])
      await Task.yield()
      currentView.updateFocusedApp(at: IndexPath(item: 0, section: 0))

      let staleDetachmentAttempted = AsyncTestSignal()
      var staleDetachmentSucceeded = true
      backgroundView.ownerDetachmentDidFinish = { succeeded in
        staleDetachmentSucceeded = succeeded
        staleDetachmentAttempted.signal()
      }

      previousView = nil
      currentView.focusedBackgroundView = backgroundView
      await staleDetachmentAttempted.wait()

      #expect(!staleDetachmentSucceeded)
      #expect(backgroundView.displayedAppID == app.id)
      #expect(backgroundView.displayedImage === image)
    }
  #endif

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
      imageLoader: MoreAppsImageLoader.shared
    )

    #expect(cell.isAccessibilityElement)
    #expect(cell.accessibilityTraits.contains(.button))
    #expect(cell.accessibilityLabel?.contains("Sample") == true)
    #expect(cell.accessibilityLabel?.contains("Subtitle") == true)
    #expect(cell.accessibilityHint?.isEmpty == false)
  }

  @Test
  func testPlatformPresentationCardDescribesItsPlatformBehavior() {
    let cell = MoreAppCardCell(frame: .zero)
    cell.configure(
      with: TestFixtures.app(),
      configuration: .init(selectionBehavior: .platformPresentation),
      imageLoader: MoreAppsImageLoader.shared
    )

    #if os(iOS)
      let actionKey: String.LocalizationValue =
        "more_apps_open_or_view_action"
      let hintKey: String.LocalizationValue =
        "more_apps_open_or_view_hint"
    #else
      let actionKey: String.LocalizationValue = "more_apps_open_action"
      let hintKey: String.LocalizationValue = "more_apps_open_hint"
    #endif
    let expectedAction = String(localized: actionKey, bundle: .module)
    let expectedHint = String(localized: hintKey, bundle: .module)

    #expect(cell.accessibilityLabel?.contains(expectedAction) == true)
    #expect(cell.accessibilityHint == expectedHint)
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
  func testCardDeinitCancelsImageTransport() async {
    defer {
      CellImageMockURLProtocol.onStartLoading = nil
      CellImageMockURLProtocol.onStopLoading = nil
    }
    let starts = CellImageLifecycleCounter()
    let stops = CellImageLifecycleCounter()
    CellImageMockURLProtocol.onStartLoading = { starts.increment() }
    CellImageMockURLProtocol.onStopLoading = { stops.increment() }

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [CellImageMockURLProtocol.self]
    let imageLoader = MoreAppsImageLoader(
      sessionConfiguration: sessionConfiguration
    )
    let app = MoreApp(
      id: "image",
      bundleIdentifier: "com.example.image",
      name: "Image",
      iconURL: URL(string: "https://example.com/icon.png"),
      destinations: [],
      sortOrder: 0
    )
    var cell: MoreAppCardCell? = MoreAppCardCell(frame: .zero)
    weak let weakCell = cell
    cell?.configure(
      with: app,
      configuration: .default,
      imageLoader: imageLoader
    )

    await starts.waitUntilIncremented()
    #expect(starts.count == 1)

    cell = nil

    #expect(weakCell == nil)
    await stops.waitUntilIncremented()
    #expect(stops.count == 1)
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
    let eventDelivered = AsyncTestSignal()
    view.onEvent = {
      events.append($0)
      eventDelivered.signal()
    }
    await eventDelivered.wait()

    #expect(events == [.impression(appID: "sample")])
  }

  @Test
  func testEventDeliveryTaskDoesNotKeepViewAlive() async {
    var view: MoreAppsView? = MoreAppsView()
    weak let weakView = view
    let app = TestFixtures.app(platforms: [.current])
    view?.setApps([app])
    await Task.yield()

    weak let collectionView = view?.subviews
      .compactMap { $0 as? UICollectionView }
      .first
    var deliveredEventCount = 0
    var shouldRequeue = true
    let eventDeliveryStarted = AsyncTestSignal()
    view?.onEvent = { [weak capturedView = view] _ in
      deliveredEventCount += 1
      eventDeliveryStarted.signal()
      guard shouldRequeue,
        let capturedView,
        let collectionView
      else {
        return
      }

      capturedView.setApps([app])
      capturedView.collectionView(
        collectionView,
        willDisplay: UICollectionViewCell(),
        forItemAt: IndexPath(item: 0, section: 0)
      )
    }

    guard let collectionView else {
      Issue.record("Expected the More Apps collection view")
      return
    }
    view?.collectionView(
      collectionView,
      willDisplay: UICollectionViewCell(),
      forItemAt: IndexPath(item: 0, section: 0)
    )
    await eventDeliveryStarted.wait()
    guard deliveredEventCount > 0 else {
      Issue.record("Expected event delivery to begin")
      return
    }

    view = nil
    let releasedWhenExternallyUnreferenced = weakView == nil
    shouldRequeue = false

    #expect(releasedWhenExternallyUnreferenced)
    #expect(weakView == nil)
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

private final class CellImageLifecycleCounter {
  private let lock = NSLock()
  private let didIncrement = AsyncTestSignal()
  private var value = 0

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func increment() {
    lock.lock()
    value += 1
    lock.unlock()
    didIncrement.signal()
  }

  func waitUntilIncremented() async {
    await didIncrement.wait()
  }
}

private final class CellImageMockURLProtocol: URLProtocol {
  static var onStartLoading: (() -> Void)?
  static var onStopLoading: (() -> Void)?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    Self.onStartLoading?()
  }

  override func stopLoading() {
    Self.onStopLoading?()
  }
}
