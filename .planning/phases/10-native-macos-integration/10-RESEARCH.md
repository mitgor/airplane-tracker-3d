# Phase 10: Native macOS Integration + Distribution - Research

**Researched:** 2026-02-09
**Domain:** macOS native APIs (MenuBarExtra, NSDockTile, UNUserNotificationCenter, SwiftUI Commands), Code Signing, Notarization, DMG Distribution
**Confidence:** HIGH

## Summary

This phase adds four categories of native macOS integration to the existing SwiftUI + Metal 3 Airplane Tracker 3D app: (1) a menu bar status item showing live aircraft count, (2) dock icon badge with aircraft count, (3) configurable macOS notifications for aircraft alerts, and (4) enhanced native menus. It also covers building and distributing the app as a signed, notarized DMG.

The existing codebase already has a SwiftUI `App` with `WindowGroup`, `Settings`, and a `CommandMenu("Tracker")` with custom keyboard shortcuts. The `StatisticsCollector` samples aircraft count every 5 seconds, and the `Renderer` posts `.aircraftCountUpdated` notifications every 60 frames (~1 second). The `AircraftModel` and `InterpolatedAircraftState` already carry `squawk`, `callsign`, `altitude`, `lat`, `lon` -- all the data needed for notification alert conditions.

**Primary recommendation:** Use SwiftUI's `MenuBarExtra` scene (macOS 13+, well within the macOS 14 deployment target) with a dynamic `@State` label for the menu bar aircraft count. Use `NSApplication.shared.dockTile.badgeLabel` for the dock badge. Use `UNUserNotificationCenter` for local notifications. Use `CommandGroup(replacing:)` and `CommandGroup(after:)` to customize standard menus. Use `create-dmg` (Homebrew shell script) plus `xcrun notarytool` for distribution.

## Standard Stack

### Core (All Built-in -- No External Dependencies for Features)

| API / Framework | Platform | Purpose | Why Standard |
|-----------------|----------|---------|--------------|
| SwiftUI `MenuBarExtra` | macOS 13+ | Menu bar status item with aircraft count | Native SwiftUI scene type, no AppKit bridging needed |
| `NSDockTile` / `NSApplication.shared.dockTile` | AppKit (macOS 10.0+) | Dock icon badge label | Only API for dock badges, one-liner |
| `UNUserNotificationCenter` | UserNotifications framework (macOS 10.14+) | Local notification alerts | Standard Apple notification framework |
| SwiftUI `CommandGroup` / `CommandMenu` | macOS 11+ | Native menu bar menus | Already partially used in existing codebase |
| `codesign` + `xcrun notarytool` | Xcode CLI | Code signing + notarization | Apple's required tools, no alternatives |

### Supporting (Distribution Tooling)

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `create-dmg` (shell script) | Latest (Homebrew) | DMG creation with background, icon layout, app-drop-link | Creating the distributable DMG installer |
| `hdiutil` | Built-in macOS | Low-level DMG creation | Fallback if create-dmg unavailable |
| `xcrun stapler` | Xcode CLI | Staple notarization ticket to DMG | After notarization succeeds |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `MenuBarExtra` | `NSStatusItem` via AppKit | More control but requires NSApplicationDelegate bridging; MenuBarExtra is pure SwiftUI and sufficient |
| `create-dmg` (shell) | `sindresorhus/create-dmg` (npm) | npm version auto-codesigns but requires Node.js; shell version is more common for native Swift projects |
| `create-dmg` | Manual `hdiutil` | Full control but requires many manual steps for icon layout, background image, Applications symlink |
| `UNUserNotificationCenter` | `NSUserNotification` (deprecated) | NSUserNotification was deprecated in macOS 10.14; UNUserNotificationCenter is the only supported path |

**Installation (distribution tools only):**
```bash
brew install create-dmg
```

No additional Swift packages are needed -- all APIs are built into macOS SDK.

## Architecture Patterns

### Recommended New File Structure

