//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

@testable import MMMoth
import XCTest

class IDTokenTestCase: XCTestCase {

	func testBasics() {

		guard let token = try? MMMothIDToken(string: "eyJhbGciOiJSUzI1NiIsImtpZCI6IjA4MWJjODhmOWVmNjNhNGUyMjU2ZmJkNWQyMzYzZmRmIn0.eyJpc3MiOiJodHRwczovL2FwcG9ic3Rvay5vdnBvYnMudHYvYXBpL2lkZW50aXR5Iiwic3ViIjoiODc1ODIzMzEtY2E3Yy00OWVmLTkwZjctNWJmMzQ4YTFkYTQ4IiwiYXVkIjoiMjczMTk3IiwiZXhwIjoxNTkzMTA5MTk2LCJpYXQiOjE1OTMxMDg1OTYsImF1dGhfdGltZSI6MTU5MzEwODU5NSwiYXRfaGFzaCI6IjR4NDE3VlVvV1kta2s5bzA0bHZpZ3cifQ")
		else {
			XCTFail()
			return
		}

		XCTAssertEqual(token.issuer, "https://appobstok.ovpobs.tv/api/identity")
		XCTAssertEqual(token.subject, "87582331-ca7c-49ef-90f7-5bf348a1da48")
		XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 1593109196))
	}
}
