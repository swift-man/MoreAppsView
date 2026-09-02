//
//  MoreAppsView.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import ComposableArchitecture
import UIKit

/// A reusable, horizontally scrolling UIKit view for cross-promoting apps.
///
/// The view filters all input through the current platform and bundle identifier,
/// renders changes with a diffable data source, and owns no view-controller state.
@MainActor
public final class MoreAppsView: UIView {
  private enum Section {
    case main
  }

  /// Receives analytics-neutral interaction and loading events.
  ///
  /// MoreAppsKit does not collect, persist, or transmit these events itself.
  /// Up to the 100 most recent undelivered events are retained temporarily in
  /// memory and delivered when a handler becomes available.
  public var onEvent: ((MoreAppsEvent) -> Void)? {
    didSet { scheduleEventDeliveryIfNeeded() }
  }

  /// A host-owned full-screen view that displays the focused app's artwork.
  ///
  /// Place the background view behind the host interface before assigning it.
  /// MoreAppsView keeps only a weak reference and synchronizes tvOS Focus Engine
  /// changes with the current destination's
  /// ``MoreAppDestination/backgroundImageURL``.
  public weak var focusedBackgroundView: MoreAppsFocusedBackgroundView? {
    didSet {
      guard oldValue !== focusedBackgroundView else { return }
      oldValue?.display(appID: nil, imageURL: nil, animated: false)
      renderFocusedBackground(appID: store.focusedAppID)
    }
  }

  private var configuration: MoreAppsConfiguration
  private let imageLoader: MoreAppsImageLoader
  private let flowLayout: UICollectionViewFlowLayout
  private let collectionView: UICollectionView
  private let titleLabel = UILabel()
  private let store: StoreOf<MoreAppsFeature>
  private var dataSource: UICollectionViewDiffableDataSource<Section, MoreApp.ID>!
  private var provider: MoreAppsProviderClient?
  private var currentApps: [MoreApp.ID: MoreApp] = [:]
  private var currentOrderedApps: [MoreApp] = []
  private var hasAppliedSnapshot = false
  private var eventDeliveryTask: Task<Void, Never>?
  private var collectionHeightConstraint: NSLayoutConstraint!
  private var titleLeadingConstraint: NSLayoutConstraint!
  private var titleTrailingConstraint: NSLayoutConstraint!
  private var titleTopConstraint: NSLayoutConstraint!
  private var collectionTopToTitleConstraint: NSLayoutConstraint!
  private var collectionTopConstraint: NSLayoutConstraint!

  /// Creates a More Apps view using live host and URL-opening dependencies.
  ///
  /// - Parameter configuration: Visual and behavioral options for the view.
  public convenience init(
    configuration: MoreAppsConfiguration = .default
  ) {
    self.init(
      configuration: configuration,
      opener: DefaultMoreAppsOpener.shared,
      presenter: nil,
      imageLoader: .shared
    )
  }

  /// Creates a More Apps view with the package's platform presenter.
  ///
  /// Use this initializer with ``MoreAppsSelectionBehavior/platformPresentation``
  /// to present an App Store overlay on iOS. tvOS always opens its validated
  /// app or App Store destination immediately and does not present package UI.
  /// The presenter keeps only a weak reference to the supplied view controller.
  ///
  /// - Parameters:
  ///   - configuration: Visual and behavioral options for the view.
  ///   - presentingViewController: The controller that owns the presentation context.
  public convenience init(
    configuration: MoreAppsConfiguration = .default,
    presentingViewController: UIViewController
  ) {
    let imageLoader = MoreAppsImageLoader.shared
    self.init(
      configuration: configuration,
      opener: DefaultMoreAppsOpener.shared,
      presenter: DefaultMoreAppsPresenter(
        presentingViewController: presentingViewController
      ),
      imageLoader: imageLoader
    )
  }

  /// Creates a More Apps view with explicit testable collaborators.
  ///
  /// - Parameters:
  ///   - configuration: Visual and behavioral options for the view.
  ///   - opener: The object used for deep links and App Store URLs.
  ///   - imageLoader: The loader used for remote app icons.
  public convenience init(
    configuration: MoreAppsConfiguration,
    opener: any MoreAppsOpening,
    imageLoader: MoreAppsImageLoader
  ) {
    self.init(
      configuration: configuration,
      opener: opener,
      presenter: nil,
      imageLoader: imageLoader
    )
  }

