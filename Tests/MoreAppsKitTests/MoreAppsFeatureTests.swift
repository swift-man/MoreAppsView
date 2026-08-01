import ComposableArchitecture
import Foundation
import Testing
@testable import MoreAppsKit

@MainActor
@Suite
struct MoreAppsFeatureTests {
    @Test
    func testDeepLinkSuccessDoesNotOpenAppStore() async {
        let recorder = OpenRecorder(results: [true])
        let store = makeStore(
            app: TestFixtures.app(),
            recorder: recorder
        )

        await store.send(.selected(appID: "sample")) {
            $0.openingAppIDs = ["sample"]
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .selected(appID: "sample"))
            ]
        }
        await store.receive({ action in
            guard case .openFinished(
                dataSessionID: 0,
                appID: "sample",
                outcome: .app
            ) = action else {
                return false
            }
            return true
        }) {
            $0.openingAppIDs = []
            $0.nextEventID = 2
            $0.pendingEvents.append(
                .init(id: 2, event: .openedApp(appID: "sample"))
            )
        }

        #expect(recorder.openedURLs == [TestFixtures.deepLinkURL])
    }

    @Test
    func testDeepLinkFailureFallsBackToAppStore() async {
        let recorder = OpenRecorder(results: [false, true])
        let store = makeStore(
            app: TestFixtures.app(),
            recorder: recorder
        )

        await store.send(.selected(appID: "sample")) {
            $0.openingAppIDs = ["sample"]
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .selected(appID: "sample"))
            ]
        }
        await store.receive({ action in
            guard case .openFinished(
                dataSessionID: 0,
                appID: "sample",
                outcome: .appStore
            ) = action else {
                return false
            }
            return true
        }) {
            $0.openingAppIDs = []
            $0.nextEventID = 2
            $0.pendingEvents.append(
                .init(id: 2, event: .openedAppStore(appID: "sample"))
            )
        }

        #expect(
            recorder.openedURLs
                == [TestFixtures.deepLinkURL, TestFixtures.iOSStoreURL]
        )
    }

    @Test
    func testMissingDeepLinkOpensAppStoreImmediately() async {
        let recorder = OpenRecorder(results: [true])
        let store = makeStore(
            app: TestFixtures.app(deepLinkURL: nil),
            recorder: recorder
        )

        await store.send(.selected(appID: "sample")) {
            $0.openingAppIDs = ["sample"]
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .selected(appID: "sample"))
            ]
        }
        await store.receive({ action in
            guard case .openFinished(
                dataSessionID: 0,
                appID: "sample",
                outcome: .appStore
            ) = action else {
                return false
            }
            return true
        }) {
            $0.openingAppIDs = []
            $0.nextEventID = 2
            $0.pendingEvents.append(
                .init(id: 2, event: .openedAppStore(appID: "sample"))
            )
        }

        #expect(recorder.openedURLs == [TestFixtures.iOSStoreURL])
    }

    @Test
    func testProviderErrorBecomesLoadingFailedEvent() async {
        struct LoadError: LocalizedError {
            var errorDescription: String? { "Offline" }
        }

        let store = TestStore(
            initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
        ) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
        }

        await store.send(
            .load(.init { throw LoadError() })
        ) {
            $0.isLoading = true
            $0.nextLoadID = 1
            $0.activeLoadID = 1
        }
        await store.receive({ action in
            guard case .loadFailed(id: 1, message: "Offline") = action else {
                return false
            }
            return true
        }) {
            $0.isLoading = false
            $0.activeLoadID = nil
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .loadingFailed(message: "Offline"))
            ]
        }
    }

    @Test
    func testProviderLoadSuccessAppliesFilteredApps() async {
        let app = TestFixtures.app()
        let store = TestStore(
            initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
        ) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
        }

        await store.send(.load(.init { [app] })) {
            $0.isLoading = true
            $0.nextLoadID = 1
            $0.activeLoadID = 1
        }
        await store.receive({ action in
            guard case let .loadSucceeded(id, apps) = action else {
                return false
            }
            return id == 1 && apps == [app]
        }) {
            $0.sourceApps = [app]
            $0.apps = [app]
            $0.dataSessionID = 1
            $0.isLoading = false
            $0.activeLoadID = nil
        }
    }

    @Test
    func testUnrequestedCancellationErrorBecomesLoadingFailure() async {
        let message = CancellationError().localizedDescription
        let store = TestStore(
            initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
        ) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
        }

        await store.send(
            .load(.init { throw CancellationError() })
        ) {
            $0.isLoading = true
            $0.nextLoadID = 1
            $0.activeLoadID = 1
        }
        await store.receive({ action in
            guard case let .loadFailed(id, receivedMessage) = action else {
                return false
            }
            return id == 1 && receivedMessage == message
        }) {
            $0.isLoading = false
            $0.activeLoadID = nil
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .loadingFailed(message: message))
            ]
        }
    }

    @Test
    func testStaleProviderResponseCannotReplaceCurrentState() async {
        let currentApp = TestFixtures.app(id: "current")
        var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
        state.apps = [currentApp]
        state.isLoading = true
        state.nextLoadID = 2
        state.activeLoadID = 2

        let store = TestStore(initialState: state) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
        }

        await store.send(
            .loadSucceeded(
                id: 1,
                apps: [TestFixtures.app(id: "stale")]
            )
        )
    }

    @Test
    func testStaleProviderFailureDoesNotEmitAnEvent() async {
        var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
        state.isLoading = true
        state.nextLoadID = 2
        state.activeLoadID = 2

        let store = TestStore(initialState: state) {
            MoreAppsFeature()
        }

        await store.send(.loadFailed(id: 1, message: "Stale"))
    }

    @Test
    func testSetAppsCancelsAnActiveProviderLoad() async {
        let replacement = TestFixtures.app(id: "replacement")
        let store = TestStore(
            initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
        ) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
        }

        await store.send(
            .load(.init {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return [TestFixtures.app(id: "stale")]
            })
        ) {
            $0.isLoading = true
            $0.nextLoadID = 1
            $0.activeLoadID = 1
        }
        await store.send(.setApps([replacement])) {
            $0.sourceApps = [replacement]
            $0.apps = [replacement]
            $0.dataSessionID = 1
            $0.isLoading = false
            $0.activeLoadID = nil
        }
    }

    @Test
    func testReplacementLoadCancelsItsPredecessor() async {
        let fresh = TestFixtures.app(id: "fresh")
        let store = TestStore(
            initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
        ) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
        }

        await store.send(
            .load(.init {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return [TestFixtures.app(id: "stale")]
            })
        ) {
            $0.isLoading = true
            $0.nextLoadID = 1
            $0.activeLoadID = 1
        }
        await store.send(.load(.init { [fresh] })) {
            $0.nextLoadID = 2
            $0.activeLoadID = 2
        }
        await store.receive({ action in
            guard case let .loadSucceeded(id, apps) = action else {
                return false
            }
            return id == 2 && apps == [fresh]
        }) {
            $0.sourceApps = [fresh]
            $0.apps = [fresh]
            $0.dataSessionID = 1
            $0.isLoading = false
            $0.activeLoadID = nil
        }
    }

    @Test
    func testImpressionIsEmittedOncePerDataSession() async {
        let store = TestStore(
            initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
        ) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
        }

        await store.send(.setApps([TestFixtures.app()])) {
            $0.sourceApps = [TestFixtures.app()]
            $0.apps = [TestFixtures.app()]
            $0.dataSessionID = 1
        }
        await store.send(.itemBecameVisible(appID: "sample")) {
            $0.impressedAppIDs = ["sample"]
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .impression(appID: "sample"))
            ]
        }
        await store.send(.itemBecameVisible(appID: "sample"))
    }

    @Test
    func testNewCatalogResetsImpressionEligibility() async {
        let app = TestFixtures.app()
        var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
        state.sourceApps = [app]
        state.apps = [app]
        state.impressedAppIDs = [app.id]

        let store = TestStore(initialState: state) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
        }

        await store.send(.setApps([app])) {
            $0.dataSessionID = 1
            $0.impressedAppIDs = []
        }
        await store.send(.itemBecameVisible(appID: app.id)) {
            $0.impressedAppIDs = [app.id]
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .impression(appID: app.id))
            ]
        }
    }

    @Test
    func testUnknownImpressionAndDuplicateSelectionAreIgnored() async {
        var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
        state.apps = [TestFixtures.app()]
        state.openingAppIDs = ["sample"]

        let store = TestStore(initialState: state) {
            MoreAppsFeature()
        }

        await store.send(.itemBecameVisible(appID: "missing"))
        await store.send(.selected(appID: "sample"))
        await store.send(.selected(appID: "missing"))
    }

    @Test
    func testSelectionWithoutCurrentPlatformDestinationIsIgnored() async {
        var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
        state.apps = [TestFixtures.app(platforms: [.tvOS])]

        let store = TestStore(initialState: state) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
        }

        await store.send(.selected(appID: "sample"))
    }

    @Test
    func testFailedStoreOpenEmitsFailedToOpen() async {
        let recorder = OpenRecorder(results: [false, false])
        let store = makeStore(
            app: TestFixtures.app(),
            recorder: recorder
        )

        await store.send(.selected(appID: "sample")) {
            $0.openingAppIDs = ["sample"]
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .selected(appID: "sample"))
            ]
        }
        await store.receive({ action in
            guard case .openFinished(
                dataSessionID: 0,
                appID: "sample",
                outcome: .failed
            ) = action else {
                return false
            }
            return true
        }) {
            $0.openingAppIDs = []
            $0.nextEventID = 2
            $0.pendingEvents.append(
                .init(id: 2, event: .failedToOpen(appID: "sample"))
            )
        }

        #expect(
            recorder.openedURLs
                == [TestFixtures.deepLinkURL, TestFixtures.iOSStoreURL]
        )
    }

    @Test
    func testBlockedDeepLinkFallsBackToValidatedAppStoreURL() async {
        let blockedURL = URL(fileURLWithPath: "/tmp/not-an-app-link")
        let recorder = OpenRecorder(results: [true])
        let store = makeStore(
            app: TestFixtures.app(deepLinkURL: blockedURL),
            recorder: recorder
        )

        await store.send(.selected(appID: "sample")) {
            $0.openingAppIDs = ["sample"]
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .selected(appID: "sample"))
            ]
        }
        await store.receive({ action in
            guard case .openFinished(
                dataSessionID: 0,
                appID: "sample",
                outcome: .appStore
            ) = action else {
                return false
            }
            return true
        }) {
            $0.openingAppIDs = []
            $0.nextEventID = 2
            $0.pendingEvents.append(
                .init(id: 2, event: .openedAppStore(appID: "sample"))
            )
        }

        #expect(recorder.openedURLs == [TestFixtures.iOSStoreURL])
    }

    @Test
    func testUntrustedStoreURLIsRejectedWithoutOpening() async {
        let untrustedURL = URL(string: "https://example.com/not-the-app-store")!
        let recorder = OpenRecorder(results: [true])
        let store = makeStore(
            app: TestFixtures.app(
                deepLinkURL: nil,
                appStoreURL: untrustedURL
            ),
            recorder: recorder
        )

        await store.send(.selected(appID: "sample")) {
            $0.nextEventID = 2
            $0.pendingEvents = [
                .init(id: 1, event: .selected(appID: "sample")),
                .init(id: 2, event: .failedToOpen(appID: "sample"))
            ]
        }

        #expect(recorder.openedURLs.isEmpty)
    }

    @Test
    func testAppStoreDeepLinkUsesAppStoreOutcome() async {
        let recorder = OpenRecorder(results: [true])
        let store = makeStore(
            app: TestFixtures.app(
                deepLinkURL: TestFixtures.iOSStoreURL
            ),
            recorder: recorder
        )

        await store.send(.selected(appID: "sample")) {
            $0.openingAppIDs = ["sample"]
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .selected(appID: "sample"))
            ]
        }
        await store.receive({ action in
            guard case .openFinished(
                dataSessionID: 0,
                appID: "sample",
                outcome: .appStore
            ) = action else {
                return false
            }
            return true
        }) {
            $0.openingAppIDs = []
            $0.nextEventID = 2
            $0.pendingEvents.append(
                .init(id: 2, event: .openedAppStore(appID: "sample"))
            )
        }

        #expect(recorder.openedURLs == [TestFixtures.iOSStoreURL])
    }

    @Test
    func testReplacingCatalogRejectsStaleOpenResult() async {
        let oldApp = TestFixtures.app()
        let replacement = TestFixtures.app(bundleIdentifier: "com.example.new")
        var state = MoreAppsFeature.State(
            maximumNumberOfItems: nil,
            allowedCustomDeepLinkSchemes: ["sample"]
        )
        state.sourceApps = [oldApp]
        state.apps = [oldApp]
        state.openingAppIDs = [oldApp.id]

        let recorder = OpenRecorder(results: [true])
        let store = TestStore(initialState: state) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
            $0.moreAppsOpen = MoreAppsOpenClient { url in
                recorder.open(url)
            }
        }

        await store.send(.setApps([replacement])) {
            $0.sourceApps = [replacement]
            $0.apps = [replacement]
            $0.openingAppIDs = []
            $0.dataSessionID = 1
        }
        await store.send(
            .openFinished(
                dataSessionID: 0,
                appID: oldApp.id,
                outcome: .app
            )
        )
        await store.send(.selected(appID: replacement.id)) {
            $0.openingAppIDs = [replacement.id]
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .selected(appID: replacement.id))
            ]
        }
        await store.receive({ action in
            guard case .openFinished(
                dataSessionID: 1,
                appID: replacement.id,
                outcome: .app
            ) = action else {
                return false
            }
            return true
        }) {
            $0.openingAppIDs = []
            $0.nextEventID = 2
            $0.pendingEvents.append(
                .init(id: 2, event: .openedApp(appID: replacement.id))
            )
        }
    }

    @Test
    func testReplacingCatalogPreventsStaleAppStoreFallback() async {
        let oldApp = TestFixtures.app()
        let replacement = TestFixtures.app(
            id: "replacement",
            bundleIdentifier: "com.example.new"
        )
        var state = MoreAppsFeature.State(
            maximumNumberOfItems: nil,
            allowedCustomDeepLinkSchemes: ["sample"]
        )
        state.sourceApps = [oldApp]
        state.apps = [oldApp]
        let recorder = DeferredOpenRecorder()

        let store = TestStore(initialState: state) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
            $0.moreAppsOpen = MoreAppsOpenClient { url in
                await recorder.open(url)
            }
        }

        await store.send(.selected(appID: oldApp.id)) {
            $0.openingAppIDs = [oldApp.id]
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .selected(appID: oldApp.id))
            ]
        }
        await recorder.waitUntilFirstOpenStarts()

        await store.send(.setApps([replacement])) {
            $0.sourceApps = [replacement]
            $0.apps = [replacement]
            $0.openingAppIDs = []
            $0.dataSessionID = 1
        }

        recorder.finishFirstOpen(with: false)
        await store.finish()

        #expect(recorder.openedURLs == [TestFixtures.deepLinkURL])
    }

    @Test
    func testCancelledOpenClientDoesNotInvokeUnderlyingOpener() async {
        let recorder = OpenRecorder(results: [true])
        let client = MoreAppsOpenClient { url in
            recorder.open(url)
        }
        let task = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            return await client(TestFixtures.iOSStoreURL)
        }

        task.cancel()

        #expect(await task.value == false)
        #expect(recorder.openedURLs.isEmpty)
    }

    @Test
    func testChangingMaximumRestoresItemsFromTheSourceCatalog() async {
        let apps = [
            TestFixtures.app(id: "first", sortOrder: 0),
            TestFixtures.app(id: "second", sortOrder: 1),
            TestFixtures.app(id: "third", sortOrder: 2)
        ]
        let store = TestStore(
            initialState: MoreAppsFeature.State(maximumNumberOfItems: nil)
        ) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
        }

        await store.send(.setApps(apps)) {
            $0.sourceApps = apps
            $0.apps = apps
            $0.dataSessionID = 1
        }
        await store.send(.itemBecameVisible(appID: apps[0].id)) {
            $0.impressedAppIDs = [apps[0].id]
            $0.nextEventID = 1
            $0.pendingEvents = [
                .init(id: 1, event: .impression(appID: apps[0].id))
            ]
        }
        await store.send(.setMaximumNumberOfItems(1)) {
            $0.maximumNumberOfItems = 1
            $0.apps = [apps[0]]
        }
        await store.send(.setMaximumNumberOfItems(nil)) {
            $0.maximumNumberOfItems = nil
            $0.apps = apps
        }
    }

    @Test
    func testEventDeliveryAcknowledgesOnlyMatchingEnvelope() async {
        var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
        state.pendingEvents = [
            .init(id: 1, event: .selected(appID: "first")),
            .init(id: 2, event: .selected(appID: "second"))
        ]

        let store = TestStore(initialState: state) {
            MoreAppsFeature()
        }

        await store.send(.eventDelivered(1)) {
            $0.pendingEvents = [
                .init(id: 2, event: .selected(appID: "second"))
            ]
        }
    }

    @Test
    func testPendingEventBacklogIsBounded() {
        let apps = (0...MoreAppsFeature.maximumPendingEventCount).map { index in
            TestFixtures.app(id: "app-\(index)")
        }
        var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
        state.apps = apps

        let store = Store(initialState: state) {
            MoreAppsFeature()
        }

        for app in apps {
            store.send(.itemBecameVisible(appID: app.id))
        }

        #expect(
            store.pendingEvents.count
                == MoreAppsFeature.maximumPendingEventCount
        )
        #expect(store.pendingEvents.first?.id == 2)
        #expect(
            store.pendingEvents.last?.id
                == MoreAppsFeature.maximumPendingEventCount + 1
        )
    }

    private func makeStore(
        app: MoreApp,
        recorder: OpenRecorder
    ) -> TestStoreOf<MoreAppsFeature> {
        var state = MoreAppsFeature.State(maximumNumberOfItems: nil)
        state.apps = [app]
        state.allowedCustomDeepLinkSchemes = ["sample"]

        return TestStore(initialState: state) {
            MoreAppsFeature()
        } withDependencies: {
            $0.moreAppsEnvironment = .init(
                platform: .iOS,
                bundleIdentifier: nil
            )
            $0.moreAppsOpen = MoreAppsOpenClient { url in
                recorder.open(url)
            }
        }
    }
}

@MainActor
private final class OpenRecorder {
    private var results: [Bool]
    private(set) var openedURLs: [URL] = []

    init(results: [Bool]) {
        self.results = results
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        guard !results.isEmpty else { return false }
        return results.removeFirst()
    }
}

@MainActor
private final class DeferredOpenRecorder {
    private(set) var openedURLs: [URL] = []
    private var firstOpenContinuation: CheckedContinuation<Bool, Never>?
    private var firstOpenStartWaiters: [CheckedContinuation<Void, Never>] = []

    func open(_ url: URL) async -> Bool {
        openedURLs.append(url)
        guard openedURLs.count == 1 else { return true }

        firstOpenStartWaiters.forEach { $0.resume() }
        firstOpenStartWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            firstOpenContinuation = continuation
        }
    }

    func waitUntilFirstOpenStarts() async {
        guard openedURLs.isEmpty else { return }
        await withCheckedContinuation { continuation in
            firstOpenStartWaiters.append(continuation)
        }
    }

    func finishFirstOpen(with result: Bool) {
        firstOpenContinuation?.resume(returning: result)
        firstOpenContinuation = nil
    }
}