```
AirplaneTracker3D/
├── AirplaneTracker3DApp.swift       # Modified: add MenuBarExtra scene
├── Services/
│   ├── MenuBarManager.swift         # NEW: manages menu bar status item state
│   ├── DockBadgeManager.swift       # NEW: updates dock tile badge
│   └── NotificationManager.swift    # NEW: UNUserNotificationCenter wrapper
├── Models/
│   └── AlertCondition.swift         # NEW: configurable alert conditions
├── Views/
│   ├── SettingsView.swift           # Modified: add Notifications tab
│   └── MenuBarContentView.swift     # NEW: dropdown content for menu bar
├── Commands/
│   └── AppCommands.swift            # Extracted + enhanced from AirplaneTracker3DApp.swift
└── Scripts/
    └── build-dmg.sh                 # NEW: build + sign + notarize + DMG script
```

### Pattern 1: MenuBarExtra with Dynamic Label

**What:** Add a `MenuBarExtra` scene alongside the existing `WindowGroup` in the app's body. The MenuBarExtra label updates dynamically via `@State` to show the current aircraft count.

**When to use:** When the app needs a persistent status indicator in the macOS menu bar.

**Example:**
```swift
// Source: Apple Developer Documentation + verified community patterns
@main
struct AirplaneTracker3DApp: App {
    @State private var aircraftCount: Int = 0

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

        // Menu bar status item showing aircraft count
        MenuBarExtra {
            MenuBarContentView(aircraftCount: aircraftCount)
        } label: {
            Label {
                Text("\(aircraftCount)")
            } icon: {
                Image(systemName: "airplane")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
```

**Key detail:** When both a title and system image are provided, only the image shows by default. To show BOTH icon and count text, use the `label:` closure with a `Label` view. The `@State var aircraftCount` in the App struct can be updated via NotificationCenter observer or by making it flow from a shared ObservableObject.

### Pattern 2: Dock Badge Updates

**What:** Update the dock icon badge with the aircraft count using `NSDockTile.badgeLabel`.

**When to use:** Whenever the aircraft count changes.

**Example:**
```swift
// Source: Apple NSDockTile documentation
@MainActor
final class DockBadgeManager {
    static let shared = DockBadgeManager()

    func updateBadge(count: Int) {
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    func clearBadge() {
        NSApplication.shared.dockTile.badgeLabel = nil
    }
}
```

**Key detail:** `badgeLabel` must be set on the main thread. Setting it to `nil` removes the badge. The dock tile automatically renders a red badge overlay on the app icon -- no custom drawing needed.

### Pattern 3: Local Notifications for Aircraft Alerts

**What:** Use `UNUserNotificationCenter` to send macOS notifications when configurable conditions are met (specific callsigns appearing, emergency squawk codes, altitude/distance thresholds).

**When to use:** When real-time aircraft data matches user-configured alert conditions.

**Example:**
```swift
// Source: Apple UNUserNotificationCenter documentation + community patterns
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            print("Notification permission error: \(error)")
        }
    }

    func sendAlert(title: String, body: String, identifier: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Immediate trigger (nil trigger = deliver immediately, but we use 0.1s)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
```

### Pattern 4: Alert Condition Configuration

**What:** A data model for user-configurable alert conditions stored in UserDefaults.

**When to use:** To let users specify which aircraft events trigger notifications.

**Example:**
```swift
struct AlertCondition: Codable, Identifiable {
    let id: UUID
    var type: AlertType
    var isEnabled: Bool

    enum AlertType: Codable {
        case callsign(String)              // e.g., "UAL123"
        case squawk(String)                // e.g., "7700" (emergency)
        case altitudeBelow(Float)          // feet
        case altitudeAbove(Float)          // feet
        case emergencySquawk               // 7500, 7600, 7700
    }
}
```

**Emergency squawk codes to detect:**
- `7700` -- General emergency
- `7600` -- Communication failure (radio failure)
- `7500` -- Hijack / unlawful interference

### Pattern 5: Enhanced Standard Menus via CommandGroup

**What:** Use `CommandGroup(replacing:)` and `CommandGroup(after:)` to customize the standard File, Edit, View, and Window menus.

**When to use:** To provide macOS-standard menu structure with app-specific actions.

**Example:**
```swift
struct AppCommands: Commands {
    var body: some Commands {
        // Replace "New Window" in File menu (prevent multiple windows)
        CommandGroup(replacing: .newItem) { }

        // Add app-specific items after standard View menu items
        CommandGroup(after: .toolbar) {
            Button("Toggle Info Panel") {
                NotificationCenter.default.post(name: .toggleInfoPanel, object: nil)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Toggle Statistics") {
                NotificationCenter.default.post(name: .toggleStats, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        // Custom "Tracker" menu (already exists, enhance it)
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
        }
    }
}
```

