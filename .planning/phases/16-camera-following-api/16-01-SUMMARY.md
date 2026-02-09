---
phase: 16-camera-following-api
plan: 01
subsystem: data-pipeline
tags: [adsb, polling, camera, geolocation, async-actor]

# Dependency graph
requires: []
provides:
  - "Dynamic API query center that follows camera position"
  - "Camera-to-actor pipeline: Renderer -> ContentView -> FlightDataManager -> FlightDataActor"
affects: [18-remote-data-sources]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Actor-isolated mutable state for polling center (currentCenter on FlightDataActor)"
    - "Camera position pipeline via NotificationCenter -> @MainActor manager -> actor"

key-files:
  created: []
  modified:
    - "AirplaneTracker3D/DataLayer/FlightDataActor.swift"
    - "AirplaneTracker3D/ContentView.swift"

key-decisions:
  - "Polling loop reads currentCenter each cycle via await self.currentCenter rather than capturing center in closure"
  - "switchDataSource uses current camera lat/lon instead of hardcoded Seattle so source changes respect camera position"

patterns-established:
  - "Camera-driven data pipeline: Renderer posts notification -> ContentView converts world-to-geo -> manager forwards to actor"

# Metrics
duration: 1min
completed: 2026-02-09
---

# Phase 16 Plan 01: Dynamic Polling Center + Camera-to-Actor Wiring Summary

**Dynamic API query center on FlightDataActor that reads camera-derived lat/lon each polling cycle, wired via ContentView's cameraTargetUpdated handler**

## Performance

- **Duration:** 1 min 29s
- **Started:** 2026-02-09T20:58:23Z
- **Completed:** 2026-02-09T20:59:52Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- FlightDataActor has a mutable `currentCenter` property read each polling cycle instead of a closure-captured fixed center
- ContentView's cameraTargetUpdated handler feeds camera lat/lon to FlightDataManager.updateCenter, completing the pipeline
- Data source switching uses current camera position instead of hardcoded Seattle coordinates
- MapCoordinateSystem.swift left untouched (Mercator projection center stays fixed)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add dynamic center to FlightDataActor and FlightDataManager** - `f260142` (feat)
2. **Task 2: Wire camera position updates to polling center in ContentView** - `380482e` (feat)

## Files Created/Modified
- `AirplaneTracker3D/DataLayer/FlightDataActor.swift` - Added currentCenter property, updateCenter method on actor and manager, polling loop reads dynamic center
- `AirplaneTracker3D/ContentView.swift` - Added updateCenter call in cameraTargetUpdated handler, switched switchDataSource to use camera position

## Decisions Made
- Polling loop reads `currentCenter` via `await self.currentCenter` each cycle. This is actor-isolated access, safe without additional synchronization.
- `switchDataSource` handler now uses the `centerLat`/`centerLon` @State properties (already updated by camera pipeline) instead of `MapCoordinateSystem.shared` values, ensuring source switches respect current camera position.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Camera-following API pipeline is complete; aircraft will load for whatever area the user views
- Phase 17 (Expanded Airport Database) is independent and ready
- Phase 18 (Remote Data Sources) can build on the dynamic center pipeline established here

---
*Phase: 16-camera-following-api*
*Completed: 2026-02-09*
