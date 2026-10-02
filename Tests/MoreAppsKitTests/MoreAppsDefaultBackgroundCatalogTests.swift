//
//  MoreAppsDefaultBackgroundCatalogTests.swift
//  MoreAppsKit
//
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Testing

@testable import MoreAppsKitCore

@MainActor
@Suite
struct MoreAppsDefaultBackgroundCatalogTests {
  @Test
  func defaultArtworkAppliesToRegisteredTVOSApp() {
    let defaultURL = makeApp().resolvedBackgroundImageURL(for: .tvOS)
    #expect(defaultURL?.scheme == "https")
    #expect(defaultURL?.host == "is1-ssl.mzstatic.com")
  }

  @Test
  func explicitURLOverridesDefault() {
    let custom = URL(string: "https://example.com/custom.png")!
    #expect(makeApp(customURL: custom).resolvedBackgroundImageURL(for: .tvOS) == custom)
    #expect(
      makeApp(bundleIdentifier: "unknown.app", customURL: custom)
        .resolvedBackgroundImageURL(for: .tvOS) == custom)
  }

  @Test
  func unknownAppHasNoFallback() {
    #expect(makeApp(bundleIdentifier: "unknown.app").resolvedBackgroundImageURL(for: .tvOS) == nil)
  }

  @Test
  func platformWithoutDestinationHasNoFallback() {
    #expect(makeApp().resolvedBackgroundImageURL(for: .iOS) == nil)
  }

  @Test
  func matchingIOSDestinationDoesNotInheritTVOSArtwork() {
    let app = makeApp(platforms: [.iOS, .tvOS])
    #expect(app.destination(for: .iOS) != nil)
    #expect(app.resolvedBackgroundImageURL(for: .iOS) == nil)
    #expect(app.resolvedBackgroundImageURL(for: .tvOS) != nil)
  }

  @Test
  func decoderMapsPlatformKeys() throws {
    let data = Data(#"{"app":{"tvOS":"https://example.com/tv.png","iOS":"https://example.com/ios.png"}}"#.utf8)
    let images = try MoreAppsDefaultBackgroundCatalog.decode(data)
    #expect(images["app"]?[.tvOS]?.lastPathComponent == "tv.png")
    #expect(images["app"]?[.iOS]?.lastPathComponent == "ios.png")
  }

  @Test(arguments: [#"{"app":{"tvos":"https://example.com/tv.png"}}"#, "invalid-json"])
  func decoderRejectsInvalidCatalog(json: String) {
    #expect(throws: DecodingError.self) {
      try MoreAppsDefaultBackgroundCatalog.decode(Data(json.utf8))
    }
  }

  @Test
  func focusReducerUsesResolvedURLAndClearsOnFocusLoss() async {
    let app = makeApp()
    let defaultURL = app.resolvedBackgroundImageURL(for: .tvOS)

    var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
    state.apps = [app]
    let store = TestStore(initialState: state) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .init(platform: .tvOS, bundleIdentifier: "host.app")
    }
    await store.send(.focusChanged(appID: app.id)) {
      $0.focusedAppID = app.id
      $0.focusedBackgroundImageURL = defaultURL
    }
    await store.send(.focusChanged(appID: nil)) {
      $0.focusedAppID = nil
      $0.focusedBackgroundImageURL = nil
    }
  }

  private func makeApp(
    bundleIdentifier: String = "me.gorani.Andromeda17K", customURL: URL? = nil,
    platforms: [MoreAppsPlatform] = [.tvOS]
  ) -> MoreApp {
    MoreApp(
      id: "andromeda", bundleIdentifier: bundleIdentifier, name: "Andromeda",
      destinations: platforms.map { platform in
        MoreAppDestination(
          platform: platform, appStoreURL: URL(string: "https://apps.apple.com/app/id6786789129")!,
          backgroundImageURL: customURL)
      }, sortOrder: 0)
  }
}
