# Roadmap: Airplane Tracker 3D

## Milestones

- **v1.0 Web App Foundation** - Phases 1-4 (shipped 2026-02-07)
- **v2.0 Native macOS App** - Phases 5-10 (in progress)

## Phases

<details>
<summary>v1.0 Web App Foundation (Phases 1-4) - SHIPPED 2026-02-07</summary>

### Phase 1: Data Source Abstraction
**Goal**: Users can switch between local dump1090 and global flight data with automatic API failover
**Status**: Complete (2026-02-07)

### Phase 2: Airport Search and Labels
**Goal**: Users can discover airports by searching, browsing nearby, and seeing 3D labels on the ground
**Status**: Complete (2026-02-07)

### Phase 3: Terrain Elevation
**Goal**: The ground has real 3D elevation with satellite or map imagery draped over the terrain surface
**Status**: Complete (2026-02-07)

### Phase 4: Airspace Volumes
**Goal**: Controlled airspace (Class B/C/D) renders as visible 3D volumes around airports
**Status**: Complete (2026-02-07)

</details>

### v2.0 Native macOS App (Phases 5-10)

**Milestone Goal:** Rewrite the core flight visualization as a fully native macOS application using Swift, Metal 3, and SwiftUI -- optimized for Apple Silicon, no WebView.

**Phase Numbering:**
- Integer phases (5, 6, 7...): Planned milestone work
- Decimal phases (e.g., 6.1): Urgent insertions (marked with INSERTED)

- [x] **Phase 5: Metal Foundation + Ground Plane** - MTKView rendering surface, orbital camera with trackpad gestures, and map tile ground plane ✅
- [x] **Phase 6: Data Pipeline + Aircraft Rendering** - Live aircraft from network APIs with instanced Metal rendering and smooth interpolation ✅
- [x] **Phase 7: Trails + Labels + Selection** - Flight trails, billboard text labels, aircraft selection with detail panel, and follow mode ✅
- [ ] **Phase 8: Terrain + Themes** - Elevation mesh, three visual themes, and airport ground labels
- [ ] **Phase 9: UI Controls + Settings + Airports** - SwiftUI controls, airport search, statistics, keyboard shortcuts, and settings persistence
- [ ] **Phase 10: Native macOS Integration + Distribution** - Menu bar status item, dock badge, notifications, native menus, and notarized DMG

## Phase Details

### Phase 5: Metal Foundation + Ground Plane
**Goal**: User sees a navigable 3D map -- a Metal-rendered ground plane with real map tiles that responds to trackpad orbit, zoom, and pan gestures
**Depends on**: Nothing (first phase of v2.0 milestone)
**Requirements**: REND-07, REND-10, CAM-01, CAM-02, CAM-03, CAM-04, CAM-05
**Success Criteria** (what must be TRUE):
  1. User sees a macOS window with map tiles rendered on a 3D ground plane that matches real-world geography at the configured center coordinates
  2. User can orbit the view by rotating with two fingers on the trackpad, zoom with pinch, and pan with two-finger drag -- all at 60fps
  3. User can reset the camera to the default view position with a single action
  4. User can enable auto-rotate and the camera orbits smoothly around the center point as an ambient display
  5. Map tiles load asynchronously as the user navigates -- tiles appear progressively without blocking the rendering loop
**Plans:** 2 plans

Plans:
- [x] 05-01-PLAN.md -- Xcode project, MTKView + SwiftUI shell, triple-buffered renderer, and orbital camera
- [x] 05-02-PLAN.md -- Map tile ground plane with async tile loading and coordinate system

### Phase 6: Data Pipeline + Aircraft Rendering
**Goal**: User sees live aircraft appearing on the map from real ADS-B data sources, rendered as distinct 3D models with smooth 60fps movement
**Depends on**: Phase 5 (needs rendering surface and coordinate system)
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04, REND-01, REND-02, REND-03, REND-04, REND-05
**Success Criteria** (what must be TRUE):
  1. User sees aircraft from local dump1090 receiver (1s polling) or global APIs (5s polling) appearing at correct geographic positions on the map
  2. User can switch between local and global data modes, and when a global API fails, the app silently falls back to the next provider with no visible interruption
  3. User sees 6 distinct aircraft model categories (jet, widebody, helicopter, small prop, military, regional) rendered via instanced Metal draw calls at 60fps with 200+ aircraft
  4. User sees aircraft move smoothly between data updates (no teleporting), with altitude-based color gradient, glow sprites, blinking position lights, and spinning rotors/propellers
**Plans:** 2 plans

