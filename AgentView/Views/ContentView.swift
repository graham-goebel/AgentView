import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var store: SessionStore
    @State private var showSettings = false
    @State private var showAddSession = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
        } detail: {
            if let session = store.selectedSession {
                SessionDetailView(session: session)
            } else {
                EmptyStateView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showAddSession = true }) {
                    Label("Add Session", systemImage: "plus")
                }
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gear")
                }
            }
            ToolbarItemGroup(placement: .navigation) {
                RefreshButton()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showAddSession) {
            AddSessionView()
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBar(text: $store.searchQuery)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            // Filter chips
            FilterChipsView()
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            Divider()

            // Stats bar
            StatsBarView()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            // Session list
            if store.filteredSessions.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(store.sessions.isEmpty ? "No sessions yet" : "No matching sessions")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    if store.sessions.isEmpty {
                        Text("Sessions will appear as Claude\nor Cursor agents run.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                Spacer()
            } else {
                List(store.filteredSessions, selection: $store.selectedSessionId) { session in
                    SessionRowView(session: session)
                        .tag(session.id)
                        .contextMenu {
                            SessionContextMenu(session: session)
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 260)
        .navigationTitle("AgentView")
        .navigationSubtitle("\(store.activeSessions.count) active")
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)
            TextField("Search sessions...", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Filter Chips

struct FilterChipsView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(
                    label: "Active",
                    isSelected: store.showOnlyActive,
                    action: { store.showOnlyActive.toggle() }
                )
                ForEach(AgentTool.allCases) { tool in
                    FilterChip(
                        label: tool.rawValue,
                        isSelected: store.filterTool == tool,
                        action: {
                            store.filterTool = store.filterTool == tool ? nil : tool
                        }
                    )
                }
                if store.filterTool != nil || store.showOnlyActive {
                    Button("Clear") {
                        store.filterTool = nil
                        store.showOnlyActive = false
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }
            }
        }
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stats Bar

struct StatsBarView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        HStack(spacing: 16) {
            StatItem(value: "\(store.sessions.count)", label: "Total")
            StatItem(value: "\(store.activeSessions.count)", label: "Active")
            Spacer()
            if store.totalCost > 0 {
                StatItem(value: String(format: "$%.3f", store.totalCost), label: "Cost")
            }
        }
    }
}

struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
    }
}

// MARK: - Context Menu

struct SessionContextMenu: View {
    let session: AgentSession
    @EnvironmentObject var store: SessionStore

    var body: some View {
        Button("Copy Session ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.sessionId, forType: .string)
        }
        if let dir = session.workingDirectory {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir)
            }
        }
        Divider()
        Button("Remove Session") {
            store.removeSession(session.id)
        }
    }
}

// MARK: - Refresh Button

struct RefreshButton: View {
    @EnvironmentObject var store: SessionStore
    @State private var isRefreshing = false

    var body: some View {
        Button(action: refresh) {
            Label("Refresh", systemImage: isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
        }
        .disabled(isRefreshing)
    }

    private func refresh() {
        isRefreshing = true
        Task {
            await ClaudeSessionMonitor.shared.scanAllDirectories()
            await CursorMonitor.shared.scanCursorDirectories()
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run { isRefreshing = false }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Select a Session")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Choose a session from the sidebar\nto view its details and progress.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Add Session View

struct AddSessionView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss
    @State private var sessionId = ""
    @State private var selectedTool: AgentTool = .claude
    @State private var prompt = ""
    @State private var workingDir = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Session Manually")
                .font(.headline)

            Form {
                Picker("Tool", selection: $selectedTool) {
                    ForEach(AgentTool.allCases) { tool in
                        Text(tool.rawValue).tag(tool)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Session ID", text: $sessionId)
                    .textFieldStyle(.roundedBorder)

                TextField("Initial Prompt", text: $prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                TextField("Working Directory (optional)", text: $workingDir)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Add") {
                    let session = AgentSession(
                        sessionId: sessionId.isEmpty ? UUID().uuidString : sessionId,
                        tool: selectedTool,
                        status: .active,
                        workingDirectory: workingDir.isEmpty ? nil : workingDir,
                        prompt: prompt.isEmpty ? "Manual session" : prompt
                    )
                    store.addSession(session)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(prompt.isEmpty && sessionId.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss
    @State private var apiKeyInput = ""
    @State private var showAPIKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Anthropic API Key")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Used to generate session summaries and insights.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    if showAPIKey {
                        TextField("sk-ant-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-ant-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showAPIKey ? "Hide" : "Show") {
                        showAPIKey.toggle()
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Data Management")
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 12) {
                    Button("Clear Completed Sessions") {
                        store.removeAllCompleted()
                    }
                    .foregroundColor(.orange)
                    Button("Clear All Sessions") {
                        store.clearAll()
                    }
                    .foregroundColor(.red)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    store.saveAPIKey(apiKeyInput)
                    dismiss()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 420, height: 320)
        .onAppear {
            apiKeyInput = store.apiKey
        }
    }
}
