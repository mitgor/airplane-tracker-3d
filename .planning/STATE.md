# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-09)

**Core value:** Real-time 3D flight visualization that works both as a personal ADS-B receiver dashboard and as a global flight explorer with airport discovery.
**Current focus:** v2.1 Phase 13 -- Airspace Volume Rendering

## Current Position

Phase: 13 of 15 (Airspace Volume Rendering)
Plan: 1 of 2 in current phase
Status: Plan 13-01 complete
Last activity: 2026-02-09 -- Completed 13-01-PLAN.md (airspace data pipeline and Metal rendering primitives)

Progress: v1.0 shipped (4 phases), v2.0 shipped (6 phases), v2.1 [####......] 50%

## Performance Metrics

**v2.0 Velocity:**
- Plans completed: 12
- Average duration: ~4.4min
- Total execution time: ~47min

**v2.1 Velocity:**
- Plans completed: 4
- Average duration: ~2.5min
- Total execution time: ~10min

## Accumulated Context

### Decisions

All decisions archived in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- v2.0: CPU-side terrain vertex displacement (simpler than GPU, adequate for current tile count)
- v2.0: Zero external Swift dependencies (URLSession, simd, UserDefaults only)
- v2.1: Pure Swift ear-clipping for polygon triangulation (no LibTessSwift dependency)
- v2.1: CPU-side heatmap grid with texture upload (no compute shader needed for 32x32 grid)
- v2.1: Single aft-offset wing box for jet sweep (simpler than per-side segments, still visually distinct)
- v2.1: T-tail + wing-mounted engines for regional jet distinction (not just scaled-down jet)
- v2.1: Removed @2x retina suffix from CartoDB day theme URL for reliable tile loading
- v2.1: Propeller mesh at origin with noseOffset translation (clean matrix composition pattern)
- v2.1: planespotters.net as primary photo source with hexdb.io fallback (no API key, AsyncImage handles 404)
- v2.1: Flat alpha for airspace fill (skip Fresnel), Uniforms.cameraPosition for future polish
- v2.1: Edge mesh with .line primitive type for clean airspace wireframe outlines

### Known Issues (v2.1 scope)

- ~~Map tile ground plane not displaying~~ FIXED: @2x URL removed, diagnostic logging added (11-01)
- ~~Propeller rotation matrix incorrectly composed~~ FIXED: mesh at origin + noseOffset translation (11-01)
- ~~Native detail panel missing: lat/lon, aircraft photo, external links~~ FIXED: links, photo, lat/lon verified (12-01)
- Airspace volumes data pipeline built, pending Renderer integration (13-02)
- Coverage heatmaps not yet ported from web

### Pending Todos

None.

### Blockers/Concerns

- FAA ArcGIS URL integrated (services6.arcgis.com) -- verify at runtime in Plan 13-02

## Session Continuity

Last session: 2026-02-09
Stopped at: Completed 13-01-PLAN.md (airspace data pipeline: ShaderTypes, EarClipTriangulator, AirspaceShaders, AirspaceManager). Plan 02 next.
Resume file: None
