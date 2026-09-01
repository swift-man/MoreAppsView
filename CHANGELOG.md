# Changelog

## [0.2.1] - 2026-09-02

### Added

- Let tvOS selections immediately open an installed promoted app, with automatic fallback
  to the system App Store when the app cannot be opened.
- Add optional platform-specific focus artwork and a host-owned full-screen background
  view with stale-request cancellation, dimming, crossfade, and Reduce Motion support.

### Changed

- Bypass platform presentation on tvOS so selecting a card never shows an intermediate
  popup or package-owned preview.
- Keep card VoiceOver guidance aligned with the immediate deep-link-first, App Store
  fallback behavior.
- Use Andromeda 17K's first tvOS App Store screenshot in the sample catalog and decode
  full-screen artwork independently from card-sized icons.

## [0.2.0] - 2026-08-23

### Added

- Add an opt-in platform presentation policy while preserving direct URL opening as the
  source-compatible default.
- Present a StoreKit App Store overlay after iOS deep-link fallback and a focus-aware app
  detail sheet with explicit App Store and close actions on tvOS.
- Inject platform presentation through a public `MoreAppsPresenting` boundary and a TCA
  dependency, including SwiftUI presenter replacement support.

### Changed

- Validate a single numeric App Store path identifier before configuring the iOS overlay,
  while retaining the validated App Store URL as a safe fallback.
- Keep presentation effects alive through dismissal so catalog or filtering changes cancel
  stale UI, and clarify that App Store events report URL handoff rather than product-page
  loading.
- Keep tvOS presentation failures inside the host app, and retain iOS overlay state until
  StoreKit reports that its dismissal transition has finished.
- Localize platform-presentation accessibility actions and make the tvOS image cancellation
  test yield execution without busy-waiting on the main actor.

## [0.1.1] - 2026-08-23

### Added

- Add a checked-in Swift formatting policy and document its strict validation command.

### Changed

- Standardize package sources, samples, and Swift Testing files on two-space indentation
  with consistent file headers.
- Keep the README, remote JSON, and tvOS integration sample aligned with the production
  metadata, App Store destination, icon, and deep link for Andromeda 17K.
- Preserve the failing coding path and decoding context in remote-catalog diagnostics.
- Avoid retaining `MoreAppsView` across event-delivery suspension points.

## [0.1.0] - 2026-08-01

- Use the public `MoreAppsKit` Swift package to add cross-promotion UI to iOS 26.0 and tvOS 26.0 apps.
- Keep catalog state, filtering, event delivery, and deep-link fallback consistent through TCA-driven effects.
- Choose an in-memory static catalog or load remote JSON through Alamofire.
- Share each icon URL's download, decoding, and cache publication through a coalesced
  Alamofire pipeline, avoiding duplicate network and CPU work while cancelling transport
  only after its last caller or owning cell is released.
- Bound remote catalog and decoded icon memory, enforce HTTPS redirects, and require
  normalized, host-approved custom deep-link schemes.
- Ignore stale URL-opening results after a catalog session is replaced.
- Compare presentation configurations through synthesized `Equatable` conformance.
- Embed MoreAppsKit from UIKit or SwiftUI with Dynamic Type, VoiceOver, and tvOS focus support.
- Start from iOS/tvOS integration samples backed by Swift Testing coverage.
