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
      title: "More Apps on Apple TV",
      cardSpacing: 28,
      contentInsets: .init(
        top: 24,
        leading: 64,
        bottom: 24,
        trailing: 64
      ),
      allowedCustomDeepLinkSchemes: ["andromeda17k"],
      selectionBehavior: .platformPresentation
    ),
    presentingViewController: self
  )

  override func viewDidLoad() {
    super.viewDidLoad()

    moreAppsView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(moreAppsView)

    NSLayoutConstraint.activate([
      moreAppsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      moreAppsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      moreAppsView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])

    moreAppsView.onEvent = { event in
      print("MoreAppsKit event:", event)
    }
    moreAppsView.setApps(Self.catalog)
  }

  private static let catalog = [
    MoreApp(
      id: "andromeda-17k",
      bundleIdentifier: "me.gorani.Andromeda17K",
      name: "Andromeda 17K: Clock&Wallpaper",
      subtitle: "17K galaxy panorama and full-screen clock",
      iconURL: URL(
        string: "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/"
          + "fd/e7/8a/fde78abc-df06-a02f-0ccb-e3bc68c973c3/"
          + "App_Icon-marketing.lsr/512x512bb.jpg"
      ),
      destinations: [
        MoreAppDestination(
          platform: .tvOS,
          appStoreURL: URL(
            string: "https://apps.apple.com/us/app/andromeda-17k-clock-wallpaper/id6786789129"
          )!,
          deepLinkURL: URL(string: "andromeda17k://")
        )
      ],
      sortOrder: 20
    ),
    // This entry is intentionally filtered out by a tvOS host.
    MoreApp(
      id: "phone-notes",
      bundleIdentifier: "com.example.phonenotes",
      name: "Phone Notes",
      destinations: [
        MoreAppDestination(
          platform: .iOS,
          appStoreURL: URL(
            string: "https://apps.apple.com/app/id1111111111"
          )!
        )
      ],
      sortOrder: 20
    ),
  ]
}
