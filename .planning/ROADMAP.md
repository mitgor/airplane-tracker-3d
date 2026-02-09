# Roadmap: Airplane Tracker 3D

## Milestones

- **v1.0 Web App Foundation** - Phases 1-4 (shipped 2026-02-07)
- **v2.0 Native macOS App** - Phases 5-10 (shipped 2026-02-09)
- **v2.1 Polish & Bug Fixes** - Phases 11-15 (shipped 2026-02-09)
- **v2.2 Core Fixes & Data Sources** - Phases 16-18 (in progress)

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

<details>
<summary>v2.1 Polish & Bug Fixes (Phases 11-15) - SHIPPED 2026-02-09</summary>

- [x] Phase 11: Bug Fixes & Rendering Foundation (2/2 plans) - 2026-02-09
- [x] Phase 12: Info Panel Restoration (1/1 plan) - 2026-02-09
- [x] Phase 13: Airspace Volume Rendering (2/2 plans) - 2026-02-09
- [x] Phase 14: Coverage Heatmap (2/2 plans) - 2026-02-09
- [x] Phase 15: Visual Polish (2/2 plans) - 2026-02-09

</details>

### v2.2 Core Fixes & Data Sources (In Progress)

**Milestone Goal:** Fix broken aircraft/airport visibility, expand airport database, and add configurable remote dump1090 data source.

- [ ] **Phase 16: Camera-Following API & Aircraft Visibility** - Global API queries follow the camera so aircraft actually appear
- [ ] **Phase 17: Expanded Airport Database** - 500 airports with correct search and labels
- [ ] **Phase 18: Remote Data Sources** - Configurable remote dump1090 and unified source switching

## Phase Details

### Phase 16: Camera-Following API & Aircraft Visibility
**Goal**: Aircraft are visible on the 3D map wherever the user looks by making the global API query center follow the camera position
**Depends on**: Nothing (foundational fix for this milestone)
**Requirements**: DATA-02, RNDR-01
**Success Criteria** (what must be TRUE):
  1. User pans the camera to a new geographic area and aircraft begin loading for that area within one polling cycle
  2. Aircraft icons are visible and correctly positioned on the 3D globe when the global API returns data
  3. Moving the camera to different continents loads aircraft for each new area (not stuck on a fixed coordinate)
**Plans:** 1 plan

Plans:
- [ ] 16-01-PLAN.md — Dynamic polling center + camera-to-actor wiring

### Phase 17: Expanded Airport Database
**Goal**: Users can discover and search for any major commercial airport worldwide, with correct search results and visible 3D labels
**Depends on**: Nothing (independent of Phase 16)
**Requirements**: ARPT-01, ARPT-02, ARPT-03
**Success Criteria** (what must be TRUE):
  1. Airport database contains approximately 500 major worldwide airports with scheduled commercial service
  2. User can search for "Berlin" and get Berlin Brandenburg (BER) as a result, not unrelated airports
  3. User can search by name, IATA code, or ICAO code and get correct matches for all 500 airports
  4. Airport labels render on the 3D map for all airports in the expanded database (respecting existing distance culling)
**Plans:** 1 plan

Plans:
- [ ] 17-01-PLAN.md — Expand airports.json to ~500 airports and resize label atlas

### Phase 18: Remote Data Sources
**Goal**: Users can connect to a remote dump1090 receiver over the network and seamlessly switch between Local, Remote, and Global data sources
**Depends on**: Phase 16 (camera-following center is part of the data pipeline that remote sources interact with)
**Requirements**: DATA-01, DATA-03, DATA-04
**Success Criteria** (what must be TRUE):
  1. User can enter an IP address and port for a remote dump1090 instance in Settings
  2. User can choose between Local, Remote, and Global data sources in Settings
  3. Switching data source takes effect immediately -- aircraft from the new source appear without restarting the app
  4. Remote dump1090 polls aircraft.json from the configured IP:port and displays aircraft on the map
**Plans**: TBD

Plans:
- [ ] 18-01: TBD
- [ ] 18-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 16 -> 17 -> 18

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
| 15. Visual Polish | v2.1 | 2/2 | Complete | 2026-02-09 |
| 16. Camera-Following API & Aircraft Visibility | v2.2 | 0/1 | Not started | - |
| 17. Expanded Airport Database | v2.2 | 0/1 | Not started | - |
| 18. Remote Data Sources | v2.2 | 0/TBD | Not started | - |
