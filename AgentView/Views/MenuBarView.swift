import SwiftUI

// MARK: - Menu Bar Popover View

struct MenuBarView: View {
    @EnvironmentObject var store: SessionStore
    var onOpenMainWindow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("AgentView")
                        .font(.headline)
                }

                Spacer()

                if store.activeSessions.isEmpty {
                    Text("No active sessions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 4) {
                        PulsingCircle(color: .green)
                            .frame(width: 8, height: 8)
                        Text("\(store.activeSessions.count) active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Sessions list
            if store.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No sessions")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("Run Claude or Cursor agents\nto see progress here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Show active sessions first, then recent
                        let displaySessions = store.activeSessions.isEmpty
                            ? Array(store.sessions.prefix(8))
                            : store.activeSessions + store.sessions
                                .filter { !$0.isLive }
                                .prefix(3)

                        ForEach(displaySessions) { session in
                            MenuBarSessionRow(session: session)
                                .onTapGesture {
                                    store.selectedSessionId = session.id
                                    onOpenMainWindow()
                                }
                            if session.id != displaySessions.last?.id {
                                Divider().padding(.leading, 12)
                            }
                        }

                        if store.sessions.count > 8 {
                            Button("View all \(store.sessions.count) sessions") {
                                onOpenMainWindow()
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            Divider()

            // Footer actions
            HStack(spacing: 0) {
                MenuBarActionButton(icon: "arrow.clockwise", label: "Refresh") {
                    Task {
                        await ClaudeSessionMonitor.shared.scanAllDirectories()
                        await CursorMonitor.shared.scanCursorDirectories()
                    }
                }
                Divider().frame(height: 20)
                MenuBarActionButton(icon: "macwindow", label: "Open App") {
                    onOpenMainWindow()
                }
                Divider().frame(height: 20)
                MenuBarActionButton(icon: "xmark", label: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 320)
    }
}

// MARK: - Menu Bar Session Row

struct MenuBarSessionRow: View {
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
        HStack(spacing: 8) {
            // Status dot
            ZStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                if session.isLive {
                    PulsingCircle(color: statusColor)
                        .frame(width: 7, height: 7)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.tool.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(toolColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(toolColor.opacity(0.12))
                        .cornerRadius(3)
                    Text(session.displayTitle)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                if let task = session.currentTask, session.isLive {
                    Text(task)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(session.lastUpdateTime, style: .relative)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(Color.clear)
        .buttonStyle(.plain)
    }

    var toolColor: Color {
        switch session.tool {
        case .claude: return .orange
        case .cursor: return .blue
        case .manual: return .purple
        }
    }
}

// MARK: - Menu Bar Action Button

struct MenuBarActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(isHovered ? Color(NSColor.selectedControlColor).opacity(0.3) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Menu Bar Status Icon

struct MenuBarStatusView: View {
    let activeCount: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "cpu")
                .font(.system(size: 13))
            if activeCount > 0 {
                Text("\(activeCount)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
        }
    }
}
