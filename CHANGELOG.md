# Changelog

## [0.1.1] - 2026-08-23

### Added

- Add a checked-in Swift formatting policy and document its strict validation command.

### Changed

- Standardize package sources, samples, and Swift Testing files on two-space indentation
  with consistent file headers.
- Update the remote JSON example with the production tvOS metadata, App Store destination,
  icon, and deep link for Andromeda 17K.

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
