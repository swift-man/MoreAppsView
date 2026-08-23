//
//  MoreAppsExampleViewController.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import MoreAppsKit
import UIKit

@MainActor
final class MoreAppsExampleViewController: UIViewController {
  private lazy var moreAppsView = MoreAppsView(
    configuration: .init(
      showsTitle: true,
      hidesWhenEmpty: true,
      maximumNumberOfItems: 8,
      allowedCustomDeepLinkSchemes: ["wordrush"],
      selectionBehavior: .platformPresentation
    ),
    presentingViewController: self
  )

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .systemBackground
    moreAppsView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(moreAppsView)

    NSLayoutConstraint.activate([
      moreAppsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      moreAppsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      moreAppsView.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor
      ),
    ])

    moreAppsView.onEvent = { event in
      print("MoreAppsKit event:", event)
    }
    moreAppsView.setApps(Self.catalog)
  }

  private static let catalog = [
    MoreApp(
      id: "word-rush",
      bundleIdentifier: "com.example.wordrush",
      name: "Word Rush",
      subtitle: "Fast-paced typing challenge",
      iconURL: URL(string: "https://example.com/wordrush.png"),
      destinations: [
        MoreAppDestination(
          platform: .iOS,
          appStoreURL: URL(
            string: "https://apps.apple.com/app/id1234567890"
          )!,
          deepLinkURL: URL(string: "wordrush://home")
        )
      ],
      sortOrder: 10
    ),
    // This entry is intentionally filtered out by an iOS host.
    MoreApp(
      id: "tv-clock",
      bundleIdentifier: "com.example.tvclock",
      name: "TV Clock",
      destinations: [
        MoreAppDestination(
          platform: .tvOS,
          appStoreURL: URL(
            string: "https://apps.apple.com/app/id0987654321"
          )!
        )
      ],
      sortOrder: 20
    ),
  ]
}
