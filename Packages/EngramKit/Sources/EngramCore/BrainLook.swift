import Foundation

/// Couleur de chaque grande catégorie : toujours la même (Cerveau, Notes, Retrouver), choisie dans une palette douce.
/// Le nom est normalisé (accents, majuscules, pluriel) ; une sous-catégorie prend la couleur de sa grande catégorie.
public enum CategoryPalette {
    /// Teintes (0 à 1) : bleu, indigo, violet, rose, corail, orange, ambre, vert, sarcelle, cyan.
    public static let hues: [Double] = [0.58, 0.66, 0.76, 0.90, 0.01, 0.07, 0.12, 0.37, 0.47, 0.53]
    public static var count: Int { hues.count }

    public static func index(for name: String) -> Int {
        Int(fnv1a(TextNormalizer.normalizedName(name)) % UInt64(count))
    }

    /// « Maison › Réparations » prend la couleur de « Maison ».
    public static func index(forPath path: String) -> Int {
        index(for: path.components(separatedBy: " › ").first ?? path)
    }

    public static func hue(for name: String) -> Double { hues[index(for: name)] }

    /// Empreinte stable d'un texte (contrairement à `hashValue`, identique d'un lancement à l'autre).
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}

/// Mouvements du Cerveau, calculés à partir du temps (aucun état) : à l'arrêt (temps 0), le dessin est identique.
public enum BrainMotion {
    /// Une note tourne lentement autour de sa catégorie (un tour en 40 à 70 s), sans jamais s'en éloigner.
    public static func orbit(_ point: (x: Double, y: Double), around anchor: (x: Double, y: Double), seed: UInt64,
                             time: Double) -> (x: Double, y: Double) {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let period = 40 + Double(seed % 31)
        let direction: Double = seed % 2 == 0 ? 1 : -1
        let angle = direction * 2 * Double.pi * time / period
        let cosine = cos(angle)
        let sine = sin(angle)
        return (anchor.x + dx * cosine - dy * sine, anchor.y + dx * sine + dy * cosine)
    }

    /// Respiration d'un neurone : ± 6 % sur 3 à 5 s, chacun à son rythme.
    public static func pulse(seed: UInt64, time: Double) -> Double {
        let period = 3 + Double(seed % 21) / 10
        let phase = Double(seed % 628) / 100
        return 1 + 0.06 * sin(2 * Double.pi * time / period + phase)
    }

    /// Signal le long d'une connexion : il la parcourt en 1,4 s, une fois toutes les 4 à 9 s. Renvoie l'avancement
    /// (0 à 1) pendant son passage, nil sinon.
    public static func signal(seed: UInt64, time: Double) -> Double? {
        let every = 4 + Double(seed % 51) / 10
        let offset = Double(seed % 97) / 97 * every
        let local = (max(0, time) + offset).truncatingRemainder(dividingBy: every)
        let travel = 1.4
        return local < travel ? local / travel : nil
    }

    /// Graine stable tirée d'un identifiant de note ou de catégorie.
    public static func seed(_ id: UUID) -> UInt64 {
        CategoryPalette.fnv1a(id.uuidString)
    }
}
