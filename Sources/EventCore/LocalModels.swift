import Foundation

public enum ExtractionProvider: String, CaseIterable, Sendable {
    case openRouter, ollama, lmStudio

    public var name: String {
        switch self {
        case .openRouter: "OpenRouter"
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        }
    }

    public var isLocal: Bool { self != .openRouter }

    private var baseURL: URL {
        URL(string: self == .ollama ? "http://127.0.0.1:11434" : "http://127.0.0.1:1234")!
    }

    fileprivate func url(_ path: String) -> URL { baseURL.appending(path: path) }
}

public struct LocalModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let provider: ExtractionProvider

    public init(id: String, provider: ExtractionProvider) {
        self.id = id
        self.provider = provider
    }
}

// A local server must not be able to redirect the selected text to another host.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct LocalModelClient: Sendable {
    public init() {}

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    public static func discoveryURL(for provider: ExtractionProvider) -> URL? {
        switch provider {
        case .openRouter: nil
        case .ollama: provider.url("api/tags")
        case .lmStudio: provider.url("v1/models")
        }
    }

    public func discover(_ provider: ExtractionProvider) async throws -> [LocalModel] {
        guard let url = Self.discoveryURL(for: provider) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw DraftError("\(provider.name) did not return a model list. Start its local server and check its settings.")
            }
            let models = try Self.decodeModels(data, provider: provider)
            guard provider == .ollama else { return models }

            // /api/tags can contain stale manifests. /api/show confirms that a model is usable.
            var usable: [LocalModel] = []
            for model in models.prefix(100) where !Self.isCloudModel(model.id) {
                var details = URLRequest(url: provider.url("api/show"))
                details.httpMethod = "POST"
                details.timeoutInterval = 3
                details.setValue("application/json", forHTTPHeaderField: "Content-Type")
                details.httpBody = try JSONSerialization.data(withJSONObject: ["model": model.id])
                guard let (data, response) = try? await session.data(for: details),
                      let http = response as? HTTPURLResponse,
                      Self.supportsChat(data, status: http.statusCode) else { continue }
                usable.append(model)
            }
            return usable
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw DraftError("Cannot reach \(provider.name) on this Mac. Start its local server, then refresh models.")
        }
    }

    public static func decodeModels(_ data: Data, provider: ExtractionProvider) throws -> [LocalModel] {
        guard data.count <= 2_000_000 else { throw DraftError("The local model list was too large.") }
        struct Entry: Decodable { let name: String?; let id: String? }
        struct OllamaList: Decodable { let models: [Entry] }
        struct StudioList: Decodable { let data: [Entry] }
        do {
            let entries: [Entry]
            switch provider {
            case .openRouter: return []
            case .ollama: entries = try JSONDecoder().decode(OllamaList.self, from: data).models
            case .lmStudio: entries = try JSONDecoder().decode(StudioList.self, from: data).data
            }
            let names = entries.compactMap { provider == .ollama ? $0.name : $0.id }
                .filter { !$0.isEmpty }
            return Array(Set(names)).sorted().map { LocalModel(id: $0, provider: provider) }
        } catch {
            throw DraftError("\(provider.name) returned an unreadable model list.")
        }
    }

    public static func supportsChat(_ data: Data, status: Int) -> Bool {
        struct Details: Decodable { let capabilities: [String] }
        guard status == 200, data.count <= 2_000_000,
              let details = try? JSONDecoder().decode(Details.self, from: data) else { return false }
        return details.capabilities.contains("completion")
    }

    private static func isCloudModel(_ name: String) -> Bool {
        name.hasSuffix(":cloud") || name.hasSuffix("-cloud")
    }

    public static func request(text: String, model: LocalModel, now: Date = Date(), zone: TimeZone = .current) throws -> URLRequest {
        try EventExtraction.validateInput(text)
        guard model.provider.isLocal, !model.id.isEmpty else { throw DraftError("Choose an available local model first.") }
        let messages = EventExtraction.messages(text: text, now: now, zone: zone)
        let body: [String: Any]
        let url: URL
        switch model.provider {
        case .openRouter: throw DraftError("Choose a local model first.")
        case .ollama:
            url = model.provider.url("api/chat")
            body = ["model": model.id, "messages": messages, "stream": false,
                    "format": EventExtraction.schema, "options": ["temperature": 0, "num_predict": 2500]]
        case .lmStudio:
            url = model.provider.url("v1/chat/completions")
            body = ["model": model.id, "messages": messages, "stream": false,
                    "temperature": 0, "max_tokens": 2500,
                    "response_format": ["type": "json_schema", "json_schema": [
                        "name": "calendar_event", "strict": true, "schema": EventExtraction.schema]]]
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func extract(text: String, model: LocalModel) async throws -> EventDraft {
        let request = try Self.request(text: text, model: model)
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DraftError("Invalid local server response.") }
            return try Self.decode(data, status: http.statusCode, provider: model.provider)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw DraftError("\(model.provider.name) could not complete the request. Check that its local server and model are running.")
        }
    }

    public static func decode(_ data: Data, status: Int, provider: ExtractionProvider) throws -> EventDraft {
        guard provider.isLocal else { throw DraftError("Choose a local provider first.") }
        if provider == .ollama, status == 400,
           let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error,
           message.contains("does not support chat") || message.contains("not found") {
            throw DraftError("Ollama lists this model but cannot open it for chat. Check `ollama show <model>`; a missing download may need to be pulled again.")
        }
        guard (200...299).contains(status) else {
            throw DraftError("\(provider.name) returned HTTP \(status). Check the model, server and structured-output support.")
        }
        guard data.count <= 200_000 else { throw DraftError("The local server response was too large.") }
        switch provider {
        case .openRouter: throw DraftError("Choose a local provider first.")
        case .ollama:
            struct Response: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
                let done: Bool
                let done_reason: String?
            }
            guard let result = try? JSONDecoder().decode(Response.self, from: data), result.done,
                  result.done_reason == nil || result.done_reason == "stop" else {
                throw DraftError("Ollama did not finish a usable answer.")
            }
            return try EventExtraction.decodeContent(result.message.content)
        case .lmStudio:
            struct Response: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { let content: String? }
                    let message: Message
                    let finish_reason: String?
                }
                let choices: [Choice]
            }
            guard let result = try? JSONDecoder().decode(Response.self, from: data),
                  let choice = result.choices.first, choice.finish_reason == "stop",
                  let content = choice.message.content else {
                throw DraftError("LM Studio did not finish a usable answer.")
            }
            return try EventExtraction.decodeContent(content)
        }
    }

    private struct ServerError: Decodable { let error: String }
}
