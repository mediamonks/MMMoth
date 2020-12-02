//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

@testable import MMMoth
import XCTest

class MMMothClientTestCase: XCTestCase {

	// MARK: - Some helpers first

	// To be able to pass client setup in more than one place and have some defaults.
	private struct ClientSetup {

		// Parts of the config we tend to override.
		var tokenEndpoint: URL? = URL(string: "https://example.com/token")!
		var redirectURL: URL = URL(string: "https://example.com/redirect")!

		// Other parameters of start().
		var mode: MMMothClient.Mode = .interactive
		var responseType: Set<MMMothClient.ResponseType> = [ .code ]
		var scope: Set<String> = []
	}

	private struct ClientContext {

		let setup: ClientSetup
		let client: MMMothClient
		let overrides: TestMMMothClientOverrides

		/// Parameters to the authorization endpoint URL formed by the client.
		let authorizationEndpointParams: [String: String]
	}

	/// Creates a client overriding external dependencies, starts the flow and passes control to the given block.
	///
	/// It's just more convenient to use a closure here instead of returning the context or throwing from early returns.
	private func withStartedClient(
		setup: ClientSetup = .init(),
		overrides: TestMMMothClientOverrides? = nil,
		block: (ClientContext) -> Void
	) {

		// All in one overrides. Can be provided from the outside so the use of the storage can be tested.
		let overrides = overrides ?? TestMMMothClientOverrides()

		let client = MMMothClient(storage: overrides, networking: overrides, timeSource: overrides)

		XCTAssert(client.state == .idle, "The client should not do anything (like checking the storage) before explicitly started")

		client.start(
			// Not all parts of the config are important for the client's logic, so always fixing them for now.
			config: .init(
				authorizationEndpoint: URL(string: "http://example.com/auth?paramToPreserve=true&anotherOneEmpty=")!,
				tokenEndpoint: setup.tokenEndpoint,
				clientIdentifier: "test",
				clientSecret: "secret",
				redirectURL: setup.redirectURL
			),
			mode: setup.mode,
			responseType: setup.responseType,
			scope: setup.scope
		)

		let authorizationEndpointParams: [String: String]

		switch setup.mode {

		case .interactive:

			guard case let .authorizing(url, _) = client.state else {
				XCTFail("In interactive mode the client should start authorization as soon as start() is called")
				return
			}

			authorizationEndpointParams = url.paramsFromQuery()

			// I'm not going to verify that all the parameters are present in the URL as that would be a repetition
			// of quite straightforward code of the client and then would need to be updated when more flows are added.
			// Just a sanitiy check to see that something is still indeed generated.
			XCTAssertTrue(authorizationEndpointParams["response_type"] != nil)

			// I'm more interested in checking how it reacts to external inputs.

			// Query parameters in the endpoint URL are part of the input, they should be preserved, as per the spec.
			XCTAssertEqual(authorizationEndpointParams["paramToPreserve"], "true")
			XCTAssertEqual(authorizationEndpointParams["anotherOneEmpty"], "")

		case .silent:

			// No authorizaton endpoint URL in the silent mode.
			authorizationEndpointParams = [:]

			XCTAssert(
				!overrides.storage.isEmpty || client.state == .cancelled,
				"Expected to be cancelled when started in silent mode with empty storage"
			)
		}

		// Let's try different flows from here.
		block(.init(
			setup: setup,
			client: client,
			overrides: overrides,
			authorizationEndpointParams: authorizationEndpointParams
		))
	}

