import Foundation
import Testing
@testable import MoreAppsKit

@Suite
struct MoreAppsURLPolicyTests {
    @Test(
        arguments: [
            "tel:+18005551212",
            "sms:+18005551212",
            "mailto:person@example.com",
            "facetime:person@example.com",
            "App-Prefs:root=General",
            "http://example.com/open/sample"
        ]
    )
    func testSystemActionSchemesAreRejected(urlString: String) {
        let url = URL(string: urlString)!

        #expect(
            MoreAppsURLPolicy.allowedDeepLink(
                url,
                allowedCustomSchemes: []
            ) == nil
        )
    }

    @Test
    func testAllowlistedCustomSchemeAndUniversalLinkAreSupported() {
        let customURL = URL(string: "sample://home")!
        let universalLink = URL(string: "https://example.com/open/sample")!

        #expect(
            MoreAppsURLPolicy.allowedDeepLink(
                customURL,
                allowedCustomSchemes: ["SAMPLE"]
            ) == customURL
        )
        #expect(
            MoreAppsURLPolicy.allowedDeepLink(
                universalLink,
                allowedCustomSchemes: []
            ) == universalLink
        )
    }

    @Test
    func testUnlistedCustomSchemeIsRejected() {
        let url = URL(string: "shortcuts://run-shortcut?name=Unexpected")!

        #expect(
            MoreAppsURLPolicy.allowedDeepLink(
                url,
                allowedCustomSchemes: ["sample"]
            ) == nil
        )
    }

    @Test
    func testAppStoreURLIsNotTreatedAsADeepLink() {
        let url = URL(string: "https://apps.apple.com/app/id100")!

        #expect(
            MoreAppsURLPolicy.allowedDeepLink(
                url,
                allowedCustomSchemes: []
            ) == nil
        )
    }

    @Test(
        arguments: [
            "https://apps.apple.com/app/id100",
            "itms-apps://apps.apple.com/app/id100",
            "https://itunes.apple.com/app/id100"
        ]
    )
    func testSupportedAppStoreRoutesAreAccepted(urlString: String) {
        let url = URL(string: urlString)!

        #expect(MoreAppsURLPolicy.allowedAppStoreURL(url) == url)
    }

    @Test
    func testSchemelessDeepLinkAndHTTPStoreURLAreRejected() {
        let schemelessDeepLink = URL(string: "example.com/open/sample")!
        let insecureStoreURL = URL(
            string: "http://apps.apple.com/app/id100"
        )!

        #expect(
            MoreAppsURLPolicy.allowedDeepLink(
                schemelessDeepLink,
                allowedCustomSchemes: []
            ) == nil
        )
        #expect(MoreAppsURLPolicy.allowedAppStoreURL(insecureStoreURL) == nil)
    }

    @MainActor
    @Test
    func testOnlyNonStoreHTTPSLinksRequireUniversalLinkHandling() {
        let universalLink = URL(string: "https://example.com/open/sample")!
        let storeURL = URL(string: "https://apps.apple.com/app/id100")!
        let customURL = URL(string: "sample://home")!

        #expect(
            DefaultMoreAppsOpener.usesUniversalLinksOnly(for: universalLink)
        )
        #expect(!DefaultMoreAppsOpener.usesUniversalLinksOnly(for: storeURL))
        #expect(!DefaultMoreAppsOpener.usesUniversalLinksOnly(for: customURL))
    }
}