**Available `CommandGroupPlacement` values for standard menus:**

| Placement | Menu | What It Controls |
|-----------|------|-----------------|
| `.appInfo` | App menu | About dialog |
| `.appSettings` | App menu | Preferences/Settings |
| `.appTermination` | App menu | Quit |
| `.appVisibility` | App menu | Hide/Show |
| `.systemServices` | App menu | Services submenu |
| `.newItem` | File | New Window/Document |
| `.saveItem` | File | Save/Save As |
| `.printItem` | File | Print |
| `.importExport` | File | Import/Export |
| `.undoRedo` | Edit | Undo/Redo |
| `.pasteboard` | Edit | Cut/Copy/Paste |
| `.textEditing` | Edit | Find/Replace |
| `.textFormatting` | Format | Font/Text formatting |
| `.toolbar` | View | Toolbar controls |
| `.sidebar` | View | Sidebar toggle |
| `.windowArrangement` | Window | Tile/Arrange |
| `.windowList` | Window | Open windows list |
| `.windowSize` | Window | Zoom/Minimize |
| `.singleWindowList` | Window | Single window |
| `.help` | Help | Help items |

### Anti-Patterns to Avoid

- **Anti-pattern: Using NSStatusItem directly.** SwiftUI's `MenuBarExtra` handles the NSStatusItem lifecycle. Do not create NSStatusItem manually alongside MenuBarExtra -- they will conflict.
- **Anti-pattern: Polling for notification triggers.** Do not create a timer that constantly checks alert conditions. Instead, evaluate alert conditions inline when new aircraft data arrives (inside the existing polling/interpolation flow).
- **Anti-pattern: Showing raw aircraft count as dock badge when count is 0.** Set `badgeLabel = nil` when count is 0 to remove the badge entirely rather than showing "0".
- **Anti-pattern: Sending duplicate notifications.** Track which alerts have already fired (by aircraft hex + condition type) and implement a cooldown period to avoid spamming.
- **Anti-pattern: Using deprecated NSUserNotification.** It was deprecated in macOS 10.14. Always use UNUserNotificationCenter.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Menu bar status item | Custom NSStatusItem with AppKit bridging | `MenuBarExtra` SwiftUI scene | MenuBarExtra is pure SwiftUI, handles lifecycle, works alongside WindowGroup |
| Dock badge rendering | Custom NSDockTile contentView with drawn badge | `NSDockTile.badgeLabel` string property | System renders the badge automatically with correct styling |
| Notification permissions + delivery | Custom alert system or NSUserNotification | `UNUserNotificationCenter` | Handles permissions, scheduling, foreground display, and integrates with macOS Notification Center |
| DMG creation with layout | Manual hdiutil + AppleScript for icon positioning | `create-dmg` shell script | Handles background image, icon positions, Applications symlink, volume name in one command |
| Code signing validation | Manual entitlements checking | `codesign --verify --deep --strict` | System tool that validates the entire bundle hierarchy |

**Key insight:** Every feature in this phase has a first-party Apple API or well-established community tool. There is zero need for third-party Swift packages.

## Common Pitfalls

### Pitfall 1: MenuBarExtra Label Not Updating

**What goes wrong:** The aircraft count in the menu bar appears static and never changes.
**Why it happens:** `@State` in the `App` struct does not automatically receive updates from NotificationCenter or other data sources. The state must be explicitly wired up.
**How to avoid:** Use `.onReceive(NotificationCenter.default.publisher(for: .aircraftCountUpdated))` on a view inside the MenuBarExtra, or use a shared `@Observable` / `@ObservableObject` that both the main window and menu bar reference.
**Warning signs:** Count shows as 0 or the initial value forever.

### Pitfall 2: Notification Permission Not Requested

**What goes wrong:** Notifications never appear because permission was never requested.
**Why it happens:** `UNUserNotificationCenter.requestAuthorization()` must be called explicitly. Unlike iOS, macOS does not automatically prompt.
**How to avoid:** Request permission on first launch or when user enables notifications in Settings. Store the authorization status and check it before attempting to send notifications.
**Warning signs:** `isAuthorized` is always false; no system permission dialog appears.

