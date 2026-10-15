import Foundation
import Testing
@testable import EngramCore

/// P10 — les mesures dites dans une note sont reconnues sur l'iPhone, sans IA ; les pièges sont évités.
struct MeasurementParserTests {
    func one(_ text: String) -> ParsedMeasurement? {
        let found = MeasurementParser.parse(text)
        return found.count == 1 ? found[0] : nil
    }

    @Test(arguments: [
        ("Je pèse 162,5 livres aujourd'hui", 162.5, "lb", 0),
        ("je pese 162.5 lbs", 162.5, "lb", 0),
        ("Poids ce matin : 74,2 kg", 74.2, "kg", 0),
        ("J'ai pesé 75 kilos hier", 75, "kg", 1),
        ("Sur la balance : 160 lb", 160, "lb", 0),
        ("I weigh 158 pounds", 158, "lb", 0),
    ])
    func weightsAreRecognized(text: String, value: Double, unit: String, daysBefore: Int) throws {
        let found = try #require(one(text))
        #expect(found.metric == .weight)
        #expect(abs(found.value - value) < 1e-9)
        #expect(found.unit == unit)
        #expect(found.daysBefore == daysBefore)
    }

    @Test(arguments: [
        ("J'ai dormi 7 h 30", 7.5, 0), ("dormi 7h30 cette nuit", 7.5, 0), ("J'ai dormi 6 heures et demie", 6.5, 0),
        ("8 heures de sommeil", 8, 0), ("Slept 7 hours", 7, 0), ("dormi 7 h 45 avant-hier", 7.75, 2),
    ])
    func sleepIsRecognized(text: String, hours: Double, daysBefore: Int) throws {
        let found = try #require(one(text))
        #expect(found.metric == .sleep)
        #expect(abs(found.value - hours) < 1e-9)
        #expect(found.daysBefore == daysBefore)
    }

    @Test(arguments: [("Tension 120 sur 80", 120.0, 80.0), ("pression 118/76 ce matin", 118, 76),
                      ("blood pressure 125 over 82", 125, 82)])
    func bloodPressureIsRecognized(text: String, high: Double, low: Double) throws {
        let found = try #require(one(text))
        #expect(found.metric == .bloodPressure)
        #expect(found.value == high && found.secondValue == low)
    }

    @Test(arguments: [("pouls 62", 62.0), ("Mon pouls est à 58", 58), ("fréquence cardiaque 71", 71), ("64 bpm au repos", 64)])
    func heartRateIsRecognized(text: String, bpm: Double) throws {
        let found = try #require(one(text))
        #expect(found.metric == .heartRate && found.value == bpm)
    }

    @Test(arguments: [("8 000 pas aujourd'hui", 8_000.0), ("10k pas", 10_000), ("12000 steps", 12_000)])
    func stepsAreRecognized(text: String, steps: Double) throws {
        let found = try #require(one(text))
        #expect(found.metric == .steps && found.value == steps)
    }

    @Test(arguments: [("glycémie 5,6", 5.6), ("taux de sucre à 6,1", 6.1)])
    func bloodSugarIsRecognized(text: String, value: Double) throws {
        let found = try #require(one(text))
        #expect(found.metric == .glucose && abs(found.value - value) < 1e-9)
    }

    @Test(arguments: [
        "Acheter 2 livres de bœuf", "Lire 3 livres cet été", "Je pèse 1500 livres", "Rendez-vous à 7 h 30",
        "120 sur 80", "faire 3 pas", "Le colis pèse 2 kg",
    ])
    func trapsAreIgnored(text: String) {
        #expect(MeasurementParser.parse(text).isEmpty)
    }

    @Test func severalMeasurementsInOneNote() {
        let found = MeasurementParser.parse("J'ai dormi 7 h et je pèse 162 livres")
        #expect(found.map(\.metric) == [.sleep, .weight])
    }

    @Test func valuesAreShownTheQuebecWay() {
        #expect(MetricUnits.format(162.5, second: nil, metric: .weight, unit: "lb") == "162,5 lb")
        #expect(MetricUnits.format(7.5, second: nil, metric: .sleep, unit: "h") == "7 h 30")
        #expect(MetricUnits.format(8, second: nil, metric: .sleep, unit: "h") == "8 h")
        #expect(MetricUnits.format(120, second: 80, metric: .bloodPressure, unit: "mmHg") == "120/80")
        #expect(MetricUnits.format(62, second: nil, metric: .heartRate, unit: "bpm") == "62 bpm")
        #expect(MetricUnits.format(8_000, second: nil, metric: .steps, unit: "pas") == "8\u{00A0}000 pas")
        #expect(MetricUnits.format(5.6, second: nil, metric: .glucose, unit: "mmol/L") == "5,6 mmol/L")
        #expect(abs(MetricUnits.kilograms(fromPounds: 162.5) - 73.709) < 0.001)
        #expect(abs(MetricUnits.pounds(fromKilograms: 75) - 165.347) < 0.001)
    }

    @Test func theSummaryGivesTheLatestValueAndTheChangeOver30Days() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }
        let points = [MetricPoint(date: day(0), value: 165), MetricPoint(date: day(10), value: 164),
                      MetricPoint(date: day(25), value: 163), MetricPoint(date: day(40), value: 162)]
        let summary = try #require(MetricStats.summary(of: points))
        #expect(summary.latest == 162 && summary.latestDate == day(40))
        #expect(summary.change30 == -2)
        #expect(summary.minimum == 162 && summary.maximum == 165)
        #expect(summary.average == 163.5 && summary.count == 4)
        #expect(MetricStats.summary(of: [points[0]])?.change30 == nil)
        #expect(MetricStats.summary(of: []) == nil)
    }
}
