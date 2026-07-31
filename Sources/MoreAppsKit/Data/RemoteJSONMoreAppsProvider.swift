import Alamofire
import Foundation

private actor RemoteJSONMoreAppsRepository {
    private let url: URL
    private let session: Session
    private let decoder: JSONDecoder

    init(
        url: URL,
        session: Session,
        decoder: JSONDecoder
    ) {
        self.url = url
        self.session = session
        self.decoder = decoder
    }

    func fetchApps() async throws -> [MoreApp] {
        let response = await session
            .request(url)
            .validate(statusCode: 200..<300)
            .serializingData()
            .response

        if let error = response.error {
            throw RemoteJSONMoreAppsProviderError.network(
                message: error.localizedDescription
            )
        }

        guard let data = response.value else {
            throw RemoteJSONMoreAppsProviderError.network(
                message: "The response did not contain a body."
            )
        }

        do {
            return try decoder.decode([MoreApp].self, from: data)
        } catch {
            throw RemoteJSONMoreAppsProviderError.decoding(
                message: error.localizedDescription
            )
        }
    }
}

/// An error produced while loading a remote MoreAppsKit catalog.
public enum RemoteJSONMoreAppsProviderError: Error, Equatable, LocalizedError, Sendable {
    /// The HTTP request or response validation failed.
    case network(message: String)

    /// The response body could not be decoded as `[MoreApp]`.
    case decoding(message: String)

    /// A human-readable description suitable for diagnostics and events.
    public var errorDescription: String? {
        switch self {
        case let .network(message):
            return "Network error: \(message)"
        case let .decoding(message):
            return "Decoding error: \(message)"
        }
    }
}

/// A provider that downloads and decodes a JSON app catalog with Alamofire.
public struct RemoteJSONMoreAppsProvider: MoreAppsProviding, Sendable {
    /// The remote JSON endpoint.
    public let url: URL

    private let repository: RemoteJSONMoreAppsRepository

    /// Creates a remote JSON provider.
    ///
    /// - Parameters:
    ///   - url: The HTTPS endpoint containing a JSON array of ``MoreApp`` values.
    ///   - sessionConfiguration: The URL session configuration used by Alamofire.
    ///   - decoder: The decoder used for the response body.
    public init(
        url: URL,
        sessionConfiguration: URLSessionConfiguration = .default,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.url = url
        self.repository = RemoteJSONMoreAppsRepository(
            url: url,
            session: Session(configuration: sessionConfiguration),
            decoder: decoder
        )
    }

    init(
        url: URL,
        session: Session,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.url = url
        self.repository = RemoteJSONMoreAppsRepository(
            url: url,
            session: session,
            decoder: decoder
        )
    }

    /// Downloads and decodes the remote catalog.
    ///
    /// - Throws: ``RemoteJSONMoreAppsProviderError/network(message:)`` for request
    ///   failures and ``RemoteJSONMoreAppsProviderError/decoding(message:)`` for
    ///   malformed JSON.
    public func fetchApps() async throws -> [MoreApp] {
        try await repository.fetchApps()
    }
}
