//
//  DeviceIdentityManager.swift
//  VisionClaw
//
//  Created by Jessie Hua on 2/27/26.
//

import CryptoKit
import Foundation
import Security

class DeviceIdentityManager {

    private let privateKey: Curve25519.Signing.PrivateKey
    let publicKey: Curve25519.Signing.PublicKey
    let deviceId: String

    init() {
        if let savedKey = Self.loadPrivateKey() {
            self.privateKey = savedKey
        } else {
            self.privateKey = Curve25519.Signing.PrivateKey()
            Self.savePrivateKey(self.privateKey)
        }
        self.publicKey = self.privateKey.publicKey

        // Device ID = hex-encoded SHA256 of the public key (matches OpenClaw reference)
        let hash = SHA256.hash(data: publicKey.rawRepresentation)
        self.deviceId = hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Sign a challenge using the v2 payload format expected by OpenClaw.
    /// Format: "v2|{deviceId}|cli|cli|operator||{timestamp}||{nonce}"
    func signChallenge(nonce: String, timestamp: Int64) -> String {
        let payload = "v2|\(deviceId)|cli|cli|operator||\(timestamp)||\(nonce)"
        let signature = try! privateKey.signature(for: Data(payload.utf8))
        return Self.base64UrlEncode(Data(signature))
    }

    var publicKeyBase64: String {
        return Self.base64UrlEncode(publicKey.rawRepresentation)
    }

    /// base64url encoding (no padding) as required by OpenClaw protocol.
    static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func loadPrivateKey() -> Curve25519.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.visionclaw.openclaw",
            kSecAttrAccount as String: "privatekey",
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    private static func savePrivateKey(_ key: Curve25519.Signing.PrivateKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.visionclaw.openclaw",
            kSecAttrAccount as String: "privatekey"
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = key.rawRepresentation
        SecItemAdd(add as CFDictionary, nil)
    }
}
