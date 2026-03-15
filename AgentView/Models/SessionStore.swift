import Foundation
import Combine
import AppKit

// MARK: - Session Store

@MainActor
class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published var sessions: [AgentSession] = []
    @Published var selectedSessionId: UUID?
    @Published var filterTool: AgentTool? = nil
    @Published var filterStatus: SessionStatus? = nil
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var apiKey: String = ""
    @Published var showOnlyActive: Bool = false

    private let persistenceURL: URL
    private var cancellables = Set<AnyCancellable>()

    var filteredSessions: [AgentSession] {
        sessions
            .filter { session in
                if showOnlyActive && !session.isLive { return false }
                if let tool = filterTool, session.tool != tool { return false }
                if let status = filterStatus, session.status != status { return false }
                if !searchQuery.isEmpty {
                    let q = searchQuery.lowercased()
                    return session.prompt.lowercased().contains(q)
                        || session.sessionId.lowercased().contains(q)
                        || (session.workingDirectory ?? "").lowercased().contains(q)
                        || (session.summary ?? "").lowercased().contains(q)
                }
                return true
            }
            .sorted { $0.lastUpdateTime > $1.lastUpdateTime }
    }

    var activeSessions: [AgentSession] {
        sessions.filter { $0.isLive }
    }

    var selectedSession: AgentSession? {
        guard let id = selectedSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AgentView", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        persistenceURL = appDir.appendingPathComponent("sessions.json")

        loadAPIKey()
        loadPersistedSessions()
    }

    // MARK: - Session Management

    func addSession(_ session: AgentSession) {
        if let idx = sessions.firstIndex(where: { $0.sessionId == session.sessionId && $0.tool == session.tool }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
        persistSessions()
    }

    func updateSession(_ session: AgentSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
            persistSessions()
        }
    }

    func removeSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if selectedSessionId == id {
            selectedSessionId = sessions.first?.id
        }
        persistSessions()
    }

    func removeAllCompleted() {
        sessions.removeAll { $0.status == .completed || $0.status == .cancelled }
        persistSessions()
    }

    func clearAll() {
        sessions.removeAll()
        selectedSessionId = nil
        persistSessions()
    }

    func refreshSession(_ id: UUID) async {
        // Triggers re-read from source
        guard let session = sessions.first(where: { $0.id == id }),
              let sourceFile = session.sourceFile else { return }
        let url = URL(fileURLWithPath: sourceFile)
        await ClaudeSessionMonitor.shared.reloadSession(from: url)
    }

    // MARK: - Persistence

    private func loadPersistedSessions() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoded = try JSONDecoder().decode([AgentSession].self, from: data)
            sessions = decoded
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }

    func persistSessions() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessions)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            print("Failed to persist sessions: \(error)")
        }
    }

    // MARK: - API Key

    func loadAPIKey() {
        apiKey = UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""
    }

    func saveAPIKey(_ key: String) {
        apiKey = key
        UserDefaults.standard.set(key, forKey: "anthropic_api_key")
    }

    // MARK: - Statistics

    var totalTokensUsed: Int {
        sessions.reduce(0) { $0 + $1.totalTokens }
    }

    var totalCost: Double {
        sessions.reduce(0) { $0 + $1.totalCost }
    }

    var sessionsByTool: [AgentTool: Int] {
        Dictionary(grouping: sessions, by: { $0.tool }).mapValues { $0.count }
    }
}
