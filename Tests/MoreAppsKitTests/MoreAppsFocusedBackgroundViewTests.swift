//
//  MoreAppsFocusedBackgroundViewTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 9/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Testing
import UIKit

@testable import MoreAppsKit

@MainActor
@Suite
struct MoreAppsFocusedBackgroundViewTests {
  @Test
  func testFocusedArtworkLoadsAtTheConfiguredPixelSize() async {
    let image = UIImage(systemName: "sparkles")!
    var requestedPixelSize: Int?
    let view = makeView { _, maximumPixelSize in
      requestedPixelSize = maximumPixelSize
      return image
    }

    view.display(
      appID: "andromeda",
      imageURL: TestFixtures.backgroundImageURL,
      animated: false
    )
    await waitUntilImageRequestFinishes(in: view)

    #expect(view.displayedAppID == "andromeda")
    #expect(view.displayedImage === image)
    #expect(requestedPixelSize == 1_920)
    #expect(!view.isUserInteractionEnabled)
    #expect(view.accessibilityElementsHidden)
  }

  @Test
  func testFocusWithoutArtworkClearsThePreviousImage() async {
    let image = UIImage(systemName: "sparkles")!
    let view = makeView { _, _ in image }
    view.display(
      appID: "andromeda",
      imageURL: TestFixtures.backgroundImageURL,
      animated: false
    )
    await waitUntilImageRequestFinishes(in: view)
    #expect(abs(view.dimmingOpacity - 0.46) < 0.001)

    view.dimmingAlpha = 0.7
    #expect(abs(view.dimmingOpacity - 0.7) < 0.001)

    view.display(appID: "other", imageURL: nil, animated: false)

    #expect(view.displayedAppID == nil)
    #expect(view.displayedImage == nil)
    #expect(view.dimmingOpacity == 0)
  }

  @Test
  func testStaleImageCannotOverwriteTheLatestFocus() async {
    let firstURL = URL(string: "https://example.com/first.png")!
    let secondURL = URL(string: "https://example.com/second.png")!
    let firstImage = UIImage(systemName: "1.circle")!
    let secondImage = UIImage(systemName: "2.circle")!
    let firstImageGate = BackgroundImageGate()
    let view = makeView { url, _ in
      if url == firstURL {
        return await firstImageGate.image(afterRelease: firstImage)
      }
      return secondImage
    }

    view.display(appID: "first", imageURL: firstURL, animated: false)
    await firstImageGate.waitUntilStarted()
    view.display(appID: "second", imageURL: secondURL, animated: false)
    await waitUntilImageRequestFinishes(in: view)
    firstImageGate.release()
    await firstImageGate.waitUntilReturned()

    #expect(view.displayedAppID == "second")
    #expect(view.displayedImage === secondImage)
  }

  @Test
  func testReturningToTheSameFocusRejectsTheFirstStaleCompletion() async {
    let firstURL = URL(string: "https://example.com/first.png")!
    let middleURL = URL(string: "https://example.com/middle.png")!
    let staleImage = UIImage(systemName: "1.circle")!
    let latestImage = UIImage(systemName: "3.circle")!
    let firstImageGate = BackgroundImageGate()
    var firstURLRequestCount = 0
    let view = makeView { url, _ in
      if url == firstURL {
        firstURLRequestCount += 1
        if firstURLRequestCount == 1 {
          return await firstImageGate.image(afterRelease: staleImage)
        }
        return latestImage
      }
      return UIImage(systemName: "2.circle")!
    }

    view.display(appID: "first", imageURL: firstURL, animated: false)
    await firstImageGate.waitUntilStarted()
    view.display(appID: "middle", imageURL: middleURL, animated: false)
    view.display(appID: "first", imageURL: firstURL, animated: false)
    await waitUntilImageRequestFinishes(in: view)

    #expect(view.displayedAppID == "first")
    #expect(view.displayedImage === latestImage)

    firstImageGate.release()
    await firstImageGate.waitUntilReturned()
    await Task.yield()
    await Task.yield()

    #expect(view.displayedAppID == "first")
    #expect(view.displayedImage === latestImage)
  }

  @Test
  func testLoadFailureLeavesTheBackgroundEmpty() async {
    let view = makeView { _, _ in
      throw MoreAppsImageLoadingError.decodingFailed
    }

    view.display(
      appID: "andromeda",
      imageURL: TestFixtures.backgroundImageURL,
      animated: false
    )
    await waitUntilImageRequestFinishes(in: view)

    #expect(view.displayedAppID == nil)
    #expect(view.displayedImage == nil)
  }

  @Test
  func testFailedArtworkRetriesAfterFocusLeavesAndReturns() async {
    let image = UIImage(systemName: "sparkles")!
    var requestCount = 0
    let view = makeView { _, _ in
      requestCount += 1
      if requestCount == 1 {
        throw MoreAppsImageLoadingError.decodingFailed
      }
      return image
    }

    view.display(
      appID: "andromeda",
      imageURL: TestFixtures.backgroundImageURL,
      animated: false
    )
    await waitUntilImageRequestFinishes(in: view)
    #expect(view.displayedImage == nil)

    view.display(appID: nil, imageURL: nil, animated: false)
    view.display(
      appID: "andromeda",
      imageURL: TestFixtures.backgroundImageURL,
      animated: false
    )
    await waitUntilImageRequestFinishes(in: view)

    #expect(requestCount == 2)
    #expect(view.displayedImage === image)
  }

