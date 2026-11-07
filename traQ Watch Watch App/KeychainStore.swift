//
//  KeychainStore.swift
//  traQ Watch Watch App
//
//  Created by 青りんご on 2026/11/07.
//

import Foundation
import Security

struct SavedSession: Codable {
    let server: String
    let token: String
}

enum KeychainStore {
    private static let service = "traQWatch.session"
    private static let account = "current"

    static func save(_ session: SavedSession) throws {
        let data = try JSONEncoder().encode(session)

        delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status)
            )
        }
    }

    static func load() -> SavedSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(
            SavedSession.self,
            from: data
        )
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
