//
// MMMoth. Part of MMMTemple.
// Copyright (C) 2020 MediaMonks. All rights reserved.
//

import Foundation
import MMMLog

extension MMMothClient {

	/// NSUserDefaults-backed credentials store for `MMMothClient`.
	public final class UserDefaultsStorage: MMMothClientStorage {

		private let key: String

		public init(key: String) {
			self.key = key
		}

		private static let magicVersion = 1209

		private class Blob: Codable {
			var version: Int = magicVersion
			var store: [String: Data] = [:]
		}

		private var blob: Blob?

		private func load() -> Blob? {

			guard let data = UserDefaults.standard.data(forKey: key) else {
				return nil
			}

			do {
				let blob = try JSONDecoder().decode(Blob.self, from: data)
				if blob.version != Self.magicVersion {
					throw NSError(domain: self, message: "Invalid magic number")
				}
				return blob
			} catch {
				MMMLogError(self, "Ignoring data at '\(key)': \(error.mmm_description)")
				return nil
			}
		}

		private func loadBlobIfNeeded() -> Blob {
			if let blob = self.blob {
				return blob
			} else {
				let blob = load() ?? Blob()
				self.blob = blob
				return blob
			}
		}

		private func save() {
			guard let blob = self.blob else {
				// Nothing to save.
				return
			}
			do {
				let data = try JSONEncoder().encode(blob)
				UserDefaults.standard.set(data, forKey: key)
			} catch {
				MMMLogError(self, "Could not encode data for '\(key)': \(error.mmm_description)")
			}
		}

		// MARK: - MMMothClientStore

		public func credentialsForClientIdentifier(_ clientIdentifier: String) -> Data? {
			let blob = loadBlobIfNeeded()
			return blob.store[clientIdentifier]
		}

		public func saveCredentials(_ credentials: Data, clientIdentifier: String) throws {
			let blob = loadBlobIfNeeded()
			blob.store[clientIdentifier] = credentials
			save()
		}

		public func deleteCredentialsForClientIdentifier(_ clientIdentifier: String) throws {
			let blob = loadBlobIfNeeded()
			blob.store.removeValue(forKey: clientIdentifier)
			save()
		}
	}
}
