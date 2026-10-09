import EngramCore
import EngramIntelligence
import EngramStore
import Foundation

/// Sauvegardes chiffrées d'Engram, dans un dossier choisi par le propriétaire (iCloud Drive conseillé). Le mot de passe
/// reste dans le trousseau de l'iPhone ; la sauvegarde ne peut être ouverte qu'avec lui.
@MainActor
@Observable
final class BackupService {
    enum Failure: LocalizedError {
        case noFolder, noPassword, folderUnavailable

        var errorDescription: String? {
            switch self {
            case .noFolder: "Choisis d'abord le dossier où ranger les sauvegardes."
            case .noPassword: "Choisis d'abord un mot de passe de sauvegarde."
            case .folderUnavailable: "Le dossier de sauvegarde n'est plus accessible : choisis-le de nouveau."
            }
        }
    }

    static let keep = 4
    static let filePrefix = "Engram-Sauvegarde-"
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let folderKey = "engram.backupFolder"
    private static let lastKey = "engram.lastBackup"

    private(set) var lastBackup: Date?
    private(set) var folderName: String?
    private(set) var isWorking = false
    private(set) var hasPassword: Bool

    init() {
        hasPassword = SecretStore.hasKey(.backupPassword)
        lastBackup = defaults.object(forKey: Self.lastKey) as? Date
        folderName = resolveFolder()?.lastPathComponent
    }

    /// Mot de passe d'au moins 8 caractères ; renvoie un message d'erreur, ou nil si tout va bien.
    func setPassword(_ password: String, confirmation: String) -> String? {
        guard password.count >= 8 else { return "Au moins 8 caractères." }
        guard password == confirmation else { return "Les deux mots de passe ne sont pas pareils." }
        guard SecretStore.save(password, for: .backupPassword) else { return "Impossible de le ranger dans le trousseau." }
        hasPassword = true
        return nil
    }

    /// Les sauvegardes déjà faites gardent leur ancien mot de passe.
    func forgetPassword() {
        SecretStore.delete(.backupPassword)
        hasPassword = false
    }

    /// Dossier choisi dans Fichiers : gardé par un signet sécurisé.
    func setFolder(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Self.folderKey)
        folderName = url.lastPathComponent
    }

    private func resolveFolder() -> URL? {
        guard let data = defaults.data(forKey: Self.folderKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Self.folderKey)
        }
        return url
    }

    /// Sauvegarde chaque semaine, à l'ouverture de l'app, si tout est réglé.
    func backupIfDue(model: AppModel) async {
        guard (try? model.settings.bool(.backupWeekly, default: false)) == true, hasPassword, resolveFolder() != nil,
              !isWorking else { return }
        if let lastBackup, Date().timeIntervalSince(lastBackup) < 7 * 86_400 { return }
        _ = try? await backupNow(model: model)
    }

    /// Copie cohérente de la base et des enregistrements, chiffrée, rangée dans le dossier choisi. Renvoie son nom.
    @discardableResult
    func backupNow(model: AppModel) async throws -> String {
        guard let folder = resolveFolder() else { throw Failure.noFolder }
        guard let password = SecretStore.read(.backupPassword) else { throw Failure.noPassword }
        isWorking = true
        defer { isWorking = false }
        let database = model.database
        let storage = model.storageDirectory
        let name = Self.filePrefix + Self.stamp(Date()) + "." + BackupArchive.fileExtension
        try await Task.detached(priority: .utility) {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            try database.backup(to: work.appendingPathComponent(DatabaseRecovery.databaseFileName))
            // Les enregistrements sont lus en place (lien vers le dossier audio), sans copie.
            let audio = storage.appendingPathComponent("audio", isDirectory: true)
            var files = [DatabaseRecovery.databaseFileName]
            if FileManager.default.fileExists(atPath: audio.path) {
                try FileManager.default.createSymbolicLink(at: work.appendingPathComponent("audio"), withDestinationURL: audio)
                let names = (try? FileManager.default.contentsOfDirectory(atPath: audio.path)) ?? []
                files += names.filter { $0.hasSuffix(".caf") }.sorted().map { "audio/\($0)" }
            }
            let archive = work.appendingPathComponent(name)
            try BackupArchive.write(files: files, from: work, to: archive, password: password)
            try Self.place(archive, in: folder, named: name)
        }.value
        lastBackup = Date()
        defaults.set(lastBackup, forKey: Self.lastKey)
        return name
    }

    /// Copie dans le dossier choisi (iCloud Drive compris), puis ne garde que les 4 dernières sauvegardes d'Engram.
    nonisolated static func place(_ archive: URL, in folder: URL, named name: String) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: folder.appendingPathComponent(name), options: .forReplacing,
                                       error: &coordinationError) { target in
            do {
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: archive, to: target)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        let ours = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix(filePrefix) && $0.hasSuffix("." + BackupArchive.fileExtension) }
            .sorted(by: >)
        for old in ours.dropFirst(keep) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(old)) }
    }

    /// Ouvre une sauvegarde avec son mot de passe, la vérifie et la prépare : elle s'appliquera au prochain lancement
    /// (les données actuelles seront mises de côté). Renvoie le nombre de notes qu'elle contient.
    func prepareRestore(from file: URL, password: String, model: AppModel) async throws -> Int {
        isWorking = true
        defer { isWorking = false }
        let storage = model.storageDirectory
        return try await Task.detached(priority: .userInitiated) {
            let accessing = file.startAccessingSecurityScopedResource()
            defer { if accessing { file.stopAccessingSecurityScopedResource() } }
            let work = storage.deletingLastPathComponent().appendingPathComponent("RestoreWork-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            do {
                try BackupArchive.read(file, password: password, into: work)
                let count = try BackupRestore.noteCount(inRestored: work)
                try BackupRestore.stage(work, in: storage)
                return count
            } catch {
                try? FileManager.default.removeItem(at: work)
                throw error
            }
        }.value
    }

    nonisolated static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }
}
