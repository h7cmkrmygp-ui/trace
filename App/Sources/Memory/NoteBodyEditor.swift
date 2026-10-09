import EngramCore
import SwiftUI

/// Le texte d'une note, modifiable sur place comme dans Notes d'Apple : des paragraphes et des cases à cocher.
/// Retour dans une case en crée une nouvelle ; Retour dans une case vide termine la liste.
struct NoteBodyEditor: View {
    @Binding var blocks: [NoteBlock]
    var focus: FocusState<NoteField?>.Binding
    let tint: Color
    /// Une case cochée ou décochée : enregistrée tout de suite.
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($blocks) { $block in
                switch block.kind {
                case .text:
                    TextField("Écris ta note…", text: $block.text, axis: .vertical)
                        .font(.body)
                        .lineSpacing(3)
                        .focused(focus, equals: .block(block.id))
                case .check(let done):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Button {
                            block.kind = .check(done: !done)
                            onToggle()
                        } label: {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(done ? tint : Color.secondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(done ? "Fait : \(block.text)" : "À faire : \(block.text)")
                        .sensoryFeedback(.selection, trigger: done)
                        TextField("Élément", text: $block.text, axis: .vertical)
                            .strikethrough(done, color: .secondary)
                            .foregroundStyle(done ? Color.secondary : Color.primary)
                            .focused(focus, equals: .block(block.id))
                            .onChange(of: block.text) { _, text in splitOnReturn(block.id, text) }
                    }
                }
            }
        }
    }

    /// Retour dans une case : la suite part dans une nouvelle case ; dans une case vide, la liste se termine.
    private func splitOnReturn(_ id: UUID, _ text: String) {
        guard text.contains("\n"), let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let head = parts[0]
        let tail = parts.count > 1 ? parts[1] : ""
        if head.trimmingCharacters(in: .whitespaces).isEmpty && tail.isEmpty {
            blocks[index] = NoteBlock(id: id, kind: .text, text: "")
            focus.wrappedValue = .block(id)
            return
        }
        blocks[index].text = head
        let next = NoteBlock(kind: .check(done: false), text: tail)
        blocks.insert(next, at: index + 1)
        focus.wrappedValue = .block(next.id)
    }

    /// Bouton « Liste à cocher » : la ligne vide en cours devient une case, sinon une case s'ajoute juste après.
    static func addCheck(to blocks: inout [NoteBlock], after focused: NoteField?) -> UUID {
        if case .block(let id) = focused, let index = blocks.firstIndex(where: { $0.id == id }) {
            if blocks[index].kind == .text, blocks[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks[index].kind = .check(done: false)
                blocks[index].text = ""
                return id
            }
            let next = NoteBlock(kind: .check(done: false), text: "")
            blocks.insert(next, at: index + 1)
            return next.id
        }
        let next = NoteBlock(kind: .check(done: false), text: "")
        blocks.append(next)
        return next.id
    }
}

/// Champ en cours de saisie dans une note.
enum NoteField: Hashable {
    case title
    case block(UUID)
}
