import Foundation
import Security

enum ScribeAIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case local
    case venice
    case openAI = "openai"
    case claude
    case xAI = "xai"
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "On-device Scribe"
        case .venice: return "Venice AI"
        case .openAI: return "OpenAI"
        case .claude: return "Claude"
        case .xAI: return "Grok (xAI)"
        case .custom: return "Custom OpenAI-compatible"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .local: return ""
        case .venice: return "https://api.venice.ai/api/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .claude: return "https://api.anthropic.com/v1"
        case .xAI: return "https://api.x.ai/v1"
        case .custom: return "http://localhost:11434/v1"
        }
    }

    var needsAPIKey: Bool { self != .local && self != .custom }
    var isRemote: Bool { self != .local && self != .custom }
}

struct ScribeAISettings: Equatable, Sendable {
    var provider: ScribeAIProvider
    var model: String
    var baseURL: String
    var redactSensitive: Bool
}

struct ScribeAIModelOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let isRecommended: Bool
}

struct ScribeChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

enum ScribeKeychain {
    private static let service = "com.cmadd21mm.scribe.ai"

    static func saveAPIKey(_ value: String, provider: ScribeAIProvider) throws {
        let account = provider.rawValue
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func apiKey(provider: ScribeAIProvider) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum ScribeAIError: LocalizedError {
    case missingModel
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingModel: return "Choose a model name in Settings."
        case .missingAPIKey: return "Add an API key in Settings."
        case .invalidEndpoint: return "The provider address is invalid."
        case .invalidResponse: return "The AI provider returned an unreadable response."
        case .requestFailed(let message): return message
        }
    }
}

