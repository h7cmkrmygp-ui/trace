import Foundation

/// Fin de la parole : après au moins 1 s de parole, le niveau du micro reste au bruit de fond pendant 4 s.
/// Une pause pour réfléchir (1 à 3 s) ne coupe pas ; un bruit bref (une toux) ne suffit pas à déclencher l'arrêt.
/// Le bruit de fond est le niveau bas habituel des 10 dernières secondes : une pièce calme ou une voiture sont
/// jugées par rapport à leur propre bruit. Dans un lieu trop bruyant pour distinguer la voix, rien ne s'arrête seul.
public struct SilenceDetector: Sendable {
    public var silenceDuration: TimeInterval = 4
    public var minimumSpeech: TimeInterval = 1
    /// Écart au-dessus du bruit de fond qui compte comme de la voix (niveaux de 0 à 1, soit environ 7 dB).
    public var speechMargin: Float = 0.15
    static let floorWindow: TimeInterval = 10

    private var samples: [(time: TimeInterval, level: Float)] = []

    public init() {}

    /// Ajoute une mesure du micro ; renvoie vrai quand on peut arrêter l'enregistrement.
    public mutating func add(level: Float, at time: TimeInterval, interval: TimeInterval) -> Bool {
        samples.append((time, level))
        let recent = samples.filter { $0.time > time - Self.floorWindow }.map(\.level).sorted()
        guard !recent.isEmpty else { return false }
        let floor = recent[Int(Double(recent.count - 1) * 0.1)]
        // La voix est recomptée sur tout l'enregistrement avec le bruit de fond actuel : si on a parlé tout de
        // suite, elle est reconnue dès que le premier silence révèle le vrai bruit de fond.
        let spoken = samples.reduce(0) { $1.level > floor + speechMargin ? $0 + 1 : $0 }
        guard Double(spoken) * interval >= minimumSpeech - 1e-9 else { return false }
        var quiet = 0
        for sample in samples.reversed() {
            guard sample.level < floor + speechMargin / 2 else { break }
            quiet += 1
        }
        return Double(quiet) * interval >= silenceDuration - 1e-9
    }
}
