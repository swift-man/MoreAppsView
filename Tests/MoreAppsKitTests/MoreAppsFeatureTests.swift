//
//  MoreAppsFeatureTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Testing

@testable import MoreAppsKit

@MainActor
@Suite
struct MoreAppsFeatureTests {
  @Test
  func testFocusTracksOnlyAppsInTheFilteredCatalog() async {
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.apps = [TestFixtures.app()]
    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    }

    await store.send(.focusChanged(appID: "sample")) {
      $0.focusedAppID = "sample"
    }
    await store.send(.focusChanged(appID: "missing")) {
      $0.focusedAppID = nil
    }
  }

  @Test
  func testFilteringOutTheFocusedAppClearsFocus() async {
    let first = TestFixtures.app(id: "first", sortOrder: 0)
    let second = TestFixtures.app(id: "second", sortOrder: 1)
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.sourceApps = [first, second]
    state.apps = [first, second]
    state.focusedAppID = second.id
    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(.setMaximumNumberOfItems(1)) {
      $0.maximumNumberOfItems = 1
      $0.apps = [first]
      $0.focusedAppID = nil
    }
  }

  @Test
  func testNewCatalogClearsAFocusedAppThatWasRemoved() async {
    let app = TestFixtures.app()
    let replacement = TestFixtures.app(id: "replacement")
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.sourceApps = [app]
    state.apps = [app]
    state.focusedAppID = app.id
    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(.setApps([replacement])) {
      $0.sourceApps = [replacement]
      $0.apps = [replacement]
      $0.dataSessionID = 1
      $0.focusedAppID = nil
    }
  }

  @Test
  func testNewCatalogKeepsFocusForTheSameStableAppID() async {
    let app = TestFixtures.app()
    let updatedApp = TestFixtures.app(
      backgroundImageURL: TestFixtures.backgroundImageURL
    )
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.sourceApps = [app]
    state.apps = [app]
    state.focusedAppID = app.id
    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(.setApps([updatedApp])) {
      $0.sourceApps = [updatedApp]
      $0.apps = [updatedApp]
      $0.dataSessionID = 1
    }
  }

  @Test
  func testDeepLinkSuccessDoesNotOpenAppStore() async {
    let recorder = OpenRecorder(results: [true])
    let store = makeStore(
      app: TestFixtures.app(),
      recorder: recorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.openingAppIDs = ["sample"]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .app
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedApp(appID: "sample"))
      )
    }

    #expect(recorder.openedURLs == [TestFixtures.deepLinkURL])
  }

  @Test
  func testDeepLinkFailureFallsBackToAppStore() async {
    let recorder = OpenRecorder(results: [false, true])
    let store = makeStore(
      app: TestFixtures.app(),
      recorder: recorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.openingAppIDs = ["sample"]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .appStore
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedAppStore(appID: "sample"))
      )
    }

    #expect(
      recorder.openedURLs
        == [TestFixtures.deepLinkURL, TestFixtures.iOSStoreURL]
    )
  }

  @Test
  func testMissingDeepLinkOpensAppStoreImmediately() async {
    let recorder = OpenRecorder(results: [true])
    let store = makeStore(
      app: TestFixtures.app(deepLinkURL: nil),
      recorder: recorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.openingAppIDs = ["sample"]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .appStore
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedAppStore(appID: "sample"))
      )
    }

    #expect(recorder.openedURLs == [TestFixtures.iOSStoreURL])
  }

  @Test
  func testIOSPlatformPresentationOpensInstalledAppBeforePresenting() async {
    let openRecorder = OpenRecorder(results: [true])
    let presentationRecorder = PresentationRecorder(outcomes: [.dismissed])
    let store = makePlatformStore(
      app: TestFixtures.app(),
      platform: .iOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.presentingAppID = "sample"
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .app
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.presentingAppID = nil
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedApp(appID: "sample"))
      )
    }

    #expect(openRecorder.openedURLs == [TestFixtures.deepLinkURL])
    #expect(presentationRecorder.requests.isEmpty)
  }

  @Test
  func testIOSPlatformPresentationOpensDeepLinkWithoutAValidStoreURL() async {
    let openRecorder = OpenRecorder(results: [true])
    let presentationRecorder = PresentationRecorder(outcomes: [.dismissed])
    let store = makePlatformStore(
      app: TestFixtures.app(
        appStoreURL: URL(string: "https://example.com/app/id100")!
      ),
      platform: .iOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.presentingAppID = "sample"
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .app
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.presentingAppID = nil
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedApp(appID: "sample"))
      )
    }

    #expect(openRecorder.openedURLs == [TestFixtures.deepLinkURL])
    #expect(presentationRecorder.requests.isEmpty)
  }

  @Test
  func testIOSDeepLinkFailurePresentsStoreOverlay() async {
    let openRecorder = OpenRecorder(results: [false])
    let presentationRecorder = PresentationRecorder(outcomes: [.dismissed])
    let store = makePlatformStore(
      app: TestFixtures.app(
        backgroundImageURL: TestFixtures.backgroundImageURL
      ),
      platform: .iOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.presentingAppID = "sample"
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .presentationFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .dismissed
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.presentingAppID = nil
    }

    #expect(openRecorder.openedURLs == [TestFixtures.deepLinkURL])
    #expect(presentationRecorder.requests.count == 1)
    #expect(
      presentationRecorder.requests.first?.appStoreIdentifier == "100"
    )
    #expect(
      presentationRecorder.requests.first?.destination.backgroundImageURL
        == TestFixtures.backgroundImageURL
    )
  }

  @Test
  func testIOSDismissedPresentationDoesNotFallbackToAppStoreURL() async {
    let openRecorder = OpenRecorder(results: [])
    let presentationRecorder = PresentationRecorder(outcomes: [.dismissed])
    let store = makePlatformStore(
      app: TestFixtures.app(deepLinkURL: nil),
      platform: .iOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.presentingAppID = "sample"
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .presentationFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .dismissed
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.presentingAppID = nil
    }

    #expect(openRecorder.openedURLs.isEmpty)
    #expect(presentationRecorder.requests.count == 1)
  }

  @Test
  func testTVOSPlatformPresentationImmediatelyOpensInstalledApp() async {
    let openRecorder = OpenRecorder(results: [true])
    let presentationRecorder = PresentationRecorder(outcomes: [])
    let store = makePlatformStore(
      app: TestFixtures.app(platforms: [.tvOS]),
      platform: .tvOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.openingAppIDs = ["sample"]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .app
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedApp(appID: "sample"))
      )
    }

    #expect(openRecorder.openedURLs == [TestFixtures.deepLinkURL])
    #expect(presentationRecorder.requests.isEmpty)
  }

  @Test
  func testTVOSPlatformPresentationImmediatelyFallsBackToAppStore() async {
    let openRecorder = OpenRecorder(results: [false, true])
    let presentationRecorder = PresentationRecorder(outcomes: [])
    let store = makePlatformStore(
      app: TestFixtures.app(platforms: [.tvOS]),
      platform: .tvOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.openingAppIDs = ["sample"]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .appStore
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedAppStore(appID: "sample"))
      )
    }

    #expect(
      openRecorder.openedURLs
        == [TestFixtures.deepLinkURL, TestFixtures.tvOSStoreURL]
    )
    #expect(presentationRecorder.requests.isEmpty)
  }

  @Test
  func testTVOSPlatformPresentationWithoutDeepLinkOpensAppStore() async {
    let openRecorder = OpenRecorder(results: [true])
    let presentationRecorder = PresentationRecorder(outcomes: [])
    let store = makePlatformStore(
      app: TestFixtures.app(platforms: [.tvOS], deepLinkURL: nil),
      platform: .tvOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.openingAppIDs = ["sample"]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .appStore
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedAppStore(appID: "sample"))
      )
    }

    #expect(openRecorder.openedURLs == [TestFixtures.tvOSStoreURL])
    #expect(presentationRecorder.requests.isEmpty)
  }

  @Test
  func testTVOSPlatformPresentationReportsFailureWhenNoDestinationOpens() async {
    let openRecorder = OpenRecorder(results: [false, false])
    let presentationRecorder = PresentationRecorder(outcomes: [])
    let store = makePlatformStore(
      app: TestFixtures.app(platforms: [.tvOS]),
      platform: .tvOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.openingAppIDs = ["sample"]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .failed
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .failedToOpen(appID: "sample"))
      )
    }

    #expect(
      openRecorder.openedURLs
        == [TestFixtures.deepLinkURL, TestFixtures.tvOSStoreURL]
    )
    #expect(presentationRecorder.requests.isEmpty)
  }

  @Test
  func testDismissedPlatformPresentationDoesNotOpenAURL() async {
    let openRecorder = OpenRecorder(results: [])
    let presentationRecorder = PresentationRecorder(outcomes: [.dismissed])
    let store = makePlatformStore(
      app: TestFixtures.app(deepLinkURL: nil),
      platform: .iOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.presentingAppID = "sample"
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .presentationFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .dismissed
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.presentingAppID = nil
    }

    #expect(openRecorder.openedURLs.isEmpty)
    #expect(presentationRecorder.requests.count == 1)
  }

  @Test
  func testIOSAppStoreRequestOpensAppStoreURL() async {
    let openRecorder = OpenRecorder(results: [true])
    let presentationRecorder = PresentationRecorder(
      outcomes: [.appStoreRequested]
    )
    let store = makePlatformStore(
      app: TestFixtures.app(deepLinkURL: nil),
      platform: .iOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.presentingAppID = "sample"
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .presentationFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .appStoreRequested
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.presentingAppID = nil
      $0.openingAppIDs = ["sample"]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .appStore
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedAppStore(appID: "sample"))
      )
    }

    #expect(openRecorder.openedURLs == [TestFixtures.iOSStoreURL])
    #expect(presentationRecorder.requests.count == 1)
  }

  @Test
  func testIOSPresentationFailureFallsBackToAppStoreURL() async {
    let openRecorder = OpenRecorder(results: [true])
    let presentationRecorder = PresentationRecorder(outcomes: [.failed])
    let store = makePlatformStore(
      app: TestFixtures.app(deepLinkURL: nil),
      platform: .iOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.presentingAppID = "sample"
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .presentationFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .failed
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.presentingAppID = nil
      $0.openingAppIDs = ["sample"]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .appStore
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedAppStore(appID: "sample"))
      )
    }

    #expect(openRecorder.openedURLs == [TestFixtures.iOSStoreURL])
  }

  @Test
  func testIOSRejectedStoreFallbackAfterPresentationFailureEmitsFailure() async {
    let openRecorder = OpenRecorder(results: [false])
    let presentationRecorder = PresentationRecorder(outcomes: [.failed])
    let store = makePlatformStore(
      app: TestFixtures.app(deepLinkURL: nil),
      platform: .iOS,
      openRecorder: openRecorder,
      presentationRecorder: presentationRecorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.presentingAppID = "sample"
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .presentationFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .failed
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.presentingAppID = nil
      $0.openingAppIDs = ["sample"]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .failed
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .failedToOpen(appID: "sample"))
      )
    }

    #expect(openRecorder.openedURLs == [TestFixtures.iOSStoreURL])
  }

  @Test
  func testReplacingCatalogCancelsAnActivePlatformPresentation() async {
    let oldApp = TestFixtures.app(deepLinkURL: nil)
    let replacement = TestFixtures.app(
      id: "replacement",
      bundleIdentifier: "com.example.replacement",
      deepLinkURL: nil
    )
    let presentationRecorder = DeferredPresentationRecorder()
    var state = MoreAppsFeature.State(
      maximumNumberOfItems: nil,
      selectionBehavior: .platformPresentation
    )
    state.apps = [oldApp]

    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
      $0.moreAppsPresentation = MoreAppsPresentationClient(
        presenter: presentationRecorder
      )
    }

    await store.send(.selected(appID: oldApp.id)) {
      $0.presentingAppID = oldApp.id
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: oldApp.id))
      ]
    }
    await presentationRecorder.waitUntilPresentationStarts()

    await store.send(.setApps([replacement])) {
      $0.sourceApps = [replacement]
      $0.apps = [replacement]
      $0.presentingAppID = nil
      $0.dataSessionID = 1
    }
    await store.finish()

    #expect(presentationRecorder.cancellationCount == 1)
  }

  @Test
  func testStalePresentationResultCannotOpenAReplacementDestination() async {
    let oldApp = TestFixtures.app(
      deepLinkURL: nil,
      appStoreURL: TestFixtures.iOSStoreURL
    )
    let replacementStoreURL = URL(
      string: "https://apps.apple.com/app/id999"
    )!
    let replacement = TestFixtures.app(
      deepLinkURL: nil,
      appStoreURL: replacementStoreURL
    )
    let openRecorder = OpenRecorder(results: [true])
    var state = MoreAppsFeature.State(
      maximumNumberOfItems: nil,
      selectionBehavior: .platformPresentation
    )
    state.sourceApps = [oldApp]
    state.apps = [oldApp]
    state.presentingAppID = oldApp.id

    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
      $0.moreAppsOpen = MoreAppsOpenClient { url in
        openRecorder.open(url)
      }
    }

    await store.send(.setApps([replacement])) {
      $0.sourceApps = [replacement]
      $0.apps = [replacement]
      $0.presentingAppID = nil
      $0.dataSessionID = 1
    }
    await store.send(
      .presentationFinished(
        dataSessionID: 0,
        appID: oldApp.id,
        outcome: .appStoreRequested
      )
    )

    #expect(openRecorder.openedURLs.isEmpty)
  }

  @Test
  func testSelectionsAreIgnoredWhilePlatformPresentationIsActive() async {
    let firstApp = TestFixtures.app(
      id: "first",
      bundleIdentifier: "com.example.first",
      deepLinkURL: nil
    )
    let secondApp = TestFixtures.app(
      id: "second",
      bundleIdentifier: "com.example.second",
      deepLinkURL: nil
    )
    let presentationRecorder = DeferredPresentationRecorder()
    var state = MoreAppsFeature.State(
      maximumNumberOfItems: nil,
      selectionBehavior: .platformPresentation
    )
    state.sourceApps = [firstApp, secondApp]
    state.apps = [firstApp, secondApp]

    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
      $0.moreAppsPresentation = MoreAppsPresentationClient(
        presenter: presentationRecorder
      )
    }

    await store.send(.selected(appID: firstApp.id)) {
      $0.presentingAppID = firstApp.id
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: firstApp.id))
      ]
    }
    await presentationRecorder.waitUntilPresentationStarts()

    await store.send(.selected(appID: firstApp.id))
    await store.send(.selected(appID: secondApp.id))

    await store.send(.setApps([])) {
      $0.sourceApps = []
      $0.apps = []
      $0.presentingAppID = nil
      $0.dataSessionID = 1
    }
    await store.finish()

    #expect(presentationRecorder.requests.map(\.app.id) == [firstApp.id])
    #expect(presentationRecorder.cancellationCount == 1)
  }

  @Test
  func testLimitingCatalogCancelsPresentationForAnExcludedApp() async {
    let retainedApp = TestFixtures.app(
      id: "retained",
      bundleIdentifier: "com.example.retained",
      deepLinkURL: nil,
      sortOrder: 0
    )
    let presentedApp = TestFixtures.app(
      id: "presented",
      bundleIdentifier: "com.example.presented",
      deepLinkURL: nil,
      sortOrder: 1
    )
    let openRecorder = OpenRecorder(results: [true])
    let presentationRecorder = DeferredPresentationRecorder()
    var state = MoreAppsFeature.State(
      maximumNumberOfItems: nil,
      selectionBehavior: .platformPresentation
    )
    state.sourceApps = [retainedApp, presentedApp]
    state.apps = [retainedApp, presentedApp]

    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
      $0.moreAppsPresentation = MoreAppsPresentationClient(
        presenter: presentationRecorder
      )
      $0.moreAppsOpen = MoreAppsOpenClient { url in
        openRecorder.open(url)
      }
    }

    await store.send(.selected(appID: presentedApp.id)) {
      $0.presentingAppID = presentedApp.id
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: presentedApp.id))
      ]
    }
    await presentationRecorder.waitUntilPresentationStarts()

    await store.send(.setMaximumNumberOfItems(1)) {
      $0.maximumNumberOfItems = 1
      $0.apps = [retainedApp]
      $0.presentingAppID = nil
    }
    await store.send(
      .presentationFinished(
        dataSessionID: 0,
        appID: presentedApp.id,
        outcome: .appStoreRequested
      )
    )
    await store.finish()

    #expect(presentationRecorder.cancellationCount == 1)
    #expect(openRecorder.openedURLs.isEmpty)
  }

  @Test
  func testProviderErrorBecomesLoadingFailedEvent() async {
    struct LoadError: LocalizedError {
      var errorDescription: String? { "Offline" }
    }

    let store = TestStore(
      initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
    ) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(
      .load(.init { throw LoadError() })
    ) {
      $0.isLoading = true
      $0.nextLoadID = 1
      $0.activeLoadID = 1
    }
    await store.receive({ action in
      guard case .loadFailed(id: 1, message: "Offline") = action else {
        return false
      }
      return true
    }) {
      $0.isLoading = false
      $0.activeLoadID = nil
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .loadingFailed(message: "Offline"))
      ]
    }
  }

  @Test
  func testProviderLoadSuccessAppliesFilteredApps() async {
    let app = TestFixtures.app()
    let store = TestStore(
      initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
    ) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(.load(.init { [app] })) {
      $0.isLoading = true
      $0.nextLoadID = 1
      $0.activeLoadID = 1
    }
    await store.receive({ action in
      guard case .loadSucceeded(let id, let apps) = action else {
        return false
      }
      return id == 1 && apps == [app]
    }) {
      $0.sourceApps = [app]
      $0.apps = [app]
      $0.dataSessionID = 1
      $0.isLoading = false
      $0.activeLoadID = nil
    }
  }

  @Test
  func testUnrequestedCancellationErrorBecomesLoadingFailure() async {
    let message = CancellationError().localizedDescription
    let store = TestStore(
      initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
    ) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(
      .load(.init { throw CancellationError() })
    ) {
      $0.isLoading = true
      $0.nextLoadID = 1
      $0.activeLoadID = 1
    }
    await store.receive({ action in
      guard case .loadFailed(let id, let receivedMessage) = action else {
        return false
      }
      return id == 1 && receivedMessage == message
    }) {
      $0.isLoading = false
      $0.activeLoadID = nil
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .loadingFailed(message: message))
      ]
    }
  }

  @Test
  func testStaleProviderResponseCannotReplaceCurrentState() async {
    let currentApp = TestFixtures.app(id: "current")
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.apps = [currentApp]
    state.isLoading = true
    state.nextLoadID = 2
    state.activeLoadID = 2

    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(
      .loadSucceeded(
        id: 1,
        apps: [TestFixtures.app(id: "stale")]
      )
    )
  }

  @Test
  func testStaleProviderFailureDoesNotEmitAnEvent() async {
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.isLoading = true
    state.nextLoadID = 2
    state.activeLoadID = 2

    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    }

    await store.send(.loadFailed(id: 1, message: "Stale"))
  }

  @Test
  func testSetAppsCancelsAnActiveProviderLoad() async {
    let replacement = TestFixtures.app(id: "replacement")
    let store = TestStore(
      initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
    ) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(
      .load(
        .init {
          try await Task.sleep(nanoseconds: 60_000_000_000)
          return [TestFixtures.app(id: "stale")]
        })
    ) {
      $0.isLoading = true
      $0.nextLoadID = 1
      $0.activeLoadID = 1
    }
    await store.send(.setApps([replacement])) {
      $0.sourceApps = [replacement]
      $0.apps = [replacement]
      $0.dataSessionID = 1
      $0.isLoading = false
      $0.activeLoadID = nil
    }
  }

  @Test
  func testReplacementLoadCancelsItsPredecessor() async {
    let fresh = TestFixtures.app(id: "fresh")
    let store = TestStore(
      initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
    ) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(
      .load(
        .init {
          try await Task.sleep(nanoseconds: 60_000_000_000)
          return [TestFixtures.app(id: "stale")]
        })
    ) {
      $0.isLoading = true
      $0.nextLoadID = 1
      $0.activeLoadID = 1
    }
    await store.send(.load(.init { [fresh] })) {
      $0.nextLoadID = 2
      $0.activeLoadID = 2
    }
    await store.receive({ action in
      guard case .loadSucceeded(let id, let apps) = action else {
        return false
      }
      return id == 2 && apps == [fresh]
    }) {
      $0.sourceApps = [fresh]
      $0.apps = [fresh]
      $0.dataSessionID = 1
      $0.isLoading = false
      $0.activeLoadID = nil
    }
  }

  @Test
  func testImpressionIsEmittedOncePerDataSession() async {
    let store = TestStore(
      initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
    ) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(.setApps([TestFixtures.app()])) {
      $0.sourceApps = [TestFixtures.app()]
      $0.apps = [TestFixtures.app()]
      $0.dataSessionID = 1
    }
    await store.send(.itemBecameVisible(appID: "sample")) {
      $0.impressedAppIDs = ["sample"]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .impression(appID: "sample"))
      ]
    }
    await store.send(.itemBecameVisible(appID: "sample"))
  }

  @Test
  func testNewCatalogResetsImpressionEligibility() async {
    let app = TestFixtures.app()
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.sourceApps = [app]
    state.apps = [app]
    state.impressedAppIDs = [app.id]

    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(.setApps([app])) {
      $0.dataSessionID = 1
      $0.impressedAppIDs = []
    }
    await store.send(.itemBecameVisible(appID: app.id)) {
      $0.impressedAppIDs = [app.id]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .impression(appID: app.id))
      ]
    }
  }

  @Test
  func testUnknownImpressionAndDuplicateSelectionAreIgnored() async {
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.apps = [TestFixtures.app()]
    state.openingAppIDs = ["sample"]

    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    }

    await store.send(.itemBecameVisible(appID: "missing"))
    await store.send(.selected(appID: "sample"))
    await store.send(.selected(appID: "missing"))
  }

  @Test
  func testSelectionWithoutCurrentPlatformDestinationIsIgnored() async {
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.apps = [TestFixtures.app(platforms: [.tvOS])]

    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(.selected(appID: "sample"))
  }

  @Test
  func testFailedStoreOpenEmitsFailedToOpen() async {
    let recorder = OpenRecorder(results: [false, false])
    let store = makeStore(
      app: TestFixtures.app(),
      recorder: recorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.openingAppIDs = ["sample"]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .failed
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .failedToOpen(appID: "sample"))
      )
    }

    #expect(
      recorder.openedURLs
        == [TestFixtures.deepLinkURL, TestFixtures.iOSStoreURL]
    )
  }

  @Test
  func testBlockedDeepLinkFallsBackToValidatedAppStoreURL() async {
    let blockedURL = URL(fileURLWithPath: "/tmp/not-an-app-link")
    let recorder = OpenRecorder(results: [true])
    let store = makeStore(
      app: TestFixtures.app(deepLinkURL: blockedURL),
      recorder: recorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.openingAppIDs = ["sample"]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .appStore
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedAppStore(appID: "sample"))
      )
    }

    #expect(recorder.openedURLs == [TestFixtures.iOSStoreURL])
  }

  @Test
  func testUntrustedStoreURLIsRejectedWithoutOpening() async {
    let untrustedURL = URL(string: "https://example.com/not-the-app-store")!
    let recorder = OpenRecorder(results: [true])
    let store = makeStore(
      app: TestFixtures.app(
        deepLinkURL: nil,
        appStoreURL: untrustedURL
      ),
      recorder: recorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.nextEventID = 2
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample")),
        .init(id: 2, event: .failedToOpen(appID: "sample")),
      ]
    }

    #expect(recorder.openedURLs.isEmpty)
  }

  @Test
  func testAppStoreDeepLinkUsesAppStoreOutcome() async {
    let recorder = OpenRecorder(results: [true])
    let store = makeStore(
      app: TestFixtures.app(
        deepLinkURL: TestFixtures.iOSStoreURL
      ),
      recorder: recorder
    )

    await store.send(.selected(appID: "sample")) {
      $0.openingAppIDs = ["sample"]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: "sample"))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 0,
          appID: "sample",
          outcome: .appStore
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedAppStore(appID: "sample"))
      )
    }

    #expect(recorder.openedURLs == [TestFixtures.iOSStoreURL])
  }

  @Test
  func testReplacingCatalogRejectsStaleOpenResult() async {
    let oldApp = TestFixtures.app()
    let replacement = TestFixtures.app(bundleIdentifier: "com.example.new")
    var state = MoreAppsFeature.State(
      maximumNumberOfItems: nil,
      allowedCustomDeepLinkSchemes: ["sample"]
    )
    state.sourceApps = [oldApp]
    state.apps = [oldApp]
    state.openingAppIDs = [oldApp.id]

    let recorder = OpenRecorder(results: [true])
    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
      $0.moreAppsOpen = MoreAppsOpenClient { url in
        recorder.open(url)
      }
    }

    await store.send(.setApps([replacement])) {
      $0.sourceApps = [replacement]
      $0.apps = [replacement]
      $0.openingAppIDs = []
      $0.dataSessionID = 1
    }
    await store.send(
      .openFinished(
        dataSessionID: 0,
        appID: oldApp.id,
        outcome: .app
      )
    )
    await store.send(.selected(appID: replacement.id)) {
      $0.openingAppIDs = [replacement.id]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: replacement.id))
      ]
    }
    await store.receive({ action in
      guard
        case .openFinished(
          dataSessionID: 1,
          appID: replacement.id,
          outcome: .app
        ) = action
      else {
        return false
      }
      return true
    }) {
      $0.openingAppIDs = []
      $0.nextEventID = 2
      $0.pendingEvents.append(
        .init(id: 2, event: .openedApp(appID: replacement.id))
      )
    }
  }

  @Test
  func testReplacingCatalogPreventsStaleAppStoreFallback() async {
    let oldApp = TestFixtures.app()
    let replacement = TestFixtures.app(
      id: "replacement",
      bundleIdentifier: "com.example.new"
    )
    var state = MoreAppsFeature.State(
      maximumNumberOfItems: nil,
      allowedCustomDeepLinkSchemes: ["sample"]
    )
    state.sourceApps = [oldApp]
    state.apps = [oldApp]
    let recorder = DeferredOpenRecorder()

    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
      $0.moreAppsOpen = MoreAppsOpenClient { url in
        await recorder.open(url)
      }
    }

    await store.send(.selected(appID: oldApp.id)) {
      $0.openingAppIDs = [oldApp.id]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .selected(appID: oldApp.id))
      ]
    }
    await recorder.waitUntilFirstOpenStarts()

    await store.send(.setApps([replacement])) {
      $0.sourceApps = [replacement]
      $0.apps = [replacement]
      $0.openingAppIDs = []
      $0.dataSessionID = 1
    }

    recorder.finishFirstOpen(with: false)
    await store.finish()

    #expect(recorder.openedURLs == [TestFixtures.deepLinkURL])
  }

  @Test
  func testCancelledOpenClientDoesNotInvokeUnderlyingOpener() async {
    let recorder = OpenRecorder(results: [true])
    let client = MoreAppsOpenClient { url in
      recorder.open(url)
    }
    let task = Task {
      try? await Task.sleep(nanoseconds: 60_000_000_000)
      return await client(TestFixtures.iOSStoreURL)
    }

    task.cancel()

    #expect(await task.value == false)
    #expect(recorder.openedURLs.isEmpty)
  }

  @Test
  func testChangingMaximumRestoresItemsFromTheSourceCatalog() async {
    let apps = [
      TestFixtures.app(id: "first", sortOrder: 0),
      TestFixtures.app(id: "second", sortOrder: 1),
      TestFixtures.app(id: "third", sortOrder: 2),
    ]
    let store = TestStore(
      initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
    ) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
    }

    await store.send(.setApps(apps)) {
      $0.sourceApps = apps
      $0.apps = apps
      $0.dataSessionID = 1
    }
    await store.send(.itemBecameVisible(appID: apps[0].id)) {
      $0.impressedAppIDs = [apps[0].id]
      $0.nextEventID = 1
      $0.pendingEvents = [
        .init(id: 1, event: .impression(appID: apps[0].id))
      ]
    }
    await store.send(.setMaximumNumberOfItems(1)) {
      $0.maximumNumberOfItems = 1
      $0.apps = [apps[0]]
    }
    await store.send(.setMaximumNumberOfItems(nil)) {
      $0.maximumNumberOfItems = nil
      $0.apps = apps
    }
  }

  @Test
  func testEventDeliveryAcknowledgesOnlyMatchingEnvelope() async {
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.pendingEvents = [
      .init(id: 1, event: .selected(appID: "first")),
      .init(id: 2, event: .selected(appID: "second")),
    ]

    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    }

    await store.send(.eventDelivered(1)) {
      $0.pendingEvents = [
        .init(id: 2, event: .selected(appID: "second"))
      ]
    }
  }

  @Test
  func testPendingEventBacklogIsBounded() {
    let apps = (0...MoreAppsFeature.maximumPendingEventCount).map { index in
      TestFixtures.app(id: "app-\(index)")
    }
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.apps = apps

    let store = Store(initialState: state) {
      MoreAppsFeature()
    }

    for app in apps {
      store.send(.itemBecameVisible(appID: app.id))
    }

    #expect(
      store.pendingEvents.count
        == MoreAppsFeature.maximumPendingEventCount
    )
    #expect(store.pendingEvents.first?.id == 2)
    #expect(
      store.pendingEvents.last?.id
        == MoreAppsFeature.maximumPendingEventCount + 1
    )
  }

  private func makeStore(
    app: MoreApp,
    recorder: OpenRecorder
  ) -> TestStoreOf<MoreAppsFeature> {
    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.apps = [app]
    state.allowedCustomDeepLinkSchemes = ["sample"]

    return TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: .iOS,
        bundleIdentifier: nil
      )
      $0.moreAppsOpen = MoreAppsOpenClient { url in
        recorder.open(url)
      }
    }
  }

  private func makePlatformStore(
    app: MoreApp,
    platform: MoreAppsPlatform,
    openRecorder: OpenRecorder,
    presentationRecorder: PresentationRecorder
  ) -> TestStoreOf<MoreAppsFeature> {
    var state = MoreAppsFeature.State(
      maximumNumberOfItems: nil,
      allowedCustomDeepLinkSchemes: ["sample"],
      selectionBehavior: .platformPresentation
    )
    state.apps = [app]

    return TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(
        platform: platform,
        bundleIdentifier: nil
      )
      $0.moreAppsOpen = MoreAppsOpenClient { url in
        openRecorder.open(url)
      }
      $0.moreAppsPresentation = MoreAppsPresentationClient(
        presenter: presentationRecorder
      )
    }
  }
}

