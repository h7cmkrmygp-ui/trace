import EngramCore

/// Une phrase d'évaluation **fictive** et les catégories racines acceptables.
public struct EvaluationCase: Sendable, Hashable {
    public let sentence: String
    public let acceptedRoots: [String]
    /// Nombre de notes attendu quand il compte (un rappel qui parle de la même chose = une seule note).
    public let expectedNotes: Int?

    public init(sentence: String, acceptedRoots: [String], expectedNotes: Int? = nil) {
        self.sentence = sentence
        self.acceptedRoots = acceptedRoots
        self.expectedNotes = expectedNotes
    }

    /// Vrai si la catégorie racine proposée correspond à une racine acceptée (accents, casse et pluriel ignorés).
    public func accepts(categoryPath: [String]) -> Bool {
        guard let root = categoryPath.first else { return false }
        let key = TextNormalizer.normalizedName(root)
        return acceptedRoots.contains { TextNormalizer.normalizedName($0) == key }
    }
}

/// 49 phrases inventées (aucune donnée réelle), en français, en anglais ou mélangées, dont neuf qui reprennent
/// les erreurs constatées sur l'iPhone : un rappel coupé en deux notes, un poids classé en Finance, deux sujets fusionnés,
/// deux sujets dans une même phrase en franglais, une hésitation, un poids daté « aujourd'hui », deux fêtes (une a été
/// classée dans Santé › Poids) et une assurance.
public enum EvaluationSet {
    static let auto = ["Automobile", "Auto", "Voiture", "Véhicule", "Véhicules"]
    static let finance = ["Finance", "Finances", "Argent", "Placements", "Investissements", "Budget"]
    static let work = ["Travail", "Emploi", "Boulot", "Carrière"]
    static let health = ["Santé", "Sport", "Fitness", "Entraînement", "Bien-être"]
    static let home = ["Maison", "Logement", "Domicile", "Entretien", "Réparations"]
    static let shopping = ["Achats", "Courses", "Épicerie", "Magasinage", "Shopping"]
    static let travel = ["Voyages", "Voyage", "Vacances"]
    static let family = ["Famille", "Proches", "Personnel"]
    static let birthdays = ["Amis", "Anniversaires", "Anniversaire", "Fêtes", "Personnes", "Relations", "Dates importantes"]
    static let studies = ["Études", "École", "Cours", "Apprentissage", "Formation"]
    static let projects = ["Projets", "Idées", "Technologie", "Développement", "Application"]

