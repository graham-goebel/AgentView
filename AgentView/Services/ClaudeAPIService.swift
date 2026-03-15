import Foundation

// MARK: - Claude API Service

actor ClaudeAPIService {
    static let shared = ClaudeAPIService()

    private let baseURL = "https://api.anthropic.com/v1"
    private let model = "claude-opus-4-6"

    // MARK: - Summarize Session

    func summarizeSession(_ session: AgentSession, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw APIError.missingAPIKey }

        let recentMessages = session.messages.suffix(10)
        let conversation = recentMessages.map { msg in
            "\(msg.role.rawValue.uppercased()): \(msg.content.prefix(500))"
        }.joined(separator: "\n\n")

        let prompt = """
        Summarize this AI agent session in 2-3 sentences. Focus on what was accomplished.

        Session Tool: \(session.tool.rawValue)
        Working Directory: \(session.workingDirectory ?? "unknown")
        Duration: \(formatDuration(session.duration))

        Conversation (last 10 messages):
        \(conversation)
        """

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "messages": [["role": "user", "content": prompt]]
        ]

        let response = try await makeRequest(endpoint: "/messages", body: requestBody, apiKey: apiKey)

        guard let content = response["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw APIError.invalidResponse
        }

        return text
    }

    // MARK: - Get Progress Insight

    func getProgressInsight(_ session: AgentSession, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw APIError.missingAPIKey }

        let recentMessages = session.messages.suffix(5)
        let conversation = recentMessages.map { msg in
            "\(msg.role.rawValue): \(msg.content.prefix(300))"
        }.joined(separator: "\n")

        let prompt = """
        Based on this agent conversation, what is the current status and next likely action?
        Respond in one sentence.

        \(conversation)
        """

        let requestBody: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 100,
            "messages": [["role": "user", "content": prompt]]
        ]

        let response = try await makeRequest(endpoint: "/messages", body: requestBody, apiKey: apiKey)

        guard let content = response["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw APIError.invalidResponse
        }

        return text
    }

    // MARK: - HTTP

    private func makeRequest(endpoint: String, body: [String: Any], apiKey: String) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        return json
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - API Error

enum APIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case unauthorized
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API key not configured. Set it in Settings."
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid API response"
        case .unauthorized: return "Invalid API key"
        case .httpError(let code): return "HTTP error: \(code)"
        }
    }
}
