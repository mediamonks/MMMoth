//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import Foundation
import MMMLog
import MMMObservables

/// Basic [OAuth 2.0](https://tools.ietf.org/html/rfc6749) client supporting
/// [OpenID](https://openid.net/specs/openid-connect-core-1_0.html) as well.
///
/// ## OAuth Refresher
///
/// 1. The app ("client") wants to get access to protected resources of the end-user and thus needs a permission from
/// them in the form of an access token, a string that the app is going to show to the server storing those resources.
///
/// 2. In order to obtain the access token the app opens a web browser (in-app or external) and navigates it to
/// the corresponding "authorization server". It tells the server what kind of app it is ("client identifier"),
/// what resources the talk is about ("scope"), and how the credentials should be returned back ("response type").
///
/// 3. The end-user authenticates themselves on this page and confirms that they are OK with the app accessing the
/// resources in question.
///
/// 4. The server responds back to the app by directing the browser to a "redirect URL" mentioned by the app earlier
/// adding its response in "query" or "fragment" parts of this URL.
///
/// 5. The app then either directly finds the access token in this response URL ("implicit flow") or uses a short-lived
/// code from there to get the access token via a separate network call to the "token endpoint"
/// ("authorization code flow").
///
/// Note that the extra step about code seems like having no sense for a native app. This is because it was designed
/// for web servers and similar clients allowing them to obtain access tokens without the end-user (and thus any
/// malicious code running on their device) seeing them. Note also that the access tokens usually expire but might
/// be refreshed using a "refresh token". A quirk of the protocol is that this token, if available, can be obtained
/// only via "authorization code flow".
///
/// ## OpenID Refresher
///
/// OpenID is essentially an OAuth flow where the resource being accessed is some basic information about the user.
/// Implementation-wise the "scope" of such a flow includes "openid" and a more fancy JWT ID Token is returned
/// in addition to (or instead of) the usual access token. It's an official replacement for ad-hoc OAuth flows used
/// earlier to authenticate users of one service by asking them via OAuth for access to their email address or basic
/// details let say on another service.
///
/// ## Usage
///
/// TLDR: call `start*()` and watch the `state` to become `.authorized` helping with authorization UI when needed.
///
/// Nothing happens when the client is initialized, i.e. it stays at `.idle`.
///
/// Once `start()` and friends are called the client checks the storage for the existing credentials corresponding
/// to the passed scope and response types:
///
/// - If credentials were found and are not expired or can be refreshed, then it directly switches to
///   `.authorized` state. The user code now has access to the token(s).
///
/// - If no good credentials were found and a non-interactive ("silent") mode was specified, then the client
///   cancels the flow. The user code can treat this state as "not logged in" / "have no access".
///
/// - If no good credentials were found and an interactive mode was specified, then the client
///   enters `.authorizing` state and expects the user code to help with authorization UI
///   by presenting a browser (in-app or external).
///
///   (See `AuthWebViewController` in "MMMoth/UI" for a basic implementation.)
///
///   The browser should navigate to the endpoint associated with `.authorizing` state.
///   The user code should be able to intercept all the requests to the associated redirect URL and feed them back
///   to the client via `handleAuthorizationRedirect()`; it should also report any errors opening the endpoint
///   via `handleAuthorizationFailure()` and can cancel the flow via `cancel()`.
///
/// When the client gets information from authorization server via `handleAuthorizationRedirect()`, then it either:
///
/// - immediatelly fails the flow (in case the server returned an explicit error or provided an invalid response);
///
/// - or directly enters `.authorized` state (in case of an "implicit" flow, that is when responseType
///   does NOT include `.code`);
///
/// - or begins exchanging the authorization code to token(s) (in case of an "authorization code" flow, that is when
///   responseType does include `.code`).
///
/// A picture for the above:
///
/// ```
///          ┌─────────────────┐
///          │      idle       │
///          └─────────────────┘
///                   │
///                   ▼
///                                          ┏━━━━━━━━━━━━━━━━━┓
///               start()  ─────────────────▶┃   authorized    ┃
///                         Have credentials ┗━━━━━━━━━━━━━━━━━┛
///                   │       in the storage
///                   ▼
///         No good credentials              ┌─────────────────┐
///            in the storage   ────────────▶│    cancelled    │
///                   │          Silent mode └─────────────────┘
///                   │
///  Interactive mode │
///                   ▼
///          ┌ ─ ─ ─ ─ ─ ─ ─ ─ ┐  The user code opens a browser
///              authorizing      and directs it to the
///          └ ─ ─ ─ ─ ─ ─ ─ ─ ┘  specified URL.
///
///
///  The user code managing the browser calls either of these:
///
///                                          ┌─────────────────┐
///                                cancel()─▶│    cancelled    │
///                                          └─────────────────┘
///                                          ┌─────────────────┐
///            handleAuthorizationFailure()─▶│     failed      │
///                                          └─────────────────┘
///                                                   ▲
///           handleAuthorizationRedirect()           │
///
///  Implicit │   Auth Code │             │           │
///      flow │   or Hybrid │
///           │        flow ▼             └ ─ ─ ─ ─ ─ ┤
///           │    ┌ ─ ─ ─ ─ ─ ─ ─ ─ ┐
///           │       fetchingToken   ─ ─ ─ ─ ─ ─ ─ ─ ┘
///           │    └ ─ ─ ─ ─ ─ ─ ─ ─ ┘
///           │             │
///           │             ▼
///           │    ┏━━━━━━━━━━━━━━━━━┓
///           └───▶┃   authorized    ┃
///                ┗━━━━━━━━━━━━━━━━━┛
/// ```
///
/// ## Notes
///
/// Initially I wanted to have an OpenID client that would be using an OAuth client under the hood,
/// but this would be more complicated without the OAuth client knowing of OpenID-specific parameters.
public final class MMMothClient {

	private let storage: MMMothClientStorage
	private let networking: MMMothClientNetworking
	private let timeSource: MMMothClientTimeSource

