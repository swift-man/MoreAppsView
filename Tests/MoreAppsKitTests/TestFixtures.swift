//
//  TestFixtures.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation

@testable import MoreAppsKit

enum TestFixtures {
  static let iOSStoreURL = URL(string: "https://apps.apple.com/app/id100")!
  static let tvOSStoreURL = URL(string: "https://apps.apple.com/app/id200")!
  static let deepLinkURL = URL(string: "sample://home")!
  static let backgroundImageURL = URL(
    string: "https://example.com/background.png"
  )!

  static func app(
    id: String = "sample",
    bundleIdentifier: String = "com.example.sample",
    platforms: [MoreAppsPlatform] = [.iOS],
    deepLinkURL: URL? = TestFixtures.deepLinkURL,
    backgroundImageURL: URL? = nil,
    appStoreURL: URL? = nil,
    sortOrder: Int = 0
  ) -> MoreApp {
    MoreApp(
      id: id,
      bundleIdentifier: bundleIdentifier,
      name: id.capitalized,
      subtitle: "Subtitle",
      destinations: platforms.map { platform in
        MoreAppDestination(
          platform: platform,
          appStoreURL: appStoreURL
            ?? (platform == .iOS ? iOSStoreURL : tvOSStoreURL),
          deepLinkURL: deepLinkURL,
          backgroundImageURL: backgroundImageURL
        )
      },
      sortOrder: sortOrder
    )
  }
}

final class AsyncTestSignal: @unchecked Sendable {
  private struct Waiter {
    let targetCount: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private let lock = NSLock()
  private var count = 0
  private var waiters: [Waiter] = []

  func signal() {
    lock.lock()
    count += 1
    let readyWaiters = waiters.filter { $0.targetCount <= count }
    waiters.removeAll { $0.targetCount <= count }
    lock.unlock()

    for waiter in readyWaiters {
      waiter.continuation.resume()
    }
  }

  func wait(forCount targetCount: Int = 1) async {
    precondition(targetCount > 0)

    await withCheckedContinuation { continuation in
      lock.lock()
      guard count < targetCount else {
        lock.unlock()
        continuation.resume()
        return
      }
      waiters.append(
        Waiter(
          targetCount: targetCount,
          continuation: continuation
        )
      )
      lock.unlock()
    }
  }
}

@MainActor
func waitForImageRequestToFinish(
  in view: MoreAppsFocusedBackgroundView
) async {
  if !view.isLoadingImage {
    let started = AsyncTestSignal()
    let previousStartHandler = view.imageRequestDidStart
    view.imageRequestDidStart = {
      previousStartHandler?()
      started.signal()
    }
    await started.wait()
    view.imageRequestDidStart = previousStartHandler
  }

  guard view.isLoadingImage else { return }

  let completion = AsyncTestSignal()
  let previousHandler = view.imageRequestDidFinish
  view.imageRequestDidFinish = {
    previousHandler?()
    completion.signal()
  }
  await completion.wait()
  view.imageRequestDidFinish = previousHandler
}
