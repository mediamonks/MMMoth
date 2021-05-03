//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import Foundation

extension MMMothClient {

	/// Default implementation of `MMMothClientNetworking` used by `MMMothClient`.
	///
	/// Not open for subclassing, but open for composing into your own implementations to simulate network errors
	/// or delays in test builds of your app.
	public final class DefaultNetworking: MMMothClientNetworking {

		public init() {
			// Nothing to init but have to keep to allow creating instances outside the module.
		}

		public func performTokenRequest(
			_ request: URLRequest,
			completion: @escaping (Result<[String: Any], NSError>) -> Void
		) {

			// To not capture self or repeating domain below.
			func makeError(_ message: String, underlyingError: NSError? = nil) -> NSError {
				return NSError(domain: self, message: message, underlyingError: underlyingError)
			}

			func dispatchCompletion(_ result: Result<[String: Any], NSError>) {
				DispatchQueue.main.async {
					completion(result)
				}
			}

			let task = URLSession.shared.dataTask(with: request) { (data, response, error) in

				if let error = error {
					dispatchCompletion(.failure(makeError("Token request failed", underlyingError: error as NSError)))
					return
				}

				guard let response = response as? HTTPURLResponse else {
					dispatchCompletion(.failure(makeError("Got no error nor response")))
					return
				}

				// Note that the token endpoint returns error info with status code 400,
				// see [https://tools.ietf.org/html/rfc6749#section-5.2]().
				guard response.statusCode == 200 || response.statusCode == 400 else {
					dispatchCompletion(.failure(makeError("Got \(response.statusCode)")))
					return
				}

				guard let data = data else {
					dispatchCompletion(.failure(makeError("Got no data")))
					return
				}

				// Not checking `response.mimeType` here as it might be absent or can include the "charset" parameter,
				// so comparing it with "application/json" won't work. Let's just try to decode it instead.

				do {
					guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
						// We don't allow fragments via options, so we should not end up here.
						assertionFailure()
						dispatchCompletion(.failure(makeError("Got a non-JSON response")))
						return
					}
					dispatchCompletion(.success(json))
				} catch {
					dispatchCompletion(.failure(makeError("Got a non-JSON response", underlyingError: error as NSError)))
				}
			}

			task.resume()
		}
	}
}
