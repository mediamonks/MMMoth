//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import MMMLog
import MMMLoadable

/// Basic info about an OpenID provider we want to know.
public struct MMMothOpenIDConfig {

	public let authorizationEndpoint: URL
	public let tokenEndpoint: URL?

	public init(
		authorizationEndpoint: URL,
		tokenEndpoint: URL?
	) {
		self.authorizationEndpoint = authorizationEndpoint
		self.tokenEndpoint = tokenEndpoint
	}
}

/// OpenID config that can be fetched/refreshed from somewhere, like a local .plist or a .json response of OpenID Discovery.
public protocol MMMothOpenIDConfigProvider: MMMLoadableProtocol {
	/// "Contents" property.
	var value: MMMothOpenIDConfig? { get }
}

// MARK: -

/// OpenID config that's immediately available.
public final class MMMothStaticOpenIDConfigProvider: MMMLoadable, MMMothOpenIDConfigProvider {

	public init(value: MMMothOpenIDConfig) {
		self.value = value
		super.init()
		setDidSyncSuccessfully()
	}

	public override func doSync() {
		// Nothing to do, always synced. Let's revert to "did sync" on the next run loop cycle just in case.
		DispatchQueue.main.async {
			self.setDidSyncSuccessfully()
		}
	}

	public override var isContentsAvailable: Bool { true }

	public private(set) var value: MMMothOpenIDConfig?
}

/// OpenID config that can be fetched from a provider according to OpenID Connect Discovery conventions.
/// See [https://openid.net/specs/openid-connect-discovery-1_0.html#ProviderConfig].
public final class MMMothOpenIDDiscoveryConfigProvider: MMMLoadable, MMMothOpenIDConfigProvider {

	public let issuerURL: URL

	private var task: URLSessionDataTask?

	public init(issuerURL: URL) {
		self.issuerURL = issuerURL
	}

	deinit {
    	task?.cancel()
	}

	private func configURLFromIssuerURL(_ issuerURL: URL) -> URL? {
		guard var components = URLComponents(url: issuerURL, resolvingAgainstBaseURL: true) else {
			return nil
		}
		if !components.path.hasSuffix("/") {
			components.path.append("/")
		}
		components.path.append(".well-known/openid-configuration")
		return components.url
	}

	private func error(_ message: String, underlyingError: NSError? = nil) -> NSError {
		NSError(domain: Self.self, message: message, underlyingError: underlyingError)
	}

	public override func doSync() {

		MMMLogTrace(self, "Fetching Open ID config for '\(issuerURL)'")

		guard let configURL = configURLFromIssuerURL(issuerURL) else {
			didFailWithError(self.error("Malformed issuer URL '\(issuerURL)'"))
			return
		}

		let task = URLSession.shared.dataTask(with: configURL) { [weak self] (data, response, error) in

			guard let self = self else { return }

			if let error = error {
				self.didFailWithError(error as NSError)
				return
			}
			guard let response = response as? HTTPURLResponse else {
				preconditionFailure()
			}
			guard response.statusCode == 200 else {
				self.didFailWithError(self.error("Got \(response.statusCode)"))
				return
			}
			guard let data = data, data.count > 0 else {
				self.didFailWithError(self.error("Got empty response"))
				return
			}

			do {
				self.didFetchResponse(try JSONDecoder().decode(ConfigResponse.self, from: data))
			} catch {
				self.didFailWithError(self.error("Invalid response", underlyingError: error as NSError))
			}
		}
		task.resume()
		self.task = task
	}

	public override var isContentsAvailable: Bool { value != nil }

	private func didFailWithError(_ error: NSError) {
		MMMLogError(self, "Failed fetching Open ID config for '\(issuerURL)': \(error.mmm_description())")
		DispatchQueue.main.async { [weak self] in
			self?.setFailedToSyncWithError(error)
		}
	}

	private func didFetchResponse(_ response: ConfigResponse) {

		DispatchQueue.main.async {

			let config = MMMothOpenIDConfig(
				authorizationEndpoint: response.authorization_endpoint,
				tokenEndpoint: response.token_endpoint
			)

			MMMLogTrace(self, "Fetched successfully: \(config)")

			// TODO: match the issuer URL in the response, but don't compare literally as path might be different, like "/" vs "".
			if response.issuer != self.issuerURL {
				MMMLogError(
					self,
					"Note that the issuer URL in the config is not matching the one we used to fetch it: '\(response.issuer)' vs '\(self.issuerURL)'"
				)
			}

			self.value = config
			self.setDidSyncSuccessfully()
		}
	}

	/// We only need a small subset of the config, see [https://openid.net/specs/openid-connect-discovery-1_0.html#ProviderMetadata].
	private struct ConfigResponse: Decodable {

		// Not really using, just for sanity checks.
		let issuer: URL

		// This is the only one we need for now.
		let authorization_endpoint: URL

		// Optional because might be absent in case only implicit flow is used
		let token_endpoint: URL?
	}

	public private(set) var value: MMMothOpenIDConfig?
}
