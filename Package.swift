// swift-tools-version: 5.9

//
//  Package.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import PackageDescription

let package = Package(
  name: "MoreAppsKit",
  defaultLocalization: "en",
  platforms: [
    .iOS("26.0"),
    .tvOS("26.0"),
  ],
  products: [
    .library(
      name: "MoreAppsKit",
      targets: ["MoreAppsKit"]
    ),
    .library(
      name: "MoreAppsKitCore",
      targets: ["MoreAppsKitCore"]
    ),
    .library(
      name: "MoreAppsKitNetworking",
      targets: ["MoreAppsNetworking"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/pointfreeco/swift-composable-architecture",
      from: "1.25.5"
    ),
    .package(
      url: "https://github.com/pointfreeco/swift-dependencies",
      from: "1.12.0"
    ),
    .package(
      url: "https://github.com/Alamofire/Alamofire",
      from: "5.12.0"
    ),
  ],
  targets: [
    .target(
      name: "MoreAppsKitCore",
      dependencies: [
        .product(
          name: "ComposableArchitecture",
          package: "swift-composable-architecture"
        ),
        .product(
          name: "Dependencies",
          package: "swift-dependencies"
        ),
      ],
      resources: [
        .process("Resources")
      ]
    ),
    .target(
      name: "MoreAppsNetworking",
      dependencies: [
        "MoreAppsKitCore",
        .product(
          name: "Alamofire",
          package: "Alamofire"
        ),
      ]
    ),
    .target(
      name: "MoreAppsKit",
      dependencies: [
        "MoreAppsKitCore",
        "MoreAppsNetworking",
      ]
    ),
    .testTarget(
      name: "MoreAppsKitTests",
      dependencies: [
        "MoreAppsKit",
        "MoreAppsKitCore",
        "MoreAppsNetworking",
        .product(
          name: "ComposableArchitecture",
          package: "swift-composable-architecture"
        ),
      ]
    ),
  ],
  swiftLanguageVersions: [.v5]
)
