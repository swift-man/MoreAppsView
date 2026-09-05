//
//  MoreAppsEnvironment.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Dependencies
import Foundation

/// Host information used when filtering an app catalog.
struct MoreAppsEnvironment: Equatable, Sendable {
  /// The platform on which the host is running.
  var platform: MoreAppsPlatform

  /// The host app's bundle identifier, if available.
  var bundleIdentifier: String?

  /// Creates a host environment.
  ///
  /// - Parameters:
  ///   - platform: The platform on which the host is running.
  ///   - bundleIdentifier: The host app's bundle identifier.
  init(
    platform: MoreAppsPlatform,
    bundleIdentifier: String?
  ) {
    self.platform = platform
    self.bundleIdentifier = bundleIdentifier
  }

  /// The live environment inferred from the compiled platform and main bundle.
  static var live: Self {
    Self(
      platform: .current,
      bundleIdentifier: Bundle.main.bundleIdentifier
    )
  }
}

extension MoreAppsEnvironment: DependencyKey {
  /// The host environment used in production.
  static var liveValue: Self { .live }

  /// A deterministic default used when a test does not override the value.
  static let testValue = Self(
    platform: .iOS,
    bundleIdentifier: nil
  )
}

extension DependencyValues {
  /// The host environment used by ``MoreAppsFeature``.
  var moreAppsEnvironment: MoreAppsEnvironment {
    get { self[MoreAppsEnvironment.self] }
    set { self[MoreAppsEnvironment.self] = newValue }
  }
}
