import EngramCapture
import EngramCore
import EngramIntelligence
import SwiftUI

/// Réponse de « Retrouver » : les vraies notes trouvées, puis la phrase d'Engram (nil pendant qu'elle s'écrit).
struct RecallReply: Sendable {
    var answer: String?
    let hits: [RecallHit]
    /// La question telle qu'elle a été comprise (la suivante peut l'affiner).
    let query: RecallQuery
}

/// « Retrouver » : on demande à sa mémoire, par écrit ou à voix haute, comme dans une conversation.
@MainActor
@Observable
final class RecallModel {
    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        var reply: RecallReply?
    }

    private(set) var exchanges: [Exchange] = []
    var draft = ""
    private(set) var isTranscribing = false
    private(set) var notice: String?
    let recorder = VoiceRecorder()

    var isListening: Bool { recorder.state != .idle }
    var isBusy: Bool { isTranscribing || exchanges.last.map { $0.reply?.answer == nil } ?? false }

    /// Les questions dictées sont des fichiers temporaires, hors du dossier Engram : jamais prises pour des notes.
    private static var questionsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("RecallQuestions", isDirectory: true)
    }

    func ask(_ text: String, app: AppModel) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy else { return }
        draft = ""
        notice = nil
        let previous = exchanges.last?.reply?.query
        exchanges.append(Exchange(question: question))
        let id = exchanges[exchanges.count - 1].id
        // Les notes d'abord (tout de suite), puis la phrase de réponse.
        let result = await app.recallSearch(question, after: previous)
        guard let index = exchanges.firstIndex(where: { $0.id == id }) else { return }
        exchanges[index].reply = RecallReply(answer: nil, hits: result.hits, query: result.query)
        let answer = await app.recallAnswer(question, result: result)
        if let index = exchanges.firstIndex(where: { $0.id == id }) { exchanges[index].reply?.answer = answer }
    }

    func clear() {
        exchanges = []
        notice = nil
    }

    /// Toucher le micro : écouter la question ; s'arrête tout seul après 2 s de silence, ou au deuxième toucher.
    func toggleListening(app: AppModel) async {
        if isListening {
            await finishListening(app: app)
            return
        }
        guard await VoiceRecorder.requestPermission() else {
            notice = "Autorise le micro : Réglages › Engram › Micro."
            return
        }
        do {
            try FileManager.default.createDirectory(at: Self.questionsDirectory, withIntermediateDirectories: true)
            try recorder.start(in: Self.questionsDirectory, stopsOnSilence: true, silenceDuration: 2)
            notice = nil
        } catch {
            notice = "Impossible d'écouter pour l'instant."
        }
    }

    func finishListening(app: AppModel) async {
        guard let result = recorder.stop() else { return }
        isTranscribing = true
        defer {
            try? FileManager.default.removeItem(at: result.url)
            isTranscribing = false
        }
        do {
            let text = try await app.transcribeQuestion(url: result.url).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                notice = "Je n'ai rien entendu. Réessaie, ou écris ta question."
                return
            }
            isTranscribing = false
            await ask(text, app: app)
        } catch {
            notice = "Je n'ai pas compris la question. Réessaie, ou écris-la."
        }
    }
}

struct RecallView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = RecallModel()
    @FocusState private var isFieldFocused: Bool

    static let suggestions = [
        "Qu'est-ce que j'ai à faire aujourd'hui ?",
        "Mes tâches de cette semaine",
        "Mes idées récentes",
        "Résume ce que j'ai noté cette semaine",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if model.exchanges.isEmpty { intro }
                        ForEach(model.exchanges) { exchange in
                            ExchangeView(exchange: exchange).id(exchange.id)
                        }
                    }
                    .padding(16)
                    .animation(reduceMotion ? nil : .snappy, value: model.exchanges.map { $0.reply?.hits.count ?? -1 })
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.exchanges.last?.reply?.answer) { _, _ in
                    if let last = model.exchanges.last?.id { withAnimation { proxy.scrollTo(last, anchor: .top) } }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Retrouver")
            .toolbar {
                if !model.exchanges.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Nouvelle recherche", systemImage: "square.and.pencil") { model.clear() }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .onChange(of: model.recorder.state) { _, state in
                // Silence après la question : on la traite tout de suite.
                if state == .finished { Task { await model.finishListening(app: app) } }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Demande à ta mémoire")
                    .font(.title2.weight(.semibold))
                Text("Pose ta question comme tu la dirais, même vague : Engram cherche dans tes notes, sur ton iPhone. Rien n'est envoyé.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        Task { await model.ask(suggestion, app: app) }
                    } label: {
                        Label(suggestion, systemImage: "text.magnifyingglass")
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let notice = model.notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                TextField(model.isListening ? "Je t'écoute…" : model.isTranscribing ? "Je transcris ta question…" : "Demande à ta mémoire…",
                          text: $model.draft)
                    .focused($isFieldFocused)
                    .submitLabel(.search)
                    .onSubmit(send)
                    .disabled(model.isListening || model.isTranscribing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                if model.draft.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(model.isListening ? "Arrêter" : "Dicter ta question",
                           systemImage: model.isListening ? "stop.fill" : "mic.fill") {
                        Task { await model.toggleListening(app: app) }
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(model.isListening ? Color.red : Color.primary)
                    .disabled(model.isTranscribing || (model.isBusy && !model.isListening))
                    .sensoryFeedback(.impact(weight: .light), trigger: model.isListening)
                } else {
                    Button("Chercher", systemImage: "arrow.up.circle.fill", action: send)
                        .labelStyle(.iconOnly)
                        .font(.title)
                        .frame(width: 44, height: 44)
                        .disabled(model.isBusy)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        isFieldFocused = false
        let text = model.draft
        Task { await model.ask(text, app: app) }
    }
}

/// Une question et sa réponse : la phrase d'Engram, puis les notes trouvées (on les touche pour les ouvrir).
private struct ExchangeView: View {
    let exchange: RecallModel.Exchange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 48)
                Text(exchange.question)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if let reply = exchange.reply {
                if let answer = reply.answer {
                    Label {
                        Text(answer)
                    } icon: {
                        Image(systemName: reply.hits.isEmpty ? "questionmark.circle" : "brain")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("J'écris la réponse…").foregroundStyle(.secondary)
                    }
                }
                ForEach(reply.hits, id: \.document.id) { hit in
                    NavigationLink(value: hit.document.id) { RecallHitRow(document: hit.document) }
                        .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Je cherche dans ta mémoire…").foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Une note trouvée : titre, type, date où elle a été notée, échéance et dossier.
struct RecallHitRow: View {
    let document: RecallDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(for: document.kind))
                .font(.body)
                .frame(width: 32, height: 32)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts = ["Notée \(document.capturedAt.formatted(.relative(presentation: .named)))"]
        if let due = document.dueAt { parts.append("pour le \(due.formatted(.dateTime.weekday(.wide).day().month(.wide)))") }
        if document.status == .archived { parts.append("faite") }
        if let folder = document.categories.first { parts.append(folder) }
        return parts.joined(separator: " · ")
    }

    static func symbol(for kind: MemoryKind?) -> String {
        switch kind {
        case .task: "checklist"
        case .appointment: "calendar"
        case .idea: "lightbulb"
        case .decision: "checkmark.seal"
        case .preference: "heart"
        case .info: "info.circle"
        case .other, nil: "note.text"
        }
    }
}
