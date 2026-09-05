//
//  MoreAppsSelectionBehavior.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/23/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation

/// The action MoreAppsKit takes after someone selects an app card.
public enum MoreAppsSelectionBehavior: Equatable, Sendable {
  /// Opens the installed app and falls back directly to its App Store URL.
  case directOpen

  /// Uses the system App Store presentation when the platform supports it.
  ///
  /// On iOS, MoreAppsKit tries the app's deep link first and then presents an
  /// App Store overlay. tvOS does not provide an equivalent presentation, so
  /// selection immediately tries the installed app before falling back to its
  /// App Store URL, matching ``directOpen``.
  case platformPresentation
}
