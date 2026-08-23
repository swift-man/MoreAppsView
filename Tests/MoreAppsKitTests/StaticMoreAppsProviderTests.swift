//
//  StaticMoreAppsProviderTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Testing

@testable import MoreAppsKit

@Suite
struct StaticMoreAppsProviderTests {
  @Test
  func testProviderReturnsTheExactInjectedCatalog() async throws {
    let apps = [
      TestFixtures.app(id: "first"),
      TestFixtures.app(id: "second", platforms: [.tvOS]),
    ]
    let provider = StaticMoreAppsProvider(apps: apps)

    let fetchedApps = try await provider.fetchApps()

    #expect(fetchedApps == apps)
  }
}
