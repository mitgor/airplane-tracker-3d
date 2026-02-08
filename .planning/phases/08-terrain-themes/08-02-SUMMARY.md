---
phase: 08-terrain-themes
plan: 02
subsystem: rendering
tags: [metal, themes, day-night-retro, wireframe, airport-labels, cartodb-tiles, coretext-atlas]

# Dependency graph
requires:
  - phase: 08-terrain-themes/01
    provides: "TerrainTileManager, terrain vertex/fragment shaders, terrain pipeline states"
  - phase: 07-interaction
    provides: "LabelManager atlas pattern, NotificationCenter SwiftUI-Metal communication"
  - phase: 05-map-camera
    provides: "MapTileManager tile URL fetching, MapCoordinateSystem Mercator projection"
provides:
  - "ThemeManager with day/night/retro configs, UserDefaults persistence, cycle notification"
  - "Theme-aware rendering for all passes: clear color, terrain, aircraft, trails, labels, glow, altitude lines"
  - "Retro wireframe mode via setTriangleFillMode(.lines) for terrain and aircraft"
  - "AirportLabelManager with 99-airport JSON database, distance-culled ground labels"
  - "Theme-aware CartoDB tile URLs (Positron for day, Dark Matter for night, OSM for retro)"
  - "Retro green-tint fragment shaders for terrain and flat tiles"
affects: [09-export-settings, 10-packaging]

# Tech tracking
tech-stack:
  added: [cartodb-positron-tiles, cartodb-dark-matter-tiles, retro-wireframe-rendering]
  patterns: [theme-system-with-config-structs, notification-driven-theme-switching, atlas-re-rasterization-on-theme-change]

key-files:
  created:
    - AirplaneTracker3D/Rendering/ThemeManager.swift
    - AirplaneTracker3D/Rendering/AirportLabelManager.swift
    - AirplaneTracker3D/Data/airports.json
  modified:
    - AirplaneTracker3D/Rendering/Renderer.swift
    - AirplaneTracker3D/Rendering/Shaders.metal
    - AirplaneTracker3D/Rendering/TerrainShaders.metal
    - AirplaneTracker3D/Rendering/AltitudeLineShaders.metal
    - AirplaneTracker3D/Rendering/ShaderTypes.h
    - AirplaneTracker3D/Map/MapTileManager.swift
    - AirplaneTracker3D/ContentView.swift
    - AirplaneTracker3D/Rendering/MetalView.swift
    - AirplaneTracker3D/Rendering/LabelManager.swift
    - AirplaneTracker3D/Rendering/AircraftInstanceManager.swift
    - AirplaneTracker3D/Rendering/TrailManager.swift
    - AirplaneTracker3D.xcodeproj/project.pbxproj

key-decisions:
  - "CartoDB Positron for day, Dark Matter for night -- free public tile servers, no API key needed"
  - "Retro uses OSM tiles + green-tint shader (avoids Stadia Maps API key)"
  - "ThemeConfig as pure-data struct (no Metal references) -- safe for multi-threaded access"
  - "AltLineVertex extended from 16 to 32 bytes with color field for theme-aware altitude lines"
  - "Airport labels in separate atlas (1024x512) from aircraft labels (2048x2048) for isolation"
  - "Retro wireframe via setTriangleFillMode(.lines) -- restored to .fill before trails/labels/glow"

patterns-established:
  - "Theme cycling: ThemeManager.cycleTheme() posts .themeChanged notification, callback chain updates all subsystems"
  - "Cache invalidation on theme change: LabelManager.invalidateCache() forces re-rasterization next frame"
  - "Tint color parameter pattern: optional SIMD4<Float>? tintColor passed to update() methods for retro override"
  - "Retro fragment shader pattern: grayscale-invert-then-green-tint for CRT look"

# Metrics
duration: 7min
completed: 2026-02-09
---

# Phase 8 Plan 2: Theme System and Airport Labels Summary

**Three-theme visual system (day/night/retro wireframe) affecting all render passes, with CartoDB tile switching and 99-airport ground label database**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-08T23:39:25Z
- **Completed:** 2026-02-08T23:46:25Z
- **Tasks:** 3
- **Files modified:** 15

## Accomplishments
- ThemeManager provides day (sky blue, CartoDB Positron), night (dark blue, CartoDB Dark Matter), and retro (dark green, wireframe + green tint) themes with UserDefaults persistence
- Every render pass is theme-aware: clear color, terrain, flat tiles, aircraft, trails, labels, altitude lines, glow, and airport labels all update when theme changes
- Retro mode uses setTriangleFillMode(.lines) for wireframe terrain and aircraft, with green-tint fragment shaders for inverted CRT aesthetic
- AirportLabelManager renders IATA codes for 99 major world airports at ground level, distance-culled to max 40 visible with opacity fade
- Theme toggle via "DAY"/"NIGHT"/"RETRO" button in top-left corner and 't' keyboard shortcut

