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

    private func makeProvider() -> RemoteJSONMoreAppsProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteJSONMockURLProtocol.self]
        return RemoteJSONMoreAppsProvider(
            url: URL(string: "https://example.com/apps.json")!,
            sessionConfiguration: configuration
        )
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
