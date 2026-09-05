//
//  MoreAppsOpening.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Dependencies
import Foundation

/// An object that can ask the operating system to open a URL.
@MainActor
public protocol MoreAppsOpening: AnyObject, Sendable {
  /// Attempts to open a URL.
  ///
  /// - Parameter url: The URL to open.
  /// - Returns: `true` when the system reports that the URL opened.
  func open(_ url: URL) async -> Bool
}

/// A dependency client that exposes URL opening to a TCA reducer.
struct MoreAppsOpenClient: Sendable {
  private let openURL: @MainActor @Sendable (URL) async -> Bool

  /// Creates a client from a URL-opening operation.
  ///
  /// - Parameter open: The operation to invoke.
  init(
    open: @escaping @MainActor @Sendable (URL) async -> Bool
  ) {
    self.openURL = open
  }

  /// Creates a client that forwards to an opener object.
  ///
  /// - Parameter opener: The opener to wrap.
  @MainActor
  init(opener: any MoreAppsOpening) {
    self.openURL = { url in
      await opener.open(url)
    }
  }

  /// Attempts to open a URL.
  ///
  /// - Parameter url: The URL to open.
  /// - Returns: `true` when the operation reports success.
  @MainActor
  func callAsFunction(_ url: URL) async -> Bool {
    guard !Task.isCancelled else { return false }
    return await openURL(url)
  }
}

extension MoreAppsOpenClient: DependencyKey {
  /// The system URL opener used in production.
  static let liveValue = MoreAppsOpenClient {
    await DefaultMoreAppsOpener.shared.open($0)
  }

  /// A safe test default that never opens external URLs.
  static let testValue = MoreAppsOpenClient { _ in false }
}

extension DependencyValues {
  /// The URL-opening dependency used by ``MoreAppsFeature``.
  var moreAppsOpen: MoreAppsOpenClient {
    get { self[MoreAppsOpenClient.self] }
    set { self[MoreAppsOpenClient.self] = newValue }
  }
}