## Task Commits

Each task was committed atomically:

1. **Task 1: ThemeManager, theme-aware tile URLs, and retro shaders** - `cf07912` (feat)
2. **Task 2: Airport ground labels with embedded database** - `d03e17f` (feat)
3. **Task 3: Renderer theme integration and ContentView theme toggle** - `1aadfe4` (feat)

## Files Created/Modified
- `AirplaneTracker3D/Rendering/ThemeManager.swift` - Theme enum, ThemeConfig struct, three theme palettes, tileURL(), UserDefaults persistence, cycle support
- `AirplaneTracker3D/Rendering/AirportLabelManager.swift` - Airport JSON loading, 1024x512 atlas, distance-culled ground labels with theme-aware rasterization
- `AirplaneTracker3D/Data/airports.json` - 99 major airports (ATL, LAX, LHR, NRT, DXB, SYD, GRU, etc.) with IATA/ICAO/lat/lon
- `AirplaneTracker3D/Rendering/Renderer.swift` - Full theme integration: retro pipelines, wireframe mode, tint colors, airport label rendering, theme change handler
- `AirplaneTracker3D/Rendering/Shaders.metal` - Added fragment_retro_textured (green-tint CRT for flat tiles)
- `AirplaneTracker3D/Rendering/TerrainShaders.metal` - Added fragment_retro_terrain and fragment_retro_terrain_placeholder
- `AirplaneTracker3D/Rendering/AltitudeLineShaders.metal` - Updated to read color from vertex data instead of hardcoded gray
- `AirplaneTracker3D/Rendering/ShaderTypes.h` - AltLineVertex expanded with simd_float4 color field (16->32 bytes)
- `AirplaneTracker3D/Map/MapTileManager.swift` - Theme-aware tile URLs (CartoDB Positron/Dark Matter/OSM), switchTheme() with cache clear
- `AirplaneTracker3D/ContentView.swift` - Theme toggle button, .themeChanged notification listener
- `AirplaneTracker3D/Rendering/MetalView.swift` - .cycleTheme observer, 't' keyboard shortcut
- `AirplaneTracker3D/Rendering/LabelManager.swift` - Theme-aware text/bg colors, altLineColor, invalidateCache()
- `AirplaneTracker3D/Rendering/AircraftInstanceManager.swift` - Optional tintColor parameter for retro green override
- `AirplaneTracker3D/Rendering/TrailManager.swift` - Optional tintColor parameter for retro green trails
- `AirplaneTracker3D.xcodeproj/project.pbxproj` - Added ThemeManager.swift, AirportLabelManager.swift, airports.json, Data group, Resources build phase

## Decisions Made
- **CartoDB tiles (no API key):** CartoDB Positron (day) and Dark Matter (night) are free public tile servers matching the research spec, avoiding Stadia Maps API key requirement.
- **Retro keeps OSM tiles:** Instead of a separate retro tile provider, OSM tiles are used with a green-tint fragment shader that inverts and shifts to green channel.
- **AltLineVertex color field:** Extended the vertex struct from 16 to 32 bytes to pass theme-aware color per-vertex, avoiding a separate color buffer.
- **Separate atlas for airports:** 1024x512 atlas (128 slots) for airport labels vs 2048x2048 for aircraft labels -- keeps concerns isolated and airports never conflict with aircraft label slots.
- **Fill mode management:** setTriangleFillMode(.lines) set once at frame start for retro, restored to .fill before trails/labels/glow to avoid visual artifacts on triangle strips and billboard quads.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - CartoDB and OSM tile servers are public and require no API keys.

## Next Phase Readiness
- Phase 8 (Terrain + Themes) fully complete with both plans executed
- Three visual themes working across all render passes with persistent toggle
- Airport ground labels provide geographic context for flight tracking
- Ready for Phase 9 (Export + Settings) or Phase 10 (Packaging)

## Self-Check: PASSED

All 3 created files exist, all 12 modified files exist, all 3 task commits (cf07912, d03e17f, 1aadfe4) verified in git log. All must-have artifact patterns confirmed: `enum Theme`, `class AirportLabelManager`, `icao` in airports.json, `themeManager` in Renderer, `theme` in MapTileManager, `Theme` in ContentView.

---
*Phase: 08-terrain-themes*
*Completed: 2026-02-09*
