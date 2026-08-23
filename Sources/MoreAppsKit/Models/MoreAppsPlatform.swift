//
//  MoreAppsPlatform.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation

/// A platform on which a promoted app can be installed.
public enum MoreAppsPlatform: String, Codable, Hashable, Sendable {
  /// Apple's iPhone and iPad operating system.
  case iOS

  /// Apple's television operating system.
  case tvOS

  /// The platform for which the package is currently being compiled.
  public static var current: Self {
    #if os(tvOS)
      return .tvOS
    #elseif os(iOS)
      return .iOS
    #else
      #error("MoreAppsKit supports only iOS and tvOS.")
    #endif
  }
}