  @Test
  func testDimmingAlphaIsClamped() {
    let view = makeView { _, _ in UIImage() }

    view.dimmingAlpha = 2
    #expect(view.dimmingAlpha == 1)

    view.dimmingAlpha = -1
    #expect(view.dimmingAlpha == 0)
  }

  @Test
  func testDuplicateDisplayRequestDoesNotRestartLoading() async {
    var requestCount = 0
    let view = makeView { _, _ in
      requestCount += 1
      await Task.yield()
      return UIImage(systemName: "sparkles")!
    }

    view.display(
      appID: "andromeda",
      imageURL: TestFixtures.backgroundImageURL,
      animated: false
    )
    view.display(
      appID: "andromeda",
      imageURL: TestFixtures.backgroundImageURL,
      animated: false
    )
    await waitUntilImageRequestFinishes(in: view)

    #expect(requestCount == 1)
  }

  @Test
  func testMaximumPixelSizeIsClampedToOne() async {
    var requestedPixelSize: Int?
    let view = MoreAppsFocusedBackgroundView(
      maximumPixelSize: 0,
      dimmingAlpha: 0.46,
      transitionDuration: 0,
      reduceMotionEnabled: { true },
      transitionPerformer: { _, _, changes in changes() },
      imageProvider: { _, maximumPixelSize in
        requestedPixelSize = maximumPixelSize
        return UIImage(systemName: "sparkles")!
      }
    )

    view.display(
      appID: "andromeda",
      imageURL: TestFixtures.backgroundImageURL,
      animated: false
    )
    await waitUntilImageRequestFinishes(in: view)

    #expect(requestedPixelSize == 1)
  }

  @Test
  func testMaximumPixelSizeIsClampedToFourK() async {
    var requestedPixelSize: Int?
    let view = MoreAppsFocusedBackgroundView(
      maximumPixelSize: .max,
      dimmingAlpha: 0.46,
      transitionDuration: 0,
      reduceMotionEnabled: { true },
      transitionPerformer: { _, _, changes in changes() },
      imageProvider: { _, maximumPixelSize in
        requestedPixelSize = maximumPixelSize
        return UIImage(systemName: "sparkles")!
      }
    )

    view.display(
      appID: "andromeda",
      imageURL: TestFixtures.backgroundImageURL,
      animated: false
    )
    await waitUntilImageRequestFinishes(in: view)

    #expect(requestedPixelSize == 4_096)
  }

  @Test
  func testReduceMotionSkipsCrossfade() async {
    var transitionCount = 0
    let view = MoreAppsFocusedBackgroundView(
      maximumPixelSize: 1_920,
      dimmingAlpha: 0.46,
      transitionDuration: 0.35,
      reduceMotionEnabled: { true },
      transitionPerformer: { _, _, changes in
        transitionCount += 1
        changes()
      },
      imageProvider: { _, _ in UIImage(systemName: "sparkles")! }
    )

    view.display(
      appID: "andromeda",
      imageURL: TestFixtures.backgroundImageURL
    )
    await waitUntilImageRequestFinishes(in: view)

    #expect(transitionCount == 0)
  }

  @Test
  func testNormalMotionUsesCrossfade() async {
    var transitionCount = 0
    let view = MoreAppsFocusedBackgroundView(
      maximumPixelSize: 1_920,
      dimmingAlpha: 0.46,
      transitionDuration: 0.35,
      reduceMotionEnabled: { false },
      transitionPerformer: { _, _, changes in
        transitionCount += 1
        changes()
      },
      imageProvider: { _, _ in UIImage(systemName: "sparkles")! }
    )

    view.display(
      appID: "andromeda",
      imageURL: TestFixtures.backgroundImageURL
    )
    await waitUntilImageRequestFinishes(in: view)

    #expect(transitionCount == 1)
  }

  private func makeView(
    imageProvider: @escaping MoreAppsFocusedBackgroundView.ImageProvider
  ) -> MoreAppsFocusedBackgroundView {
    MoreAppsFocusedBackgroundView(
      maximumPixelSize: 1_920,
      dimmingAlpha: 0.46,
      transitionDuration: 0.35,
      reduceMotionEnabled: { true },
      transitionPerformer: { _, _, changes in changes() },
      imageProvider: imageProvider
    )
  }

  private func waitUntilImageRequestFinishes(
    in view: MoreAppsFocusedBackgroundView
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    while view.isLoadingImage, clock.now < deadline {
      await Task.yield()
    }
    #expect(!view.isLoadingImage)
  }
}

@MainActor
private final class BackgroundImageGate {
  private var hasStarted = false
  private var hasReturned = false
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func image(afterRelease image: UIImage) async -> UIImage {
    hasStarted = true
    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
    hasReturned = true
    return image
  }

  func waitUntilStarted() async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    while !hasStarted, clock.now < deadline {
      await Task.yield()
    }
    #expect(hasStarted)
  }

  func release() {
    let continuation = releaseContinuation
    releaseContinuation = nil
    continuation?.resume()
  }

  func waitUntilReturned() async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    while !hasReturned, clock.now < deadline {
      await Task.yield()
    }
    #expect(hasReturned)
  }
}
