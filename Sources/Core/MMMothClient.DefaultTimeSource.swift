//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import Foundation

extension MMMothClient {

	/// Default implementation of `MMMothClientTimeSource` that can also be used to scale expiration time intervals
	/// seen by `MMMothClient`, something that can be handy for testing.
	public final class DefaultTimeSource: MMMothClientTimeSource {

		private let scale: Double

		/// - Parameter scale: Time intervals returned by timeIntervalFromNowToDate() will be scaled by this,
		/// so, for example, you can use 0.01 to speed up token refreshes 100x times.
		public init(scale: Double = 1) {
			self.scale = scale
		}

		public func now() -> Date {
			return Date()
		}

		public func timeIntervalFromNowToDate(_ date: Date) -> TimeInterval {
			return date.timeIntervalSinceNow * scale
		}
	}
}
