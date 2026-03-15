import SwiftUI
import AppKit

@main
struct AgentViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = SessionStore.shared

    var body: some Scene {
        WindowGroup("AgentView") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session...") {
                    NotificationCenter.default.post(name: .showAddSession, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Refresh Sessions") {
                    Task {
                        await ClaudeSessionMonitor.shared.scanAllDirectories()
                        await CursorMonitor.shared.scanCursorDirectories()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Sessions") {
                Button("Clear Completed") {
                    SessionStore.shared.removeAllCompleted()
                }
                Button("Clear All Sessions") {
                    SessionStore.shared.clearAll()
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var store: SessionStore { SessionStore.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        startMonitors()

        // Allow app to run without dock icon
        NSApp.setActivationPolicy(.accessory)

        // Watch for session changes to update menu bar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuBarIcon),
            name: .sessionsDidChange,
            object: nil
        )
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateButtonAppearance(button: button, activeCount: 0)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(onOpenMainWindow: { [weak self] in
                self?.openMainWindow()
                self?.popover?.performClose(nil)
            })
            .environmentObject(SessionStore.shared)
        )
        self.popover = popover
    }

    private func updateButtonAppearance(button: NSStatusBarButton, activeCount: Int) {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "AgentView")?
            .withSymbolConfiguration(config)
        button.image = image

        if activeCount > 0 {
            button.title = " \(activeCount)"
        } else {
            button.title = ""
        }
    }

    @objc private func updateMenuBarIcon() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }
            let activeCount = self.store.activeSessions.count
            self.updateButtonAppearance(button: button, activeCount: activeCount)
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    // MARK: - Main Window

    func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.title == "AgentView" || $0.isKeyWindow }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Re-show window
            for window in NSApp.windows {
                if !window.isVisible {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
        }
    }

    // MARK: - Monitors

    private func startMonitors() {
        Task {
            await ClaudeSessionMonitor.shared.scanAllDirectories()
        }
        Task {
            await CursorMonitor.shared.scanCursorDirectories()
        }

        // Periodic refresh every 15 seconds
        Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task {
                await ClaudeSessionMonitor.shared.scanAllDirectories()
                await CursorMonitor.shared.scanCursorDirectories()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when window closes - stay in menu bar
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let sessionsDidChange = Notification.Name("sessionsDidChange")
    static let showAddSession = Notification.Name("showAddSession")
}