enum ScribeAIModelCatalog {
    static func fetch(
        provider: ScribeAIProvider,
        baseURL: String,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [ScribeAIModelOption] {
        guard provider != .local else { return [] }
        var request = try modelListRequest(
            provider: provider,
            baseURL: baseURL,
            apiKey: apiKey,
            authenticateVenice: false
        )
        var (data, response) = try await session.data(for: request)
        if provider == .venice,
           let http = response as? HTTPURLResponse,
           [401, 403].contains(http.statusCode),
           !apiKey.isEmpty {
            request = try modelListRequest(
                provider: provider,
                baseURL: baseURL,
                apiKey: apiKey,
                authenticateVenice: true
            )
            (data, response) = try await session.data(for: request)
        }
        return try models(from: data, response: response, provider: provider)
    }

    static func modelListRequest(
        provider: ScribeAIProvider,
        baseURL: String,
        apiKey: String,
        authenticateVenice: Bool = false
    ) throws -> URLRequest {
        guard provider != .local else { throw ScribeAIError.invalidEndpoint }
        let resolvedBaseURL = baseURL.isEmpty ? provider.defaultBaseURL : baseURL
        let trimmedBaseURL = resolvedBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix: String
        switch provider {
        case .venice:
            suffix = "/models?type=text"
        case .claude:
            suffix = "/models?limit=1000"
        case .xAI:
            suffix = "/language-models"
        case .openAI, .custom:
            suffix = "/models"
        case .local:
            throw ScribeAIError.invalidEndpoint
        }
        guard let url = URL(string: trimmedBaseURL + suffix) else {
            throw ScribeAIError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if provider == .claude {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if !apiKey.isEmpty && (provider != .venice || authenticateVenice) {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func models(
        from data: Data,
        response: URLResponse,
        provider: ScribeAIProvider
    ) throws -> [ScribeAIModelOption] {
        guard let http = response as? HTTPURLResponse else {
            throw ScribeAIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ScribeAIError.requestFailed(
                providerErrorMessage(from: data)
                    ?? "\(provider.title) returned HTTP \(http.statusCode) while listing models."
            )
        }
        let options = try parse(data: data, provider: provider)
        guard !options.isEmpty else {
            throw ScribeAIError.requestFailed("No compatible text models were returned for this account.")
        }
        return options
    }

    static func parse(data: Data, provider: ScribeAIProvider) throws -> [ScribeAIModelOption] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScribeAIError.invalidResponse
        }
        let rawModels: [[String: Any]]
        if provider == .xAI {
            rawModels = json["models"] as? [[String: Any]] ?? []
        } else {
            rawModels = json["data"] as? [[String: Any]] ?? []
        }

        let parsed = rawModels.compactMap { model -> ScribeAIModelOption? in
            guard let id = model["id"] as? String, !id.isEmpty else { return nil }
            if provider == .venice,
               let type = model["type"] as? String,
               type != "text" { return nil }
            if provider == .openAI && !isLikelyTextModel(id) { return nil }

            let spec = model["model_spec"] as? [String: Any]
            let displayName = (spec?["name"] as? String)
                ?? (model["display_name"] as? String)
                ?? id
            let description = spec?["description"] as? String
            let aliases = model["aliases"] as? [String]
            let detail: String
            if let description, !description.isEmpty {
                detail = description
            } else if let aliases, !aliases.isEmpty {
                detail = "Also available as \(aliases.prefix(3).joined(separator: ", "))"
            } else if displayName != id {
                detail = id
            } else {
                detail = provider.title
            }
            let traits = spec?["traits"] as? [String] ?? []
            let recommended = traits.contains { trait in
                let normalized = trait.lowercased()
                return normalized == "default" || normalized == "recommended"
            }
            return ScribeAIModelOption(
                id: id,
                title: displayName,
                detail: detail,
                isRecommended: recommended
            )
        }

        var seen = Set<String>()
        let unique = parsed.filter { seen.insert($0.id).inserted }
        return unique.filter(\.isRecommended) + unique.filter { !$0.isRecommended }
    }

    static func preferredModel(
        from options: [ScribeAIModelOption],
        provider: ScribeAIProvider
    ) -> ScribeAIModelOption? {
        if let recommended = options.first(where: \.isRecommended) { return recommended }
        if provider == .openAI {
            let preferredIDs = ["gpt-5.2", "gpt-5.1", "gpt-5", "gpt-4.1"]
            for id in preferredIDs {
                if let match = options.first(where: { $0.id == id }) { return match }
            }
        }
        return options.first
    }

    private static func isLikelyTextModel(_ id: String) -> Bool {
        let value = id.lowercased()
        let unsupportedMarkers = [
            "embedding", "moderation", "whisper", "transcribe", "tts", "dall-e",
            "image", "realtime", "audio", "computer-use", "search-preview"
        ]
        let supportedPrefixes = ["gpt-", "chatgpt-", "o1", "o3", "o4"]
        return supportedPrefixes.contains { value.hasPrefix($0) }
            && !unsupportedMarkers.contains { value.contains($0) }
    }

    private static func providerErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? [String: Any] {
            return (error["message"] as? String) ?? (error["type"] as? String)
        }
        return json["message"] as? String
    }
}

enum ScribeMeetingAssistant {
    static func answer(
        question: String,
        meetings: [MeetingRecord],
        settings: ScribeAISettings
    ) async throws -> String {
        if settings.provider == .local {
            return localAnswer(question: question, meetings: meetings)
        }
        let context = contextText(meetings, redact: settings.redactSensitive)
        return try await remoteAnswer(question: question, context: context, settings: settings)
    }

    static func contextText(_ meetings: [MeetingRecord], redact: Bool = false) -> String {
        var blocks: [String] = []
        for meeting in meetings {
            var lines = ["MEETING: \(meeting.title)", "SUMMARY: \(meeting.summary)"]
            if !meeting.decisions.isEmpty { lines.append("DECISIONS: \(meeting.decisions.joined(separator: "; "))") }
            if !meeting.actionItems.isEmpty { lines.append("ACTIONS: \(meeting.actionItems.map(\.text).joined(separator: "; "))") }
            lines.append(contentsOf: meeting.transcript.map { "[\($0.timestamp)] \($0.speaker): \($0.text)" })
            blocks.append(lines.joined(separator: "\n"))
        }
        let value = blocks.joined(separator: "\n\n---\n\n")
        return redact ? redactSensitiveData(value) : value
    }

    private static func localAnswer(question: String, meetings: [MeetingRecord]) -> String {
        let terms = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            .subtracting(["the", "a", "an", "and", "or", "is", "are", "was", "were", "what", "who", "when", "did", "we", "i", "to", "of", "in", "for"])
        var candidates: [(score: Int, text: String)] = []
        for meeting in meetings {
            for line in meeting.transcript {
                let lowered = line.text.lowercased()
                let score = terms.reduce(0) { $0 + (lowered.contains($1) ? 1 : 0) }
                if score > 0 {
                    candidates.append((score, "[\(line.timestamp)] \(line.speaker): \(line.text) — \(meeting.title)"))
                }
            }
            for decision in meeting.decisions {
                let score = terms.reduce(0) { $0 + (decision.lowercased().contains($1) ? 1 : 0) }
                if score > 0 { candidates.append((score + 1, "Decision: \(decision) — \(meeting.title)")) }
            }
        }
        let best = candidates.sorted { $0.score > $1.score }.prefix(5).map(\.text)
        if best.isEmpty {
            return "I couldn’t find a direct match in the selected meeting context. Try a person, project, decision, or phrase from the conversation."
        }
        return "Here are the most relevant moments I found locally:\n\n" + best.map { "• \($0)" }.joined(separator: "\n")
    }

    private static func remoteAnswer(
        question: String,
        context: String,
        settings: ScribeAISettings
    ) async throws -> String {
        guard !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScribeAIError.missingModel
        }
        let key = ScribeKeychain.apiKey(provider: settings.provider)
        if settings.provider.needsAPIKey && key.isEmpty { throw ScribeAIError.missingAPIKey }
        let base = settings.baseURL.isEmpty ? settings.provider.defaultBaseURL : settings.baseURL
        let suffix = settings.provider == .claude ? "/messages" : "/chat/completions"
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + suffix) else {
            throw ScribeAIError.invalidEndpoint
        }
        let prompt = """
        Answer using only the supplied Scribe meeting context. Be concise and useful. Cite transcript evidence with its exact [MM:SS] timestamp. If the context does not support an answer, say so.

        QUESTION
        \(question)

        MEETING CONTEXT
        \(context)
        """
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if settings.provider == .claude {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": settings.model,
                "max_tokens": 1_200,
                "messages": [["role": "user", "content": prompt]],
            ])
        } else {
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            var body: [String: Any] = [
                "model": settings.model,
                "messages": [["role": "user", "content": prompt]],
                "temperature": 0.2,
            ]
            if settings.provider == .openAI { body["store"] = false }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScribeAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? "The provider returned HTTP \(http.statusCode)."
            throw ScribeAIError.requestFailed(message)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if settings.provider == .claude,
           let content = json?["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String { return text }
        if let choices = json?["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let text = message["content"] as? String { return text }
        throw ScribeAIError.invalidResponse
    }

    private static func redactSensitiveData(_ value: String) -> String {
        var output = value
        let patterns = [
            #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            #"(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#,
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "[REDACTED]",
                options: .regularExpression
            )
        }
        return output
    }
}
