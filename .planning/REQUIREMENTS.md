# Requirements: Airplane Tracker 3D

**Defined:** 2026-02-09
**Core Value:** Real-time 3D flight visualization that works both as a personal ADS-B receiver dashboard and as a global flight explorer with airport discovery.

## v2.1 Requirements

Requirements for v2.1 Polish & Bug Fixes. Each maps to roadmap phases.

### Bug Fixes

- [ ] **FIX-01**: User sees map tiles rendered on the ground plane surface (debug and fix tile fetching/texture pipeline)
- [ ] **FIX-02**: User sees propellers spinning correctly aligned with aircraft nose regardless of heading
- [ ] **FIX-03**: User sees improved aircraft model silhouettes that are recognizable per category (swept wings, tapered fuselages, distinctive tails)

### Info Panel Restoration

- [ ] **INFO-01**: User sees lat/lon position coordinates in the aircraft detail panel
- [ ] **INFO-02**: User can click external links to FlightAware, ADS-B Exchange, and planespotters.net from the detail panel
- [ ] **INFO-03**: User sees an aircraft photo in the detail panel (fetched from planespotters.net or hexdb.io with fallback placeholder)

### Airspace Volumes

- [ ] **AIR-01**: User sees translucent 3D airspace volumes (Class B/C/D) rendered on the map from FAA data
- [ ] **AIR-02**: User can toggle visibility of each airspace class (B, C, D) independently
- [ ] **AIR-03**: User sees airspace volumes colored by class (blue=B, green=C, magenta=D) with correct altitude tiers

### Coverage Heatmap

- [ ] **HEAT-01**: User sees a coverage heatmap visualization showing where aircraft have been detected
- [ ] **HEAT-02**: User can toggle coverage heatmap visibility on/off

### Visual Polish

- [ ] **VIS-01**: User sees terrain with distance-based level of detail (higher resolution near camera, lower resolution far away)
- [ ] **VIS-02**: User sees smoother panel transitions (spring animations) when showing/hiding UI panels
- [ ] **VIS-03**: User sees airspace labels at the center of each airspace volume identifying the airport

## Future Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced Visualization

- **ADV-01**: Weather radar overlay on map
- **ADV-02**: Flight path prediction (extrapolated trajectory)
- **ADV-03**: International airspace data (EUROCONTROL)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Loaded 3D aircraft models (glTF/OBJ) | Breaks instanced rendering paradigm; procedural geometry keeps all instances sharing vertex buffers |
| Order-independent transparency | Overkill for 6% opacity volumes; sorted alpha blending is visually identical |
| 3D elevated heatmap columns | Adds visual clutter; 2D overlay matches proven web UX |
| GPU polygon triangulation | CPU ear-clipping is instant for <500 features with <50 vertices each |
| Non-FAA airspace sources | Massively different data formats; US-only acceptable for v2.1 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FIX-01 | Phase 11 | Pending |
| FIX-02 | Phase 11 | Pending |
| FIX-03 | Phase 11 | Pending |
| INFO-01 | Phase 12 | Pending |
| INFO-02 | Phase 12 | Pending |
| INFO-03 | Phase 12 | Pending |
| AIR-01 | Phase 13 | Pending |
| AIR-02 | Phase 13 | Pending |
| AIR-03 | Phase 13 | Pending |
| HEAT-01 | Phase 14 | Pending |
| HEAT-02 | Phase 14 | Pending |
| VIS-01 | Phase 15 | Pending |
| VIS-02 | Phase 15 | Pending |
| VIS-03 | Phase 15 | Pending |

**Coverage:**
- v2.1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-02-09*
*Last updated: 2026-02-09 after roadmap creation*
