import Foundation
import Security

public protocol ReaderCredentialStore: Sendable {
    func values(for provider: String) -> [String: String]
    /// Empty `values` removes them.
    func set(_ values: [String: String], for provider: String)
}

/// The Keychain, one item per source; never synced, readable after the first unlock (for a search while the
/// TV or Mac has been asleep).
public struct KeychainReaderCredentials: ReaderCredentialStore {
    let service: String
    public init(service: String = "com.jo32.yingxia.reader-sources") { self.service = service }

    public func values(for provider: String) -> [String: String] {
        var query = base(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess, status != errSecItemNotFound { Diagnostics.shared.record(.warning, "reader", "keychain read failed status=\(status)") }
        guard status == errSecSuccess, let data = result as? Data else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    public func set(_ values: [String: String], for provider: String) {
        SecItemDelete(base(provider) as CFDictionary)
        guard !values.isEmpty, let data = try? JSONEncoder().encode(values) else { return }
        var item = base(provider)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { Diagnostics.shared.record(.warning, "reader", "keychain save failed status=\(status)") }
    }

    private func base(_ provider: String) -> [String: Any] {
        // On the Mac this is the login keychain: the data-protection one needs an entitlement Debug builds lack.
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider]
    }
}

