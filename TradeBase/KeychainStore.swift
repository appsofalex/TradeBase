//
//  KeychainStore.swift
//  TradeBase
//
//  Created by Alex Walters on 19/09/2025.
//

import Foundation
import Security

enum KeychainStore {

    /// Where a keychain item should live.
    /// - deviceOnly: Current behavior. Item is not synchronizable and uses a ThisDeviceOnly accessibility class.
    /// - iCloudKeychain: Item is synchronizable via iCloud Keychain and uses a non-ThisDeviceOnly accessibility class.
    /// - any: For reads/removes, target either scope. Writes are not supported with `.any`.
    enum Scope: Equatable {
        case deviceOnly
        case iCloudKeychain
        case any
    }

    // MARK: - Core (Data)

    @discardableResult
    static func set(_ data: Data,
                    for key: String,
                    service: String = Bundle.main.bundleIdentifier ?? "TradeBase",
                    scope: Scope = .deviceOnly) throws -> OSStatus {
        precondition(scope != .any, "Cannot write with scope .any; choose .deviceOnly or .iCloudKeychain")

        // Base query (used for delete and add)
        var baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        // Scope attributes
        switch scope {
        case .deviceOnly:
            baseQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse
        case .iCloudKeychain:
            baseQuery[kSecAttrSynchronizable as String] = kCFBooleanTrue
        case .any:
            break // guarded by precondition
        }

        // Delete any existing item in the same scope to avoid duplicates within that scope
        SecItemDelete(baseQuery as CFDictionary)

        // Add attributes
        var attributes = baseQuery
        attributes[kSecValueData as String] = data

        // Accessibility must not be "ThisDeviceOnly" for items that should sync
        if scope == .iCloudKeychain {
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        } else {
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return status
    }

    static func data(for key: String,
                     service: String = Bundle.main.bundleIdentifier ?? "TradeBase",
                     scope: Scope = .deviceOnly) -> Data? {
        switch scope {
        case .deviceOnly, .iCloudKeychain:
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            query[kSecAttrSynchronizable as String] =
                (scope == .iCloudKeychain) ? kCFBooleanTrue : kCFBooleanFalse

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess else { return nil }
            return item as? Data

        case .any:
            // Prefer iCloud copy if present, then fall back to device-only.
            if let d = data(for: key, service: service, scope: .iCloudKeychain) {
                return d
            }
            return data(for: key, service: service, scope: .deviceOnly)
        }
    }

    static func remove(_ key: String,
                       service: String = Bundle.main.bundleIdentifier ?? "TradeBase",
                       scope: Scope = .deviceOnly) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        switch scope {
        case .deviceOnly:
            query[kSecAttrSynchronizable as String] = kCFBooleanFalse
            SecItemDelete(query as CFDictionary)
        case .iCloudKeychain:
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
            SecItemDelete(query as CFDictionary)
        case .any:
            // Delete both scopes
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            SecItemDelete(query as CFDictionary)
        }
    }

    // MARK: - Migration helpers

    /// Move a keychain item between scopes (e.g., deviceOnly <-> iCloudKeychain).
    /// If the source item doesn't exist, this is a no-op.
    static func migrate(key: String,
                        service: String = Bundle.main.bundleIdentifier ?? "TradeBase",
                        from: Scope,
                        to: Scope) throws {
        precondition(from != .any && to != .any, "Migration requires explicit scopes")
        guard from != to else { return }
        guard let d = data(for: key, service: service, scope: from) else { return }
        try set(d, for: key, service: service, scope: to)
        remove(key, service: service, scope: from)
    }

    // MARK: - Convenience (String)

    @discardableResult
    static func set(_ string: String,
                    for key: String,
                    service: String = Bundle.main.bundleIdentifier ?? "TradeBase",
                    scope: Scope = .deviceOnly) throws -> OSStatus {
        try set(Data(string.utf8), for: key, service: service, scope: scope)
    }

    static func string(for key: String,
                       service: String = Bundle.main.bundleIdentifier ?? "TradeBase",
                       scope: Scope = .deviceOnly) -> String? {
        guard let d = data(for: key, service: service, scope: scope) else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
