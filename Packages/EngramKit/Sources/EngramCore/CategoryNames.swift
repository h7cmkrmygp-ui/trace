import Foundation

/// P32 — « Assurance » et « Assurances » sont la même catégorie : la clé ignore accents, majuscules et pluriel.
public enum CategoryNames {
    public static func key(_ name: String) -> String {
        TextNormalizer.normalizedName(name)
    }
}
