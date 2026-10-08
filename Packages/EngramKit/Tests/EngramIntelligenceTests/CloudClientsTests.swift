import EngramCore
import Foundation
import Testing
@testable import EngramIntelligence

/// Clients Gemini et Groq, testés sans réseau : requêtes construites, réponses et erreurs lues.
struct CloudClientsTests {
    static let context = CloudContext(now: Date(timeIntervalSince1970: 1_791_475_200), // 8 octobre 2026
                                      timeZone: TimeZone(identifier: "America/Toronto")!)

    func json(_ request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: - Gemini

    @Test func geminiRequestPutsTheKeyInAHeaderAndAsksForJSON() throws {
        let request = try GeminiClient.makeRequest(model: "gemini-3.8-flash", apiKey: "CLE-TEST",
                                                   system: "consignes", user: "Note : acheter du lait")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "CLE-TEST")
        #expect(!(request.url?.absoluteString.contains("CLE-TEST") ?? true))
        let body = try json(request)
        let system = try #require(body["systemInstruction"] as? [String: Any])
        #expect(((system["parts"] as? [[String: Any]])?.first?["text"] as? String) == "consignes")
        let contents = try #require(body["contents"] as? [[String: Any]])
        #expect(contents.count == 1)
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        #expect(config["responseSchema"] != nil)
    }

