# Changelog

## [0.1.0] - 2026-08-01

- Use the public `MoreAppsKit` Swift package to add cross-promotion UI to iOS 26.0 and tvOS 26.0 apps.
- Keep catalog state, filtering, event delivery, and deep-link fallback consistent through TCA-driven effects.
- Choose an in-memory static catalog or load remote JSON through Alamofire.
- Load icons through a cached, coalesced Alamofire pipeline that avoids duplicate requests.
- Embed MoreAppsKit from UIKit or SwiftUI with Dynamic Type, VoiceOver, and tvOS focus support.
- Start from iOS/tvOS integration samples backed by Swift Testing coverage.
