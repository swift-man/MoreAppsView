//
//  RemoteJSONMoreAppsProvider.swift
//  MoreAppsKit
//
//  Created by SwiftMan on 8/1/26.
//  Copyright © 2026 MoreAppsKit. All rights reserved.
//

import Alamofire
import Foundation

private actor RemoteJSONMoreAppsRepository {
  static let defaultMaximumResponseByteCount = 1 * 1_024 * 1_024

  private let url: URL
  private let session: Session
  private let decoder: JSONDecoder
  private let maximumResponseByteCount: Int

  init(
    url: URL,
    session: Session,
    decoder: JSONDecoder,
    maximumResponseByteCount: Int
  ) {
    self.url = url
    self.session = session
    self.decoder = decoder
    self.maximumResponseByteCount = maximumResponseByteCount
  }

  func fetchApps() async throws -> [MoreApp] {
    guard MoreAppsHTTPSPolicy.isSecure(url) else {
      throw RemoteJSONMoreAppsProviderError.insecureURL(url)
    }

    let data = try await Self.downloadData(
      from: url,
      using: session,
      maximumResponseByteCount: maximumResponseByteCount
    )

    do {
      return try decoder.decode([MoreApp].self, from: data)
    } catch {
      throw RemoteJSONMoreAppsProviderError.decoding(
        message: error.localizedDescription
      )
    }
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
        let receiver = RemoteJSONCatalogStreamReceiver(
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

private final class RemoteJSONCatalogStreamReceiver: @unchecked Sendable {
  let queue = DispatchQueue(
    label: "com.moreappskit.catalog-stream-receiver"
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

  func responseDisposition(
    for response: HTTPURLResponse
  ) -> Request.ResponseDisposition {
    guard let responseURL = response.url,
      MoreAppsHTTPSPolicy.isSecure(responseURL)
    else {
      fail(
        with: RemoteJSONMoreAppsProviderError.network(
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
        with: RemoteJSONMoreAppsProviderError.responseTooLarge(
          maximumByteCount: maximumResponseByteCount
        )
      )
      return .cancel
    }

    return .allow
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
        throwing: RemoteJSONMoreAppsProviderError.responseTooLarge(
          maximumByteCount: maximumResponseByteCount
        )
      )
      return
    }
    data.append(chunk)
    lock.unlock()
  }

  private func finish(with completion: DataStreamRequest.Completion) {
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
        throwing: RemoteJSONMoreAppsProviderError.network(
          message: error.localizedDescription
        )
      )
      return
    }

    guard let response = completion.response,
      MoreAppsHTTPSPolicy.isSecure(response.url)
    else {
      continuation.resume(
        throwing: RemoteJSONMoreAppsProviderError.network(
          message: "The response did not use HTTPS."
        )
      )
      return
    }

    guard (200..<300).contains(response.statusCode) else {
      continuation.resume(
        throwing: RemoteJSONMoreAppsProviderError.network(
          message: "Unexpected HTTP status: \(response.statusCode)."
        )
      )
      return
    }

    guard !data.isEmpty else {
      continuation.resume(
        throwing: RemoteJSONMoreAppsProviderError.network(
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

/// An error produced while loading a remote MoreAppsKit catalog.
public enum RemoteJSONMoreAppsProviderError: Error, Equatable, LocalizedError, Sendable {
  /// The catalog URL does not use secure HTTPS transport.
  case insecureURL(URL)

  /// The declared or received response body exceeded the supported limit.
  case responseTooLarge(maximumByteCount: Int)

  /// The HTTP request or response validation failed.
  case network(message: String)

  /// The response body could not be decoded as `[MoreApp]`.
  case decoding(message: String)

  /// A human-readable description suitable for diagnostics and events.
  public var errorDescription: String? {
    switch self {
    case .insecureURL(let url):
      return "The catalog URL must use HTTPS: \(url.absoluteString)"
    case .responseTooLarge(let maximumByteCount):
      return "The catalog response exceeded the "
        + "\(maximumByteCount)-byte limit."
    case .network(let message):
      return "Network error: \(message)"
    case .decoding(let message):
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
      decoder: decoder,
      maximumResponseByteCount: RemoteJSONMoreAppsRepository
        .defaultMaximumResponseByteCount
    )
  }

  init(
    url: URL,
    session: Session,
    decoder: JSONDecoder = JSONDecoder(),
    maximumResponseByteCount: Int = RemoteJSONMoreAppsRepository
      .defaultMaximumResponseByteCount
  ) {
    self.url = url
    self.repository = RemoteJSONMoreAppsRepository(
      url: url,
      session: session,
      decoder: decoder,
      maximumResponseByteCount: maximumResponseByteCount
    )
  }

  init(
    url: URL,
    sessionConfiguration: URLSessionConfiguration,
    decoder: JSONDecoder = JSONDecoder(),
    maximumResponseByteCount: Int
  ) {
    self.url = url
    self.repository = RemoteJSONMoreAppsRepository(
      url: url,
      session: Session(configuration: sessionConfiguration),
      decoder: decoder,
      maximumResponseByteCount: maximumResponseByteCount
    )
  }

  /// Downloads and decodes the remote catalog.
  ///
  /// - Throws: ``RemoteJSONMoreAppsProviderError`` when transport validation,
  ///   the one-megabyte response limit, HTTP loading, or decoding fails.
  public func fetchApps() async throws -> [MoreApp] {
    try await repository.fetchApps()
  }
}
