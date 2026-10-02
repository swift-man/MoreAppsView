import ComposableArchitecture
import Foundation
import Testing

@testable import MoreAppsKitCore

@MainActor
@Suite
struct MoreAppsDefaultBackgroundCatalogTests {
  @Test
  func defaultFirstScreenshotAndCustomOverrideFollowPlatform() async {
    let app = makeApp()
    let defaultURL = app.resolvedBackgroundImageURL(for: .tvOS)
    #expect(defaultURL?.host == "is1-ssl.mzstatic.com")
    #expect(defaultURL?.absoluteString.contains("2026-07-29_at_15.54.24") == true)
    #expect(app.resolvedBackgroundImageURL(for: .iOS) == nil)
    let custom = URL(string: "https://example.com/custom.png")!
    #expect(makeApp(customURL: custom).resolvedBackgroundImageURL(for: .tvOS) == custom)
    #expect(makeApp(bundleIdentifier: "unknown.app").resolvedBackgroundImageURL(for: .tvOS) == nil)

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
    bundleIdentifier: String = "me.gorani.Andromeda17K", customURL: URL? = nil
  ) -> MoreApp {
    MoreApp(
      id: "andromeda", bundleIdentifier: bundleIdentifier, name: "Andromeda",
      destinations: [
        MoreAppDestination(
          platform: .tvOS, appStoreURL: URL(string: "https://apps.apple.com/app/id6786789129")!,
          backgroundImageURL: customURL)
      ], sortOrder: 0)
  }
}
