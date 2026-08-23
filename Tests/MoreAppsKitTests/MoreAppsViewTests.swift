//
//  MoreAppsViewTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

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

    let clock = ContinuousClock()
    let startDeadline = clock.now.advanced(by: .seconds(1))
    while starts.count == 0, clock.now < startDeadline {
      await Task.yield()
    }
    #expect(starts.count == 1)

    cell = nil

    #expect(weakCell == nil)
    let stopDeadline = clock.now.advanced(by: .seconds(1))
    while stops.count == 0, clock.now < stopDeadline {
      await Task.yield()
    }
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
    view.onEvent = { events.append($0) }
    for _ in 0..<5 {
      await Task.yield()
    }

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
    view?.onEvent = { [weak capturedView = view] _ in
      deliveredEventCount += 1
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
    for _ in 0..<20 where deliveredEventCount == 0 {
      await Task.yield()
    }
    guard deliveredEventCount > 0 else {
      Issue.record("Expected event delivery to begin")
      return
    }

    view = nil
    let releasedWhenExternallyUnreferenced = weakView == nil
    shouldRequeue = false
    for _ in 0..<20 where weakView != nil {
      await Task.yield()
    }

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