@MainActor
private final class OpenRecorder {
  private var results: [Bool]
  private(set) var openedURLs: [URL] = []

  init(results: [Bool]) {
    self.results = results
  }

  func open(_ url: URL) -> Bool {
    openedURLs.append(url)
    guard !results.isEmpty else { return false }
    return results.removeFirst()
  }
}

@MainActor
private final class PresentationRecorder: MoreAppsPresenting {
  private var outcomes: [MoreAppsPresentationOutcome]
  private(set) var requests: [MoreAppsPresentationRequest] = []

  init(outcomes: [MoreAppsPresentationOutcome]) {
    self.outcomes = outcomes
  }

  func present(
    _ request: MoreAppsPresentationRequest
  ) async -> MoreAppsPresentationOutcome {
    requests.append(request)
    guard !outcomes.isEmpty else { return .failed }
    return outcomes.removeFirst()
  }
}

@MainActor
private final class DeferredPresentationRecorder: MoreAppsPresenting {
  private(set) var cancellationCount = 0
  private(set) var requests: [MoreAppsPresentationRequest] = []
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  func present(
    _ request: MoreAppsPresentationRequest
  ) async -> MoreAppsPresentationOutcome {
    requests.append(request)
    startWaiters.forEach { $0.resume() }
    startWaiters.removeAll()

    do {
      try await Task.sleep(nanoseconds: 60_000_000_000)
      return .dismissed
    } catch {
      cancellationCount += 1
      return .dismissed
    }
  }

  func waitUntilPresentationStarts() async {
    guard requests.isEmpty else { return }
    await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
  }
}

@MainActor
private final class DeferredOpenRecorder {
  private(set) var openedURLs: [URL] = []
  private var firstOpenContinuation: CheckedContinuation<Bool, Never>?
  private var firstOpenStartWaiters: [CheckedContinuation<Void, Never>] = []

  func open(_ url: URL) async -> Bool {
    openedURLs.append(url)
    guard openedURLs.count == 1 else { return true }

    firstOpenStartWaiters.forEach { $0.resume() }
    firstOpenStartWaiters.removeAll()
    return await withCheckedContinuation { continuation in
      firstOpenContinuation = continuation
    }
  }

  func waitUntilFirstOpenStarts() async {
    guard openedURLs.isEmpty else { return }
    await withCheckedContinuation { continuation in
      firstOpenStartWaiters.append(continuation)
    }
  }

  func finishFirstOpen(with result: Bool) {
    firstOpenContinuation?.resume(returning: result)
    firstOpenContinuation = nil
  }
}
