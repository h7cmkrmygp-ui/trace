import Foundation
import Testing
@testable import EngramCapture

/// F26 — la confiance du modèle suit le texte : le morceau le moins sûr donne la confiance de la dictée.
/// F27 — ressources bornées : un seul chargement de Whisper à la fois, une seule transcription à la fois, un détecteur
/// de silence qui ne garde qu'une fenêtre bornée même après cinq minutes de bruit.
struct TranscriptQualityTests {
    @Test func theLeastConfidentPieceGivesTheConfidence() {
        let transcript = TranscriptAssembler.assemble([
            Hypothesis(language: "fr", text: "Acheter du lait", averageLogProbability: -0.3),
            Hypothesis(language: "en", text: "and eggs", averageLogProbability: -1.1),
        ])
        #expect(transcript.averageLogProbability == -1.1)
        #expect(TranscriptAssembler.assemble([]).averageLogProbability == nil)
    }

    @Test func aHeavyResourceIsLoadedOnceEvenWhenAskedTwiceAtOnce() async throws {
        let loads = Counter()
        let flight = SingleFlight<Int>()
        async let first = flight.value { await loads.increment(); try await Task.sleep(nanoseconds: 50_000_000); return 7 }
        async let second = flight.value { await loads.increment(); return 8 }
        let values = try await [first, second]
        #expect(values == [7, 7])
        #expect(await loads.value == 1)
        // Après une libération, le prochain appel recharge.
        await flight.reset()
        #expect(try await flight.value { await loads.increment(); return 9 } == 9)
        #expect(await loads.value == 2)
    }

    @Test func aFailedLoadIsRetriedNextTime() async throws {
        let flight = SingleFlight<Int>()
        await #expect(throws: TranscriptionError.unreadableAudio) {
            try await flight.value { throw TranscriptionError.unreadableAudio }
        }
        #expect(try await flight.value { 3 } == 3)
    }

    @Test func transcriptionsRunOneAtATime() async throws {
        let gate = SerialGate()
        let tracker = Overlap()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    try await gate.run {
                        await tracker.enter()
                        try await Task.sleep(nanoseconds: 20_000_000)
                        await tracker.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await tracker.maximum == 1)
    }

    @Test func theSilenceDetectorKeepsABoundedWindow() {
        var detector = SilenceDetector()
        var time = 0.0
        // Cinq minutes de bruit de fond régulier, une mesure toutes les 50 ms.
        for index in 0..<6_000 {
            time += 0.05
            _ = detector.add(level: index % 2 == 0 ? 0.3 : 0.32, at: time, interval: 0.05)
        }
        #expect(detector.retainedSamples <= SilenceDetector.retentionLimit)
    }
}

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

actor Overlap {
    private var current = 0
    private(set) var maximum = 0
    func enter() {
        current += 1
        maximum = max(maximum, current)
    }
    func leave() { current -= 1 }
}
