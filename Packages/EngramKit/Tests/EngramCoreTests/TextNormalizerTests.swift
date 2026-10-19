import Testing
@testable import EngramCore

struct TextNormalizerTests {
    @Test(arguments: [
        ("Voyages", "voyage"),
        ("voyage", "voyage"),
        ("VOYAGES", "voyage"),
        ("Études", "etude"),
        ("Santé", "sante"),
        ("Idées", "idee"),
        ("Finances", "finance"),
        ("  Course   à pied ", "course a pied"),
        ("Voyages d'été", "voyage d ete"),
        ("Business", "business"),
        ("Bus", "bus"),
        ("!!!", ""),
        ("", ""),
    ])
    func normalizedName(input: String, expected: String) {
        #expect(TextNormalizer.normalizedName(input) == expected)
    }

    @Test func equivalentCategoryNamesShareNormalizedForm() {
        let forms = Set(["Voyages", "voyage", "  VOYAGE ", "Voyagés"].map(TextNormalizer.normalizedName))
        #expect(forms == ["voyage"])
    }

    @Test(arguments: [
        ("Il faut, que je TERMINE !", "il faut que je termine"),
        ("Réunion à 14h30", "reunion a 14h30"),
        ("  plusieurs\n\nlignes\t ici ", "plusieurs lignes ici"),
    ])
    func matchingForm(input: String, expected: String) {
        #expect(TextNormalizer.matchingForm(input) == expected)
    }
}
