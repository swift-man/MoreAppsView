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

  /// Uses platform-specific presentation before handing off to a destination.
  ///
  /// On iOS, MoreAppsKit tries the app's deep link first and then presents an
  /// App Store overlay. On tvOS, it presents a full-screen app preview whose
  /// explicit action tries the installed app before falling back to the App
  /// Store URL.
  case platformPresentation
}
