# Project Research Summary

**Project:** Airplane Tracker 3D -- Global Data, Terrain, Airspace, Airport Search
**Domain:** 3D Flight Tracking Visualization
**Researched:** 2026-02-07
**Confidence:** MEDIUM-HIGH

## Executive Summary

This project extends a mature 3D flight tracker (4,631 lines, THREE.js r128, single-file HTML architecture) with four major capabilities: global flight data sourcing via API fallback chains, 3D terrain elevation with satellite imagery, airspace volume rendering (Class B/C/D), and comprehensive airport search with ground labels. The existing system is performant (30fps+ with 200 aircraft) and architecturally sound with established patterns for aircraft interpolation, trail rendering, and map tile management.

The recommended approach is incremental integration that reuses existing coordinate systems, tile grids, and rendering pipelines. Critical success factors: (1) implement terrain using vertex shader displacement rather than CPU-side vertex manipulation to avoid memory explosion, (2) respect API rate limits with geographic queries and fallback chains (airplanes.live -> adsb.lol -> OpenSky), (3) render airspace volumes as wireframe outlines to avoid WebGL transparency artifacts, (4) pre-filter OurAirports data to medium/large airports only (~5K airports vs 78K) to keep memory and performance reasonable.

The primary risk is terrain tile memory consumption -- naive implementation with 256x256 vertices per tile would create 6.5 million vertices across a 10x10 grid, crashing the browser. Using vertex shader displacement with shared low-poly geometry (32x32 segments) keeps terrain cost to <100 geometries total. Secondary risks include API rate limit bans (mitigated by 5-10 second polling intervals for global data) and single-file maintainability (4,631 lines growing to 6,500+ requires strict section organization or multi-file split).

## Key Findings

### Recommended Stack

The stack extends the existing single-file HTML + THREE.js r128 + vanilla JS application with zero build tooling. All additions are CDN-free APIs consumed via `fetch()` or static data embedded/loaded at runtime.

**Core technologies:**

- **airplanes.live API v2** (primary global data): 250nm radius queries, 1 req/sec rate limit, no auth, ADSBx v2 compatible response format -- best free option with richest field set
- **adsb.lol API v2** (fallback): Drop-in replacement with identical response format, no current rate limits, Kubernetes-backed scalability
- **OpenSky Network REST API** (second fallback): 400 credits/day anonymous, bounding-box queries, different response format requires adapter
- **MapTiler Terrain-RGB v2**: Global elevation tiles at ~30m resolution (zoom 0-14), RGB-encoded PNG tiles decodable client-side, free tier 100K requests/month, requires free API key
- **Open-Meteo Elevation API**: Point elevation queries for discrete locations (airport labels), no API key needed, 90m resolution
- **ArcGIS World Imagery**: Satellite texture tiles, free with no API key, no documented rate limits, standard XYZ tile format
- **FAA ADDS ArcGIS Feature Service**: US Class B/C/D airspace polygon boundaries with 3D altitude data (UPPER_VAL, LOWER_VAL), GeoJSON output, updated every 8 weeks
- **OurAirports CSV dataset**: 78K+ airports (public domain, updated nightly), 12.5 MB CSV with all ICAO/IATA codes, coordinates, types -- filter to large/medium airports (~5K) for practical use
- **Canvas Texture Sprites** (THREE.js r128): Airport ground labels using existing `_renderLabelToCanvas()` pattern already in codebase, no new library needed

**Critical finding:** airplanes.live, adsb.lol, and the existing dump1090 local endpoint all share the ADSBx v2 response format -- same JSON structure, same field names. Write ONE parser and swap between providers with zero code changes.

### Expected Features

**Must have (table stakes):**
- Global flight data via API with geographic query (250nm radius around map center)
- Automatic fallback between APIs (airplanes.live -> adsb.lol -> OpenSky)
- Data source mode switch (local dump1090 vs global API) without restart
- Airport search by name/IATA/ICAO code with autocomplete
- Camera fly-to animation on airport selection
- Terrain elevation with actual 3D ground mesh (not flat plane)
- Satellite or map imagery draped on terrain
- Airspace Class B/C/D volume rendering with characteristic 3D shapes (inverted wedding cake, tiered cylinders)

