import SwiftUI

@main
struct AirplaneTracker3DApp: App {
    @StateObject private var menuBarManager = MenuBarManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 4) {
                Text("Aircraft Tracked: \(menuBarManager.aircraftCount)")
                    .font(.headline)
                Divider()
                Button("Show Window") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(8)
        } label: {
            Label("\(menuBarManager.aircraftCount)", systemImage: "airplane")
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - Menu Bar Commands

struct AppCommands: Commands {
    var body: some Commands {
        CommandMenu("Tracker") {
            Button("Reset Camera") {
                NotificationCenter.default.post(name: .resetCamera, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Toggle Auto-Rotate") {
                NotificationCenter.default.post(name: .toggleAutoRotate, object: nil)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Divider()

            Button("Cycle Theme") {
                NotificationCenter.default.post(name: .cycleTheme, object: nil)
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button("Search Airport") {
                NotificationCenter.default.post(name: .toggleSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Toggle Info Panel") {
                NotificationCenter.default.post(name: .toggleInfoPanel, object: nil)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Toggle Statistics") {
                NotificationCenter.default.post(name: .toggleStats, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