	/// Initializes without attempting to obtain authorization or check for previously stored credentials.
	///
	/// - Parameter storage:
	/// 	Allows to override where and how the credentials are stored.
	/// 	If not provided, then credentials are stored under "MMMOth" key in `UserDefaults`.
	///
	/// - Parameter networking: Allows to override how network calls are made. Normally used for testing.
	///
	/// - Parameter timeSource: Allows to override the notion of current time. Used only for testing.
	public init(
		storage: MMMothClientStorage? = nil,
		networking: MMMothClientNetworking? = nil,
		timeSource: MMMothClientTimeSource? = nil
	) {
		// Using a literal key instead of type name allows to not depend on renames.
		self.storage = storage ?? UserDefaultsStorage(key: "MMMOth")
		self.networking = networking ?? DefaultNetworking()
		self.timeSource = timeSource ?? DefaultTimeSource()
	}

	deinit {
		cancelTokenRefresh()
	}

	public enum State: Equatable {

		/// Not doing anything yet, did not even check for previous credentials.
		/// The user code is expected to begin the flow via `start()`.
		case idle

		/// The flow has been started and no valid access or refresh tokens were found in the storage.
		/// No "silent" mode was requested so the client is waiting for the user code to show a browser and navigate
		/// to the given URL where the end-user is going to authenticate themselves and authorize the client to access
		/// the resource in question.
		///
		/// The user code is also responsible for intercepting requests to a redirect URL and passing them back
		/// to us via `handleAuthorizationFailure()`.
		///
		/// Note that we are not using `URLRequest` here as it would be hard to support one with an external browser.
		case authorizing(url: URL, redirectURL: URL)

		/// The client is exchanging the authorization code received from the server for an access token.
		case fetchingToken

		/// The flow has failed at some point, no credentials are available.
		/// The user code might restart the process.
		case failed(NSError)

		/// The flow has been explicitly cancelled by the user.
		/// Separate from `.failed` to never display "cancelled" errors.
		case cancelled

		/// The client got authorization to access the requested scopes.
		/// The corresponding tokens are available (`credentials`) though they might be (almost) expired
		/// and the client can be in the process of refreshing them. When this happens the user code should wait before
		/// using the credentials. 
		case authorized(Credentials, refreshing: Bool)
	}

	public private(set) var state: State = .idle {

		didSet {

			// Not checking if the state has really changed: can go from .failed again to .failed right in start().

			// Let's customize traces for important states.
			switch state {

			case .failed(let error):
				// Errors should be always traced.
				MMMLogError(self, "Failed: \(error.mmm_description)")

			case .authorized(let credentials, let refreshing):
				// Note that credentials are not exposing tokens, so it should be safe to trace them in production.
				if refreshing {
					MMMLogInfo(self, "Authorized, but credentials are (almost) expired, refreshing: \(credentials)")
				} else {
					MMMLogInfo(self, "Authorized: \(credentials)")
				}

			default:
				// The rest are traced as usual.
				MMMLogTrace(self, "State: \(state)")
			}

			_didChange.trigger()
		}
	}

	private let _didChange = SimpleEvent()

	/// Triggers when `state` changes.
	public var didChange: SimpleEventObservable { _didChange }

	// Things available only when the flow has been started. Combined to avoid having individual items as optionals.
	private struct FlowState {
		let config: Config
		let scope: Set<String>
		let responseType: Set<ResponseType>
		let stateString: String
		let nonceString: String
	}

	private var flowState: FlowState?

	/// The mode to start the flow in.
	public enum Mode {

		/// No attempt to request user authorization interactively (via a browser) is made in this mode.
		/// The flow succeeds only if valid credentials from the previous session are available.
		/// This can be used on app start-up to check if the user is logged in or has access to a resource already.
		case silent

		/// When in this mode it is expected that the user code monitors the state of the client and helps
		/// it in getting permission from the user by presenting them a browser, etc (see the class description).
		case interactive
	}


	/// A shortcut for `start()` beginning "authorization code" OpenID flow.
	///
	/// This flow involves an extra network request but allows to have a refresh token too.
	public func startOpenIDFlow(
		config: Config,
		mode: Mode,
		openIDSettings: OpenIDSettings? = nil
	) {
		start(
			config: config,
			mode: mode,
			responseType: [ .code ],
			scope: [ "openid" ],
			openIDSettings: openIDSettings ?? OpenIDSettings()
		)
	}

	/// A shortcut for `start()` beginning "implicit" OpenID flow.
	///
	/// This flow is faster than the "authorization code" flow but retrieves only an ID Token that cannot be refreshed.
	public func startImplicitOpenIDFlow(
		config: Config,
		mode: Mode,
		openIDSettings: OpenIDSettings? = nil
	) {
		start(
			config: config,
			mode: mode,
			responseType: [ .idToken ],
			scope: [ "openid" ],
			openIDSettings: openIDSettings ?? OpenIDSettings()
		)
	}

