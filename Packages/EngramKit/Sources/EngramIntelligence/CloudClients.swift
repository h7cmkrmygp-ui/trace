import EngramCore
import Foundation

// Services en ligne gratuits pour classer les notes : Gemini (notes neutres) et Groq (notes personnelles).
// Seul le texte de LA note à classer et les noms de catégories sont envoyés — jamais l'historique, jamais l'audio.
// Les clés sont collées par le propriétaire (trousseau de l'iPhone) et passent dans un en-tête, jamais dans l'adresse.

public enum CloudError: Error, Equatable, Sendable {
    /// Aucune clé enregistrée pour ce service.
    case missingKey
    /// Clé refusée par le service.
    case invalidKey
    /// Quota gratuit atteint (délai avant de réessayer, s'il est connu).
    case quotaExceeded(retryAfter: TimeInterval?)
    /// Pas de réseau ou service injoignable.
    case network
    /// Le service refuse de traiter cette note (garde-fous).
    case refused
    /// Autre erreur HTTP du service.
    case service(Int)
    /// Réponse inutilisable.
    case invalidOutput
}

/// Envoi HTTP (URLSession dans l'app, faux transport dans les tests).
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CloudError.network }
            return (data, http)
        } catch let error as CloudError {
            throw error
        } catch {
            throw CloudError.network
        }
    }
}

/// Moment de la dictée : les expressions comme « demain » sont recopiées par le service, puis calculées par Engram.
public struct CloudContext: Sendable {
    public let now: Date
    public let timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }
}

// MARK: - Consignes

public enum CloudPrompt {
    public static let version = "p4-cloud-v1"

    public static let system = """
        You are the filing engine of Engram, a personal memory app. The owner dictates or types notes in Québec French, \
        often mixed with English words. Understand the full meaning of each note, as a thoughtful human assistant would; \
        never classify by keywords alone.

        Return one item per distinct subject. Never split a sentence, or a request, that is about a single subject. \
        A reminder about the same thing belongs to that same item: in "rappelle-moi de demander congé le 24 novembre, \
        rappelle-moi ça demain", "demain" is the reminder date of the same task, not a second note. \
        Two unrelated subjects ("call the garage, and buy milk") are two items.

        For each item:
        - excerpt: the exact words of the note for this item, copied verbatim (same spelling, same language, no translation, no correction).
        - title: at most 8 words, in the owner's own language and words.
        - summary: one sentence keeping dates, amounts and conditions; empty when the title says it all.
        - kind: task (something to do), appointment (something at a given time or place), idea, decision, preference, \
        info (a fact to remember, such as a measurement), other.
        - category: a broad life domain written in French, such as Santé, Travail, Finance, Maison, Famille, Automobile, \
        Achats, Alimentation, Loisirs, Sport, Voyages, Études, Projets. Reuse an existing category exactly when one fits; \
        create a new one only when none fits. A body measurement (weight, sleep, blood pressure) belongs to Santé. \
        A weight in pounds ("livres") is not money and not a book. Money spent, owed or earned belongs to Finance.
        - categoryDescription: when the category is new, one short French sentence describing what it will contain; otherwise empty.
        - subcategory: only for a specific named thing that will recur (a car model, a project, a recurring topic); usually empty.
        - tags: up to 3 short French tags.
        - dates: every date or time expression copied verbatim from the note, with its role: reminder (when to remind the owner), \
        deadline, event (when something happens), other.

        Never invent facts, dates, names or amounts that are not in the note. Keep the owner's words.
        """

    public static func user(text: String, categories: [String], context: CloudContext) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.timeZone = context.timeZone
        formatter.dateFormat = "EEEE d MMMM yyyy"
        let existing = categories.isEmpty ? "aucune pour l'instant" : categories.joined(separator: " ; ")
        return """
            Aujourd'hui : \(formatter.string(from: context.now)) (fuseau \(context.timeZone.identifier)).
            Catégories existantes : \(existing)
            Note à classer :
            <note>
            \(text)
            </note>
            """
    }
}

