import Foundation

public enum MemoryValidationError: Error, Equatable, Sendable {
    case emptyTitle, titleTooLong, emptyContent, emptyExcerpt, invalidStatus, invalidConfidence
}

public enum MemoryValidation {
    /// Vérifie les champs communs à toute écriture d'un souvenir.
    public static func validate(title: String, content: String) throws {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MemoryValidationError.emptyTitle }
        if title.count > TitleMaker.maxLength { throw MemoryValidationError.titleTooLong }
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MemoryValidationError.emptyContent }
    }
}

extension MemoryDraft {
    public func validate() throws {
        try MemoryValidation.validate(title: title.trimmingCharacters(in: .whitespacesAndNewlines), content: content)
        if excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MemoryValidationError.emptyExcerpt }
        guard status == .active || status == .unsorted else { throw MemoryValidationError.invalidStatus }
        if let confidence, !(0...1).contains(confidence) { throw MemoryValidationError.invalidConfidence }
    }
}
