# Requirements: Airplane Tracker 3D

**Defined:** 2026-02-08
**Core Value:** Real-time 3D flight visualization that works both as a personal ADS-B receiver dashboard and as a global flight explorer with airport discovery.

## v2.0 Requirements

Requirements for native macOS Metal app. Each maps to roadmap phases.

### Metal Rendering

- [ ] **REND-01**: User sees aircraft rendered as 3D models in Metal with 6 distinct categories (jet, widebody, helicopter, small prop, military, regional) using instanced rendering
- [ ] **REND-02**: User sees aircraft colored by altitude with per-instance color gradient
- [ ] **REND-03**: User sees glow sprites on each aircraft with pulsing animation
- [ ] **REND-04**: User sees position light blinking animation on aircraft
- [ ] **REND-05**: User sees helicopter rotors and prop plane propellers spinning
- [ ] **REND-06**: User sees flight trails with per-vertex altitude color gradient (configurable length 50-4000 points, configurable width)
- [ ] **REND-07**: User sees map tile ground plane with async tile loading at zoom levels 6-12
- [ ] **REND-08**: User can switch between three themes: day (solid), night (solid), retro (wireframe) with distinct color palettes
- [ ] **REND-09**: User sees terrain elevation from terrain-RGB tiles with vertex displacement mesh
- [ ] **REND-10**: User sees 4x MSAA anti-aliasing for smooth edges

### Camera Controls

- [ ] **CAM-01**: User can orbit the camera with two-finger trackpad rotate
- [ ] **CAM-02**: User can zoom with trackpad pinch gesture
- [ ] **CAM-03**: User can pan the map with two-finger drag
- [ ] **CAM-04**: User can reset camera to default view
- [ ] **CAM-05**: User can enable auto-rotate for ambient display
- [ ] **CAM-06**: User can follow a selected aircraft with smooth camera tracking

### Data Pipeline

- [ ] **DATA-01**: User can poll local dump1090 receiver at 1-second intervals
- [ ] **DATA-02**: User can poll global APIs (airplanes.live, adsb.lol) with automatic failover at 5-second intervals
- [ ] **DATA-03**: User sees smooth 60fps aircraft movement interpolated from 1-5 second data updates
- [ ] **DATA-04**: User can switch between local and global data modes

### Aircraft Interaction

- [ ] **ACFT-01**: User can click an aircraft to select it and see a detail panel (callsign, altitude, speed, heading, squawk, position)
- [ ] **ACFT-02**: User sees aircraft enrichment data (registration, type, operator, route) from hexdb.io and adsbdb.com
- [ ] **ACFT-03**: User sees billboard text labels above each aircraft showing callsign and altitude with distance-based LOD
- [ ] **ACFT-04**: User sees dashed altitude reference lines from aircraft to ground

### Airport Features

- [ ] **ARPT-01**: User can search airports by name, IATA code, or ICAO code with autocomplete
- [ ] **ARPT-02**: User can fly-to any airport from search results with smooth camera animation
- [ ] **ARPT-03**: User sees 3D text labels on ground for nearby major airports
- [ ] **ARPT-04**: User can browse nearby airports list

### UI & Settings

- [ ] **UI-01**: User sees an info panel with aircraft count, last update time, center coordinates
- [ ] **UI-02**: User can configure settings (theme, units, data source, trail length/width, altitude exaggeration) via SwiftUI controls
- [ ] **UI-03**: User's settings persist across app restarts
- [ ] **UI-04**: User can use keyboard shortcuts for common actions with native macOS menu bar integration
- [ ] **UI-05**: User can view statistics graphs (aircraft count, message rate over time) via SwiftUI Charts
- [ ] **UI-06**: User can switch between imperial and metric units

### Native macOS

- [ ] **MAC-01**: User sees aircraft count in the macOS menu bar status item
- [ ] **MAC-02**: User sees aircraft count badge on the dock icon
- [ ] **MAC-03**: User receives macOS notifications for configurable aircraft alerts (callsigns, emergency squawks, altitude/distance thresholds)
- [ ] **MAC-04**: User can distribute the app as a notarized DMG for direct download
- [ ] **MAC-05**: User can use native macOS menus (File, Edit, View, Window) with standard shortcuts (Cmd+W, Cmd+Q, Cmd+,)

