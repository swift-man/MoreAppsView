//
//  MoreAppCardCell.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import UIKit

@MainActor
final class MoreAppCardCell: UICollectionViewCell {
  static let reuseIdentifier = "MoreAppCardCell"

  private static let cardBackgroundColor: UIColor = {
    #if os(tvOS)
      return UIColor { traits in
        traits.userInterfaceStyle == .light
          ? UIColor(white: 0.92, alpha: 1)
          : UIColor(white: 0.16, alpha: 1)
      }
    #else
      return .secondarySystemBackground
    #endif
  }()

  private static let focusedBackgroundColor: UIColor = {
    #if os(tvOS)
      return UIColor { traits in
        traits.userInterfaceStyle == .light
          ? .white
          : UIColor(white: 0.27, alpha: 1)
      }
    #else
      return .tertiarySystemBackground
    #endif
  }()

  private static let iconBackgroundColor: UIColor = {
    #if os(tvOS)
      return UIColor { traits in
        traits.userInterfaceStyle == .light
          ? UIColor(white: 0.84, alpha: 1)
          : UIColor(white: 0.24, alpha: 1)
      }
    #else
      return .tertiarySystemBackground
    #endif
  }()

  private let iconImageView = UIImageView()
  private let nameLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let textStack = UIStackView()
  private let contentStack = UIStackView()
  private var iconSizeConstraint: NSLayoutConstraint?
  private var imageTask: Task<Void, Never>?
  private var representedAppID: MoreApp.ID?

  override init(frame: CGRect) {
    super.init(frame: frame)
    setUpViews()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("MoreAppCardCell supports programmatic initialization only.")
  }

  deinit {
    imageTask?.cancel()
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageTask?.cancel()
    imageTask = nil
    representedAppID = nil
    iconImageView.image = nil
    nameLabel.text = nil
    subtitleLabel.text = nil
    contentView.alpha = 1
    contentView.transform = .identity
    transform = .identity
    layer.zPosition = 0
  }

  override var isHighlighted: Bool {
    didSet {
      #if os(iOS)
        UIView.animate(
          withDuration: 0.16,
          delay: 0,
          options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
          self.contentView.alpha = self.isHighlighted ? 0.68 : 1
          self.contentView.transform =
            self.isHighlighted
            ? CGAffineTransform(scaleX: 0.985, y: 0.985)
            : .identity
        }
      #endif
    }
  }

  #if os(tvOS)
    override var canBecomeFocused: Bool { true }

    override func didUpdateFocus(
      in context: UIFocusUpdateContext,
      with coordinator: UIFocusAnimationCoordinator
    ) {
      super.didUpdateFocus(in: context, with: coordinator)

      let isFocused = context.nextFocusedView === self
      let reduceMotion = UIAccessibility.isReduceMotionEnabled
      let scale: CGFloat = isFocused ? (reduceMotion ? 1.02 : 1.07) : 1

      layer.zPosition = isFocused ? 1 : 0
      coordinator.addCoordinatedAnimations {
        self.transform = CGAffineTransform(scaleX: scale, y: scale)
        self.contentView.backgroundColor =
          isFocused
          ? Self.focusedBackgroundColor
          : Self.cardBackgroundColor
      }
    }
  #endif

