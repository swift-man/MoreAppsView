# MoreAppsKit

MoreAppsKit is a reusable UIKit package for cross-promoting your own apps with
clean, horizontally scrolling App Store-style cards. It filters the catalog for
the host platform, removes the current app, can present platform-native store
entry points, and emits optional closure-based events without collecting user
data.

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
    from: "0.2.1"
  )
]
```

Then add `MoreAppsKit` to the consuming target and import it:

```swift
import MoreAppsKit
```

The package resolves compatible versions of TCA, Dependencies, and Alamofire
transitively; the host app does not need to add those products to its own target.
The current package version is recorded in [VERSION.txt](VERSION.txt), and shipped
changes are listed in [CHANGELOG.md](CHANGELOG.md).

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
    id: "andromeda-17k",
    bundleIdentifier: "me.gorani.Andromeda17K",
    name: "Andromeda 17K: Clock&Wallpaper",
    subtitle: "17K galaxy panorama and full-screen clock",
    iconURL: URL(
      string: "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/fd/e7/8a/fde78abc-df06-a02f-0ccb-e3bc68c973c3/App_Icon-marketing.lsr/512x512bb.jpg"
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
  )
]

let moreAppsView = MoreAppsView(
  configuration: .init(
    showsTitle: true,
    hidesWhenEmpty: true,
    allowedCustomDeepLinkSchemes: ["wordrush", "andromeda17k"]
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

Add the view to any UIKit hierarchy. Platform presentation takes an explicit host
controller instead of discovering one from global application state:

```swift
final class AppsViewController: UIViewController {
  private lazy var moreAppsView = MoreAppsView(
    configuration: .init(
      allowedCustomDeepLinkSchemes: ["wordrush"],
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
      moreAppsView.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor
      ),
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
are enabled by default. With `.platformPresentation`, a successful deep link
opens the installed app; otherwise StoreKit displays Apple's App Store overlay
in the view controller's active window scene. If the overlay cannot load, the
validated App Store URL remains the fallback.

See [Samples/iOS/MoreAppsExampleViewController.swift](Samples/iOS/MoreAppsExampleViewController.swift)
for a complete example.

## tvOS integration

The UIKit setup is the same on tvOS. Only apps with a `.tvOS` destination are
displayed. Cards are larger and use the Focus Engine, coordinated focus scaling,
elevated z-order, additional clipping insets, and reduced animation when Reduce
Motion is enabled.

```swift
final class TVAppsViewController: UIViewController {
  private let focusedBackgroundView = MoreAppsFocusedBackgroundView()

  private lazy var moreAppsView = MoreAppsView(
    configuration: .init(
      title: "More Apps on Apple TV",
      cardSpacing: 28,
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
      focusedBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      focusedBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      focusedBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      moreAppsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      moreAppsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      moreAppsView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])

    moreAppsView.setApps(sharedCatalog)
  }
}
```

When the focused destination has a `backgroundImageURL`, the host-owned
`MoreAppsFocusedBackgroundView` requests artwork with a maximum decoded dimension
of 1,920 pixels by default, applies a dark legibility overlay, and crossfades it
behind the cards. Focus changes cancel stale work, and Reduce Motion disables the
crossfade.
A destination without artwork clears the previous image instead of showing another
app's screenshot. The sample catalog uses Andromeda 17K's first App Store tvOS
screenshot; for production catalogs, hosting approved artwork on a URL you control
avoids depending on a storefront asset URL remaining stable.

Selecting a card immediately tries the validated deep link. If the system accepts
it, the installed app opens; otherwise MoreAppsKit hands the validated App Store
URL to the system App Store app. No intermediate popup or package-owned preview is
presented. tvOS does not provide `SKOverlay` or an in-app App Store product
controller, so the final App Store experience always belongs to the system.

See [Samples/tvOS/MoreAppsExampleViewController.swift](Samples/tvOS/MoreAppsExampleViewController.swift)
for a complete example.

## Remote JSON

`RemoteJSONMoreAppsProvider` uses Alamofire, requires HTTPS throughout redirects,
limits catalog responses to one megabyte, validates HTTP status codes, and
distinguishes transport/HTTP failures from JSON decoding failures:

```swift
let endpoint = URL(string: "https://example.com/more-apps.json")!
let provider = RemoteJSONMoreAppsProvider(url: endpoint)
let moreAppsView = MoreAppsView(
  configuration: .init(
    allowedCustomDeepLinkSchemes: [
      "reactionspeed",
      "andromeda17k",
      "sharedcompanion",
    ]
  )
)

Task {
  await moreAppsView.load(using: provider)
}
```

Call `await moreAppsView.reload()` to fetch again with the most recently supplied
provider. Starting another provider load cancels the prior TCA effect so a stale
response cannot replace newer state.

The optional `backgroundImageURL` belongs to each platform destination. The built-in
focus-background synchronization reads it from the matching tvOS destination, and
older catalogs that omit it continue to decode. The JSON schema is demonstrated in
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

## Selection and App Store presentation

`MoreAppsConfiguration.selectionBehavior` supports two policies:

- `.directOpen` preserves the original behavior and remains the default.
- `.platformPresentation` uses an iOS StoreKit overlay. On tvOS it intentionally
  matches `.directOpen`, so no presenter or presenting view controller is needed.

In direct-open mode, the TCA reducer:

1. Validates the platform's `deepLinkURL` against the host's policy.
2. Calls `UIApplication.shared.open` for an allowed deep link, if present.
3. Stops when the completion result is `true`.
4. Opens `appStoreURL` when the deep link is absent, rejected, or reports failure.
5. Emits the matching `openedApp`, `openedAppStore`, or `failedToOpen` event.

MoreAppsKit never calls `canOpenURL`, so it does not require the host to add custom
schemes to `LSApplicationQueriesSchemes` or make any other `Info.plist` change.
The target app must configure its own URL scheme or Universal Link if it wants to
accept the supplied deep link. HTTPS deep links use the system's
`universalLinksOnly` option so a missing target app falls back to the App Store
instead of opening Safari. Plain HTTP and unlisted custom or system-action schemes
are rejected. Add only the target apps' trusted scheme names to
`allowedCustomDeepLinkSchemes`; its default is an empty set.

In platform-presentation mode, iOS tries the same validated deep link first. A
failed or missing deep link presents `SKOverlay` using the numeric identifier in
the validated App Store URL, and a presentation failure safely falls back to the
App Store URL. tvOS bypasses the presentation dependency and follows the direct
deep-link-first, App-Store-fallback flow immediately.

A custom `MoreAppsPresenting` implementation keeps `present(_:)` suspended until
its UI lifecycle ends. It dismisses that UI and returns `.dismissed` when its task
is cancelled, allowing catalog and filtering changes to remove stale presentation.

The `openedAppStore` event means the operating system accepted the URL handoff.
It cannot confirm that the product page loaded, the product is available in the
current storefront, or the app was installed.

## Events and privacy

Set `onEvent` to receive `impression`, `selected`, open-result, and loading-failure
events. An impression is emitted at most once per app in a data session, even when
the same cell scrolls off screen and reappears. Calling `setApps`, or completing a
new provider load, begins a new impression session.

The callback is purely local. MoreAppsKit includes no analytics SDK, persists no
events to disk, collects no user data, and sends no analytics traffic. It retains
up to 100 undelivered events temporarily in memory until a handler can receive
them.

## Configuration

`MoreAppsConfiguration` controls the title, title visibility, empty-state hiding,
corner radius, card spacing, directional insets, result limit, subtitle visibility,
trusted custom deep-link schemes, selection behavior, and placeholder SF Symbol.
A `nil` title uses the package's English/Korean string catalog (`More Apps` /
`다른 앱 둘러보기`). Supply `title` to override localization.

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

The wrapper accepts an optional `MoreAppsPresenting` implementation when an iOS
SwiftUI host opts into platform presentation. tvOS and direct-open behavior do
not require a presenter.

## Public API overview

- `MoreApp`, `MoreAppDestination`, `MoreAppsPlatform`: Codable, hashable, sendable models.
- `MoreAppsFilter`: explicit pure filtering for custom catalog pipelines and tests.
- `MoreAppsProviding`, `StaticMoreAppsProvider`, `RemoteJSONMoreAppsProvider`: catalog sources.
- `MoreAppsOpening`, `DefaultMoreAppsOpener`: testable system URL opening.
- `MoreAppsPresenting`, `DefaultMoreAppsPresenter`: testable iOS StoreKit
  presentation without expanding the URL opener's responsibility.
- `MoreAppsSelectionBehavior`: source-compatible direct opening or opt-in iOS StoreKit UI.
- `MoreAppsConfiguration`: presentation, empty-state, and trusted deep-link options.
- `MoreAppsImageLoader`: Alamofire HTTP loading, MIME validation, request coalescing,
  size-aware background decoding, and memory caching.
- `MoreAppsFocusedBackgroundView`: optional host-owned full-screen focus artwork.
- `MoreAppsView`: UIKit entry point with `setApps`, `load`, `reload`, `onEvent`, and
  focus-background synchronization.
- `MoreAppsSwiftUIView`: SwiftUI adapter around `MoreAppsView`.

Every public declaration includes DocC documentation in source. Internal reducers,
cells, event envelopes, and caches remain implementation details.

## Architecture and file roles

| Area | Responsibility |
| --- | --- |
| `Models` | Codable metadata, platform destinations, events, pure filtering |
| `Data` | Provider protocol/client, static provider, Alamofire remote provider |
| `Navigation` | URL-opening protocol, live `UIApplication` implementation, dependency key |
| `Presentation` | iOS StoreKit overlay and presenter dependency key |
| `Feature` | TCA state, actions, effects, host environment dependency |
| `ImageLoading` | Alamofire image bytes, MIME checks, in-flight sharing, memory caches |
| `UI` | Configuration, reusable card cell, diffable UIKit view, SwiftUI wrapper |
| `Resources` | English and Korean string catalog |
| `Tests` | Swift Testing suites for filters, reducer effects, providers, and empty UI |

## Validation

The package is intended to be validated with Xcode 26 or newer:

```sh
xcrun swift-format lint --strict --recursive --parallel \
  --configuration .swift-format Package.swift Samples Sources Tests
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
