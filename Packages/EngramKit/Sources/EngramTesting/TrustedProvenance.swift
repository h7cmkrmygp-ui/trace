import EngramCore

extension ContextProvenance {
    /// Pour les tests : ces dossiers, ces listes et la dictée précédente viennent de notes neutres (rien n'y est interdit).
    /// Ne jamais utiliser dans l'app.
    public static func trusted(categories: [String] = [], lists: [String] = [], recent: Bool = true) -> ContextProvenance {
        ContextProvenance(categories: Dictionary(categories.map { ($0, 0) }, uniquingKeysWith: { first, _ in first }),
                          lists: Dictionary(lists.map { ($0, 0) }, uniquingKeysWith: { first, _ in first }),
                          recent: recent ? 0 : PrivacyPolicy.unknownMask)
    }
}
