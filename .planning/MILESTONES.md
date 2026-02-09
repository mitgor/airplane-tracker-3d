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

