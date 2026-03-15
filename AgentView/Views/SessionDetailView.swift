import SwiftUI

// MARK: - Session Detail View

struct SessionDetailView: View {
    let session: AgentSession
    @EnvironmentObject var store: SessionStore
    @State private var summary: String? = nil
    @State private var isSummarizing = false
    @State private var summaryError: String? = nil
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SessionHeaderView(session: session)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tabs
            TabView(selection: $selectedTab) {
                // Messages Tab
                MessagesTabView(session: session)
                    .tabItem { Label("Messages", systemImage: "message") }
                    .tag(0)

                // Summary Tab
                SummaryTabView(
                    session: session,
                    summary: $summary,
                    isSummarizing: $isSummarizing,
                    summaryError: $summaryError
                )
                .tabItem { Label("Summary", systemImage: "doc.text") }
                .tag(1)

                // Details Tab
                DetailsTabView(session: session)
                    .tabItem { Label("Details", systemImage: "info.circle") }
                    .tag(2)
            }
        }
        .id(session.id)
        .navigationTitle(session.displayTitle)
    }
}

// MARK: - Session Header

struct SessionHeaderView: View {
    let session: AgentSession

    var statusColor: Color {
        switch session.status {
        case .active: return .green
        case .thinking: return .blue
        case .completed: return .secondary
        case .idle: return .orange
        case .error: return .red
        case .cancelled: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Tool icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(toolColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: session.tool.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(toolColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(session.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                // Status + Tool
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(session.status.rawValue)
                            .font(.caption)
                            .foregroundColor(statusColor)
                    }
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(session.tool.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let dir = session.workingDirectory {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(URL(fileURLWithPath: dir).lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Metrics row
                HStack(spacing: 12) {
                    MetricBadge(icon: "message", value: "\(session.turnCount) turns")
                    if session.totalTokens > 0 {
                        MetricBadge(icon: "character", value: "\(formatTokens(session.totalTokens)) tokens")
                    }
                    if session.totalCost > 0 {
                        MetricBadge(icon: "dollarsign.circle", value: String(format: "$%.4f", session.totalCost))
                    }
                    MetricBadge(icon: "clock", value: formatDuration(session.duration))
                }
            }

            Spacer()

            // Session ID
            VStack(alignment: .trailing) {
                Text(session.shortId)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("ID")
                    .font(.system(size: 9))
                    .foregroundColor(.tertiary)
            }
        }
    }

    var toolColor: Color {
        switch session.tool {
        case .claude: return .orange
        case .cursor: return .blue
        case .manual: return .purple
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000) }
        return "\(n)"
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        let s = Int(t.truncatingRemainder(dividingBy: 60))
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

struct MetricBadge: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(value)
                .font(.system(size: 10))
        }
        .foregroundColor(.secondary)
    }
}

// MARK: - Messages Tab

struct MessagesTabView: View {
    let session: AgentSession
    @State private var expandedMessageId: UUID? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(session.messages) { message in
                        MessageBubble(
                            message: message,
                            isExpanded: expandedMessageId == message.id,
                            onTap: {
                                withAnimation(.spring(response: 0.3)) {
                                    expandedMessageId = expandedMessageId == message.id ? nil : message.id
                                }
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: session.messages.count) { _ in
                if let last = session.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: SessionMessage
    let isExpanded: Bool
    let onTap: () -> Void

    var isUser: Bool { message.role == .user }
    var isSystem: Bool { message.role == .system }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isUser {
                Spacer(minLength: 40)
            }

            VStack(alignment: isUser ? .leading : .trailing, spacing: 4) {
                // Role label
                HStack(spacing: 4) {
                    if isUser {
                        Image(systemName: "person.crop.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("User")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Assistant")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "cpu")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(message.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.tertiary)
                }

                // Content bubble
                VStack(alignment: .leading, spacing: 6) {
                    Text(isExpanded ? message.content : String(message.content.prefix(300)))
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if message.content.count > 300 && !isExpanded {
                        Button("Show more") { onTap() }
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    } else if isExpanded && message.content.count > 300 {
                        Button("Show less") { onTap() }
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }

                    // Tool uses
                    if !message.toolUses.isEmpty {
                        Divider()
                        ForEach(message.toolUses) { tool in
                            ToolUseView(toolUse: tool)
                        }
                    }
                }
                .padding(10)
                .background(isUser ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isUser ? Color.accentColor.opacity(0.15) : Color.clear, lineWidth: 1)
                )
            }

            if isUser {
                Spacer(minLength: 40)
            }
        }
        .onTapGesture { onTap() }
    }
}

struct ToolUseView: View {
    let toolUse: ToolUse
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption)
                    Text(toolUse.name)
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(toolUse.isError ? .red : .blue)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(toolUse.input)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(4)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)