	/// Prepares a client started in "interactive" mode that already:
	/// - handled a redirect,
	/// - got an authorization code,
	/// - sent a request to the token endpoint but have not got a response yet, so you can step in.
	private func withTokenFetchingClient(
		setup: ClientSetup = .init(),
		block: (_ context: ClientContext, _ tokenEndpointParams: [String: String]) -> Void
	) {
		// It's OK to tweak the setup, but it should not exclude the authorization code flow.
		assert(setup.mode == .interactive || setup.responseType.contains(.code))

		withStartedClient(setup: setup) {

			$0.client.handleAuthorizationRedirect(
				url: $0.setup.redirectURL.addingParamsToQuery([
					"state": $0.authorizationEndpointParams["state"]!,
					"code": "code:12345"
				])
			)

			guard case .fetchingToken = $0.client.state else {
				XCTFail("Expected the client to start exchanging the authorization code to a token")
				return
			}

			guard let tokenEndpointParams = $0.overrides.lastRequestParams() else {
				XCTFail("Expected the client to perform a request with some URL-encoded parameters")
				return
			}

			block($0, tokenEndpointParams)
		}
	}

	// MARK: -

	// 100% happy Authorization Code flow.
	public func testHappyAuthCodeFlow() {

		var response: [String: Any] = [
			"access_token": "token:12345",
			"token_type": "bearer",
		]
		// Trying different expiration times along the way as there is a piece of non-static code to double-check.
		response["expires_in"] = [nil, 30, "30"].randomElement()!

		var prevCredentials: MMMothClient.Credentials!
		var overrides: TestMMMothClientOverrides!

		withTokenFetchingClient(
			setup: .init(mode: .interactive)
		) { (context, params) in

			context.overrides.lastCompletion!(.success(response))

			guard case .authorized(let credentials, _) = context.client.state else {
				XCTFail("Should be able to fetch correct credentials at this point")
				return
			}

			XCTAssertEqual(
				credentials,
				.init(
					scope: [],
					responseType: [ .code ],
					accessToken: "token:12345",
					expiresAt: response["expires_in"].map { _ in context.overrides.now().addingTimeInterval(30) },
					refreshToken: nil,
					idToken: nil
				)
			)

			// Let's grab credentials and the state of the storage for the test below.
			prevCredentials = credentials
			overrides = context.overrides
		}

		// Let's confirm that the last used credentials can be restored as well.
		withStartedClient(
			setup: .init(mode: .silent),
			overrides: overrides
		) { (context) in
			guard case .authorized(let credentials, _) = context.client.state else {
				XCTFail("Should be able to fetch correct credentials at this point")
				return
			}
			XCTAssertEqual(credentials, prevCredentials)
		}
	}

	public func testHappyImplicitFlows() {

		checkHappyImplicitFlow(
			responseType: [ .token ],
			params: [
				"access_token": "token:12345",
				"refresh_token": "[Should ignore this one]",
				// Let's check if it grabs the non-default scope along the way.
				"scope": "something else from asked"
			],
			expectedCredentials: .init(
				scope: [ "something", "asked", "from", "else" ],
				responseType: [ .token ],
				accessToken: "token:12345",
				expiresAt: nil,
				refreshToken: nil,
				idToken: nil
			)
		)

		// This token is already expired, but it should be OK in the tests below as expiration is not checked in implicit flow.
		// TODO: hmm, should not we check expiration ourselves at least some time later?
		let idToken = try! MMMothIDToken(string: "eyJhbGciOiJSUzI1NiIsImtpZCI6IjA4MWJjODhmOWVmNjNhNGUyMjU2ZmJkNWQyMzYzZmRmIn0.eyJpc3MiOiJodHRwczovL2FwcG9ic3Rvay5vdnBvYnMudHYvYXBpL2lkZW50aXR5Iiwic3ViIjoiODc1ODIzMzEtY2E3Yy00OWVmLTkwZjctNWJmMzQ4YTFkYTQ4IiwiYXVkIjoiMjczMTk3IiwiZXhwIjoxNTkzMTA5MTk2LCJpYXQiOjE1OTMxMDg1OTYsImF1dGhfdGltZSI6MTU5MzEwODU5NSwiYXRfaGFzaCI6IjR4NDE3VlVvV1kta2s5bzA0bHZpZ3cifQ")
		checkHappyImplicitFlow(
			responseType: [ .idToken ],
			params: [
				"access_token": "[Should not touch this either]",
				"id_token": idToken.value,
			],
			expectedCredentials: .init(
				scope: [],
				responseType: [ .idToken ],
				accessToken: nil,
				expiresAt: nil,
				refreshToken: nil,
				idToken: idToken
			)
		)

		checkHappyImplicitFlow(
			responseType: [ .idToken, .token ],
			params: [
				"access_token": "token:12345",
				"id_token": idToken.value
			],
			expectedCredentials: .init(
				scope: [],
				responseType: [ .idToken, .token ],
				accessToken: "token:12345",
				expiresAt: nil,
				refreshToken: nil,
				idToken: idToken
			)
		)
	}

