//
//  RemoteJSONMoreAppsProviderTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation
import Testing

@testable import MoreAppsKit

@Suite(.serialized)
struct RemoteJSONMoreAppsProviderTests {
  @Test
  func testRemoteJSONDecodesCatalog() async throws {
    defer { RemoteJSONMockURLProtocol.handler = nil }
    RemoteJSONMockURLProtocol.handler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Self.validJSON)
    }

    let apps = try await makeProvider().fetchApps()

    #expect(apps.count == 1)
    #expect(apps.first?.id == "reaction-speed")
    #expect(apps.first?.destinations.first?.platform == .iOS)
  }

  @Test
  func testInvalidPlatformStringProducesDecodingError() async throws {
    defer { RemoteJSONMockURLProtocol.handler = nil }
    let invalidJSON = Data(
      String(decoding: Self.validJSON, as: UTF8.self)
        .replacingOccurrences(
          of: "\"iOS\"",
          with: "\"android\""
        )
        .utf8
    )
    RemoteJSONMockURLProtocol.handler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, invalidJSON)
    }

    do {
      _ = try await makeProvider().fetchApps()
      Issue.record("Expected a decoding error")
    } catch let error as RemoteJSONMoreAppsProviderError {
      guard case .decoding = error else {
        Issue.record("Expected decoding error, got \(error)")
        return
      }
    }
  }

  @Test
  func testHTTPFailureProducesNetworkError() async throws {
    defer { RemoteJSONMockURLProtocol.handler = nil }
    RemoteJSONMockURLProtocol.handler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      let response = HTTPURLResponse(
        url: url,
        statusCode: 503,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, Data())
    }

    do {
      _ = try await makeProvider().fetchApps()
      Issue.record("Expected a network error")
    } catch let error as RemoteJSONMoreAppsProviderError {
      guard case .network = error else {
        Issue.record("Expected network error, got \(error)")
        return
      }
    }
  }

  @Test
  func testInsecureCatalogURLIsRejectedBeforeRequestStarts() async {
    defer { RemoteJSONMockURLProtocol.handler = nil }
    var requestCount = 0
    RemoteJSONMockURLProtocol.handler = { request in
      requestCount += 1
      guard let url = request.url else { throw URLError(.badURL) }
      return (
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!,
        Self.validJSON
      )
    }

    do {
      _ = try await makeProvider(
        url: URL(string: "http://example.com/apps.json")!
      ).fetchApps()
      Issue.record("Expected an insecure URL error")
    } catch let error as RemoteJSONMoreAppsProviderError {
      #expect(
        error
          == .insecureURL(
            URL(string: "http://example.com/apps.json")!
          )
      )
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(requestCount == 0)
  }

  @Test
  func testDeclaredResponseLengthOverLimitIsRejected() async {
    defer { RemoteJSONMockURLProtocol.handler = nil }
    let maximumByteCount = Self.validJSON.count
    RemoteJSONMockURLProtocol.handler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      return (
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: [
            "Content-Type": "application/json",
            "Content-Length": String(maximumByteCount + 1),
          ]
        )!,
        Data()
      )
    }

    await expectResponseTooLarge(
      from: makeProvider(maximumResponseByteCount: maximumByteCount),
      maximumByteCount: maximumByteCount
    )
  }

  @Test
  func testActualResponseLengthOverLimitIsRejected() async {
    defer { RemoteJSONMockURLProtocol.handler = nil }
    let maximumByteCount = Self.validJSON.count - 1
    RemoteJSONMockURLProtocol.handler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      return (
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!,
        Self.validJSON
      )
    }

    await expectResponseTooLarge(
      from: makeProvider(maximumResponseByteCount: maximumByteCount),
      maximumByteCount: maximumByteCount
    )
  }

  @Test
  func testResponseExactlyAtLimitIsAccepted() async throws {
    defer { RemoteJSONMockURLProtocol.handler = nil }
    RemoteJSONMockURLProtocol.handler = { request in
      guard let url = request.url else { throw URLError(.badURL) }
      return (
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )!,
        Self.validJSON
      )
    }

    let apps = try await makeProvider(
      maximumResponseByteCount: Self.validJSON.count
    ).fetchApps()

    #expect(apps.count == 1)
  }

  @Test
  func testHTTPSRedirectPolicyRejectsDowngrade() {
    let secureURL = URL(string: "https://example.com/apps.json")!
    let insecureURL = URL(string: "http://example.com/apps.json")!

    #expect(MoreAppsHTTPSPolicy.isSecure(secureURL))
    #expect(!MoreAppsHTTPSPolicy.isSecure(insecureURL))
  }

  private func makeProvider(
    url: URL = URL(string: "https://example.com/apps.json")!,
    maximumResponseByteCount: Int? = nil
  ) -> RemoteJSONMoreAppsProvider {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RemoteJSONMockURLProtocol.self]
    if let maximumResponseByteCount {
      return RemoteJSONMoreAppsProvider(
        url: url,
        sessionConfiguration: configuration,
        maximumResponseByteCount: maximumResponseByteCount
      )
    }
    return RemoteJSONMoreAppsProvider(
      url: url,
      sessionConfiguration: configuration
    )
  }

  private func expectResponseTooLarge(
    from provider: RemoteJSONMoreAppsProvider,
    maximumByteCount: Int
  ) async {
    do {
      _ = try await provider.fetchApps()
      Issue.record("Expected a response-too-large error")
    } catch let error as RemoteJSONMoreAppsProviderError {
      #expect(
        error
          == .responseTooLarge(
            maximumByteCount: maximumByteCount
          )
      )
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private static let validJSON = Data(
    """
    [
      {
        "id": "reaction-speed",
        "bundleIdentifier": "com.example.reactionspeed",
        "name": "Reaction Speed Test",
        "subtitle": "Test your reflexes",
        "iconURL": "https://example.com/icon.png",
        "sortOrder": 10,
        "destinations": [
          {
            "platform": "iOS",
            "appStoreURL": "https://apps.apple.com/app/id1234567890",
            "deepLinkURL": "reactionspeed://home"
          }
        ]
      }
    ]
    """.utf8
  )
}
