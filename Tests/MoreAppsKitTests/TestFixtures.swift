//
//  TestFixtures.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation

@testable import MoreAppsKit

enum TestFixtures {
  static let iOSStoreURL = URL(string: "https://apps.apple.com/app/id100")!
  static let tvOSStoreURL = URL(string: "https://apps.apple.com/app/id200")!
  static let deepLinkURL = URL(string: "sample://home")!

  static func app(
    id: String = "sample",
    bundleIdentifier: String = "com.example.sample",
    platforms: [MoreAppsPlatform] = [.iOS],
    deepLinkURL: URL? = TestFixtures.deepLinkURL,
    appStoreURL: URL? = nil,
    sortOrder: Int = 0
  ) -> MoreApp {
    MoreApp(
      id: id,
      bundleIdentifier: bundleIdentifier,
      name: id.capitalized,
      subtitle: "Subtitle",
      destinations: platforms.map { platform in
        MoreAppDestination(
          platform: platform,
          appStoreURL: appStoreURL
            ?? (platform == .iOS ? iOSStoreURL : tvOSStoreURL),
          deepLinkURL: deepLinkURL
        )
      },
      sortOrder: sortOrder
    )
  }
}