	private func checkHappyImplicitFlow(
		responseType: Set<MMMothClient.ResponseType>,
		params: [String: String],
		expectedCredentials: MMMothClient.Credentials
	) {
		withStartedClient(setup: .init(responseType: responseType)) {

			$0.client.handleAuthorizationRedirect(
				url: $0.setup.redirectURL.addingParamsToFragment([
					"state": $0.authorizationEndpointParams["state"]!,
					"token_type": "bearer"
				].merging(params, uniquingKeysWith: { a, b in a }))
			)

			guard case .authorized(let credentials, _) = $0.client.state else {
				XCTFail("Should have credentials at this point")
				return
			}

			XCTAssertEqual(credentials, expectedCredentials)
		}
	}

	// TODO: test automatic token refreshes here

	public func testAuthorizationErrors() {
		// Not providing state propertly.
		withStartedClient() {
			$0.client.handleAuthorizationRedirect(
				url: $0.setup.redirectURL.addingParamsToQuery([
					"state": "[invalid]",
					"code": "code:12345"
				])
			)
			XCTAssertTrue($0.client.state.isFailed)
		}
		// An error takes over even a good response.
		withStartedClient() {
			$0.client.handleAuthorizationRedirect(
				url: $0.setup.redirectURL.addingParamsToQuery([
					"state": $0.authorizationEndpointParams["state"]!,
					"code": "code:12345",
					"error": "invalid_something"
				])
			)
			XCTAssertTrue($0.client.state.isFailed)
		}
		// Explicit server error.
		withStartedClient() {
			$0.client.handleAuthorizationRedirect(
				url: $0.setup.redirectURL.addingParamsToQuery([
					"state": $0.authorizationEndpointParams["state"]!,
					"error": "invalid_something",
					"error_description": "More info"
				])
			)
			XCTAssertTrue($0.client.state.isFailed)
		}
	}

	public func testTokenFetchErrors() {

		// Providing authorization code but failing token fetch request.
		withTokenFetchingClient { (context, params) in
			context.overrides.lastCompletion!(.failure(MMMError(domain: self, message: "Network problem")))
			XCTAssertTrue(context.client.state.isFailed)
		}

		// The network request per se is successful but describes an error.
		withTokenFetchingClient { (context, params) in
			context.overrides.lastCompletion!(.success([
				"error": "invalid_something",
				"error_description": "More info here"
			]))
			XCTAssertTrue(context.client.state.isFailed)
		}

		// Similar, but with a successful part as well. The error should win.
		// Silly check, but I did not have this handled initially.
		withTokenFetchingClient { (context, params) in
			context.overrides.lastCompletion!(.success([
				"access_token": "token:12345",
				"token_type": "bearer",
				"error": "invalid_something"
			]))
			XCTAssertTrue(context.client.state.isFailed)
		}

		// Providing authorization code but succeeding the fetch with an invalid response.
		withTokenFetchingClient { (context, params) in

			// Successfull but totally empty response.
			context.overrides.lastCompletion!(.success([:]))
			XCTAssertTrue(context.client.state.isFailed)

			// Exta completion calls, even if good, should be safely ignored.
			context.overrides.lastCompletion!(.success([
				"access_token": "token:12345",
				"token_type": "bearer"
			]))
			XCTAssertTrue(context.client.state.isFailed)
		}
		// Similarly.
		withTokenFetchingClient { (context, params) in
			// No "token_type".
			context.overrides.lastCompletion!(.success([
				"access_token": "token:12345",
			]))
			XCTAssertTrue(context.client.state.isFailed)
		}

		// Should reject weird expiration dates.
		withTokenFetchingClient { (context, params) in
			context.overrides.lastCompletion!(.success([
				"access_token": "token:12345",
				"token_type": "bearer",
				"expires_in": -10
			]))
			XCTAssertTrue(context.client.state.isFailed)
		}

		// Should reject responses without ID Token in case of "openid" scope.
		withTokenFetchingClient(
			setup: .init(scope: ["openid"])
		) { (context, params) in
			context.overrides.lastCompletion!(.success([
				"access_token": "token:12345",
				"token_type": "bearer",
				"expires_in": 10
			]))
			XCTAssertTrue(context.client.state.isFailed)
		}
	}
}

