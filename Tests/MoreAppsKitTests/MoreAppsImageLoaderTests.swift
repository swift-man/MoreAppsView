import Foundation
import Testing
import UIKit
@testable import MoreAppsKit

@MainActor
@Suite(.serialized)
struct MoreAppsImageLoaderTests {
    @Test
    func testValidImageIsCoalescedCachedAndCanBePurged() async throws {
        defer { ImageMockURLProtocol.handler = nil }
        let counter = LockedCounter()
        ImageMockURLProtocol.handler = { request in
            counter.increment()
            Thread.sleep(forTimeInterval: 0.05)
            return (
                Self.response(
                    for: request,
                    contentType: "image/png"
                ),
                Self.onePixelPNG
            )
        }

        let loader = makeLoader()
        async let first = loader.image(for: Self.imageURL)
        async let second = loader.image(for: Self.imageURL)
        let images = try await (first, second)

        #expect(images.0.size.width > 0)
        #expect(images.1.size.height > 0)
        #expect(counter.count == 1)

        _ = try await loader.image(for: Self.imageURL)
        #expect(counter.count == 1)

        await loader.removeAllCachedImages()
        _ = try await loader.image(for: Self.imageURL)
        #expect(counter.count == 2)
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
            guard case let .network(message) = error else {
                Issue.record("Expected network error, got \(error)")
                return
            }
            #expect(message.contains("32-byte limit"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
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
        let task = Task {
            try await loader.image(for: Self.imageURL)
        }
        while counter.count == 0 {
            await Task.yield()
        }
        task.cancel()
        let sharedRequestImage = Task {
            try await loader.image(for: Self.imageURL)
        }

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            let image = try await sharedRequestImage.value
            #expect(image.size.width > 0)
            #expect(counter.count == 1)
        } catch {
            Issue.record("Shared request unexpectedly failed: \(error)")
        }
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
        while counter.count == 0 {
            await Task.yield()
        }

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

private actor ImageDecodeGate {
    private var isWaiting = true
    private var hasStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func decode(_ data: Data) async -> UIImage? {
        hasStarted = true
        if isWaiting {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return UIImage(data: data, scale: 1)
    }

    func waitUntilStarted() async {
        while !hasStarted {
            await Task.yield()
        }
    }

    func release() {
        isWaiting = false
        continuation?.resume()
        continuation = nil
    }
}

private final class LockedCounter {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private final class ImageMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

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

    override func stopLoading() {}
}
