//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import Foundation
import MMMCommonUI
import MMMLog
import MMMObservables

/// A basic in-app browser to use with OAuth/OpenID flows.
/// Nothing special here, you can make your own or direct the user to an external browser, for example.
public final class AuthWebViewController: NonStoryboardableViewController, WKNavigationDelegate {

	public struct Style {

		public var backgroundColor: UIColor
		public var completedStateMessage: NSAttributedString
		public var failedStateMessage: NSAttributedString

		public init(
			backgroundColor: UIColor,
			completedStateMessage: NSAttributedString,
			failedStateMessage: NSAttributedString
		) {
			self.backgroundColor = backgroundColor
			self.completedStateMessage = completedStateMessage
			self.failedStateMessage = failedStateMessage
		}
	}

	private let style: Style

	private let viewModel: AuthWebViewViewModel
	private var viewModelToken: SimpleEventToken?
	private let webView: WKWebView?

	/// - Parameter webView: Optional instance of a pre-customized web view.
	///   For example, the caller might use the one displaying shadows when scrolled
	///   or using a tweaked default configuration.
	public init(
		viewModel: AuthWebViewViewModel,
		style: Style,
		webView: WKWebView? = nil
	) {
		self.style = style
		self.webView = webView

		self.viewModel = viewModel
		super.init()

		viewModel.didChange.addObserver(&viewModelToken) { [weak self] _ in
			self?.updateUI(animated: true)
		}
	}

	private weak var _view: AuthWebView?

	public override func loadView() {
		let v = AuthWebView(webView: webView)
		self._view = v
		self.view = v
	}

	override public func viewDidLoad() {

		super.viewDidLoad()

		guard let view = _view else { preconditionFailure() }

		view.webView.navigationDelegate = self

		// Some providers refuse to work in an in-app browser which is a bad move.
		// Let's pretend it's a standalone browser.
		view.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 13_1_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.1 Mobile/15E148 Safari/604.1"

		updateUI(animated: false)
	}

	private lazy var activityStateView: UIView = { AuthWebViewActivityView() }()
	private lazy var failedStateView: UIView = { AuthWebViewMessageStateView(message: style.failedStateMessage) }()
	private lazy var completedStateView: UIView = { AuthWebViewMessageStateView(message: style.completedStateMessage) }()

	private var request: URLRequest?

	private func updateUI(animated: Bool) {

		guard let view = _view else {
			// Can be subscribed before the view is available.
			return
		}

		switch viewModel.state {

		case .preparing:
			view.setStateOverlayView(activityStateView, animated: animated)

		case .gotEndpoint(let r):
			if request != r {
				request = r
				isInitialFrameLoading = true
				view.webView.load(r)
			}
			view.setStateOverlayView(isLoading ? activityStateView : nil, animated: animated)

		case .finalizing:
			view.setStateOverlayView(activityStateView, animated: animated)

		case .cancelled:
			// Keeping the current display state, assuming that the web view is being dismissed now.
			break

		case .failed:
			view.setStateOverlayView(failedStateView, animated: animated)

		case .completedSuccessfully:
			view.setStateOverlayView(completedStateView, animated: animated)
		}
	}

	// MARK: - WKNavigationDelegate

	public func webView(
		_ webView: WKWebView,
		decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
	) {
		let request = navigationAction.request
		#if DEBUG
		MMMLogTrace(self, "Request: \(request)")
		#endif
		if let url = request.url, viewModel.looksLikeRedirectURL(url: url) {
			viewModel.handleRedirect(request: request)
			decisionHandler(.cancel)
		} else {
			decisionHandler(.allow)
		}
	}

	// We track loading of the main frame, so don't need to count how many time loading started, etc, a bool is OK.
	private var isLoading: Bool = false

	// We allow to ignore the errors for loads of pages different from the first one,
	// because the implementation might not be always clean.
	private var isInitialFrameLoading: Bool = false

	private func didStartLoading() {
		isLoading = true
		updateUI(animated: true)
	}

	private func didFinishLoading(error: NSError?) {

		guard isLoading else {
			assertionFailure("Got a double 'did finish' notification? (\(error?.mmm_description ?? "<no error>"))")
			return
		}

		isLoading = false
		if let error = error, case .gotEndpoint = viewModel.state {
			if isInitialFrameLoading || !viewModel.ignoreNavigationErrors {
				viewModel.handleFailureToOpenEndpoint(error: error)
			}
		}

		isInitialFrameLoading = false

		updateUI(animated: true)
	}

	public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		MMMLogTraceMethod(self)
		didStartLoading()
	}

	public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		MMMLogTraceMethod(self)
		MMMLogError(self, "Failed provisional navigation, not reporting this as an error though: \(error.mmm_description)")
		didFinishLoading(error: error as NSError)
	}

	public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		MMMLogTraceMethod(self)
		didFinishLoading(error: nil)
	}

	public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		MMMLogTraceMethod(self)
		didFinishLoading(error: error as NSError)
	}

	public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		MMMLogTraceMethod(self)
		didFinishLoading(error: NSError(domain: Self.self, message: "Web content process has terminated"))
	}
}

/// Default "activity" view. Displayed while we don't have an endpoint or when the flow is being finalized.
internal final class AuthWebViewActivityView: NonStoryboardableView {

	private let activityIndicator = UIActivityIndicatorView(style: .gray)

	public override init() {

		super.init()

		activityIndicator.translatesAutoresizingMaskIntoConstraints = false
		addSubview(activityIndicator)

		mmm_addConstraintsAligningView(activityIndicator, horizontally: .center, vertically: .golden)
	}

