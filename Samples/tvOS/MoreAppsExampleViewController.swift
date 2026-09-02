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
  private let focusedBackgroundView = MoreAppsFocusedBackgroundView()

  // Selecting a card opens an installed app immediately, then falls back to
  // the system App Store app without presenting intermediate package UI.
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
      selectionBehavior: .directOpen
    )
  )

  override func viewDidLoad() {
    super.viewDidLoad()

    focusedBackgroundView.translatesAutoresizingMaskIntoConstraints = false
    moreAppsView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(focusedBackgroundView)
    view.addSubview(moreAppsView)
    moreAppsView.focusedBackgroundView = focusedBackgroundView

    NSLayoutConstraint.activate([
      focusedBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
      focusedBackgroundView.leadingAnchor.constraint(
        equalTo: view.leadingAnchor
      ),
      focusedBackgroundView.trailingAnchor.constraint(
        equalTo: view.trailingAnchor
      ),
      focusedBackgroundView.bottomAnchor.constraint(
        equalTo: view.bottomAnchor
      ),
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
          deepLinkURL: URL(string: "andromeda17k://"),
          backgroundImageURL: URL(
            string: "https://is1-ssl.mzstatic.com/image/thumb/"
              + "PurpleSource221/v4/f2/47/f8/"
              + "f247f87c-b756-f833-1307-aee7f81f65db/"
              + "Simulator_Screenshot_-_Apple_TV_4K__U00283rd_generation_U0029_-_"
              + "2026-07-29_at_15.54.24.png/1920x1080bb.png"
          )
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