**Should have (competitive differentiators):**
- Browse nearby airports list (ranked by distance/size)
- 3D ground labels for major airports (visible on terrain)
- Theme-aware terrain rendering (satellite for day, dark-tinted for night, wireframe green for retro)
- Airspace opacity and per-class toggles (B/C/D on/off individually)
- Focused radius mode (show only data within configurable radius)
- Altitude exaggeration slider (makes vertical relationships visible -- real airspace has 36:1 width-to-height ratio)
- Ground elevation offset (automatic or manual adjustment for different airport elevations)

**Defer (v2+):**
- International airspace beyond US (OpenAIP worldwide data)
- Multiple map layer selector (7+ layer options)
- Navigation aids overlay (VORs, waypoints, navaids)
- Weather radar overlay (precipitation on terrain)
- Real-time NOTAM/TFR display

**Anti-features (deliberately NOT building):**
- Full WASD fly mode (orbit controls already provide full 3D navigation)
- Recording and playback (massive memory, complex UI)
- Show ALL 78K airports with labels (performance disaster)
- Worldwide airspace data on initial load (freezes browser)

### Architecture Approach

The architecture evolves within strict constraints: single-file HTML (or multi-file with `<script src>` tags), no build tooling, vanilla JS, 30fps+ with 200+ aircraft. Every new component integrates with existing global state, the existing `animate()` loop, the existing `latLonToXZ()` coordinate system, and the existing `interpolateAircraft()` pipeline.

**Major components:**

1. **Data Source Abstraction Layer** -- Normalizes aircraft data from dump1090/airplanes.live/adsb.lol/OpenSky into common format that existing interpolation pipeline expects. Each source is an adapter. Fallback chain rotates through providers on failure.

2. **Terrain Elevation Layer** -- Fetches MapTiler Terrain-RGB tiles (PNG) using same tile grid as existing map tiles, decodes RGB to elevation values, creates PlaneGeometry meshes with vertex shader displacement (NOT CPU-side), applies satellite imagery texture. LOD: 64x64 segments near camera, 32x32 medium, 16x16 far. Shares geometry across same-LOD tiles.

3. **Airspace Volume Layer** -- Parses FAA ADDS GeoJSON (Class B/C/D polygons + floor/ceiling altitudes), converts to THREE.Shape, extrudes vertically using THREE.ExtrudeGeometry. Renders as wireframe outlines (not filled volumes) to avoid WebGL transparency sorting artifacts. Uses existing `latLonToXZ()` coordinate system.

4. **Airport Database Layer** -- Loads OurAirports CSV once (pre-filtered to medium/large airports, ~5K rows), builds in-memory search index (Map by ICAO/IATA/name), renders 3D ground labels as CanvasTexture sprites using existing `_renderLabelToCanvas()` pattern. Labels positioned on terrain surface, LOD-based visibility.

**Key patterns:**
- **Terrain tiles align with map tiles**: Same tile grid (`latLonToTile`), same lifecycle (`loadMapTiles()`), terrain meshes and map tiles perfectly aligned
- **Data source adapters**: Each source normalizes to common `{aircraft: [{hex, lat, lon, altitude, track, gs, ...}]}` format
- **Vertex shader displacement for terrain**: Load elevation as texture, let GPU sample for displacement -- avoids tainted canvas CORS issue, vastly better performance than CPU vertex manipulation
- **Airspace as wireframe outlines**: THREE.EdgesGeometry on extruded shapes, no transparency sorting issues, clean aesthetic matching existing retro/wireframe theme
- **Airport search with fly-to**: In-memory search is instant for 5K records, fly-to reuses existing `startMapTransition()` camera animation

### Critical Pitfalls

1. **Terrain Tile Memory Explosion** -- Loading Terrarium PNG tiles and converting to PlaneGeometry with displaced vertices can create 6.5 million vertices (786 KB per tile * 100 tiles). Prevention: Use LOW vertex density (32x32 or 64x64 segments max, not 256x256), use vertex shader displacement instead of CPU-side modification, implement aggressive LOD, share geometry across tiles at same LOD level, cap at 25 terrain tiles loaded simultaneously.

