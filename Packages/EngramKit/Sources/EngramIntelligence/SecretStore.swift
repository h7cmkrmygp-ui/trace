import Foundation
import Security

/// Clés des services en ligne (Gemini, Groq), collées par le propriétaire et rangées dans le **trousseau** de l'iPhone :
/// jamais dans le code, la base, les exports, les journaux ni sur GitHub. Elles ne quittent pas cet appareil
/// (`ThisDeviceOnly` : pas de sauvegarde iCloud ni de transfert vers un autre iPhone).
public enum SecretStore {
    public enum Account: String, Sendable, CaseIterable {
        case gemini = "gemini.apiKey"
        case groq = "groq.apiKey"
    }

    static let service = "io.github.h7cmkrmygpui.engram"

    public static func read(_ account: Account) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public static func hasKey(_ account: Account) -> Bool { read(account) != nil }

    /// Enregistre (ou remplace) la clé. Une valeur vide l'efface.
    @discardableResult
    public static func save(_ value: String, for account: Account) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        delete(account)
        guard !trimmed.isEmpty else { return true }
        var query = baseQuery(account)
        query[kSecValueData as String] = Data(trimmed.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public static func delete(_ account: Account) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: Account) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account.rawValue]
    }
}
