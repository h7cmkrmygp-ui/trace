import Foundation
import Testing
@testable import EngramCore

/// Le texte d'une note, comme dans Notes d'Apple : des paragraphes et des cases à cocher.
struct NoteBodyTests {
    func shape(_ blocks: [NoteBlock]) -> [String] {
        blocks.map { block in
            switch block.kind {
            case .text: "texte:\(block.text)"
            case .check(let done): "\(done ? "fait" : "à faire"):\(block.text)"
            }
        }
    }

    @Test func paragraphsAndCheckboxesAreSplitIntoBlocks() {
        let body = "Préparer le voyage\nRéserver tôt\n☐ Passeport\n☑ Valise\nNe pas oublier le chargeur"
        #expect(shape(NoteBody.blocks(from: body)) == [
            "texte:Préparer le voyage\nRéserver tôt", "à faire:Passeport", "fait:Valise", "texte:Ne pas oublier le chargeur",
        ])
    }

    @Test func aBodyComesBackUnchanged() {
        let body = "Préparer le voyage\n☐ Passeport\n☑ Valise\nNe pas oublier le chargeur"
        #expect(NoteBody.text(from: NoteBody.blocks(from: body)) == body)
    }

    @Test func markdownCheckboxesFromTheAIAreUnderstood() {
        let blocks = NoteBody.blocks(from: "- [ ] Lait\n- [x] Pain\n[ ] Œufs")
        #expect(shape(blocks) == ["à faire:Lait", "fait:Pain", "à faire:Œufs"])
        #expect(NoteBody.text(from: blocks) == "☐ Lait\n☑ Pain\n☐ Œufs")
    }

    @Test func anEmptyBodyHasNoBlocks() {
        #expect(NoteBody.blocks(from: "  \n ").isEmpty)
        #expect(NoteBody.text(from: []).isEmpty)
    }

    /// Dans les listes : « 2/3 » pour une note à cases, rien pour un texte simple.
    @Test func checklistProgressIsCounted() {
        #expect(NoteBody.progress(of: "Préparer\n☐ Passeport\n☑ Valise\n☑ Billets")?.done == 2)
        #expect(NoteBody.progress(of: "Préparer\n☐ Passeport\n☑ Valise\n☑ Billets")?.total == 3)
        #expect(NoteBody.progress(of: "Un texte sans cases") == nil)
        #expect(NoteBody.progress(of: nil) == nil)
    }

    @Test func checkingABoxOnlyChangesThatLine() {
        var blocks = NoteBody.blocks(from: "☐ Passeport\n☐ Valise")
        blocks[1].kind = .check(done: true)
        #expect(NoteBody.text(from: blocks) == "☐ Passeport\n☑ Valise")
    }
}