	/// Called by the user code to start the flow.
	///
	/// The config is provided here to make it more convenient when it is not available right away, e.g. when it
	/// has to be fetched from a backend or an OpenID provider first.
	///
	/// Depending on the availability of the access/refresh tokens in the store it might skip some states.
	/// For example, if an access token is expired but a refresh token is still valid, then it'll begin with
	/// `.fetchingToken`.
	public func start(
		config: Config,
		mode: Mode,
		responseType: Set<ResponseType> = [ .code ],
		scope: Set<String> = .init(),
		openIDSettings: OpenIDSettings? = nil
	) {

		assert(Thread.isMainThread)
		assert(responseType.count >= 1, "Specify at least one response type")

		switch state {
		case .idle, .failed, .cancelled:
			// Supporting flow restart in these states.
			break
		default:
			assertionFailure("Trying to restart \(type(of: self)) at unexpected point (\(state))")
			return
		}

		MMMLogInfo(
			self,
			"""
			Starting the flow for client '\(config.clientIdentifier)', \
			scope: '\(scope.sorted().joined(separator: " "))', \
			response type: '\(responseType.map{ $0.rawValue }.sorted().joined(separator: " "))'
			"""
		)

		// Setting `flowState` earlier just in case we enter `.authorized` immediately.
		let flowState = FlowState(
			config: config,
			scope: scope,
			responseType: responseType,
			stateString: newStateString(),
			nonceString: newStateString()
		)
		self.flowState = flowState

		// Let's see if we've got something in the storage from the previous session.
		if let credentials = credentialsForClientIdentifier(config.clientIdentifier) {

			// We can use them if they have a similar scope and were received for the same response type.
			if credentials.responseType == responseType {

				switch expirationStatus(credentials) {

				case .validForever, .valid, .expired(canBeRefreshed: true):

					MMMLogTrace(self, "Got compatible credentials from the storage")

					// Unfortunately, for the most special providers the scope returned is not always a
					// superset of what we were asking for originally, so we only emit warning for those.
					if !credentials.scope.isSuperset(of: scope) {
						MMMLogError(
							self, """
							Note that the scope of credentials in the store (\(credentials.scope)) is not a \
							superset of what we ask for now (\(scope)). We are allowing this though as you \
							must be using one of those very special providers.
							"""
						)
					}

					self.setAuthorized(credentials)

					return

				case .expired(canBeRefreshed: false):
					MMMLogTrace(self, "Skipping credentials in the storage because they are expired and cannot be refreshed")
				}

			} else {
				MMMLogTrace(self, "Skipping credentials in the storage due to scope or response type mismatch")
			}

			// Not dropping the unfit credentials till get the newer ones.
		}

		guard mode == .interactive else {
			MMMLogTrace(self, "No good credentials in the storage nor can do interactive authorization")
			self.state = .cancelled
			self.cleanUp()
			return
		}

		// In case of authorization code we would later need the token endpoint, so let's flag this early.
		if responseType.contains(.code) && config.tokenEndpoint == nil {
			// Not asserting because the config might be dynamic.
			setFailed("Response type is 'code' but no token endpoint is configured to exchange the code later")
			return
		}

		guard let url = authorizationEndpointURL(flowState: flowState, openIDSettings: openIDSettings) else {
			setFailed("Could not prepare the authorization endpoint URL")
			return
		}

		self.state = .authorizing(url: url, redirectURL: config.redirectURL)
	}

	private func credentialsForClientIdentifier(_ clientIdentifier: String) -> Credentials? {

		guard let data = storage.credentialsForClientIdentifier(clientIdentifier) else {
			return nil
		}

		do {
			return try JSONDecoder().decode(Credentials.self, from: data)
		} catch {
			MMMLogError(self, "Could not decode credentials from the storage: \(error.mmm_description)")
			return nil
		}
	}

	private func encodeCredentials(_ credentials: Credentials) throws -> Data {
		return try JSONEncoder().encode(credentials)
	}

