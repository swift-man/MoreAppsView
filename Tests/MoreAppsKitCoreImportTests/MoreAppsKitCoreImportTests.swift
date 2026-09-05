//
//  MoreAppsKitCoreImportTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 9/5/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import MoreAppsKitCore
import Testing

@Suite("MoreAppsKitCore product boundary")
struct MoreAppsKitCoreImportTests {
  @Test("Core exposes UI configuration without the networking product")
  func coreProductImportsIndependently() {
    let configuration = MoreAppsConfiguration.default

    #expect(configuration.maximumNumberOfItems == nil)
  }
}
