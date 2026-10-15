import Foundation

/// Fin de la parole : après au moins 1 s de parole, ta voix ne revient pas pendant 4 s.
/// Une pause pour réfléchir (1 à 3 s) ne coupe pas ; un bruit bref (une toux, un coup à la porte) ne compte pas.
///
/// Ta voix, tout près du micro, est bien plus forte que ce qui vient de loin : la musique, un ventilateur, une
/// conversation dans la pièce. Le détecteur apprend donc deux niveaux : le bruit de fond (le niveau bas habituel des
/// 10 dernières secondes) et ta voix (tes syllabes les plus fortes). Ce qui reste nettement sous ta voix compte comme
/// du silence, même si ça bouge. Dans un lieu où le bruit est aussi fort que ta voix, rien ne s'arrête seul.
public struct SilenceDetector: Sendable {
    public var silenceDuration: TimeInterval = 4
    public var minimumSpeech: TimeInterval = 1
    /// Écart au-dessus du bruit de fond qui peut être de la voix (niveaux de 0 à 1, soit environ 7 dB).
    public var speechMargin: Float = 0.15
    /// Ce qui reste à plus de 10 dB (0,2) sous tes syllabes les plus fortes n'est pas ta voix.
    public var voiceDrop: Float = 0.2
    /// Un éclat plus court que ça (0,15 s), isolé dans le silence, ne relance pas l'attente.
    public var ignoredBurst: TimeInterval = 0.15
    /// Silence qui doit précéder un éclat pour qu'il soit isolé (la parole, elle, a des creux bien plus courts).
    public var burstIsolation: TimeInterval = 0.5
    static let floorWindow: TimeInterval = 10

    private var samples: [(time: TimeInterval, level: Float)] = []

    public init() {}

    /// Ajoute une mesure du micro ; renvoie vrai quand on peut arrêter l'enregistrement.
    public mutating func add(level: Float, at time: TimeInterval, interval: TimeInterval) -> Bool {
        samples.append((time, level))
        let recent = samples.filter { $0.time > time - Self.floorWindow }.map(\.level).sorted()
        guard !recent.isEmpty else { return false }
        let floor = recent[Int(Double(recent.count - 1) * 0.1)]
        // Ta voix : les sons au-dessus du bruit de fond, dont on garde les plus forts (9 sur 10 sont plus faibles).
        // Recalculée sur tout l'enregistrement : si tu as parlé tout de suite, elle est reconnue dès le premier silence.
        let loud = samples.map(\.level).filter { $0 > floor + speechMargin }.sorted()
        guard !loud.isEmpty else { return false }
        let voice = loud[Int(Double(loud.count - 1) * 0.9)]
        let threshold = max(floor + speechMargin, voice - voiceDrop)
        let spoken = samples.reduce(0) { $1.level >= threshold ? $0 + 1 : $0 }
        guard Double(spoken) * interval >= minimumSpeech - 1e-9 else { return false }
        // Un son fort en ce moment : peut-être le début d'une phrase, on attend de voir.
        if let last = samples.last, last.level >= threshold { return false }
        // Silence final, en remontant le temps. Un éclat bref, précédé d'au moins 0,5 s de silence, en fait partie ;
        // un éclat plus long, ou suivi trop vite d'un autre (les syllabes d'une phrase), l'interrompt.
        let burstLimit = Int((ignoredBurst / interval).rounded())
        let isolation = Int((burstIsolation / interval).rounded())
        var quiet = 0
        var burst = 0
        var quietBeforeBurst = 0
        for sample in samples.reversed() {
            if sample.level >= threshold {
                if quietBeforeBurst > 0 { break }
                burst += 1
                if burst > burstLimit { break }
            } else if burst > 0 {
                quietBeforeBurst += 1
                if quietBeforeBurst >= isolation {
                    quiet += burst + quietBeforeBurst
                    burst = 0
                    quietBeforeBurst = 0
                }
            } else {
                quiet += 1
            }
        }
        return Double(quiet) * interval >= silenceDuration - 1e-9
    }
}
