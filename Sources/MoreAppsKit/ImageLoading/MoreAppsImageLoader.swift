import Alamofire
import Foundation
import ImageIO
import UIKit

private let moreAppsMaximumDecodedPixelSize = 512
private let moreAppsImageCacheCostLimit = 32 * 1_024 * 1_024

/// An error produced while downloading or decoding an app icon.
public enum MoreAppsImageLoadingError: Error, Equatable, LocalizedError, Sendable {
    /// The image URL does not use secure HTTPS transport.
    case insecureURL(URL)

    /// The HTTP request failed.
    case network(message: String)

    /// The response did not advertise an image MIME type.
    case invalidMIMEType(String?)

    /// UIKit could not decode the returned bytes as an image.
    case decodingFailed

    /// A human-readable diagnostic description.
    public var errorDescription: String? {
        switch self {
        case let .insecureURL(url):
            return "The image URL must use HTTPS: \(url.absoluteString)"
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
        let task: Task<Void, Never>
        var waiters: [UInt: CheckedContinuation<Data, any Error>]
    }

    private let session: Session
    private let maximumResponseByteCount: Int
    private var inFlight: [URL: InFlightRequest] = [:]
    private var cacheGeneration: UInt = 0
    private var nextRequestID: UInt = 0
    private var nextWaiterID: UInt = 0

    init(
        sessionConfiguration: URLSessionConfiguration,
        maximumResponseByteCount: Int = MoreAppsImageRepository
            .defaultMaximumResponseByteCount
    ) {
        self.session = Session(configuration: sessionConfiguration)
        self.maximumResponseByteCount = maximumResponseByteCount
    }

    func data(for url: URL) async throws -> Data {
        guard MoreAppsHTTPSPolicy.isSecure(url) else {
            throw MoreAppsImageLoadingError.insecureURL(url)
        }

        let requestID: UInt
        if let request = inFlight[url] {
            requestID = request.id
        } else {
            let generation = cacheGeneration
            nextRequestID &+= 1
            requestID = nextRequestID
            let task = Task { [session, maximumResponseByteCount] in
                let result: Result<Data, any Error>
                do {
                    let data = try await Self.downloadData(
                        from: url,
                        using: session,
                        maximumResponseByteCount: maximumResponseByteCount
                    )
                    result = .success(data)
                } catch {
                    result = .failure(error)
                }
                finishRequest(
                    for: url,
                    id: requestID,
                    generation: generation,
                    with: result
                )
            }
            inFlight[url] = InFlightRequest(
                id: requestID,
                generation: generation,
                task: task,
                waiters: [:]
            )
        }

        nextWaiterID &+= 1
        let waiterID = nextWaiterID
        return try await withTaskCancellationHandler {
            let data = try await withCheckedThrowingContinuation { continuation in
                addWaiter(
                    continuation,
                    for: url,
                    requestID: requestID,
                    waiterID: waiterID
                )
            }
            try Task.checkCancellation()
            return data
        } onCancel: {
            Task {
                await self.cancelWaiter(
                    for: url,
                    requestID: requestID,
                    waiterID: waiterID
                )
            }
        }
    }

    func removeAllCachedImages() {
        cacheGeneration &+= 1
        let requests = Array(inFlight.values)
        inFlight.removeAll()
        for request in requests {
            request.task.cancel()
            request.waiters.values.forEach {
                $0.resume(throwing: CancellationError())
            }
        }
    }

    private func addWaiter(
        _ continuation: CheckedContinuation<Data, any Error>,
        for url: URL,
        requestID: UInt,
        waiterID: UInt
    ) {
        guard var request = inFlight[url], request.id == requestID else {
            continuation.resume(throwing: CancellationError())
            return
        }
        request.waiters[waiterID] = continuation
        inFlight[url] = request
    }

    private func cancelWaiter(
        for url: URL,
        requestID: UInt,
        waiterID: UInt
    ) {
        guard var request = inFlight[url],
              request.id == requestID,
              let continuation = request.waiters.removeValue(
                  forKey: waiterID
              ) else {
            return
        }

        if request.waiters.isEmpty {
            inFlight[url] = nil
            request.task.cancel()
        } else {
            inFlight[url] = request
        }
        continuation.resume(throwing: CancellationError())
    }

    private func finishRequest(
        for url: URL,
        id: UInt,
        generation: UInt,
        with result: Result<Data, any Error>
    ) {
        guard let request = inFlight[url], request.id == id else { return }
        inFlight[url] = nil

        guard generation == cacheGeneration,
              request.generation == cacheGeneration else {
            request.waiters.values.forEach {
                $0.resume(throwing: CancellationError())
            }
            return
        }
        request.waiters.values.forEach { $0.resume(with: result) }
    }

    private nonisolated static func downloadData(
        from url: URL,
        using session: Session,
        maximumResponseByteCount: Int
    ) async throws -> Data {
        let request = session
            .streamRequest(url)
            .redirect(using: MoreAppsHTTPSPolicy.redirectHandler)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let receiver = MoreAppsImageStreamReceiver(
                    maximumResponseByteCount: maximumResponseByteCount,
                    continuation: continuation
                )
                request
                    .onHTTPResponse(on: receiver.queue) { response, completion in
                        completion(receiver.responseDisposition(for: response))
                    }
                    .responseStream(on: receiver.queue) { stream in
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

    func responseDisposition(
        for response: HTTPURLResponse
    ) -> Request.ResponseDisposition {
        guard let responseURL = response.url,
              MoreAppsHTTPSPolicy.isSecure(responseURL) else {
            fail(
                with: MoreAppsImageLoadingError.network(
                    message: "The response did not use HTTPS."
                )
            )
            return .cancel
        }

        let declaredByteCount = response.expectedContentLength
        guard declaredByteCount < 0
            || declaredByteCount <= maximumResponseByteCount else {
            fail(
                with: MoreAppsImageLoadingError.network(
                    message: "Image response exceeded the "
                        + "\(maximumResponseByteCount)-byte limit."
                )
            )
            return .cancel
        }

        return .allow
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
            if error.isExplicitlyCancelledError {
                continuation.resume(throwing: CancellationError())
                return
            }
            continuation.resume(
                throwing: MoreAppsImageLoadingError.network(
                    message: error.localizedDescription
                )
            )
            return
        }

        guard let response = completion.response,
              MoreAppsHTTPSPolicy.isSecure(response.url),
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

    private func fail(with error: Error) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: error)
    }
}

/// An Alamofire-backed, memory-caching app icon loader.
///
/// Concurrent requests for the same URL share one download, decode, and cache
/// publication task. Image decoding is performed away from the main actor.
/// Cancelling one caller leaves shared work running for the remaining callers;
/// cancelling the last caller cancels the shared task and HTTP request.
@MainActor
public final class MoreAppsImageLoader {
    private struct InFlightImageRequest {
        let id: UInt
        let generation: UInt
        let task: Task<Void, Never>
        var waiters: [UInt: CheckedContinuation<UIImage, any Error>]
    }

