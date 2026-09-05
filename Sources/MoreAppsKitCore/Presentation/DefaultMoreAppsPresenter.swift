//
//  DefaultMoreAppsPresenter.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/23/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation
#if os(iOS)
  import StoreKit
#endif
import UIKit

/// Presents the system App Store overlay on iOS.
///
/// tvOS selections bypass presentation and use the URL-opening dependency
/// directly, so this presenter does not display UI on tvOS.
@MainActor
public final class DefaultMoreAppsPresenter: NSObject, MoreAppsPresenting {
  private weak var presentingViewController: UIViewController?
  private var pendingPresentationID: UUID?
  private var pendingContinuation:
    CheckedContinuation<
      MoreAppsPresentationOutcome,
      Never
    >?

  #if os(iOS)
    private var activeOverlay: SKOverlay?
    private weak var activeWindowScene: UIWindowScene?
    private var overlayCancellationState = MoreAppsOverlayCancellationState()
  #endif

  /// Creates a presenter hosted by a view controller.
  ///
  /// The presenter keeps a weak reference to the host. Keep both objects alive
  /// for as long as a presentation may be active.
  ///
  /// - Parameter presentingViewController: The view controller whose window and
  ///   modal presentation context should be used.
  public init(
    presentingViewController: UIViewController
  ) {
    self.presentingViewController = presentingViewController
    super.init()
  }

  /// Creates a presenter hosted by a view controller while accepting a legacy
  /// image-loader argument.
  ///
  /// tvOS no longer presents package-owned artwork. This initializer remains
  /// available for source compatibility and delegates to
  /// ``init(presentingViewController:)``.
  ///
  /// - Parameters:
  ///   - presentingViewController: The view controller whose window and modal
  ///     presentation context should be used.
  ///   - imageLoader: An unused legacy image-loader argument.
  @available(
    *,
    deprecated,
    message: "Use init(presentingViewController:) instead."
  )
  public convenience init(
    presentingViewController: UIViewController,
    imageLoader: any MoreAppsImageLoading
  ) {
    _ = imageLoader
    self.init(presentingViewController: presentingViewController)
  }

  /// Presents the system App Store experience when the platform supports it.
  ///
  /// - Parameter request: The app and destination to present.
  /// - Returns: The outcome reported by StoreKit, or `failed` on tvOS where
  ///   package-owned presentation is intentionally disabled.
  public func present(
    _ request: MoreAppsPresentationRequest
  ) async -> MoreAppsPresentationOutcome {
    guard !Task.isCancelled else { return .dismissed }

    #if os(tvOS)
      _ = request
      return .failed
    #else
      if activeOverlay != nil {
        return overlayCancellationState.overlappingPresentationOutcome
      }

      guard
        let host = presentingViewController,
        host.presentedViewController == nil,
        let scene = host.viewIfLoaded?.window?.windowScene,
        scene.activationState == .foregroundActive
      else {
        return .failed
      }

      guard
        let appStoreIdentifier = request.appStoreIdentifier,
        !appStoreIdentifier.isEmpty
      else {
        return .failed
      }

      let presentationID = UUID()
      return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          pendingPresentationID = presentationID
          pendingContinuation = continuation

          presentOverlay(
            appStoreIdentifier: appStoreIdentifier,
            in: scene
          )

          if Task.isCancelled {
            cancelPresentation(id: presentationID)
          }
        }
      } onCancel: { [weak self] in
        Task { @MainActor in
          self?.cancelPresentation(id: presentationID)
        }
      }
    #endif
  }

  private func finishPendingPresentation(
    id: UUID,
    outcome: MoreAppsPresentationOutcome
  ) {
    guard pendingPresentationID == id else { return }

    let continuation = pendingContinuation
    pendingPresentationID = nil
    pendingContinuation = nil
    continuation?.resume(returning: outcome)
  }

  private func cancelPresentation(id: UUID) {
    guard pendingPresentationID == id else { return }

    #if os(iOS)
      guard overlayCancellationState.requestDismissal() else { return }

      guard activeOverlay != nil, let activeWindowScene else {
        finishActiveOverlay(outcome: .dismissed)
        return
      }

      SKOverlay.dismiss(in: activeWindowScene)
    #endif
  }

  #if os(iOS)
    private func presentOverlay(
      appStoreIdentifier: String,
      in scene: UIWindowScene
    ) {
      let configuration = SKOverlay.AppConfiguration(
        appIdentifier: appStoreIdentifier,
        position: .bottom
      )
      configuration.userDismissible = true

      let overlay = SKOverlay(configuration: configuration)
      overlay.delegate = self
      overlayCancellationState.beginPresentation()
      activeOverlay = overlay
      activeWindowScene = scene
      overlay.present(in: scene)
    }

    private func overlayDidFail(_ overlay: SKOverlay) {
      guard activeOverlay === overlay else { return }

      finishActiveOverlay(outcome: .failed)
    }

    private func overlayDidFinishDismissal(_ overlay: SKOverlay) {
      guard activeOverlay === overlay else { return }

      finishActiveOverlay(outcome: .dismissed)
    }

    private func finishActiveOverlay(
      outcome: MoreAppsPresentationOutcome
    ) {
      guard
        let resolvedOutcome = overlayCancellationState.finish(
          with: outcome
        )
      else {
        return
      }

      let presentationID = pendingPresentationID
      activeOverlay = nil
      activeWindowScene = nil
      if let presentationID {
        finishPendingPresentation(
          id: presentationID,
          outcome: resolvedOutcome
        )
      }
    }
  #endif
}