Plans:
- [x] 06-01-PLAN.md -- Flight data actor, network polling, provider fallback, and data normalization
- [x] 06-02-PLAN.md -- Instanced aircraft rendering with 6 model categories, interpolation, and visual effects

### Phase 7: Trails + Labels + Selection
**Goal**: User can identify aircraft by their labels, trace their flight paths, select aircraft for details, and follow them with the camera
**Depends on**: Phase 6 (needs aircraft data and rendering)
**Requirements**: REND-06, ACFT-01, ACFT-02, ACFT-03, ACFT-04, CAM-06
**Success Criteria** (what must be TRUE):
  1. User sees flight trails behind each aircraft with per-vertex altitude color gradient, and can configure trail length (50-4000 points) and width
  2. User sees billboard text labels above each aircraft showing callsign and altitude, with labels fading or hiding at distance (LOD)
  3. User can click an aircraft to select it and see a SwiftUI detail panel with callsign, altitude, speed, heading, squawk, position, plus enrichment data (registration, type, operator, route) from hexdb.io and adsbdb.com
  4. User sees dashed altitude reference lines from each aircraft down to the ground plane
  5. User can follow a selected aircraft and the camera smoothly tracks it as it moves
**Plans:** 2 plans

Plans:
- [x] 07-01-PLAN.md -- GPU polyline trail rendering with screen-space extrusion and altitude color gradient
- [x] 07-02-PLAN.md -- Billboard labels, altitude lines, ray-cast selection, detail panel, enrichment, and follow camera

### Phase 8: Terrain + Themes
**Goal**: The world has depth and personality -- terrain elevation gives geographic context, and three distinct themes change the entire visual character
**Depends on**: Phase 5 (needs ground plane and map tile system), Phase 7 (themes affect all existing rendering passes)
**Requirements**: REND-08, REND-09, ARPT-03
**Success Criteria** (what must be TRUE):
  1. User sees terrain elevation from terrain-RGB tiles with visible mountains, valleys, and coastlines that match real-world geography
  2. User can switch between three themes -- day (solid), night (solid), and retro (wireframe) -- and the entire scene updates: ground, aircraft, trails, labels, and sky
  3. User sees 3D text labels on the ground for nearby major airports that remain readable as the camera moves
**Plans:** 2 plans

Plans:
- [ ] 08-01-PLAN.md -- Terrain elevation mesh from AWS Terrarium tiles with 32x32 subdivided meshes and vertex displacement
- [ ] 08-02-PLAN.md -- Three-theme system (day/night/retro) with theme-aware rendering for all passes, and airport ground labels

### Phase 9: UI Controls + Settings + Airports
**Goal**: User can configure every aspect of the app, search and fly to airports, view statistics, and control the app via keyboard -- and all preferences persist across restarts
**Depends on**: Phase 8 (UI controls need all features to exist before they can configure them)
**Requirements**: UI-01, UI-02, UI-03, UI-04, UI-05, UI-06, ARPT-01, ARPT-02, ARPT-04
**Success Criteria** (what must be TRUE):
  1. User can search airports by name, IATA code, or ICAO code with autocomplete results, fly to any result with smooth camera animation, and browse a nearby airports list
  2. User can configure settings (theme, units, data source, trail length/width, altitude exaggeration) via SwiftUI controls and those settings persist across app restarts
  3. User sees an info panel with aircraft count, last update time, and center coordinates
  4. User can view statistics graphs (aircraft count, message rate over time) rendered with SwiftUI Charts
  5. User can use keyboard shortcuts for common actions and sees them reflected in a native macOS menu bar
**Plans**: TBD

Plans:
- [ ] 09-01: Airport database loading, search with autocomplete, fly-to, and nearby browse
- [ ] 09-02: SwiftUI settings, info panel, statistics graphs, keyboard shortcuts, and persistence

### Phase 10: Native macOS Integration + Distribution
**Goal**: The app feels like a first-class macOS citizen -- menu bar status, dock badge, smart notifications, native menus -- and ships as a signed, notarized DMG
**Depends on**: Phase 9 (native integration wraps the complete, polished app)
**Requirements**: MAC-01, MAC-02, MAC-03, MAC-04, MAC-05
**Success Criteria** (what must be TRUE):
  1. User sees aircraft count in the macOS menu bar status item and as a badge on the dock icon
  2. User receives macOS notifications for configurable aircraft alerts (specific callsigns, emergency squawks, altitude/distance thresholds)
  3. User can use native macOS menus (File, Edit, View, Window) with standard shortcuts (Cmd+W, Cmd+Q, Cmd+,)
  4. User can download and install the app as a notarized DMG that passes Gatekeeper on a clean Mac without developer tools
