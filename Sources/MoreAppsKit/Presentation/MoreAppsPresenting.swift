//
//  MoreAppsPresenting.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/23/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Dependencies
import Foundation

/// The information required to present an App Store destination.
public struct MoreAppsPresentationRequest: Equatable, Sendable {
  /// The app whose destination should be presented.
  public let app: MoreApp

  /// The platform-specific destination being presented.
  public let destination: MoreAppDestination

  /// The numeric App Store identifier used by the system presentation UI.
  public let appStoreIdentifier: String?

  /// Creates an App Store presentation request.
  ///
  /// - Parameters:
  ///   - app: The app whose destination should be presented.
  ///   - destination: The platform-specific destination being presented.
  ///   - appStoreIdentifier: The numeric App Store identifier, when available.
  public init(
    app: MoreApp,
    destination: MoreAppDestination,
    appStoreIdentifier: String?
  ) {
    self.app = app
    self.destination = destination
    self.appStoreIdentifier = appStoreIdentifier
  }
}

/// The result of presenting an App Store destination.
public enum MoreAppsPresentationOutcome: Equatable, Sendable {
  /// The user requested that MoreAppsKit open the App Store destination.
  case appStoreRequested

  /// The presentation lifecycle ended without requesting a URL handoff.
  case dismissed

  /// The presentation could not be started or loaded.
  ///
  /// iOS may fall back to the validated App Store URL. tvOS treats this as a
  /// failure and does not perform a URL handoff.
  case failed
}

/// An object that presents platform-appropriate App Store UI.
@MainActor
public protocol MoreAppsPresenting: AnyObject, Sendable {
  /// Presents the destination described by a request.
  ///
  /// Keep this operation suspended until the presentation lifecycle ends. This
  /// lets MoreAppsKit cancel stale UI when its catalog or configuration changes.
  /// When the task is cancelled, dismiss any active UI and return
  /// ``MoreAppsPresentationOutcome/dismissed``.
  /// Return ``MoreAppsPresentationOutcome/appStoreRequested`` only when the
  /// package should perform the validated App Store URL handoff.
  ///
  /// - Parameter request: The app and destination to present.
  /// - Returns: The outcome reported by the presentation UI.
  func present(
    _ request: MoreAppsPresentationRequest
  ) async -> MoreAppsPresentationOutcome
}

@MainActor
final class MoreAppsPresentationRelay: MoreAppsPresenting {
  var presenter: (any MoreAppsPresenting)?

  init(presenter: (any MoreAppsPresenting)? = nil) {
    self.presenter = presenter
  }

  func present(
    _ request: MoreAppsPresentationRequest
  ) async -> MoreAppsPresentationOutcome {
    guard let presenter else { return .failed }
    return await presenter.present(request)
  }
}

/// A dependency client that exposes App Store presentation to a TCA reducer.
struct MoreAppsPresentationClient: Sendable {
  private let presentRequest:
    @MainActor @Sendable (
      MoreAppsPresentationRequest
    ) async -> MoreAppsPresentationOutcome

  /// Creates a client from a presentation operation.
  ///
  /// - Parameter present: The operation to invoke.
  init(
    present:
      @escaping @MainActor @Sendable (
        MoreAppsPresentationRequest
      ) async -> MoreAppsPresentationOutcome
  ) {
    self.presentRequest = present
  }

  /// Creates a client that forwards to a presenter object.
  ///
  /// - Parameter presenter: The presenter to wrap, or `nil` to disable
  ///   platform presentation.
  @MainActor
  init(presenter: (any MoreAppsPresenting)?) {
    self.presentRequest = { request in
      guard let presenter else { return .failed }
      return await presenter.present(request)
    }
  }

  /// Presents a platform-appropriate App Store destination.
  ///
  /// - Parameter request: The app and destination to present.
  /// - Returns: The outcome reported by the presentation UI.
  @MainActor
  func callAsFunction(
    _ request: MoreAppsPresentationRequest
  ) async -> MoreAppsPresentationOutcome {
    guard !Task.isCancelled else { return .dismissed }
    return await presentRequest(request)
  }
}

extension MoreAppsPresentationClient: DependencyKey {
  /// A safe live default that does not assume a presentation host.
  static let liveValue = MoreAppsPresentationClient { _ in .failed }

  /// A safe test default that never presents user interface.
  static let testValue = MoreAppsPresentationClient { _ in .failed }
}

extension DependencyValues {
  /// The App Store presentation dependency used by ``MoreAppsFeature``.
  var moreAppsPresentation: MoreAppsPresentationClient {
    get { self[MoreAppsPresentationClient.self] }
    set { self[MoreAppsPresentationClient.self] = newValue }
  }
}
