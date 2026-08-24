//
//  MoreAppsURLPolicy.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation

enum MoreAppsURLPolicy {
  static func allowedDeepLink(
    _ url: URL?,
    allowedCustomSchemes: Set<String>
  ) -> URL? {
    guard let url,
      let scheme = url.scheme?.lowercased(),
      !scheme.isEmpty
    else {
      return nil
    }

    if scheme == "https" {
      return allowedAppStoreURL(url) == nil ? url : nil
    }

    guard scheme != "http" else { return nil }

    return allowedCustomSchemes.contains(scheme) ? url : nil
  }

  static func allowedAppStoreURL(_ url: URL) -> URL? {
    guard let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "itms-apps",
      let host = url.host?.lowercased(),
      host == "apps.apple.com"
        || host == "itunes.apple.com"
        || host.hasSuffix(".itunes.apple.com")
    else {
      return nil
    }
    return url
  }

  static func appStoreIdentifier(from url: URL) -> String? {
    guard allowedAppStoreURL(url) != nil,
      let components = URLComponents(
        url: url,
        resolvingAgainstBaseURL: false
      )
    else {
      return nil
    }

    let identifiers = components.percentEncodedPath.split(separator: "/")
      .compactMap { component -> String? in
        guard component.hasPrefix("id") else { return nil }

        let identifier = component.dropFirst(2)
        guard !identifier.isEmpty,
          identifier.utf8.allSatisfy({ (48...57).contains($0) }),
          identifier.utf8.contains(where: { $0 != 48 })
        else {
          return nil
        }

        return String(identifier)
      }

    guard identifiers.count == 1 else {
      return nil
    }

    return identifiers[0]
  }
}
