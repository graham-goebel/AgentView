import Foundation

// MARK: - Cursor Session Monitor

@MainActor
class CursorMonitor: ObservableObject {
    static let shared = CursorMonitor()

    private var watcher: DispatchSourceFileSystemObject?

    private var cursorDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage"),
            home.appendingPathComponent("Library/Application Support/Cursor/logs"),
            home.appendingPathComponent(".cursor/chat"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    init() {
        start()
    }

    func start() {
        Task {
            await scanCursorDirectories()
        }
        for dir in cursorDirectories {
            watchDirectory(dir)
        }
    }

    private func watchDirectory(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: DispatchQueue.global(qos: .background)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.scanCursorDirectories()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    func scanCursorDirectories() async {
        for dir in cursorDirectories {
            await scanDirectory(dir)
        }
    }

    private func scanDirectory(_ directory: URL) async {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        for item in contents {
            if item.pathExtension == "json" || item.pathExtension == "db" {
                if item.lastPathComponent.contains("chat") ||
                   item.lastPathComponent.contains("conversation") ||
                   item.lastPathComponent.contains("composer") {
                    await parseCursorFile(item)
                }
            } else if item.hasDirectoryPath {
                await scanDirectory(item)
            }
        }
    }

    private func parseCursorFile(_ url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }

        // Try to parse as JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let sessionId = url.deletingPathExtension().lastPathComponent
        var messages: [SessionMessage] = []
        var prompt = "Cursor Session"

        // Parse various Cursor JSON formats
        if let conversations = json["conversations"] as? [[String: Any]] {
            for conv in conversations {
                if let text = conv["text"] as? String, let role = conv["role"] as? String {
                    let msgRole: MessageRole = role == "user" ? .user : .assistant
                    messages.append(SessionMessage(role: msgRole, content: text))
                    if msgRole == .user && prompt == "Cursor Session" {
                        prompt = text
                    }
                }
            }
        } else if let msgs = json["messages"] as? [[String: Any]] {
            for msg in msgs {
                if let content = msg["content"] as? String, let role = msg["role"] as? String {
                    let msgRole: MessageRole = role == "user" ? .user : .assistant
                    messages.append(SessionMessage(role: msgRole, content: content))
                    if msgRole == .user && prompt == "Cursor Session" {
                        prompt = content
                    }
                }
            }
        }

        guard !messages.isEmpty else { return }

        let modTime = url.modificationDate ?? Date()
        let timeSinceUpdate = Date().timeIntervalSince(modTime)
        let status: SessionStatus = timeSinceUpdate < 120 ? .active : .completed

        let session = AgentSession(
            sessionId: sessionId,
            tool: .cursor,
            status: status,
            startTime: url.creationDate ?? Date(),
            lastUpdateTime: modTime,
            prompt: String(prompt.prefix(200)),
            messages: messages,
            turnCount: messages.filter { $0.role == .user }.count,
            sourceFile: url.path
        )

        await MainActor.run {
            SessionStore.shared.addSession(session)
        }
    }

    deinit {
        watcher?.cancel()
    }
}
