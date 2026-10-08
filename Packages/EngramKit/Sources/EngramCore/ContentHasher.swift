import CryptoKit
import Foundation

/// Empreintes SHA-256, pour détecter les doublons techniques.
public enum ContentHasher {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Empreinte d'un texte, insensible aux différences d'espaces (mais pas à la casse).
    public static func textHash(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return sha256Hex(Data(collapsed.utf8))
    }
}
