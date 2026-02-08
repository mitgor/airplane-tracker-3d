# Airplane Tracker 3D

## What This Is

A real-time 3D flight tracker available as both a browser-based web app (THREE.js/WebGL) and a native macOS application (Swift/Metal/SwiftUI). It visualizes aircraft positions with smooth interpolated movement, flight trails, and rich enrichment data. The web version includes terrain elevation, airspace volumes, airport search, and 3D labels. The native macOS version is being built as a high-performance ARM-optimized Metal application.

## Core Value

Real-time 3D flight visualization that works both as a personal ADS-B receiver dashboard and as a global flight explorer with airport discovery.

## Current Milestone: v2.0 Native macOS App

**Goal:** Rewrite the core flight visualization as a fully native macOS application using Swift, Metal, and SwiftUI — optimized for Apple Silicon, no WebView.

**Target features (core first):**
- Native Metal 3D rendering pipeline for aircraft visualization
- Real-time data polling (dump1090 local + global API sources)
- Smooth aircraft interpolation and flight trails
- SwiftUI controls and aircraft detail panel
- ARM-optimized performance targeting 60fps+

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

### Active

<!-- v2.0 — Native macOS App requirements defined in REQUIREMENTS.md -->

(Defined in REQUIREMENTS.md)

### Out of Scope

- Recording/playback functionality — adds significant complexity, not core to the vision
- Fly mode (WASD navigation) — orbit camera is sufficient
- Mobile native app — macOS-first for v2.0
- User accounts or authentication — client-side only
- Real-time chat or social features — this is a visualization tool
- WebView/WKWebView wrapper — must be fully native Metal rendering
- Mac App Store distribution — direct download for v2.0
- Full feature parity with web version in v2.0 — core features first, add terrain/airspace/airports in later milestones

## Context

This is a platform rewrite. The existing web app (~5,600 lines, single HTML file) serves as the feature reference. The v2.0 native app will be built in Swift using Metal for 3D rendering and SwiftUI for UI controls. The goal is native performance optimized for Apple Silicon (M1/M2/M3/M4), targeting 60fps+ with hundreds of aircraft.

The web version remains the production app. The native version starts with core rendering and data pipeline, with richer features (terrain, airports, airspace) planned for subsequent milestones.

Inspiration: [Air Loom](http://objectiveunclear.com/airloom.html) — the native app should feel as polished and performant as dedicated aviation software.

Airport data source: OurAirports dataset (open data, includes coordinates, IATA/ICAO codes, names, types).

## Constraints

- **Tech stack**: Swift, Metal, SwiftUI — no WebView, no Electron, no Catalyst
- **Architecture**: Apple Silicon ARM-optimized, universal binary acceptable but ARM primary
- **Performance**: Must target 60fps+ with 200+ aircraft on Apple Silicon
- **Data sources**: Global APIs must be free/public (no paid API keys required)
- **Offline tolerance**: App should degrade gracefully when APIs are unavailable
- **Distribution**: Direct download (DMG), no App Store sandboxing constraints
- **macOS version**: macOS 13 Ventura+ (Metal 3 support)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Shared core with mode switch (not separate files) | Avoids code duplication, both modes benefit from new features | ✓ Good — v1.0 |
| Multiple global APIs with fallback | No single free API guarantees uptime; fallback ensures reliability | ✓ Good — v1.0 |
| Major airports only for 3D labels | Showing all airports would be visually cluttered and hurt performance | ✓ Good — v1.0 |
| 4-phase roadmap: Data -> Airports -> Terrain -> Airspace | Follows dependency chain; each phase delivers independently verifiable capability | ✓ Good — v1.0 |
| Metal over SceneKit for 3D | Maximum performance and control for real-time flight data rendering | — Pending |
| SwiftUI over AppKit for UI | Modern, declarative, sufficient for controls/panels/settings | — Pending |
| Core features first, add terrain/airports later | Reduces v2.0 scope to achievable milestone, proves native rendering works | — Pending |
| Direct download distribution | No App Store sandboxing, faster iteration, full system access | — Pending |

---
*Last updated: 2026-02-08 after v2.0 milestone start*
