import Testing
import Foundation
@testable import EngramCore

struct MemoryValidationTests {
    let sourceID = UUID()

    func draft(title: String = "Titre", content: String = "Contenu", excerpt: String = "Contenu",
               status: MemoryStatus = .unsorted, confidence: Double? = nil) -> MemoryDraft {
        MemoryDraft(sourceID: sourceID, excerpt: excerpt, title: title, content: content,
                    status: status, confidence: confidence, analysisVersion: "test")
    }

    @Test func validDraftPasses() throws {
        try draft().validate()
    }

    @Test func rejectsBlankTitle() {
        #expect(throws: MemoryValidationError.emptyTitle) { try draft(title: "   ").validate() }
    }

    @Test func rejectsTitleOver80Characters() {
        #expect(throws: MemoryValidationError.titleTooLong) {
            try draft(title: String(repeating: "x", count: 81)).validate()
        }
    }

    @Test func rejectsBlankContentAndExcerpt() {
        #expect(throws: MemoryValidationError.emptyContent) { try draft(content: " \n").validate() }
        #expect(throws: MemoryValidationError.emptyExcerpt) { try draft(excerpt: "").validate() }
    }

    @Test func draftCannotStartArchivedOrTrashed() {
        #expect(throws: MemoryValidationError.invalidStatus) { try draft(status: .archived).validate() }
        #expect(throws: MemoryValidationError.invalidStatus) { try draft(status: .trashed).validate() }
    }

    @Test func rejectsConfidenceOutsideZeroOne() {
        #expect(throws: MemoryValidationError.invalidConfidence) { try draft(confidence: 1.5).validate() }
    }

    @Test func memoryFromDraftStartsAtVersionOne() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let memory = Memory(draft: draft(title: "  Titre  "), capturedAt: now, now: now)
        #expect(memory.version == 1)
        #expect(memory.title == "Titre")
        #expect(memory.userEdited == false)
        #expect(memory.trashedAt == nil)
    }

    @Test func editReportsWhetherSomethingChanged() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var memory = Memory(draft: draft(), capturedAt: now, now: now)
        #expect(MemoryEdit(title: "Titre").apply(to: &memory) == false)
        #expect(MemoryEdit(title: " Nouveau ").apply(to: &memory) == true)
        #expect(memory.title == "Nouveau")
        #expect(MemoryEdit(summary: "Résumé").apply(to: &memory) == true)
        #expect(MemoryEdit(summary: "").apply(to: &memory) == true)
        #expect(memory.summary == nil)
    }
}
