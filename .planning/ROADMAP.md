# Roadmap: Airplane Tracker 3D

## Milestones

- **v1.0 Web App Foundation** - Phases 1-4 (shipped 2026-02-07)
- **v2.0 Native macOS App** - Phases 5-10 (shipped 2026-02-09)
- **v2.1 Polish & Bug Fixes** - Phases 11-15 (in progress)

## Phases

<details>
<summary>v1.0 Web App Foundation (Phases 1-4) - SHIPPED 2026-02-07</summary>

- [x] Phase 1: Data Source Abstraction (2/2 plans) - 2026-02-07
- [x] Phase 2: Airport Search and Labels (2/2 plans) - 2026-02-07
- [x] Phase 3: Terrain Elevation (2/2 plans) - 2026-02-07
- [x] Phase 4: Airspace Volumes (1/1 plan) - 2026-02-07

</details>

<details>
<summary>v2.0 Native macOS App (Phases 5-10) - SHIPPED 2026-02-09</summary>

- [x] Phase 5: Metal Foundation + Ground Plane (2/2 plans) - 2026-02-08
- [x] Phase 6: Data Pipeline + Aircraft Rendering (2/2 plans) - 2026-02-08
- [x] Phase 7: Trails + Labels + Selection (2/2 plans) - 2026-02-08
- [x] Phase 8: Terrain + Themes (2/2 plans) - 2026-02-09
- [x] Phase 9: UI Controls + Settings + Airports (2/2 plans) - 2026-02-09
- [x] Phase 10: Native macOS Integration + Distribution (2/2 plans) - 2026-02-09

</details>

### v2.1 Polish & Bug Fixes (Phases 11-15)

**Milestone Goal:** Fix rendering bugs, restore missing info panel features from the web version, port airspace volumes and coverage heatmaps to native Metal, and polish visual quality across the app.

- [x] **Phase 11: Bug Fixes & Rendering Foundation** (2/2 plans) - 2026-02-09
- [x] **Phase 12: Info Panel Restoration** (1/1 plan) - 2026-02-09
- [x] **Phase 13: Airspace Volume Rendering** (2/2 plans) - 2026-02-09
- [x] **Phase 14: Coverage Heatmap** (2/2 plans) - 2026-02-09
- [ ] **Phase 15: Visual Polish** - Terrain LOD, panel animations, and airspace labels

## Phase Details

### Phase 11: Bug Fixes & Rendering Foundation
**Goal**: Users see a fully working ground plane with map tiles, correctly spinning propellers, and recognizable aircraft silhouettes per category
**Depends on**: Phase 10 (v2.0 shipped codebase)
**Requirements**: FIX-01, FIX-02, FIX-03
**Success Criteria** (what must be TRUE):
  1. User sees map tiles rendered on the ground plane surface when the app launches (no blank ground)
  2. User sees propellers spinning aligned with the aircraft nose regardless of the aircraft's heading
  3. User can visually distinguish aircraft categories by silhouette (swept wings on jets, straight wings on props, rotors on helicopters, wide fuselage on widebodies)
**Plans**: 2 plans

Plans:
- [ ] 11-01-PLAN.md -- Fix map tile loading pipeline and propeller rotation
- [ ] 11-02-PLAN.md -- Improve aircraft silhouettes for category distinction

### Phase 12: Info Panel Restoration
**Goal**: Users have a complete aircraft detail panel matching the web version's information density, with position, external links, and photos
**Depends on**: Phase 11 (rendering pipeline validated)
**Requirements**: INFO-01, INFO-02, INFO-03
**Success Criteria** (what must be TRUE):
  1. User sees latitude/longitude coordinates displayed in the aircraft detail panel when an aircraft is selected
  2. User can click links to FlightAware, ADS-B Exchange, and planespotters.net that open in the default browser with the correct aircraft pre-filled
  3. User sees an aircraft photo in the detail panel (fetched from planespotters.net or hexdb.io, with a placeholder shown while loading or if unavailable)
**Plans**: 1 plan

Plans:
- [ ] 12-01-PLAN.md -- Add external links, aircraft photo, and verify lat/lon in detail panel

