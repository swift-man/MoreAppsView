# MoreAppsKit

MoreAppsKit is a reusable UIKit package for cross-promoting your own apps with
clean, horizontally scrolling App Store-style cards. It filters the catalog for
the host platform, removes the current app, opens deep links with an App Store
fallback, and emits optional closure-based events without collecting user data.

The implementation uses The Composable Architecture (TCA) for state and effects,
`swift-dependencies` for replaceable host and URL-opening dependencies, Alamofire
for remote JSON and image HTTP requests, and a
`UICollectionViewDiffableDataSource` for incremental UI updates.

## Requirements

- Xcode 26.0 or newer with the Swift 6.2 toolchain
- Swift 5 language mode (`swift-tools-version: 5.9`)
- iOS 26.0 or newer
- tvOS 26.0 or newer
- UIKit

macOS, watchOS, and visionOS are not supported in this release.

## Installation

In Xcode, choose **File > Add Package Dependencies** and enter
`https://github.com/swift-man/MoreAppsView.git`. To declare it in another Swift
package:

```swift
dependencies: [
    .package(
        url: "https://github.com/swift-man/MoreAppsView.git",
        from: "0.1.0"
    )
]
```

Then add `MoreAppsKit` to the consuming target and import it:

```swift
import MoreAppsKit
```

The package resolves compatible versions of TCA, Dependencies, and Alamofire
transitively; the host app does not need to add those products to its own target.

## Static catalog

Each app supplies a separate destination for each supported platform. The same
metadata array can therefore be shared by iOS and tvOS hosts:

```swift
import MoreAppsKit
import UIKit

let apps = [
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
    MoreApp(
        id: "andromeda",
        bundleIdentifier: "com.example.andromeda",
        name: "Andromeda 17K",
        subtitle: "Space clock for Apple TV",
        destinations: [
            MoreAppDestination(
                platform: .tvOS,
                appStoreURL: URL(
                    string: "https://apps.apple.com/app/id0987654321"
                )!,
                deepLinkURL: URL(string: "andromeda://home")
            )
        ],
        sortOrder: 20
    )
]

let moreAppsView = MoreAppsView(
    configuration: .init(
        showsTitle: true,
        hidesWhenEmpty: true
    )
)
moreAppsView.setApps(apps)
```

`StaticMoreAppsProvider` is useful when the caller wants the same provider-based
loading flow without a network request:

```swift
let provider = StaticMoreAppsProvider(apps: apps)
await moreAppsView.load(using: provider)
```

## iOS integration

Add the view to any UIKit hierarchy. It does not depend on a view controller:

```swift
final class AppsViewController: UIViewController {
    private let moreAppsView = MoreAppsView()

    override func viewDidLoad() {
        super.viewDidLoad()

        moreAppsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(moreAppsView)
        NSLayoutConstraint.activate([
            moreAppsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            moreAppsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            moreAppsView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor
            )
        ])

        moreAppsView.onEvent = { event in
            // Forward to analytics only if your app chooses to do so.
            print(event)
        }
        moreAppsView.setApps(apps)
    }
}
```

iPhone cards default to about 220 points wide and adapt for iPad and accessibility
content sizes. Dynamic Type, semantic colors, VoiceOver, and touch highlighting
are enabled by default.

See [Samples/iOS/MoreAppsExampleViewController.swift](Samples/iOS/MoreAppsExampleViewController.swift)
for a complete example.

## tvOS integration

The UIKit setup is the same on tvOS. Only apps with a `.tvOS` destination are
displayed. Cards are larger and use the Focus Engine, coordinated focus scaling,
elevated z-order, additional clipping insets, and reduced animation when Reduce
Motion is enabled.

```swift
let moreAppsView = MoreAppsView(
    configuration: .init(
        title: "More Apps on Apple TV",
        cardSpacing: 28
    )
)
moreAppsView.setApps(sharedCatalog)
```

See [Samples/tvOS/MoreAppsExampleViewController.swift](Samples/tvOS/MoreAppsExampleViewController.swift)
for a complete example.

## Remote JSON

`RemoteJSONMoreAppsProvider` uses Alamofire, validates HTTP status codes, and
distinguishes network/HTTP failures from JSON decoding failures:

```swift
let endpoint = URL(string: "https://example.com/more-apps.json")!
let provider = RemoteJSONMoreAppsProvider(url: endpoint)

Task {
    await moreAppsView.load(using: provider)
}
```

Call `await moreAppsView.reload()` to fetch again with the most recently supplied
provider. Starting another provider load cancels the prior TCA effect so a stale
response cannot replace newer state.

The JSON schema is demonstrated in
[Samples/RemoteJSON/more-apps.json](Samples/RemoteJSON/more-apps.json).
An unknown platform string fails decoding instead of accidentally exposing an app
on the wrong platform.

