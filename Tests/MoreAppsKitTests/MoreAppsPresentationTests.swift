//
//  MoreAppsPresentationTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/23/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Testing
#if os(tvOS)
  import UIKit
#endif

@testable import MoreAppsKit

@MainActor
@Suite
struct MoreAppsPresentationTests {
  @Test
  func testRelayUsesTheLatestPresenter() async {
    let firstPresenter = OutcomePresenter(outcome: .appStoreRequested)
    let secondPresenter = OutcomePresenter(outcome: .dismissed)
    let relay = MoreAppsPresentationRelay(presenter: firstPresenter)
    let request = makeRequest()

    let firstOutcome = await relay.present(request)
    relay.presenter = secondPresenter
    let secondOutcome = await relay.present(request)

    #expect(firstOutcome == .appStoreRequested)
    #expect(secondOutcome == .dismissed)
    #expect(firstPresenter.presentationCount == 1)
    #expect(secondPresenter.presentationCount == 1)
  }

  @Test
  func testRelayWithoutAPresenterFailsSafely() async {
    let relay = MoreAppsPresentationRelay()

    let outcome = await relay.present(makeRequest())

    #expect(outcome == .failed)
  }

  #if os(tvOS)
    @Test
    func testTVOSStoreActionFinishesExactlyOnceDuringDisappearance() {
      var outcomes: [MoreAppsPresentationOutcome] = []
      let viewController = MoreAppDetailViewController(
        app: TestFixtures.app(platforms: [.tvOS]),
        imageLoader: .shared
      ) { outcome in
        outcomes.append(outcome)
      }
      viewController.loadViewIfNeeded()

      viewController.storeButtonPressed()
      viewController.viewDidDisappear(false)
      viewController.viewDidDisappear(false)

      #expect(outcomes == [.appStoreRequested])
    }

    @Test
    func testTVOSDetailFinishesOnlyOnceWhenItDisappearsRepeatedly() {
      var outcomes: [MoreAppsPresentationOutcome] = []
      let viewController = MoreAppDetailViewController(
        app: TestFixtures.app(platforms: [.tvOS]),
        imageLoader: .shared
      ) { outcome in
        outcomes.append(outcome)
      }
      viewController.loadViewIfNeeded()

      viewController.viewDidDisappear(false)
      viewController.viewDidDisappear(false)

      #expect(outcomes == [.dismissed])
    }

  #endif

  private func makeRequest() -> MoreAppsPresentationRequest {
    let app = TestFixtures.app()
    let destination = app.destination(for: .iOS)!
    return MoreAppsPresentationRequest(
      app: app,
      destination: destination,
      appStoreIdentifier: "100"
    )
  }
}

@MainActor
private final class OutcomePresenter: MoreAppsPresenting {
  private let outcome: MoreAppsPresentationOutcome
  private(set) var presentationCount = 0

  init(outcome: MoreAppsPresentationOutcome) {
    self.outcome = outcome
  }

  func present(
    _ request: MoreAppsPresentationRequest
  ) async -> MoreAppsPresentationOutcome {
    presentationCount += 1
    return outcome
  }
}
