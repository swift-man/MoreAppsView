//
//  MoreAppsImageLoaderTests.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Foundation
import MoreAppsNetworking
import Testing
import UIKit

@testable import MoreAppsKit
@testable import MoreAppsNetworking
@testable import MoreAppsKitCore

@MainActor
@Suite(.serialized)
struct MoreAppsImageLoaderTests {
  @Test
  func testValidImageIsCoalescedCachedAndCanBePurged() async throws {
    defer { ImageMockURLProtocol.handler = nil }
    let requestCounter = LockedCounter()
    let decodeCounter = LockedCounter()
    ImageMockURLProtocol.handler = { request in
      requestCounter.increment()
      Thread.sleep(forTimeInterval: 0.05)
      return (
        Self.response(
          for: request,
          contentType: "image/png"
        ),
        Self.onePixelPNG
      )
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageMockURLProtocol.self]
    let loader = MoreAppsImageLoader(
      sessionConfiguration: configuration,
      imageDecoder: { data in
        decodeCounter.increment()
        return UIImage(data: data, scale: 1)
      }
    )
    async let first = loader.image(for: Self.imageURL)
    async let second = loader.image(for: Self.imageURL)
    let images = try await (first, second)

    #expect(images.0.size.width > 0)
    #expect(images.1.size.height > 0)
    #expect(requestCounter.count == 1)
    #expect(decodeCounter.count == 1)

    _ = try await loader.image(for: Self.imageURL)
    #expect(requestCounter.count == 1)
    #expect(decodeCounter.count == 1)

    await loader.removeAllCachedImages()
    _ = try await loader.image(for: Self.imageURL)
    #expect(requestCounter.count == 2)
    #expect(decodeCounter.count == 2)
  }

  @Test
  func testRequestJoiningDuringDecodeSharesTheEntireLoad() async throws {
    defer { ImageMockURLProtocol.handler = nil }
    let requestCounter = LockedCounter()
    let decodeCounter = LockedCounter()
    ImageMockURLProtocol.handler = { request in
      requestCounter.increment()
      return (
        Self.response(for: request, contentType: "image/png"),
        Self.onePixelPNG
      )
    }

    let gate = ImageDecodeGate()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageMockURLProtocol.self]
    let loader = MoreAppsImageLoader(
      sessionConfiguration: configuration,
      imageDecoder: { data in
        decodeCounter.increment()
        return await gate.decode(data)
      }
    )

    let first = Task {
      try await loader.image(for: Self.imageURL)
    }
    await gate.waitUntilStarted()
    let secondStarted = MainActorSignal()
    let second = Task {
      secondStarted.signal()
      return try await loader.image(for: Self.imageURL)
    }

    await secondStarted.wait()
    // The second task keeps the main actor until the loader registers its waiter.
    #expect(requestCounter.count == 1)
    #expect(decodeCounter.count == 1)

