//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import MMMCommonCore
import MMMLog
import MMMObservables
import MMMocking

/// To test AuthWebViewController without any actual provider.
///
/// 1. It spends some time in the "preparing" state sometimes skipping it.
/// 2. Then pretends that it got an endpoint (an inline page) with a link to a redirect URL.
///    Tapping the link should cause the webview to intercept it and notify the view model via `handleRedirect()`.
/// 3. The latter is going to jump to a "finalizing" state spending some time there (possibily skipping it)
///    and then jumping to "completed".
/// And of course it can randomly fail at any step.
public class MockAuthWebViewViewModel: AuthWebViewViewModel {

	private static let random = MMMPseudoRandomSequence(seed: 123)
	private let stateTimeout: TimeInterval = 1
	private let stateSkipChance: Double = 0.5
	private let failureChance: Double = 0.5

	public init() {
		self.state = .preparing
		rescheduleStateChange() { [weak self] _ in
			self?.enterGotEndpoint()
		}
	}

	deinit {
    	cancelTimer()
	}

	public internal(set) var state: AuthWebViewViewModelState {
		didSet {
			MMMLogTrace(self, "State: \(state)")
			_didChange.trigger()
		}
	}

	internal var _didChange = SimpleEvent()
	public var didChange: SimpleEvent { _didChange }

	// MARK: -

	private func enterGotEndpoint() {

		let page = """
			<html>
			<head><meta name="viewport" content="width=device-width"></head>
			<body>
				<h2>Mock OAuth/OpenID Authorization</h2>
				<p><a href="\(redirectURL.absoluteString)/test">Click here</a> to simulate a jump to a redirect URL.</p>
			</body>
			</html>
			"""

		// Static text, thus exclamation marks.
		let pageEncoded = page.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
		let url = URL(string: "data:text/html," + pageEncoded)!

		self.state = .gotEndpoint(URLRequest(url: url))
	}

	public internal(set) var redirectURL = URL(string: "mock-auth://")!

	public func handleRedirect(request: URLRequest) {
		MMMLogTrace(self, "Redirected")
		rescheduleStateChange { [weak self] (skip) in
			if !skip {
				self?.state = .finalizing
			}
			self?.enterCompleted()
		}
	}

	public func handleFailureToOpenEndpoint(error: NSError) {
		MMMLogError(self, "Could not open the endpoint: \(error.mmm_description)")
		if case .gotEndpoint = state {
			state = .failed
		} else {
			MMMLogTrace(self, "Ignoring the failure to open the endpoint while in \(state) state")
		}
	}

	private func enterCompleted() {
		rescheduleStateChange { [weak self] _ in
			self?.state = .completedSuccessfully
		}
	}

	public func cancel() {
		cancelTimer()
		self.state = .cancelled
	}

	public private(set) var ignoreNavigationErrors: Bool = false

	private var timer: Timer?

	private func rescheduleStateChange(_ block: @escaping (_ skip: Bool) -> Void) {

		cancelTimer()

		if Self.random.nextDouble() < stateSkipChance {
			block(true)
		} else {
			timer = Timer.scheduledTimer(withTimeInterval: stateTimeout, repeats: false) { _ in
				if Self.random.nextDouble() < self.failureChance {
					self.state = .failed
				} else {
					block(false)
				}
			}
		}
	}

	private func cancelTimer() {
		timer?.invalidate()
		timer = nil
	}
}
