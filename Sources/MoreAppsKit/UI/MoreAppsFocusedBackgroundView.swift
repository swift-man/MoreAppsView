//
//  MoreAppsFocusedBackgroundView.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 9/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import UIKit

private let moreAppsDefaultDimmingAlpha: CGFloat = 0.46

private func moreAppsNormalizedDimmingAlpha(_ value: CGFloat) -> CGFloat {
  guard value.isFinite else { return moreAppsDefaultDimmingAlpha }
  return min(max(value, 0), 1)
}

private func moreAppsNormalizedTransitionDuration(
  _ value: TimeInterval
) -> TimeInterval {
  guard value.isFinite else { return 0 }
  return max(0, value)
}

/// A full-screen image view synchronized with the focused tvOS ``MoreAppsView`` card.
///
/// Add this view behind the rest of a host's interface and assign it to
/// ``MoreAppsView/focusedBackgroundView``. Artwork is loaded only when the
/// focused app's current-platform destination supplies a
/// ``MoreAppDestination/backgroundImageURL``. Stale work is cancelled when
/// focus changes, and transitions honor Reduce Motion.
@MainActor
public final class MoreAppsFocusedBackgroundView: UIView {
  typealias ImageProvider = @MainActor (URL, Int) async throws -> UIImage
  typealias TransitionPerformer =
    @MainActor (
      UIView,
      TimeInterval,
      @escaping () -> Void
    ) -> Void

  private let imageView = UIImageView()
  private let dimmingView = UIView()
  private let maximumPixelSize: Int
  private let transitionDuration: TimeInterval
  private let reduceMotionEnabled: @MainActor () -> Bool
  private let imageProvider: ImageProvider
  private let transitionPerformer: TransitionPerformer
  private var imageTask: Task<Void, Never>?
  private var requestedAppID: MoreApp.ID?
  private var requestedImageURL: URL?
  private var requestedRevision = 0
  private var renderedAppID: MoreApp.ID?
  private var requestGeneration: UInt = 0
  private var ownerID: UUID?

  var imageRequestDidStart: (() -> Void)?
  var imageRequestDidFinish: (() -> Void)?
  var ownerDetachmentDidFinish: ((Bool) -> Void)?

  /// Receives non-cancellation failures while loading focused artwork.
  ///
  /// MoreAppsKit does not log or transmit these errors. Use this callback for
  /// host diagnostics when artwork availability is operationally important.
  public var onImageLoadingFailure: ((URL, any Error) -> Void)?

  /// The opacity of the black overlay placed above focused artwork.
  ///
  /// Values are clamped to the range from zero through one. The default is
  /// `0.46`, which keeps foreground cards legible over bright screenshots.
  public var dimmingAlpha: CGFloat {
    didSet {
      dimmingAlpha = moreAppsNormalizedDimmingAlpha(dimmingAlpha)
      if imageView.image != nil {
        dimmingView.alpha = dimmingAlpha
      }
    }
  }

