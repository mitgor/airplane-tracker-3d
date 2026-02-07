# Roadmap: Airplane Tracker 3D

## Overview

This roadmap evolves a working single-file 3D flight tracker (4,631 lines, THREE.js r128, vanilla JS) from local-only dump1090 data into a dual-mode application with global flight data, airport discovery, 3D terrain, and airspace visualization. The four phases follow a strict dependency chain: data source abstraction enables global mode (Phase 1), airport search and labels deliver immediate user value on the new global foundation (Phase 2), terrain elevation establishes the 3D ground reference (Phase 3), and airspace volumes complete the picture with controlled airspace boundaries rendered on top of terrain (Phase 4). Each phase delivers a coherent, independently verifiable capability.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4): Planned milestone work
- Decimal phases (e.g., 2.1): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Data Source Abstraction** - Dual-mode data layer enabling local dump1090 and global API flight tracking with automatic fallback
- [ ] **Phase 2: Airport Search and Labels** - Airport discovery via search, nearby browsing, 3D ground labels, and camera fly-to
- [ ] **Phase 3: Terrain Elevation** - 3D terrain meshes with elevation data and satellite/map imagery draped on the ground
- [ ] **Phase 4: Airspace Volumes** - Class B/C/D airspace boundary rendering as 3D extruded volumes

## Phase Details

### Phase 1: Data Source Abstraction
**Goal**: Users can switch between local dump1090 and global flight data, seeing aircraft anywhere in the world with automatic API failover -- and all existing and future features work identically in both modes
**Depends on**: Nothing (first phase)
**Requirements**: DATA-01, DATA-02, CORE-01
**Success Criteria** (what must be TRUE):
  1. User can toggle between "Local" and "Global" data modes from the UI without restarting the app
  2. In global mode, aircraft appear around the current map center from airplanes.live, adsb.lol, or another fallback API -- and the user never sees which API is active (it just works)
  3. When the primary global API fails or returns errors, the app silently falls back to the next provider with no visible interruption in aircraft data
  4. All existing features (trails, enrichment, themes, selection, follow mode, stats) work identically regardless of data mode
  5. Global mode respects API rate limits (5-10 second polling interval) and does not trigger 429 errors during normal use
**Plans**: TBD

Plans:
- [ ] 01-01: Data source adapter architecture and mode switch
- [ ] 01-02: Global API integration with fallback chain

### Phase 2: Airport Search and Labels
**Goal**: Users can discover airports by searching, browsing nearby, and seeing 3D labels on the ground -- with smooth camera animation to any selected airport
**Depends on**: Phase 1 (global mode provides geographic context for airport search in any location)
**Requirements**: ARPT-01, ARPT-02, ARPT-03, ARPT-04
**Success Criteria** (what must be TRUE):
  1. User can type an airport name, city, IATA code, or ICAO code into a search box and see ranked autocomplete results within 200ms
  2. User can browse a list of nearby airports (sorted by distance from current view center) and click any airport to navigate there
  3. Major airports within the current view display 3D text labels on the ground (city name and airport code) that scale appropriately with zoom and do not cause FPS drops below 30
  4. Selecting an airport from search or nearby list triggers a smooth camera fly-to animation that centers the view on that airport
  5. Airport data loads asynchronously after app startup -- aircraft tracking works immediately while airports load in the background
**Plans**: TBD

Plans:
- [ ] 02-01: Airport database loading, indexing, and search
- [ ] 02-02: Nearby airports, 3D ground labels, and camera fly-to

### Phase 3: Terrain Elevation
**Goal**: The ground has real 3D elevation -- mountains rise, valleys dip, and satellite or map imagery drapes over the terrain surface
**Depends on**: Phase 1 (terrain works in both data modes per CORE-01)
**Requirements**: TERR-01
**Success Criteria** (what must be TRUE):
  1. Terrain meshes display visible elevation changes (mountains, valleys, coastlines) that match real-world geography at the current map location
  2. Satellite imagery (or theme-appropriate map tiles) is draped on the terrain surface, aligned with the existing map tile grid
  3. Terrain loads progressively as the user pans and zooms, without blocking aircraft rendering or dropping FPS below 30 with 200+ aircraft visible
  4. Terrain tiles are cached and properly disposed when panning away -- GPU memory does not grow unbounded during a 30-minute session
  5. Aircraft altitude lines and positions remain visually correct relative to the terrain surface (aircraft do not clip inside mountains)
**Plans**: TBD

Plans:
- [ ] 03-01: Terrain tile fetching, elevation decoding, and mesh generation
- [ ] 03-02: Imagery draping, LOD, memory management, and aircraft-terrain interaction

### Phase 4: Airspace Volumes
**Goal**: Controlled airspace (Class B/C/D) is rendered as visible 3D volumes around airports, giving users spatial awareness of airspace structure
**Depends on**: Phase 2 (airport locations drive which airspace to load), Phase 3 (airspace volumes look correct sitting on terrain)
**Requirements**: ASPC-01
**Success Criteria** (what must be TRUE):
  1. Class B, C, and D airspace boundaries render as 3D volumes with correct floor and ceiling altitudes around US airports
  2. Airspace volumes are visually distinguishable by class (different colors) and do not cause rendering artifacts (flickering, disappearing) when the camera rotates
  3. Airspace loads on-demand for the current view area and does not cause FPS drops below 30 or block other rendering
  4. User can toggle airspace visibility on/off from the UI
**Plans**: TBD

Plans:
- [ ] 04-01: Airspace data loading, parsing, and 3D volume rendering

## Requirement Coverage

| Requirement | Description | Phase |
|-------------|-------------|-------|
| DATA-01 | Data source abstraction layer with mode switch | Phase 1 |
| DATA-02 | Global data sourcing with API fallback | Phase 1 |
| CORE-01 | Both modes share all new features | Phase 1 |
| ARPT-01 | Airport search by name/IATA/ICAO with autocomplete | Phase 2 |
| ARPT-02 | Browse nearby airports list | Phase 2 |
| ARPT-03 | 3D text labels on ground for major airports | Phase 2 |
| ARPT-04 | Camera fly-to animation on airport selection | Phase 2 |
| TERR-01 | 3D terrain elevation with satellite imagery | Phase 3 |
| ASPC-01 | Airspace volume rendering (Class B/C/D) | Phase 4 |

**Coverage: 9/9 requirements mapped. No orphans.**

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Data Source Abstraction | 0/2 | Not started | - |
| 2. Airport Search and Labels | 0/2 | Not started | - |
| 3. Terrain Elevation | 0/2 | Not started | - |
| 4. Airspace Volumes | 0/1 | Not started | - |
