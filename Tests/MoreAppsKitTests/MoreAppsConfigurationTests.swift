import Testing
@testable import MoreAppsKit

struct MoreAppsConfigurationTests {
    @Test
    func testSynthesizedEqualityTracksConfigurationChanges() {
        let baseline = MoreAppsConfiguration.default
        var changed = baseline

        #expect(baseline == changed)

        changed.allowedCustomDeepLinkSchemes = ["wordrush"]

        #expect(baseline != changed)
    }

    @Test
    func testCustomSchemesAreNormalizedWhenAssigned() {
        var configuration = MoreAppsConfiguration(
            allowedCustomDeepLinkSchemes: ["SAMPLE", ""]
        )

        #expect(configuration.allowedCustomDeepLinkSchemes == ["sample"])

        configuration.allowedCustomDeepLinkSchemes = ["WordRush"]

        #expect(configuration.allowedCustomDeepLinkSchemes == ["wordrush"])
    }
}