    public static let cases: [EvaluationCase] = [
        EvaluationCase(sentence: "Rappeler d'acheter des wipers pour la Corolla", acceptedRoots: auto),
        EvaluationCase(sentence: "Appeler mon gestionnaire de placements", acceptedRoots: finance),
        EvaluationCase(sentence: "Envoyer le rapport trimestriel le 24 novembre", acceptedRoots: work),
        EvaluationCase(sentence: "Prendre rendez-vous chez le dentiste", acceptedRoots: health),
        EvaluationCase(sentence: "Faire le changement d'huile de la Civic la semaine prochaine", acceptedRoots: auto),
        EvaluationCase(sentence: "Payer la facture d'électricité avant le 15", acceptedRoots: finance + home + ["Factures"]),
        EvaluationCase(sentence: "Acheter du lait et des œufs", acceptedRoots: shopping + ["Alimentation"]),
        EvaluationCase(sentence: "Book the flight to Paris for December", acceptedRoots: travel),
        EvaluationCase(sentence: "Idée : une app qui classe mes pensées toute seule", acceptedRoots: projects),
        EvaluationCase(sentence: "Envoyer le rapport trimestriel à mon boss", acceptedRoots: work),
        EvaluationCase(sentence: "Renouveler mon passeport avant l'été", acceptedRoots: travel + ["Documents", "Administratif", "Administration"]),
        EvaluationCase(sentence: "Appeler maman pour son anniversaire dimanche", acceptedRoots: family),
        EvaluationCase(sentence: "Réserver un resto pour la Saint-Valentin", acceptedRoots: family + ["Couple", "Sorties", "Loisirs", "Restaurants"]),
        EvaluationCase(sentence: "Faire mon workout avant le travail jeudi", acceptedRoots: health),
        EvaluationCase(sentence: "Need to fix the leaking faucet in the kitchen", acceptedRoots: home),
        EvaluationCase(sentence: "Commander des pneus d'hiver pour le RAV4", acceptedRoots: auto),
        EvaluationCase(sentence: "Vérifier le solde de mon CELI", acceptedRoots: finance),
        EvaluationCase(sentence: "Préparer la présentation du projet Atlas pour lundi", acceptedRoots: work + ["Projets"]),
        EvaluationCase(sentence: "Lire le chapitre 4 pour le cours de statistiques", acceptedRoots: studies),
        EvaluationCase(sentence: "Prendre mes vitamines tous les matins", acceptedRoots: health),
        EvaluationCase(sentence: "Buy a birthday gift for Julie", acceptedRoots: shopping + family + ["Cadeaux", "Amis"]),
        EvaluationCase(sentence: "Annuler l'abonnement au gym", acceptedRoots: finance + health + ["Abonnements"]),
        EvaluationCase(sentence: "Planifier les vacances au Mexique en mars", acceptedRoots: travel),
        EvaluationCase(sentence: "Faire l'épicerie samedi", acceptedRoots: shopping + ["Alimentation"]),
        EvaluationCase(sentence: "Le meeting avec l'équipe marketing est déplacé à 14h", acceptedRoots: work),
        EvaluationCase(sentence: "Changer le filtre de la fournaise", acceptedRoots: home),
        EvaluationCase(sentence: "Remember to call the insurance about the car claim", acceptedRoots: auto + finance + ["Assurances", "Assurance"]),
        EvaluationCase(sentence: "Je préfère un design minimaliste pour mon application", acceptedRoots: projects + ["Préférences", "Design"]),
        EvaluationCase(sentence: "Inscrire les enfants au camp de jour", acceptedRoots: family + ["Enfants"]),
        EvaluationCase(sentence: "Faire ma déclaration d'impôts avant avril", acceptedRoots: finance + ["Impôts", "Administratif", "Administration"]),
        EvaluationCase(sentence: "Apprendre les bases de SwiftUI ce mois-ci", acceptedRoots: studies + projects + ["Programmation"]),
        EvaluationCase(sentence: "Prendre rendez-vous pour l'inspection de la Corolla", acceptedRoots: auto),
        EvaluationCase(sentence: "Order new running shoes", acceptedRoots: shopping + health),
        EvaluationCase(sentence: "Rembourser 50 $ à Marc pour le souper", acceptedRoots: finance + ["Amis", "Dettes"]),
        EvaluationCase(sentence: "Mettre à jour mon CV", acceptedRoots: work),
        EvaluationCase(sentence: "Prendre des nouvelles de grand-papa", acceptedRoots: family),
        EvaluationCase(sentence: "Nettoyer les gouttières en novembre", acceptedRoots: home),
        EvaluationCase(sentence: "Regarder le documentaire sur l'espace recommandé par Léa", acceptedRoots: ["Loisirs", "Divertissement", "Culture", "Films", "Documentaires", "Médias"]),
        EvaluationCase(sentence: "Acheter un nouveau chargeur pour mon iPhone", acceptedRoots: shopping + ["Technologie", "Électronique"]),
        EvaluationCase(sentence: "Envoyer la demande de remboursement des frais de déplacement", acceptedRoots: work + finance),
        EvaluationCase(sentence: "Rappelle-moi de réserver la salle le 24 novembre, rappelle-moi ça demain",
                       acceptedRoots: work + projects + ["Événements", "Rappels", "Loisirs"], expectedNotes: 1),
        EvaluationCase(sentence: "Je pèse 75 kg ce matin", acceptedRoots: health, expectedNotes: 1),
        EvaluationCase(sentence: "Appeler le garage pour les pneus, pis acheter du lait en revenant",
                       acceptedRoots: auto + shopping + ["Alimentation"], expectedNotes: 2),
        EvaluationCase(sentence: "Faut que je call mon manager demain pour changer mon shift, pis après je vais au gym.",
                       acceptedRoots: work + health, expectedNotes: 2),
        EvaluationCase(sentence: "Rappelle-moi de euh appeler l'assurance demain ok",
                       acceptedRoots: finance + auto + home + ["Assurances", "Assurance", "Administratif"], expectedNotes: 1),
        EvaluationCase(sentence: "Je pèse 162,5 livres aujourd'hui", acceptedRoots: health, expectedNotes: 1),
        // P31-P32 : une fête rangée dans Santé › Poids, une assurance rangée dans « Automobile › car part ».
        EvaluationCase(sentence: "Retiens la fête à Léa, c'est le 13 mars", acceptedRoots: family + birthdays, expectedNotes: 1),
        EvaluationCase(sentence: "L'anniversaire de mon frère est le 2 juin", acceptedRoots: family + birthdays, expectedNotes: 1),
        EvaluationCase(sentence: "Réévaluer l'assurance de la maison avant le renouvellement",
                       acceptedRoots: finance + home + ["Assurances", "Assurance", "Administratif"]),
    ]
}
