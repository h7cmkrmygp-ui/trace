import EngramCore
import Foundation
import GRDB

extension ListStore {
    /// P43 — « Qu'est-ce que je voulais pour mon anniversaire ? » : ce qui reste dans la liste ; nil si la question porte
    /// sur autre chose.
    public func listAnswer(to question: String) throws -> String? {
        ListQuestion.list(in: question, among: try widgetSources()).map(ListQuestion.answer)
    }
}

extension EntityStore {
    /// P43 — ce que les notes disent d'une personne : ses goûts (ses notes, de la plus ancienne à la plus récente ; une
    /// liste n'en fait pas partie) et ses idées de cadeaux (ce qui reste dans les listes à son nom, sauf une liste privée).
    public func profile(of entityID: UUID) throws -> PersonProfile {
        guard let person = try entity(id: entityID), person.kind == .person else { return PersonProfile() }
        let listIDs = Set(try database.writer.read { db in try UUID.fetchAll(db, sql: "SELECT memory_id FROM memory_list") })
        let texts = try memories(for: person.id).reversed()
            .filter { !listIDs.contains($0.id) }
            .map { $0.content.isEmpty ? $0.title : $0.content }
        let key = " " + TextNormalizer.matchingForm(person.name) + " "
        let gifts = try ListStore(database: database, dates: dates).widgetSources()
            .filter { !$0.isPrivate && (" " + TextNormalizer.matchingForm($0.name) + " ").contains(key) }
            .flatMap { list in
                NoteBody.blocks(from: list.body).compactMap { block -> String? in
                    if case .check(done: false) = block.kind { return block.text }
                    return nil
                }
            }
        return PersonProfile(tastes: PersonQuestion.tastes(in: texts), giftIdeas: gifts)
    }

    /// P43 — « Qu'est-ce que Julie aime ? » : ses goûts, ses idées de cadeaux et sa fête ; nil si la question porte sur autre
    /// chose ou si rien n'est noté.
    public func personAnswer(to question: String, now: Date, calendar: Calendar) throws -> String? {
        let people = try allEntities(kind: .person)
        guard let name = PersonQuestion.person(in: question, among: people.map(\.name)),
              let person = people.first(where: { $0.name == name }) else { return nil }
        let known = try self.profile(of: person.id)
        let birthday = BirthdayQuestion.find(person.name, in: try birthdays())
            .map { BirthdayQuestion.answer($0, now: now, calendar: calendar) }
        return PersonQuestion.answer(person: person.name, tastes: known.tastes, giftIdeas: known.giftIdeas,
                                     birthday: birthday)
    }
}