    @Test func geminiAnswerIsDecodedIntoThoughts() throws {
        let answer = #"{"notes":[{"title":"Demander congé","summary":"","excerpt":"demander congé pour le 24 novembre","kind":"task","category":"Travail","categoryDescription":"Emploi, horaires et congés","subcategory":"","tags":["congé"],"dates":[{"phrase":"24 novembre","role":"event"},{"phrase":"demain","role":"reminder"}]}]}"#
        let envelope = try JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [["text": answer]]], "finishReason": "STOP"]],
        ])
        let text = try GeminiClient.parse(data: envelope, status: 200, headers: [:])
        let analysis = try CloudDecoder.decode(text)
        let thought = try #require(analysis.thoughts.first)
        #expect(thought.title == "Demander congé")
        #expect(thought.summary == nil)
        #expect(thought.kind == .task)
        #expect(thought.category == "Travail")
        #expect(thought.categoryDescription == "Emploi, horaires et congés")
        #expect(thought.subcategory == nil)
        // Le rappel passe en premier : c'est lui qui donne l'échéance.
        #expect(thought.mentionedDates == ["demain", "24 novembre"])
    }

    /// Un rendez-vous garde sa propre date en premier : c'est elle qui va dans le calendrier, pas la date du rappel.
    @Test func anAppointmentKeepsItsOwnDateFirst() throws {
        let answer = #"{"notes":[{"title":"Dentiste","summary":"","excerpt":"Dentiste mardi à 10 h, rappelle-moi ça lundi","kind":"appointment","category":"Santé","categoryDescription":"","subcategory":"","tags":[],"dates":[{"phrase":"lundi","role":"reminder"},{"phrase":"mardi à 10 h","role":"event"}]}]}"#
        let thought = try #require(try CloudDecoder.decode(answer).thoughts.first)
        #expect(thought.mentionedDates == ["mardi à 10 h", "lundi"])
        #expect(thought.kind == .appointment)
    }

    /// Un rappel demandé fait d'une idée une chose « À faire », même quand le service rend une seule note.
    @Test func aReminderMakesATask() throws {
        let answer = #"{"notes":[{"title":"Cadeau : livre de cuisine","summary":"","excerpt":"Idée de cadeau : un livre de cuisine, rappelle-moi ça samedi","kind":"idea","category":"Famille","categoryDescription":"","subcategory":"","tags":[],"dates":[{"phrase":"samedi","role":"reminder"}]}]}"#
        #expect(try CloudDecoder.decode(answer).thoughts.first?.kind == .task)
    }

    @Test func geminiErrorsAreUnderstood() throws {
        let quota = Data(#"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","message":"Quota exceeded","details":[{"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"30s"}]}}"#.utf8)
        #expect(throws: CloudError.quotaExceeded(retryAfter: 30)) { try GeminiClient.parse(data: quota, status: 429, headers: [:]) }
        let badKey = Data(#"{"error":{"code":400,"status":"INVALID_ARGUMENT","message":"API key not valid. Please pass a valid API key."}}"#.utf8)
        #expect(throws: CloudError.invalidKey) { try GeminiClient.parse(data: badKey, status: 400, headers: [:]) }
        #expect(throws: CloudError.invalidKey) { try GeminiClient.parse(data: Data("{}".utf8), status: 403, headers: [:]) }
        #expect(throws: CloudError.service(503)) { try GeminiClient.parse(data: Data("{}".utf8), status: 503, headers: [:]) }
        let blocked = try JSONSerialization.data(withJSONObject: ["promptFeedback": ["blockReason": "SAFETY"]])
        #expect(throws: CloudError.refused) { try GeminiClient.parse(data: blocked, status: 200, headers: [:]) }
    }

    @Test func picksTheNewestStableFlashModels() {
        let names = ["models/gemini-2.5-flash", "models/gemini-3.5-flash", "models/gemini-3.8-flash",
                     "models/gemini-3.8-flash-tts", "models/gemini-3.5-flash-lite", "models/gemini-3-flash-preview",
                     "models/gemini-3.1-flash-lite", "models/gemini-embedding-2", "models/gemini-3.8-live"]
        let picked = GeminiModelPicker.pick(from: names)
        #expect(picked.primary == "gemini-3.8-flash")
        #expect(picked.lite == "gemini-3.5-flash-lite")
        #expect(GeminiModelPicker.pick(from: []).primary == nil)
    }

    // MARK: - Groq

    @Test func groqRequestUsesABearerKeyAndAStrictSchema() throws {
        let request = try GroqClient.makeRequest(apiKey: "CLE-GROQ", system: "consignes", user: "Note : voir le dentiste")
        #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer CLE-GROQ")
        #expect(!(request.url?.absoluteString.contains("CLE-GROQ") ?? true))
        let body = try json(request)
        #expect(body["model"] as? String == "openai/gpt-oss-120b")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["json_schema"] as? [String: Any])
        #expect(schema["strict"] as? Bool == true)
        #expect(Self.isStrict(try #require(schema["schema"] as? [String: Any])))
    }

    /// En mode strict, chaque objet interdit les champs en trop et exige tous ses champs.
    static func isStrict(_ schema: [String: Any]) -> Bool {
        if schema["type"] as? String == "object" {
            guard schema["additionalProperties"] as? Bool == false,
                  let properties = schema["properties"] as? [String: Any],
                  let required = schema["required"] as? [String], Set(required) == Set(properties.keys) else { return false }
            return properties.values.allSatisfy { ($0 as? [String: Any]).map(isStrict) ?? false }
        }
        if schema["type"] as? String == "array" {
            return (schema["items"] as? [String: Any]).map(isStrict) ?? false
        }
        return true
    }

    @Test func groqAnswerAndErrorsAreUnderstood() throws {
        let content = #"{"notes":[{"title":"Dentiste vendredi","summary":"","excerpt":"voir le dentiste vendredi","kind":"appointment","category":"Santé","categoryDescription":"","subcategory":"","tags":[],"dates":[{"phrase":"vendredi","role":"event"}]}]}"#
        let ok = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["role": "assistant", "content": content]]]])
        let analysis = try CloudDecoder.decode(try GroqClient.parse(data: ok, status: 200, headers: [:]))
        #expect(analysis.thoughts.first?.kind == .appointment)
        #expect(analysis.thoughts.first?.categoryDescription == nil)
        #expect(throws: CloudError.invalidKey) { try GroqClient.parse(data: Data("{}".utf8), status: 401, headers: [:]) }
        #expect(throws: CloudError.quotaExceeded(retryAfter: 12)) {
            try GroqClient.parse(data: Data("{}".utf8), status: 429, headers: ["retry-after": "12"])
        }
        #expect(throws: CloudError.service(500)) { try GroqClient.parse(data: Data("{}".utf8), status: 500, headers: [:]) }
    }

    // MARK: - Consignes et décodage

    @Test func theUserPromptContainsOnlyTodayTheCategoriesAndTheNote() {
        let prompt = CloudPrompt.user(text: "Acheter du lait", categories: ["Achats", "Maison"], context: Self.context)
        #expect(prompt.contains("Acheter du lait"))
        #expect(prompt.contains("Achats"))
        #expect(prompt.contains("2026"))
        #expect(CloudPrompt.user(text: "x", categories: [], context: Self.context).contains("aucune"))
    }

    @Test func theInstructionsForbidArbitrarySplittingAndInvention() {
        let system = CloudPrompt.system
        #expect(system.localizedCaseInsensitiveContains("verbatim"))
        #expect(system.localizedCaseInsensitiveContains("never split"))
        #expect(system.localizedCaseInsensitiveContains("never invent"))
    }

    @Test func decoderToleratesFencesAndMissingFieldsButRejectsGarbage() throws {
        let fenced = "```json\n{\"notes\":[{\"title\":\"Idée\",\"excerpt\":\"une idée\",\"kind\":\"weird\",\"category\":\"Projets\"}]}\n```"
        let thought = try #require(try CloudDecoder.decode(fenced).thoughts.first)
        #expect(thought.kind == .other)
        #expect(thought.tags.isEmpty)
        #expect(thought.mentionedDates.isEmpty)
        #expect(throws: CloudError.invalidOutput) { try CloudDecoder.decode("pas du JSON") }
    }
}
