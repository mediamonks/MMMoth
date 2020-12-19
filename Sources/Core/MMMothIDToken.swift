//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import Foundation

/// Simple parser for [ID Tokens](https://openid.net/specs/openid-connect-core-1_0.html#IDToken ""),
/// which are non-encrypted [JSON Web Tokens](https://tools.ietf.org/html/rfc7519 "").
///
/// In the context of MMMoth library we are only interested in expiration time field, just to know when to refresh
/// the token. We are not concerned with verification, it's something for the backend accepting the tokens.
/// We don't want support for generic JWTs either and thus can require some of the fields avoiding optionals.
public final class MMMothIDToken: Equatable, Codable, CustomStringConvertible {

	/// The raw value of the token.
	public let value: String

	// MARK: - Required Claims

	/// "Issuer Identifier for the Issuer of the response. The iss value is a case sensitive URL using the https
	/// scheme that contains scheme, host, and optionally, port number and path components and no query or
	/// fragment components."
	public let issuer: String

	/// "Subject Identifier. A locally unique and never reassigned identifier within the Issuer for the End-User,
	/// which is intended to be consumed by the Client, e.g., 24400320 or AItOawmwtWwcT0k51BayewNvutrJUqsvl6qs7A4."
	public let subject: String

	/// "Audience(s) that this ID Token is intended for. It MUST contain the OAuth 2.0 client_id of the Relying Party
	/// as an audience value. It MAY also contain identifiers for other audiences. In the general case, the aud value is
	/// an array of case sensitive strings. In the common special case when there is one audience, the aud value MAY be
	/// a single case sensitive string."
	public let audience: [String]

	/// "Expiration time on or after which the ID Token MUST NOT be accepted for processing."
	public let expiresAt: Date

	/// "Time at which the JWT was issued."
	public let issuedAt: Date

	/// "String value used to associate a Client session with an ID Token, and to mitigate replay attacks.
	/// The value is passed through unmodified from the Authentication Request to the ID Token."
	///
	/// Note that this is required depending on the flow it was obtained through.
	public var nonce: String? { payload["nonce"] as? String }

	// MARK: - Some of the Standard Claims

	/// "End-User's full name in displayable form including all name parts, possibly including titles and suffixes,
	/// ordered according to the End-User's locale and preferences."
	public var name: String? { payload["name"] as? String }

	/// "URL of the End-User's profile picture. This URL MUST refer to an image file (for example, a PNG, JPEG,
	/// or GIF image file), rather than to a Web page containing an image."
	public var picture: URL? {
		guard let urlString = payload["picture"] as? String, let url = URL(string: urlString) else {
			return nil
		}
		return url
	}

	/// "End-User's preferred e-mail address. Its value MUST conform to the RFC 5322 [RFC5322] addr-spec syntax.
	/// The RP MUST NOT rely upon this value being unique, as discussed in Section 5.7."
	public var email: String? { payload["email"] as? String }

	/// "Given name(s) or first name(s) of the End-User. Note that in some cultures, people can have multiple
	/// given names; all can be present, with the names being separated by space characters."
	public var givenName: String? { payload["given_name"] as? String }

	/// "Surname(s) or last name(s) of the End-User. Note that in some cultures, people can have multiple
	/// family names or no family name; all can be present, with the names being separated by space characters."
	public var familyName: String? { payload["family_name"] as? String }

	// MARK: -

	/// A raw payload dictionary in case the client needs to read something we have not covered.
	public let payload: [String: Any]

	/// A raw header dictionary, for diagnostics.
	public let header: [String: Any]

	public init(string: String) throws {

		func error(_ message: String) -> NSError {
			NSError(domain: MMMothIDToken.self, message: message)
		}

		let parts = string.split(separator: ".")
		guard parts.count >= 2 else {
			throw error("Expected at least 2 parts")
		}

		func decodedPart(_ s: Substring) throws -> [String: Any] {

			// "Base 64 Encoding with URL and Filename Safe Alphabet" is used here.
			// This is where minus and underline are used instead of a plus and a slash correspondingly
			// and where trailing padding is removed.
			let padded = s
				.replacingOccurrences(of: "-", with: "+")
				.replacingOccurrences(of: "_", with: "/")
			 	+ String(repeating: "=", count: (4 - s.count) & 3)

			guard let data = Data(base64Encoded: padded, options: []) else {
				throw error("Cannot decode a part as base64")
			}

			guard let result = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
				throw error("Cannot decode a part as JSON")
			}

			return result
		}

		self.value = string
		self.header = try decodedPart(parts[0])
		self.payload = try decodedPart(parts[1])

		// The things below are optional in JWTs but are required in ID Tokens.

		if let issuer = payload["iss"] as? String {
			self.issuer = issuer
		} else {
			throw error("Wrong 'iss'")
		}

		if let audience = payload["aud"] as? [String] {
			self.audience = audience
		} else if let audience = payload["aud"] as? String {
			self.audience = [audience]
		} else {
			throw error("Wrong 'aud'")
		}

		if let subject = payload["sub"] as? String {
			self.subject = subject
		} else {
			throw error("Wrong 'sub'")
		}

		if let expirationTime = payload["exp"] as? Double {
			self.expiresAt = Date(timeIntervalSince1970: expirationTime)
		} else {
			throw error("Wrong 'exp'")
		}

		if let issuedAt = payload["iat"] as? Double {
			self.issuedAt = Date(timeIntervalSince1970: issuedAt)
		} else {
			throw error("Wrong 'iat'")
		}

		// The more required claims we are interested in, so can lazily get them when needed.
	}

	// MARK: - Codable

	// This is to be able to store it as a regular token in the credentials store.
	// It encodes/decodes as the raw string. 

	public convenience init(from decoder: Decoder) throws {
		try self.init(string: try decoder.singleValueContainer().decode(String.self))
	}

    public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
    	try container.encode(value)
    }

	// MARK: - CustomStringConvertible

	public var description: String {
		// Very basic info is enough for diagnostics and does not leak the token itself into logs.
		"IDToken(issuer: '\(issuer)', subject: '\(subject)', expiresAt: \(expiresAt))"
	}

	// MARK: - Equatable

	public static func == (lhs: MMMothIDToken, rhs: MMMothIDToken) -> Bool { lhs.value == rhs.value }

	// MARK: -
}
