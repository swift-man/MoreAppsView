//
//  MoreAppsDefaultBackgroundCatalog.swift
//  MoreAppsKit
//
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation

/// Fixed first App Store screenshots for the package's supported catalog entries.
enum MoreAppsDefaultBackgroundCatalog {
  private static let images: [String: [MoreAppsPlatform: URL]] = {
    guard let url = Bundle.module.url(forResource: "DefaultBackgrounds", withExtension: "json") else {
      assertionFailure("DefaultBackgrounds.json is missing from the package bundle.")
      return [:]
    }
    do {
      return try decode(Data(contentsOf: url))
    } catch {
      assertionFailure("DefaultBackgrounds.json could not be loaded: \(error)")
      return [:]
    }
  }()

  static func imageURL(bundleIdentifier: String, platform: MoreAppsPlatform) -> URL? {
    images[bundleIdentifier]?[platform]
  }

  /// Validates platform keys before a bundled catalog can enter the lookup table.
  static func decode(_ data: Data) throws -> [String: [MoreAppsPlatform: URL]] {
    let raw = try JSONDecoder().decode([String: [String: URL]].self, from: data)
    return try raw.mapValues { entries in
      var images: [MoreAppsPlatform: URL] = [:]
      for (key, url) in entries {
        guard let platform = MoreAppsPlatform(rawValue: key) else {
          throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Unknown background platform: \(key)"))
        }
        images[platform] = url
      }
      return images
    }
  }
}
