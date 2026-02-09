import SwiftUI

@main
struct AirplaneTracker3DApp: App {
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