    await gate.release()
    let images = try await (first.value, second.value)
    #expect(images.0.size.width > 0)
    #expect(images.1.size.height > 0)
    #expect(requestCounter.count == 1)
    #expect(decodeCounter.count == 1)
  }

  @Test
  func testInvalidMIMETypeIsRejected() async {
    defer { ImageMockURLProtocol.handler = nil }
    ImageMockURLProtocol.handler = { request in
      (
        Self.response(
          for: request,
          contentType: "text/plain"
        ),
        Data("not an image".utf8)
      )
    }

    do {
      _ = try await makeLoader().image(for: Self.imageURL)
      Issue.record("Expected an invalid MIME type error")
    } catch let error as MoreAppsImageLoadingError {
      #expect(error == .invalidMIMEType("text/plain"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func testCorruptImageBytesProduceDecodingError() async {
    defer { ImageMockURLProtocol.handler = nil }
    ImageMockURLProtocol.handler = { request in
      (
        Self.response(
          for: request,
          contentType: "image/png"
        ),
        Data("not a png".utf8)
      )
    }

    do {
      _ = try await makeLoader().image(for: Self.imageURL)
      Issue.record("Expected an image decoding error")
    } catch let error as MoreAppsImageLoadingError {
      #expect(error == .decodingFailed)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func testCorruptImageBytesDoNotPoisonARetry() async throws {
    defer { ImageMockURLProtocol.handler = nil }
    let counter = LockedCounter()
    ImageMockURLProtocol.handler = { request in
      let attempt = counter.increment()
      return (
        Self.response(for: request, contentType: "image/png"),
        attempt == 1 ? Data("not a png".utf8) : Self.onePixelPNG
      )
    }

    let loader = makeLoader()
    do {
      _ = try await loader.image(for: Self.imageURL)
      Issue.record("Expected an image decoding error")
    } catch let error as MoreAppsImageLoadingError {
      #expect(error == .decodingFailed)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    let image = try await loader.image(for: Self.imageURL)
    #expect(image.size.width > 0)
    #expect(counter.count == 2)
  }

  @Test
  func testHTTPFailureProducesNetworkError() async {
    defer { ImageMockURLProtocol.handler = nil }
    ImageMockURLProtocol.handler = { request in
      (
        Self.response(
          for: request,
          statusCode: 503,
          contentType: "image/png"
        ),
        Data()
      )
    }

    do {
      _ = try await makeLoader().image(for: Self.imageURL)
      Issue.record("Expected an image network error")
    } catch let error as MoreAppsImageLoadingError {
      guard case .network = error else {
        Issue.record("Expected network error, got \(error)")
        return
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func testOversizedImageResponseIsRejected() async {
    defer { ImageMockURLProtocol.handler = nil }
    ImageMockURLProtocol.handler = { request in
      (
        Self.response(for: request, contentType: "image/png"),
        Data(repeating: 0, count: 33)
      )
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageMockURLProtocol.self]
    let loader = MoreAppsImageLoader(
      sessionConfiguration: configuration,
      maximumResponseByteCount: 32,
      imageDecoder: { UIImage(data: $0, scale: 1) }
    )

    do {
      _ = try await loader.image(for: Self.imageURL)
      Issue.record("Expected an oversized image response error")
    } catch let error as MoreAppsImageLoadingError {
      guard case .network(let message) = error else {
        Issue.record("Expected network error, got \(error)")
        return
      }
      #expect(message.contains("32-byte limit"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func testInsecureImageURLIsRejectedBeforeRequestStarts() async {
    defer { ImageMockURLProtocol.handler = nil }
    let counter = LockedCounter()
    ImageMockURLProtocol.handler = { request in
      counter.increment()
      return (
        Self.response(for: request, contentType: "image/png"),
        Self.onePixelPNG
      )
    }
    let insecureURL = URL(string: "http://example.com/icon.png")!

    do {
      _ = try await makeLoader().image(for: insecureURL)
      Issue.record("Expected an insecure URL error")
    } catch let error as MoreAppsImageLoadingError {
      #expect(error == .insecureURL(insecureURL))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(counter.count == 0)
  }

  @Test
  func testLargePixelImageIsDownsampledBeforeCaching() async throws {
    defer { ImageMockURLProtocol.handler = nil }
    let renderer = UIGraphicsImageRenderer(
      size: CGSize(width: 1_024, height: 1_024)
    )
    let imageData = renderer.pngData { context in
      UIColor.systemBlue.setFill()
      context.fill(
        CGRect(x: 0, y: 0, width: 1_024, height: 1_024)
      )
    }
    ImageMockURLProtocol.handler = { request in
      (
        Self.response(for: request, contentType: "image/png"),
        imageData
      )
    }

    let image = try await makeLoader().image(for: Self.imageURL)

    #expect((image.cgImage?.width ?? .max) <= 512)
    #expect((image.cgImage?.height ?? .max) <= 512)
  }

  @Test
  func testRequestedPixelSizesUseDistinctDecodedCacheEntries() async throws {
    let responseGate = ImageResponseGate()
    defer {
      responseGate.release()
      ImageMockURLProtocol.handler = nil
    }
    let requestCounter = LockedCounter()
    let decodedSizes = LockedValues<Int>()
    let waiterCounts = LockedValues<Int>()
    let twoWaiters = AsyncTestSignal()
    ImageMockURLProtocol.handler = { request in
      requestCounter.increment()
      responseGate.wait()
      return (
        Self.response(for: request, contentType: "image/png"),
        Self.onePixelPNG
      )
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageMockURLProtocol.self]
    let loader = MoreAppsImageLoader(
      sessionConfiguration: configuration,
      onDataWaiterAdded: { _, waiterCount in
        waiterCounts.append(waiterCount)
        if waiterCount == 2 {
          twoWaiters.signal()
        }
      },
      sizedImageDecoder: { data, maximumPixelSize in
        decodedSizes.append(maximumPixelSize)
        return UIImage(data: data, scale: 1)
      }
    )

    let cardImage = Task {
      try await loader.image(
        for: Self.imageURL,
        maximumPixelSize: 512
      )
    }
    await waitUntilIncremented(requestCounter)
    let backgroundImage = Task {
      try await loader.image(
        for: Self.imageURL,
        maximumPixelSize: 1_920
      )
    }
    await twoWaiters.wait()
    #expect(waiterCounts.values.contains(2))
    responseGate.release()
    _ = try await (cardImage.value, backgroundImage.value)

    #expect(requestCounter.count == 1)
    #expect(Set(decodedSizes.values) == [512, 1_920])

    _ = try await loader.image(
      for: Self.imageURL,
      maximumPixelSize: 512
    )
    _ = try await loader.image(
      for: Self.imageURL,
      maximumPixelSize: 1_920
    )
    #expect(requestCounter.count == 1)
    #expect(decodedSizes.values.count == 2)
  }

  @Test
  func testNonpositiveRequestedPixelSizeIsClampedToOne() async throws {
    defer { ImageMockURLProtocol.handler = nil }
    let decodedSizes = LockedValues<Int>()
    ImageMockURLProtocol.handler = { request in
      (
        Self.response(for: request, contentType: "image/png"),
        Self.onePixelPNG
      )
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageMockURLProtocol.self]
    let loader = MoreAppsImageLoader(
      sessionConfiguration: configuration,
      sizedImageDecoder: { data, maximumPixelSize in
        decodedSizes.append(maximumPixelSize)
        return UIImage(data: data, scale: 1)
      }
    )

    _ = try await loader.image(
      for: Self.imageURL,
      maximumPixelSize: 0
    )

    #expect(decodedSizes.values == [1])
  }

  @Test
  func testOversizedRequestedPixelSizeIsClampedToFourK() async throws {
    defer { ImageMockURLProtocol.handler = nil }
    let decodedSizes = LockedValues<Int>()
    ImageMockURLProtocol.handler = { request in
      (
        Self.response(for: request, contentType: "image/png"),
        Self.onePixelPNG
      )
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageMockURLProtocol.self]
    let loader = MoreAppsImageLoader(
      sessionConfiguration: configuration,
      sizedImageDecoder: { data, maximumPixelSize in
        decodedSizes.append(maximumPixelSize)
        return UIImage(data: data, scale: 1)
      }
    )

    _ = try await loader.image(
      for: Self.imageURL,
      maximumPixelSize: .max
    )

    #expect(decodedSizes.values == [4_096])
  }

  @Test
  func testOversizedDecodedBitmapIsNotCacheable() {
    let fourKSquareCost = MoreAppsImageLoader.decodedCost(
      bytesPerRow: 4_096 * 4,
      height: 4_096
    )

    #expect(fourKSquareCost == 64 * 1_024 * 1_024)
    #expect(!MoreAppsImageLoader.isCacheable(decodedCost: fourKSquareCost))
    #expect(
      MoreAppsImageLoader.isCacheable(
        decodedCost: 32 * 1_024 * 1_024
      )
    )
    #expect(
      MoreAppsImageLoader.decodedCost(
        bytesPerRow: .max,
        height: 2
      ) == .max
    )
  }

  @Test
  func testOversizedDecodedBitmapBypassesTheImageCache() async throws {
    defer { ImageMockURLProtocol.handler = nil }
    let requestCounter = LockedCounter()
    let decodeCounter = LockedCounter()
    ImageMockURLProtocol.handler = { request in
      requestCounter.increment()
      return (
        Self.response(for: request, contentType: "image/png"),
        Self.onePixelPNG
      )
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = try #require(
      CGContext(
        data: nil,
        width: 2_900,
        height: 2_900,
        bitsPerComponent: 8,
        bytesPerRow: 2_900 * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    let oversizedCGImage = try #require(context.makeImage())
    let oversizedImage = UIImage(cgImage: oversizedCGImage)
    #expect(
      MoreAppsImageLoader.decodedCost(
        bytesPerRow: oversizedCGImage.bytesPerRow,
        height: oversizedCGImage.height
      ) > 32 * 1_024 * 1_024
    )

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageMockURLProtocol.self]
    let loader = MoreAppsImageLoader(
      sessionConfiguration: configuration,
      sizedImageDecoder: { _, _ in
        decodeCounter.increment()
        return oversizedImage
      }
    )

    _ = try await loader.image(for: Self.imageURL)
    _ = try await loader.image(for: Self.imageURL)

    #expect(requestCounter.count == 2)
    #expect(decodeCounter.count == 2)
  }

  @Test
  func testCancellingOnePixelSizeKeepsSharedTransportForAnother() async throws {
    let responseGate = ImageResponseGate()
    defer {
      responseGate.release()
      ImageMockURLProtocol.handler = nil
      ImageMockURLProtocol.onStopLoading = nil
    }
    let requestCounter = LockedCounter()
    let stopCounter = LockedCounter()
    let waiterCounts = LockedValues<Int>()
    let twoWaiters = AsyncTestSignal()
    ImageMockURLProtocol.handler = { request in
      requestCounter.increment()
      responseGate.wait()
      return (
        Self.response(for: request, contentType: "image/png"),
        Self.onePixelPNG
      )
    }
    ImageMockURLProtocol.onStopLoading = { stopCounter.increment() }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageMockURLProtocol.self]
    let loader = MoreAppsImageLoader(
      sessionConfiguration: configuration,
      onDataWaiterAdded: { _, waiterCount in
        waiterCounts.append(waiterCount)
        if waiterCount == 2 {
          twoWaiters.signal()
        }
      },
      sizedImageDecoder: { data, _ in UIImage(data: data, scale: 1) }
    )
    let cardImage = Task {
      try await loader.image(
        for: Self.imageURL,
        maximumPixelSize: 512
      )
    }
    await waitUntilIncremented(requestCounter)
    let backgroundImage = Task {
      try await loader.image(
        for: Self.imageURL,
        maximumPixelSize: 1_920
      )
    }
    await twoWaiters.wait()
    #expect(waiterCounts.values.contains(2))

    cardImage.cancel()
    await expectCancellation(of: cardImage)
    #expect(stopCounter.count == 0)

    responseGate.release()
    let image = try await backgroundImage.value
    #expect(image.size.width > 0)
    #expect(requestCounter.count == 1)
  }

  @Test
  func testPurgeInvalidatesAllInFlightPixelSizes() async throws {
    let responseGate = ImageResponseGate()
    defer {
      responseGate.release()
      ImageMockURLProtocol.handler = nil
    }
    let requestCounter = LockedCounter()
    let waiterCounts = LockedValues<Int>()
    let twoWaiters = AsyncTestSignal()
    ImageMockURLProtocol.handler = { request in
      requestCounter.increment()
      responseGate.wait()
      return (
        Self.response(for: request, contentType: "image/png"),
        Self.onePixelPNG
      )
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageMockURLProtocol.self]
    let loader = MoreAppsImageLoader(
      sessionConfiguration: configuration,
      onDataWaiterAdded: { _, waiterCount in
        waiterCounts.append(waiterCount)
        if waiterCount == 2 {
          twoWaiters.signal()
        }
      },
      sizedImageDecoder: { data, _ in UIImage(data: data, scale: 1) }
    )
    let cardImage = Task {
      try await loader.image(
        for: Self.imageURL,
        maximumPixelSize: 512
      )
    }
    await waitUntilIncremented(requestCounter)
    let backgroundImage = Task {
      try await loader.image(
        for: Self.imageURL,
        maximumPixelSize: 1_920
      )
    }
    await twoWaiters.wait()
    #expect(waiterCounts.values.contains(2))

    await loader.removeAllCachedImages()
    responseGate.release()
    await expectCancellation(of: cardImage)
    await expectCancellation(of: backgroundImage)

    let freshImage = try await loader.image(
      for: Self.imageURL,
      maximumPixelSize: 1_920
    )
    #expect(freshImage.size.width > 0)
    #expect(requestCounter.count == 2)
  }

  @Test
  func testCancelledCallerDoesNotReceiveDecodedImage() async {
    defer { ImageMockURLProtocol.handler = nil }
    let counter = LockedCounter()
    ImageMockURLProtocol.handler = { request in
      counter.increment()
      Thread.sleep(forTimeInterval: 0.1)
      return (
        Self.response(
          for: request,
          contentType: "image/png"
        ),
        Self.onePixelPNG
      )
    }

    let loader = makeLoader()
    let cancelledCaller = Task {
      try await loader.image(for: Self.imageURL)
    }
    let remainingCaller = Task {
      try await loader.image(for: Self.imageURL)
    }
    await waitUntilIncremented(counter)
    cancelledCaller.cancel()

    do {
      _ = try await cancelledCaller.value
      Issue.record("Expected cancellation")
    } catch is CancellationError {
      // Expected.
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    do {
      let image = try await remainingCaller.value
      #expect(image.size.width > 0)
      #expect(counter.count == 1)
    } catch {
      Issue.record("Shared request unexpectedly failed: \(error)")
    }
  }

  @Test
  func testCancellingOnlyWaiterCancelsHTTPTransport() async {
    defer {
      ImageMockURLProtocol.handler = nil
      ImageMockURLProtocol.defersResponse = false
      ImageMockURLProtocol.onStartLoading = nil
      ImageMockURLProtocol.onStopLoading = nil
    }
    let starts = LockedCounter()
    let stops = LockedCounter()
    ImageMockURLProtocol.handler = { request in
      (
        Self.response(for: request, contentType: "image/png"),
        Self.onePixelPNG
      )
    }
    ImageMockURLProtocol.defersResponse = true
    ImageMockURLProtocol.onStartLoading = { starts.increment() }
    ImageMockURLProtocol.onStopLoading = { stops.increment() }

    let task = Task {
      try await makeLoader().image(for: Self.imageURL)
    }
    await waitUntilIncremented(starts)

    task.cancel()
    await expectCancellation(of: task)

    await stops.waitUntilIncremented()
    #expect(stops.count == 1)
  }

  @Test
  func testPurgeInvalidatesAnInFlightDownload() async throws {
    defer { ImageMockURLProtocol.handler = nil }
    let counter = LockedCounter()
    ImageMockURLProtocol.handler = { request in
      counter.increment()
      Thread.sleep(forTimeInterval: 0.1)
      return (
        Self.response(for: request, contentType: "image/png"),
        Self.onePixelPNG
      )
    }

    let loader = makeLoader()
    let staleRequest = Task {
      try await loader.image(for: Self.imageURL)
    }
    await waitUntilIncremented(counter)

    await loader.removeAllCachedImages()
    await expectCancellation(of: staleRequest)

    let image = try await loader.image(for: Self.imageURL)
    #expect(image.size.width > 0)
    #expect(counter.count == 2)
  }

  @Test
  func testPurgeInvalidatesAnInFlightDecode() async throws {
    defer { ImageMockURLProtocol.handler = nil }
    let counter = LockedCounter()
    ImageMockURLProtocol.handler = { request in
      counter.increment()
      return (
        Self.response(for: request, contentType: "image/png"),
        Self.onePixelPNG
      )
    }

    let gate = ImageDecodeGate()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageMockURLProtocol.self]
    let loader = MoreAppsImageLoader(
      sessionConfiguration: configuration,
      imageDecoder: { data in
        await gate.decode(data)
      }
    )
    let staleRequest = Task {
      try await loader.image(for: Self.imageURL)
    }
    await gate.waitUntilStarted()

    await loader.removeAllCachedImages()
    await gate.release()
    await expectCancellation(of: staleRequest)

    let image = try await loader.image(for: Self.imageURL)
    #expect(image.size.width > 0)
    #expect(counter.count == 2)
  }

  private func makeLoader() -> MoreAppsImageLoader {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageMockURLProtocol.self]
    return MoreAppsImageLoader(sessionConfiguration: configuration)
  }

  private func expectCancellation(
    of task: Task<UIImage, Error>
  ) async {
    do {
      _ = try await task.value
      Issue.record("Expected cancellation")
    } catch is CancellationError {
      // Expected.
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private func waitUntilIncremented(_ counter: LockedCounter) async {
    await counter.waitUntilIncremented()
    #expect(counter.count > 0)
  }

  private static func response(
    for request: URLRequest,
    statusCode: Int = 200,
    contentType: String
  ) -> HTTPURLResponse {
    HTTPURLResponse(
      url: request.url ?? imageURL,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": contentType]
    )!
  }

  private static let imageURL = URL(
    string: "https://example.com/icon.png"
  )!

  private static let onePixelPNG = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
  )!
}

@MainActor
private final class MainActorSignal {
  private var isSignaled = false
  private var continuation: CheckedContinuation<Void, Never>?

  func signal() {
    isSignaled = true
    let continuation = continuation
    self.continuation = nil
    continuation?.resume()
  }

  func wait() async {
    guard !isSignaled else { return }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }
}

private actor ImageDecodeGate {
  private var isWaiting = true
  private let didStart = AsyncTestSignal()
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func decode(_ data: Data) async -> UIImage? {
    didStart.signal()
    if isWaiting {
      await withCheckedContinuation { continuation in
        continuations.append(continuation)
      }
    }
    return UIImage(data: data, scale: 1)
  }

  func waitUntilStarted() async {
    await didStart.wait()
  }

  func release() {
    isWaiting = false
    continuations.forEach { $0.resume() }
    continuations.removeAll()
  }
}

private final class LockedCounter {
  private let lock = NSLock()
  private let didIncrement = AsyncTestSignal()
  private var value = 0

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  @discardableResult
  func increment() -> Int {
    lock.lock()
    value += 1
    let updatedValue = value
    lock.unlock()
    didIncrement.signal()
    return updatedValue
  }

  func waitUntilIncremented() async {
    await didIncrement.wait()
  }
}

private final class LockedValues<Value> {
  private let lock = NSLock()
  private var storage: [Value] = []

  var values: [Value] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func append(_ value: Value) {
    lock.lock()
    defer { lock.unlock() }
    storage.append(value)
  }
}

private final class ImageResponseGate {
  private let condition = NSCondition()
  private var isReleased = false

  func wait() {
    condition.lock()
    while !isReleased {
      condition.wait()
    }
    condition.unlock()
  }

  func release() {
    condition.lock()
    isReleased = true
    condition.broadcast()
    condition.unlock()
  }
}

private final class ImageMockURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
  static var defersResponse = false
  static var onStartLoading: (() -> Void)?
  static var onStopLoading: (() -> Void)?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(
        self,
        didFailWithError: URLError(.resourceUnavailable)
      )
      return
    }
    Self.onStartLoading?()
    guard !Self.defersResponse else { return }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(
        self,
        didReceive: response,
        cacheStoragePolicy: .notAllowed
      )
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {
    Self.onStopLoading?()
  }
}
