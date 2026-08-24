//
//  MoreAppsURLPolicyTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation
import Testing

@testable import MoreAppsKit

@Suite
struct MoreAppsURLPolicyTests {
  @Test(
    arguments: [
      "tel:+18005551212",
      "sms:+18005551212",
      "mailto:person@example.com",
      "facetime:person@example.com",
      "App-Prefs:root=General",
      "http://example.com/open/sample",
    ]
  )
  func testSystemActionSchemesAreRejected(urlString: String) {
    let url = URL(string: urlString)!

    #expect(
      MoreAppsURLPolicy.allowedDeepLink(
        url,
        allowedCustomSchemes: []
      ) == nil
    )
  }

  @Test
  func testAllowlistedCustomSchemeAndUniversalLinkAreSupported() {
    let customURL = URL(string: "sample://home")!
    let universalLink = URL(string: "https://example.com/open/sample")!

    #expect(
      MoreAppsURLPolicy.allowedDeepLink(
        customURL,
        allowedCustomSchemes: ["sample"]
      ) == customURL
    )
    #expect(
      MoreAppsURLPolicy.allowedDeepLink(
        universalLink,
        allowedCustomSchemes: []
      ) == universalLink
    )
  }

  @Test
  func testPlainHTTPIsRejectedEvenWhenAllowlisted() {
    let url = URL(string: "http://example.com/open/sample")!

    #expect(
      MoreAppsURLPolicy.allowedDeepLink(
        url,
        allowedCustomSchemes: ["http"]
      ) == nil
    )
  }

  @Test
  func testUnlistedCustomSchemeIsRejected() {
    let url = URL(string: "shortcuts://run-shortcut?name=Unexpected")!

    #expect(
      MoreAppsURLPolicy.allowedDeepLink(
        url,
        allowedCustomSchemes: ["sample"]
      ) == nil
    )
  }

  @Test
  func testAppStoreURLIsNotTreatedAsADeepLink() {
    let url = URL(string: "https://apps.apple.com/app/id100")!

    #expect(
      MoreAppsURLPolicy.allowedDeepLink(
        url,
        allowedCustomSchemes: []
      ) == nil
    )
  }

  @Test(
    arguments: [
      "https://apps.apple.com/app/id100",
      "itms-apps://apps.apple.com/app/id100",
      "https://itunes.apple.com/app/id100",
    ]
  )
  func testSupportedAppStoreRoutesAreAccepted(urlString: String) {
    let url = URL(string: urlString)!

    #expect(MoreAppsURLPolicy.allowedAppStoreURL(url) == url)
  }

  @Test
  func testSchemelessDeepLinkAndHTTPStoreURLAreRejected() {
    let schemelessDeepLink = URL(string: "example.com/open/sample")!
    let insecureStoreURL = URL(
      string: "http://apps.apple.com/app/id100"
    )!

    #expect(
      MoreAppsURLPolicy.allowedDeepLink(
        schemelessDeepLink,
        allowedCustomSchemes: []
      ) == nil
    )
    #expect(MoreAppsURLPolicy.allowedAppStoreURL(insecureStoreURL) == nil)
  }

  @Test(
    arguments: [
      (
        "https://apps.apple.com/us/app/andromeda-17k-clock-wallpaper/id6786789129",
        "6786789129"
      ),
      (
        "https://itunes.apple.com/us/app/sample/id12345?mt=8",
        "12345"
      ),
      (
        "itms-apps://apps.apple.com/app/id42",
        "42"
      ),
      (
        "itms-apps://itunes.apple.com/us/app/id7",
        "7"
      ),
    ]
  )
  func testAppStoreIdentifierIsExtractedFromAPathComponent(
    urlString: String,
    expectedIdentifier: String
  ) {
    let url = URL(string: urlString)!

    #expect(
      MoreAppsURLPolicy.appStoreIdentifier(from: url)
        == expectedIdentifier
    )
  }

  @Test(
    arguments: [
      "https://apps.apple.com/app/sample",
      "https://apps.apple.com/app/sample?id123",
      "https://apps.apple.com/app/sample#id123",
      "https://apps.apple.com/app/sample-id123",
      "https://apps.apple.com/app/id123-preview",
      "https://apps.apple.com/app/id12a3",
      "https://apps.apple.com/app/id0",
      "https://apps.apple.com/app/id000",
      "https://apps.apple.com/app/id%31%32%33",
      "https://apps.apple.com/app/id100/id200",
    ]
  )
  func testInvalidAppStoreIdentifiersAreRejected(urlString: String) {
    let url = URL(string: urlString)!

    #expect(MoreAppsURLPolicy.appStoreIdentifier(from: url) == nil)
  }

  @Test(
    arguments: [
      "https://example.com/app/id123",
      "https://apps.apple.com.example.com/app/id123",
      "itms-apps://example.com/app/id123",
      "http://apps.apple.com/app/id123",
    ]
  )
  func testAppStoreIdentifierRequiresAnAllowedStoreURL(
    urlString: String
  ) {
    let url = URL(string: urlString)!

    #expect(MoreAppsURLPolicy.appStoreIdentifier(from: url) == nil)
  }

  @MainActor
  @Test
  func testOnlyNonStoreHTTPSLinksRequireUniversalLinkHandling() {
    let universalLink = URL(string: "https://example.com/open/sample")!
    let storeURL = URL(string: "https://apps.apple.com/app/id100")!
    let customURL = URL(string: "sample://home")!

    #expect(
      DefaultMoreAppsOpener.usesUniversalLinksOnly(for: universalLink)
    )
    #expect(!DefaultMoreAppsOpener.usesUniversalLinksOnly(for: storeURL))
    #expect(!DefaultMoreAppsOpener.usesUniversalLinksOnly(for: customURL))
  }
}
