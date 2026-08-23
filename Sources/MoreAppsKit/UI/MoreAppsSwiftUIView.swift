//
//  MoreAppsSwiftUIView.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

#if canImport(SwiftUI)
  import SwiftUI

  /// A SwiftUI wrapper around the UIKit-based ``MoreAppsView``.
  @MainActor
  public struct MoreAppsSwiftUIView: UIViewRepresentable {
    private let apps: [MoreApp]
    private let configuration: MoreAppsConfiguration
    private let onEvent: ((MoreAppsEvent) -> Void)?

    /// Creates a SwiftUI More Apps view backed by `UICollectionView`.
    ///
    /// - Parameters:
    ///   - apps: The unfiltered app catalog.
    ///   - configuration: Visual and behavioral options.
    ///   - onEvent: An optional event callback.
    public init(
      apps: [MoreApp],
      configuration: MoreAppsConfiguration = .default,
      onEvent: ((MoreAppsEvent) -> Void)? = nil
    ) {
      self.apps = apps
      self.configuration = configuration
      self.onEvent = onEvent
    }

    /// State retained across SwiftUI updates to avoid resetting impressions.
    @MainActor
    public final class Coordinator {
      fileprivate var apps: [MoreApp] = []
      fileprivate var configuration: MoreAppsConfiguration?

      /// Creates an empty wrapper coordinator.
      public init() {}
    }

    /// Creates the wrapper coordinator.
    public func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    /// Creates the underlying UIKit view.
    public func makeUIView(context: Context) -> MoreAppsView {
      let view = MoreAppsView(configuration: configuration)
      view.onEvent = onEvent
      view.setApps(apps)
      context.coordinator.apps = apps
      context.coordinator.configuration = configuration
      return view
    }

    /// Synchronizes SwiftUI input with the underlying UIKit view.
    public func updateUIView(
      _ uiView: MoreAppsView,
      context: Context
    ) {
      uiView.onEvent = onEvent

      if context.coordinator.configuration != configuration {
        context.coordinator.configuration = configuration
        uiView.update(configuration: configuration)
      }

      if context.coordinator.apps != apps {
        context.coordinator.apps = apps
        uiView.setApps(apps)
      }
    }
  }
#endif
