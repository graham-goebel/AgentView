import Foundation
import SQLite3

// MARK: - Cursor Session Monitor
//
// Cursor stores chat/composer data in SQLite databases (.vscdb files) under:
//   ~/Library/Application Support/Cursor/User/workspaceStorage/<hash>/state.vscdb
//   ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
//
// Each database has an `ItemTable` with (key TEXT, value TEXT) where the value
// is a JSON blob. Relevant keys: 'aiService.prompts', 'composer.composerData',
// 'workbench.panel.aichat.view.aichat.chatdata'

@MainActor
class CursorMonitor: ObservableObject {
    static let shared = CursorMonitor()

    private var watchers: [String: DispatchSourceFileSystemObject] = [:]

    private var cursorStorageRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent("Library/Application Support/Cursor/User")
        return [
            base.appendingPathComponent("workspaceStorage"),
            base.appendingPathComponent("globalStorage"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    init() { start() }

    func start() {
        Task { await scanCursorDirectories() }
        for root in cursorStorageRoots { watchDirectory(root) }
    }

    private func watchDirectory(_ url: URL) {
        guard !watchers.keys.contains(url.path) else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename],
            queue: DispatchQueue.global(qos: .background)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in await self?.scanCursorDirectories() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watchers[url.path] = source
    }

    func scanCursorDirectories() async {
        for root in cursorStorageRoots {
            await findAndReadDatabases(in: root)
        }
    }

    // MARK: - Find .vscdb files

    private func findAndReadDatabases(in directory: URL) async {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            if url.pathExtension == "vscdb" {
                await readVSCDB(url)
            }
        }
    }

    // MARK: - SQLite Reading

