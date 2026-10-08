import EngramCapture
import EngramStore
import SwiftUI

/// Réglages › Transcription : moteur, modèle Whisper (téléchargement), vérification avant classement, retranscription.
struct TranscriptionSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var engine: TranscriptionEngine = .default
    @State private var whisperModel: WhisperModel = .default
    @State private var strategy: TranscriptionStrategy = .default
    @State private var review = true
    @State private var downloaded: Set<WhisperModel> = []
    @State private var retranscription: (done: Int, total: Int)?
    @State private var retranscriptionResult: String?
    @State private var isConfirmingRetranscribeAll = false

    var body: some View {
        Section {
            Picker("Moteur", selection: $engine) {
                ForEach(TranscriptionEngine.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: engine) { _, value in model.perform { try model.settings.set(value.rawValue, for: .transcriptionEngine) } }
            if engine == .whisper {
                Picker("Modèle utilisé", selection: $whisperModel) {
                    ForEach(WhisperModel.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: whisperModel) { _, value in model.perform { try model.settings.set(value.rawValue, for: .whisperModel) } }
                ForEach(WhisperModel.allCases) { modelRow($0) }
                Picker("Langues", selection: $strategy) {
                    ForEach(TranscriptionStrategy.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: strategy) { _, value in model.perform { try model.settings.set(value.rawValue, for: .whisperStrategy) } }
                NavigationLink(value: NotesRoute.benchmark) {
                    Label("Banc d'essai : Turbo ou Large V3", systemImage: "gauge.with.dots.needle.50percent")
                }
            }
            Toggle("Vérifier avant de classer", isOn: $review)
                .onChange(of: review) { _, value in model.perform { try model.settings.set(value, for: .reviewBeforeFiling) } }
            if engine == .whisper && downloaded.contains(whisperModel) {
                Button {
                    isConfirmingRetranscribeAll = true
                } label: {
                    HStack {
                        Label("Retranscrire mes anciennes notes", systemImage: "waveform")
                        if let retranscription {
                            Spacer()
                            Text("\(retranscription.done)/\(retranscription.total)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(retranscription != nil)
            }
            if let retranscriptionResult {
                Text(retranscriptionResult).font(.footnote).foregroundStyle(.secondary)
            }
            if let notice = model.transcriptionNotice {
                Text(notice).font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Transcription")
        } footer: {
            Text("Whisper fonctionne sur ton iPhone, gratuitement et sans rien envoyer. Il comprend le français québécois et l'anglais mélangés et ne traduit jamais. Le modèle se télécharge une seule fois (Wi-Fi conseillé, garde l'app ouverte pendant le téléchargement).")
        }
        .onAppear(perform: load)
        .confirmationDialog("Retranscrire avec Whisper ?", isPresented: $isConfirmingRetranscribeAll, titleVisibility: .visible) {
            Button("Retranscrire mes notes vocales") { Task { await retranscribeAll() } }
        } message: {
            Text("Whisper relit l'audio de tes anciennes notes vocales, puis elles sont reclassées. Les notes que tu as modifiées à la main restent telles quelles.")
        }
    }

    private func modelRow(_ item: WhisperModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                Text("\(item.approximateSizeMB) Mo").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if model.preparingModels.contains(item) {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("Préparation…").font(.footnote).foregroundStyle(.secondary)
                }
            } else if let progress = model.modelDownloads[item] {
                ProgressView(value: progress)
                    .frame(width: 90)
                    .accessibilityLabel("Téléchargement \(Int(progress * 100)) %")
            } else if downloaded.contains(item) {
                Menu {
                    Button("Supprimer le modèle", systemImage: "trash", role: .destructive) {
                        Task {
                            await model.deleteWhisperModel(item)
                            refreshDownloaded()
                        }
                    }
                } label: {
                    Label("Sur l'iPhone", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Button("Télécharger") {
                    Task {
                        await model.downloadWhisperModel(item)
                        refreshDownloaded()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func load() {
        engine = model.transcriptionEngine
        whisperModel = model.whisperModel
        strategy = model.whisperStrategy
        review = model.reviewsBeforeFiling
        refreshDownloaded()
    }

    private func refreshDownloaded() {
        downloaded = Set(WhisperModel.allCases.filter { model.whisperModels.isDownloaded($0) })
    }

    private func retranscribeAll() async {
        retranscriptionResult = nil
        retranscription = (0, 0)
        let count = await model.retranscribeAll { done, total in retranscription = (done, total) }
        retranscription = nil
        retranscriptionResult = count == 0 ? "Aucune note à retranscrire." : "\(count) note\(count > 1 ? "s" : "") retranscrite\(count > 1 ? "s" : "") et reclassée\(count > 1 ? "s" : "")."
    }
}