### Pitfall 3: Notifications Not Shown While App is Foreground

**What goes wrong:** Notifications fire but no banner appears because the app is in the foreground.
**Why it happens:** By default, macOS suppresses notification banners when the originating app is frontmost.
**How to avoid:** Implement `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)` and return `[.banner, .sound]` in the completion handler. Set the delegate early (in `applicationDidFinishLaunching` or app init).
**Warning signs:** Notifications only appear when switching away from the app.

### Pitfall 4: Notification Spam from Continuous Data

**What goes wrong:** Hundreds of duplicate notifications for the same aircraft event.
**Why it happens:** Aircraft data updates every 1-5 seconds. If alert conditions are checked every update without deduplication, the same aircraft triggers the same alert repeatedly.
**How to avoid:** Maintain a `Set<String>` of recently-fired alert keys (e.g., `"hex-squawk7700"`). Use a cooldown timer (e.g., 5 minutes per aircraft per condition type). Clear fired alerts when the aircraft disappears from the data.
**Warning signs:** Notification Center fills with identical alerts.

### Pitfall 5: Hardened Runtime Blocks Network Access

**What goes wrong:** The app crashes or fails to fetch ADS-B data after code signing with hardened runtime.
**Why it happens:** Hardened runtime restricts certain capabilities by default. The app needs network access to fetch flight data.
**How to avoid:** Add `com.apple.security.network.client` entitlement (outgoing network connections). This is required for the app to make HTTP requests to airplanes.live and adsb.lol APIs.
**Warning signs:** URLSession requests fail with security errors after signing.

### Pitfall 6: Code Signing Identity Not Found

**What goes wrong:** `codesign` fails with "no identity found" or notarization is rejected.
**Why it happens:** The current project has `CODE_SIGN_IDENTITY = "-"` (ad-hoc signing) and `DEVELOPMENT_TEAM = ""` (no team). Notarization requires a valid Developer ID Application certificate.
**How to avoid:** A paid Apple Developer Program membership ($99/year) is required. Generate a "Developer ID Application" certificate in the Apple Developer portal. Set `CODE_SIGN_IDENTITY = "Developer ID Application"` and `DEVELOPMENT_TEAM` in the Xcode project.
**Warning signs:** Build succeeds but notarization submission is rejected.

### Pitfall 7: DMG Not Stapled After Notarization

**What goes wrong:** Users see Gatekeeper warnings despite successful notarization.
**Why it happens:** Notarization only registers the ticket with Apple servers. The ticket must be stapled to the DMG for offline verification.
**How to avoid:** Always run `xcrun stapler staple YourApp.dmg` after successful notarization. Verify with `xcrun stapler validate`.
**Warning signs:** Gatekeeper warns on first launch even though `notarytool` reported success.

## Code Examples

### Complete MenuBarExtra Integration with Shared State

```swift
// Source: Verified from Apple documentation and multiple community examples

import SwiftUI

@main
struct AirplaneTracker3DApp: App {
    @State private var aircraftCount: Int = 0

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: .aircraftCountUpdated)) { notification in
                    if let count = notification.userInfo?["count"] as? Int {
                        aircraftCount = count
                    }
                }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("Aircraft Tracked: \(aircraftCount)")
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
            HStack(spacing: 4) {
                Image(systemName: "airplane")
                Text("\(aircraftCount)")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
```

### Dock Badge Update from Existing Notification Flow

```swift
// Source: Apple NSDockTile documentation

// In ContentView or a dedicated manager, listen for aircraft count updates:
.onReceive(NotificationCenter.default.publisher(for: .aircraftCountUpdated)) { notification in
    if let count = notification.userInfo?["count"] as? Int {
        aircraftCount = count
        // Update dock badge
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
}
```

### Notification Manager with Alert Condition Evaluation

