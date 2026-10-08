import Foundation
import Testing
@testable import EngramCapture

/// Arrêt automatique quand on se tait : jamais pendant une pause pour réfléchir, jamais avant d'avoir parlé.
struct SilenceDetectorTests {
    /// Niveaux du micro (0 = silence, 1 = très fort), un toutes les 50 ms ; renvoie l'instant où l'arrêt est demandé.
    func stopTime(_ segments: [(level: Float, seconds: Double)]) -> Double? {
        var detector = SilenceDetector()
        var time = 0.0
        for segment in segments {
            for _ in 0..<Int(segment.seconds / 0.05) {
                time += 0.05
                if detector.add(level: segment.level, at: time, interval: 0.05) { return time }
            }
        }
        return nil
    }

    @Test func aPauseToThinkDoesNotStopTheRecording() throws {
        let stop = try #require(stopTime([(0.1, 1), (0.6, 2), (0.1, 2.5), (0.6, 1.5), (0.1, 6)]))
        // Arrêt seulement après la dernière phrase (fin à 7 s) et 4 s de silence.
        #expect(stop > 10.9 && stop < 11.2)
    }

    @Test func silenceWithoutSpeechNeverStops() {
        #expect(stopTime([(0.1, 20)]) == nil)
    }

    @Test func speakingRightAwayStillWorks() throws {
        let stop = try #require(stopTime([(0.6, 3), (0.1, 5)]))
        #expect(stop > 6.9 && stop < 7.2)
    }

    @Test func aNoisyPlaceIsJudgedAgainstItsOwnNoise() throws {
        // Bruit de voiture (0,45) : la parole (0,75) se distingue, puis le bruit seul compte comme silence.
        let stop = try #require(stopTime([(0.45, 2), (0.75, 3), (0.45, 5)]))
        #expect(stop > 8.9 && stop < 9.2)
    }

    @Test func tooLittleSpeechIsNotEnough() {
        // Un bruit bref (une toux) n'est pas une dictée : pas d'arrêt automatique.
        #expect(stopTime([(0.1, 1), (0.7, 0.3), (0.1, 8)]) == nil)
    }
}