  /// Creates a More Apps view with explicit testable collaborators.
  ///
  /// - Parameters:
  ///   - configuration: Visual and behavioral options for the view.
  ///   - opener: The object used for deep links and App Store URLs.
  ///   - presenter: An optional platform presentation implementation. In
  ///     platform-presentation mode, iOS falls back to `opener` when it is
  ///     absent or fails. tvOS bypasses this collaborator and opens its
  ///     destination immediately.
  ///   - imageLoader: The loader used for remote app icons.
  public init(
    configuration: MoreAppsConfiguration,
    opener: any MoreAppsOpening,
    presenter: (any MoreAppsPresenting)?,
    imageLoader: MoreAppsImageLoader
  ) {
    self.configuration = configuration
    self.imageLoader = imageLoader

    let flowLayout = UICollectionViewFlowLayout()
    flowLayout.scrollDirection = .horizontal
    flowLayout.minimumInteritemSpacing = configuration.cardSpacing
    flowLayout.minimumLineSpacing = configuration.cardSpacing
    self.flowLayout = flowLayout
    self.collectionView = UICollectionView(
      frame: .zero,
      collectionViewLayout: flowLayout
    )

    let store = Store(
      initialState: MoreAppsFeature.State(
        maximumNumberOfItems: configuration.maximumNumberOfItems,
        allowedCustomDeepLinkSchemes: configuration
          .allowedCustomDeepLinkSchemes,
        selectionBehavior: configuration.selectionBehavior
      )
    ) {
      MoreAppsFeature()
    } withDependencies: {
      $0.moreAppsEnvironment = .live
      $0.moreAppsOpen = MoreAppsOpenClient(opener: opener)
      $0.moreAppsPresentation = MoreAppsPresentationClient(
        presenter: presenter
      )
    }
    self.store = store

    super.init(frame: .zero)

    setUpViews()
    configureDataSource()
    bindStore()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("MoreAppsView supports programmatic initialization only.")
  }

  deinit {
    eventDeliveryTask?.cancel()
  }

  /// Replaces the current catalog with app metadata supplied directly in code.
  ///
  /// This begins a new impression session and cancels an in-progress provider load.
  ///
  /// - Parameter apps: The unfiltered app catalog.
  public func setApps(_ apps: [MoreApp]) {
    provider = nil
    store.send(.setApps(apps))
  }

  /// Loads and displays an app catalog from a provider.
  ///
  /// A subsequent call to ``reload()`` uses the same provider. Starting another
  /// load cancels the prior load effect.
  ///
  /// - Parameter provider: The catalog source to fetch.
  public func load(using provider: any MoreAppsProviding) async {
    let client = MoreAppsProviderClient(provider)
    self.provider = client
    await store.send(.load(client)).finish()
  }

  /// Reloads the most recently supplied provider.
  ///
  /// This method does nothing until ``load(using:)`` has supplied a provider.
  public func reload() async {
    guard let provider else { return }
    await store.send(.load(provider)).finish()
  }

  func update(configuration newConfiguration: MoreAppsConfiguration) {
    guard configuration != newConfiguration else {
      return
    }

    let previousMaximum = configuration.maximumNumberOfItems
    let previousAllowedSchemes = configuration.allowedCustomDeepLinkSchemes
    let previousSelectionBehavior = configuration.selectionBehavior
    configuration = newConfiguration

    titleLabel.text =
      configuration.title
      ?? String(
        localized: "more_apps_title",
        bundle: .module
      )
    titleLabel.isHidden = !configuration.showsTitle
    titleLeadingConstraint.constant = configuration.contentInsets.leading
    titleTrailingConstraint.constant = -configuration.contentInsets.trailing
    updateTitleLayoutConstraints()
    flowLayout.minimumInteritemSpacing = configuration.cardSpacing
    flowLayout.minimumLineSpacing = configuration.cardSpacing
    isHidden = configuration.hidesWhenEmpty && currentOrderedApps.isEmpty

    if previousMaximum != configuration.maximumNumberOfItems {
      store.send(
        .setMaximumNumberOfItems(configuration.maximumNumberOfItems)
      )
    }

    if previousAllowedSchemes != configuration.allowedCustomDeepLinkSchemes {
      store.send(
        .setAllowedCustomDeepLinkSchemes(
          configuration.allowedCustomDeepLinkSchemes
        )
      )
    }

    if previousSelectionBehavior != configuration.selectionBehavior {
      store.send(
        .setSelectionBehavior(configuration.selectionBehavior)
      )
    }

    reconfigureCurrentItems()
    setNeedsLayout()
  }

  /// Updates platform-specific card metrics after the view's bounds change.
  public override func layoutSubviews() {
    super.layoutSubviews()
    updateLayoutMetrics()
  }

