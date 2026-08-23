//
//  MoreAppsFilterTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Testing

@testable import MoreAppsKit

@Suite
struct MoreAppsFilterTests {
  @Test
  func testIOSIncludesOnlyAppsWithIOSDestination() {
    let apps = [
      TestFixtures.app(id: "ios", platforms: [.iOS]),
      TestFixtures.app(id: "tvos", platforms: [.tvOS]),
      TestFixtures.app(id: "both", platforms: [.iOS, .tvOS]),
    ]

    let result = MoreAppsFilter.filtered(
      apps,
      for: .iOS,
      excluding: nil
    )

    #expect(result.map(\.id) == ["ios", "both"])
  }

  @Test
  func testTVOSIncludesOnlyAppsWithTVOSDestination() {
    let apps = [
      TestFixtures.app(id: "ios", platforms: [.iOS]),
      TestFixtures.app(id: "tvos", platforms: [.tvOS]),
      TestFixtures.app(id: "both", platforms: [.iOS, .tvOS]),
    ]

    let result = MoreAppsFilter.filtered(
      apps,
      for: .tvOS,
      excluding: nil
    )

    #expect(result.map(\.id) == ["tvos", "both"])
  }

  @Test
  func testCurrentBundleIdentifierIsExcluded() {
    let current = TestFixtures.app(
      id: "current",
      bundleIdentifier: "com.example.host"
    )
    let other = TestFixtures.app(id: "other")

    let result = MoreAppsFilter.filtered(
      [current, other],
      for: .iOS,
      excluding: "com.example.host"
    )

    #expect(result.map(\.id) == ["other"])
  }

  @Test
  func testAppsAreSortedBySortOrderWithStableTies() {
    let result = MoreAppsFilter.filtered(
      [
        TestFixtures.app(id: "third", sortOrder: 30),
        TestFixtures.app(id: "first-a", sortOrder: 10),
        TestFixtures.app(id: "first-b", sortOrder: 10),
      ],
      for: .iOS,
      excluding: nil
    )

    #expect(result.map(\.id) == ["first-a", "first-b", "third"])
  }

  @Test
  func testFirstDuplicatedIDWins() {
    let first = TestFixtures.app(id: "duplicate", sortOrder: 20)
    let second = TestFixtures.app(id: "duplicate", sortOrder: 1)

    let result = MoreAppsFilter.filtered(
      [first, second],
      for: .iOS,
      excluding: nil
    )

    #expect(result == [first])
  }

  @Test
  func testMaximumNumberOfItemsIsAppliedAfterSorting() {
    let result = MoreAppsFilter.filtered(
      [
        TestFixtures.app(id: "second", sortOrder: 2),
        TestFixtures.app(id: "first", sortOrder: 1),
      ],
      for: .iOS,
      excluding: nil,
      maximumNumberOfItems: 1
    )

    #expect(result.map(\.id) == ["first"])
  }

  @Test(arguments: [0, -1])
  func testNonPositiveMaximumProducesEmptyResult(maximum: Int) {
    let result = MoreAppsFilter.filtered(
      [TestFixtures.app()],
      for: .iOS,
      excluding: nil,
      maximumNumberOfItems: maximum
    )

    #expect(result.isEmpty)
  }
}
