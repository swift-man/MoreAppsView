//
//  MoreAppsPresentationTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/23/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Testing

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

  #if os(iOS)
    @Test
    func testOverlayCancellationRequestsDismissalOnlyOnce() {
      var state = MoreAppsOverlayCancellationState()
      state.beginPresentation()

      let activeOverlapOutcome = state.overlappingPresentationOutcome
      let firstRequestWasAccepted = state.requestDismissal()
      let secondRequestWasAccepted = state.requestDismissal()
      let dismissingOverlapOutcome = state.overlappingPresentationOutcome

      #expect(activeOverlapOutcome == .dismissed)
      #expect(firstRequestWasAccepted)
      #expect(!secondRequestWasAccepted)
      #expect(dismissingOverlapOutcome == .dismissed)
    }

    @Test
    func testOverlayFailureAfterCancellationFinishesAsDismissed() {
      var state = MoreAppsOverlayCancellationState()
      state.beginPresentation()
      _ = state.requestDismissal()

      let outcome = state.finish(with: .failed)
      let duplicateOutcome = state.finish(with: .dismissed)

      #expect(outcome == .dismissed)
      #expect(duplicateOutcome == nil)
      #expect(!state.isDismissalRequested)
    }

    @Test
    func testOverlayFailureWithoutCancellationRemainsFailure() {
      var state = MoreAppsOverlayCancellationState()
      state.beginPresentation()

      let outcome = state.finish(with: .failed)
      let duplicateOutcome = state.finish(with: .dismissed)

      #expect(outcome == .failed)
      #expect(duplicateOutcome == nil)
      #expect(!state.isDismissalRequested)
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
