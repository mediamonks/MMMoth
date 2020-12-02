//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import Foundation

extension MMMothClient {

	public struct Config {

		/// An endpoint that will be opened in a browser (in-app or external) so the end-user can authenticate themselves
		/// with the server and authorize the client to access their resources.
		///
		/// The browser is then redirected to the client's URL where the client either gets an access token directly
		/// or gets a code that can be exchanged to an access token via the token endpoint.
		/// The latter is something that makes little sense for a "public client", such as a native app,
		/// but we are trying to support it. See [https://tools.ietf.org/html/rfc6749#section-3.1]().
		public var authorizationEndpoint: URL

		/// An endpoint where a "grant" (a refresh token or an authorization code in our case) can be exchanged
		/// to an access token. This is accessed by the client directly, no browser needed.
		///
		/// Optional because some of the providers support only implicit flow, that is when the token is received directly
		/// from the authorization endpoint. See [https://tools.ietf.org/html/rfc6749#section-3.2]().
		public var tokenEndpoint: URL?

		/// A string identifying the client.
		///
		/// Note that "public clients" don't have to authenticate themselves (by providing the secret),
		/// but their identifier is still used in the flows to avoid using responses designated for other clients.
		/// See [https://tools.ietf.org/html/rfc6749#section-2.3]().
		public var clientIdentifier: String

		/// The secret part of the client's identifier.
		///
		/// Note that it's optional because native apps are considered to be "public clients" and thus it makes no sense
		/// to authenticate them as the secret can be easily extracted. Certain servers still insist on using a secret,
		/// so we still support client authentication when accessing the token endpoint just in case.
		public var clientSecret: String?

		/// The URL the authorization server is going to redirect its response regarding authorization.
		public var redirectURL: URL

		// And now all the fields two times again because members are public, gotta love Swift...

		public init(
			authorizationEndpoint: URL,
			tokenEndpoint: URL?,
			clientIdentifier: String,
			clientSecret: String?,
			redirectURL: URL
		) {
			self.authorizationEndpoint = authorizationEndpoint
			self.tokenEndpoint = tokenEndpoint
			self.clientIdentifier = clientIdentifier
			self.clientSecret = clientSecret
			self.redirectURL = redirectURL
		}
	}
}
