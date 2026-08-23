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
    )
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
      name: "MoreAppsKit",
      dependencies: [
        .product(
          name: "ComposableArchitecture",
          package: "swift-composable-architecture"
        ),
        .product(
          name: "Dependencies",
          package: "swift-dependencies"
        ),
        .product(
          name: "Alamofire",
          package: "Alamofire"
        ),
      ],
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "MoreAppsKitTests",
      dependencies: [
        "MoreAppsKit",
        .product(
          name: "ComposableArchitecture",
          package: "swift-composable-architecture"
        ),
      ]
    ),
  ],
  swiftLanguageVersions: [.v5]
)