  /// Creates a focus-synchronized background view.
  ///
  /// - Parameters:
  ///   - maximumPixelSize: The requested maximum decoded image dimension.
  ///     Values are clamped to `1...4096`.
  ///   - dimmingAlpha: The opacity of the black foreground-legibility overlay.
  ///   - transitionDuration: The crossfade duration when Reduce Motion is off.
  public convenience init(
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

  /// Creates a focus-synchronized background view with an explicit loader.
  ///
  /// - Parameters:
  ///   - imageLoader: The Alamofire-backed loader used for artwork.
  ///   - maximumPixelSize: The requested maximum decoded image dimension.
  ///     Values are clamped to `1...4096`.
  ///   - dimmingAlpha: The opacity of the black foreground-legibility overlay.
  ///   - transitionDuration: The crossfade duration when Reduce Motion is off.
  public convenience init(
    imageLoader: MoreAppsImageLoader,
    maximumPixelSize: Int = 1_920,
    dimmingAlpha: CGFloat = 0.46,
    transitionDuration: TimeInterval = 0.35
  ) {
    self.init(
      maximumPixelSize: maximumPixelSize,
      dimmingAlpha: dimmingAlpha,
      transitionDuration: transitionDuration,
      reduceMotionEnabled: { UIAccessibility.isReduceMotionEnabled },
      transitionPerformer: { view, duration, changes in
        UIView.transition(
          with: view,
          duration: duration,
          options: [
            .transitionCrossDissolve,
            .beginFromCurrentState,
            .allowUserInteraction,
          ],
          animations: changes
        )
      },
      imageProvider: { url, maximumPixelSize in
        try await imageLoader.image(
          for: url,
          maximumPixelSize: maximumPixelSize
        )
      }
    )
  }

  init(
    maximumPixelSize: Int,
    dimmingAlpha: CGFloat,
    transitionDuration: TimeInterval,
    reduceMotionEnabled: @escaping @MainActor () -> Bool,
    transitionPerformer: @escaping TransitionPerformer,
    imageProvider: @escaping ImageProvider
  ) {
    self.maximumPixelSize = moreAppsClampedDecodedPixelSize(maximumPixelSize)
    self.dimmingAlpha = moreAppsNormalizedDimmingAlpha(dimmingAlpha)
    self.transitionDuration = moreAppsNormalizedTransitionDuration(
      transitionDuration
    )
    self.reduceMotionEnabled = reduceMotionEnabled
    self.transitionPerformer = transitionPerformer
    self.imageProvider = imageProvider

    super.init(frame: .zero)

    setUpViews()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError(
      "MoreAppsFocusedBackgroundView supports programmatic initialization only."
    )
  }

  deinit {
    imageTask?.cancel()
  }

  func display(
    appID: MoreApp.ID?,
    imageURL: URL?,
    requestRevision: Int = 0,
    ownerID: UUID? = nil,
    animated: Bool = true
  ) {
    guard ownerID == nil || self.ownerID == ownerID else { return }

    guard
      requestedAppID != appID
        || requestedImageURL != imageURL
        || requestedRevision != requestRevision
    else {
      return
    }

    imageTask?.cancel()
    imageTask = nil
    requestGeneration &+= 1
    let generation = requestGeneration
    requestedAppID = appID
    requestedImageURL = imageURL
    requestedRevision = requestRevision

    guard let appID, let imageURL else {
      setImage(nil, appID: nil, animated: animated)
      return
    }

    imageTask = Task { [weak self, imageProvider, maximumPixelSize] in
      defer { self?.imageRequestDidFinish?() }

      do {
        let image = try await imageProvider(imageURL, maximumPixelSize)
        try Task.checkCancellation()
        guard let self,
          self.requestGeneration == generation,
          self.requestedAppID == appID,
          self.requestedImageURL == imageURL
        else {
          return
        }
        self.imageTask = nil
        self.setImage(image, appID: appID, animated: animated)
      } catch is CancellationError {
        guard let self,
          self.requestGeneration == generation,
          self.requestedAppID == appID,
          self.requestedImageURL == imageURL,
          self.requestedRevision == requestRevision
        else {
          return
        }
        self.imageTask = nil
        self.setImage(nil, appID: nil, animated: animated)
      } catch {
        guard let self,
          self.requestGeneration == generation,
          self.requestedAppID == appID,
          self.requestedImageURL == imageURL,
          self.requestedRevision == requestRevision
        else {
          return
        }
        self.imageTask = nil
        self.onImageLoadingFailure?(imageURL, error)
        self.setImage(nil, appID: nil, animated: animated)
      }
    }
    imageRequestDidStart?()
  }

  func attach(ownerID: UUID) {
    self.ownerID = ownerID
  }

  func detach(ownerID: UUID) {
    guard self.ownerID == ownerID else {
      ownerDetachmentDidFinish?(false)
      return
    }
    self.ownerID = nil
    display(appID: nil, imageURL: nil, animated: false)
    ownerDetachmentDidFinish?(true)
  }

  var displayedImage: UIImage? {
    imageView.image
  }

  var displayedAppID: MoreApp.ID? {
    renderedAppID
  }

  var isLoadingImage: Bool {
    imageTask != nil
  }

  var dimmingOpacity: CGFloat {
    dimmingView.alpha
  }

  private func setUpViews() {
    backgroundColor = .clear
    clipsToBounds = true
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    accessibilityElementsHidden = true

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    addSubview(imageView)

    dimmingView.translatesAutoresizingMaskIntoConstraints = false
    dimmingView.backgroundColor = .black
    dimmingView.alpha = 0
    addSubview(dimmingView)

    NSLayoutConstraint.activate([
      imageView.topAnchor.constraint(equalTo: topAnchor),
      imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
      imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
      dimmingView.topAnchor.constraint(equalTo: topAnchor),
      dimmingView.leadingAnchor.constraint(equalTo: leadingAnchor),
      dimmingView.trailingAnchor.constraint(equalTo: trailingAnchor),
      dimmingView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  private func setImage(
    _ image: UIImage?,
    appID: MoreApp.ID?,
    animated: Bool
  ) {
    renderedAppID = image == nil ? nil : appID
    let targetDimmingAlpha = image == nil ? 0 : dimmingAlpha
    guard
      imageView.image !== image
        || dimmingView.alpha != targetDimmingAlpha
    else {
      return
    }

    let changes = {
      self.imageView.image = image
      self.dimmingView.alpha = targetDimmingAlpha
    }
    guard animated,
      transitionDuration > 0,
      !reduceMotionEnabled()
    else {
      layer.removeAllAnimations()
      changes()
      return
    }

    transitionPerformer(self, transitionDuration, changes)
  }
}
