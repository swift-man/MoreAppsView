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
    private static let defaultMaximumResponseByteCount = 8 * 1_024 * 1_024

    private struct InFlightRequest {
        let id: UInt
        let generation: UInt
        let task: Task<Data, Error>
    }

    private let session: Session
    private let maximumResponseByteCount: Int
    private var inFlight: [URL: InFlightRequest] = [:]
    private var cacheGeneration: UInt = 0
    private var nextRequestID: UInt = 0

    init(
        sessionConfiguration: URLSessionConfiguration,
        maximumResponseByteCount: Int = MoreAppsImageRepository
            .defaultMaximumResponseByteCount
    ) {
        self.session = Session(configuration: sessionConfiguration)
        self.maximumResponseByteCount = maximumResponseByteCount
    }

    func data(for url: URL) async throws -> Data {
        if let request = inFlight[url] {
            return try await value(for: request)
        }

        let generation = cacheGeneration
        nextRequestID &+= 1
        let requestID = nextRequestID
        let task = Task<Data, Error> {
            try await Self.downloadData(
                from: url,
                using: session,
                maximumResponseByteCount: maximumResponseByteCount
            )
        }

        let request = InFlightRequest(
            id: requestID,
            generation: generation,
            task: task
        )
        inFlight[url] = request

        do {
            let data = try await value(for: request)
            removeInFlightRequest(for: url, id: requestID)
            return data
        } catch {
            removeInFlightRequest(for: url, id: requestID)
            throw error
        }
    }

    func removeAllCachedImages() {
        cacheGeneration &+= 1
        let tasks = inFlight.values.map(\.task)
        inFlight.removeAll()
        tasks.forEach { $0.cancel() }
    }

    private func value(for request: InFlightRequest) async throws -> Data {
        do {
            let data = try await request.task.value
            guard request.generation == cacheGeneration else {
                throw CancellationError()
            }
            return data
        } catch {
            guard request.generation == cacheGeneration else {
                throw CancellationError()
            }
            throw error
        }
    }

    private func removeInFlightRequest(for url: URL, id: UInt) {
        guard inFlight[url]?.id == id else { return }
        inFlight[url] = nil
    }

    private nonisolated static func downloadData(
        from url: URL,
        using session: Session,
        maximumResponseByteCount: Int
    ) async throws -> Data {
        let request = session.streamRequest(url)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let receiver = MoreAppsImageStreamReceiver(
                    maximumResponseByteCount: maximumResponseByteCount,
                    continuation: continuation
                )
                request.responseStream(
                    on: receiver.queue
                ) { stream in
                    receiver.receive(stream)
                }
            }
        } onCancel: {
            request.cancel()
        }
    }
}

private final class MoreAppsImageStreamReceiver: @unchecked Sendable {
    let queue = DispatchQueue(
        label: "com.moreappskit.image-stream-receiver"
    )

    private let maximumResponseByteCount: Int
    private let lock = NSLock()
    private var data = Data()
    private var continuation: CheckedContinuation<Data, Error>?

    init(
        maximumResponseByteCount: Int,
        continuation: CheckedContinuation<Data, Error>
    ) {
        self.maximumResponseByteCount = maximumResponseByteCount
        self.continuation = continuation
    }

    func receive(_ stream: DataStreamRequest.Stream<Data, Never>) {
        switch stream.event {
        case let .stream(result):
            guard case let .success(chunk) = result else { return }
            append(chunk, cancellationToken: stream)

        case let .complete(completion):
            finish(with: completion)
        }
    }

    private func append(
        _ chunk: Data,
        cancellationToken stream: DataStreamRequest.Stream<Data, Never>
    ) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        guard chunk.count <= maximumResponseByteCount - data.count else {
            self.continuation = nil
            lock.unlock()
            stream.cancel()
            continuation.resume(
                throwing: MoreAppsImageLoadingError.network(
                    message: "Image response exceeded the "
                        + "\(maximumResponseByteCount)-byte limit."
                )
            )
            return
        }
        data.append(chunk)
        lock.unlock()
    }

    private func finish(
        with completion: DataStreamRequest.Completion
    ) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let data = data
        lock.unlock()

        if let error = completion.error {
            continuation.resume(
                throwing: MoreAppsImageLoadingError.network(
                    message: error.localizedDescription
                )
            )
            return
        }

        guard let response = completion.response,
              (200..<300).contains(response.statusCode) else {
            let statusCode = completion.response
                .map { String($0.statusCode) } ?? "missing"
            continuation.resume(
                throwing: MoreAppsImageLoadingError.network(
                    message: "Unexpected HTTP status: \(statusCode)."
                )
            )
            return
        }

        let mimeType = response.mimeType
        guard mimeType?.lowercased().hasPrefix("image/") == true else {
            continuation.resume(
                throwing: MoreAppsImageLoadingError.invalidMIMEType(mimeType)
            )
            return
        }

        guard !data.isEmpty else {
            continuation.resume(
                throwing: MoreAppsImageLoadingError.network(
                    message: "The response did not contain a body."
                )
            )
            return
        }

        continuation.resume(returning: data)
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
    private let imageDecoder: @Sendable (Data) async -> UIImage?
    private var cacheGeneration: UInt = 0

    /// Creates an image loader.
    ///
    /// - Parameter sessionConfiguration: The configuration for Alamofire's URL session.
    public init(
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.repository = MoreAppsImageRepository(
            sessionConfiguration: sessionConfiguration
        )
        self.imageDecoder = { data in
            await Task.detached(priority: .userInitiated) {
                UIImage(data: data, scale: 1)
            }.value
        }
    }

    init(
        sessionConfiguration: URLSessionConfiguration,
        maximumResponseByteCount: Int = 8 * 1_024 * 1_024,
        imageDecoder: @escaping @Sendable (Data) async -> UIImage?
    ) {
        self.repository = MoreAppsImageRepository(
            sessionConfiguration: sessionConfiguration,
            maximumResponseByteCount: maximumResponseByteCount
        )
        self.imageDecoder = imageDecoder
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

        let generation = cacheGeneration
        let data = try await repository.data(for: url)
        try Task.checkCancellation()
        guard generation == cacheGeneration else {
            throw CancellationError()
        }

        let image = await imageDecoder(data)

        try Task.checkCancellation()
        guard generation == cacheGeneration else {
            throw CancellationError()
        }
        guard let image else {
            throw MoreAppsImageLoadingError.decodingFailed
        }

        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Removes all cached images and invalidates in-progress image work.
    public func removeAllCachedImages() async {
        cacheGeneration &+= 1
        imageCache.removeAllObjects()
        await repository.removeAllCachedImages()
    }
}
