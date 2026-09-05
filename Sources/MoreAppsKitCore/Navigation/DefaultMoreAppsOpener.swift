//
//  DefaultMoreAppsOpener.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import UIKit

/// The production URL opener backed by `UIApplication.shared.open`.
@MainActor
public final class DefaultMoreAppsOpener: MoreAppsOpening {
  /// The shared stateless opener.
  public static let shared = DefaultMoreAppsOpener()

  /// Creates a system URL opener.
  public init() {}

  /// Attempts to open a URL through `UIApplication`.
  ///
  /// This deliberately does not call `canOpenURL`, so the host app does not
  /// need to add queried URL schemes to its `Info.plist`.
  public func open(_ url: URL) async -> Bool {
    let options: [UIApplication.OpenExternalURLOptionsKey: Any] =
      Self.usesUniversalLinksOnly(for: url)
      ? [.universalLinksOnly: true]
      : [:]

    return await withCheckedContinuation { continuation in
      UIApplication.shared.open(
        url,
        options: options
      ) { didOpen in
        continuation.resume(returning: didOpen)
      }
    }
  }

  static func usesUniversalLinksOnly(for url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https" else { return false }

    let host = url.host?.lowercased()
    let isAppStoreHost =
      host == "apps.apple.com"
      || host == "itunes.apple.com"
      || host?.hasSuffix(".itunes.apple.com") == true
    return !isAppStoreHost
  }
}
