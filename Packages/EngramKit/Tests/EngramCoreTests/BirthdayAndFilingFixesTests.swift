import Foundation
import Testing
@testable import EngramCore

/// Correctifs signalés sur l'iPhone : « retiens l'anniversaire de Inès c'est le 13 octobre » classé dans
/// Santé › Poids, et « c'est quand la fête à Inès ? » sans réponse dans Retrouver.
struct BirthdayAndFilingFixesTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Les fêtes dites comme au Québec

    @Test func birthdaysAreRecognizedTheWayTheyAreSaid() {
        #expect(BirthdayParser.parse("Retiens l'anniversaire de Inès c'est le 13 octobre")
            == ParsedBirthday(person: "Inès", month: 10, day: 13))
        #expect(BirthdayParser.parse("Retiens la fête à Inès, c'est le 13 octobre")
            == ParsedBirthday(person: "Inès", month: 10, day: 13))
        #expect(BirthdayParser.parse("L'anniversaire à Inès c'est le treize octobre")
            == ParsedBirthday(person: "Inès", month: 10, day: 13))
        #expect(BirthdayParser.parse("C'est la fête de Marc le premier mars") == ParsedBirthday(person: "Marc", month: 3, day: 1))
        #expect(BirthdayParser.parse("Inès fête ses 30 ans le 13 octobre")
            == ParsedBirthday(person: "Inès", month: 10, day: 13, turning: 30))
        #expect(BirthdayParser.parse("La fête de Noël, c'est le 25 décembre") == nil)
    }

    @Test func turningAnAgeGivesTheYearOfBirth() {
        let parsed = ParsedBirthday(person: "Inès", month: 10, day: 13, turning: 30)
        // Dit le 9 octobre 2026 : elle aura 30 ans le 13 octobre 2026, donc née en 1996.
        #expect(parsed.birthYear(saidOn: Self.date(2026, 10, 9), calendar: Self.calendar) == 1996)
        // Dit après la fête : c'est l'an prochain qu'elle aura 30 ans.
        #expect(parsed.birthYear(saidOn: Self.date(2026, 11, 2), calendar: Self.calendar) == 1997)
        #expect(ParsedBirthday(person: "Marc", month: 3, day: 1, year: 1980).birthYear(saidOn: Self.date(2026, 10, 9),
                                                                                     calendar: Self.calendar) == 1980)
    }

    // MARK: - Ce qu'Engram a déjà compris, dit à l'IA

    @Test func theFactsEngramRecognizedAreToldToTheAI() {
        #expect(NoteFacts.describe("Retiens l'anniversaire de Inès c'est le 13 octobre")
            == ["la fête d'Inès, le 13 octobre (une date pour une personne, pas une mesure de santé)"])
        #expect(NoteFacts.describe("Je pèse 162,5 livres") == ["une mesure de poids"])
        #expect(NoteFacts.describe("Ajoute du lait à ma liste d'épicerie") == ["un ajout à la liste d'épicerie"])
        #expect(NoteFacts.describe("Appeler l'assurance pour la voiture").isEmpty)
    }

    // MARK: - Un suivi ne reçoit que ses mesures

    func validated(_ text: String, category: String, subcategory: String?) throws -> [String] {
        let thought = AnalyzedThought(title: text, summary: nil, excerpt: text, kind: .info, tags: [], mentionedDates: [],
                                      category: category, subcategory: subcategory)
        return try #require(try AnalysisValidator.validate(ThoughtAnalysis(thoughts: [thought]), against: text).first)
            .categoryPath
    }

    @Test func aMeasurementFolderOnlyReceivesThatMeasurement() throws {
        // Une fête n'a rien à faire dans « Poids » : elle va avec les anniversaires (P33).
        #expect(try validated("Retiens l'anniversaire de Inès c'est le 13 octobre", category: "Santé", subcategory: "Poids")
            == ["Anniversaires"])
        // Une note sans mesure reste « À classer » plutôt que mal rangée.
        #expect(try validated("Appeler la clinique", category: "Santé", subcategory: "Poids") == [])
        #expect(try validated("Je pèse 162,5 livres", category: "Santé", subcategory: "Poids") == ["Santé", "Poids"])
        #expect(try validated("J'ai dormi 7 h", category: "Santé", subcategory: "Poids") == [])
        #expect(try validated("J'ai dormi 7 h", category: "Santé", subcategory: "Sommeil") == ["Santé", "Sommeil"])
        // Un dossier qui n'est pas un suivi ne change pas.
        #expect(try validated("Rendez-vous chez le dentiste", category: "Santé", subcategory: "Rendez-vous")
            == ["Santé", "Rendez-vous"])
    }

    // MARK: - Retrouver

    func document(_ title: String, _ text: String) -> RecallDocument {
        RecallDocument(id: UUID(), title: title, text: text, kind: .info, status: .active,
                       capturedAt: Self.date(2026, 10, 8), dueAt: nil, categories: [], tags: [])
    }

    @Test func aFeteIsAnAnniversaire() {
        // Le prénom a été mal transcrit (« Inèz ») : « fête » trouve quand même « anniversaire ».
        let note = document("Anniversaire le 13 octobre", "Retiens l'anniversaire de Inèz c'est le 13 octobre")
        let other = document("Appeler l'assurance", "Appeler l'assurance pour la voiture")
        let query = RecallQuery.parse("C'est quand déjà la fête à Inès?", now: Self.date(2026, 10, 9), calendar: Self.calendar)
        #expect(RecallRanker.rank([note, other], for: query, now: Self.date(2026, 10, 9)).map(\.document.id) == [note.id])
    }

    @Test func aBirthdayQuestionNamesThePerson() {
        #expect(BirthdayQuestion.person(in: "C'est quand déjà la fête à Inès?") == "Inès")
        #expect(BirthdayQuestion.person(in: "Quand est l'anniversaire de Marc ?") == "Marc")
        #expect(BirthdayQuestion.person(in: "C'est quand la fête de ma mère") == "ma mère")
        #expect(BirthdayQuestion.person(in: "When is Julie's birthday?") == "Julie")
        #expect(BirthdayQuestion.person(in: "C'est quoi déjà que j'avais dit sur l'assurance?") == nil)
        #expect(BirthdayQuestion.person(in: "La fête d'Inès?") == "Inès")
        // Une question sur un cadeau n'est pas une question de date ; Noël n'est pas une personne.
        #expect(BirthdayQuestion.person(in: "Qu'est-ce que je voulais offrir pour la fête de Julie?") == nil)
        #expect(BirthdayQuestion.person(in: "C'est quand la fête de Noël?") == nil)
    }

    @Test func thePersonIsFoundEvenWhenTheNameWasHeardDifferently() {
        let inez = Birthday(personID: UUID(), name: "Inèz", month: 10, day: 13, year: nil)
        let marc = Birthday(personID: UUID(), name: "Marc", month: 3, day: 1, year: nil)
        #expect(BirthdayQuestion.find("Inès", in: [marc, inez]) == inez)
        #expect(BirthdayQuestion.find("marc", in: [marc, inez]) == marc)
        #expect(BirthdayQuestion.find("Luc", in: [marc, inez]) == nil)
        // Deux noms aussi proches l'un que l'autre : Engram ne devine pas.
        let inas = Birthday(personID: UUID(), name: "Inas", month: 5, day: 2, year: nil)
        #expect(BirthdayQuestion.find("Inès", in: [inez, inas]) == nil)
    }

    @Test func aBirthdayQuestionIsAnsweredFromThePersonsPage() {
        let ines = Birthday(personID: UUID(), name: "Inès", month: 10, day: 13, year: nil)
        let now = Self.date(2026, 10, 9)
        #expect(BirthdayQuestion.answer(ines, now: now, calendar: Self.calendar)
            == "La fête d'Inès, c'est le 13 octobre, dans 4 jours.")
        let marc = Birthday(personID: UUID(), name: "Marc", month: 10, day: 10, year: 1990)
        #expect(BirthdayQuestion.answer(marc, now: now, calendar: Self.calendar)
            == "La fête de Marc, c'est demain, le 10 octobre. Marc aura 36 ans.")
        let today = Birthday(personID: UUID(), name: "Léa", month: 10, day: 9, year: nil)
        #expect(BirthdayQuestion.answer(today, now: now, calendar: Self.calendar) == "La fête de Léa, c'est aujourd'hui, le 9 octobre.")
    }
}
