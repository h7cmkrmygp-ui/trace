import Foundation

extension PersonQuestion {
    /// P44 — la ligne ajoutée au rappel de la veille d'une fête : « Idées de cadeaux : Foulard. Julie aime les parfums et le
    /// chocolat. » (3 idées et 2 goûts au plus) ; nil si les notes ne disent rien (le rappel reste comme avant).
    public static func reminderIdeas(person: String, profile: PersonProfile) -> String? {
        var parts: [String] = []
        if !profile.giftIdeas.isEmpty {
            parts.append("Idées de cadeaux : \(SecondBrainText.naturalList(Array(profile.giftIdeas.prefix(3)))).")
        }
        if !profile.tastes.likes.isEmpty {
            parts.append("\(person) aime \(SecondBrainText.naturalList(Array(profile.tastes.likes.prefix(2)))).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