## v2.1+ Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Airspace

- **ASPC-01**: User sees airspace volumes (FAA Class B/C/D) as transparent extruded polygons

### Platform Integration

- **PLAT-01**: User sees desktop widgets showing aircraft count and stats (WidgetKit)
- **PLAT-02**: User can search active flights from macOS Spotlight
- **PLAT-03**: User can use Siri shortcuts for flight queries (App Intents)
- **PLAT-04**: User can open multiple windows showing different geographic regions

### Visual Polish

- **VIS-01**: User sees post-processing bloom glow effect on retro theme
- **VIS-02**: User sees HDR/EDR vivid colors on capable displays
- **VIS-03**: User sees coverage heatmap visualization

### Data Persistence

- **PERS-01**: User's statistics history persists in SQLite across app restarts
- **PERS-02**: User's flight trails persist and restore when aircraft reappear

## Out of Scope

| Feature | Reason |
|---------|--------|
| WebView / WKWebView | Must be fully native Metal rendering -- defeats the purpose of the rewrite |
| SceneKit / RealityKit | Higher-level 3D frameworks prevent instanced rendering architecture |
| MapKit for 3D view | Cannot composite with custom Metal rendering pipeline |
| iOS / iPadOS port | Different UI, gesture model, and platform integration -- separate project |
| Photorealistic aircraft models | Conflicts with stylized aesthetic and breaks instancing (shared geometry required) |
| Recording / playback | Massive scope, explicitly excluded in web version |
| Real-time audio / ATC | Zero overlap with visual tracking, enormous scope |
| ML flight prediction | Research project, not product feature -- linear extrapolation sufficient |
| Electron / Catalyst | Defeats native Metal + SwiftUI purpose |
| Touch Bar | Discontinued hardware, zero new users |
| Mac App Store | Direct download for v2.0, App Store can be added later |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| REND-01 | Phase 6 | Pending |
| REND-02 | Phase 6 | Pending |
| REND-03 | Phase 6 | Pending |
| REND-04 | Phase 6 | Pending |
| REND-05 | Phase 6 | Pending |
| REND-06 | Phase 7 | Pending |
| REND-07 | Phase 5 | Pending |
| REND-08 | Phase 8 | Pending |
| REND-09 | Phase 8 | Pending |
| REND-10 | Phase 5 | Pending |
| CAM-01 | Phase 5 | Pending |
| CAM-02 | Phase 5 | Pending |
| CAM-03 | Phase 5 | Pending |
| CAM-04 | Phase 5 | Pending |
| CAM-05 | Phase 5 | Pending |
| CAM-06 | Phase 7 | Pending |
| DATA-01 | Phase 6 | Pending |
| DATA-02 | Phase 6 | Pending |
| DATA-03 | Phase 6 | Pending |
| DATA-04 | Phase 6 | Pending |
| ACFT-01 | Phase 7 | Pending |
| ACFT-02 | Phase 7 | Pending |
| ACFT-03 | Phase 7 | Pending |
| ACFT-04 | Phase 7 | Pending |
| ARPT-01 | Phase 9 | Pending |
| ARPT-02 | Phase 9 | Pending |
| ARPT-03 | Phase 8 | Pending |
| ARPT-04 | Phase 9 | Pending |
| UI-01 | Phase 9 | Pending |
| UI-02 | Phase 9 | Pending |
| UI-03 | Phase 9 | Pending |
| UI-04 | Phase 9 | Pending |
| UI-05 | Phase 9 | Pending |
| UI-06 | Phase 9 | Pending |
| MAC-01 | Phase 10 | Pending |
| MAC-02 | Phase 10 | Pending |
| MAC-03 | Phase 10 | Pending |
| MAC-04 | Phase 10 | Pending |
| MAC-05 | Phase 10 | Pending |

**Coverage:**
- v2.0 requirements: 39 total
- Mapped to phases: 39
- Unmapped: 0

---
*Requirements defined: 2026-02-08*
*Last updated: 2026-02-08 after roadmap creation*