### Phase 13: Airspace Volume Rendering
**Goal**: Users see translucent 3D airspace boundaries on the map that communicate controlled airspace classes and their altitude structure
**Depends on**: Phase 11 (rendering pipeline validated, map tiles working)
**Requirements**: AIR-01, AIR-02, AIR-03
**Success Criteria** (what must be TRUE):
  1. User sees semi-transparent 3D volumes rendered over major airports representing FAA Class B, C, and D airspace boundaries with correct floor/ceiling altitudes
  2. User can independently toggle visibility of Class B, Class C, and Class D airspace volumes from the UI
  3. User sees airspace volumes colored distinctly by class (blue for Class B, green for Class C, magenta for Class D) with concentric altitude tiers visible
  4. Aircraft and trails remain visible through and in front of airspace volumes (volumes do not occlude other scene elements)
**Plans**: 2 plans

Plans:
- [ ] 13-01-PLAN.md -- Airspace data pipeline: ShaderTypes, ear-clip triangulator, Metal shaders, AirspaceManager
- [ ] 13-02-PLAN.md -- Renderer integration: pipeline states, draw loop, theme colors, Settings toggles

### Phase 14: Coverage Heatmap
**Goal**: Users can visualize their ADS-B receiver coverage area as a density heatmap showing where aircraft have been detected over time
**Depends on**: Phase 11 (rendering pipeline validated, map tiles working)
**Requirements**: HEAT-01, HEAT-02
**Success Criteria** (what must be TRUE):
  1. User sees a color-mapped ground overlay showing aircraft detection density that updates as new aircraft positions are received
  2. User can toggle the coverage heatmap on and off without affecting other map layers
**Plans**: 2 plans

Plans:
- [ ] 14-01-PLAN.md -- HeatmapManager data pipeline: ShaderTypes, Metal shaders, grid accumulation, texture generation
- [ ] 14-02-PLAN.md -- Renderer integration: pipeline state, draw loop, theme colors, Settings toggle

### Phase 15: Visual Polish
**Goal**: Users experience higher visual fidelity through terrain detail, smooth UI transitions, and informative airspace labels
**Depends on**: Phase 13 (airspace volumes must exist before airspace labels can be added)
**Requirements**: VIS-01, VIS-02, VIS-03
**Success Criteria** (what must be TRUE):
  1. User sees higher-resolution terrain near the camera and lower-resolution terrain in the distance (level of detail scales with viewing distance)
  2. User sees smooth spring-animated transitions when showing and hiding UI panels (detail panel, settings, statistics)
  3. User sees text labels at the center of each airspace volume identifying the associated airport name
**Plans**: TBD

Plans:
- [ ] 15-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 11 -> 12 -> 13 -> 14 -> 15
Note: Phases 13 and 14 both depend on Phase 11 but not on each other. Phase 15 depends on Phase 13.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Data Source Abstraction | v1.0 | 2/2 | Complete | 2026-02-07 |
| 2. Airport Search and Labels | v1.0 | 2/2 | Complete | 2026-02-07 |
| 3. Terrain Elevation | v1.0 | 2/2 | Complete | 2026-02-07 |
| 4. Airspace Volumes | v1.0 | 1/1 | Complete | 2026-02-07 |
| 5. Metal Foundation + Ground Plane | v2.0 | 2/2 | Complete | 2026-02-08 |
| 6. Data Pipeline + Aircraft Rendering | v2.0 | 2/2 | Complete | 2026-02-08 |
| 7. Trails + Labels + Selection | v2.0 | 2/2 | Complete | 2026-02-08 |
| 8. Terrain + Themes | v2.0 | 2/2 | Complete | 2026-02-09 |
| 9. UI Controls + Settings + Airports | v2.0 | 2/2 | Complete | 2026-02-09 |
| 10. Native macOS Integration + Distribution | v2.0 | 2/2 | Complete | 2026-02-09 |
| 11. Bug Fixes & Rendering Foundation | v2.1 | 2/2 | Complete | 2026-02-09 |
| 12. Info Panel Restoration | v2.1 | 1/1 | Complete | 2026-02-09 |
| 13. Airspace Volume Rendering | v2.1 | 2/2 | Complete | 2026-02-09 |
| 14. Coverage Heatmap | v2.1 | 2/2 | Complete | 2026-02-09 |
| 15. Visual Polish | v2.1 | 0/0 | Not started | - |
