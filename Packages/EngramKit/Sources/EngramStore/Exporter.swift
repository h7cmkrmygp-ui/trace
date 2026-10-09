import EngramCore
import Foundation
import GRDB

/// Contenu de `engram.json`. Les embeddings (recalculables) et les données internes ne sont pas exportés.
public struct ExportDocument: Codable, Sendable {
    public var formatVersion: Int
    public var app: String
    public var exportedAt: Date
    public var sources: [Source]
    public var memories: [Memory]
    public var memoryVersions: [MemoryVersion]
    public var categories: [EngramCategory]
    public var tags: [EngramTag]
    public var categoryAssignments: [CategoryAssignment]
    public var tagAssignments: [TagAssignment]
    /// Événements du calendrier de l'iPhone créés par Engram (identifiants seulement).
    public var calendarLinks: [CalendarLink]
    /// Personnes et lieux (P9), leurs anciens noms et leurs liens avec les notes.
    public var entities: [EngramEntity]
    public var entityAliases: [EntityAlias]
    public var entityAssignments: [EntityAssignment]
    /// Mesures des suivis (P10).
    public var measurements: [MetricMeasurement]

    enum CodingKeys: String, CodingKey {
        case app, sources, memories, categories, tags, entities, measurements
        case entityAliases = "entity_aliases"
        case entityAssignments = "entity_assignments"
        case formatVersion = "format_version"
        case exportedAt = "exported_at"
        case memoryVersions = "memory_versions"
        case categoryAssignments = "category_assignments"
        case tagAssignments = "tag_assignments"
        case calendarLinks = "calendar_links"
    }
}

public struct ExportResult: Sendable, Equatable {
    public let folderURL: URL
    public let archiveURL: URL
    public let memoryCount: Int
}

/// Export ouvert de toute la mémoire (F89). L'export n'est PAS chiffré.
public struct Exporter: Sendable {
    public let database: AppDatabase
    /// Dossier où se trouvent les fichiers audio (les `audio_path` lui sont relatifs).
    public let audioDirectory: URL?
    public let dates: any DateProvider

    public init(database: AppDatabase, audioDirectory: URL? = nil, dates: any DateProvider = SystemDateProvider()) {
        self.database = database
        self.audioDirectory = audioDirectory
        self.dates = dates
    }

    public func export(into parentDirectory: URL) throws -> ExportResult {
        let exportedAt = dates.now()
        let document = try database.writer.read { db in
            ExportDocument(
                formatVersion: EngramCore.exportFormatVersion,
                app: "Engram",
                exportedAt: exportedAt,
                sources: try Source.order(Column("captured_at")).fetchAll(db),
                memories: try Memory.order(Column("captured_at")).fetchAll(db),
                memoryVersions: try MemoryVersion.order(Column("created_at"), Column("version")).fetchAll(db),
                categories: try EngramCategory.order(Column("name")).fetchAll(db),
                tags: try EngramTag.order(Column("name")).fetchAll(db),
                categoryAssignments: try CategoryAssignment.fetchAll(db),
                tagAssignments: try TagAssignment.fetchAll(db),
                calendarLinks: try CalendarLink.fetchAll(db),
                entities: try EngramEntity.order(Column("kind"), Column("name")).fetchAll(db),
                entityAliases: try EntityAlias.fetchAll(db),
                entityAssignments: try EntityAssignment.fetchAll(db),
                measurements: try MetricMeasurement.order(Column("measured_at")).fetchAll(db))
        }
        let fileManager = FileManager.default
        let folder = parentDirectory.appendingPathComponent("Engram-Export-\(Self.stamp(exportedAt))", isDirectory: true)
        if fileManager.fileExists(atPath: folder.path) { try fileManager.removeItem(at: folder) }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        try Self.writeJSON(document, to: folder.appendingPathComponent("engram.json"))
        try Self.writeMarkdown(document, to: folder.appendingPathComponent("markdown", isDirectory: true))
        try copyAudio(of: document.sources, to: folder.appendingPathComponent("audio", isDirectory: true))
        try Self.readme.write(to: folder.appendingPathComponent("LISEZMOI.txt"), atomically: true, encoding: .utf8)

        let archive = parentDirectory.appendingPathComponent(folder.lastPathComponent + ".zip")
        try Self.zip(folder, to: archive)
        return ExportResult(folderURL: folder, archiveURL: archive, memoryCount: document.memories.count)
    }

    // MARK: - JSON

