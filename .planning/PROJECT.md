# Airplane Tracker 3D

## What This Is

A real-time 3D flight tracker available as both a browser-based web app (THREE.js/WebGL) and a fully native macOS application (Swift/Metal 3/SwiftUI). The native macOS app features a Metal 3 rendering engine with terrain elevation, three visual themes, instanced aircraft rendering, flight trails, airport search with fly-to, SwiftUI settings, and native macOS integration (menu bar status, dock badge, notifications). Optimized for Apple Silicon at 60fps+.

## Core Value

Real-time 3D flight visualization that works both as a personal ADS-B receiver dashboard and as a global flight explorer with airport discovery.

## Requirements

### Validated

- ✓ 3D aircraft rendering with smooth interpolation between data updates — v1.0 web
- ✓ Real-time data polling from dump1090 (aircraft.json, stats.json) — v1.0 web
- ✓ Three visual themes: day, night, retro 80s — v1.0 web
- ✓ Flight trails with altitude/speed color coding — v1.0 web
- ✓ Aircraft enrichment via hexdb.io, adsbdb.com, adsb.lol APIs — v1.0 web
- ✓ Map tile rendering with zoom/pan (OSM, CartoDB, Stamen) — v1.0 web
- ✓ Aircraft selection with detail panel and external links — v1.0 web
- ✓ Statistics graphs (message rate, aircraft count, signal level) — v1.0 web
- ✓ Settings persistence via cookies — v1.0 web
- ✓ Keyboard shortcuts and touch controls — v1.0 web
- ✓ Performance optimization (object pooling, LOD, shared geometries) — v1.0 web
- ✓ IndexedDB persistence for stats history and trail data — v1.0 web
- ✓ Aircraft category detection (helicopter, military, small, regional, widebody, jet) — v1.0 web
- ✓ Follow aircraft mode with smooth camera tracking — v1.0 web
- ✓ Coverage heatmap visualization — v1.0 web
- ✓ Data source abstraction with local/global mode switch — v1.0 web
- ✓ Global data sourcing with API fallback (airplanes.live, adsb.lol) — v1.0 web
- ✓ Airport search, labels, fly-to, nearby browse — v1.0 web
- ✓ 3D terrain elevation with satellite imagery — v1.0 web
- ✓ Airspace volume rendering (Class B/C/D) — v1.0 web
- ✓ Metal 3 rendering with triple buffering and 4x MSAA — v2.0 native
- ✓ Orbital camera with trackpad orbit/zoom/pan and auto-rotate — v2.0 native
- ✓ Async map tile ground plane with coordinate system — v2.0 native
- ✓ 6 instanced aircraft model categories at 60fps — v2.0 native
- ✓ Local dump1090 and global API polling with automatic failover — v2.0 native
- ✓ Smooth 60fps interpolated aircraft movement — v2.0 native
- ✓ GPU polyline flight trails with altitude color gradient — v2.0 native
- ✓ Billboard text labels with distance-based LOD — v2.0 native
- ✓ Aircraft selection with enrichment detail panel — v2.0 native
- ✓ Follow camera mode with smooth tracking — v2.0 native
- ✓ Terrain elevation mesh from AWS Terrarium tiles — v2.0 native
- ✓ Three themes (day/night/retro wireframe) affecting all passes — v2.0 native
- ✓ 3D airport ground labels for 99 major airports — v2.0 native
- ✓ Airport search by name/IATA/ICAO with fly-to animation — v2.0 native
- ✓ SwiftUI Settings with persistent preferences — v2.0 native
- ✓ Swift Charts statistics visualization — v2.0 native
- ✓ Keyboard shortcuts with macOS menu bar — v2.0 native
- ✓ Imperial/metric unit switching — v2.0 native
- ✓ MenuBarExtra status item with live aircraft count — v2.0 native
- ✓ Dock icon badge with aircraft count — v2.0 native
- ✓ Configurable aircraft alert notifications — v2.0 native
- ✓ Standard macOS menus (File/Edit/View/Window) — v2.0 native
- ✓ DMG build/distribution script with entitlements — v2.0 native

### Active

#### v2.1 — Polish & Bug Fixes

