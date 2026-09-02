//
//  MoreAppsImageLoader.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Alamofire
import Foundation
import ImageIO
import UIKit

private let moreAppsDefaultMaximumDecodedPixelSize = 512
private let moreAppsImageCacheCostLimit = 32 * 1_024 * 1_024
private let moreAppsMaximumResponseByteCount = 8 * 1_024 * 1_024
private let moreAppsImageDecoder = MoreAppsImageDecoder()

func moreAppsClampedDecodedPixelSize(_ pixelSize: Int) -> Int {
  min(max(1, pixelSize), 4_096)
}

private actor MoreAppsImageDecoder {
  func image(from data: Data, maximumPixelSize: Int) -> UIImage? {
    guard !Task.isCancelled else { return nil }
    return MoreAppsImageLoader.downsampledImage(
      from: data,
      maximumPixelSize: maximumPixelSize
    )
  }
}

/// An error produced while downloading or decoding remote app artwork.
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
    case .insecureURL(let url):
      return "The image URL must use HTTPS: \(url.absoluteString)"
    case .network(let message):
      return "Image network error: \(message)"
    case .invalidMIMEType(let mimeType):
      return "Invalid image MIME type: \(mimeType ?? "missing")"
    case .decodingFailed:
      return "The downloaded bytes are not a valid image."
    }
  }
}

