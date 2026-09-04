//
//  CompatibilityInitializers.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 9/5/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import MoreAppsKitCore
import MoreAppsNetworking
import UIKit

@MainActor
public extension MoreAppsView {
  /// Creates a More Apps view using the package's Alamofire-backed loader.
  ///
  /// This compatibility initializer is available from the umbrella
  /// `MoreAppsKit` product. Use ``MoreAppsKitCore`` with an explicit
  /// ``MoreAppsImageLoading`` implementation when Alamofire is not needed.
  ///
  /// - Parameter configuration: Visual and behavioral options for the view.
  convenience init(configuration: MoreAppsConfiguration = .default) {
    self.init(
      configuration: configuration,
      opener: DefaultMoreAppsOpener.shared,
      presenter: nil,
      imageLoader: MoreAppsImageLoader.shared
    )
  }

  /// Creates a More Apps view with the package's platform presenter.
  ///
  /// - Parameters:
  ///   - configuration: Visual and behavioral options for the view.
  ///   - presentingViewController: The controller that owns the presentation context.
  convenience init(
    configuration: MoreAppsConfiguration = .default,
    presentingViewController: UIViewController
  ) {
    self.init(
      configuration: configuration,
      opener: DefaultMoreAppsOpener.shared,
      presenter: DefaultMoreAppsPresenter(
        presentingViewController: presentingViewController
      ),
      imageLoader: MoreAppsImageLoader.shared
    )
  }
}

@MainActor
public extension MoreAppsFocusedBackgroundView {
  /// Creates a focus-synchronized background using the package's loader.
  ///
  /// - Parameters:
  ///   - maximumPixelSize: The requested maximum decoded image dimension.
  ///   - dimmingAlpha: The opacity of the foreground-legibility overlay.
  ///   - transitionDuration: The crossfade duration when Reduce Motion is off.
  convenience init(
    maximumPixelSize: Int = 1_920,
    dimmingAlpha: CGFloat = 0.46,
    transitionDuration: TimeInterval = 0.35
  ) {
    self.init(
      imageLoader: MoreAppsImageLoader.shared,
      maximumPixelSize: maximumPixelSize,
      dimmingAlpha: dimmingAlpha,
      transitionDuration: transitionDuration
    )
  }
}

@MainActor
public extension MoreAppsSwiftUIView {
  /// Creates a SwiftUI More Apps view using the package's artwork loader.
  ///
  /// - Parameters:
  ///   - apps: The unfiltered app catalog.
  ///   - configuration: Visual and behavioral options for the view.
  ///   - presenter: An optional platform presentation implementation.
  ///   - onEvent: An optional event callback.
  init(
    apps: [MoreApp],
    configuration: MoreAppsConfiguration = .default,
    presenter: (any MoreAppsPresenting)? = nil,
    onEvent: ((MoreAppsEvent) -> Void)? = nil
  ) {
    self.init(
      apps: apps,
      configuration: configuration,
      presenter: presenter,
      onEvent: onEvent,
      imageLoader: MoreAppsImageLoader.shared
    )
  }
}
