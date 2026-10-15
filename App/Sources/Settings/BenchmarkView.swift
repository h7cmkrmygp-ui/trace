import EngramCapture
import EngramCore
import SwiftUI

/// Banc d'essai : lire les 40 phrases, lancer la comparaison, voir les mesures et valider (ou non) un changement.
struct BenchmarkView: View {
    @Environment(AppModel.self) private var app
    @State private var bench = BenchmarkModel()
    @State private var isConfirmingReset = false

    private var isRecording: Bool { bench.recorder.state != .idle }

    var body: some View {
        Form {
            readingSection
            Section {
                LabeledContent("Notes réelles corrigées", value: "\(bench.notes.count) / \(ModelRecommendation.minimumCorrectedNotes)")
            } footer: {
                Text("Chaque correction faite dans « Vérifie ta note » sert de référence fiable. Il en faut au moins \(ModelRecommendation.minimumCorrectedNotes).")
            }
            comparisonSection
            if bench.rows.contains(where: { $0.wordErrorRate != nil }) { resultsSection }
            recommendationSection
            Section {
                Button("Effacer le banc d'essai", role: .destructive) { isConfirmingReset = true }
                    .disabled(bench.isRunning || isRecording)
            } footer: {
                Text("Les enregistrements des phrases restent sur ton iPhone et ne sont jamais envoyés ni exportés.")
            }
        }
        .navigationTitle("Banc d'essai")
        .onAppear { bench.load(app: app) }
        .task { bench.supportedModels = await WhisperModelStore.supportedModelsOnThisDevice() }
        .onDisappear { if isRecording { bench.cancelRecording() } }
        .confirmationDialog("Effacer les phrases lues et les résultats ?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Effacer", role: .destructive) { bench.reset(app: app) }
        }
    }

    @ViewBuilder private var readingSection: some View {
        Section {
            LabeledContent("Phrases lues", value: "\(bench.saved.sentences.count) / \(BilingualTestSet.sentences.count)")
            if let sentence = bench.nextSentence {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lis cette phrase naturellement :").font(.footnote).foregroundStyle(.secondary)
                    Text(sentence.text).font(.title3)
                    HStack {
                        Button(isRecording ? "Terminer" : "Lire à voix haute",
                               systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill") {
                            if isRecording {
                                bench.stopRecording(sentence: sentence, app: app)
                            } else {
                                Task { await bench.startRecording(app: app) }
                            }
                        }
                        .buttonStyle(.prominent)
                        .tint(isRecording ? .red : .accentColor)
                        if isRecording {
                            Text(RecordView.clock(bench.recorder.elapsed)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                Label("Toutes les phrases sont lues.", systemImage: "checkmark.circle")
            }
            if !bench.saved.sentences.isEmpty && !isRecording {
                Button("Recommencer la dernière phrase", systemImage: "arrow.counterclockwise") { bench.redoLastSentence(app: app) }
                    .disabled(bench.isRunning)
            }
            if let message = bench.statusMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Jeu d'essai")
        } footer: {
            Text("Quarante phrases inventées : français québécois, anglais et mélange des deux, comme tu parles.")
        }
    }

    @ViewBuilder private var comparisonSection: some View {
        Section {
            if let progress = bench.progress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text("Transcriptions \(progress.done) / \(progress.total)")
                }
                Button("Interrompre", role: .cancel) { bench.cancelComparison() }
            } else {
                Button("Lancer la comparaison", systemImage: "play.fill") { bench.startComparison(app: app) }
                    .disabled(isRecording || (bench.saved.sentences.isEmpty && bench.notes.isEmpty))
            }
        } header: {
            Text("Comparaison")
        } footer: {
            Text("Les deux modèles et les trois stratégies transcrivent chaque enregistrement. Garde l'app ouverte ; débranche l'iPhone pour que la batterie soit mesurée.")
        }
    }

    private var resultsSection: some View {
        Section("Résultats") {
            ForEach(bench.rows.filter { $0.wordErrorRate != nil }) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(row.model.label) · \(row.strategy.label)").font(.subheadline.weight(.semibold))
                    HStack(spacing: 12) {
                        metric("Erreurs", row.wordErrorRate.map { Self.percent($0) })
                        metric("Mots anglais gardés", row.englishRetention.map { Self.percent($0) })
                    }
                    HStack(spacing: 12) {
                        metric("Vitesse", row.realTimeFactor.map { String(format: "%.2f × temps réel", $0) })
                        metric("Batterie", row.batteryPerMinute.map { String(format: "%.1f %%/min", $0) } ?? "non mesurée")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func metric(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value ?? "—").font(.footnote.monospacedDigit())
        }
    }

    @ViewBuilder private var recommendationSection: some View {
        let modelAdvice = bench.modelRecommendation(app: app)
        Section {
            verdictRow(title: "Modèle : \(modelAdvice.model.label) ?", verdict: modelAdvice.verdict) {
                app.perform { try app.settings.set(modelAdvice.model.rawValue, for: .whisperModel) }
                bench.load(app: app)
            }
            if let strategyAdvice = bench.strategyRecommendation(app: app) {
                verdictRow(title: "Stratégie : \(strategyAdvice.strategy.label) ?", verdict: strategyAdvice.verdict) {
                    app.perform { try app.settings.set(strategyAdvice.strategy.rawValue, for: .whisperStrategy) }
                    bench.load(app: app)
                }
            }
        } header: {
            Text("Recommandation")
        } footer: {
            Text("Actuellement : \(app.whisperModel.label), \(app.whisperStrategy.label). Engram ne change rien sans ton accord.")
        }
    }

    @ViewBuilder private func verdictRow(title: String, verdict: ModelRecommendation, apply: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            switch verdict {
            case .needMoreData(let reason):
                Label(reason, systemImage: "hourglass").font(.footnote).foregroundStyle(.secondary)
            case .keepCurrent(let reason):
                Label(reason, systemImage: "equal.circle").font(.footnote).foregroundStyle(.secondary)
            case .proposeSwitch(let reason):
                Label(reason, systemImage: "arrow.up.circle").font(.footnote)
                Button("Valider ce changement", action: apply)
                    .buttonStyle(.prominent)
            }
        }
        .padding(.vertical, 2)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f %%", value * 100)
    }
}
