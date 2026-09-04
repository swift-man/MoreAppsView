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
    private let presenter: (any MoreAppsPresenting)?
    private let onEvent: ((MoreAppsEvent) -> Void)?
    private let imageLoader: any MoreAppsImageLoading

    /// Creates a SwiftUI More Apps view backed by `UICollectionView`.
    ///
    /// - Parameters:
    ///   - apps: The unfiltered app catalog.
    ///   - configuration: Visual and behavioral options.
    ///   - presenter: An optional platform presentation implementation.
    ///   - onEvent: An optional event callback.
    public init(
      apps: [MoreApp],
      configuration: MoreAppsConfiguration = .default,
      presenter: (any MoreAppsPresenting)? = nil,
      onEvent: ((MoreAppsEvent) -> Void)? = nil,
      imageLoader: any MoreAppsImageLoading
    ) {
      self.apps = apps
      self.configuration = configuration
      self.presenter = presenter
      self.onEvent = onEvent
      self.imageLoader = imageLoader
    }

    /// State retained across SwiftUI updates to avoid resetting impressions.
    @MainActor
    public final class Coordinator {
      fileprivate var apps: [MoreApp] = []
      fileprivate var configuration: MoreAppsConfiguration?
      fileprivate var imageLoader: (any MoreAppsImageLoading)?
      fileprivate let presentationRelay = MoreAppsPresentationRelay()

      /// Creates an empty wrapper coordinator.
      public init() {}
    }

    /// Creates the wrapper coordinator.
    public func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    /// Creates the underlying UIKit view.
    public func makeUIView(context: Context) -> MoreAppsView {
      context.coordinator.presentationRelay.presenter = presenter
      let view = MoreAppsView(
        configuration: configuration,
        opener: DefaultMoreAppsOpener.shared,
        presenter: context.coordinator.presentationRelay,
        imageLoader: imageLoader
      )
      view.onEvent = onEvent
      view.setApps(apps)
      context.coordinator.apps = apps
      context.coordinator.configuration = configuration
      context.coordinator.imageLoader = imageLoader
      return view
    }

    /// Synchronizes SwiftUI input with the underlying UIKit view.
    public func updateUIView(
      _ uiView: MoreAppsView,
      context: Context
    ) {
      uiView.onEvent = onEvent
      context.coordinator.presentationRelay.presenter = presenter

      if context.coordinator.imageLoader !== imageLoader {
        context.coordinator.imageLoader = imageLoader
        uiView.update(imageLoader: imageLoader)
      }

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