    private func readVSCDB(_ url: URL) async {
        var db: OpaquePointer?
        // Open read-only to avoid locking Cursor's live database
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = db else { return }
        defer { sqlite3_close(db) }

        let query = """
            SELECT key, value FROM ItemTable
            WHERE key IN (
                'aiService.prompts',
                'composer.composerData',
                'workbench.panel.aichat.view.aichat.chatdata',
                'interactive.sessions'
            )
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK,
              let stmt = stmt else { return }
        defer { sqlite3_finalize(stmt) }

        let modTime = url.modificationDate ?? Date()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let keyPtr = sqlite3_column_text(stmt, 0),
                  let valPtr = sqlite3_column_text(stmt, 1) else { continue }
            let key = String(cString: keyPtr)
            let value = String(cString: valPtr)
            await parseCursorEntry(key: key, value: value, sourceURL: url, modTime: modTime)
        }
    }

    // MARK: - JSON Parsing

    private func parseCursorEntry(key: String, value: String, sourceURL: URL, modTime: Date) async {
        guard let data = value.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }

        switch key {
        case "composer.composerData":
            parseComposerData(json, sourceURL: sourceURL, modTime: modTime)
        case "workbench.panel.aichat.view.aichat.chatdata":
            parseChatData(json, sourceURL: sourceURL, modTime: modTime)
        case "aiService.prompts":
            parseAIPrompts(json, sourceURL: sourceURL, modTime: modTime)
        case "interactive.sessions":
            parseInteractiveSessions(json, sourceURL: sourceURL, modTime: modTime)
        default:
            break
        }
    }

    // MARK: - Composer format
    // { "allComposers": [ { "composerId": "...", "text": "...", "conversation": [...] } ] }

    private func parseComposerData(_ json: Any, sourceURL: URL, modTime: Date) {
        guard let root = json as? [String: Any],
              let composers = root["allComposers"] as? [[String: Any]] else { return }

        for composer in composers {
            let composerId = composer["composerId"] as? String ?? UUID().uuidString
            var messages: [SessionMessage] = []
            var prompt = composer["text"] as? String ?? ""

            if let conversation = composer["conversation"] as? [[String: Any]] {
                for bubble in conversation {
                    let type = bubble["type"] as? String ?? ""
                    let text = bubble["text"] as? String
                        ?? (bubble["message"] as? String)
                        ?? ""
                    guard !text.isEmpty else { continue }
                    let role: MessageRole = (type == "user" || type == "human") ? .user : .assistant
                    messages.append(SessionMessage(role: role, content: text))
                    if role == .user && prompt.isEmpty { prompt = text }
                }
            }

            guard !messages.isEmpty else { continue }
            let session = buildSession(
                id: "composer-\(composerId)",
                prompt: prompt,
                messages: messages,
                sourceURL: sourceURL,
                modTime: modTime
            )
            SessionStore.shared.addSession(session)
        }
    }

    // MARK: - Chat panel format
    // { "tabs": [ { "chatTitle": "...", "bubbles": [ { "type": "user"/"ai", "text": "..." } ] } ] }

    private func parseChatData(_ json: Any, sourceURL: URL, modTime: Date) {
        guard let root = json as? [String: Any],
              let tabs = root["tabs"] as? [[String: Any]] else { return }

        for tab in tabs {
            let tabId = tab["tabId"] as? String ?? UUID().uuidString
            let title = tab["chatTitle"] as? String ?? ""
            var messages: [SessionMessage] = []
            var prompt = title

            if let bubbles = tab["bubbles"] as? [[String: Any]] {
                for bubble in bubbles {
                    let type = bubble["type"] as? String ?? ""
                    let text = bubble["text"] as? String
                        ?? (bubble["rawText"] as? String)
                        ?? ""
                    guard !text.isEmpty else { continue }
                    let role: MessageRole = (type == "user" || type == "human") ? .user : .assistant
                    messages.append(SessionMessage(role: role, content: text))
                    if role == .user && prompt.isEmpty { prompt = text }
                }
            }

            guard !messages.isEmpty else { continue }
            let session = buildSession(
                id: "chat-\(tabId)",
                prompt: prompt.isEmpty ? "Chat session" : prompt,
                messages: messages,
                sourceURL: sourceURL,
                modTime: modTime
            )
            SessionStore.shared.addSession(session)
        }
    }

    // MARK: - AI prompts format (simpler list)

    private func parseAIPrompts(_ json: Any, sourceURL: URL, modTime: Date) {
        guard let prompts = json as? [[String: Any]] else { return }
        for (i, prompt) in prompts.enumerated() {
            let text = prompt["prompt"] as? String ?? prompt["text"] as? String ?? ""
            guard !text.isEmpty else { continue }
            let response = prompt["response"] as? String ?? ""
            var messages: [SessionMessage] = [SessionMessage(role: .user, content: text)]
            if !response.isEmpty {
                messages.append(SessionMessage(role: .assistant, content: response))
            }
            let session = buildSession(
                id: "prompt-\(sourceURL.deletingPathExtension().lastPathComponent)-\(i)",
                prompt: text,
                messages: messages,
                sourceURL: sourceURL,
                modTime: modTime
            )
            SessionStore.shared.addSession(session)
        }
    }

    // MARK: - Interactive sessions format

    private func parseInteractiveSessions(_ json: Any, sourceURL: URL, modTime: Date) {
        guard let sessions = json as? [[String: Any]] else { return }
        for s in sessions {
            let sid = s["id"] as? String ?? UUID().uuidString
            var messages: [SessionMessage] = []
            var prompt = ""
            if let exchanges = s["exchanges"] as? [[String: Any]] {
                for ex in exchanges {
                    let q = ex["query"] as? String ?? ""
                    let r = ex["response"] as? String ?? ""
                    if !q.isEmpty {
                        messages.append(SessionMessage(role: .user, content: q))
                        if prompt.isEmpty { prompt = q }
                    }
                    if !r.isEmpty { messages.append(SessionMessage(role: .assistant, content: r)) }
                }
            }
            guard !messages.isEmpty else { continue }
            let session = buildSession(
                id: "interactive-\(sid)",
                prompt: prompt,
                messages: messages,
                sourceURL: sourceURL,
                modTime: modTime
            )
            SessionStore.shared.addSession(session)
        }
    }

    // MARK: - Build AgentSession

    private func buildSession(id: String, prompt: String, messages: [SessionMessage],
                               sourceURL: URL, modTime: Date) -> AgentSession {
        let timeSince = Date().timeIntervalSince(modTime)
        let status: SessionStatus = timeSince < 120 ? .active : .completed
        let lastAssistant = messages.last(where: { $0.role == .assistant })?.content
        return AgentSession(
            sessionId: id,
            tool: .cursor,
            status: status,
            startTime: sourceURL.creationDate ?? modTime,
            lastUpdateTime: modTime,
            workingDirectory: workingDirFromSourceURL(sourceURL),
            prompt: String(prompt.prefix(300)),
            messages: messages,
            currentTask: lastAssistant.map { String($0.prefix(80)) },
            turnCount: messages.filter { $0.role == .user }.count,
            sourceFile: sourceURL.path
        )
    }

    private func workingDirFromSourceURL(_ url: URL) -> String? {
        // workspaceStorage/<hash>/state.vscdb  — try to find workspace.json alongside
        let dir = url.deletingLastPathComponent()
        let workspaceJSON = dir.appendingPathComponent("workspace.json")
        if let data = try? Data(contentsOf: workspaceJSON),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let folder = json["folder"] as? String {
            return folder.replacingOccurrences(of: "file://", with: "")
        }
        return nil
    }

    deinit { watchers.values.forEach { $0.cancel() } }
}