```swift
// Source: Apple UNUserNotificationCenter documentation

import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var isAuthorized = false
    @AppStorage("notificationsEnabled") var notificationsEnabled = false
    @AppStorage("alertOnEmergencySquawk") var alertOnEmergencySquawk = true

    /// Tracks recently fired alerts to prevent spam. Key: "hex-conditionType"
    private var firedAlerts: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 300 // 5 minutes

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() async {
        do {
            isAuthorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            isAuthorized = false
        }
    }

    func evaluateAlerts(for states: [InterpolatedAircraftState]) {
        guard notificationsEnabled, isAuthorized else { return }

        let now = Date()
        // Clean expired cooldowns
        firedAlerts = firedAlerts.filter { now.timeIntervalSince($0.value) < cooldownInterval }

        for aircraft in states {
            // Emergency squawk detection
            if alertOnEmergencySquawk {
                let emergencySquawks = ["7500", "7600", "7700"]
                if emergencySquawks.contains(aircraft.squawk) {
                    let key = "\(aircraft.hex)-squawk-\(aircraft.squawk)"
                    guard firedAlerts[key] == nil else { continue }
                    firedAlerts[key] = now

                    let squawkMeaning: String
                    switch aircraft.squawk {
                    case "7700": squawkMeaning = "EMERGENCY"
                    case "7600": squawkMeaning = "RADIO FAILURE"
                    case "7500": squawkMeaning = "HIJACK"
                    default: squawkMeaning = "ALERT"
                    }

                    sendNotification(
                        title: "Squawk \(aircraft.squawk) - \(squawkMeaning)",
                        body: "\(aircraft.callsign.isEmpty ? aircraft.hex : aircraft.callsign) at \(Int(aircraft.altitude)) ft",
                        identifier: key
                    )
                }
            }
        }
    }

    private func sendNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // Show banners even when app is foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
```

### Build + Sign + Notarize + DMG Script

```bash
#!/bin/bash
# Source: Apple notarization documentation + create-dmg docs

set -e

APP_NAME="AirplaneTracker3D"
SCHEME="AirplaneTracker3D"
PROJECT="${APP_NAME}.xcodeproj"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_PATH="build/export"
DMG_NAME="${APP_NAME}.dmg"
BUNDLE_ID="com.airplanetracker3d.app"
NOTARY_PROFILE="notary-airplanetracker"  # stored via xcrun notarytool store-credentials

# 1. Archive
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH"

# 2. Export (requires ExportOptions.plist)
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath "$EXPORT_PATH"

# 3. Create DMG
create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon "${APP_NAME}.app" 150 190 \
    --app-drop-link 450 190 \
    --icon-size 100 \
    "build/${DMG_NAME}" \
    "${EXPORT_PATH}/"

# 4. Notarize
xcrun notarytool submit "build/${DMG_NAME}" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# 5. Staple
xcrun stapler staple "build/${DMG_NAME}"

# 6. Verify
xcrun stapler validate "build/${DMG_NAME}"
echo "Done! DMG ready at build/${DMG_NAME}"
```

### ExportOptions.plist for Developer ID Distribution

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

### Required Entitlements File

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required: app fetches flight data over the network -->
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

