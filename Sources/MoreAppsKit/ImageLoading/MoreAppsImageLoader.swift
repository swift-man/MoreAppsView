import Alamofire
import Foundation
import UIKit

/// An error produced while downloading or decoding an app icon.
public enum MoreAppsImageLoadingError: Error, Equatable, LocalizedError, Sendable {
    /// The HTTP request failed.
    case network(message: String)

    /// The response did not advertise an image MIME type.
    case invalidMIMEType(String?)

    /// UIKit could not decode the returned bytes as an image.
    case decodingFailed

    /// A human-readable diagnostic description.
    public var errorDescription: String? {
        switch self {
        case let .network(message):
            return "Image network error: \(message)"
        case let .invalidMIMEType(mimeType):
            return "Invalid image MIME type: \(mimeType ?? "missing")"
        case .decodingFailed:
            return "The downloaded bytes are not a valid image."
        }
    }
}

private actor MoreAppsImageRepository {
    private let session: Session
    private let cache = NSCache<NSURL, NSData>()
    private var inFlight: [URL: Task<Data, Error>] = [:]

    init(sessionConfiguration: URLSessionConfiguration) {
        self.session = Session(configuration: sessionConfiguration)
    }

    func data(for url: URL) async throws -> Data {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached as Data
        }

        if let task = inFlight[url] {
            return try await task.value
        }

        let task = Task<Data, Error> { [session] in
            let response = await session
                .request(url)
                .validate(statusCode: 200..<300)
                .serializingData()
                .response

            if let error = response.error {
                throw MoreAppsImageLoadingError.network(
                    message: error.localizedDescription
                )
            }

            let mimeType = response.response?.mimeType
            guard mimeType?.lowercased().hasPrefix("image/") == true else {
                throw MoreAppsImageLoadingError.invalidMIMEType(mimeType)
            }

            guard let data = response.value else {
                throw MoreAppsImageLoadingError.network(
                    message: "The response did not contain a body."
                )
            }
            return data
        }

        inFlight[url] = task
        defer { inFlight[url] = nil }

        let data = try await task.value
        cache.setObject(data as NSData, forKey: url as NSURL)
        return data
    }

    func removeAllCachedImages() {
        cache.removeAllObjects()
    }
}

/// An Alamofire-backed, memory-caching app icon loader.
///
/// Concurrent requests for the same URL share one HTTP task. Image decoding is
/// performed away from the main actor.
@MainActor
public final class MoreAppsImageLoader {
    /// The shared image loader used by ``MoreAppsView``.
    public static let shared = MoreAppsImageLoader()

    private let repository: MoreAppsImageRepository
    private let imageCache = NSCache<NSURL, UIImage>()

    /// Creates an image loader.
    ///
    /// - Parameter sessionConfiguration: The configuration for Alamofire's URL session.
    public init(
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.repository = MoreAppsImageRepository(
            sessionConfiguration: sessionConfiguration
        )
    }

    /// Returns a cached or downloaded image for a URL.
    ///
    /// - Parameter url: The remote icon URL.
    /// - Returns: A decoded UIKit image.
    /// - Throws: ``MoreAppsImageLoadingError`` or `CancellationError`.
    public func image(for url: URL) async throws -> UIImage {
        if let image = imageCache.object(forKey: url as NSURL) {
            return image
        }

        let data = try await repository.data(for: url)
        try Task.checkCancellation()

        let image = await Task.detached(priority: .userInitiated) {
            UIImage(data: data, scale: 1)
        }.value

        try Task.checkCancellation()
        guard let image else {
            throw MoreAppsImageLoadingError.decodingFailed
        }

        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Removes all cached image data and decoded images.
    public func removeAllCachedImages() async {
        imageCache.removeAllObjects()
        await repository.removeAllCachedImages()
    }
}
