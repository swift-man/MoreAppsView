//
//  MoreAppsKitNetworkingImportTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 9/5/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import MoreAppsNetworking
import Testing

@Suite("MoreAppsKitNetworking product boundary")
struct MoreAppsKitNetworkingImportTests {
  @Test("Networking exposes the Alamofire-backed image loader independently")
  @MainActor
  func networkingProductImportsIndependently() {
    let loader = MoreAppsImageLoader.shared

    #expect(loader === MoreAppsImageLoader.shared)
  }
}
