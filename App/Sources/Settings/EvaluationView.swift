import EngramCore
import EngramIntelligence
import SwiftUI

/// Mesure la qualité du classement **sur l'iPhone** avec des phrases **inventées**. Rien n'est enregistré dans la mémoire.
struct EvaluationView: View {
    struct Row: Identifiable {
        let id = UUID()
        let sentence: String
        let path: String
        let isAccepted: Bool
    }

    @State private var rows: [Row] = []
    @State private var isRunning = false
    @State private var problem: String?

    private var score: Int { rows.filter(\.isAccepted).count }

    var body: some View {
        List {
            Section {
                Button(isRunning ? "Évaluation en cours…" : "Lancer l'évaluation", systemImage: "play") {
                    Task { await run() }
                }
                .disabled(isRunning)
                if !rows.isEmpty {
                    LabeledContent("Catégories correctes", value: "\(score) / \(rows.count)")
                }
                if let problem {
                    Text(problem).foregroundStyle(.secondary)
                }
            } footer: {
                Text("\(EvaluationSet.cases.count) phrases inventées, en français et en anglais, classées par l'IA d'Apple sur ton iPhone. Rien n'est enregistré dans ta mémoire.")
            }
            Section {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.sentence)
                        Label(row.path, systemImage: row.isAccepted ? "checkmark" : "xmark")
                            .font(.footnote)
                            .foregroundStyle(row.isAccepted ? Color.secondary : Color.red)
                    }
                }
            }
        }
        .navigationTitle("Évaluation")
    }

    private func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        rows = []
        problem = nil
        let analyzer = AppleThoughtAnalyzer()
        var known: [String] = []
        for item in EvaluationSet.cases {
            do {
                let analysis = try await analyzer.analyze(text: item.sentence, existingCategories: known)
                let valid = try AnalysisValidator.validate(analysis, against: item.sentence)
                let path = valid.first?.categoryPath ?? []
                let display = path.joined(separator: " › ")
                if let root = path.first, !known.contains(root) { known.append(root) }
                if path.count == 2, !known.contains(display) { known.append(display) }
                // Quand le nombre de notes compte (un rappel ne doit pas devenir deux notes), il est vérifié aussi.
                let countIsRight = item.expectedNotes.map { $0 == valid.count } ?? true
                let label = display.isEmpty ? "(aucune catégorie)" : display
                rows.append(Row(sentence: item.sentence,
                                path: item.expectedNotes == nil ? label : "\(label) · \(valid.count) note\(valid.count > 1 ? "s" : "")",
                                isAccepted: item.accepts(categoryPath: path) && countIsRight))
            } catch AnalyzerError.unavailable(let reason) {
                problem = reason
                return
            } catch {
                rows.append(Row(sentence: item.sentence, path: "(échec de l'analyse)", isAccepted: false))
            }
        }
    }
}
