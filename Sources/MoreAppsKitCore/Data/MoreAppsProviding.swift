//
//  MoreAppsProviding.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation

/// A source capable of asynchronously supplying app promotion metadata.
public protocol MoreAppsProviding: Sendable {
  /// Fetches the unfiltered app catalog.
  ///
  /// - Returns: App metadata that MoreAppsKit will filter for the host.
  func fetchApps() async throws -> [MoreApp]
}

/// A sendable closure-based provider used at TCA effect boundaries.
struct MoreAppsProviderClient: MoreAppsProviding, Sendable {
  private let fetch: @Sendable () async throws -> [MoreApp]

  /// Creates a provider client from an asynchronous operation.
  ///
  /// - Parameter fetch: The operation that supplies an app catalog.
  init(
    fetch: @escaping @Sendable () async throws -> [MoreApp]
  ) {
    self.fetch = fetch
  }

  /// Creates a client that forwards to another provider.
  ///
  /// - Parameter provider: The provider to wrap.
  init(_ provider: any MoreAppsProviding) {
    self.fetch = {
      try await provider.fetchApps()
    }
  }

  /// Fetches the unfiltered app catalog.
  func fetchApps() async throws -> [MoreApp] {
    try await fetch()
  }
}
