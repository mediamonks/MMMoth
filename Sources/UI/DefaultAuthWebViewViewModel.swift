//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import Foundation
import MMMLog
import MMMObservables
import Core

public final class DefaultAuthWebViewViewModel: AuthWebViewViewModel {

	public init(
		client: MMMothClient,
		ignoreNavigationErrors: Bool = false
	) {
		self.ignoreNavigationErrors = ignoreNavigationErrors

		self.client = client
		client.didChange.addObserver(&clientDidChange) { [weak self] _ in
			self?.update()
		}

		update()
	}

	private var client: MMMothClient?
	private var clientDidChange: SimpleEventToken?

	private func update() {

		guard let client = self.client else {
			assertionFailure("We should not be calling \(#function) before the client is set")
			self.state = .preparing
			return
		}

		switch client.state {
		case .idle:
			self.state = .preparing
		case let .authorizing(url, redirectURL):
			self.redirectURL = redirectURL
			self.state = .gotEndpoint(URLRequest(url: url))
		case .fetchingToken:
			self.state = .finalizing
		case .failed:
			self.state = .failed
		case .cancelled:
			self.state = .cancelled
		case .authorized:
			self.state = .completedSuccessfully
		}
	}

	public var state: AuthWebViewViewModelState = .preparing {
		didSet {
			if state != oldValue {
				MMMLogTrace(self, "State: \(state)")
				_didChange.trigger()
			}
		}
	}

	private let _didChange = SimpleEvent()
	public var didChange: SimpleEvent { _didChange }

	public var redirectURL = URL(string: "invalid")!

	public func handleRedirect(request: URLRequest) {

		guard let client = self.client else {
			assertionFailure("Got a \(#function) call without having client")
			return
		}

		guard let url = request.url else {
			assertionFailure()
			return
		}

		guard case .authorizing = client.state else {
			// Could be that the flow has been cancelled while the web view is still working. Ignoring.
			return
		}

		client.handleAuthorizationRedirect(url: url)
	}

	public func handleFailureToOpenEndpoint(error: NSError) {

		guard let client = self.client else {
			assertionFailure("Got a \(#function) call without having client")
			return
		}

		guard case .authorizing = client.state else {
			// Could be that the flow has been cancelled while the web view is still working. Ignoring.
			return
		}

		client.handleAuthorizationFailure(error: error)
	}

	public let ignoreNavigationErrors: Bool

	public func cancel() {
		client?.cancel()
	}
}
