import Foundation

// MARK: - Agent Tool

enum AgentTool: String, Codable, CaseIterable, Identifiable {
    case claude = "Claude"
    case cursor = "Cursor"
    case manual = "Manual"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .claude: return "brain.head.profile"
        case .cursor: return "cursorarrow.rays"
        case .manual: return "person.crop.circle"
        }
    }

    var color: String {
        switch self {
        case .claude: return "orange"
        case .cursor: return "blue"
        case .manual: return "purple"
        }
    }
}

// MARK: - Session Status

enum SessionStatus: String, Codable {
    case active = "Active"
    case thinking = "Thinking"
    case completed = "Completed"
    case idle = "Idle"
    case error = "Error"
    case cancelled = "Cancelled"

    var isLive: Bool {
        self == .active || self == .thinking
    }

    var iconName: String {
        switch self {
        case .active: return "circle.fill"
        case .thinking: return "brain"
        case .completed: return "checkmark.circle.fill"
        case .idle: return "pause.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}

// MARK: - Session Message

struct SessionMessage: Identifiable, Codable {
    let id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var toolUses: [ToolUse]

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), toolUses: [ToolUse] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolUses = toolUses
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct ToolUse: Identifiable, Codable {
    let id: UUID
    var name: String
    var input: String
    var result: String?
    var isError: Bool

    init(id: UUID = UUID(), name: String, input: String, result: String? = nil, isError: Bool = false) {
        self.id = id
        self.name = name
        self.input = input
        self.result = result
        self.isError = isError
    }
}

// MARK: - Agent Session

struct AgentSession: Identifiable, Codable {
    let id: UUID
    var sessionId: String
    var tool: AgentTool
    var status: SessionStatus
    var startTime: Date
    var lastUpdateTime: Date
    var workingDirectory: String?
    var prompt: String
    var summary: String?
    var messages: [SessionMessage]
    var currentTask: String?
    var totalTokens: Int
    var totalCost: Double
    var turnCount: Int
    var sourceFile: String?

    init(
        id: UUID = UUID(),
        sessionId: String,
        tool: AgentTool,
        status: SessionStatus = .active,
        startTime: Date = Date(),
        lastUpdateTime: Date = Date(),
        workingDirectory: String? = nil,
        prompt: String,
        summary: String? = nil,
        messages: [SessionMessage] = [],
        currentTask: String? = nil,
        totalTokens: Int = 0,
        totalCost: Double = 0,
        turnCount: Int = 0,
        sourceFile: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.tool = tool
        self.status = status
        self.startTime = startTime
        self.lastUpdateTime = lastUpdateTime
        self.workingDirectory = workingDirectory
        self.prompt = prompt
        self.summary = summary
        self.messages = messages
        self.currentTask = currentTask
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.turnCount = turnCount
        self.sourceFile = sourceFile
    }

    var duration: TimeInterval {
        lastUpdateTime.timeIntervalSince(startTime)
    }

    var isLive: Bool {
        status.isLive
    }

    var displayTitle: String {
        if let task = currentTask, !task.isEmpty {
            return task
        }
        let truncated = prompt.prefix(60)
        return truncated.count < prompt.count ? "\(truncated)..." : String(truncated)
    }

    var shortId: String {
        String(sessionId.prefix(8))
    }
}

// MARK: - Claude Session File Format

struct ClaudeSessionFile: Codable {
    var sessionId: String?
    var cwd: String?
    var messages: [ClaudeMessage]?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case messages
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ClaudeMessage: Codable {
    var type: String?
    var message: ClaudeMessageContent?
    var result: String?
    var subtype: String?
    var costUsd: Double?
    var durationMs: Double?
    var sessionId: String?

    enum CodingKeys: String, CodingKey {
        case type, message, result, subtype
        case costUsd = "cost_usd"
        case durationMs = "duration_ms"
        case sessionId = "session_id"
    }
}

struct ClaudeMessageContent: Codable {
    var role: String?
    var content: ClaudeContent?
    var usage: ClaudeUsage?
}

enum ClaudeContent: Codable {
    case text(String)
    case blocks([ClaudeContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else if let blocks = try? container.decode([ClaudeContentBlock].self) {
            self = .blocks(blocks)
        } else {
            self = .text("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .blocks(let blocks): try container.encode(blocks)
        }
    }

    var text: String {
        switch self {
        case .text(let t): return t
        case .blocks(let blocks):
            return blocks.compactMap { $0.text }.joined(separator: "\n")
        }
    }
}

struct ClaudeContentBlock: Codable {
    var type: String?
    var text: String?
    var name: String?
    var input: AnyCodable?
}

struct ClaudeUsage: Codable {
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String: try container.encode(string)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        default: try container.encodeNil()
        }
    }

    var description: String {
        switch value {
        case let string as String: return string
        case let dict as [String: AnyCodable]:
            let pairs = dict.map { "\($0.key): \($0.value.description)" }.joined(separator: ", ")
            return "{\(pairs)}"
        default: return "\(value)"
        }
    }
}