// MARK: - Schéma de réponse

enum CloudSchema {
    enum Style { case gemini, strictJSONSchema }

    static func response(_ style: Style) -> [String: Any] {
        let date = object(style, [
            ("phrase", string(style)),
            ("role", string(style, allowed: ["reminder", "deadline", "event", "other"])),
        ])
        let note = object(style, [
            ("title", string(style)),
            ("summary", string(style)),
            ("excerpt", string(style)),
            ("kind", string(style, allowed: ["idea", "task", "appointment", "decision", "preference", "info", "other"])),
            ("category", string(style)),
            ("categoryDescription", string(style)),
            ("subcategory", string(style)),
            ("tags", array(style, of: string(style))),
            ("dates", array(style, of: date)),
        ])
        return object(style, [("notes", array(style, of: note))])
    }

    private static func string(_ style: Style, allowed: [String]? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": style == .gemini ? "STRING" : "string"]
        if let allowed { schema["enum"] = allowed }
        return schema
    }

    private static func array(_ style: Style, of items: [String: Any]) -> [String: Any] {
        ["type": style == .gemini ? "ARRAY" : "array", "items": items]
    }

    private static func object(_ style: Style, _ properties: [(String, [String: Any])]) -> [String: Any] {
        var schema: [String: Any] = [
            "type": style == .gemini ? "OBJECT" : "object",
            "properties": Dictionary(uniqueKeysWithValues: properties),
            "required": properties.map(\.0),
        ]
        switch style {
        case .gemini: schema["propertyOrdering"] = properties.map(\.0)
        case .strictJSONSchema: schema["additionalProperties"] = false
        }
        return schema
    }
}

// MARK: - Décodage

public enum CloudDecoder {
    struct Payload: Decodable { let notes: [Note] }

    struct Note: Decodable {
        let title: String
        let summary: String?
        let excerpt: String
        let kind: String?
        let category: String?
        let categoryDescription: String?
        let subcategory: String?
        let tags: [String]?
        let dates: [Mention]?
    }

    struct Mention: Decodable {
        let phrase: String
        let role: String?
    }

    public static func decode(_ text: String) throws -> ThoughtAnalysis {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
                .joined(separator: "\n")
            if let fence = cleaned.range(of: "```", options: .backwards) { cleaned = String(cleaned[..<fence.lowerBound]) }
        }
        guard let data = cleaned.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw CloudError.invalidOutput
        }
        return ThoughtAnalysis(thoughts: payload.notes.map(convert))
    }

    static func convert(_ note: Note) -> AnalyzedThought {
        func clean(_ value: String?) -> String? {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        // Le rappel d'abord : c'est lui qui donne l'échéance de la note.
        let order = ["reminder": 0, "deadline": 1, "event": 2]
        let dates = (note.dates ?? []).enumerated()
            .sorted { (order[$0.element.role ?? ""] ?? 3, $0.offset) < (order[$1.element.role ?? ""] ?? 3, $1.offset) }
            .map(\.element.phrase)
        return AnalyzedThought(title: note.title, summary: clean(note.summary), excerpt: note.excerpt,
                               kind: MemoryKind(rawValue: note.kind ?? "") ?? .other,
                               tags: Array((note.tags ?? []).prefix(3)), mentionedDates: dates,
                               category: clean(note.category) ?? "", subcategory: clean(note.subcategory),
                               categoryDescription: clean(note.categoryDescription))
    }
}

func lowercasedHeaders(_ response: HTTPURLResponse) -> [String: String] {
    var headers: [String: String] = [:]
    for (key, value) in response.allHeaderFields {
        if let key = key as? String { headers[key.lowercased()] = "\(value)" }
    }
    return headers
}

// MARK: - Gemini