  func configure(
    with app: MoreApp,
    configuration: MoreAppsConfiguration,
    imageLoader: MoreAppsImageLoader
  ) {
    representedAppID = app.id
    imageTask?.cancel()

    contentView.layer.cornerRadius = configuration.cardCornerRadius
    nameLabel.text = app.name
    subtitleLabel.text = app.subtitle
    subtitleLabel.isHidden =
      !configuration.showsSubtitle
      || app.subtitle?.isEmpty != false

    let placeholder =
      UIImage(
        systemName: configuration.placeholderSystemImageName
      ) ?? UIImage(systemName: "app")
    iconImageView.image = placeholder
    iconImageView.tintColor = .secondaryLabel

    let presentsOptions =
      configuration.selectionBehavior == .platformPresentation
    #if os(iOS)
      let presentationActionKey: String.LocalizationValue =
        "more_apps_open_or_view_action"
      let presentationHintKey: String.LocalizationValue =
        "more_apps_open_or_view_hint"
    #else
      let presentationActionKey: String.LocalizationValue =
        "more_apps_view_action"
      let presentationHintKey: String.LocalizationValue =
        "more_apps_view_hint"
    #endif
    let action = String(
      localized: presentsOptions
        ? presentationActionKey
        : "more_apps_open_action",
      bundle: .module
    )
    accessibilityLabel = [app.name, app.subtitle, action]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
    accessibilityHint = String(
      localized: presentsOptions
        ? presentationHintKey
        : "more_apps_open_hint",
      bundle: .module
    )

    guard let iconURL = app.iconURL else {
      return
    }

    let appID = app.id
    imageTask = Task { [weak self] in
      do {
        let image = try await imageLoader.image(for: iconURL)
        try Task.checkCancellation()
        guard let self, self.representedAppID == appID else {
          return
        }
        self.iconImageView.image = image
        self.iconImageView.tintColor = nil
      } catch {
        // The configured placeholder intentionally remains visible.
      }
    }
  }

  private func setUpViews() {
    isAccessibilityElement = true
    accessibilityTraits = [.button]

    contentView.backgroundColor = Self.cardBackgroundColor
    contentView.layer.cornerCurve = .continuous
    contentView.layer.masksToBounds = true
    contentView.directionalLayoutMargins = .init(
      top: 14,
      leading: 14,
      bottom: 14,
      trailing: 14
    )

    iconImageView.translatesAutoresizingMaskIntoConstraints = false
    iconImageView.contentMode = .scaleAspectFill
    iconImageView.clipsToBounds = true
    iconImageView.backgroundColor = Self.iconBackgroundColor

    nameLabel.font = .preferredFont(forTextStyle: .headline)
    nameLabel.adjustsFontForContentSizeCategory = true
    nameLabel.textColor = .label
    nameLabel.numberOfLines = 2
    nameLabel.lineBreakMode = .byTruncatingTail

    subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
    subtitleLabel.adjustsFontForContentSizeCategory = true
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.numberOfLines = 2
    subtitleLabel.lineBreakMode = .byTruncatingTail

    textStack.axis = .vertical
    textStack.alignment = .fill
    textStack.spacing = 3
    textStack.addArrangedSubview(nameLabel)
    textStack.addArrangedSubview(subtitleLabel)

    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.axis = .horizontal
    contentStack.alignment = .center
    contentStack.spacing = 12
    contentStack.addArrangedSubview(iconImageView)
    contentStack.addArrangedSubview(textStack)
    contentView.addSubview(contentStack)

    #if os(tvOS)
      let iconSize: CGFloat = 96
      iconImageView.layer.cornerRadius = 22
    #else
      let iconSize: CGFloat = 64
      iconImageView.layer.cornerRadius = 14
    #endif

    let iconSizeConstraint = iconImageView.widthAnchor.constraint(
      equalToConstant: iconSize
    )
    self.iconSizeConstraint = iconSizeConstraint

    NSLayoutConstraint.activate([
      contentStack.leadingAnchor.constraint(
        equalTo: contentView.layoutMarginsGuide.leadingAnchor
      ),
      contentStack.trailingAnchor.constraint(
        equalTo: contentView.layoutMarginsGuide.trailingAnchor
      ),
      contentStack.topAnchor.constraint(
        greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor
      ),
      contentStack.bottomAnchor.constraint(
        lessThanOrEqualTo: contentView.layoutMarginsGuide.bottomAnchor
      ),
      contentStack.centerYAnchor.constraint(
        equalTo: contentView.layoutMarginsGuide.centerYAnchor
      ),
      iconSizeConstraint,
      iconImageView.heightAnchor.constraint(equalTo: iconImageView.widthAnchor),
    ])
  }
}
