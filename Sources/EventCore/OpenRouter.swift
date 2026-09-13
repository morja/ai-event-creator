import Foundation

public struct OpenRouterClient: Sendable {
    public init() {}

    public static func isFreeModel(_ model: String) -> Bool {
        model == "openrouter/free" || (model.contains("/") && model.hasSuffix(":free") && !model.contains(where: { $0.isWhitespace }))
    }

    public static func isAllowedModel(_ model: String, allowPaid: Bool) -> Bool {
        if isFreeModel(model) { return true }
        guard allowPaid, model.count <= 200, model.contains("/"),
              model != "openrouter/auto", !model.contains(where: { $0.isWhitespace || $0.isNewline }) else { return false }
        return true
    }

    public static func request(text: String, key: String, model: String, now: Date = Date(), zone: TimeZone = .current,
                               allowPaid: Bool = false) throws -> URLRequest {
        try EventExtraction.validateInput(text)
        guard !key.isEmpty else { throw DraftError("Bitte zuerst den OpenRouter-API-Schlüssel in den Einstellungen speichern.") }
        guard isAllowedModel(model, allowPaid: allowPaid) else {
            throw DraftError("Bitte ein kostenloses Modell wählen oder bezahlte Modelle in den Einstellungen freigeben.")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": EventExtraction.messages(text: text, now: now, zone: zone),
            "temperature": 0,
            "max_tokens": 2500,
            "provider": ["require_parameters": true, "allow_fallbacks": false],
            "response_format": ["type": "json_schema", "json_schema": [
                "name": "calendar_event", "strict": true,
                "schema": EventExtraction.schema
            ]]
        ]
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func extract(text: String, key: String, model: String, allowPaid: Bool = false) async throws -> EventDraft {
        let request = try Self.request(text: text, key: key, model: model, allowPaid: allowPaid)
        // Ephemeral storage avoids keeping selected text in disk caches. There are no automatic retries.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DraftError("Invalid server response.") }
            return try Self.decode(data, status: http.statusCode)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw DraftError("OpenRouter could not be reached: \(error.localizedDescription) Check your connection and try again.")
        }
    }

    public static func decode(_ data: Data, status: Int) throws -> EventDraft {
        switch status {
        case 200...299: break
        case 401, 403: throw DraftError("OpenRouter hat den Zugriff abgelehnt. Prüfe API-Schlüssel und Anbieterfreigaben.")
        case 402: throw DraftError("OpenRouter meldet eine Abrechnungssperre. Es wurde kein anderes Modell versucht.")
        case 429: throw DraftError("Das Modell hat sein Anfragelimit erreicht. Bitte später erneut versuchen.")
        case 400, 404, 422: throw DraftError("Für dieses Modell ist keine passende strukturierte Ausgabe verfügbar. Wähle in den Einstellungen ein anderes Modell, zum Beispiel openrouter/free.")
        default: throw DraftError("OpenRouter antwortet mit HTTP \(status). Es wurde kein anderes Modell versucht.")
        }
        guard data.count <= 200000 else { throw DraftError("The server response was too large.") }
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
                let finish_reason: String?
            }
            let choices: [Choice]
        }
        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard let choice = response.choices.first, choice.finish_reason == "stop",
                  let content = choice.message.content else {
                throw DraftError("The model did not finish a usable answer. Try again or enter the event manually.")
            }
            return try EventExtraction.decodeContent(content)
        } catch let error as DraftError { throw error }
        catch { throw DraftError("The model returned invalid event data. Try another model or enter the event manually.") }
    }
}
