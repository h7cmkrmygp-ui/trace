import EngramCore
import Foundation
import NaturalLanguage

/// Reconnaissance des noms **sur l'iPhone** (NaturalLanguage d'Apple), pour relire les anciennes notes sans rien
/// envoyer. Un nom de personne devient une personne ; un nom de lieu ou d'organisation (un magasin, une entreprise),
/// un lieu.
public struct AppleEntityRecognizer: EntityRecognizer {
    public init() {}

    public func names(in text: String) -> [RecognizedName] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.setLanguage(.french, range: text.startIndex..<text.endIndex)
        var found: [RecognizedName] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            switch tag {
            case .personalName?: found.append(RecognizedName(name: String(text[range]), kind: .person))
            case .placeName?, .organizationName?: found.append(RecognizedName(name: String(text[range]), kind: .place))
            default: break
            }
            return true
        }
        return found
    }
}