public struct GeminiClient: Sendable {
    public static let base = "https://generativelanguage.googleapis.com/v1beta"
    public let apiKey: String
    let transport: any HTTPTransport

    public init(apiKey: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    public static func makeRequest(model: String, apiKey: String, system: String, user: String) throws -> URLRequest {
        guard let url = URL(string: "\(base)/models/\(model):generateContent") else { throw CloudError.invalidOutput }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": user]]]],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json",
                "responseSchema": CloudSchema.response(.gemini),
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public static func parse(data: Data, status: Int, headers: [String: String]) throws -> String {
        guard (200..<300).contains(status) else { throw error(data: data, status: status) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CloudError.invalidOutput }
        if let feedback = root["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil { throw CloudError.refused }
        guard let candidate = (root["candidates"] as? [[String: Any]])?.first else { throw CloudError.invalidOutput }
        if let reason = candidate["finishReason"] as? String,
           ["SAFETY", "PROHIBITED_CONTENT", "SPII", "BLOCKLIST", "RECITATION"].contains(reason) {
            throw CloudError.refused
        }
        let parts = ((candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CloudError.invalidOutput }
        return text
    }

    static func error(data: Data, status: Int) -> CloudError {
        let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
        let message = body?["message"] as? String ?? ""
        let details = body?["details"] as? [[String: Any]] ?? []
        switch status {
        case 401, 403:
            return .invalidKey
        case 400 where message.localizedCaseInsensitiveContains("api key")
            || details.contains(where: { ($0["reason"] as? String) == "API_KEY_INVALID" }):
            return .invalidKey
        case 429:
            let delay = details.compactMap { $0["retryDelay"] as? String }.first
                .flatMap { TimeInterval($0.trimmingCharacters(in: CharacterSet(charactersIn: "s"))) }
            return .quotaExceeded(retryAfter: delay)
        default:
            return (body?["status"] as? String) == "RESOURCE_EXHAUSTED" ? .quotaExceeded(retryAfter: nil) : .service(status)
        }
    }

    public func generate(model: String, system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else { throw CloudError.missingKey }
        let request = try Self.makeRequest(model: model, apiKey: apiKey, system: system, user: user)
        let (data, response) = try await transport.send(request)
        return try Self.parse(data: data, status: response.statusCode, headers: lowercasedHeaders(response))
    }

    /// Modèles accessibles avec cette clé (sert aussi à tester la clé).
    public func listModels() async throws -> [String] {
        guard !apiKey.isEmpty else { throw CloudError.missingKey }
        guard let url = URL(string: "\(Self.base)/models?pageSize=200") else { throw CloudError.invalidOutput }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw Self.error(data: data, status: response.statusCode) }
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((root?["models"] as? [[String: Any]]) ?? []).compactMap { model in
            let methods = model["supportedGenerationMethods"] as? [String] ?? []
            return methods.contains("generateContent") ? model["name"] as? String : nil
        }
    }
}

/// Choisit les modèles Flash et Flash-Lite stables les plus récents parmi ceux de la clé.
public enum GeminiModelPicker {
    public static func pick(from names: [String]) -> (primary: String?, lite: String?) {
        var flash: [(version: [Int], id: String)] = []
        var lite: [(version: [Int], id: String)] = []
        let pattern = try? NSRegularExpression(pattern: #"^gemini-(\d+(?:\.\d+)*)-flash(-lite)?$"#)
        for raw in names {
            let id = raw.hasPrefix("models/") ? String(raw.dropFirst("models/".count)) : raw
            guard let pattern, let match = pattern.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
                  let versionRange = Range(match.range(at: 1), in: id) else { continue }
            let version = id[versionRange].split(separator: ".").compactMap { Int($0) }
            if match.range(at: 2).location != NSNotFound { lite.append((version, id)) } else { flash.append((version, id)) }
        }
        func newest(_ list: [(version: [Int], id: String)]) -> String? {
            list.max { $0.version.lexicographicallyPrecedes($1.version) }?.id
        }
        return (newest(flash), newest(lite))
    }
}

// MARK: - Groq

public struct GroqClient: Sendable {
    public static let base = "https://api.groq.com/openai/v1"
    /// Modèle ouvert d'OpenAI hébergé par Groq ; prend en charge la sortie JSON stricte.
    public static let model = "openai/gpt-oss-120b"
    public let apiKey: String
    let transport: any HTTPTransport

    public init(apiKey: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    public static func makeRequest(apiKey: String, system: String, user: String) throws -> URLRequest {
        guard let url = URL(string: "\(base)/chat/completions") else { throw CloudError.invalidOutput }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "engram_notes", "strict": true, "schema": CloudSchema.response(.strictJSONSchema)],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public static func parse(data: Data, status: Int, headers: [String: String]) throws -> String {
        guard (200..<300).contains(status) else {
            switch status {
            case 401, 403: throw CloudError.invalidKey
            case 429: throw CloudError.quotaExceeded(retryAfter: headers["retry-after"].flatMap { TimeInterval($0) })
            default: throw CloudError.service(status)
            }
        }
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = ((root?["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any]
        guard let content = message?["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CloudError.invalidOutput }
        return content
    }

    public func generate(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else { throw CloudError.missingKey }
        let request = try Self.makeRequest(apiKey: apiKey, system: system, user: user)
        let (data, response) = try await transport.send(request)
        return try Self.parse(data: data, status: response.statusCode, headers: lowercasedHeaders(response))
    }

    /// Teste la clé (liste des modèles).
    public func checkKey() async throws {
        guard !apiKey.isEmpty else { throw CloudError.missingKey }
        guard let url = URL(string: "\(Self.base)/models") else { throw CloudError.invalidOutput }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        // Une réponse d'erreur est traduite (clé invalide, quota…) ; une réponse 2xx suffit à valider la clé.
        guard (200..<300).contains(response.statusCode) else {
            _ = try Self.parse(data: data, status: response.statusCode, headers: lowercasedHeaders(response))
            return
        }
    }
}

// MARK: - Analyseurs

/// Classement par Gemini (notes neutres uniquement — le routage s'en assure). Flash, puis Flash-Lite si le quota est atteint.
public struct GeminiThoughtAnalyzer: MemoryAnalyzer {
    public static let providerName = "gemini"
    let client: GeminiClient
    let models: [String]

    public init(client: GeminiClient, models: [String]) {
        self.client = client
        self.models = models
    }

    public func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis {
        try await analyze(text: text, existingCategories: existingCategories,
                          context: CloudContext(now: Date(), timeZone: .current))
    }

    public func analyze(text: String, existingCategories: [String], context: CloudContext) async throws -> ThoughtAnalysis {
        let user = CloudPrompt.user(text: text, categories: existingCategories, context: context)
        var lastError = CloudError.missingKey
        for model in models {
            do {
                return try CloudDecoder.decode(try await client.generate(model: model, system: CloudPrompt.system, user: user))
            } catch let error as CloudError {
                lastError = error
                switch error {
                case .quotaExceeded, .service: continue
                default: throw error
                }
            }
        }
        throw lastError
    }
}

/// Classement par Groq (notes personnelles : Groq n'entraîne aucun modèle avec les données envoyées).
public struct GroqThoughtAnalyzer: MemoryAnalyzer {
    public static let providerName = "groq"
    let client: GroqClient

    public init(client: GroqClient) {
        self.client = client
    }

    public func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis {
        try await analyze(text: text, existingCategories: existingCategories,
                          context: CloudContext(now: Date(), timeZone: .current))
    }

    public func analyze(text: String, existingCategories: [String], context: CloudContext) async throws -> ThoughtAnalysis {
        let user = CloudPrompt.user(text: text, categories: existingCategories, context: context)
        return try CloudDecoder.decode(try await client.generate(system: CloudPrompt.system, user: user))
    }
}
