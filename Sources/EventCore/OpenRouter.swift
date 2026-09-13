import Foundation

public struct OpenRouterClient: Sendable {
    public init() {}

    public static func isFreeModel(_ model: String) -> Bool {
        model == "openrouter/free" || (model.contains("/") && model.hasSuffix(":free") && !model.contains(where: { $0.isWhitespace }))
    }

    public static func request(text: String, key: String, model: String, now: Date = Date(), zone: TimeZone = .current) throws -> URLRequest {
        try EventExtraction.validateInput(text)
        guard !key.isEmpty else { throw DraftError("Save your own OpenRouter API key in Settings first.") }
        guard isFreeModel(model) else { throw DraftError("Choose openrouter/free or a specific model ending in :free. Paid models are disabled.") }

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

    public func extract(text: String, key: String, model: String) async throws -> EventDraft {
        let request = try Self.request(text: text, key: key, model: model)
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
        case 401, 403: throw DraftError("OpenRouter rejected access. Check your API key and provider privacy settings.")
        case 402: throw DraftError("OpenRouter reported a billing restriction. No paid fallback was attempted.")
        case 429: throw DraftError("The free-model rate limit was reached. Wait before trying again. No paid fallback was attempted.")
        case 400, 404, 422: throw DraftError("This free model or structured-output provider is unavailable. Try openrouter/free or another compatible :free model.")
        default: throw DraftError("OpenRouter returned HTTP \(status). Try again later. No paid fallback was attempted.")
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
        catch { throw DraftError("The model returned invalid event data. Try another free model or enter the event manually.") }
    }
}
