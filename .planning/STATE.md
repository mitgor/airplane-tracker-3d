# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-08)

**Core value:** Real-time 3D flight visualization that works both as a personal ADS-B receiver dashboard and as a global flight explorer with airport discovery.
**Current focus:** Phase 6 -- Data Pipeline + Aircraft Rendering

## Current Position

Phase: 6 of 10 (Data Pipeline + Aircraft Rendering) -- COMPLETE
Plan: 2 of 2 in current phase
Status: Phase Complete
Last activity: 2026-02-08 -- Completed 06-02 (aircraft rendering)

Progress: [===========---] 85% (11/13 plans across all milestones)

## Performance Metrics

**Velocity:**
- Total plans completed: 10 (7 v1.0 + 3 v2.0)
- Average duration: ~4.3min (v2.0)
- Total execution time: ~13min (v2.0)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 (v1.0) | 2 | -- | -- |
| 2 (v1.0) | 2 | -- | -- |
| 3 (v1.0) | 2 | -- | -- |
| 4 (v1.0) | 1 | -- | -- |
| 5 (v2.0) | 2 | 9min | 4.5min |
| 6 (v2.0) | 2/2 | 10min | 5min |

**Recent Trend:**
- v1.0 completed all 7 plans
- v2.0 plan 05-01 completed in 5 min
- v2.0 plan 05-02 completed in 4 min
- Phase 5 verified: 5/5 automated checks pass
- v2.0 plan 06-01 completed in 4 min (2 tasks, 5 files)
- v2.0 plan 06-02 completed in 6 min (2 tasks, 9 files)

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v2.0]: Metal 3 over Metal 4 -- mature, stable, well-documented; Metal 4 is bleeding-edge
- [v2.0]: macOS 14 Sonoma minimum -- enables @Observable macro, drops Ventura (EOL)
- [v2.0]: Core features first, terrain/airports/airspace later in phased delivery
- [v2.0]: Zero external dependencies -- URLSession, simd, UserDefaults cover all needs
- [v2.0]: Triple buffering from day 1 -- non-negotiable for CPU/GPU sync
- [05-01]: Manual Xcode project creation for precise build setting control
- [05-01]: Custom MTKView subclass for input handling (scroll wheel, key events)
- [05-01]: Bridging header for shared CPU/GPU types (ShaderTypes.h)
- [05-01]: Metal NDC depth [0,1] projection matrix built from scratch
- [05-02]: Mercator projection with worldScale=500 for tile alignment
- [05-02]: Serial DispatchQueue for thread-safe tile cache (not actor)
- [05-02]: Reusable unit quad with per-tile model matrix for efficiency
- [05-02]: URLSession with 200MB disk + 50MB memory cache for tile data
- [06-01]: FlightDataManager @MainActor pattern for synchronous render-loop access
- [06-01]: Buffer snapshot approach: actor stores raw data, manager copies for render-thread interpolation
- [06-01]: Altitude scale 0.001 (35000ft = 35 world units) with worldScale=500
- [06-02]: Category-sorted instanced batching: one draw call per non-empty category (max 8 total)
- [06-02]: Persistent per-aircraft animation state (lightPhase, rotorAngle) keyed by hex for continuity
- [06-02]: Additive glow blending with depth-read/no-write stencil state

### Pending Todos

None yet.

### Blockers/Concerns

- Research flags Phase 7 (GPU polyline rendering) and Phase 8 (terrain LOD) as needing deeper research during planning
- Research flags Phase 10 (notarization workflow) as needing research for DMG signing

## Session Continuity

Last session: 2026-02-08
Stopped at: Completed 06-02-PLAN.md, Phase 6 complete, ready for Phase 7
Resume file: None