**Plans**: TBD

Plans:
- [ ] 10-01: Menu bar status item, dock badge, and notification system
- [ ] 10-02: Native macOS menus, code signing, notarization, and DMG distribution

## Requirement Coverage

| Requirement | Description | Phase |
|-------------|-------------|-------|
| REND-01 | 3D aircraft models with 6 categories via instanced rendering | Phase 6 |
| REND-02 | Altitude-based per-instance color gradient | Phase 6 |
| REND-03 | Glow sprites with pulsing animation | Phase 6 |
| REND-04 | Position light blinking animation | Phase 6 |
| REND-05 | Helicopter rotors and propeller spinning | Phase 6 |
| REND-06 | Flight trails with altitude color gradient | Phase 7 |
| REND-07 | Map tile ground plane with async loading | Phase 5 |
| REND-08 | Three themes: day, night, retro wireframe | Phase 8 |
| REND-09 | Terrain elevation with vertex displacement mesh | Phase 8 |
| REND-10 | 4x MSAA anti-aliasing | Phase 5 |
| CAM-01 | Orbit camera with two-finger trackpad rotate | Phase 5 |
| CAM-02 | Zoom with trackpad pinch gesture | Phase 5 |
| CAM-03 | Pan with two-finger drag | Phase 5 |
| CAM-04 | Reset camera to default view | Phase 5 |
| CAM-05 | Auto-rotate for ambient display | Phase 5 |
| CAM-06 | Follow selected aircraft with smooth tracking | Phase 7 |
| DATA-01 | Poll local dump1090 at 1-second intervals | Phase 6 |
| DATA-02 | Poll global APIs with automatic failover | Phase 6 |
| DATA-03 | Smooth 60fps interpolated aircraft movement | Phase 6 |
| DATA-04 | Switch between local and global data modes | Phase 6 |
| ACFT-01 | Click aircraft for detail panel | Phase 7 |
| ACFT-02 | Aircraft enrichment from hexdb.io and adsbdb.com | Phase 7 |
| ACFT-03 | Billboard text labels with distance-based LOD | Phase 7 |
| ACFT-04 | Dashed altitude reference lines to ground | Phase 7 |
| ARPT-01 | Airport search by name/IATA/ICAO with autocomplete | Phase 9 |
| ARPT-02 | Fly-to airport with smooth camera animation | Phase 9 |
| ARPT-03 | 3D text labels on ground for major airports | Phase 8 |
| ARPT-04 | Browse nearby airports list | Phase 9 |
| UI-01 | Info panel with aircraft count, update time, coordinates | Phase 9 |
| UI-02 | Settings via SwiftUI controls | Phase 9 |
| UI-03 | Settings persist across app restarts | Phase 9 |
| UI-04 | Keyboard shortcuts with macOS menu bar integration | Phase 9 |
| UI-05 | Statistics graphs via SwiftUI Charts | Phase 9 |
| UI-06 | Imperial and metric unit switching | Phase 9 |
| MAC-01 | Menu bar status item with aircraft count | Phase 10 |
| MAC-02 | Dock icon badge with aircraft count | Phase 10 |
| MAC-03 | Configurable aircraft alert notifications | Phase 10 |
| MAC-04 | Notarized DMG distribution | Phase 10 |
| MAC-05 | Native macOS menus with standard shortcuts | Phase 10 |

**Coverage: 39/39 v2.0 requirements mapped. No orphans.**

## Progress

**Execution Order:**
Phases execute in numeric order: 5 -> 6 -> 7 -> 8 -> 9 -> 10

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Data Source Abstraction | v1.0 | 2/2 | Complete | 2026-02-07 |
| 2. Airport Search and Labels | v1.0 | 2/2 | Complete | 2026-02-07 |
| 3. Terrain Elevation | v1.0 | 2/2 | Complete | 2026-02-07 |
| 4. Airspace Volumes | v1.0 | 1/1 | Complete | 2026-02-07 |
| 5. Metal Foundation + Ground Plane | v2.0 | 2/2 | Complete | 2026-02-08 |
| 6. Data Pipeline + Aircraft Rendering | v2.0 | 2/2 | Complete | 2026-02-08 |
| 7. Trails + Labels + Selection | v2.0 | 2/2 | Complete | 2026-02-08 |
| 8. Terrain + Themes | v2.0 | 0/2 | Not started | - |
| 9. UI Controls + Settings + Airports | v2.0 | 0/2 | Not started | - |
| 10. Native macOS Integration + Distribution | v2.0 | 0/2 | Not started | - |