	/// A random token used for `state` and `nonce` parameters.
	private func newStateString() -> String {
		// Should have at least 128 random bits in it, but at least 160 is recommended,
		// see [https://tools.ietf.org/html/rfc6749#section-10.10].
		let stateBytesCount = Int(21) // 110%, but one byte less to avoid base64 padding.
		var stateBytes = Data(count: stateBytesCount)
		// `arc4random()` Is good enough in our case. Don't want to handle errors with `SecRandomCopyBytes()`.
		stateBytes.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, stateBytesCount) }
		return stateBytes.base64EncodedString()
	}

	private func authorizationEndpointURL(
		flowState: FlowState,
		openIDSettings: OpenIDSettings?
	) -> URL? {

		var params: [String: String] = [:]

		// What do we want back: authorization code, token directly, etc. Required.
		params["response_type"] = flowState.responseType.map{ $0.rawValue }.sorted().joined(separator: " ")

		// Client identifier. Required.
		params["client_id"] = flowState.config.clientIdentifier

		// Note that the client authentication is not performed for the authorization endpoint,
		// i.e. we don't provide the secret here even if we have one.
		//
		// According to the spec the client secret should be passed via headers (Basic authentication),
		// or via the body of the corresponding POST request; never via query parameters.
		// See [https://tools.ietf.org/html/rfc6749#section-2.3.1]().
		//
		// Since the endpoint is supposed to be passed to a browser (potentially external), we would not be able
		// to use the secret here even if a non-standard server insisted on passing one.
		//
		// Client authentication does not make sense for public clients like us (native app) in general,
		// however the server MAY insists on one, so we'll try to support it just in case for the token endpoint.

		// Redirect URL. Required.
		params["redirect_uri"] = flowState.config.redirectURL.absoluteString

		// What kind of user resources we want authorization for, if different from default. Optional.
		if !flowState.scope.isEmpty {
			params["scope"] = flowState.scope.joined(separator: " ")
		}

		// A piece of randomness identifying this authorization attempt to counter CSRF,
		// see [https://tools.ietf.org/html/rfc6749#section-10.12]().
		// Recommended.
		params["state"] = flowState.stateString

		// A nonce is required when ID Token is expected, see [https://openid.net/specs/openid-connect-core-1_0.html#ImplicitAuthRequest]().
		if flowState.responseType.contains(.idToken) {
			params["nonce"] = flowState.nonceString
		}

		// OpenID specific parameters.
		if let display = openIDSettings?.display {
			params["display"] = display.rawValue
		}
		if let prompt = openIDSettings?.prompt {
			params["prompt"] = prompt.map{ $0.rawValue }.joined(separator: " ")
		}

		return urlWithParamsInQuery(url: flowState.config.authorizationEndpoint, params: params)
	}

	/// Turns the client into `.cancelled` state unless it is in `.authrorized` already. Safe to call multiple times.
	/// Use `end()` to cancel it even when athorized.
	public func cancel() {

		assert(Thread.isMainThread)

		switch state {
		case .idle, .cancelled, .authorized:
			MMMLogTrace(self, "Tried to cancel the flow, but it's \(state) already, skipping")
		case .authorizing, .fetchingToken, .failed:
			MMMLogTrace(self, "Cancelling the flow")
			self.state = .cancelled
			self.cleanUp()
		}
	}

	/// Forgets the credentials, if was authorized, cancels the flow otherwise.
	public func end() {

		assert(Thread.isMainThread)

		switch state {
		
		case .authorized:

			guard let flowState = flowState else { preconditionFailure() }

			// TODO: for OpenID we can also request to end the corresponding session with the authorization server,
			// see [https://openid.net/specs/openid-connect-session-1_0.html]().
			// This involves a webview however and might look weird in a native app where no webview
			// is used when somebody request to log out.
			MMMLogInfo(self, "Ending the flow by dropping credentials")

			do {
				try storage.deleteCredentialsForClientIdentifier(flowState.config.clientIdentifier)
			} catch {
				MMMLogError(self, "Could not delete credentials: \(error.mmm_description)")
			}

			self.state = .cancelled
			self.cleanUp()

		default:
			MMMLogTrace(self, "Tried to end the flow that was in \(state) already, cancelling instead")
			self.cancel()
		}
	}

	private func cleanUp() {
		// Effectively ignoring a pending token endpoint request, if any.
		self.tokenRequestCookie += 1
		// Cancel scheduled token refreshes, if any.
		self.cancelTokenRefresh()
		// Forgetting everything about the flow.
		self.flowState = nil
	}

	private func error(_ message: String, underlyingError: NSError? = nil) -> MMMError {
		return MMMError(domain: self, message: message, underlyingError: underlyingError)
	}

	private func setFailed(_ message: String, underlyingError: NSError? = nil) {

		// Note that it is possible to fail while being in the .failed state already, so no checks here.

		self.cleanUp()

		let error = self.error(message, underlyingError: underlyingError)
		self.state = .failed(error)
	}

	// TODO: move these two into a local extension

	private func urlWithParamsInQuery(url: URL, params: [String: String]) -> URL? {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
		// The query part might be present and we must retain it, [https://tools.ietf.org/html/rfc6749#section-3.1].
		components.queryItems = (components.queryItems ?? []) + params.map { URLQueryItem(name: $0.0, value: $0.1) }
		return components.url
	}

	private func paramsFromQueryOfURL(_ url: URL) -> [String: String]? {
		guard let components = NSURLComponents(url: url, resolvingAgainstBaseURL: true) else {
			return nil
		}
		return [String: String](
			components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
			uniquingKeysWith: { a, _ in a }
		)
	}

	private func paramsFromFragmentOfURL(_ url: URL) -> [String: String]? {
		guard let components = NSURLComponents(url: url, resolvingAgainstBaseURL: true) else {
			return nil
		}
		components.query = components.fragment
		return [String: String](
			components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
			uniquingKeysWith: { a, _ in a }
		)
	}

	private func errorFromParams(_ params: [String: Any]) -> NSError? {

		// See [https://tools.ietf.org/html/rfc6749#section-5.2]().

		guard let errorString = params["error"] else {
			return nil
		}

		// TODO: not sure if useful, but might be nicer to map errorString to codes or enum.

		let descriptionPart = params["error_description"].map { " ('\($0)')" } ?? ""

		return MMMError(domain: self, message: "'\(errorString)'\(descriptionPart)")
	}

	/// Called by the user code when the browser got redirected to `redirectURL`.
	public func handleAuthorizationRedirect(url: URL) {

		assert(Thread.isMainThread)

		guard case .authorizing = state else {
			assertionFailure("Got \(#function) call when was not expecting one")
			return
		}

		guard let flowState = flowState else {
			// Flow state is kept for the duration of the flow.
			preconditionFailure()
		}

		// Only pure Authorization Code flow uses the query for passing parameters,
		// implicit and hybrid ones use the fragment.
		// See [https://openid.net/specs/oauth-v2-multiple-response-types-1_0.html#Combinations]().
		let paramsPassedViaQuery = flowState.responseType == [ .code ]
		guard let params = paramsPassedViaQuery ? paramsFromQueryOfURL(url) : paramsFromFragmentOfURL(url) else {
			setFailed("Cannot parse the redirect URL")
			return
		}

		// Checking of the state must happen first, so we don't trust invalid responses.
		guard params["state"] == flowState.stateString else {
			// We could also ignore responses with wrong state assuming they are related to old flows
			// and ours is coming. Failing the flow seems better though as would cut malicious responses
			// and flag potential user code issues earlier.
			setFailed("Missing or invalid 'state' token in the redirect URL")
			return
		}

		if let error = errorFromParams(params) {
			setFailed("Authorization endpoint failure", underlyingError: error)
			return
		}

		if flowState.responseType.contains(.code) {

			// Note that we partially have credentials here in case of a "hybrid flow", that is when responseType
			// contains .token and/or .idToken in addition to .code.
			// We could grab them here, however they are going to be returned from the token endpoint that we are about
			// to visit anyway so it would make little sense.
			// (Though the whole hybrid flow makes little sense in a native app.)

			// Expect the authorization code which we are going to exchange to access/refresh/ID tokens.
			guard let code = params["code"], !code.isEmpty else {
				setFailed("Missing 'code' in the authorization endpoint redirect")
				return
			}

			enterFetchingToken(code: code)

		} else {

			// No trip to the server is required. All you need is in your arms.
			do {
				let credentials = try grabTokensFromResponse(params, source: .authorizationEndpoint)
				setAuthorized(credentials)
			} catch {
				self.setFailed("Invalid authorization endpoint redirect", underlyingError: error as NSError)
			}
		}
	}

	/// Called by the user code when the browser cannot open the authorization endpoint.
	public func handleAuthorizationFailure(error: NSError?) {
	
		guard case .authorizing = state else {
			MMMLogError(self, "Got authorization endpoint failure when was not really authorizing: \(error?.mmm_description ?? "<no extra info>")")
			return
		}

		setFailed("Failure accessing the authorization endpoint", underlyingError: error)
	}

	private func enterFetchingToken(code: String) {

		guard let config = flowState?.config else { preconditionFailure() }

		guard let tokenEndpoint = config.tokenEndpoint else {
			// The endpoint was checked when starting the flow.
			preconditionFailure()
		}

		self.state = .fetchingToken

		// TODO: authenticate the client
		// A note from [https://tools.ietf.org/html/rfc6749#section-9]():
		// "Native applications that use the authorization code grant type SHOULD do so without using client credentials,
		// due to the native application's inability to keep client credentials confidential."

		// All parameters are required, see [https://tools.ietf.org/html/rfc6749#section-4.1.3]().
		self.performTokenRequest(
			url: tokenEndpoint,
			params: [
				// We are going to exchange the authorization code...
				"grant_type": "authorization_code",
				// ...and here it goes.
				"code": code,
				// The code was given to this client...
				"client_id": config.clientIdentifier,
				// ...which was using the following redirect URL when obtaining the code.
				"redirect_uri": config.redirectURL.absoluteString
			]
		) { [weak self] (result) in
			self?.didFinishFetchingToken(result)
		}
	}

	private func didFinishFetchingToken(_ result: Result<[String: Any], NSError>) {

		guard case .fetchingToken = state else {
			assertionFailure()
			return
		}

		switch result {

		case .failure(let error):
			self.setFailed("Could not fetch the access token", underlyingError: error as NSError)

		case .success(let response):

			if let error = errorFromParams(response) {
				self.setFailed("Token endpoint failure", underlyingError: error)
				return
			}

			do {
				setAuthorized(try grabTokensFromResponse(response, source: .tokenEndpoint))
			} catch {
				setFailed("Got invalid response from the token endpoint", underlyingError: error as NSError)
			}
		}
	}

	private enum TokenResponseSource {
		case authorizationEndpoint
		case tokenEndpoint
	}

	// Grabs tokens from either an implicit flow redirect response or from the token endpoint response.
	private func grabTokensFromResponse(
		_ response: [String: Any],
		source: TokenResponseSource
	) throws -> Credentials  {

		guard let flowState = flowState else { preconditionFailure() }

		// The actual scope the access was given for. Required if different from the requested scope.
		// Note that this might show up in responses from both authorization and token endpoints.
		let scope: Set<String> = try {
			if let scope = response["scope"] {
				if let scopeString = scope as? String, !scopeString.isEmpty {
					return Set<String>(scopeString.split(separator: " ").map{ String($0) })
				} else {
					throw error("Invalid `scope` field")
				}
			} else {
				// The absense of scope means that it's the one that was initially requested.
				return flowState.scope
			}
		}()

		let (accessToken, expiresAt, refreshToken) = try { () -> (String?, Date?, String?) in

			// The access token is always expected from the token endpoint.
			// It's expected from the authorization endpoint only when asked for (implicit flow).
			guard source == .tokenEndpoint
				|| source == .authorizationEndpoint && flowState.responseType.contains(.token)
			else {
				return (nil, nil, nil)
			}

			// Access token. Required.
			guard let accessToken = response["access_token"] as? String, !accessToken.isEmpty else {
				throw error("No `access_token` in the response")
			}
			// What kind of access token is that. Required in order to properly use it.
			guard let tokenType = response["token_type"] as? String, !tokenType.isEmpty else {
				throw error("No `token_type` in the response")
			}
			// We could simply pass the token type up to the user code, but they might forget to check it
			// and get confused. Bearer tokens seem to be used most of the time anyway.
			guard tokenType == "bearer" else {
				throw error("Only 'bearer' token types are supported (got '\(tokenType)')")
			}

			// Time in seconds (since generation of the response) when the access token expires. Optional.
			let expiresIn: Int? = {
				if let expiresInRaw = response["expires_in"] {
					if let s = expiresInRaw as? String {
						return Int(s)
					} else {
						return expiresInRaw as? Int
					}
				} else {
					return nil
				}
			}()
			if let expiresIn = expiresIn, expiresIn <= 0 {
				throw error("Invalid `expires_in` field")
			}

			// It's more useful to store its absolute expiration time though.
			// TODO: we assume that it begins now, but could use time of the corresponding request.
			let expiresAt = expiresIn.map { timeSource.now().addingTimeInterval(TimeInterval($0)) }

			// The refresh token might appear only from the token endpoint, and even there it's optional.
			let refreshToken: String? = try {
				guard source == .tokenEndpoint, let token = response["refresh_token"] else {
					return nil
				}
				// And if it seems to be present, then it should be a non-empty string at least.
				guard let tokenString = token as? String, !tokenString.isEmpty else {
					throw error("Invalid `refresh_token` field")
				}
				return tokenString
			}()

			return (accessToken, expiresAt, refreshToken)
		}()

		let idToken: MMMothIDToken? = try {

			// The ID Token, just like the access token, is expected in the response of authorization endpoint
			// only in the case of the implicit flow (with `id_token` is among response types).
			// It also must be present in the response of the token endpoint when we know that we are handling OpenID
			// (i.e. 'openid' in the set scopes).
			guard
				source == .authorizationEndpoint && flowState.responseType.contains(.idToken)
				|| source == .tokenEndpoint && flowState.scope.contains("openid")
			else {
				return nil
			}

			guard let idTokenString = response["id_token"] as? String, !idTokenString.isEmpty else {
				throw error("No `id_token` in the response")
			}

			guard let idToken = try? MMMothIDToken(string: idTokenString) else {
				throw error("Invalid value of `id_token` field")
			}

			// Checking the nonce if present as we know it.
			// No sense to verify other stuff as we don't verify the signature here anyway.
			if source == .authorizationEndpoint, let nonce = idToken.nonce, flowState.nonceString != nonce {
				throw error("The nonce on ID token does not match")
			}

			return idToken
		}()

		return Credentials(
			scope: scope,
			responseType: flowState.responseType,
			accessToken: accessToken, expiresAt: expiresAt,
			refreshToken: refreshToken,
			idToken: idToken
		)
	}

	private enum ExpirationStatus {
		case validForever
		case valid(expireAt: Date, canBeRefreshed: Bool)
		case expired(canBeRefreshed: Bool)
	}

	private func expirationStatus(_ credentials: Credentials) -> ExpirationStatus {

		guard let flowState = flowState else { preconditionFailure() }

		let canBeRefreshed = (credentials.refreshToken != nil) && (flowState.config.tokenEndpoint != nil)

		if let expireAt = credentials.earliestExpirationDate() {
			if expireAt <= timeSource.now() {
				return .expired(canBeRefreshed: canBeRefreshed)
			} else {
				return .valid(expireAt: expireAt, canBeRefreshed: canBeRefreshed)
			}
		} else {
			// It can be that only the access token is available and no expiration info was provided.
			// Assuming that it never expires.
			return .validForever
		}
	}

	private func setAuthorized(_ credentials: Credentials) {

		guard let flowState = flowState else { preconditionFailure() }

		do {
			try storage.saveCredentials(
				encodeCredentials(credentials),
				clientIdentifier: flowState.config.clientIdentifier
			)
		} catch {
			// Not failing the flow in this case, the credentials can be used at least for this app session.
			MMMLogError(self, "Could not store credentials but continuing: \(error.mmm_description)")
		}

		cancelTokenRefresh()

		switch expirationStatus(credentials) {

		case .expired(canBeRefreshed: false):
			setFailed("Credentials have expired and there is no way to refresh it them")

		case .validForever:
			self.state = .authorized(credentials, refreshing: false)
			MMMLogTrace(self, "No expiration date is available, no need to schedule a refresh")

		case .expired(canBeRefreshed: true):
			// Let's schedule refresh asap and mark it as refreshing now.
			self.state = .authorized(credentials, refreshing: true)
			scheduleRegularTokenRefresh(0)

		case .valid(let expireAt, canBeRefreshed: true):
			self.state = .authorized(credentials, refreshing: false)
			// Let's schedule a refresh a bit earlier than the expiration time.
			// (Possible negative timeout is safe here.)
			scheduleRegularTokenRefresh(timeSource.timeIntervalFromNowToDate(expireAt.addingTimeInterval(-eagerRefreshInterval)))

		case .valid(let expireAt, canBeRefreshed: false):
			self.state = .authorized(credentials, refreshing: false)
			// The token(s) cannot be refreshed, so it's more like scheduling a check up to declare them expired.
			scheduleRegularTokenRefresh(timeSource.timeIntervalFromNowToDate(expireAt))
		}
	}

	// MARK: - Refreshing of Tokens

	// Note that could move these constants into the config, but reasonable defaults should be OK.

	/// How early before the actual token expiration time we should begin refreshing them.
	private let eagerRefreshInterval: TimeInterval = 2 * 60

	/// How the timeouts should grow after each failure to retry.
	private let refreshBackOffPolicy: (min: TimeInterval, max: TimeInterval, multiplier: Double) = (1, 2 * 60 * 60, 2)

	private enum TokenRefreshState: Equatable {
		case idle
		/// Scheduled a normal token refresh when it's about to expire.
		case scheduled
		/// Scheduled token refresh after a transient error.
		case scheduledAfterError
		/// Making a token refresh now.
		case busy
	}

	private var tokenRefreshState: TokenRefreshState = .idle
	private var refreshTimer: Timer?
	private var lastRetryTimeout: TimeInterval = 0

	/// Nudges the client to begin refreshing tokens now in case it is waiting between transient token refresh errors.
	/// Safe to call regardless of the current state.
	///
	/// When the client is authorized and the credentials have (almost) expired
	/// (`case state = .authorized(_, refreshing: true)`), then it is going to start refreshing them (if possible),
	/// retrying in case of transient errors (e.g. no network). However the timeout between unsuccessful retries is
	/// going to grow and it might become relatively large for the user code to simply wait for the client to refresh it.
	/// The user code can also have some extra information suggesting that it might make sense to retry earlier.
	/// For example, when the user manually triggers to refresh something, then there is a possibility that the
	/// connection problems are fixed and the new retry might succeed. This is a call for such a situation.
	public func nudgeToRefresh() {

		guard case .authorized(_, refreshing: true) = state else {
			// Not authorized or don't need to refresh.
			// As per contract, should be safe to call this anytime.
			return
		}

		switch tokenRefreshState {
		case .idle, .scheduled:
			assertionFailure("Expected to be busy or waiting after a transient failure")
			break
		case .scheduledAfterError:
			// Waiting for a back off timeout now. Rescheduling with the minimal timeout keeping "after error" state.
			// Too many nudges can have the effect of postponing the refresh (by constantly resetting the timer).
			lastRetryTimeout = 0
			scheduleToRetryTokenRefresh()
		case .busy:
			// It's being refreshed now, nothing to do except resetting the back-off timeout for the next retry, if any.
			lastRetryTimeout = 0
		}
	}

	private func scheduleRegularTokenRefresh(_ timeout: TimeInterval) {
		tokenRefreshState = .scheduled
		_scheduleTokenRefresh(timeout)
	}

	private func scheduleToRetryTokenRefresh() {

		tokenRefreshState = .scheduledAfterError

		var newTimeout = Double.random(in: 0...lastRetryTimeout) + lastRetryTimeout * refreshBackOffPolicy.multiplier
		newTimeout = max(refreshBackOffPolicy.min, min(newTimeout, refreshBackOffPolicy.max))

		lastRetryTimeout = newTimeout

		// This looks like an unneccessery round trip, but allows to override the scale of these timeouts as well.
		newTimeout = timeSource.timeIntervalFromNowToDate(timeSource.now().addingTimeInterval(newTimeout))

		_scheduleTokenRefresh(newTimeout)
	}

	private func _scheduleTokenRefresh(_ timeout: TimeInterval) {

		switch tokenRefreshState {
		case .scheduled, .scheduledAfterError:
			// OK, double internal function, state set outside.
			break
		case .idle, .busy:
			assertionFailure()
			return
		}

		let t = max(timeout, 0)

		MMMLogTrace(self, "Going to try refreshing the token(s) in \(String(format: "%.1fs", t))")

		refreshTimer?.invalidate()
		refreshTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
			self?.startRefreshingTokens()
		}
	}

	private func cancelTokenRefresh() {

		tokenRefreshState = .idle
		lastRetryTimeout = 0

		refreshTimer?.invalidate()
		refreshTimer = nil

		if tokenRefreshState == .busy {
			MMMLogTrace(self, "Cancelling the pending token refresh")
			tokenRequestCookie += 1
			// Changing the request cookie would cancel the initial token fetch as well, but these are not used together.
			assert(state != .fetchingToken)
		}
	}

	private func startRefreshingTokens() {

		guard case .authorized(let credentials, _) = state else {
			assertionFailure("Should not start refreshing token(s) when not in authorized state")
			return
		}

		guard let config = flowState?.config else { preconditionFailure() }

		guard let refreshToken = credentials.refreshToken, let tokenEndpoint = config.tokenEndpoint else {
			setFailed("Token(s) expired and cannot be refreshed (no refresh token available or token endpoint configured)")
			return
		}

		MMMLogTrace(self, "Refreshing token(s)...")

		// TODO: use a background task to improve our chances in case the server invalidates this refresh token but the app is killed before receiving the new one

		self.tokenRefreshState = .busy
		self.state = .authorized(credentials, refreshing: true)

		// See [https://tools.ietf.org/html/rfc6749#section-6].
		self.performTokenRequest(
			url: tokenEndpoint,
			params: [
				// This time we are exchaning our refresh token.
				"grant_type": "refresh_token",
				// ...and here it goes.
				"refresh_token": refreshToken
				// No scope needed, as we don't want to change it.
				// No client identifier either, the token should be bound to the client.
			]
		) { [weak self] (result) in
			self?.didFinishRefreshingTokens(result)
		}
	}

	private func didFinishRefreshingTokens(_ result: Result<[String: Any], NSError>) {

		guard tokenRefreshState == .busy else {
			assertionFailure("The callback of the token refresh call is expected to be cancelled along with the process")
			return
		}

		guard case .authorized(let prevCredentials, _) = state else {
			assertionFailure("Forgot to cancel token refresh while leaving .authorized state?")
			return
		}

		guard case .authorized(_, refreshing: true) = self.state else {
			assertionFailure("We keep the `refreshig` flag up till the refresh completes successfully")
			return
		}

		guard let flowState = flowState else { preconditionFailure() }

		switch result {

		case .failure(let error):

			// Note that a proper JSON-encoded error is expected in case of a "permanent failure" (handled below).
			// Any other failures thus are treated as temporary ones. This would include network errors as well as
			// internal server errors and the likes.
			//
			// It should not hurt if we persist trying to refresh the token in these cases. This won't cause any dead
			// end situations:
			// - if the user code is waiting on a token from us, then it eventually gets a timeout;
			// - in case the end-user cannot access their protected resources for too lon, then the can re-authorize
			//   or sign in/out again.
			MMMLogError(self, "Could not refresh token(s) but will retry later: \(error.mmm_description)")

			scheduleToRetryTokenRefresh()

		case .success(let response):

			if let error = errorFromParams(response) {
				// A proper JSON-encoded error should mean a "permanent failure" because there are no error codes
				// implying that the same request might be successful later.
				// See [https://tools.ietf.org/html/rfc6749#section-5.2]().
				//
				// We should sign out as soon as any of the tokens actually expires, which is not necessarily now
				// as we might be performing an "eager" refresh. However given that "eager" refreshes are performed
				// close to the actual expiration it might be simpler to sign out right now.
				setFailed("An attempt to refresh token(s) has failed permanently, dropping credentials", underlyingError: error)
				do {
					try storage.deleteCredentialsForClientIdentifier(flowState.config.clientIdentifier)
				} catch {
					MMMLogError(self, "Could not delete the corresponding credentials: \(error.mmm_description)")
				}
				return
			}

			var credentials: Credentials
			do {
				credentials = try grabTokensFromResponse(response, source: .tokenEndpoint)
			} catch {
				// Having something funky in the response is like a "permanent error",
				// there is no hope something better is going to be returned if we retry.
				setFailed("Got invalid response while refreshing the token", underlyingError: error as NSError)
				return
			}

			// If the response is missing a new refresh token, which is allowed by the spec, then we assume that we can
			// continue using the old one. This assumption is not explicit in the spec though,
			// see https://tools.ietf.org/html/rfc6749#section-6]().
			// The next refresh is not even possible without the refresh token however; and if we keep the old refresh
			// token, then it'll just fail to refresh in the worst case. So nothing to lose.
			if credentials.refreshToken == nil {
				credentials.refreshToken = prevCredentials.refreshToken
			}

			// TODO: can check the issuer and subject of the ID Token, if any, are the same as before.

			setAuthorized(credentials)
		}
	}

	// MARK: - Token Endpoint

	private var tokenRequestCookie: Int = 0

	private func performTokenRequest(
		url: URL,
		params: [String: String],
		completion: @escaping (Result<[String: Any], NSError>) -> Void
	) {
		// Let's make sure we care only about the most recent callback, i.e. older callbacks won't cause any trouble.
		// TODO: maybe just request the provider to return something to cancel the request/callback
		tokenRequestCookie += 1
		networking.performTokenRequest(
			requestForTokenEndpoint(url: url, params: params)
		) { [weak self, cookie = tokenRequestCookie] (result) in
			guard cookie == self?.tokenRequestCookie else {
				// Got a callback for the request we don't care about or maybe self is gone.
				return
			}
			completion(result)
		}
	}

	private func requestForTokenEndpoint(url: URL, params: [String: String]) -> URLRequest {

		var request = URLRequest(url: url)

		request.httpMethod = "POST"

		guard let config = self.flowState?.config else {
			preconditionFailure()
		}

		// Passing client credentials via Basic auth headers, see [https://tools.ietf.org/html/rfc6749#section-2.3.1]().
		// Note that we could include them into the body, but this is not necesserily supported by the server
		// nor is recommended to use. The headers option must be supported by any server however.
		if let clientSecret = config.clientSecret {

			let header: String = {

				// For Basic authentication we get username and password separated by a colon and encode them to Base64,
				// see [https://tools.ietf.org/html/rfc2617#section-2]().
				let usernamePassword = "\(config.clientIdentifier):\(clientSecret)"
				guard let usernamePasswordData = usernamePassword.data(using: .utf8) else {
					// Everything is encodable as utf-8, we can get here only if there is no memory.
					preconditionFailure()
				}

				return "Basic \(usernamePasswordData.base64EncodedString())"
			}()

			request.setValue(header, forHTTPHeaderField: "Authorization")
		}

		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

		request.httpBody = {
			// Let's use URLComponents' ability to encode query strings.
			var c = URLComponents()
			c.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
			guard let encoded = (c.query ?? "").data(using: .utf8) else {
				// The query is escaped, so there should not be any problems encoding it to UTF8
				// (unless there is no memory, something we can ignore).
				preconditionFailure()
			}
			return encoded
		}()

		return request
	}
}