    static func writeJSON(_ document: ExportDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: url, options: .atomic)
    }

    // MARK: - Markdown

    static func writeMarkdown(_ document: ExportDocument, to root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let categoriesByID = Dictionary(uniqueKeysWithValues: document.categories.map { ($0.id, $0) })
        let tagsByID = Dictionary(uniqueKeysWithValues: document.tags.map { ($0.id, $0) })
        let sourcesByID = Dictionary(uniqueKeysWithValues: document.sources.map { ($0.id, $0) })
        let categoryLinks = Dictionary(grouping: document.categoryAssignments.filter { !$0.rejected }, by: \.memoryID)
        let tagLinks = Dictionary(grouping: document.tagAssignments.filter { !$0.rejected }, by: \.memoryID)

        for memory in document.memories {
            let paths = (categoryLinks[memory.id] ?? [])
                .compactMap { categoriesByID[$0.categoryID] }
                .filter { $0.status == .active }
                .map { CategoryPaths.components(of: $0, in: categoriesByID) }
                .sorted { $0.joined(separator: "/") < $1.joined(separator: "/") }
            let tagNames = (tagLinks[memory.id] ?? []).compactMap { tagsByID[$0.tagID]?.name }.sorted()

            let folderComponents: [String] = switch memory.status {
            case .trashed: ["Corbeille"]
            case .archived: ["Archives"]
            case .unsorted: ["À classer"]
            case .active: paths.first ?? ["À classer"]
            }
            let directory = folderComponents.reduce(root) { $0.appendingPathComponent(safeFileName($1), isDirectory: true) }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let fileName = "\(safeFileName(memory.title))-\(memory.id.uuidString.prefix(8).lowercased()).md"
            let text = markdown(for: memory, categoryPaths: paths.map { $0.joined(separator: " / ") },
                                tags: tagNames, source: sourcesByID[memory.sourceID])
            try text.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        }
    }

    static func markdown(for memory: Memory, categoryPaths: [String], tags: [String], source: Source?) -> String {
        var lines = ["---"]
        lines.append("id: \(yaml(memory.id.uuidString.lowercased()))")
        lines.append("titre: \(yaml(memory.title))")
        lines.append("statut: \(memory.status.rawValue)")
        if let kind = memory.kind { lines.append("type: \(kind.rawValue)") }
        lines.append("categories: [\(categoryPaths.map(yaml).joined(separator: ", "))]")
        lines.append("tags: [\(tags.map(yaml).joined(separator: ", "))]")
        lines.append("capture: \(yaml(memory.capturedAt.formatted(.iso8601)))")
        lines.append("version: \(memory.version)")
        if let source { lines.append("source: \(source.kind.rawValue)") }
        lines.append("---")
        lines.append("")
        lines.append("# \(memory.title)")
        if let summary = memory.summary { lines += ["", "_\(summary)_"] }
        lines += ["", memory.content]
        if memory.excerpt != memory.content {
            lines += ["", "> Extrait de la source : " + memory.excerpt.replacingOccurrences(of: "\n", with: "\n> ")]
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Chaîne YAML entre guillemets (une chaîne JSON est une chaîne YAML valide).
    static func yaml(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Octets maximum pour la partie lisible d'un nom de fichier (le suffixe « -xxxxxxxx.md » s'y ajoute).
    static let maxFileNameBytes = 120

    static func safeFileName(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let replaced = String(String.UnicodeScalarView(raw.unicodeScalars.map { forbidden.contains($0) ? "-" : $0 }))
        let trimmed = replaced.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        // Limite en octets (le système de fichiers refuse les noms de plus de 255 octets), sans couper un caractère.
        var limited = ""
        for character in trimmed {
            guard limited.utf8.count + character.utf8.count <= maxFileNameBytes else { break }
            limited.append(character)
        }
        return limited.isEmpty ? "sans-titre" : limited
    }

    // MARK: - Audio

    func copyAudio(of sources: [Source], to directory: URL) throws {
        guard let audioDirectory else { return }
        let fileManager = FileManager.default
        let paths = sources.compactMap(\.audioPath)
        guard !paths.isEmpty else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for path in paths {
            let from = audioDirectory.appendingPathComponent(path)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            let to = directory.appendingPathComponent(from.lastPathComponent)
            if fileManager.fileExists(atPath: to.path) { try fileManager.removeItem(at: to) }
            try fileManager.copyItem(at: from, to: to)
        }
    }

    // MARK: - ZIP

    /// Compresse un dossier avec le service système (NSFileCoordinator `.forUploading`).
    static func zip(_ folder: URL, to archive: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: archive.path) { try fileManager.removeItem(at: archive) }
        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinationError) { zipped in
            do { try FileManager.default.copyItem(at: zipped, to: archive) } catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    static func stamp(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d%02d%02d-%02d%02d%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    static let readme = """
        Export Engram
        =============

        engram.json  : toute ta mémoire (sources, souvenirs, versions, catégories, tags, liens), format JSON.
        markdown/    : un fichier lisible par souvenir, rangé par catégorie (« À classer », « Archives », « Corbeille »).
        audio/       : les enregistrements d'origine, s'il y en a.

        Attention : cet export N'EST PAS chiffré. Garde-le dans un endroit sûr.
        """
}
