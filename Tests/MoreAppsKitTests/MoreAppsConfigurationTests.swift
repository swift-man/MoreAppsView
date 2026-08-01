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
}
