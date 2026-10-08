import EngramCore
import EngramStore
import Foundation
import Observation

/// Services partagés par tous les écrans, et dernière erreur à afficher.
@MainActor
@Observable
final class AppModel {
    let database: AppDatabase
    let memories: MemoryStore
    let categories: CategoryStore
    var errorMessage: String?

    init(database: AppDatabase) {
        self.database = database
        memories = MemoryStore(database: database)
        categories = CategoryStore(database: database)
    }

    /// Ouvre la base sur l'appareil et crée les catégories de départ si besoin.
    static func launch() -> Result<AppModel, any Error> {
        Result {
            let model = AppModel(database: try AppDatabase.openOnDisk())
            try model.categories.seedDefaultsIfNeeded()
            return model
        }
    }

    /// Exécute une action ; en cas d'erreur, l'affiche dans une alerte.
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = Self.describe(error) }
    }

    static func describe(_ error: any Error) -> String {
        if let error = error as? StoreError {
            switch error {
            case .emptyContent: return "Le contenu est vide."
            case .notFound: return "Cet élément n'existe plus."
            case .protectedByUser: return "Ce souvenir a été modifié à la main : il est protégé."
            case .nameConflict: return "Une catégorie porte déjà ce nom à cet endroit."
            case .invalidName: return "Ce nom n'est pas valide (vide ou trop long)."
            case .invalidOperation(let reason): return "Opération impossible : \(reason)."
            }
        }
        if let error = error as? MemoryValidationError {
            switch error {
            case .emptyTitle: return "Le titre ne peut pas être vide."
            case .titleTooLong: return "Le titre dépasse 80 caractères."
            case .emptyContent: return "Le contenu ne peut pas être vide."
            case .emptyExcerpt, .invalidStatus, .invalidConfidence: return "Données de souvenir invalides."
            }
        }
        return error.localizedDescription
    }
}
