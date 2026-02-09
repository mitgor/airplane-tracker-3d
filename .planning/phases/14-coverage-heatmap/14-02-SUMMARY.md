---
phase: 14-coverage-heatmap
plan: 02
subsystem: rendering
tags: [metal, heatmap, renderer-integration, pipeline-state, settings-toggle, alpha-blending]

# Dependency graph
requires:
  - phase: 14-coverage-heatmap
    plan: 01
    provides: HeatmapManager, HeatmapShaders.metal, HeatmapVertex/BufferIndex in ShaderTypes.h
  - phase: 13-airspace-volumes
    provides: AirspaceManager integration pattern (pipeline state + encodeX method + draw loop wiring)
provides:
  - Complete coverage heatmap feature: visible density overlay on ground plane, togglable from Settings
  - heatmapColorRamp property on ThemeConfig for theme-aware gradient colors
  - Renderer.encodeHeatmap method for ground overlay rendering with alpha blending
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [ground overlay rendering with fill-mode toggle for retro wireframe compatibility]

key-files:
  created: []
  modified:
    - AirplaneTracker3D/Rendering/Renderer.swift
    - AirplaneTracker3D/Rendering/ThemeManager.swift
    - AirplaneTracker3D/Views/SettingsView.swift
    - AirplaneTracker3D/AirplaneTracker3DApp.swift

key-decisions:
  - "Heatmap renders once after tiles, before both branches (persists without aircraft)"
  - "Temporary fill-mode restore in retro theme for heatmap (wireframe quad would be invisible)"
  - "ThemeConfig heatmapColorRamp provides explicit low/high gradient values per theme"

patterns-established:
  - "Ground overlay fill-mode toggle: restore fill before semi-transparent overlay, re-enable wireframe after"
  - "Single-section Settings toggle for simple features (no sub-options like airspace per-class)"

# Metrics
duration: 3min
completed: 2026-02-09
---

# Phase 14 Plan 02: Renderer Integration & Settings Toggle Summary

**Coverage heatmap wired into Metal render loop with theme-aware color ramp, alpha-blended ground overlay, and Settings toggle**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-09T11:49:50Z
- **Completed:** 2026-02-09T11:52:26Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Added heatmapColorRamp tuple to ThemeConfig with per-theme gradient values (day: blue-cyan, night: dark-blue-cyan, retro: green)
- Created heatmap pipeline state with alpha blending and encodeHeatmap method in Renderer
- Wired HeatmapManager into draw loop: accumulate aircraft positions, update buffers, render ground overlay
- Heatmap renders after map tiles but before aircraft for correct z-ordering
- Added "Coverage Heatmap" section with toggle in Settings Rendering tab

## Task Commits

Each task was committed atomically:

1. **Task 1: Add heatmap color ramp to ThemeConfig and register UserDefaults default** - `6751c3c` (feat)
2. **Task 2: Integrate HeatmapManager into Renderer and add Settings toggle** - `503c00f` (feat)

## Files Created/Modified
- `AirplaneTracker3D/Rendering/ThemeManager.swift` - Added heatmapColorRamp (low/high SIMD4 tuple) to ThemeConfig struct for all 3 themes
- `AirplaneTracker3D/AirplaneTracker3DApp.swift` - Registered showHeatmap=true in UserDefaults defaults
- `AirplaneTracker3D/Rendering/Renderer.swift` - Added heatmapPipeline + heatmapManager properties, pipeline creation, encodeHeatmap method, draw loop integration (accumulate + update + render)
- `AirplaneTracker3D/Views/SettingsView.swift` - Added showHeatmap @AppStorage and Coverage Heatmap toggle section

## Decisions Made
- Heatmap renders once after all tiles and before the aircraft/no-aircraft branch split, so it persists when no aircraft are visible
- Temporary fill-mode restore in retro theme before heatmap rendering (wireframe mode would make the quad invisible)
- ThemeConfig carries explicit heatmapColorRamp values rather than relying on clearColor detection in HeatmapManager

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 14 (Coverage Heatmap) is fully complete
- All GPU resources, shaders, manager, renderer integration, and user controls are in place
- Ready to proceed to Phase 15

## Self-Check: PASSED

- All 4 modified files verified on disk (ThemeManager.swift, AirplaneTracker3DApp.swift, Renderer.swift, SettingsView.swift)
- Both task commits verified in git log (6751c3c, 503c00f)
- Build succeeds with all changes included
