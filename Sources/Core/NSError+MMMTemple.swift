//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import Foundation

// To not depend on MMMTemple for NSError conveniences.
extension NSError {

	internal convenience init<T>(domain: T, message: String, code: Int = -1, underlyingError: NSError? = nil) {
		var userInfo = [String: Any]()
		userInfo[NSLocalizedDescriptionKey] = message
		if let underlyingError = underlyingError {
			userInfo[NSUnderlyingErrorKey] = underlyingError
		}
		self.init(domain: String(describing: type(of: domain)), code: code, userInfo: userInfo)
	}

	internal func mmm_description() -> String {
		var result = ""
		var error: NSError? = self
		while let e = error {
			if !result.isEmpty {
				result.append(" > ")
			}
			// Treating the -1 error code as "other" kind of error, where only the message matters for diagnostics.
			result.append("\(e.localizedDescription) (\(e.domain)\(e.code != -1 ? "#\(e.code)" : ""))")
			error = e.userInfo[NSUnderlyingErrorKey] as? NSError
		}
		return result
	}
}

internal class MMMError: NSError {
	override var description: String { mmm_description() }
	override var debugDescription: String { mmm_description() }
}
