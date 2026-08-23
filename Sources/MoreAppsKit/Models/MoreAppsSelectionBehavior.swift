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

  /// Uses the platform's recommended presentation before handing off to the store.
  ///
  /// On iOS, MoreAppsKit tries the app's deep link first and then presents an
  /// App Store overlay. On tvOS, it presents an app-detail sheet with an
  /// explicit App Store action.
  case platformPresentation
}
