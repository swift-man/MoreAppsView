//
//  MoreAppDetailViewController.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/23/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

#if os(tvOS)
  import UIKit

  @MainActor
  final class MoreAppDetailViewController: UIViewController {
    private let app: MoreApp
    private let imageLoader: MoreAppsImageLoader
    private var onFinish: ((MoreAppsPresentationOutcome) -> Void)?

    private let scrollView = UIScrollView()
    private let contentContainer = UIView()
    private let contentStack = UIStackView()
    private let headerStack = UIStackView()
    private let textStack = UIStackView()
    private let buttonStack = UIStackView()
    private let iconImageView = UIImageView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let storeButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    private var imageTask: Task<Void, Never>?
    private var representedAppID: MoreApp.ID?
    private var pendingOutcome: MoreAppsPresentationOutcome?
    private var didFinish = false

    init(
      app: MoreApp,
      imageLoader: MoreAppsImageLoader,
      onFinish: @escaping (MoreAppsPresentationOutcome) -> Void
    ) {
      self.app = app
      self.imageLoader = imageLoader
      self.onFinish = onFinish
      self.representedAppID = app.id
      super.init(nibName: nil, bundle: nil)
      preferredContentSize = CGSize(width: 1_100, height: 620)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError(
        "MoreAppDetailViewController supports programmatic initialization only."
      )
    }

    deinit {
      imageTask?.cancel()
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      setUpViews()
      loadIcon()
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      UIAccessibility.post(notification: .screenChanged, argument: nameLabel)
    }

    override func viewDidDisappear(_ animated: Bool) {
      super.viewDidDisappear(animated)

      imageTask?.cancel()
      imageTask = nil
      representedAppID = nil

      finish(with: pendingOutcome ?? .dismissed)
    }

    override func pressesBegan(
      _ presses: Set<UIPress>,
      with event: UIPressesEvent?
    ) {
      guard presses.contains(where: { $0.type == .menu }) else {
        super.pressesBegan(presses, with: event)
        return
      }
      dismissAndFinish(with: .dismissed)
    }

    override func accessibilityPerformEscape() -> Bool {
      dismissAndFinish(with: .dismissed)
      return true
    }

    @objc
    func storeButtonPressed() {
      dismissAndFinish(with: .appStoreRequested)
    }

    @objc
    private func closeButtonPressed() {
      dismissAndFinish(with: .dismissed)
    }

    private func setUpViews() {
      view.backgroundColor = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
          ? UIColor(white: 0.08, alpha: 1)
          : UIColor(white: 0.96, alpha: 1)
      }
      view.accessibilityViewIsModal = true

      scrollView.translatesAutoresizingMaskIntoConstraints = false
      scrollView.alwaysBounceHorizontal = false
      scrollView.showsHorizontalScrollIndicator = false
      view.addSubview(scrollView)

      contentContainer.translatesAutoresizingMaskIntoConstraints = false
      scrollView.addSubview(contentContainer)

      contentStack.translatesAutoresizingMaskIntoConstraints = false
      contentStack.axis = .vertical
      contentStack.alignment = .fill
      contentStack.spacing = 44
      contentContainer.addSubview(contentStack)

      setUpHeader()
      setUpButtons()
      contentStack.addArrangedSubview(headerStack)
      contentStack.addArrangedSubview(buttonStack)

      let safeArea = view.safeAreaLayoutGuide
      let frameGuide = scrollView.frameLayoutGuide
      let contentGuide = scrollView.contentLayoutGuide
      let preferredContentHeight = contentContainer.heightAnchor.constraint(
        equalTo: frameGuide.heightAnchor
      )
      preferredContentHeight.priority = .defaultLow
      let preferredContentWidth = contentStack.widthAnchor.constraint(
        equalTo: contentContainer.widthAnchor,
        constant: -144
      )
      preferredContentWidth.priority = .defaultHigh

      NSLayoutConstraint.activate([
        scrollView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
        scrollView.topAnchor.constraint(equalTo: safeArea.topAnchor),
        scrollView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),

        contentContainer.leadingAnchor.constraint(
          equalTo: contentGuide.leadingAnchor
        ),
        contentContainer.trailingAnchor.constraint(
          equalTo: contentGuide.trailingAnchor
        ),
        contentContainer.topAnchor.constraint(equalTo: contentGuide.topAnchor),
        contentContainer.bottomAnchor.constraint(
          equalTo: contentGuide.bottomAnchor
        ),
        contentContainer.widthAnchor.constraint(equalTo: frameGuide.widthAnchor),
        contentContainer.heightAnchor.constraint(
          greaterThanOrEqualTo: frameGuide.heightAnchor
        ),
        preferredContentHeight,

        contentStack.centerXAnchor.constraint(
          equalTo: contentContainer.centerXAnchor
        ),
        contentStack.centerYAnchor.constraint(
          equalTo: contentContainer.centerYAnchor
        ),
        contentStack.leadingAnchor.constraint(
          greaterThanOrEqualTo: contentContainer.leadingAnchor,
          constant: 72
        ),
        contentStack.trailingAnchor.constraint(
          lessThanOrEqualTo: contentContainer.trailingAnchor,
          constant: -72
        ),
        contentStack.topAnchor.constraint(
          greaterThanOrEqualTo: contentContainer.topAnchor,
          constant: 48
        ),
        contentStack.bottomAnchor.constraint(
          lessThanOrEqualTo: contentContainer.bottomAnchor,
          constant: -48
        ),
        contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: 960),
        preferredContentWidth,
      ])
    }

    private func setUpHeader() {
      iconImageView.translatesAutoresizingMaskIntoConstraints = false
      iconImageView.contentMode = .scaleAspectFill
      iconImageView.clipsToBounds = true
      iconImageView.backgroundColor = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
          ? UIColor(white: 0.18, alpha: 1)
          : UIColor(white: 0.88, alpha: 1)
      }
      iconImageView.layer.cornerRadius = 36
      iconImageView.layer.cornerCurve = .continuous
      iconImageView.isAccessibilityElement = false

      nameLabel.font = .preferredFont(forTextStyle: .title1)
      nameLabel.adjustsFontForContentSizeCategory = true
      nameLabel.textColor = .label
      nameLabel.numberOfLines = 2
      nameLabel.lineBreakMode = .byTruncatingTail
      nameLabel.text = app.name
      nameLabel.accessibilityTraits = [.header]

      subtitleLabel.font = .preferredFont(forTextStyle: .body)
      subtitleLabel.adjustsFontForContentSizeCategory = true
      subtitleLabel.textColor = .secondaryLabel
      subtitleLabel.numberOfLines = 4
      subtitleLabel.lineBreakMode = .byTruncatingTail
      subtitleLabel.text = app.subtitle
      subtitleLabel.isHidden = app.subtitle?.isEmpty != false

      textStack.axis = .vertical
      textStack.alignment = .fill
      textStack.spacing = 12
      textStack.addArrangedSubview(nameLabel)
      textStack.addArrangedSubview(subtitleLabel)

      headerStack.axis = .horizontal
      headerStack.alignment = .center
      headerStack.spacing = 40
      headerStack.addArrangedSubview(iconImageView)
      headerStack.addArrangedSubview(textStack)

      NSLayoutConstraint.activate([
        iconImageView.widthAnchor.constraint(equalToConstant: 180),
        iconImageView.heightAnchor.constraint(equalTo: iconImageView.widthAnchor),
      ])
    }

    private func setUpButtons() {
      var storeConfiguration = UIButton.Configuration.filled()
      storeConfiguration.title = String(
        localized: "more_apps_store_action",
        bundle: .module
      )
      storeConfiguration.cornerStyle = .large
      storeConfiguration.contentInsets = .init(
        top: 18,
        leading: 28,
        bottom: 18,
        trailing: 28
      )
      storeConfiguration.titleTextAttributesTransformer =
        preferredButtonTitleAttributes
      storeButton.configuration = storeConfiguration
      storeButton.titleLabel?.adjustsFontForContentSizeCategory = true
      storeButton.accessibilityHint = String(
        localized: "more_apps_detail_hint",
        bundle: .module
      )
      storeButton.addTarget(
        self,
        action: #selector(storeButtonPressed),
        for: .primaryActionTriggered
      )

      var closeConfiguration = UIButton.Configuration.gray()
      closeConfiguration.title = String(
        localized: "more_apps_close_action",
        bundle: .module
      )
      closeConfiguration.cornerStyle = .large
      closeConfiguration.contentInsets = .init(
        top: 18,
        leading: 28,
        bottom: 18,
        trailing: 28
      )
      closeConfiguration.titleTextAttributesTransformer =
        preferredButtonTitleAttributes
      closeButton.configuration = closeConfiguration
      closeButton.titleLabel?.adjustsFontForContentSizeCategory = true
      closeButton.addTarget(
        self,
        action: #selector(closeButtonPressed),
        for: .primaryActionTriggered
      )

      buttonStack.axis = .horizontal
      buttonStack.alignment = .fill
      buttonStack.distribution = .fillEqually
      buttonStack.spacing = 24
      buttonStack.addArrangedSubview(storeButton)
      buttonStack.addArrangedSubview(closeButton)

      NSLayoutConstraint.activate([
        storeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 66),
        closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 66),
      ])
    }

    private var preferredButtonTitleAttributes: UIConfigurationTextAttributesTransformer {
      UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        outgoing.font = .preferredFont(forTextStyle: .headline)
        return outgoing
      }
    }

    private func loadIcon() {
      let placeholder =
        UIImage(systemName: "app.dashed") ?? UIImage(systemName: "app")
      iconImageView.image = placeholder
      iconImageView.tintColor = .secondaryLabel

      guard let iconURL = app.iconURL else { return }

      let appID = app.id
      let imageLoader = self.imageLoader
      representedAppID = appID
      imageTask?.cancel()
      imageTask = Task { [weak self] in
        do {
          let image = try await imageLoader.image(for: iconURL)
          try Task.checkCancellation()
          guard let self, self.representedAppID == appID else { return }
          self.iconImageView.image = image
          self.iconImageView.tintColor = nil
        } catch {
          // The secure loader rejects invalid responses; keep the placeholder.
        }
      }
    }

    private func dismissAndFinish(with outcome: MoreAppsPresentationOutcome) {
      guard !didFinish, pendingOutcome == nil else { return }
      pendingOutcome = outcome
      storeButton.isEnabled = false
      closeButton.isEnabled = false

      dismiss(animated: true)
    }

    private func finish(with outcome: MoreAppsPresentationOutcome) {
      guard !didFinish else { return }
      didFinish = true
      pendingOutcome = nil

      let completion = onFinish
      onFinish = nil
      completion?(outcome)
    }
  }
#endif