	override func didMoveToSuperview() {
		super.didMoveToSuperview()
		activityIndicator.startAnimating()
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		activityIndicator.startAnimating()
	}
}

/// To show a plain label for both failure and success messages.
internal final class AuthWebViewMessageStateView: NonStoryboardableView {

	private let messageLabel = UILabel()

	public init(message: NSAttributedString) {

		super.init()

		messageLabel.translatesAutoresizingMaskIntoConstraints = false
		messageLabel.attributedText = message
		messageLabel.numberOfLines = 0
		addSubview(messageLabel)

		let padding: CGFloat = 16
		mmm_addConstraintsAligningView(
			messageLabel,
			horizontally: .fill, vertically: .golden,
			insets: .init(top: padding, left: padding, bottom: padding, right: padding)
		)
	}
}

internal final class AuthWebView: NonStoryboardableView {

	public let webView: WKWebView

	public init(webView: WKWebView?) {

		self.webView = webView ?? WKWebView()

		super.init()

		// Root view of the controller to be presented in older controllers.
		self.translatesAutoresizingMaskIntoConstraints = true
		self.backgroundColor = .white

		self.webView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(self.webView)
		mmm_addConstraintsAligningView(self.webView, horizontally: .fill, vertically: .fill)

		updateUI()
	}

	private var stateOverlayView: UIView?

	/// Shows the given view as an overlay on top of the web view, this can be an activity indicator, "something went wrong" state, etc.
	public func setStateOverlayView(_ view: UIView?, animated: Bool) {

		guard stateOverlayView != view else {
			// Calling this multiple times for the same view should be convenient.
			return
		}

		stateOverlayView?.removeFromSuperview()
		if let view = view {
			stateOverlayView = view
			addSubview(view)
			self.mmm_addConstraintsAligningView(view, horizontally: .fill, vertically: .fill)
		} else {
			stateOverlayView = nil
		}

		updateUI()

		if animated {
			// A cheap fading is enough here.
			let t = CATransition()
			t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
			t.type = .fade
			t.duration = 0.2
			self.layer.add(t, forKey: kCATransition)
		}
	}

	private func updateUI() {
		webView.isHidden = stateOverlayView != nil
	}
}

// MARK: -

public protocol AuthWebViewViewModel: AnyObject {

	var state: AuthWebViewViewModelState { get }

	var didChange: SimpleEvent { get }

	/// The web view, once it got an endpoint, should be intercepting requests to URLs matching this one
	/// (possibly with different query items) and feeding them via `handleRedirect()`.
	var redirectURL: URL { get }

	/// `true` if the given URL looks like a redirect one. Just a helper for the view, optional for the view model.
	///
	/// Note that comparing prefixes of two URLs can cover many cases, but won't be correct when query parameters are
	/// added before the ones existing in the original redirect URL.
	func looksLikeRedirectURL(url: URL) -> Bool

	/// Called by the web view when it detects a redirect to a URL matching `redirectURL`.
	func handleRedirect(request: URLRequest)

	/// Called by the web view to indicate that it was unable to open the endpoint.
	/// (The error is only for diagnostics.)
	func handleFailureToOpenEndpoint(error: NSError)

	/// If `true`, then navigation errors are reported via `handleFailureToOpenEndpoint` only for the initial
	/// navigation to the authorization endpoint; errors loading any other pages are ignored.
	/// Might be handy for some non-clean implementations.
	var ignoreNavigationErrors: Bool { get }

	/// Called by any party to indicate that the user wants to cancel the flow.
	/// It should be safe to call this regardless of the current state.
	func cancel()
}

extension AuthWebViewViewModel {

	public func looksLikeRedirectURL(url: URL) -> Bool {

		guard let rc = URLComponents(url: self.redirectURL, resolvingAgainstBaseURL: true) else {
			assertionFailure("Should have a valid redirect URL at this point")
			return false
		}

		guard let c = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
			// No assert here, just a URL we cannot crack, ignoring.
			return false
		}

		// All pieces except query and fragment should match.
		return rc.scheme == c.scheme && rc.user == c.user && rc.password == c.password
			&& rc.host == c.host && rc.port == c.port && rc.path == c.path
	}
}

public enum AuthWebViewViewModelState: Equatable {

	/// The authorization endpoint is not known yet, e.g. an OAuth configuration is being fetched
	/// from a backend or an OpenID configuration is being retrieved from the corresponding OpenID provider.
	///
	/// The view should be displaying a generic "activity" state.
	case preparing

	/// The endpoint is known now.
	///
	/// The view should start loading it and monitoring all requests looking for a redirect one.
	case gotEndpoint(URLRequest)

	/// The request to a redirect URL contains a successful response and the flow is being finalized
	/// by fetching an access token, etc.
	///
	/// The view can display another "activity" state here or continue displaying the web view in its previous state.
	case finalizing

	/// The flow has failed at one of the steps.
	///
	/// The view should display a generic error state or dismiss automatically keeping the current state.
	/// In the latter case it is assumed that the result will be clear for the user from other elements of the app.
	case failed

	/// The flow has been completed successfully.
	///
	/// The view should display a "success state" or dismiss automatically keeping the current state.
	/// In the latter case it is assumed that the result will be clear for the user from other elements of the app.
	case completedSuccessfully

	/// The authentication has been cancelled by the user.
	///
	/// The view is expected to be dismissed without changing what was displayed in it.
	case cancelled
}
