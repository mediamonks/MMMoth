//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

@testable import MMMoth
import MMMLoadable
import XCTest

public class MMMothTestCase: XCTestCase {

	func testOpenIDConfigProvider() {

		let p = MMMothOpenIDDiscoveryConfigProvider(issuerURL: URL(string: "https://accounts.google.com/")!)
		let contentsAvailableExpectation = XCTestExpectation()
		let o = MMMLoadableObserver(loadable: p) { _ in
			if p.isContentsAvailable { contentsAvailableExpectation.fulfill() }
		}
		p.syncIfNeeded()

		wait(for: [contentsAvailableExpectation], timeout: 10)

		guard let config = p.value else {
			XCTFail()
			return
		}

		o?.remove() // Only for the unused var warning.
	}
}
