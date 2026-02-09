---
phase: 10-native-macos-integration
plan: 02
subsystem: ui
tags: [CommandGroup, SwiftUI-menus, entitlements, hardened-runtime, DMG, code-signing, notarization, distribution]

# Dependency graph
requires:
  - phase: 10-native-macos-integration
    provides: "MenuBarExtra scene, CommandMenu('Tracker') with 6 keyboard shortcuts, Settings scene"
provides:
  - "Standard macOS menus (File, Edit, View, Window) via CommandGroup placements"
  - "Entitlements plist with com.apple.security.network.client for hardened runtime"
  - "ExportOptions.plist for Developer ID distribution"
  - "build-dmg.sh script with unsigned and --signed notarization paths"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [CommandGroup replacing/after placements for standard menus, hdiutil/create-dmg DMG creation, ad-hoc and Developer ID code signing]

key-files:
  created:
    - AirplaneTracker3D/AirplaneTracker3D.entitlements
    - ExportOptions.plist
    - Scripts/build-dmg.sh
  modified:
    - AirplaneTracker3D/AirplaneTracker3DApp.swift

key-decisions:
  - "CommandGroup placements before CommandMenu for standard menu integration without disturbing Tracker menu"
  - "View menu items have no keyboard shortcuts to avoid duplicate conflicts with Tracker menu"
  - "Window menu Reset Camera uses Cmd+0 (Tracker menu uses Cmd+R) to avoid shortcut collision"
  - "ExportOptions.plist omits teamID so it works for any developer"
  - "Build script defaults to unsigned DMG for accessibility, --signed flag for Apple Developer Program members"

patterns-established:
  - "CommandGroup(replacing:) to suppress unwanted system menu items (New Window)"
  - "CommandGroup(after:) to inject app items into standard menus (View, Window)"
  - "Scripts/ directory for build automation"

# Metrics
duration: 2min
completed: 2026-02-09
---

# Phase 10 Plan 02: Standard macOS Menus and DMG Distribution Summary

**Standard macOS menus via CommandGroup placements (File, View, Window) alongside Tracker menu, plus hardened runtime entitlements and build-dmg.sh for unsigned and signed DMG distribution**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-09T00:39:43Z
- **Completed:** 2026-02-09T00:41:25Z
- **Tasks:** 2
- **Files modified:** 4 (3 created, 1 modified)

## Accomplishments
- Standard macOS menus appear in menu bar: File (no "New Window"), Edit (system default), View (toggle items), Window (Reset Camera), Tracker (6 items), Help
- Entitlements file grants network.client for hardened runtime code signing (required for ADS-B API calls)
- DMG build script supports both unsigned (default, no Apple Developer Program) and --signed (notarization) paths with create-dmg or hdiutil fallback
- ExportOptions.plist configured for Developer ID automatic signing

## Task Commits

Each task was committed atomically:

1. **Task 1: Standard macOS menus via CommandGroup placements** - `b0c4fd0` (feat)
2. **Task 2: Entitlements, export options, and DMG build script** - `04aa2fe` (feat)

## Files Created/Modified
- `AirplaneTracker3D/AirplaneTracker3DApp.swift` - Added 3 CommandGroup placements (replacing .newItem, after .toolbar, after .windowArrangement) before existing CommandMenu("Tracker")
- `AirplaneTracker3D/AirplaneTracker3D.entitlements` - Hardened runtime entitlements with com.apple.security.network.client for outgoing API connections
- `ExportOptions.plist` - Xcode export options for Developer ID distribution with automatic signing
- `Scripts/build-dmg.sh` - Build, sign, notarize, and DMG creation script with unsigned (default) and --signed paths

## Decisions Made
- View menu toggle items have no keyboard shortcuts to avoid duplicating shortcuts already in Tracker menu (Cmd+I, Cmd+Shift+S, Cmd+F)
- Window menu "Reset Camera to Default" uses Cmd+0 (different from Tracker menu's Cmd+R) to avoid shortcut conflicts
- ExportOptions.plist intentionally omits teamID so any developer can use it (set via Xcode or xcodebuild argument)
- Build script defaults to unsigned mode for accessibility -- most users won't have Apple Developer Program membership

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required. For signed distribution, users need Apple Developer Program membership (documented in build-dmg.sh header).

## Next Phase Readiness
- All native macOS integration is complete (menu bar, dock badge, notifications, standard menus, distribution)
- Phase 10 is the final phase -- the app is ready for distribution as a macOS DMG
- Unsigned distribution: right-click to open on first launch
- Signed distribution: requires Apple Developer Program, build script documents the setup steps

## Self-Check: PASSED

- All 4 files verified on disk (1 modified, 3 created)
- Both task commits (b0c4fd0, 04aa2fe) verified in git log
- xcodebuild Debug build succeeded with zero errors

---
*Phase: 10-native-macos-integration*
*Completed: 2026-02-09*
