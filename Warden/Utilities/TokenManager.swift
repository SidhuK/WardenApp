

import Foundation
import KeychainAccess
import os

class TokenManager {
    private static let wardenKeychain = Keychain(service: "karatsidhu.WardenAI")
    private static let legacyKeychain = Keychain(service: "notfullin.com.macai")
    private static let tokenPrefix = "api_token_"
    private static let migrationKey = "keychainMigratedToWarden"

    enum TokenError: Error {
        case setFailed
        case getFailed
        case deleteFailed
    }

    // MARK: - Migration

    static func migrateKeychainIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        let legacyKeys = legacyKeychain.allKeys()
        guard !legacyKeys.isEmpty else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        var migratedCount = 0
        for key in legacyKeys {
            do {
                if let value = try legacyKeychain.get(key) {
                    try wardenKeychain.set(value, key: key)
                    try legacyKeychain.remove(key)
                    migratedCount += 1
                }
            } catch {
                WardenLog.app.error("Failed to migrate keychain key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        #if DEBUG
        WardenLog.app.debug("Keychain migration complete: \(migratedCount) keys migrated from macai to Warden")
        #endif

        defaults.set(true, forKey: migrationKey)
    }

    // MARK: - Token Operations

    static func setToken(_ token: String, for service: String, identifier: String? = nil) throws {
        let key = makeKey(for: service, identifier: identifier)
        do {
            try wardenKeychain.set(token, key: key)
        } catch {
            throw TokenError.setFailed
        }
    }

    static func getToken(for service: String, identifier: String? = nil) throws -> String? {
        let key = makeKey(for: service, identifier: identifier)
        do {
            return try wardenKeychain.get(key)
        } catch {
            throw TokenError.getFailed
        }
    }

    static func deleteToken(for service: String, identifier: String? = nil) throws {
        let key = makeKey(for: service, identifier: identifier)
        do {
            try wardenKeychain.remove(key)
        } catch {
            throw TokenError.deleteFailed
        }
    }

    private static func makeKey(for service: String, identifier: String?) -> String {
        if let identifier = identifier {
            return "\(tokenPrefix)\(service)_\(identifier)"
        } else {
            return "\(tokenPrefix)\(service)"
        }
    }
}
