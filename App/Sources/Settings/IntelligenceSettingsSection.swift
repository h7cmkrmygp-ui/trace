import EngramIntelligence
import EngramStore
import SwiftUI

/// Réglages › Intelligence : clés Gemini et Groq (collées par le propriétaire, rangées dans le trousseau),
/// santé gardée sur l'iPhone, quotas du jour et répartition des notes du mois.
struct IntelligenceSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var geminiKey = ""
    @State private var groqKey = ""
    @State private var hasGemini = false
    @State private var hasGroq = false
    @State private var geminiMessage: String?
    @State private var groqMessage: String?
    @State private var healthStaysLocal = false
    @State private var keepEverythingLocal = false
    @State private var counts: [String: Int] = [:]
    @State private var isWorking = false
    private let apple = AppleThoughtAnalyzer.availabilityDescription()

    var body: some View {
        Section {
            LabeledContent("IA d'Apple (sur l'iPhone)", value: apple.text)
            Toggle("Tout garder sur l'iPhone", isOn: $keepEverythingLocal)
                .tint(.green)
                .onChange(of: keepEverythingLocal) { _, value in model.perform { try model.settings.set(value, for: .keepEverythingLocal) } }
            if !keepEverythingLocal {
                Toggle("Santé : garder sur l'iPhone", isOn: $healthStaysLocal)
                    .tint(.green)
                    .onChange(of: healthStaysLocal) { _, value in model.perform { try model.settings.set(value, for: .healthStaysLocal) } }
            }
            if !counts.isEmpty {
                LabeledContent("Ce mois-ci", value: Self.summary(counts))
            }
            NavigationLink(value: NotesRoute.evaluation) {
                Label("Évaluer le classement sur l'iPhone", systemImage: "checklist")
            }
        } header: {
            Text("Intelligence")
        } footer: {
            Text("Avant tout envoi, ton iPhone vérifie chaque note. Neutre (rien de personnel) : Gemini. Personnelle : Groq. Secrète, « Garder sur l'iPhone » ou en cas de doute : l'IA d'Apple, sans rien envoyer. Le texte original reste toujours sur l'iPhone.")
        }

        keySection(title: "Gemini — notes neutres", account: .gemini, key: $geminiKey, hasKey: hasGemini,
                   message: geminiMessage, usage: model.quota.usage(GeminiThoughtAnalyzer.providerName),
                   pausedUntil: model.quota.pausedUntil(GeminiThoughtAnalyzer.providerName),
                   links: [("Créer une clé (Google AI Studio)", "https://aistudio.google.com/apikey"),
                           ("Voir mon quota gratuit", "https://aistudio.google.com/rate-limit")],
                   footer: "Gratuit, sans carte de crédit : n'associe jamais de facturation à ton projet. En version gratuite, Google peut utiliser et faire lire par des humains ce qu'il reçoit : c'est pourquoi seules les notes jugées neutres lui sont envoyées.")

        keySection(title: "Groq — notes personnelles", account: .groq, key: $groqKey, hasKey: hasGroq,
                   message: groqMessage, usage: model.quota.usage(GroqThoughtAnalyzer.providerName),
                   pausedUntil: model.quota.pausedUntil(GroqThoughtAnalyzer.providerName),
                   links: [("Créer une clé (console Groq)", "https://console.groq.com/keys"),
                           ("Activer « Zero Data Retention »", "https://console.groq.com/settings/data-controls")],
                   footer: "Gratuit, sans carte. Groq n'entraîne aucun modèle avec tes notes ; active « Zero Data Retention » pour qu'il ne garde rien. Sans clé Groq, les notes personnelles sont classées sur l'iPhone.")
            .onAppear(perform: load)
    }

    @ViewBuilder
    private func keySection(title: String, account: SecretStore.Account, key: Binding<String>, hasKey: Bool,
                            message: String?, usage: Int, pausedUntil: Date?, links: [(String, String)],
                            footer: String) -> some View {
        Section {
            if hasKey {
                LabeledContent("Clé", value: "Enregistrée sur l'iPhone")
                LabeledContent("Analyses aujourd'hui", value: "\(usage)")
                if let pausedUntil {
                    Text("Quota gratuit atteint : reprise vers \(pausedUntil.formatted(date: .omitted, time: .shortened)). En attendant, les notes sont classées sur l'iPhone puis reclassées.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Tester") { run(account) { await model.testCloudKey(account) } }
                    Spacer()
                    Button("Supprimer la clé", role: .destructive) { run(account) { await model.saveCloudKey("", for: account) } }
                        .tint(.red)
                }
                .buttonStyle(.borderless)
                .disabled(isWorking)
            } else {
                SecureField("Colle ta clé ici", text: key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Enregistrer et tester") {
                    let value = key.wrappedValue
                    key.wrappedValue = ""
                    run(account) { await model.saveCloudKey(value, for: account) }
                }
                .disabled(isWorking || key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(links, id: \.1) { link in
                if let url = URL(string: link.1) {
                    Link(link.0, destination: url).font(.footnote)
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }

    private func run(_ account: SecretStore.Account, _ action: @escaping () async -> String) {
        isWorking = true
        Task {
            let message = await action()
            switch account {
            case .gemini: geminiMessage = message
            case .groq: groqMessage = message
            case .backupPassword: break
            }
            isWorking = false
            load()
        }
    }

    private func load() {
        hasGemini = SecretStore.hasKey(.gemini)
        hasGroq = SecretStore.hasKey(.groq)
        healthStaysLocal = (try? model.settings.bool(.healthStaysLocal, default: false)) ?? false
        keepEverythingLocal = (try? model.settings.bool(.keepEverythingLocal, default: false)) ?? false
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        counts = (try? model.memories.routeCounts(since: monthAgo)) ?? [:]
    }

    /// « Gemini 12 · Groq 30 · iPhone 8 ».
    static func summary(_ counts: [String: Int]) -> String {
        [("gemini", "Gemini"), ("groq", "Groq"), ("apple", "iPhone")]
            .compactMap { key, label in counts[key].map { "\(label) \($0)" } }
            .joined(separator: " · ")
    }
}
