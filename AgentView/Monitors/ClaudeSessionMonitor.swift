import Foundation
import AppKit

// MARK: - Claude Session Monitor

@MainActor
class ClaudeSessionMonitor: ObservableObject {
    static let shared = ClaudeSessionMonitor()

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var projectWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var knownFiles: Set<String> = []
    private let claudeDir: URL

    // Possible Claude session locations
    private var watchDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".claude/sessions"),
            home.appendingPathComponent("Library/Application Support/Claude"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    init() {
        claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        start()
    }

    // MARK: - Start Watching

    func start() {
        // Initial scan
        Task {
            await scanAllDirectories()
        }

        // Watch each directory
        for dir in watchDirectories {
            watchDirectory(dir)
        }

        // Also watch the .claude root for new project dirs
        watchDirectory(claudeDir)
    }

    private func watchDirectory(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: DispatchQueue.global(qos: .background)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.scanAllDirectories()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        projectWatchers[url.path] = source
    }

    // MARK: - Scanning

    func scanAllDirectories() async {
        for dir in watchDirectories {
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
            if item.pathExtension == "jsonl" || item.pathExtension == "json" {
                await processSessionFile(item)
            } else if item.hasDirectoryPath {
                // Recurse into project subdirectories
                await scanDirectory(item)
            }
        }
    }

    func processSessionFile(_ url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            let session = try parseSessionFile(data, sourceURL: url)
            await MainActor.run {
                SessionStore.shared.addSession(session)
            }
        } catch {
            // Skip files we can't parse
        }
    }

    func reloadSession(from url: URL) async {
        await processSessionFile(url)
    }

    // MARK: - Parsing

    private func parseSessionFile(_ data: Data, sourceURL: URL) throws -> AgentSession {
        // Try JSONL format (one JSON object per line)
        let content = String(data: data, encoding: .utf8) ?? ""
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        var sessionId: String = sourceURL.deletingPathExtension().lastPathComponent
        var cwd: String? = nil
        var allMessages: [SessionMessage] = []
        var firstUserMessage: String = ""
        var totalInputTokens = 0
        var totalOutputTokens = 0
        var totalCostUsd = 0.0
        var firstTimestamp: Date = sourceURL.creationDate ?? Date()
        var lastTimestamp: Date = sourceURL.modificationDate ?? Date()
        var currentTask: String? = nil
        var isActive = false

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(ClaudeMessage.self, from: lineData) else {
                continue
            }

            // Extract session ID from init message
            if entry.type == "system", let sid = entry.sessionId {
                sessionId = sid
            }

            if let sid = entry.sessionId, !sid.isEmpty {
                sessionId = sid
            }

            // Parse messages
            if let msg = entry.message {
                let role = msg.role ?? "user"
                let contentText = msg.content?.text ?? ""

                if !contentText.isEmpty {
                    let msgRole: MessageRole = role == "assistant" ? .assistant : .user

                    // Extract tool uses from assistant messages
                    var toolUses: [ToolUse] = []
                    if case .blocks(let blocks) = msg.content {
                        for block in blocks where block.type == "tool_use" {
                            let toolInput = block.input?.description ?? ""
                            toolUses.append(ToolUse(
                                name: block.name ?? "unknown",
                                input: toolInput
                            ))
                        }
                    }

                    let sessionMsg = SessionMessage(
                        role: msgRole,
                        content: contentText,
                        toolUses: toolUses
                    )
                    allMessages.append(sessionMsg)

                    // Track first user message as the prompt
                    if msgRole == .user && firstUserMessage.isEmpty {
                        firstUserMessage = contentText
                    }
                }

                // Track tokens
                if let usage = msg.usage {
                    totalInputTokens += usage.inputTokens ?? 0
                    totalOutputTokens += usage.outputTokens ?? 0
                }
            }

            // Track cost
            if let cost = entry.costUsd {
                totalCostUsd += cost
            }

            // Check for active status
            if entry.type == "assistant" {
                isActive = false // Will be overridden if more messages follow
            }
        }

        // Determine current task from last assistant message
        if let lastAssistant = allMessages.last(where: { $0.role == .assistant }) {
            let preview = String(lastAssistant.content.prefix(100))
            currentTask = preview.isEmpty ? nil : preview
        }

        // Determine status based on recency
        let modTime = sourceURL.modificationDate ?? Date()
        let timeSinceUpdate = Date().timeIntervalSince(modTime)
        let status: SessionStatus
        if timeSinceUpdate < 30 {
            status = .active
        } else if timeSinceUpdate < 300 {
            status = .idle
        } else {
            status = .completed
        }

        let totalTokens = totalInputTokens + totalOutputTokens

        return AgentSession(
            sessionId: sessionId,
            tool: .claude,
            status: status,
            startTime: firstTimestamp,
            lastUpdateTime: lastTimestamp,
            workingDirectory: cwd,
            prompt: firstUserMessage.isEmpty ? "Session: \(String(sessionId.prefix(12)))" : firstUserMessage,
            messages: allMessages,
            currentTask: currentTask,
            totalTokens: totalTokens,
            totalCost: totalCostUsd,
            turnCount: allMessages.filter { $0.role == .user }.count,
            sourceFile: sourceURL.path
        )
    }

    deinit {
        projectWatchers.values.forEach { $0.cancel() }
    }
}

// MARK: - URL Extensions

extension URL {
    var creationDate: Date? {
        (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    var modificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