## Filtering rules

MoreAppsKit applies these rules before a diffable snapshot:

1. Keep only apps with a destination matching the compiled host platform.
2. Remove the app whose `bundleIdentifier` matches `Bundle.main.bundleIdentifier`.
3. Keep the first app for each duplicated `id`.
4. Sort by ascending `sortOrder`, preserving input order for ties.
5. Apply `maximumNumberOfItems`, when configured.

Consequently, an iOS host never displays a tvOS-only app, and a tvOS host never
displays an iOS-only app. With `hidesWhenEmpty` enabled, `MoreAppsView` hides itself
when the filtered result is empty.

## Deep-link fallback

When the user selects a card, the TCA reducer:

1. Calls `UIApplication.shared.open` for the platform's `deepLinkURL`, if present.
2. Stops when the completion result is `true`.
3. Opens `appStoreURL` when the deep link is absent or reports failure.
4. Emits the matching `openedApp`, `openedAppStore`, or `failedToOpen` event.

MoreAppsKit never calls `canOpenURL`, so it does not require the host to add custom
schemes to `LSApplicationQueriesSchemes` or make any other `Info.plist` change.
The target app must configure its own URL scheme or Universal Link if it wants to
accept the supplied deep link. HTTPS deep links use the system's
`universalLinksOnly` option so a missing target app falls back to the App Store
instead of opening Safari. Plain HTTP and system-action schemes such as `tel:`,
`sms:`, and `mailto:` are rejected.

## Events and privacy

Set `onEvent` to receive `impression`, `selected`, open-result, and loading-failure
events. An impression is emitted at most once per app in a data session, even when
the same cell scrolls off screen and reappears. Calling `setApps`, or completing a
new provider load, begins a new impression session.

The callback is purely local. MoreAppsKit includes no analytics SDK, stores no
events, collects no user data, and sends no analytics traffic.

## Configuration

`MoreAppsConfiguration` controls the title, title visibility, empty-state hiding,
corner radius, card spacing, directional insets, result limit, subtitle visibility,
and placeholder SF Symbol. A `nil` title uses the package's English/Korean string
catalog (`More Apps` / `다른 앱 둘러보기`). Supply `title` to override localization.

## SwiftUI

The package also provides a thin wrapper whose core remains the UIKit collection
view:

```swift
MoreAppsSwiftUIView(
    apps: apps,
    configuration: .default,
    onEvent: { print($0) }
)
```

## Public API overview

- `MoreApp`, `MoreAppDestination`, `MoreAppsPlatform`: Codable, hashable, sendable models.
- `MoreAppsFilter`: explicit pure filtering for custom catalog pipelines and tests.
- `MoreAppsProviding`, `StaticMoreAppsProvider`, `RemoteJSONMoreAppsProvider`: catalog sources.
- `MoreAppsOpening`, `DefaultMoreAppsOpener`: testable system URL opening.
- `MoreAppsConfiguration`: presentation and empty-state options.
- `MoreAppsImageLoader`: Alamofire HTTP loading, MIME validation, request coalescing,
  background decoding, and memory caching.
- `MoreAppsView`: UIKit entry point with `setApps`, `load`, `reload`, and `onEvent`.
- `MoreAppsSwiftUIView`: SwiftUI adapter around `MoreAppsView`.

Every public declaration includes DocC documentation in source. Internal reducers,
cells, event envelopes, and caches remain implementation details.

## Architecture and file roles

| Area | Responsibility |
| --- | --- |
| `Models` | Codable metadata, platform destinations, events, pure filtering |
| `Data` | Provider protocol/client, static provider, Alamofire remote provider |
| `Navigation` | URL-opening protocol, live `UIApplication` implementation, dependency key |
| `Feature` | TCA state, actions, effects, host environment dependency |
| `ImageLoading` | Alamofire image bytes, MIME checks, in-flight sharing, memory caches |
| `UI` | Configuration, reusable card cell, diffable UIKit view, SwiftUI wrapper |
| `Resources` | English and Korean string catalog |
| `Tests` | Swift Testing suites for filters, reducer effects, providers, and empty UI |

## Validation

The package is intended to be validated with Xcode 26 or newer:

```sh
xcodebuild -scheme MoreAppsKit -destination 'generic/platform=iOS' build
xcodebuild -scheme MoreAppsKit -destination 'generic/platform=tvOS' build
```

Run the Swift Testing suites on installed iOS 26 and tvOS 26 simulators:

```sh
xcodebuild -scheme MoreAppsKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' test
xcodebuild -scheme MoreAppsKit \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' test
```

The test target imports `Testing` and uses `@Suite`, `@Test`, and `#expect`; it
does not define `XCTestCase` subclasses.