2. **Global Flight API Rate Limiting** -- Airplanes.live is 1 req/sec with 250nm radius. Naive tiling of global queries or carrying over dump1090's 1-second polling habit will exceed limits and get IP banned. Prevention: Use geographic queries (not "all aircraft"), implement request queue with minimum 5-10 second spacing for global mode, cache aggressively, exponential backoff on 429 responses.

3. **CORS Failures with Terrain Tile S3 Bucket** -- AWS S3 terrain tiles may not return CORS headers. Terrain tiles MUST be read as pixel data (not just displayed as textures) for elevation decoding, triggering tainted canvas error if CORS headers missing. Prevention: Test CORS FIRST before writing terrain code with `fetch('https://s3.amazonaws.com/elevation-tiles-prod/terrarium/10/163/395.png', {mode: 'cors'})`. If CORS blocked, use vertex shader displacement approach (no pixel reading needed) or switch to Nextzen tiles with API key.

4. **Single-File HTML Beyond Maintainability** -- Current file is 4,631 lines. Adding terrain (~400 lines), global API (~300 lines), airspace (~500 lines), airport search (~400 lines), labels (~200 lines) pushes to 6,500+ lines. Prevention: Split to multi-file with `<script src>` tags (NOT build tooling, just basic HTML), or establish strict section ordering with consistent comment banners, or use simple concatenation script.

5. **Airspace Transparent Volume Rendering Artifacts** -- THREE.js sorts transparent objects by center distance, not per-pixel. Overlapping Class B/C/D volumes flicker or render incorrectly depending on camera angle. Prevention: Use `depthWrite: false` on all airspace materials, set explicit `renderOrder` (Class D=1, C=2, B=3), use low opacity (0.05-0.15), OR (better) render as wireframe outlines with THREE.EdgesGeometry -- completely avoids transparency sorting.

## Implications for Roadmap

Based on research, suggested phase structure follows dependency order and risk-first approach:

### Phase 1: Data Source Abstraction
**Rationale:** Foundational -- enables global mode which enriches ALL subsequent features. No dependencies on terrain/airspace/airports. Pure refactoring of existing data fetch system.
**Delivers:** Mode switch UI (local vs global), normalized adapter for each data source (dump1090, airplanes.live, adsb.lol, OpenSky), automatic fallback chain, geographic queries around map center.
**Addresses:** Global data via API, automatic fallback (table stakes features from FEATURES.md)
**Avoids:** API rate limiting pitfall (implements 5-10s polling, request queue, exponential backoff)

### Phase 2: Airport Database + Search + Labels
**Rationale:** High-value, medium-complexity, independent of terrain/airspace. Delivers visible functionality quickly. Airport labels BENEFIT from terrain (sit on surface) but can fall back to flat plane if terrain isn't ready yet.
**Delivers:** OurAirports CSV loading (pre-filtered to 5K airports), in-memory search index (ICAO/IATA/name), autocomplete UI, camera fly-to animation (reuses existing `startMapTransition()`), 3D ground labels as canvas sprites (reuses existing `_renderLabelToCanvas()` pattern).
**Uses:** Canvas texture sprites (from STACK.md)
**Addresses:** Airport search, camera fly-to, browse nearby airports (table stakes + differentiator features)
**Avoids:** OurAirports memory pitfall (pre-filter to 5K rows, not 78K)

### Phase 3: Terrain Elevation
**Rationale:** Visually impactful, establishes ground truth that airspace volumes sit on. Significant complexity but well-researched. Must address memory pitfall from day one.
**Delivers:** MapTiler Terrain-RGB tile fetching (using existing tile grid), vertex shader displacement (NOT CPU-side), satellite imagery draping (ArcGIS World Imagery), LOD-based segment density (64/32/16), terrain mesh caching, ground elevation auto-offset.
**Uses:** MapTiler Terrain-RGB v2, ArcGIS World Imagery, Open-Meteo point elevation (from STACK.md)
**Implements:** Terrain Elevation Layer component (from ARCHITECTURE.md)
**Addresses:** Terrain elevation, satellite imagery, altitude exaggeration (table stakes features)
**Avoids:** Terrain memory explosion (vertex shader displacement, low segment counts, LOD, tile cap), CORS failures (test CORS first or use vertex shader approach)