**Bug Fixes:**
- [ ] Fix aircraft model rendering (propeller rotation, model quality)
- [ ] Fix map tiles not displaying on ground plane surface
- [ ] Restore missing info panel features from web version (position, photo, external links)

**Missing Features (port from web):**
- [ ] Airspace volume rendering (Class B/C/D translucent 3D volumes)
- [ ] Coverage heatmap visualization

**Visual Polish:**
- [ ] Improved 3D aircraft model silhouettes (more recognizable shapes)
- [ ] Higher-quality terrain rendering (LOD, detail)
- [ ] UI refinement (panel layouts, transitions, label quality)

### Out of Scope

- Recording/playback functionality — adds significant complexity, not core to the vision
- Fly mode (WASD navigation) — orbit camera is sufficient
- Mobile native app — macOS-first
- User accounts or authentication — client-side only
- Real-time chat or social features — this is a visualization tool
- Mac App Store distribution — direct download distribution

## Context

**v2.0 shipped.** The native macOS app is a complete rewrite of the web version using Swift, Metal 3, and SwiftUI. 42 source files, 7,043 LOC. The web version (~5,600 lines, single HTML file) remains available as the cross-platform option.

The native app includes all core visualization features from v1.0 web plus native macOS integration (menu bar, dock badge, notifications, standard menus). The only v1.0 web features not ported to native are: airspace volumes and coverage heatmaps.

**Tech stack:** Swift, Metal 3, SwiftUI, macOS 14 Sonoma minimum, zero external dependencies.

Inspiration: [Air Loom](http://objectiveunclear.com/airloom.html)

Airport data: embedded 99-airport JSON dataset (OurAirports-derived).

## Constraints

- **Tech stack**: Swift, Metal, SwiftUI — no WebView, no Electron, no Catalyst
- **Architecture**: Apple Silicon ARM-optimized, universal binary acceptable but ARM primary
- **Performance**: Must target 60fps+ with 200+ aircraft on Apple Silicon
- **Data sources**: Global APIs must be free/public (no paid API keys required)
- **Offline tolerance**: App should degrade gracefully when APIs are unavailable
- **Distribution**: Direct download (DMG), no App Store sandboxing constraints
- **macOS version**: macOS 14 Sonoma+ (Metal 3 support)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Shared core with mode switch (not separate files) | Avoids code duplication, both modes benefit from new features | ✓ Good — v1.0 |
| Multiple global APIs with fallback | No single free API guarantees uptime; fallback ensures reliability | ✓ Good — v1.0 |
| Major airports only for 3D labels | Showing all airports would be visually cluttered and hurt performance | ✓ Good — v1.0 |
| 4-phase roadmap: Data -> Airports -> Terrain -> Airspace | Follows dependency chain; each phase delivers independently verifiable capability | ✓ Good — v1.0 |
| Metal over SceneKit for 3D | Maximum performance and control for real-time flight data rendering | ✓ Good — v2.0 |
| SwiftUI over AppKit for UI | Modern, declarative, sufficient for controls/panels/settings | ✓ Good — v2.0 |
| Triple buffering with DispatchSemaphore(value: 3) | Smooth 60fps without GPU stalls | ✓ Good — v2.0 |
| Mercator projection with worldScale=500 | Simple coordinate mapping, works globally | ✓ Good — v2.0 |
| NotificationCenter for SwiftUI-Metal bridge | Decoupled communication, avoids tight binding | ✓ Good — v2.0 |
| @AppStorage + UserDefaults.standard frame-time reads | Settings persist and take effect immediately | ✓ Good — v2.0 |
| CPU-side terrain vertex displacement | Simpler than GPU displacement, adequate for current tile count | ✓ Good — v2.0 |
| MenuBarExtra for menu bar status | Pure SwiftUI, no AppKit bridging needed | ✓ Good — v2.0 |
| Unsigned DMG default, signed as opt-in | Works without Apple Developer Program membership | ✓ Good — v2.0 |
| Zero external Swift dependencies | URLSession, simd, UserDefaults only — no SPM packages | ✓ Good — v2.0 |
| Direct download distribution | No App Store sandboxing, faster iteration, full system access | ✓ Good — v2.0 |

---
*Last updated: 2026-02-09 after v2.1 milestone started*
