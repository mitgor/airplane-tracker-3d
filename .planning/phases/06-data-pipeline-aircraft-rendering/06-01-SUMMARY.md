---
phase: 06-data-pipeline-aircraft-rendering
plan: 01
subsystem: data-pipeline
tags: [adsb, urlsession, async-await, actor, interpolation, codable, swift-concurrency]

# Dependency graph
requires:
  - phase: 05-metal-renderer-map-tiles
    provides: MapCoordinateSystem for world-space coordinate conversion, Renderer/MTKViewDelegate for draw loop
provides:
  - AircraftModel normalized data format with Codable API types for V2 and dump1090
  - AircraftCategory 6-case enum with 4-priority classification chain
  - DataNormalizer for V2 and dump1090 response normalization
  - FlightDataActor with async polling, provider fallback, interpolation buffer
  - FlightDataManager providing synchronous interpolatedStates(at:) for render loop
  - InterpolatedAircraftState with world-space position ready for instanced rendering
affects: [06-02-aircraft-rendering, 07-gpu-polyline-rendering, 09-settings-persistence]

# Tech tracking
tech-stack:
  added: [URLSession async/await, Swift actor, AsyncStream, CACurrentMediaTime, JSONDecoder/Codable]
  patterns: [actor-based data pipeline, provider fallback chain, time-windowed interpolation buffer, @MainActor render manager]

key-files:
  created:
    - AirplaneTracker3D/Models/AircraftModel.swift
    - AirplaneTracker3D/Models/AircraftCategory.swift
    - AirplaneTracker3D/DataLayer/DataNormalizer.swift
    - AirplaneTracker3D/DataLayer/FlightDataActor.swift
  modified:
    - AirplaneTracker3D.xcodeproj/project.pbxproj

key-decisions:
  - "FlightDataManager @MainActor pattern for synchronous render-loop access to interpolated states"
  - "Buffer snapshot approach: actor stores raw data, manager copies snapshot each poll for render-thread interpolation"
  - "Altitude scale 0.001 (35000ft = 35 world units) with worldScale=500"

patterns-established:
  - "Actor + AsyncStream polling: fetch -> normalize -> buffer -> yield pattern for all network data"
  - "Time-windowed interpolation: 2s delay, per-aircraft ring buffer, lerp/lerpAngle at render frequency"
  - "Provider fallback: try providers in order, track failCount, continue on error, return empty on total failure"

# Metrics
duration: 4min
completed: 2026-02-08
---

# Phase 6 Plan 1: Data Pipeline Summary

**Actor-based ADS-B polling with provider fallback (airplanes.live/adsb.lol/dump1090), Codable data models, 6-category aircraft classification, and time-windowed interpolation buffer for 60fps render-ready states**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-08T22:18:37Z
- **Completed:** 2026-02-08T22:22:37Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Complete Codable type system for both V2 API (airplanes.live/adsb.lol) and dump1090 formats, including AltitudeValue enum that handles Int/"ground" variance
- 6-category aircraft classification (jet, widebody, helicopter, small, military, regional) with 4-priority chain: dbFlags, ADS-B category, ICAO type code, callsign heuristics
- FlightDataActor with async polling loop, provider fallback chain, per-aircraft interpolation buffer, and stale aircraft removal
- FlightDataManager providing synchronous interpolatedStates(at:) with lerp/lerpAngle for the render loop

## Task Commits

Each task was committed atomically:

1. **Task 1: Create data models, Codable API types, and aircraft category classification** - `b9259ca` (feat)
2. **Task 2: Create FlightDataActor with polling, fallback, interpolation buffer, and stale removal** - `8717497` (feat)

## Files Created/Modified
- `AirplaneTracker3D/Models/AircraftModel.swift` - AltitudeValue enum, ADSBV2Response/Aircraft, Dump1090Response/Aircraft Codable types, AircraftModel struct, InterpolatedAircraftState struct
- `AirplaneTracker3D/Models/AircraftCategory.swift` - 6-case CaseIterable enum with classify() 4-priority chain
- `AirplaneTracker3D/DataLayer/DataNormalizer.swift` - Static normalizeV2() and normalizeDump1090() methods
- `AirplaneTracker3D/DataLayer/FlightDataActor.swift` - FlightDataActor (polling/buffer/stale removal) + FlightDataManager (@MainActor interpolation for render loop)
- `AirplaneTracker3D.xcodeproj/project.pbxproj` - Added Models/ and DataLayer/ groups with 4 new Swift files

## Decisions Made
- Used @MainActor FlightDataManager pattern rather than nonisolated actor access, since MTKViewDelegate draw(in:) runs on main thread -- allows synchronous interpolatedStates(at:) calls without async overhead
- Buffer snapshot approach: actor stores authoritative raw data, manager copies snapshot each poll cycle, interpolation happens on render thread using snapshot + current frame time
- Altitude scale factor 0.001 (35000ft = 35 world units) chosen to match worldScale=500 visual proportions

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Data pipeline complete: poll -> normalize -> buffer -> interpolate -> InterpolatedAircraftState
- FlightDataManager.interpolatedStates(at:) ready for plan 06-02 to consume in Renderer.draw(in:)
- AircraftCategory enum ready for mesh selection in instanced rendering
- All Sendable/actor isolation correct with zero concurrency warnings

---
*Phase: 06-data-pipeline-aircraft-rendering*
*Completed: 2026-02-08*

## Self-Check: PASSED

All 5 files verified on disk. Both task commits (b9259ca, 8717497) verified in git log.