extension MMMothClient {

	/// Optional OpenID-specific parameters for the authorization endpoint.
	/// See [https://openid.net/specs/openid-connect-core-1_0.html#AuthRequest]().
	public struct OpenIDSettings {

		/// How authorization page should be presented.
		public var display: Display = .touch

		public enum Display: String {
			/// Full page view. Assumed to be default by the server when no settings are provided.
			case page = "page"
			/// A popup window.
			case popup = "popup"
			/// "UI consistent with a device that leverages a touch interface".
			case touch = "touch"
		}

		public var prompt: Set<Prompt> = [ .login ]

		public enum Prompt: String {

			/// No authentication or consent pages should be displayed.
			/// The error is returned if the user is not authenticated already.
			case none = "none"

			/// The server should prompt for authentication even if the user is authenticated already.
			case login = "login"

			/// The server should ask for consent.
			case consent = "consent"

			/// The server should ask the end-user to select their account.
			case selectAccount = "select_account"
		}
	}
}

extension MMMothClient {

	/// What kind of thing we would like to get via a redirect URL when the authorization is successful,
	/// i.e. possible values of authorization endpoint's "response_type" parameter.
	///
	/// Note that we only support the values listed here as other flows are either not used in a mobile app
	/// ("password" or "client_credentials") or are unknown (extensions).
	public enum ResponseType: String, Codable {

