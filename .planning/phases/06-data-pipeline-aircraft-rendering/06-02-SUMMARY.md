---
phase: 06-data-pipeline-aircraft-rendering
plan: 02
subsystem: rendering
tags: [metal, instanced-rendering, procedural-geometry, shaders, glow, billboard, triple-buffer]

# Dependency graph
requires:
  - phase: 06-data-pipeline-aircraft-rendering
    plan: 01
    provides: FlightDataManager with interpolatedStates(at:), AircraftCategory enum, InterpolatedAircraftState
  - phase: 05-metal-foundation-ground-plane
    provides: Renderer, MTKView, ShaderTypes.h, MapCoordinateSystem, triple-buffered uniform pipeline
provides:
  - AircraftMeshLibrary with procedural geometry for 6 aircraft categories plus rotor/propeller meshes
  - AircraftInstanceManager with triple-buffered per-instance data, category batching, altitude coloring, animation timing
  - AircraftShaders.metal with instanced vertex/fragment pair including directional lighting and position light blink
  - GlowShaders.metal with billboard vertex and radial glow fragment shaders
  - Extended ShaderTypes.h with AircraftInstanceData (96 bytes), GlowInstanceData, AircraftVertex
  - Renderer integration encoding aircraft bodies, spinning parts, and glow sprites each frame
  - ContentView wiring FlightDataManager with global polling mode
affects: [07-gpu-polyline-rendering, 08-terrain-airports, 09-settings-persistence]

# Tech tracking
tech-stack:
  added: [Metal instanced rendering, procedural mesh generation, MSL shaders, billboard sprites, additive blending]
  patterns: [instanced draw calls per category, triple-buffered instance data, category-sorted batching, radial glow texture generation]

key-files:
  created:
    - AirplaneTracker3D/Rendering/AircraftMeshLibrary.swift
    - AirplaneTracker3D/Rendering/AircraftInstanceManager.swift
    - AirplaneTracker3D/Rendering/AircraftShaders.metal
    - AirplaneTracker3D/Rendering/GlowShaders.metal
  modified:
    - AirplaneTracker3D/Rendering/ShaderTypes.h
    - AirplaneTracker3D/Rendering/Renderer.swift
    - AirplaneTracker3D/Rendering/MetalView.swift
    - AirplaneTracker3D/ContentView.swift
    - AirplaneTracker3D.xcodeproj/project.pbxproj

key-decisions:
  - "Category-sorted instanced batching: sort all aircraft by category, compute offset/count ranges, one draw call per category (max 8 total)"
  - "Persistent per-aircraft animation state via dictionaries keyed by hex identifier for smooth light phase and rotor angle continuity"
  - "Additive blending for glow sprites with depth-read/no-write stencil state to prevent glow occluding geometry"

patterns-established:
  - "Instanced rendering pattern: vertex buffer (mesh) + instance buffer (per-aircraft data) + one drawIndexedPrimitives per category"
  - "Billboard sprite pattern: 6 vertices from vertexID, camera right/up from view matrix columns, per-instance size/position"
  - "Animation state persistence: per-aircraft lightPhase/rotorAngle stored by hex across frames for continuity"

# Metrics
duration: 6min
completed: 2026-02-08
---

# Phase 6 Plan 2: Aircraft Rendering Summary

**Metal instanced rendering pipeline with 6 procedural aircraft meshes, altitude color gradient, glow billboard sprites, blinking position lights, spinning rotors/propellers, and FlightDataManager integration for live aircraft on the map**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-08T22:25:41Z
- **Completed:** 2026-02-08T22:31:17Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- Procedural 3D geometry for 6 aircraft categories (jet, widebody, helicopter, small prop, military, regional) plus separate rotor and propeller spinning meshes
- Triple-buffered per-instance GPU data with category-sorted batching, altitude-based coloring (green->yellow->orange->pink), animation timing for lights and spinning parts
- Metal shaders for aircraft bodies (instanced, directional lighting, white strobe + red beacon blink, selection highlight), glow sprites (billboard quads, radial gradient texture, additive blending), and spinning parts
- Full integration: FlightDataManager polls ADS-B API, Renderer reads interpolated states each frame, encodes instanced draw calls per category

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend ShaderTypes.h, create procedural aircraft meshes, and write aircraft + glow shaders** - `2b11cfc` (feat)
2. **Task 2: Create instance manager, integrate rendering pipeline with data manager, wire into Renderer draw loop** - `72f4a26` (feat)

## Files Created/Modified
- `AirplaneTracker3D/Rendering/ShaderTypes.h` - Extended with AircraftInstanceData (96 bytes), GlowInstanceData (48 bytes), AircraftVertex, BufferIndexInstances/GlowInstances
- `AirplaneTracker3D/Rendering/AircraftMeshLibrary.swift` - Procedural geometry for 6 categories + rotor/propeller meshes + glow texture generation
- `AirplaneTracker3D/Rendering/AircraftShaders.metal` - aircraft_vertex (instanced with modelMatrix + lighting) and aircraft_fragment (directional light + strobe + beacon + selection)
- `AirplaneTracker3D/Rendering/GlowShaders.metal` - glow_vertex (billboard quad from vertexID) and glow_fragment (radial gradient with opacity)
- `AirplaneTracker3D/Rendering/AircraftInstanceManager.swift` - Triple-buffered instance data, category batching, altitude coloring, animation state
- `AirplaneTracker3D/Rendering/Renderer.swift` - Aircraft/glow/spin pipeline states, encodeAircraft/encodeSpinningParts/encodeGlow methods, FlightDataManager integration in draw loop
- `AirplaneTracker3D/Rendering/MetalView.swift` - Accept and propagate flightDataManager to Renderer
- `AirplaneTracker3D/ContentView.swift` - Initialize FlightDataManager, start global polling on appear
- `AirplaneTracker3D.xcodeproj/project.pbxproj` - Added 4 new files to Rendering group and Sources build phase

## Decisions Made
- Category-sorted instanced batching: sort all aircraft by category to minimize pipeline state changes, compute offset/count ranges, one instanced draw call per non-empty category (max 6 body + 2 spinning = 8 draw calls)
- Persistent per-aircraft animation state stored in dictionaries keyed by hex identifier -- ensures light phase and rotor angle continuity across frames even as aircraft are added/removed
- Additive blending for glow sprites with depth-read/no-write stencil state to prevent glow from occluding underlying geometry while still respecting depth ordering
- FlightDataManager passed through MetalView as a property and set on Renderer in both makeNSView and updateNSView for reliable SwiftUI lifecycle handling

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Aircraft rendering pipeline complete: data polling -> interpolation -> instanced rendering with 6 categories, altitude coloring, glow, lights, spinning parts
- Ready for Phase 7 (GPU polyline rendering) which will add flight trails below aircraft
- Ready for Phase 8 (terrain/airports) which renders under the aircraft layer
- Phase 9 (settings) can toggle data mode, change polling center, etc.

---
*Phase: 06-data-pipeline-aircraft-rendering*
*Completed: 2026-02-08*

## Self-Check: PASSED

All 9 files verified on disk. Both task commits (2b11cfc, 72f4a26) verified in git log.