// MARK: - Helpers

extension MMMothClient.State {
	var isFailed: Bool {
		if case .failed = self {
			return true
		} else {
			return false
		}
	}
}

private class TestMMMothClientOverrides: MMMothClientNetworking, MMMothClientTimeSource, MMMothClientStorage {

	public init(now: Date = Date(timeIntervalSinceReferenceDate: 0), timeScale: TimeInterval = 1) {
		self._now = now
		self.timeScale = timeScale
	}

	// MARK: - MMMothClientTimeSource

	// These allow to fix the reference time and scale it when needed.
	private let _now: Date
	private let timeScale: TimeInterval

	public func now() -> Date { _now }

	public func timeIntervalFromNowToDate(_ date: Date) -> TimeInterval {
		return date.timeIntervalSince(_now) * timeScale
	}

	// MARK: - MMMothClientNetworking

	public var lastRequest: URLRequest?

	public func lastRequestParams() -> [String: String]? {
		guard let data = lastRequest?.httpBody else {
			return nil
		}
		var components = URLComponents()
		components.query = String(data: data, encoding: .utf8)
		guard let queryItems = components.queryItems else {
			return nil
		}
		return [String: String](
			queryItems.map { ($0.name, $0.value ?? "") },
			uniquingKeysWith: { $1 }
		)
	}

	public var lastCompletion: CompletionCallback?

	func performTokenRequest(
		_ request: URLRequest,
		completion: @escaping CompletionCallback
	) {
		self.lastRequest = request
		self.lastCompletion = completion
	}

	// MARK: - MMMothClientStorage

	public var storage: [String: Data] = [:]

	func credentialsForClientIdentifier(_ clientIdentifier: String) -> Data? {
		return storage[clientIdentifier]
	}

	func saveCredentials(_ credentials: Data, clientIdentifier: String) throws {
		storage[clientIdentifier] = credentials
	}

	func deleteCredentialsForClientIdentifier(_ clientIdentifier: String) throws {
		storage[clientIdentifier] = nil
	}
}

extension URL {

	internal func addingParamsToQuery(_ params: [String: String]) -> URL {
		var components = URLComponents(url: self, resolvingAgainstBaseURL: true)!
		components.queryItems = (components.queryItems ?? []) + params.map { URLQueryItem(name: $0.0, value: $0.1) }
		return components.url!
	}

	internal func addingParamsToFragment(_ params: [String: String]) -> URL {
		var components = URLComponents(url: self, resolvingAgainstBaseURL: true)!
		let prevQuery = components.query
		components.queryItems = (components.queryItems ?? []) + params.map { URLQueryItem(name: $0.0, value: $0.1) }
		components.fragment = components.query
		components.query = prevQuery
		return components.url!
	}

	internal func paramsFromQuery() -> [String: String] {
		let components = URLComponents(url: self, resolvingAgainstBaseURL: true)!
		return [String: String](
			components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
			uniquingKeysWith: { a, _ in a }
		)
	}
}