		/// "Authorization Code" flow, see [https://tools.ietf.org/html/rfc6749#section-4.1]()
		///
		/// This means that we want to receive "authorization code", which has to be exchanged to an access token
		/// via the token endpoint.
		///
		/// Note that this flow "is not optimized" for native apps that are "public clients" in OAuth terms.
		/// Still let's support this as it might be the only option for the target server.
		case code = "code"

		/// "Implicit" flow, see [https://tools.ietf.org/html/rfc6749#section-4.2]().
		///
		/// The access token is returned right away via the redirect URL.
		/// Note that refresh token is never returned in this flow.
		case token = "token"

		/// OpenID extension. This is similar to `.token` but an ID Token is returned as well.
		/// See [https://openid.net/specs/openid-connect-core-1_0.html#ImplicitAuthRequest]().
		case idToken = "id_token"
	}
}

// MARK: -

/// Something providing `MMMothClient` with the current time and its scale. Handy for testing.
public protocol MMMothClientTimeSource: AnyObject {

	/// Time in seconds that the access token expires in is added to this date when figuring out
	/// the absolute expiration date. Can be used in unit tests to freeze the time.
	func now() -> Date

	/// Time in seconds from now till the given date, positive if the date is in the future.
	///
	/// Used to figure out when the client should wake up and refresh the tokens.
	/// The client does not assume that the result is the same as `date.timeIntervalSince(now())`,
	/// so this is where the implementation can speed things up for testing.
	func timeIntervalFromNowToDate(_ date: Date) -> TimeInterval
}

