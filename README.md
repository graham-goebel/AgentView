# AgentView

A macOS menu bar app that tracks agent progress across AI tools like Claude Code and Cursor.

## Features

- **Menu Bar Icon** — Lives in your Mac's menu bar with a badge showing active session count
- **Live Session Tracking** — Automatically discovers and monitors Claude Code sessions from `~/.claude/projects/`
- **Cursor Support** — Scans Cursor workspace storage for active conversations
- **Session Details** — View full message history, tool uses, token counts, and cost estimates
- **AI Summaries** — Generate intelligent summaries of sessions using the Claude API (optional)
- **Persistence** — Sessions persist across app restarts
- **Search & Filter** — Filter by tool, status, or search across prompts

## Requirements

- macOS 13.0+
- Xcode 15+

## Setup

1. Open `AgentView.xcodeproj` in Xcode
2. Set your Development Team in the target's Signing & Capabilities settings
3. Build and run (`Cmd+R`)
4. The app lives in your menu bar — click the CPU icon to see active sessions
5. (Optional) Add your Anthropic API key in Settings to enable AI summaries

## Architecture

```
AgentView/
├── Models/
│   ├── AgentSession.swift       # Data models for sessions, messages, tool uses
│   └── SessionStore.swift       # Observable store with persistence
├── Monitors/
│   ├── ClaudeSessionMonitor.swift  # Watches ~/.claude/ for session JSONL files
│   └── CursorMonitor.swift         # Scans Cursor workspace storage
├── Views/
│   ├── ContentView.swift        # Main app window (NavigationSplitView)
│   ├── MenuBarView.swift        # Menu bar popover (compact view)
│   ├── SessionRowView.swift     # Session list row with live indicator
│   └── SessionDetailView.swift  # Full session details (messages, summary, info)
├── Services/
│   └── ClaudeAPIService.swift   # Anthropic API for session summaries
└── AgentViewApp.swift           # App entry point + AppDelegate (NSStatusItem)
```

## How It Works

### Claude Session Monitoring
The app watches `~/.claude/projects/` for JSONL session files. Each file is parsed to extract:
- Session ID and working directory
- User prompts and assistant responses
- Tool use calls (file reads, writes, searches, etc.)
- Token counts and cost estimates
- Session status (active if modified < 30s ago)

### Cursor Session Monitoring
Scans `~/Library/Application Support/Cursor/User/workspaceStorage/` for chat JSON files.

### Session Status
- 🟢 **Active** — Modified in the last 30 seconds
- 🟡 **Idle** — Modified in the last 5 minutes
- ⚫ **Completed** — Not modified for more than 5 minutes

### AI Summaries
With an Anthropic API key configured, you can generate concise summaries of any session using Claude.

## Menu Bar Usage

- **Click** the CPU icon to open the popover
- **Active sessions** appear at the top with a pulsing indicator
- **Click any session** to open the full app and see details
- **Refresh** rescans all monitored directories

## Data Storage

Session data is persisted to:
`~/Library/Application Support/AgentView/sessions.json`

The API key is stored in `UserDefaults` (not in the Keychain — for production use, migrate to the Keychain).
