---
phase: 14-coverage-heatmap
plan: 01
subsystem: rendering
tags: [metal, heatmap, gpu-texture, density-grid, color-ramp, triple-buffering]

# Dependency graph
requires:
  - phase: 06-data-pipeline-aircraft-rendering
    provides: InterpolatedAircraftState with lat/lon for grid accumulation
  - phase: 13-airspace-volumes
    provides: AirspaceManager triple-buffered pattern and ShaderTypes.h BufferIndex convention
provides:
  - HeatmapManager class with 32x32 density grid, theme-aware RGBA texture generation, triple-buffered ground quad
  - HeatmapShaders.metal with vertex/fragment shaders for textured ground plane
  - BufferIndexHeatmapVertices and HeatmapVertex in ShaderTypes.h
affects: [14-02 renderer-integration]

# Tech tracking
tech-stack:
  added: []
  patterns: [CPU-side density grid with MTLTexture upload, premultiplied alpha color ramp]

key-files:
  created:
    - AirplaneTracker3D/Rendering/HeatmapManager.swift
    - AirplaneTracker3D/Rendering/HeatmapShaders.metal
  modified:
    - AirplaneTracker3D/Rendering/ShaderTypes.h
    - AirplaneTracker3D.xcodeproj/project.pbxproj

key-decisions:
  - "CPU-side 32x32 grid with texture upload (no compute shader needed for small grid)"
  - "Managed storage mode for texture to support replace() on macOS"
  - "50% bounds shift threshold for grid reset (prevents stale data without excessive resets)"

patterns-established:
  - "HeatmapManager follows AirspaceManager triple-buffered pattern with accumulate/update split"
  - "Theme detection via clearColor check (isRetro from isWireframe, isNight from clearColor)"

# Metrics
duration: 4min
completed: 2026-02-09
---

# Phase 14 Plan 01: Heatmap Data Pipeline Summary

**32x32 CPU density grid with theme-aware RGBA texture upload and Metal ground-quad shaders for coverage heatmap**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-09T11:42:56Z
- **Completed:** 2026-02-09T11:47:25Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- Extended ShaderTypes.h with BufferIndexHeatmapVertices = 9 and 32-byte HeatmapVertex struct
- Created HeatmapShaders.metal with vertex shader (view/projection transform) and fragment shader (texture sampling with discard)
- Built HeatmapManager.swift (297 lines) with grid accumulation, theme-aware color ramps (day/night/retro), premultiplied alpha, and triple-buffered ground quad geometry

## Task Commits

Each task was committed atomically:

1. **Task 1: Add HeatmapVertex and buffer index to ShaderTypes.h** - `0ab7100` (feat)
2. **Task 2: Create HeatmapShaders.metal** - `3e5ae02` (feat)
3. **Task 3: Create HeatmapManager.swift** - `845ebfb` (feat)

## Files Created/Modified
- `AirplaneTracker3D/Rendering/ShaderTypes.h` - Added BufferIndexHeatmapVertices = 9 and HeatmapVertex struct (position + texCoord, 32 bytes)
- `AirplaneTracker3D/Rendering/HeatmapShaders.metal` - Vertex/fragment shaders for textured ground quad with linear sampling and alpha discard
- `AirplaneTracker3D/Rendering/HeatmapManager.swift` - Core heatmap engine: 32x32 density grid, RGBA texture generation, ground quad geometry, bounds tracking
- `AirplaneTracker3D.xcodeproj/project.pbxproj` - Added HeatmapShaders.metal and HeatmapManager.swift to build sources

## Decisions Made
- Used managed storage mode for MTLTexture to support texture.replace() on macOS (shared mode does not support replace on discrete GPUs)
- Theme detection uses isWireframe flag for retro and clearColor comparison for night (avoids adding a theme property to ThemeConfig)
- 50% bounds shift threshold balances data freshness vs. unnecessary grid resets

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- HeatmapManager is ready for Renderer integration (14-02)
- Pipeline state creation, draw call encoding, and settings toggle needed in 14-02
- All GPU resources (texture, vertex buffers, shaders) are pre-allocated and compile without errors

## Self-Check: PASSED

- All 4 files verified on disk (ShaderTypes.h, HeatmapShaders.metal, HeatmapManager.swift, 14-01-SUMMARY.md)
- All 3 task commits verified in git log (0ab7100, 3e5ae02, 845ebfb)
- Build succeeds with all files included

---
*Phase: 14-coverage-heatmap*
*Completed: 2026-02-09*