/// Allows to override how `MMMothClient` makes network calls. Used mainly for testing.
public protocol MMMothClientNetworking: AnyObject {

	/// Should perform/simulate the given request.
	///
	/// Note that the completion has to be called on the main queue.
	///
	/// If overriding for non-testing purposes:
	/// - the response has to be decoded as a JSON document;
	/// - it has to be decoded in case of both 200 and 400 status codes,
	///   because the token endpoint uses 400 with error responses;
	/// - other status codes can be converted into an error.
	func performTokenRequest(_ request: URLRequest, completion: @escaping CompletionCallback)

	typealias CompletionCallback = (Result<[String: Any], NSError>) -> Void
}

/// Something that can locally store credentials obtained by `MMMothClient`.
/// Allows to customize where and how they are stored, e.g. user defaults or keychain.
///
/// Assuming for simplicity that there is only one set of credentials per client identifier.
/// This is a fair assumption to hold in a native app:
/// 1. Client identifiers for different authorization servers are usually different.
/// 2. Native apps usually work with a single set of scopes and response types.
///
/// Event if one bumps into the limitation of this assumption, then it should not be hard to
/// implement a custom store providing it with extra keys to separate the credentials.
public protocol MMMothClientStorage: AnyObject {
	func credentialsForClientIdentifier(_ clientIdentifier: String) -> Data?
	func saveCredentials(_ credentials: Data, clientIdentifier: String) throws
	func deleteCredentialsForClientIdentifier(_ clientIdentifier: String) throws
}
