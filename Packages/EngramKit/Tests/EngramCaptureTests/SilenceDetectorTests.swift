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
            for _ in 0..<Int((segment.seconds / 0.05).rounded()) {
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

    // MARK: - Bruit de fond (bug signalé : avec de la musique, un ventilateur ou des voix, l'enregistrement continuait)

    /// Bruit qui varie sans cesse (musique, voix au loin) : un niveau tiré au hasard toutes les 50 ms, toujours le même.
    func background(_ seconds: Double, from low: Float, to high: Float, seed: UInt64) -> [(level: Float, seconds: Double)] {
        var state = seed
        return (0..<Int((seconds / 0.05).rounded())).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Float((state >> 33) % 1_000) / 1_000
            return (low + (high - low) * unit, 0.05)
        }
    }

    /// Ta voix, tout près du micro : forte, avec de petits creux entre les syllabes.
    func speech(_ seconds: Double) -> [(level: Float, seconds: Double)] {
        let pattern: [Float] = [0.78, 0.82, 0.74, 0.62, 0.8, 0.85, 0.7, 0.58]
        return (0..<Int((seconds / 0.05).rounded())).map { (pattern[$0 % pattern.count], 0.05) }
    }

    @Test func musicInTheBackgroundDoesNotKeepTheRecordingGoing() throws {
        let stop = try #require(stopTime(background(2, from: 0.32, to: 0.52, seed: 1) + speech(3)
            + background(8, from: 0.32, to: 0.52, seed: 2)))
        // Fin de la parole à 5 s : arrêt 4 s plus tard, malgré la musique.
        #expect(stop > 8.9 && stop < 9.3)
    }

    @Test func distantVoicesDoNotKeepTheRecordingGoing() throws {
        let stop = try #require(stopTime(background(2, from: 0.25, to: 0.45, seed: 3) + speech(4)
            + background(8, from: 0.25, to: 0.45, seed: 4)))
        #expect(stop > 9.9 && stop < 10.3)
    }

    @Test func aSteadyFanIsJustBackgroundNoise() throws {
        let stop = try #require(stopTime(background(2, from: 0.29, to: 0.31, seed: 5) + speech(3)
            + background(6, from: 0.29, to: 0.31, seed: 6)))
        #expect(stop > 8.9 && stop < 9.2)
    }

    @Test func aPauseToThinkWithMusicDoesNotStopTheRecording() throws {
        let stop = try #require(stopTime(background(1, from: 0.32, to: 0.52, seed: 7) + speech(2)
            + background(2.5, from: 0.32, to: 0.52, seed: 8) + speech(1.5) + background(6, from: 0.32, to: 0.52, seed: 9)))
        // La pause de 2,5 s ne coupe pas : arrêt seulement 4 s après la dernière phrase (fin à 7 s).
        #expect(stop > 10.9 && stop < 11.3)
    }

    @Test func aKnockDuringTheSilenceDoesNotRestartTheWait() throws {
        let stop = try #require(stopTime([(0.1, 1)] + speech(2) + [(0.1, 2), (0.9, 0.1), (0.1, 4)]))
        #expect(stop > 6.9 && stop < 7.2)
    }

    @Test func speakingAgainAfterAPauseRestartsTheWait() throws {
        let stop = try #require(stopTime([(0.1, 1)] + speech(2) + [(0.1, 3)] + speech(0.6) + [(0.1, 6)]))
        #expect(stop > 10.5 && stop < 10.8)
    }
}