private actor MoreAppsImageRepository {
  private struct InFlightRequest {
    let id: UInt
    let generation: UInt
    let task: Task<Void, Never>
    var waiters: [UInt: CheckedContinuation<Data, any Error>]
  }

  private let session: Session
  private let maximumResponseByteCount: Int
  private let onWaiterAdded: @Sendable (URL, Int) -> Void
  private var inFlight: [URL: InFlightRequest] = [:]
  private var cacheGeneration: UInt = 0
  private var nextRequestID: UInt = 0
  private var nextWaiterID: UInt = 0

  init(
    sessionConfiguration: URLSessionConfiguration,
    maximumResponseByteCount: Int = moreAppsMaximumResponseByteCount,
    onWaiterAdded: @escaping @Sendable (URL, Int) -> Void = { _, _ in }
  ) {
    self.session = Session(configuration: sessionConfiguration)
    self.maximumResponseByteCount = maximumResponseByteCount
    self.onWaiterAdded = onWaiterAdded
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
    onWaiterAdded(url, request.waiters.count)
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
      )
    else {
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
      request.generation == cacheGeneration
    else {
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
    let request =
      session
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
    case .stream(let result):
      guard case .success(let chunk) = result else { return }
      append(chunk, cancellationToken: stream)

    case .complete(let completion):
      finish(with: completion)
    }
  }

  func responseDisposition(
    for response: HTTPURLResponse
  ) -> Request.ResponseDisposition {
    guard let responseURL = response.url,
      MoreAppsHTTPSPolicy.isSecure(responseURL)
    else {
      fail(
        with: MoreAppsImageLoadingError.network(
          message: "The response did not use HTTPS."
        )
      )
      return .cancel
    }

    let declaredByteCount = response.expectedContentLength
    guard
      declaredByteCount < 0
        || declaredByteCount <= maximumResponseByteCount
    else {
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
      (200..<300).contains(response.statusCode)
    else {
      let statusCode =
        completion.response
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

/// An Alamofire-backed, memory-caching app artwork loader.
///
/// Concurrent requests for the same URL and decoded size share one download,
/// decode, and cache publication task. Image decoding is performed away from
/// the main actor.
/// Cancelling one caller leaves shared work running for the remaining callers;
/// cancelling the last caller cancels the shared task and HTTP request.
@MainActor
public final class MoreAppsImageLoader {
  private struct ImageRequestKey: Hashable, Sendable {
    let url: URL
    let maximumPixelSize: Int

    var cacheKey: NSString {
      "\(url.absoluteString)#moreappskit-max=\(maximumPixelSize)" as NSString
    }
  }

  private struct InFlightImageRequest {
    let id: UInt
    let generation: UInt
    let task: Task<Void, Never>
    var waiters: [UInt: CheckedContinuation<UIImage, any Error>]
  }

  /// The shared image loader used by MoreAppsKit views.
  public static let shared = MoreAppsImageLoader()

  private let repository: MoreAppsImageRepository
  private let imageCache = NSCache<NSString, UIImage>()
  private let imageDecoder: @Sendable (Data, Int) async -> UIImage?
  private var inFlightImages: [ImageRequestKey: InFlightImageRequest] = [:]
  private var cacheGeneration: UInt = 0
  private var nextImageRequestID: UInt = 0
  private var nextImageWaiterID: UInt = 0

  /// Creates an image loader.
  ///
  /// - Parameter sessionConfiguration: The configuration for Alamofire's URL session.
  public convenience init(
    sessionConfiguration: URLSessionConfiguration = .default
  ) {
    self.init(
      repository: MoreAppsImageRepository(
        sessionConfiguration: sessionConfiguration
      ),
      imageDecoder: { data, maximumPixelSize in
        await moreAppsImageDecoder.image(
          from: data,
          maximumPixelSize: maximumPixelSize
        )
      }
    )
  }

  convenience init(
    sessionConfiguration: URLSessionConfiguration,
    maximumResponseByteCount: Int = moreAppsMaximumResponseByteCount,
    onDataWaiterAdded: @escaping @Sendable (URL, Int) -> Void = { _, _ in },
    sizedImageDecoder: @escaping @Sendable (Data, Int) async -> UIImage?
  ) {
    self.init(
      repository: MoreAppsImageRepository(
        sessionConfiguration: sessionConfiguration,
        maximumResponseByteCount: maximumResponseByteCount,
        onWaiterAdded: onDataWaiterAdded
      ),
      imageDecoder: sizedImageDecoder
    )
  }

  convenience init(
    sessionConfiguration: URLSessionConfiguration,
    maximumResponseByteCount: Int = moreAppsMaximumResponseByteCount,
    imageDecoder: @escaping @Sendable (Data) async -> UIImage?
  ) {
    self.init(
      repository: MoreAppsImageRepository(
        sessionConfiguration: sessionConfiguration,
        maximumResponseByteCount: maximumResponseByteCount
      ),
      imageDecoder: { data, _ in
        await imageDecoder(data)
      }
    )
  }

  private init(
    repository: MoreAppsImageRepository,
    imageDecoder: @escaping @Sendable (Data, Int) async -> UIImage?
  ) {
    self.repository = repository
    self.imageDecoder = imageDecoder
    self.imageCache.totalCostLimit = moreAppsImageCacheCostLimit
  }

  /// Returns a cached or downloaded image for a URL.
  ///
  /// - Parameter url: The remote icon URL.
  /// - Returns: A decoded UIKit image.
  /// - Throws: ``MoreAppsImageLoadingError`` or `CancellationError`.
  public func image(for url: URL) async throws -> UIImage {
    try await image(
      for: url,
      maximumPixelSize: moreAppsDefaultMaximumDecodedPixelSize
    )
  }

  /// Returns a cached or downloaded image downsampled for a target size.
  ///
  /// Requests for the same URL and target size share their download, decode,
  /// and cache entry. Overlapping downloads for different sizes share
  /// transport bytes but keep distinct decoded images so full-screen artwork
  /// does not reuse a card-sized icon.
  ///
  /// - Parameters:
  ///   - url: The remote image URL.
  ///   - maximumPixelSize: The requested maximum decoded width or height in
  ///     pixels. Values are clamped to `1...4096` to bound bitmap memory use.
  /// - Returns: A decoded UIKit image.
  /// - Throws: ``MoreAppsImageLoadingError`` or `CancellationError`.
  public func image(
    for url: URL,
    maximumPixelSize: Int
  ) async throws -> UIImage {
    let key = ImageRequestKey(
      url: url,
      maximumPixelSize: moreAppsClampedDecodedPixelSize(maximumPixelSize)
    )
    if let image = imageCache.object(forKey: key.cacheKey) {
      return image
    }

    let requestID: UInt
    if let request = inFlightImages[key] {
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
          guard
            let image = await imageDecoder(
              data,
              key.maximumPixelSize
            )
          else {
            throw MoreAppsImageLoadingError.decodingFailed
          }
          try Task.checkCancellation()
          result = .success(image)
        } catch {
          result = .failure(error)
        }
        self?.finishImageRequest(
          for: key,
          id: requestID,
          generation: generation,
          with: result
        )
      }
      inFlightImages[key] = InFlightImageRequest(
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
          for: key,
          requestID: requestID,
          waiterID: waiterID
        )
      }
      try Task.checkCancellation()
      return image
    } onCancel: { [weak self] in
      Task { @MainActor in
        self?.cancelImageWaiter(
          for: key,
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
    for key: ImageRequestKey,
    requestID: UInt,
    waiterID: UInt
  ) {
    guard var request = inFlightImages[key],
      request.id == requestID
    else {
      continuation.resume(throwing: CancellationError())
      return
    }
    request.waiters[waiterID] = continuation
    inFlightImages[key] = request
  }

  private func cancelImageWaiter(
    for key: ImageRequestKey,
    requestID: UInt,
    waiterID: UInt
  ) {
    guard var request = inFlightImages[key],
      request.id == requestID,
      let continuation = request.waiters.removeValue(
        forKey: waiterID
      )
    else {
      return
    }

    if request.waiters.isEmpty {
      inFlightImages[key] = nil
      request.task.cancel()
    } else {
      inFlightImages[key] = request
    }
    continuation.resume(throwing: CancellationError())
  }

  private func finishImageRequest(
    for key: ImageRequestKey,
    id: UInt,
    generation: UInt,
    with result: Result<UIImage, any Error>
  ) {
    guard let request = inFlightImages[key], request.id == id else { return }
    inFlightImages[key] = nil

    guard generation == cacheGeneration,
      request.generation == cacheGeneration
    else {
      request.waiters.values.forEach {
        $0.resume(throwing: CancellationError())
      }
      return
    }

    if case .success(let image) = result {
      let decodedCost = Self.decodedCost(of: image)
      if Self.isCacheable(decodedCost: decodedCost) {
        imageCache.setObject(
          image,
          forKey: key.cacheKey,
          cost: decodedCost
        )
      }
    }
    request.waiters.values.forEach { $0.resume(with: result) }
  }

  fileprivate nonisolated static func downsampledImage(
    from data: Data,
    maximumPixelSize: Int
  ) -> UIImage? {
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData,
        nil
      )
    else {
      return nil
    }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
      )
    else {
      return nil
    }

    return UIImage(cgImage: image, scale: 1, orientation: .up)
  }

  private nonisolated static func decodedCost(of image: UIImage) -> Int {
    guard let cgImage = image.cgImage else { return 0 }
    return decodedCost(
      bytesPerRow: cgImage.bytesPerRow,
      height: cgImage.height
    )
  }

  nonisolated static func decodedCost(
    bytesPerRow: Int,
    height: Int
  ) -> Int {
    let (cost, overflow) = bytesPerRow.multipliedReportingOverflow(by: height)
    return overflow ? .max : cost
  }

  nonisolated static func isCacheable(decodedCost: Int) -> Bool {
    decodedCost <= moreAppsImageCacheCostLimit
  }
}
