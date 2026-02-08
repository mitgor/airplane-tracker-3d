# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-08)

**Core value:** Real-time 3D flight visualization that works both as a personal ADS-B receiver dashboard and as a global flight explorer with airport discovery.
**Current focus:** Phase 7 -- Trails + Labels + Selection

## Current Position

Phase: 7 of 10 (Trails + Labels + Selection) -- COMPLETE
Plan: 2 of 2 in current phase
Status: Phase Complete
Last activity: 2026-02-08 -- Completed 07-02 (labels + selection + enrichment)

Progress: [==============-] 93% (13/14 plans across all milestones)

## Performance Metrics

**Velocity:**
- Total plans completed: 13 (7 v1.0 + 6 v2.0)
- Average duration: ~5.0min (v2.0)
- Total execution time: ~30min (v2.0)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 (v1.0) | 2 | -- | -- |
| 2 (v1.0) | 2 | -- | -- |
| 3 (v1.0) | 2 | -- | -- |
| 4 (v1.0) | 1 | -- | -- |
| 5 (v2.0) | 2 | 9min | 4.5min |
| 6 (v2.0) | 2 | 10min | 5min |
| 7 (v2.0) | 2/2 | 11min | 5.5min |

**Recent Trend:**
- Phase 5 verified: 5/5 automated checks pass
- Phase 6 verified: 8/8 automated checks pass
- v2.0 plan 06-01 completed in 4 min
- v2.0 plan 06-02 completed in 6 min
- v2.0 plan 07-01 completed in 4 min
- v2.0 plan 07-02 completed in 7 min

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v2.0]: Metal 3 over Metal 4 -- mature, stable, well-documented; Metal 4 is bleeding-edge
- [v2.0]: macOS 14 Sonoma minimum -- enables @Observable macro, drops Ventura (EOL)
- [v2.0]: Zero external dependencies -- URLSession, simd, UserDefaults cover all needs
- [v2.0]: Triple buffering from day 1 -- non-negotiable for CPU/GPU sync
- [05-02]: Mercator projection with worldScale=500 for tile alignment
- [06-01]: FlightDataManager @MainActor pattern for synchronous render-loop access
- [06-01]: Buffer snapshot approach: actor stores raw data, manager copies for render-thread interpolation
- [06-01]: Altitude scale 0.001 (35000ft = 35 world units) with worldScale=500
- [06-02]: Category-sorted instanced batching: one draw call per non-empty category (max 8 total)
- [06-02]: Persistent per-aircraft animation state (lightPhase, rotorAngle) keyed by hex for continuity
- [06-02]: Additive glow blending with depth-read/no-write stencil state
- [07-01]: TrailVertex 112 bytes (not 64) due to simd_float3 16-byte alignment -- consistent CPU/GPU via shared header
- [07-01]: Screen-space polyline extrusion with triangle strip topology for configurable-width trails
- [07-01]: Trail render order: after aircraft bodies + spinning parts, before glow sprites
- [07-02]: CoreText rasterization to 2048x2048 RGBA8 texture atlas with 256x64 slots for label billboards
- [07-02]: LOD distance fade: labels fully visible under 150 units, fading to hidden at 300 units
- [07-02]: Ray-sphere picking with radius 3.0 world units for click selection
- [07-02]: NotificationCenter-based communication between SwiftUI ContentView and Metal Coordinator
- [07-02]: EnrichmentService actor with dictionary caching (including negative lookups)

### Pending Todos

None yet.

### Blockers/Concerns

- Research flags Phase 7 (GPU polyline rendering) as needing deeper research during planning
- Research flags Phase 8 (terrain LOD) as needing deeper research during planning
- Research flags Phase 10 (notarization workflow) as needing research for DMG signing

## Session Continuity

Last session: 2026-02-08
Stopped at: Completed 07-02-PLAN.md (labels + selection + enrichment) -- Phase 7 complete
Resume file: None
