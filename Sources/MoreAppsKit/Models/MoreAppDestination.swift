//
//  MoreAppDestination.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation

/// URLs used to present and open one promoted app on a specific platform.
public struct MoreAppDestination: Codable, Hashable, Sendable {
  /// The platform to which the URLs apply.
  public let platform: MoreAppsPlatform

  /// The App Store product URL for the app.
  public let appStoreURL: URL

  /// An optional custom-scheme or universal-link URL for opening the app.
  public let deepLinkURL: URL?

  /// An optional promotional image shown while this destination is focused.
  ///
  /// On tvOS, ``MoreAppsView`` can render this image with
  /// ``MoreAppsFocusedBackgroundView``. The value remains platform-specific so
  /// shared catalogs can keep artwork associated with the matching destination.
  public let backgroundImageURL: URL?

  /// Creates a platform-specific destination.
  ///
  /// - Parameters:
  ///   - platform: The platform to which the URLs apply.
  ///   - appStoreURL: The App Store product URL.
  ///   - deepLinkURL: An optional URL that opens the installed app directly.
  ///   - backgroundImageURL: Optional focus background artwork for this platform.
  public init(
    platform: MoreAppsPlatform,
    appStoreURL: URL,
    deepLinkURL: URL? = nil,
    backgroundImageURL: URL? = nil
  ) {
    self.platform = platform
    self.appStoreURL = appStoreURL
    self.deepLinkURL = deepLinkURL
    self.backgroundImageURL = backgroundImageURL
  }
}