#if os(iOS)
  extension DefaultMoreAppsPresenter: SKOverlayDelegate {
    /// Handles a StoreKit overlay loading failure.
    public nonisolated func storeOverlayDidFailToLoad(
      _ overlay: SKOverlay,
      error: any Error
    ) {
      let overlayIdentifier = ObjectIdentifier(overlay)
      Task { @MainActor [weak self] in
        guard
          let overlay = self?.activeOverlay,
          ObjectIdentifier(overlay) == overlayIdentifier
        else {
          return
        }
        self?.overlayDidFail(overlay)
      }
    }

    /// Handles completion of the StoreKit overlay dismissal transition.
    public nonisolated func storeOverlayDidFinishDismissal(
      _ overlay: SKOverlay,
      transitionContext: SKOverlay.TransitionContext
    ) {
      let overlayIdentifier = ObjectIdentifier(overlay)
      Task { @MainActor [weak self] in
        guard
          let overlay = self?.activeOverlay,
          ObjectIdentifier(overlay) == overlayIdentifier
        else {
          return
        }
        self?.overlayDidFinishDismissal(overlay)
      }
    }
  }
#endif

#if os(iOS)
  struct MoreAppsOverlayCancellationState {
    private enum Phase {
      case idle
      case active
      case dismissalRequested
    }

    private var phase = Phase.idle

    var isDismissalRequested: Bool {
      if case .dismissalRequested = phase {
        return true
      }
      return false
    }

    var overlappingPresentationOutcome: MoreAppsPresentationOutcome {
      // A new selection must continue to the validated App Store URL instead
      // of being silently treated as a user dismissal while the old overlay
      // is finishing its dismissal transition.
      .failed
    }

    mutating func beginPresentation() {
      phase = .active
    }

    mutating func requestDismissal() -> Bool {
      guard case .active = phase else { return false }

      phase = .dismissalRequested
      return true
    }

    mutating func finish(
      with outcome: MoreAppsPresentationOutcome
    ) -> MoreAppsPresentationOutcome? {
      switch phase {
      case .idle:
        return nil
      case .active:
        phase = .idle
        return outcome
      case .dismissalRequested:
        phase = .idle
        return .dismissed
      }
    }
  }
#endif
