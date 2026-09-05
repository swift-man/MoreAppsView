//
//  TestFixtures.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation
import Testing

@testable import MoreAppsKit
@testable import MoreAppsKitCore

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
  private enum WaitResult: Sendable {
    case signaled
    case timedOut
    case cancelled
  }

  private struct Waiter {
    let id: UUID
    let targetCount: Int
    let continuation: CheckedContinuation<Void, any Error>
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
      waiter.continuation.resume(returning: ())
    }
  }

  func wait(
    forCount targetCount: Int = 1,
    timeout: Duration = .seconds(10)
  ) async {
    precondition(targetCount > 0)

    let result = await withTaskGroup(of: WaitResult.self) { group in
      group.addTask { [self] in
        do {
          try await waitUntilCount(targetCount)
          return .signaled
        } catch is CancellationError {
          return .cancelled
        } catch {
          return .cancelled
        }
      }
      group.addTask {
        do {
          try await Task.sleep(for: timeout)
          return .timedOut
        } catch {
          return .cancelled
        }
      }

      let firstResult = await group.next() ?? .cancelled
      group.cancelAll()
      return firstResult
    }

    if case .timedOut = result {
      Issue.record(
        "Timed out waiting for an async test signal to reach count \(targetCount)."
      )
    }
  }

  private func waitUntilCount(_ targetCount: Int) async throws {
    let waiterID = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        lock.lock()
        if count >= targetCount {
          lock.unlock()
          continuation.resume(returning: ())
          return
        }
        if Task.isCancelled {
          lock.unlock()
          continuation.resume(throwing: CancellationError())
          return
        }
        waiters.append(
          Waiter(
            id: waiterID,
            targetCount: targetCount,
            continuation: continuation
          )
        )
        lock.unlock()
      }
    } onCancel: {
      cancelWaiter(id: waiterID)
    }
  }

  private func cancelWaiter(id: UUID) {
    lock.lock()
    guard let index = waiters.firstIndex(where: { $0.id == id }) else {
      lock.unlock()
      return
    }
    let continuation = waiters.remove(at: index).continuation
    lock.unlock()

    continuation.resume(throwing: CancellationError())
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
