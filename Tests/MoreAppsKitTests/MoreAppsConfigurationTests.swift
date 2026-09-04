//
//  MoreAppsConfigurationTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Testing

@testable import MoreAppsKit
@testable import MoreAppsKitCore

struct MoreAppsConfigurationTests {
  @Test
  func testSynthesizedEqualityTracksConfigurationChanges() {
    let baseline = MoreAppsConfiguration.default
    var changed = baseline

    #expect(baseline == changed)

    changed.allowedCustomDeepLinkSchemes = ["wordrush"]

    #expect(baseline != changed)

    changed = baseline
    changed.selectionBehavior = .platformPresentation

    #expect(baseline != changed)
  }

  @Test
  func testCustomSchemesAreNormalizedWhenAssigned() {
    var configuration = MoreAppsConfiguration(
      allowedCustomDeepLinkSchemes: ["SAMPLE", ""]
    )

    #expect(configuration.allowedCustomDeepLinkSchemes == ["sample"])

    configuration.allowedCustomDeepLinkSchemes = ["WordRush"]

    #expect(configuration.allowedCustomDeepLinkSchemes == ["wordrush"])
  }
}
