# Milestones

## v1.0 — Web App Foundation (Complete)

**Completed:** 2026-02-07
**Phases:** 1–4

| Phase | Description | Commit | Lines Added |
|-------|-------------|--------|-------------|
| 1 | Data Source Abstraction | 3ec43e7 | +191 |
| 2 | Airport Search & Labels | 7b23494 | +386 |
| 3 | Terrain Elevation | 2c6ed05 | +265 |
| 4 | Airspace Volumes | 5555ce6 | +162 |

**Total:** ~1,004 lines added (4,631 → 5,616 lines)

**Features delivered:**
- Data source abstraction (local dump1090 / global APIs with fallback)
- Airport search, 3D labels, fly-to animation, nearby browse
- Terrain elevation with satellite imagery
- Airspace volumes (FAA Class B/C/D)
- UI controls, mode switch, settings persistence

## v2.0 Native macOS App (Shipped: 2026-02-09)

**Phases completed:** 6 phases, 12 plans, 24 tasks
**Source:** 42 files, 7,043 LOC (Swift, Metal, C headers)
**Timeline:** 2026-02-08 to 2026-02-09 (~47 min execution time)

**Key accomplishments:**
- Metal 3 rendering engine with triple buffering, 4x MSAA, orbital camera, and async map tile ground plane
- Live aircraft visualization with 6 instanced model categories, smooth 60fps interpolation, flight trails, and billboard labels
- AWS Terrarium terrain elevation mesh with three visual themes (day, night, retro wireframe)
- Airport search by name/IATA/ICAO with smoothstep fly-to camera animation and nearby airport browsing
- SwiftUI settings, Swift Charts statistics, keyboard shortcuts with native macOS menu bar integration
- Native macOS integration: MenuBarExtra status item, dock badge, emergency squawk notifications, standard menus, DMG build script

---


## v2.1 Polish & Bug Fixes (Shipped: 2026-02-09)

**Phases completed:** 5 phases (11-15), 9 plans
**Source:** ~8,985 LOC total (~1,971 lines added)
**Timeline:** 2026-02-09 (~28 min execution time)

**Key accomplishments:**
- Fixed map tile display (removed @2x retina suffix), propeller rotation (mesh at origin + noseOffset), and reshaped 6 aircraft category silhouettes
- Restored info panel: lat/lon coordinates, external links (FlightAware, ADS-B Exchange, planespotters.net), aircraft photos with fallback
- Translucent 3D FAA airspace volumes (Class B/C/D) with ear-clip triangulation, per-class toggles, and airspace labels at volume centroids
- Coverage heatmap: 32x32 density grid with theme-aware color ramp and Metal texture overlay
- Terrain LOD: 3-ring multi-zoom tile selection (near/mid/far zoom levels)
- Spring-animated panel transitions and airspace labels with distance culling

---


## v2.2 Core Fixes & Data Sources (Shipped: 2026-02-09)

**Phases completed:** 3 phases (16-18), 3 plans, 6 tasks
**Source:** ~9,096 LOC total (~111 lines added to Swift, ~447 to airport data)
**Timeline:** 2026-02-09 (~12 min execution time)

**Key accomplishments:**
- Camera-following global API center — aircraft load for whatever area the user is viewing, not just Seattle
- Expanded airport database from 99 to 489 worldwide airports with balanced global coverage (Berlin, Frankfurt, all major hubs included)
- Configurable remote dump1090 data source — enter IP:port in Settings to poll a network ADS-B receiver
- Three-way data source switching (Local/Remote/Global) with immediate effect, no restart needed
- Label atlas scaled to 2048x1024 (512 slots) for expanded airport database

---

