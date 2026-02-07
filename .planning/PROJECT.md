# Airplane Tracker 3D

## What This Is

A browser-based 3D flight tracker that visualizes real-time aircraft positions using THREE.js WebGL rendering. It supports two data modes: local (dump1090 ADS-B receiver) and global (public APIs like airplanes.live and ADS-B Exchange). The app shows aircraft with smooth interpolated movement, flight trails, multiple themes, and rich enrichment data — plus terrain elevation, airspace volumes, airport search, and 3D airport labels.

## Core Value

Real-time 3D flight visualization that works both as a personal ADS-B receiver dashboard and as a global flight explorer with airport discovery.

## Requirements

### Validated

- ✓ 3D aircraft rendering with smooth interpolation between data updates — existing
- ✓ Real-time data polling from dump1090 (aircraft.json, stats.json) — existing
- ✓ Three visual themes: day, night, retro 80s — existing
- ✓ Flight trails with altitude/speed color coding — existing
- ✓ Aircraft enrichment via hexdb.io, adsbdb.com, adsb.lol APIs — existing
- ✓ Map tile rendering with zoom/pan (OSM, CartoDB, Stamen) — existing
- ✓ Aircraft selection with detail panel and external links — existing
- ✓ Statistics graphs (message rate, aircraft count, signal level) — existing
- ✓ Settings persistence via cookies — existing
- ✓ Keyboard shortcuts and touch controls — existing
- ✓ Performance optimization (object pooling, LOD, shared geometries) — existing
- ✓ IndexedDB persistence for stats history and trail data — existing
- ✓ Aircraft category detection (helicopter, military, small, regional, widebody, jet) — existing
- ✓ Follow aircraft mode with smooth camera tracking — existing
- ✓ Coverage heatmap visualization — existing

### Active

- [ ] Data source abstraction layer with mode switch (local dump1090 / global APIs)
- [ ] Global data sourcing from multiple APIs with fallback (airplanes.live, ADS-B Exchange, adsb.lol)
- [ ] Airport locator with search by name, IATA/ICAO code, and autocomplete
- [ ] Browse nearby airports list
- [ ] 3D text labels on ground for major airports (city/airport name)
- [ ] 3D terrain elevation with satellite imagery
- [ ] Airspace volume rendering (Class B/C/D boundaries)
- [ ] Both modes share all new features (terrain, labels, airspace)
- [ ] Camera fly-to animation when selecting airport from search

### Out of Scope

- Recording/playback functionality — adds significant complexity, not core to the vision
- Fly mode (WASD navigation) — orbit camera is sufficient
- Mobile native app — web-first, works in mobile browser
- User accounts or authentication — client-side only
- Real-time chat or social features — this is a visualization tool

## Context

This is a brownfield project with a working single-file HTML application (~4,600 lines). The current architecture is procedural JavaScript with extensive performance optimizations (object pooling, shared geometries, LOD). The app currently only supports local dump1090 data. The main evolution is adding global data sources and richer geographic context (terrain, airports, airspace).

Inspiration: [Air Loom](http://objectiveunclear.com/airloom.html) — a similar 3D flight tracker with terrain elevation, airspace rendering, and airport search. The goal is to bring those capabilities into this project while maintaining the existing local mode.

Airport data source: OurAirports dataset (open data, includes coordinates, IATA/ICAO codes, names, types).

## Constraints

- **Tech stack**: Must remain a single-file HTML application with vanilla JavaScript and THREE.js (no build tooling)
- **Performance**: Must maintain 30fps+ with 200+ aircraft visible
- **Compatibility**: Must work in modern browsers (Chrome 80+, Firefox 75+, Safari 13+)
- **Data sources**: Global APIs must be free/public (no paid API keys required)
- **Offline tolerance**: App should degrade gracefully when APIs are unavailable

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Shared core with mode switch (not separate files) | Avoids code duplication, both modes benefit from new features | — Pending |
| Multiple global APIs with fallback | No single free API guarantees uptime; fallback ensures reliability | — Pending |
| Major airports only for 3D labels | Showing all airports would be visually cluttered and hurt performance | — Pending |
| Terrain elevation for both modes | Local mode users also benefit from geographic context | — Pending |

---
*Last updated: 2026-02-07 after initialization*