  private func setUpViews() {
    clipsToBounds = false
    isHidden = configuration.hidesWhenEmpty

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = .preferredFont(forTextStyle: .title3)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = .label
    titleLabel.numberOfLines = 0
    titleLabel.text =
      configuration.title
      ?? String(
        localized: "more_apps_title",
        bundle: .module
      )
    titleLabel.isHidden = !configuration.showsTitle
    addSubview(titleLabel)

    collectionView.translatesAutoresizingMaskIntoConstraints = false
    collectionView.backgroundColor = .clear
    collectionView.showsHorizontalScrollIndicator = false
    collectionView.alwaysBounceHorizontal = true
    collectionView.clipsToBounds = false
    collectionView.contentInsetAdjustmentBehavior = .never
    collectionView.delegate = self
    collectionView.register(
      MoreAppCardCell.self,
      forCellWithReuseIdentifier: MoreAppCardCell.reuseIdentifier
    )
    #if os(tvOS)
      collectionView.remembersLastFocusedIndexPath = true
    #endif
    addSubview(collectionView)

    let collectionHeightConstraint = collectionView.heightAnchor.constraint(
      equalToConstant: 128
    )
    self.collectionHeightConstraint = collectionHeightConstraint

    titleLeadingConstraint = titleLabel.leadingAnchor.constraint(
      equalTo: leadingAnchor,
      constant: configuration.contentInsets.leading
    )
    titleTrailingConstraint = titleLabel.trailingAnchor.constraint(
      lessThanOrEqualTo: trailingAnchor,
      constant: -configuration.contentInsets.trailing
    )
    titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: topAnchor)
    collectionTopToTitleConstraint = collectionView.topAnchor.constraint(
      equalTo: titleLabel.bottomAnchor,
      constant: 8
    )
    collectionTopConstraint = collectionView.topAnchor.constraint(
      equalTo: topAnchor
    )

    let constraints: [NSLayoutConstraint] = [
      titleLeadingConstraint,
      titleTrailingConstraint,
      collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
      collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
      collectionHeightConstraint,
    ]
    NSLayoutConstraint.activate(constraints)
    updateTitleLayoutConstraints()

