import ComposableArchitecture
import Foundation

struct MoreAppsFeature: Reducer {
    static let maximumPendingEventCount = 100

    @ObservableState
    struct State: Equatable, Sendable {
        var sourceApps: [MoreApp] = []
        var apps: [MoreApp] = []
        var isLoading = false
        var maximumNumberOfItems: Int?
        var allowedCustomDeepLinkSchemes: Set<String>
        var impressedAppIDs = Set<MoreApp.ID>()
        var openingAppIDs = Set<MoreApp.ID>()
        var pendingEvents: [EventEnvelope] = []
        var dataSessionID = 0
        var nextEventID = 0
        var nextLoadID = 0
        var activeLoadID: Int?

        init(
            maximumNumberOfItems: Int?,
            allowedCustomDeepLinkSchemes: Set<String> = []
        ) {
            self.maximumNumberOfItems = maximumNumberOfItems
            self.allowedCustomDeepLinkSchemes = allowedCustomDeepLinkSchemes
        }
    }

    enum Action: Sendable {
        case setApps([MoreApp])
        case setMaximumNumberOfItems(Int?)
        case setAllowedCustomDeepLinkSchemes(Set<String>)
        case load(MoreAppsProviderClient)
        case loadSucceeded(id: Int, apps: [MoreApp])
        case loadFailed(id: Int, message: String)
        case itemBecameVisible(appID: MoreApp.ID)
        case selected(appID: MoreApp.ID)
        case openFinished(
            dataSessionID: Int,
            appID: MoreApp.ID,
            outcome: OpenOutcome
        )
        case eventDelivered(Int)
    }

    struct EventEnvelope: Equatable, Sendable {
        let id: Int
        let event: MoreAppsEvent
    }

    enum OpenOutcome: Equatable, Sendable {
        case app
        case appStore
        case failed
    }

    private enum CancelID {
        case load
        case open
    }

    @Dependency(\.moreAppsEnvironment) private var environment
    @Dependency(\.moreAppsOpen) private var openURL

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setApps(apps):
                state.isLoading = false
                state.activeLoadID = nil
                apply(apps, to: &state)
                return .merge(
                    .cancel(id: CancelID.load),
                    .cancel(id: CancelID.open)
                )

            case let .setMaximumNumberOfItems(maximumNumberOfItems):
                guard state.maximumNumberOfItems != maximumNumberOfItems else {
                    return .none
                }
                state.maximumNumberOfItems = maximumNumberOfItems
                apply(
                    state.sourceApps,
                    resettingImpressions: false,
                    to: &state
                )
                return .none

            case let .setAllowedCustomDeepLinkSchemes(schemes):
                state.allowedCustomDeepLinkSchemes = schemes
                return .none

            case let .load(provider):
                state.isLoading = true
                state.nextLoadID += 1
                let loadID = state.nextLoadID
                state.activeLoadID = loadID
                return .run { send in
                    do {
                        let apps = try await provider.fetchApps()
                        await send(.loadSucceeded(id: loadID, apps: apps))
                    } catch let error as CancellationError {
                        guard !Task.isCancelled else { return }
                        await send(
                            .loadFailed(
                                id: loadID,
                                message: error.localizedDescription
                            )
                        )
                    } catch {
                        await send(
                            .loadFailed(
                                id: loadID,
                                message: error.localizedDescription
                            )
                        )
                    }
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .loadSucceeded(id, apps):
                guard state.activeLoadID == id else { return .none }
                state.isLoading = false
                state.activeLoadID = nil
                apply(apps, to: &state)
                return .cancel(id: CancelID.open)

            case let .loadFailed(id, message):
                guard state.activeLoadID == id else { return .none }
                state.isLoading = false
                state.activeLoadID = nil
                enqueue(.loadingFailed(message: message), in: &state)
                return .none

            case let .itemBecameVisible(appID):
                guard state.apps.contains(where: { $0.id == appID }),
                      state.impressedAppIDs.insert(appID).inserted else {
                    return .none
                }
                enqueue(.impression(appID: appID), in: &state)
                return .none

            case let .selected(appID):
                guard !state.openingAppIDs.contains(appID),
                      let app = state.apps.first(where: { $0.id == appID }),
                      let destination = app.destination(for: environment.platform) else {
                    return .none
                }

                state.openingAppIDs.insert(appID)
                enqueue(.selected(appID: appID), in: &state)
                let dataSessionID = state.dataSessionID

                let deepLinkURL = MoreAppsURLPolicy.allowedDeepLink(
                    destination.deepLinkURL,
                    allowedCustomSchemes: state.allowedCustomDeepLinkSchemes
                )
                let appStoreURL = MoreAppsURLPolicy.allowedAppStoreURL(
                    destination.appStoreURL
                )

                guard deepLinkURL != nil || appStoreURL != nil else {
                    state.openingAppIDs.remove(appID)
                    enqueue(.failedToOpen(appID: appID), in: &state)
                    return .none
                }

                return .run { send in
                    guard !Task.isCancelled else { return }

                    if let deepLinkURL {
                        let didOpenDeepLink = await openURL(deepLinkURL)
                        guard !Task.isCancelled else { return }
                        if didOpenDeepLink {
                            await send(
                                .openFinished(
                                    dataSessionID: dataSessionID,
                                    appID: appID,
                                    outcome: .app
                                )
                            )
                            return
                        }
                    }

                    guard !Task.isCancelled else { return }
                    guard let appStoreURL else {
                        await send(
                            .openFinished(
                                dataSessionID: dataSessionID,
                                appID: appID,
                                outcome: .failed
                            )
                        )
                        return
                    }

                    let didOpenStore = await openURL(appStoreURL)
                    guard !Task.isCancelled else { return }
                    await send(
                        .openFinished(
                            dataSessionID: dataSessionID,
                            appID: appID,
                            outcome: didOpenStore ? .appStore : .failed
                        )
                    )
                }
                .cancellable(id: CancelID.open)

            case let .openFinished(dataSessionID, appID, outcome):
                guard state.dataSessionID == dataSessionID else {
                    return .none
                }
                state.openingAppIDs.remove(appID)
                switch outcome {
                case .app:
                    enqueue(.openedApp(appID: appID), in: &state)
                case .appStore:
                    enqueue(.openedAppStore(appID: appID), in: &state)
                case .failed:
                    enqueue(.failedToOpen(appID: appID), in: &state)
                }
                return .none

            case let .eventDelivered(id):
                state.pendingEvents.removeAll { $0.id == id }
                return .none
            }
        }
    }

    private func apply(
        _ apps: [MoreApp],
        resettingImpressions: Bool = true,
        to state: inout State
    ) {
        state.sourceApps = apps
        state.apps = MoreAppsFilter.filtered(
            apps,
            for: environment.platform,
            excluding: environment.bundleIdentifier,
            maximumNumberOfItems: state.maximumNumberOfItems
        )
        if resettingImpressions {
            state.dataSessionID += 1
            state.impressedAppIDs.removeAll()
            state.openingAppIDs.removeAll()
        }
    }

    private func enqueue(
        _ event: MoreAppsEvent,
        in state: inout State
    ) {
        state.nextEventID += 1
        state.pendingEvents.append(
            EventEnvelope(id: state.nextEventID, event: event)
        )
        if state.pendingEvents.count > Self.maximumPendingEventCount {
            state.pendingEvents.removeFirst(
                state.pendingEvents.count - Self.maximumPendingEventCount
            )
        }
    }
}
