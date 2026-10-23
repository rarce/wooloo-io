import Foundation
import Security
import Crypto
import Citadel

public enum SecretStore {
    private static let service = "dev.wooloo.mobile.ios"
    public static func read(_ account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw WoolooError.message("Keychain read failed (\(status)).") }
        return result as? Data
    }
    public static func write(_ data: Data, account: String) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary
        let attributes = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary
        let status = SecItemUpdate(query, attributes)
        if status == errSecItemNotFound {
            let add = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary
            let added = SecItemAdd(add, nil)
            guard added == errSecSuccess else { throw WoolooError.message("Keychain save failed (\(added)).") }
        } else if status != errSecSuccess { throw WoolooError.message("Keychain save failed (\(status)).") }
    }
    public static func delete(_ account: String) throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw WoolooError.message("Keychain delete failed (\(status)).") }
    }
    public static func deviceKey() throws -> Curve25519.Signing.PrivateKey {
        if let data = try read("device-ed25519") { return try .init(rawRepresentation: data) }
        let key = Curve25519.Signing.PrivateKey()
        try write(key.rawRepresentation, account: "device-ed25519")
        return key
    }
    public static func importKey(_ text: String, passphrase: String) throws {
        let key = try Curve25519.Signing.PrivateKey(sshEd25519: text, decryptionKey: passphrase.isEmpty ? nil : Data(passphrase.utf8))
        try write(key.rawRepresentation, account: "device-ed25519")
    }
    public static func publicKey() throws -> String {
        let key = try deviceKey()
        var data = Data()
        for value in [Data("ssh-ed25519".utf8), key.publicKey.rawRepresentation] {
            var size = UInt32(value.count).bigEndian
            withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
            data.append(value)
        }
        return "ssh-ed25519 \(data.base64EncodedString()) wooloo-mobile-ios"
    }
}