                if let result = toolUse.result {
                    Text(result)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(toolUse.isError ? .red : .secondary)
                        .textSelection(.enabled)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                }
            }
        }
    }
}

// MARK: - Summary Tab

struct SummaryTabView: View {
    let session: AgentSession
    @Binding var summary: String?
    @Binding var isSummarizing: Bool
    @Binding var summaryError: String?
    @EnvironmentObject var store: SessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary = summary {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI Summary", systemImage: "brain")
                            .font(.headline)
                        Text(summary)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }

                if let error = summaryError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.callout)
                }

                if session.messages.isEmpty {
                    Text("No messages to summarize")
                        .foregroundColor(.secondary)
                } else {
                    Button(action: generateSummary) {
                        if isSummarizing {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Generating summary...")
                            }
                        } else {
                            Label(summary == nil ? "Generate Summary" : "Regenerate Summary", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(isSummarizing || store.apiKey.isEmpty)

                    if store.apiKey.isEmpty {
                        Text("Add an Anthropic API key in Settings to enable AI summaries.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Auto-generated info
                VStack(alignment: .leading, spacing: 8) {
                    Label("Session Info", systemImage: "info.circle")
                        .font(.headline)
                    InfoRow(label: "First prompt", value: session.prompt)
                    if let task = session.currentTask {
                        InfoRow(label: "Current task", value: task)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
            .padding()
        }
    }

    private func generateSummary() {
        isSummarizing = true
        summaryError = nil
        Task {
            do {
                let result = try await ClaudeAPIService.shared.summarizeSession(session, apiKey: store.apiKey)
                await MainActor.run {
                    summary = result
                    isSummarizing = false
                }
            } catch {
                await MainActor.run {
                    summaryError = error.localizedDescription
                    isSummarizing = false
                }
            }
        }
    }
}

// MARK: - Details Tab

struct DetailsTabView: View {
    let session: AgentSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Session metadata
                GroupBox("Session") {
                    VStack(spacing: 0) {
                        InfoRow(label: "Session ID", value: session.sessionId, monospaced: true)
                        InfoRow(label: "Tool", value: session.tool.rawValue)
                        InfoRow(label: "Status", value: session.status.rawValue)
                        InfoRow(label: "Started", value: session.startTime.formatted())
                        InfoRow(label: "Last Updated", value: session.lastUpdateTime.formatted())
                        InfoRow(label: "Duration", value: formatDuration(session.duration))
                        if let dir = session.workingDirectory {
                            InfoRow(label: "Working Dir", value: dir, monospaced: true)
                        }
                        if let file = session.sourceFile {
                            InfoRow(label: "Source File", value: file, monospaced: true)
                        }
                    }
                }

                // Statistics
                GroupBox("Statistics") {
                    VStack(spacing: 0) {
                        InfoRow(label: "Messages", value: "\(session.messages.count)")
                        InfoRow(label: "Turns", value: "\(session.turnCount)")
                        if session.totalTokens > 0 {
                            InfoRow(label: "Total Tokens", value: "\(session.totalTokens)")
                        }
                        if session.totalCost > 0 {
                            InfoRow(label: "Estimated Cost", value: String(format: "$%.6f", session.totalCost))
                        }
                    }
                }

                // Tool uses
                let allToolUses = session.messages.flatMap { $0.toolUses }
                if !allToolUses.isEmpty {
                    GroupBox("Tool Uses (\(allToolUses.count))") {
                        let grouped = Dictionary(grouping: allToolUses, by: { $0.name })
                        ForEach(Array(grouped.keys.sorted()), id: \.self) { name in
                            InfoRow(label: name, value: "\(grouped[name]!.count)x")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t / 60), s = Int(t.truncatingRemainder(dividingBy: 60))
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        Divider()
    }
}
