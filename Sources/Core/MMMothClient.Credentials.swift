//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import Foundation

extension MMMothClient {

	/// Access and/or ID tokens along with the scopes and response types they were obtained for.
	///
	/// `Equatable` for unit tests only, `Codable` for storage.
	public struct Credentials: Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible {

		internal var scope: Set<String>
		internal var responseType: Set<ResponseType>

		public var accessToken: String?
		public var expiresAt: Date? // TODO: rename to accessTokenExpiresAt or combine them into a struct similar to idToken

		internal var refreshToken: String?

		public var idToken: MMMothIDToken?

		internal func earliestExpirationDate() -> Date? {
			return [expiresAt, idToken?.expiresAt].compactMap{ $0 }.min()
		}

		public init(
			scope: Set<String>,
			responseType: Set<ResponseType>,
			accessToken: String?,
			expiresAt: Date?,
			refreshToken: String?,
			idToken: MMMothIDToken?
		) {
			self.scope = scope
			self.responseType = responseType
			self.accessToken = accessToken
			self.expiresAt = expiresAt
			self.refreshToken = refreshToken
			self.idToken = idToken
		}

		public var description: String {
			"""
			\(type(of: self))(\
			scope: '\(scope.sorted().joined(separator: " "))', \
			responseType: '\(responseType.map { $0.rawValue }.sorted().joined(separator: " "))', \
			accessToken: \(accessToken.map { "'\($0.prefix(4))...'" } ?? "none"), \
			expiresAt: \(expiresAt.map { "\($0)" } ?? "unknown"), \
			idToken: \(idToken.map { "\($0)" } ?? "none"), \
			refreshToken: \(refreshToken.map { "'\($0.prefix(4))...'" } ?? "none"))
			"""
		}

		public var debugDescription: String { description }
	}
}
