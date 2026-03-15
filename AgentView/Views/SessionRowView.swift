import SwiftUI

// MARK: - Session Row View

struct SessionRowView: View {
    let session: AgentSession
    @EnvironmentObject var store: SessionStore

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

    var toolColor: Color {
        switch session.tool {
        case .claude: return .orange
        case .cursor: return .blue
        case .manual: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay {
                    if session.isLive {
                        PulsingCircle(color: statusColor)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                // Title row
                HStack(spacing: 4) {
                    // Tool badge
                    Text(session.tool.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(toolColor.opacity(0.15))
                        .foregroundColor(toolColor)
                        .cornerRadius(3)

                    Text(session.displayTitle)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }

                // Subtitle row
                HStack(spacing: 6) {
                    if let dir = session.workingDirectory {
                        Text(URL(fileURLWithPath: dir).lastPathComponent)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(session.lastUpdateTime, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Progress info
                if session.isLive, let task = session.currentTask {
                    Text(task)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .italic()
                }
            }

            Spacer(minLength: 0)

            // Message count badge
            if session.turnCount > 0 {
                Text("\(session.turnCount)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Pulsing Circle Animation

struct PulsingCircle: View {
    let color: Color
    @State private var scale = 1.0
    @State private var opacity = 0.7

    var body: some View {
        Circle()
            .fill(color.opacity(opacity))
            .scaleEffect(scale)
            .frame(width: 8, height: 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    scale = 1.8
                    opacity = 0.0
                }
            }
    }
}
