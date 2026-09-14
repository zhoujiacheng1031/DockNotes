import Foundation

struct AIConfiguration: Sendable {
    let provider: AIProvider
    let endpoint: String
    let model: String
    let apiKey: String
}

enum AIClientError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case provider(message: String?, statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "The AI service URL is invalid."
        case .invalidResponse: "The AI service returned an unreadable response."
        case let .provider(message, statusCode): message ?? "AI request failed (HTTP \(statusCode))."
        }
    }

    func userMessage(language: AppLanguage) -> String {
        switch self {
        case .invalidEndpoint:
            L10n.text(.aiInvalidEndpoint, language: language)
        case .invalidResponse:
            L10n.text(.aiInvalidResponse, language: language)
        case let .provider(message, statusCode):
            message ?? String(format: L10n.text(.aiRequestFailedCode, language: language), statusCode)
        }
    }
}

enum AIClient {
    private struct OpenAIRequestBody: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
    }

    private struct AnthropicRequestBody: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }

    private struct OpenAIResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        struct ProviderError: Decodable { let message: String }
        let choices: [Choice]?
        let error: ProviderError?
    }

    private struct AnthropicResponseBody: Decodable {
        struct Content: Decodable { let type: String; let text: String? }
        struct ProviderError: Decodable { let message: String }
        let content: [Content]?
        let error: ProviderError?
    }

    static func endpointURL(from endpoint: String, provider: AIProvider) -> URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        let pathComponents = components.path.split(separator: "/")
        components.path = pathComponents.isEmpty ? "" : "/" + pathComponents.joined(separator: "/")
        guard var url = components.url else { return nil }
        if url.path.hasSuffix("/\(provider.endpointPath)") { return url }
        url.append(path: provider.endpointPath)
        return url
    }

    static func ask(
        configuration: AIConfiguration,
        note: DockNote,
        prompt: String,
        language: AppLanguage
    ) async throws -> String {
        let request = try makeRequest(
            configuration: configuration,
            note: note,
            prompt: prompt,
            language: language
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }
        switch configuration.provider {
        case .openAICompatible:
            let decoded = try? JSONDecoder().decode(OpenAIResponseBody.self, from: data)
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AIClientError.provider(message: decoded?.error?.message, statusCode: httpResponse.statusCode)
            }
            guard let answer = decoded?.choices?.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !answer.isEmpty else { throw AIClientError.invalidResponse }
            return answer
        case .anthropic:
            let decoded = try? JSONDecoder().decode(AnthropicResponseBody.self, from: data)
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AIClientError.provider(message: decoded?.error?.message, statusCode: httpResponse.statusCode)
            }
            let answer = decoded?.content?
                .filter { $0.type == "text" }
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !answer.isEmpty else { throw AIClientError.invalidResponse }
            return answer
        }
    }

    static func makeRequest(
        configuration: AIConfiguration,
        note: DockNote,
        prompt: String,
        language: AppLanguage
    ) throws -> URLRequest {
        guard let url = endpointURL(from: configuration.endpoint, provider: configuration.provider) else {
            throw AIClientError.invalidEndpoint
        }
        let systemInstruction = language == .english
            ? "You are the writing assistant inside DockNotes. Be concise, practical, and preserve the user's language."
            : "你是 DockNotes 内的写作助手。回答要简洁、实用，并沿用用户便签的语言。"
        let bodyContext = String(note.body.prefix(50_000))
        let userMessage = "Note title: \(note.title)\n\nNote content:\n\(bodyContext)\n\nUser request:\n\(prompt)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch configuration.provider {
        case .openAICompatible:
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(OpenAIRequestBody(
                model: model,
                messages: [
                    .init(role: "system", content: systemInstruction),
                    .init(role: "user", content: userMessage)
                ]
            ))
        case .anthropic:
            if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONEncoder().encode(AnthropicRequestBody(
                model: model,
                max_tokens: 2_048,
                system: systemInstruction,
                messages: [.init(role: "user", content: userMessage)]
            ))
        }
        return request
    }
}