**Note:** The app does NOT need App Sandbox for distribution outside the Mac App Store. Hardened Runtime (enabled via `codesign --options runtime`) is sufficient for notarization. If sandboxing is desired later, additional entitlements for network access would be needed.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NSStatusItem` + AppKit | `MenuBarExtra` SwiftUI scene | macOS 13 (WWDC 2022) | Pure SwiftUI, no AppKit bridging needed |
| `NSUserNotification` | `UNUserNotificationCenter` | macOS 10.14 (2018) | NSUserNotification fully deprecated |
| `xcrun altool --notarize-app` | `xcrun notarytool submit` | Xcode 13 (2021) | altool deprecated Nov 2023; notarytool is required |
| Manual DMG with AppleScript | `create-dmg` shell script | ~2015 | One command replaces 50+ lines of AppleScript |
| `CommandMenu` only | `CommandGroup` + `CommandMenu` | macOS 11 (2020) | Can now customize standard menus, not just add new ones |

**Deprecated/outdated:**
- `NSUserNotification` / `NSUserNotificationCenter`: Deprecated macOS 10.14. Do not use.
- `xcrun altool`: Deprecated November 2023. Use `notarytool` instead.
- `NSDockTile.display()` with custom `contentView`: Only needed for custom dock tile rendering. For simple text badges, `badgeLabel` is sufficient.

## Open Questions

1. **Apple Developer Program Membership**
   - What we know: Notarization and Developer ID signing require a paid Apple Developer Program membership ($99/year). Without it, the app can only be distributed unsigned (users must right-click > Open to bypass Gatekeeper).
   - What's unclear: Whether the project owner already has a membership.
   - Recommendation: Document both paths -- unsigned distribution (right-click to open) and signed/notarized DMG. Make the build script handle both cases.

2. **MenuBarExtra Label Text Width**
   - What we know: The menu bar has limited horizontal space. Showing "airplane icon + 4-digit count" could take up noticeable space.
   - What's unclear: Exact pixel limits before macOS truncates or hides the item.
   - Recommendation: Keep the label compact: icon + count number only. Test with 4-digit counts (e.g., "1234").

3. **Notification Rate Limiting by macOS**
   - What we know: macOS may throttle rapid successive notifications from the same app.
   - What's unclear: Exact throttling thresholds.
   - Recommendation: The 5-minute cooldown per aircraft per condition type should be well within macOS limits. If issues arise, increase cooldown.

4. **MenuBarExtra @State Synchronization**
   - What we know: `@State` in the `App` struct works for MenuBarExtra labels. NotificationCenter `.onReceive` works on SwiftUI views inside WindowGroup.
   - What's unclear: Whether `.onReceive` modifiers work directly on the `App` struct or only inside views.
   - Recommendation: If direct `@State` update on the App struct is problematic, use a shared `@Observable` class that both ContentView and MenuBarExtra reference.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation: `MenuBarExtra` -- SwiftUI scene for macOS menu bar items (macOS 13+)
- Apple Developer Documentation: `NSDockTile` -- dock tile badge management via `badgeLabel` property
- Apple Developer Documentation: `UNUserNotificationCenter` -- local notification scheduling and permissions
- Apple Developer Documentation: `CommandGroup` / `CommandGroupPlacement` -- standard macOS menu customization
- Apple Developer Documentation: Hardened Runtime and notarization requirements
- Apple Developer Documentation: `xcrun notarytool` for notarization submission

### Secondary (MEDIUM confidence)
- [Nil Coalescing: Build a macOS menu bar utility in SwiftUI](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) -- verified MenuBarExtra patterns and label customization
- [Swift with Majid: Commands in SwiftUI](https://swiftwithmajid.com/2020/11/24/commands-in-swiftui/) -- CommandGroup and CommandMenu patterns
- [Daniel Saidi: Customizing the macOS menu bar in SwiftUI](https://danielsaidi.com/blog/2023/11/22/customizing-the-macos-menu-bar-in-swiftui) -- menu customization examples
- [Scripting OS X: Notarize with notarytool](https://scriptingosx.com/2021/07/notarize-a-command-line-tool-with-notarytool/) -- verified notarytool workflow
- [Christian Tietze: Mac App Notarization Workflow](https://christiantietze.de/posts/2022/07/mac-app-notarization-workflow-in-2022/) -- end-to-end signing + notarization
- [create-dmg GitHub](https://github.com/create-dmg/create-dmg) -- DMG creation tool documentation
- [Peerdh: Integrating SwiftUI with macOS Notifications](https://peerdh.com/blogs/programming-insights/integrating-swiftui-with-macos-notifications-for-real-time-updates-1) -- UNUserNotificationCenter macOS patterns

### Tertiary (LOW confidence)
- Community reports suggest MenuBarExtra `.menu` style may not re-render its body view when the menu opens (FB13683957). If confirmed, `.window` style is the workaround.
- Rate limiting behavior of macOS notification system is based on developer reports, not official documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** -- All APIs are first-party Apple with stable documentation. MenuBarExtra is available since macOS 13, well within the macOS 14 deployment target.
- Architecture: **HIGH** -- Patterns are well-established and verified across multiple sources. The existing codebase architecture (NotificationCenter-based communication, @AppStorage for settings) integrates naturally.
- Pitfalls: **HIGH** -- Common issues are well-documented across community sources. The foreground notification suppression and hardened runtime entitlements are particularly well-known.
- Distribution/Notarization: **MEDIUM** -- The workflow is well-documented but depends on Apple Developer Program membership status and certificate availability, which are project-specific.

**Research date:** 2026-02-09
**Valid until:** 2026-05-09 (90 days -- these are stable macOS APIs unlikely to change)
