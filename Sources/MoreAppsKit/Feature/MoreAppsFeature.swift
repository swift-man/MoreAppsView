//
//  MoreAppsFeature.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

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
    var selectionBehavior: MoreAppsSelectionBehavior
    var impressedAppIDs = Set<MoreApp.ID>()
    var openingAppIDs = Set<MoreApp.ID>()
    var presentingAppID: MoreApp.ID?
    var focusedAppID: MoreApp.ID?
    var focusedBackgroundImageURL: URL?
    var pendingEvents: [EventEnvelope] = []
    var dataSessionID = 0
    var nextEventID = 0
    var nextLoadID = 0
    var activeLoadID: Int?

    init(
      maximumNumberOfItems: Int?,
      allowedCustomDeepLinkSchemes: Set<String> = [],
      selectionBehavior: MoreAppsSelectionBehavior = .directOpen
    ) {
      self.maximumNumberOfItems = maximumNumberOfItems
      self.allowedCustomDeepLinkSchemes = allowedCustomDeepLinkSchemes
      self.selectionBehavior = selectionBehavior
    }
  }

  enum Action: Sendable {
    case setApps([MoreApp])
    case setMaximumNumberOfItems(Int?)
    case setAllowedCustomDeepLinkSchemes(Set<String>)
    case setSelectionBehavior(MoreAppsSelectionBehavior)
    case load(MoreAppsProviderClient)
    case loadSucceeded(id: Int, apps: [MoreApp])
    case loadFailed(id: Int, message: String)
    case itemBecameVisible(appID: MoreApp.ID)
    case focusChanged(appID: MoreApp.ID?)
    case selected(appID: MoreApp.ID)
    case deepLinkFailed(
      dataSessionID: Int,
      appID: MoreApp.ID,
      continuation: DeepLinkContinuation
    )
    case openFinished(
      dataSessionID: Int,
      appID: MoreApp.ID,
      outcome: OpenOutcome
    )
    case presentationFinished(
      dataSessionID: Int,
      appID: MoreApp.ID,
      outcome: MoreAppsPresentationOutcome
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

  enum DeepLinkContinuation: Equatable, Sendable {
    case appStore
    case presentation
  }

  private enum CancelID {
    case load
    case presentation
  }

  @Dependency(\.moreAppsEnvironment) private var environment
  @Dependency(\.moreAppsOpen) private var openURL
  @Dependency(\.moreAppsPresentation) private var present

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .setApps(let apps):
        state.isLoading = false
        state.activeLoadID = nil
        apply(apps, to: &state)
        return .merge(
          .cancel(id: CancelID.load),
          .cancel(id: CancelID.presentation)
        )

      case .setMaximumNumberOfItems(let maximumNumberOfItems):
        guard state.maximumNumberOfItems != maximumNumberOfItems else {
          return .none
        }
        let presentingAppID = state.presentingAppID
        state.maximumNumberOfItems = maximumNumberOfItems
        apply(
          state.sourceApps,
          resettingImpressions: false,
          to: &state
        )

        guard let presentingAppID,
          !state.apps.contains(where: { $0.id == presentingAppID })
        else {
          return .none
        }
        state.presentingAppID = nil
        return .cancel(id: CancelID.presentation)

      case .setAllowedCustomDeepLinkSchemes(let schemes):
        state.allowedCustomDeepLinkSchemes = schemes
        return .none

      case .setSelectionBehavior(let selectionBehavior):
        guard state.selectionBehavior != selectionBehavior else {
          return .none
        }
        state.selectionBehavior = selectionBehavior
        state.presentingAppID = nil
        return .cancel(id: CancelID.presentation)

      case .load(let provider):
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

      case .loadSucceeded(let id, let apps):
        guard state.activeLoadID == id else { return .none }
        state.isLoading = false
        state.activeLoadID = nil
        apply(apps, to: &state)
        return .cancel(id: CancelID.presentation)

      case .loadFailed(let id, let message):
        guard state.activeLoadID == id else { return .none }
        state.isLoading = false
        state.activeLoadID = nil
        enqueue(.loadingFailed(message: message), in: &state)
        return .none

      case .itemBecameVisible(let appID):
        guard state.apps.contains(where: { $0.id == appID }),
          state.impressedAppIDs.insert(appID).inserted
        else {
          return .none
        }
        enqueue(.impression(appID: appID), in: &state)
        return .none

      case .focusChanged(let appID):
        updateFocusedDestination(appID: appID, in: &state)
        return .none

      case .selected(let appID):
        guard state.openingAppIDs.isEmpty,
          state.presentingAppID == nil,
          let app = state.apps.first(where: { $0.id == appID }),
          let destination = app.destination(for: environment.platform)
        else {
          return .none
        }

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
          enqueue(.failedToOpen(appID: appID), in: &state)
          return .none
        }

        let platform = environment.platform
        guard
          state.selectionBehavior == .platformPresentation,
          platform == .iOS
        else {
          state.openingAppIDs.insert(appID)
          if let deepLinkURL {
            return deepLinkOpenEffect(
              dataSessionID: dataSessionID,
              appID: appID,
              deepLinkURL: deepLinkURL,
              continuation: .appStore
            )
          }
          return appStoreOpenEffect(
            dataSessionID: dataSessionID,
            appID: appID,
            appStoreURL: appStoreURL
          )
        }

        state.presentingAppID = appID
        let request = appStoreURL.map { appStoreURL in
          MoreAppsPresentationRequest(
            app: app,
            destination: MoreAppDestination(
              platform: destination.platform,
              appStoreURL: appStoreURL,
              deepLinkURL: deepLinkURL,
              backgroundImageURL: destination.backgroundImageURL
            ),
            appStoreIdentifier: MoreAppsURLPolicy.appStoreIdentifier(
              from: appStoreURL
            )
          )
        }

        if let deepLinkURL {
          state.openingAppIDs.insert(appID)
          return deepLinkOpenEffect(
            dataSessionID: dataSessionID,
            appID: appID,
            deepLinkURL: deepLinkURL,
            continuation: .presentation
          )
        }
        guard let request else {
          state.presentingAppID = nil
          enqueue(.failedToOpen(appID: appID), in: &state)
          return .none
        }
        return presentationEffect(
          dataSessionID: dataSessionID,
          appID: appID,
          request: request
        )

      case .deepLinkFailed(
        let dataSessionID,
        let appID,
        let continuation
      ):
        state.openingAppIDs.remove(appID)
        guard state.dataSessionID == dataSessionID else {
          return .none
        }

        guard let app = state.apps.first(where: { $0.id == appID }),
          let destination = app.destination(for: environment.platform),
          let appStoreURL = MoreAppsURLPolicy.allowedAppStoreURL(
            destination.appStoreURL
          )
        else {
          if state.presentingAppID == appID {
            state.presentingAppID = nil
          }
          enqueue(.failedToOpen(appID: appID), in: &state)
          return .none
        }

        switch continuation {
        case .appStore:
          state.openingAppIDs.insert(appID)
          return appStoreOpenEffect(
            dataSessionID: dataSessionID,
            appID: appID,
            appStoreURL: appStoreURL
          )

        case .presentation:
          guard state.presentingAppID == appID else { return .none }
          let request = MoreAppsPresentationRequest(
            app: app,
            destination: MoreAppDestination(
              platform: destination.platform,
              appStoreURL: appStoreURL,
              deepLinkURL: MoreAppsURLPolicy.allowedDeepLink(
                destination.deepLinkURL,
                allowedCustomSchemes: state.allowedCustomDeepLinkSchemes
              ),
              backgroundImageURL: destination.backgroundImageURL
            ),
            appStoreIdentifier: MoreAppsURLPolicy.appStoreIdentifier(
              from: appStoreURL
            )
          )
          return presentationEffect(
            dataSessionID: dataSessionID,
            appID: appID,
            request: request
          )
        }

      case .presentationFinished(
        let dataSessionID,
        let appID,
        let outcome
      ):
        guard state.dataSessionID == dataSessionID,
          state.presentingAppID == appID
        else {
          return .none
        }

        state.presentingAppID = nil
        switch outcome {
        case .dismissed:
          return .none

        case .failed:
          break

        case .appStoreRequested:
          break
        }

        guard let app = state.apps.first(where: { $0.id == appID }),
          let destination = app.destination(for: environment.platform),
          let appStoreURL = MoreAppsURLPolicy.allowedAppStoreURL(
            destination.appStoreURL
          )
        else {
          enqueue(.failedToOpen(appID: appID), in: &state)
          return .none
        }
        state.openingAppIDs.insert(appID)
        return appStoreOpenEffect(
          dataSessionID: dataSessionID,
          appID: appID,
          appStoreURL: appStoreURL
        )

      case .openFinished(let dataSessionID, let appID, let outcome):
        state.openingAppIDs.remove(appID)
        guard state.dataSessionID == dataSessionID else {
          return .none
        }
        if state.presentingAppID == appID {
          state.presentingAppID = nil
        }
        switch outcome {
        case .app:
          enqueue(.openedApp(appID: appID), in: &state)
        case .appStore:
          enqueue(.openedAppStore(appID: appID), in: &state)
        case .failed:
          enqueue(.failedToOpen(appID: appID), in: &state)
        }
        return .none

      case .eventDelivered(let id):
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
      state.presentingAppID = nil
    }
    updateFocusedDestination(appID: state.focusedAppID, in: &state)
  }

  private func updateFocusedDestination(
    appID: MoreApp.ID?,
    in state: inout State
  ) {
    guard
      let appID,
      let app = state.apps.first(where: { $0.id == appID })
    else {
      state.focusedAppID = nil
      state.focusedBackgroundImageURL = nil
      return
    }

    state.focusedAppID = appID
    state.focusedBackgroundImageURL =
      app
      .destination(for: environment.platform)?
      .backgroundImageURL
  }

  private func deepLinkOpenEffect(
    dataSessionID: Int,
    appID: MoreApp.ID,
    deepLinkURL: URL,
    continuation: DeepLinkContinuation
  ) -> Effect<Action> {
    .run { send in
      guard !Task.isCancelled else { return }
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

      await send(
        .deepLinkFailed(
          dataSessionID: dataSessionID,
          appID: appID,
          continuation: continuation
        )
      )
    }
  }

  private func appStoreOpenEffect(
    dataSessionID: Int,
    appID: MoreApp.ID,
    appStoreURL: URL?
  ) -> Effect<Action> {
    .run { send in
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
  }

  private func presentationEffect(
    dataSessionID: Int,
    appID: MoreApp.ID,
    request: MoreAppsPresentationRequest
  ) -> Effect<Action> {
    .run { send in
      let outcome = await present(request)
      guard !Task.isCancelled else { return }
      await send(
        .presentationFinished(
          dataSessionID: dataSessionID,
          appID: appID,
          outcome: outcome
        )
      )
    }
    .cancellable(id: CancelID.presentation, cancelInFlight: true)
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
