//
//  MoreAppsImageLoading.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 9/5/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import UIKit

/// Loads remote artwork for MoreAppsKit UI components.
///
/// The core product depends only on this protocol. The Alamofire-backed
/// `MoreAppsImageLoader` implementation is provided by the optional
/// `MoreAppsKitNetworking` product.
@MainActor
public protocol MoreAppsImageLoading: AnyObject {
  /// Returns a decoded image for the supplied URL.
  func image(for url: URL) async throws -> UIImage

  /// Returns a decoded image constrained to the requested pixel dimension.
  func image(
    for url: URL,
    maximumPixelSize: Int
  ) async throws -> UIImage
}
