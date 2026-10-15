import CommonCrypto
import CryptoKit
import Foundation

/// Fichier de sauvegarde d'Engram (`.engrambackup`), chiffré avec le mot de passe du propriétaire.
///
/// En-tête : « ENGRAMB1 », sel (16 octets), nombre de tours (UInt32). Puis des blocs : longueur (UInt32) et contenu
/// scellé par AES-GCM (nonce, texte chiffré, étiquette). Chaque bloc est lié à son rang, et le dernier est marqué :
/// un bloc retiré, déplacé ou modifié, ou un fichier coupé, est refusé. En clair, une suite d'entrées : longueur du
/// chemin (UInt16), chemin, taille (UInt64), contenu ; un chemin vide termine la sauvegarde.
public enum BackupArchive {
    public enum Failure: Error, Equatable {
        case notABackup, wrongPasswordOrDamaged, unsafePath
    }

    public static let defaultIterations: UInt32 = 600_000
    public static let fileExtension = "engrambackup"
    static let magic = Data("ENGRAMB1".utf8)
    static let headerSize = 8 + 16 + 4
    static let chunkSize = 1 << 20

    /// Écrit la sauvegarde des fichiers `files` (chemins relatifs à `base`).
    public static func write(files: [String], from base: URL, to archive: URL, password: String,
                             iterations: UInt32 = defaultIterations) throws {
        var generator = SystemRandomNumberGenerator()
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) })
        let key = try deriveKey(password, salt: salt, iterations: iterations)
        try? FileManager.default.removeItem(at: archive)
        guard FileManager.default.createFile(atPath: archive.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: archive)
        defer { try? handle.close() }
        var header = magic
        header.append(salt)
        header.appendBigEndian(iterations)
        try handle.write(contentsOf: header)

        var frames = FrameWriter(handle: handle, key: key)
        for name in files {
            guard isSafe(name) else { throw Failure.unsafePath }
            let url = base.appendingPathComponent(name)
            let size = ((try FileManager.default.attributesOfItem(atPath: url.path))[.size] as? NSNumber)?.uint64Value ?? 0
            let path = Data(name.utf8)
            var entry = Data()
            entry.appendBigEndian(UInt16(path.count))
            entry.append(path)
            entry.appendBigEndian(size)
            try frames.append(entry)
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            var remaining = size
            while remaining > 0, let chunk = try input.read(upToCount: Int(min(UInt64(chunkSize), remaining))), !chunk.isEmpty {
                try frames.append(chunk)
                remaining -= UInt64(chunk.count)
            }
            guard remaining == 0 else { throw CocoaError(.fileReadUnknown) }
        }
        var end = Data()
        end.appendBigEndian(UInt16(0))
        try frames.append(end)
        try frames.finish()
    }

    /// Ouvre une sauvegarde dans `destination` et renvoie les chemins retrouvés. En cas d'échec, rien n'est laissé.
    @discardableResult
    public static func read(_ archive: URL, password: String, into destination: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: headerSize), header.count == headerSize,
              header.prefix(8) == magic else { throw Failure.notABackup }
        let salt = header.subdata(in: 8..<24)
        let iterations: UInt32 = header.subdata(in: 24..<28).bigEndianValue()
        guard iterations > 0, iterations <= 10_000_000 else { throw Failure.notABackup }
        let key = try deriveKey(password, salt: salt, iterations: iterations)

        // Tout est d'abord écrit à part : un fichier faux ou coupé ne laisse rien derrière lui.
        let partial = destination.appendingPathComponent(".partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        do {
            var stream = PlainStream(frames: FrameReader(handle: handle, key: key))
            var names: [String] = []
            while true {
                let length: UInt16 = try stream.take(2).bigEndianValue()
                if length == 0 { break }
                guard let name = String(data: try stream.take(Int(length)), encoding: .utf8), isSafe(name) else {
                    throw Failure.unsafePath
                }
                var remaining: UInt64 = try stream.take(8).bigEndianValue()
                let url = partial.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                let output = try FileHandle(forWritingTo: url)
                defer { try? output.close() }
                while remaining > 0 {
                    let chunk = try stream.take(Int(min(UInt64(chunkSize), remaining)))
                    try output.write(contentsOf: chunk)
                    remaining -= UInt64(chunk.count)
                }
                names.append(name)
            }
            // La fin doit être dans le dernier bloc, et rien ne doit la suivre.
            try stream.requireEnd()
            for name in Set(names.compactMap { $0.split(separator: "/").first.map(String.init) }) {
                let target = destination.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: partial.appendingPathComponent(name), to: target)
            }
            try? FileManager.default.removeItem(at: partial)
            return names
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// Un chemin relatif simple : jamais absolu, jamais « .. » (une sauvegarde ne peut pas écrire ailleurs).
    static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0 == "." || $0.isEmpty }
    }

    static func deriveKey(_ password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let secret = Array(password.utf8)
        guard !secret.isEmpty else { throw Failure.wrongPasswordOrDamaged }
        let saltBytes = Array(salt)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = secret.withUnsafeBufferPointer { secretPointer in
            secretPointer.withMemoryRebound(to: CChar.self) { password in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.baseAddress, password.count,
                                     saltBytes, saltBytes.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                     iterations, &derived, derived.count)
            }
        }
        guard status == Int32(kCCSuccess) else { throw Failure.wrongPasswordOrDamaged }
        return SymmetricKey(data: derived)
    }

    /// Données liées à un bloc : son rang et s'il est le dernier.
    static func blockData(index: UInt64, isLast: Bool) -> Data {
        var data = Data()
        data.appendBigEndian(index)
        data.append(isLast ? 1 : 0)
        return data
    }

    struct FrameWriter {
        let handle: FileHandle
        let key: SymmetricKey
        var buffer = Data()
        var index: UInt64 = 0

        mutating func append(_ data: Data) throws {
            buffer.append(data)
            while buffer.count >= BackupArchive.chunkSize {
                try seal(Data(buffer.prefix(BackupArchive.chunkSize)), isLast: false)
                buffer = Data(buffer.dropFirst(BackupArchive.chunkSize))
            }
        }

        mutating func finish() throws {
            try seal(buffer, isLast: true)
            buffer = Data()
        }

        mutating func seal(_ plain: Data, isLast: Bool) throws {
            let box = try AES.GCM.seal(plain, using: key, authenticating: BackupArchive.blockData(index: index, isLast: isLast))
            guard let combined = box.combined else { throw Failure.wrongPasswordOrDamaged }
            var frame = Data()
            frame.appendBigEndian(UInt32(combined.count))
            frame.append(combined)
            try handle.write(contentsOf: frame)
            index += 1
        }
    }

    struct FrameReader {
        let handle: FileHandle
        let key: SymmetricKey
        var index: UInt64 = 0
        var sawLast = false

        /// Le bloc suivant ouvert ; nil à la fin du fichier.
        mutating func next() throws -> Data? {
            guard let lengthData = try handle.read(upToCount: 4), !lengthData.isEmpty else { return nil }
            guard !sawLast, lengthData.count == 4 else { throw Failure.wrongPasswordOrDamaged }
            let length: UInt32 = lengthData.bigEndianValue()
            guard length >= 28, length <= UInt32(BackupArchive.chunkSize + 64),
                  let combined = try handle.read(upToCount: Int(length)), combined.count == Int(length),
                  let box = try? AES.GCM.SealedBox(combined: combined) else { throw Failure.wrongPasswordOrDamaged }
            for isLast in [false, true] {
                if let plain = try? AES.GCM.open(box, using: key, authenticating: BackupArchive.blockData(index: index, isLast: isLast)) {
                    index += 1
                    sawLast = isLast
                    return plain
                }
            }
            throw Failure.wrongPasswordOrDamaged
        }
    }

    /// Le texte en clair, lu bloc par bloc.
    struct PlainStream {
        var frames: FrameReader
        var pending = Data()

        mutating func take(_ count: Int) throws -> Data {
            while pending.count < count {
                guard let block = try frames.next() else { throw Failure.wrongPasswordOrDamaged }
                pending.append(block)
            }
            let taken = Data(pending.prefix(count))
            pending = Data(pending.dropFirst(count))
            return taken
        }

        mutating func requireEnd() throws {
            guard pending.isEmpty, frames.sawLast, try frames.next() == nil else { throw Failure.wrongPasswordOrDamaged }
        }
    }
}

extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }

    func bigEndianValue<T: FixedWidthInteger>() -> T {
        reduce(T(0)) { ($0 << 8) | T($1) }
    }
}