    /// The shared image loader used by ``MoreAppsView``.
    public static let shared = MoreAppsImageLoader()

    private let repository: MoreAppsImageRepository
    private let imageCache = NSCache<NSURL, UIImage>()
    private let imageDecoder: @Sendable (Data) async -> UIImage?
    private var inFlightImages: [URL: InFlightImageRequest] = [:]
    private var cacheGeneration: UInt = 0
    private var nextImageRequestID: UInt = 0
    private var nextImageWaiterID: UInt = 0

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
                Self.downsampledImage(from: data)
            }.value
        }
        self.imageCache.totalCostLimit = moreAppsImageCacheCostLimit
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
        self.imageCache.totalCostLimit = moreAppsImageCacheCostLimit
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

        let requestID: UInt
        if let request = inFlightImages[url] {
            requestID = request.id
        } else {
            let generation = cacheGeneration
            nextImageRequestID &+= 1
            requestID = nextImageRequestID
            let task = Task { [weak self, repository, imageDecoder] in
                let result: Result<UIImage, any Error>
                do {
                    let data = try await repository.data(for: url)
                    try Task.checkCancellation()
                    guard let image = await imageDecoder(data) else {
                        throw MoreAppsImageLoadingError.decodingFailed
                    }
                    try Task.checkCancellation()
                    result = .success(image)
                } catch {
                    result = .failure(error)
                }
                self?.finishImageRequest(
                    for: url,
                    id: requestID,
                    generation: generation,
                    with: result
                )
            }
            inFlightImages[url] = InFlightImageRequest(
                id: requestID,
                generation: generation,
                task: task,
                waiters: [:]
            )
        }

        nextImageWaiterID &+= 1
        let waiterID = nextImageWaiterID
        return try await withTaskCancellationHandler {
            let image = try await withCheckedThrowingContinuation {
                continuation in
                addImageWaiter(
                    continuation,
                    for: url,
                    requestID: requestID,
                    waiterID: waiterID
                )
            }
            try Task.checkCancellation()
            return image
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelImageWaiter(
                    for: url,
                    requestID: requestID,
                    waiterID: waiterID
                )
            }
        }
    }

    /// Removes all cached images and invalidates in-progress image work.
    public func removeAllCachedImages() async {
        cacheGeneration &+= 1
        imageCache.removeAllObjects()
        let requests = Array(inFlightImages.values)
        inFlightImages.removeAll()
        for request in requests {
            request.task.cancel()
            request.waiters.values.forEach {
                $0.resume(throwing: CancellationError())
            }
        }
        await repository.removeAllCachedImages()
    }

    private func addImageWaiter(
        _ continuation: CheckedContinuation<UIImage, any Error>,
        for url: URL,
        requestID: UInt,
        waiterID: UInt
    ) {
        guard var request = inFlightImages[url],
              request.id == requestID else {
            continuation.resume(throwing: CancellationError())
            return
        }
        request.waiters[waiterID] = continuation
        inFlightImages[url] = request
    }

    private func cancelImageWaiter(
        for url: URL,
        requestID: UInt,
        waiterID: UInt
    ) {
        guard var request = inFlightImages[url],
              request.id == requestID,
              let continuation = request.waiters.removeValue(
                  forKey: waiterID
              ) else {
            return
        }

        if request.waiters.isEmpty {
            inFlightImages[url] = nil
            request.task.cancel()
        } else {
            inFlightImages[url] = request
        }
        continuation.resume(throwing: CancellationError())
    }

    private func finishImageRequest(
        for url: URL,
        id: UInt,
        generation: UInt,
        with result: Result<UIImage, any Error>
    ) {
        guard let request = inFlightImages[url], request.id == id else { return }
        inFlightImages[url] = nil

        guard generation == cacheGeneration,
              request.generation == cacheGeneration else {
            request.waiters.values.forEach {
                $0.resume(throwing: CancellationError())
            }
            return
        }

        if case let .success(image) = result {
            imageCache.setObject(
                image,
                forKey: url as NSURL,
                cost: Self.decodedCost(of: image)
            )
        }
        request.waiters.values.forEach { $0.resume(with: result) }
    }

    private nonisolated static func downsampledImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: moreAppsMaximumDecodedPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    private nonisolated static func decodedCost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let (cost, overflow) = cgImage.bytesPerRow.multipliedReportingOverflow(
            by: cgImage.height
        )
        return overflow
            ? moreAppsImageCacheCostLimit
            : min(cost, moreAppsImageCacheCostLimit)
    }
}
