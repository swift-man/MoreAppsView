//
//  MoreApp.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation

/// Metadata describing an app that can be promoted by ``MoreAppsView``.
public struct MoreApp: Identifiable, Codable, Hashable, Sendable {
  /// A stable identifier used for diffing, events, and duplicate removal.
  public let id: String

  /// The target app's bundle identifier.
  public let bundleIdentifier: String

  /// The localized display name of the target app.
  public let name: String

  /// Optional supporting copy shown beneath the app name.
  public let subtitle: String?

  /// An optional remote icon URL.
  public let iconURL: URL?

  /// Platform-specific App Store and deep-link destinations.
  public let destinations: [MoreAppDestination]

  /// The ascending display priority.
  public let sortOrder: Int

  /// Creates app promotion metadata.
  ///
  /// - Parameters:
  ///   - id: A stable identifier for diffing and events.
  ///   - bundleIdentifier: The target app's bundle identifier.
  ///   - name: The target app's display name.
  ///   - subtitle: Optional supporting copy.
  ///   - iconURL: An optional remote icon URL.
  ///   - destinations: Platform-specific destinations.
  ///   - sortOrder: The ascending display priority.
  public init(
    id: String,
    bundleIdentifier: String,
    name: String,
    subtitle: String? = nil,
    iconURL: URL? = nil,
    destinations: [MoreAppDestination],
    sortOrder: Int
  ) {
    self.id = id
    self.bundleIdentifier = bundleIdentifier
    self.name = name
    self.subtitle = subtitle
    self.iconURL = iconURL
    self.destinations = destinations
    self.sortOrder = sortOrder
  }

  /// Returns this app's destination for a platform, if one exists.
  ///
  /// - Parameter platform: The platform whose destination is needed.
  /// - Returns: The first matching destination, or `nil`.
  public func destination(
    for platform: MoreAppsPlatform
  ) -> MoreAppDestination? {
    destinations.first { $0.platform == platform }
  }
}