    registerForTraitChanges([
      UITraitHorizontalSizeClass.self,
      UITraitPreferredContentSizeCategory.self,
    ]) { (view: MoreAppsView, _) in
      view.setNeedsLayout()
    }
  }

  private func configureDataSource() {
    dataSource = UICollectionViewDiffableDataSource<Section, MoreApp.ID>(
      collectionView: collectionView
    ) { [weak self] collectionView, indexPath, appID in
      guard let self,
        let app = self.currentApps[appID],
        let cell = collectionView.dequeueReusableCell(
          withReuseIdentifier: MoreAppCardCell.reuseIdentifier,
          for: indexPath
        ) as? MoreAppCardCell
      else {
        return nil
      }

      cell.configure(
        with: app,
        configuration: self.configuration,
        imageLoader: self.imageLoader
      )
      return cell
    }
  }

  private func bindStore() {
    observe { [weak self] in
      guard let self else { return }
      self.render(
        apps: self.store.apps,
        focusedAppID: self.store.focusedAppID
      )
    }
  }

  private func render(
    apps: [MoreApp],
    focusedAppID: MoreApp.ID?
  ) {
    isHidden = configuration.hidesWhenEmpty && apps.isEmpty

    if apps != currentOrderedApps {
      applySnapshot(apps: apps)
    }
    renderFocusedBackground(appID: focusedAppID)

    // Keep this observation active so reducer-enqueued events schedule delivery.
    _ = store.pendingEvents
    scheduleEventDeliveryIfNeeded()
  }

  private func applySnapshot(apps: [MoreApp]) {
    let previousApps = currentApps
    currentOrderedApps = apps
    currentApps = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })

    var snapshot = NSDiffableDataSourceSnapshot<Section, MoreApp.ID>()
    snapshot.appendSections([.main])
    snapshot.appendItems(apps.map(\.id), toSection: .main)

    let changedIDs = apps.compactMap { app -> MoreApp.ID? in
      guard let previous = previousApps[app.id], previous != app else {
        return nil
      }
      return app.id
    }
    snapshot.reconfigureItems(changedIDs)

    dataSource.apply(
      snapshot,
      animatingDifferences: hasAppliedSnapshot
    )
    hasAppliedSnapshot = true
  }

  private func reconfigureCurrentItems() {
    guard hasAppliedSnapshot else { return }

    var snapshot = dataSource.snapshot()
    snapshot.reconfigureItems(snapshot.itemIdentifiers)
    dataSource.apply(snapshot, animatingDifferences: false)
  }

  private func renderFocusedBackground(appID: MoreApp.ID?) {
    let imageURL = appID.flatMap { appID in
      currentApps[appID]?
        .destination(for: .current)?
        .backgroundImageURL
    }
    focusedBackgroundView?.display(
      appID: appID,
      imageURL: imageURL
    )
  }

  #if os(tvOS)
    func updateFocusedApp(at indexPath: IndexPath?) {
      let appID: MoreApp.ID? = indexPath.flatMap {
        dataSource.itemIdentifier(for: $0)
      }
      store.send(.focusChanged(appID: appID))
    }
  #endif

  private func scheduleEventDeliveryIfNeeded() {
    guard eventDeliveryTask == nil,
      onEvent != nil,
      !store.pendingEvents.isEmpty
    else {
      return
    }

    eventDeliveryTask = Task { [weak self] in
      await Task.yield()

      while !Task.isCancelled {
        let deliveredEvent: Bool
        do {
          guard let self else { return }
          deliveredEvent = self.deliverNextPendingEvent()
        }
        guard deliveredEvent else { break }
        await Task.yield()
      }

      guard let self else { return }
      self.eventDeliveryTask = nil
      if !self.store.pendingEvents.isEmpty {
        self.scheduleEventDeliveryIfNeeded()
      }
    }
  }

  private func deliverNextPendingEvent() -> Bool {
    guard let envelope = store.pendingEvents.first,
      let onEvent
    else {
      return false
    }

    onEvent(envelope.event)
    store.send(.eventDelivered(envelope.id))
    return true
  }

  private func updateTitleLayoutConstraints() {
    if configuration.showsTitle {
      NSLayoutConstraint.deactivate([collectionTopConstraint])
      NSLayoutConstraint.activate([
        titleTopConstraint,
        collectionTopToTitleConstraint,
      ])
    } else {
      NSLayoutConstraint.deactivate([
        titleTopConstraint,
        collectionTopToTitleConstraint,
      ])
      NSLayoutConstraint.activate([collectionTopConstraint])
    }
  }

  private func updateLayoutMetrics() {
    #if os(tvOS)
      let cardWidth: CGFloat = 420
      let baseCardHeight: CGFloat = 168
      let iconSize: CGFloat = 96
      let focusPadding: CGFloat = UIAccessibility.isReduceMotionEnabled ? 8 : 16
    #else
      let accessibilitySize = traitCollection.preferredContentSizeCategory
        .isAccessibilityCategory
      let regularWidth = traitCollection.horizontalSizeClass == .regular
      let cardWidth: CGFloat = accessibilitySize ? 300 : (regularWidth ? 260 : 220)
      let baseCardHeight: CGFloat = accessibilitySize ? 152 : 112
      let iconSize: CGFloat = 64
      let focusPadding: CGFloat = 0
    #endif

    let nameHeight =
      UIFont.preferredFont(
        forTextStyle: .headline,
        compatibleWith: traitCollection
      ).lineHeight * 2
    let subtitleHeight =
      configuration.showsSubtitle
      ? UIFont.preferredFont(
        forTextStyle: .subheadline,
        compatibleWith: traitCollection
      ).lineHeight * 2 + 3
      : 0
    let contentHeight = max(iconSize, nameHeight + subtitleHeight) + 28
    let cardSize = CGSize(
      width: cardWidth,
      height: max(baseCardHeight, ceil(contentHeight))
    )

    let direction = effectiveUserInterfaceLayoutDirection
    let left =
      direction == .rightToLeft
      ? configuration.contentInsets.trailing
      : configuration.contentInsets.leading
    let right =
      direction == .rightToLeft
      ? configuration.contentInsets.leading
      : configuration.contentInsets.trailing

    flowLayout.itemSize = cardSize
    flowLayout.sectionInset = UIEdgeInsets(
      top: configuration.contentInsets.top + focusPadding,
      left: left,
      bottom: configuration.contentInsets.bottom + focusPadding,
      right: right
    )
    collectionHeightConstraint.constant =
      cardSize.height
      + flowLayout.sectionInset.top
      + flowLayout.sectionInset.bottom
  }
}

extension MoreAppsView: UICollectionViewDelegate {
  #if os(tvOS)
    /// Synchronizes Focus Engine changes with optional background artwork.
    public func collectionView(
      _ collectionView: UICollectionView,
      didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
      with coordinator: UIFocusAnimationCoordinator
    ) {
      updateFocusedApp(at: context.nextFocusedIndexPath)
    }
  #endif

  /// Handles selection of a promoted app card.
  public func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    guard let appID = dataSource.itemIdentifier(for: indexPath) else {
      return
    }
    store.send(.selected(appID: appID))
  }

  /// Records the first visible impression for an app in the current data session.
  public func collectionView(
    _ collectionView: UICollectionView,
    willDisplay cell: UICollectionViewCell,
    forItemAt indexPath: IndexPath
  ) {
    guard let appID = dataSource.itemIdentifier(for: indexPath) else {
      return
    }
    store.send(.itemBecameVisible(appID: appID))
  }
}