### Phase 4: Airspace Volumes
**Rationale:** Most complex polygon rendering, benefits from terrain context (volumes look better with ground reference). Last because it depends on architecture patterns established by terrain.
**Delivers:** FAA ADDS GeoJSON fetching (Class B/C/D polygons + altitudes), THREE.Shape creation from GeoJSON polygons, THREE.ExtrudeGeometry extrusion, wireframe outline rendering (THREE.EdgesGeometry), per-class toggles (B/C/D on/off), opacity slider, spatial query by bounding box.
**Uses:** FAA ADDS ArcGIS Feature Service (from STACK.md)
**Implements:** Airspace Volume Layer component (from ARCHITECTURE.md)
**Addresses:** Airspace Class B/C/D rendering, per-class toggles, opacity control (table stakes + differentiators)
**Avoids:** Transparent volume rendering artifacts (wireframe outlines instead of filled volumes, or depthWrite:false + renderOrder if filled)

### Phase Ordering Rationale

- **Phase 1 first** because data source abstraction is foundational for ALL subsequent features (terrain/airspace/airports all work for both local and global users)
- **Phase 2 second** because airport search delivers immediate user value, is independent of terrain/airspace, and establishes patterns for CSV loading and 3D label rendering
- **Phase 3 third** because terrain is visually impactful and establishes the ground reference that airspace volumes sit on; also the most complex memory/performance challenge that must be solved correctly
- **Phase 4 last** because airspace rendering benefits from terrain context (volumes look better with ground), is the most complex polygon rendering work, and can leverage lessons learned from terrain tile management

This ordering follows the dependency graph from ARCHITECTURE.md:
```
Data Source Abstraction (no dependencies)
  |
  +---> Airport Database (depends only on coordinate system, already exists)
  |
  +---> Terrain Elevation (depends on tile grid, already exists)
          |
          +---> Airspace Volumes (benefits from terrain context)
```

### Research Flags

