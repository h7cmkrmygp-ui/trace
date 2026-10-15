/// Erreurs métier du stockage (les erreurs SQLite restent des `DatabaseError`).
public enum StoreError: Error, Equatable, Sendable {
    /// Le texte est vide ou ne contient que des espaces.
    case emptyContent
    /// L'élément demandé n'existe pas (ou plus).
    case notFound
    /// L'IA a tenté de modifier ce que le propriétaire a décidé à la main.
    case protectedByUser
    /// Un élément actif porte déjà ce nom au même endroit.
    case nameConflict
    /// Le nom est vide ou trop long.
    case invalidName
    /// L'opération n'est pas permise dans l'état actuel.
    case invalidOperation(String)
}
