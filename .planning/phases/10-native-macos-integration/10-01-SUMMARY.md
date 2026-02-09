---
phase: 10-native-macos-integration
plan: 01
subsystem: ui
tags: [MenuBarExtra, NSDockTile, UNUserNotificationCenter, SwiftUI, macOS-native]

# Dependency graph
requires:
  - phase: 09-ui-controls-settings-airports
    provides: "SettingsView with @AppStorage, Renderer .aircraftCountUpdated notification, ThemeManager notification names"
provides:
  - "Menu bar status item with live aircraft count (MenuBarExtra scene)"
  - "Dock icon badge with aircraft count (DockBadgeManager)"
  - "macOS notification alerts for emergency squawks and watched callsigns (NotificationManager)"
  - "AlertCondition Codable model for alert configuration"
  - "Settings > Notifications tab with enable/disable, permission, squawk, callsign controls"
affects: [10-02-distribution]

# Tech tracking
tech-stack:
  added: [UserNotifications framework]
  patterns: [MenuBarExtra scene, ObservableObject singleton for cross-scene state, NotificationCenter state broadcast with typed payloads, UNUserNotificationCenterDelegate for foreground delivery]

key-files:
  created:
    - AirplaneTracker3D/Services/MenuBarManager.swift
    - AirplaneTracker3D/Services/DockBadgeManager.swift
    - AirplaneTracker3D/Services/NotificationManager.swift
    - AirplaneTracker3D/Models/AlertCondition.swift
  modified:
    - AirplaneTracker3D/AirplaneTracker3DApp.swift
    - AirplaneTracker3D/Rendering/Renderer.swift
    - AirplaneTracker3D/Views/SettingsView.swift
    - AirplaneTracker3D.xcodeproj/project.pbxproj

key-decisions:
  - "MenuBarManager @StateObject in App struct drives MenuBarExtra label via @Published aircraftCount"
  - "Aircraft states broadcast via existing NotificationCenter .aircraftCountUpdated userInfo for zero-overhead alert evaluation"
  - "NotificationManager singleton with @AppStorage for enable/disable, 5-min cooldown deduplication per aircraft per condition"
  - "UNUserNotificationCenterDelegate foreground delivery for banner+sound even when app is active"

patterns-established:
  - "Services/ directory for app-level managers (MenuBarManager, DockBadgeManager, NotificationManager)"
  - "ObservableObject singleton pattern for cross-scene state sharing (MenuBarManager, NotificationManager)"
  - "@AppStorage in both SettingsView and NotificationManager for two-way notification preference binding"

# Metrics
duration: 4min
completed: 2026-02-09
---

# Phase 10 Plan 01: Native macOS Integration Summary

**MenuBarExtra with live aircraft count, dock badge, and configurable notification alerts for emergency squawks and watched callsigns via UNUserNotificationCenter**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-09T00:32:43Z
- **Completed:** 2026-02-09T00:37:08Z
- **Tasks:** 2
- **Files modified:** 8 (4 created, 4 modified)

## Accomplishments
- Menu bar status item shows airplane icon with live aircraft count, dropdown with "Show Window" and "Quit" actions
- Dock icon displays red badge with aircraft count, auto-clears when count is 0
- NotificationManager evaluates emergency squawk codes (7500/7600/7700) and watched callsigns with 5-minute per-aircraft cooldown
- Settings > Notifications tab with enable toggle, permission request, emergency squawk toggle, and watched callsigns field
- Notifications show as macOS banners even when app is in foreground via UNUserNotificationCenterDelegate

## Task Commits

Each task was committed atomically:

1. **Task 1: Menu bar status item, dock badge, and aircraft state broadcast** - `4cf266d` (feat)
2. **Task 2: Notification system with alert conditions and Settings tab** - `fefa233` (feat)

## Files Created/Modified
- `AirplaneTracker3D/Services/MenuBarManager.swift` - ObservableObject managing aircraft count state for menu bar and dock badge, forwards states to NotificationManager
- `AirplaneTracker3D/Services/DockBadgeManager.swift` - Singleton updating NSDockTile.badgeLabel with aircraft count
- `AirplaneTracker3D/Services/NotificationManager.swift` - UNUserNotificationCenter wrapper with permission request, alert evaluation, cooldown deduplication, foreground delivery
- `AirplaneTracker3D/Models/AlertCondition.swift` - AlertCondition Codable model with emergency squawk and callsign alert types
- `AirplaneTracker3D/AirplaneTracker3DApp.swift` - Added @StateObject MenuBarManager, MenuBarExtra scene with airplane icon + count label
- `AirplaneTracker3D/Rendering/Renderer.swift` - Added aircraft states array to .aircraftCountUpdated notification userInfo
- `AirplaneTracker3D/Views/SettingsView.swift` - Added third Notifications tab with enable/disable, permission, squawk alerts, watched callsigns
- `AirplaneTracker3D.xcodeproj/project.pbxproj` - Added Services group with 3 new files, AlertCondition in Models

## Decisions Made
- Used @StateObject MenuBarManager in App struct (not @State) so ObservableObject drives MenuBarExtra label updates reactively
- Piggybacked alert evaluation on existing 60-frame aircraft count broadcast rather than adding a new timer or polling mechanism
- Created NotificationManager stub in Task 1 to resolve forward reference from MenuBarManager (fully implemented in Task 2)
- Used @AppStorage for notification preferences so SettingsView and NotificationManager stay in sync via UserDefaults

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Created NotificationManager stub in Task 1 for forward reference**
- **Found during:** Task 1 (MenuBarManager creation)
- **Issue:** MenuBarManager references NotificationManager.shared.evaluateAlerts() which doesn't exist until Task 2
- **Fix:** Created minimal NotificationManager stub with shared singleton and empty evaluateAlerts() method, fully implemented in Task 2
- **Files modified:** AirplaneTracker3D/Services/NotificationManager.swift
- **Verification:** Build succeeded with stub, fully replaced in Task 2
- **Committed in:** 4cf266d (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Stub was necessary to maintain build-after-each-task invariant. No scope creep -- stub replaced by full implementation in Task 2.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All native macOS integration features (menu bar, dock badge, notifications) are complete and functional
- Ready for 10-02 (distribution/notarization) which focuses on code signing and DMG packaging
- Notification permission must be granted by user on first use (handled via Settings > Notifications > Request Permission)

## Self-Check: PASSED

- All 5 created files verified on disk
- Both task commits (4cf266d, fefa233) verified in git log
- xcodebuild Debug build succeeded with zero errors

---
*Phase: 10-native-macos-integration*
*Completed: 2026-02-09*