**Phases likely needing deeper research during planning:**
- **Phase 3 (Terrain):** MapTiler API key setup, vertex shader displacement implementation (THREE.js displacementMap specifics), LOD segment density tuning, CORS validation with actual S3 bucket
- **Phase 4 (Airspace):** FAA ADDS GeoJSON field mapping (UPPER_VAL/LOWER_VAL to feet), THREE.ExtrudeGeometry with complex polygons (holes, concave shapes), Class B shelf structures (different floor altitudes at different distances)

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Data Source):** Well-documented API endpoints (airplanes.live, adsb.lol verified via OpenAPI specs), adapter pattern is straightforward normalization
- **Phase 2 (Airports):** CSV parsing is trivial (~30 lines), in-memory search is Map-based, canvas sprite labels reuse existing `_renderLabelToCanvas()` code, fly-to animation reuses existing `startMapTransition()`

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All API endpoints verified via official docs or OpenAPI specs. Terrain tile encoding formula verified from Tilezen/joerd docs. ArcGIS World Imagery URL pattern verified from OpenLayers examples. |
| Features | MEDIUM-HIGH | Feature expectations derived from Air Loom analysis (full codebase inspection via WebFetch) and Flightradar24 3D documentation. MVP definition clear. Anti-features well-reasoned. |
| Architecture | HIGH | Existing codebase analyzed (4,631 lines). Integration patterns verified against THREE.js r128 capabilities. Data flow matches existing patterns. Build order follows clear dependency graph. |
| Pitfalls | MEDIUM-HIGH | Terrain memory explosion verified from THREE.js forum discussions (high-segment PlaneGeometry performance issues). API rate limits from official docs. CORS issues from community patterns. Transparency artifacts from THREE.js documentation. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **MapTiler API key**: Need free MapTiler Cloud account for Terrain-RGB tiles. Free tier is 100K requests/month which should be sufficient for personal use. Requires adding API key to HTML file (acceptable since it's a client-side key with domain restrictions).

- **ArcGIS World Imagery terms of service**: Usage terms for non-commercial display are assumed permissive but not explicitly verified. Need to check ESRI terms before production use. If restricted, fall back to CartoDB dark tiles (already in use) or MapTiler satellite (would consume free tier budget).

- **Vertex shader displacement specifics**: THREE.js MeshStandardMaterial.displacementMap is documented for THREE.js r128 but actual implementation with Terrarium tiles needs prototyping. May need custom shader if displacementMap doesn't work as expected.

- **FAA ADDS field mapping**: GeoJSON response fields (UPPER_VAL, LOWER_VAL, UPPER_UOM, LOWER_UOM) are documented but actual parsing and conversion to scene coordinates needs validation. Class B shelf structures (different floor altitudes) may require per-shelf extrusion rather than single volume per airspace.

- **OurAirports filtering strategy**: Pre-filtering to medium/large airports reduces 78K to ~5K rows, but threshold needs tuning. "large_airport" is ~600 worldwide (always show), "medium_airport" is ~4,500 (show when zoomed in), but exact zoom-level thresholds need user testing.

- **Single-file maintainability decision**: Current 4,631 lines growing to 6,500+ requires architectural decision BEFORE adding features. Options: (1) split to multi-file with `<script src>` tags, (2) strict section organization with comment banners, (3) simple build script (cat files). This decision should be made in Phase 0 or pre-work.

## Sources

### Primary (HIGH confidence)
- [airplanes.live API Guide](https://airplanes.live/api-guide/) -- endpoints, rate limits, ADSBx v2 format
- [adsb.lol API OpenAPI spec](https://api.adsb.lol/api/openapi.json) -- endpoint verification, ADSBx v2 compatibility
- [OpenSky Network REST API](https://openskynetwork.github.io/opensky-api/rest.html) -- bounding-box queries, 400 credits/day
- [MapTiler Terrain-RGB Docs](https://docs.maptiler.com/guides/map-tiling-hosting/data-hosting/rgb-terrain-by-maptiler/) -- encoding formula, tile URL pattern
- [Open-Meteo Elevation API](https://open-meteo.com/en/docs/elevation-api) -- point queries, batch limits, 90m resolution
- [FAA ADDS Class Airspace](https://adds-faa.opendata.arcgis.com/datasets/c6a62360338e408cb1512366ad61559e_0) -- GeoJSON fields, query patterns
- [OurAirports Data Dictionary](https://ourairports.com/help/data-dictionary.html) -- CSV format, field descriptions, 78K airports
- [THREE.js ExtrudeGeometry documentation](https://threejs.org/docs/pages/ExtrudeGeometry.html) -- extrusion API
- [Tilezen/joerd Terrarium format](https://github.com/tilezen/joerd/blob/master/docs/formats.md) -- elevation encoding formula
- Existing codebase: `/Users/mit/Documents/GitHub/airplane-tracker-3d/airplane-tracker-3d-map.html` (4,631 lines, THREE.js r128, direct inspection)

### Secondary (MEDIUM confidence)
- [Air Loom application](https://objectiveunclear.com/airloom.html) -- feature analysis via source inspection, terrain implementation patterns
- [ArcGIS World Imagery](https://www.arcgis.com/home/item.html?id=974d45be315c4c87b2ac32be59af9a0b) -- tile URL, usage terms unclear
- [THREE.js Canvas Textures Manual](https://threejs.org/manual/en/canvas-textures.html) -- canvas-to-texture approach
- [THREE.js performance best practices (Codrops 2025)](https://tympanus.net/codrops/2025/02/11/building-efficient-three-js-scenes-optimize-performance-while-maintaining-quality/) -- draw call optimization
- [THREE.js text labels discussion](https://discourse.threejs.org/t/how-to-create-lots-of-optimized-2d-text-labels/66927) -- sprite performance at scale
- [THREE.js transparent rendering issues](https://discourse.threejs.org/t/threejs-and-the-transparent-problem/11553) -- object-center sorting limitation

### Tertiary (LOW confidence)
- OpenAIP worldwide airspace data format -- needs direct API verification
- ESRI World Imagery non-commercial usage terms -- needs official verification

---
*Research completed: 2026-02-07*
*Ready for roadmap: yes*
