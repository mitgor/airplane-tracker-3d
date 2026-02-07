# Architecture Research

**Domain:** Multi-source 3D flight tracker with terrain, airspace, and airport features
**Researched:** 2026-02-07
**Confidence:** HIGH (based on existing codebase analysis + verified external documentation)

## Existing Architecture Baseline

The current system is a 4,631-line single-file HTML application with procedural JavaScript and THREE.js r128. It already has six implicit layers: UI/DOM, 3D Rendering, Data Fetch/Interpolation, Aircraft Management, Map Tiles, and Statistics. The architecture must evolve within these constraints: single-file HTML, no build tooling, vanilla JS, 30fps+ with 200+ aircraft.

The critical insight: this is NOT a greenfield design. Every new component must integrate with existing global state, the existing `animate()` loop, the existing `latLonToXZ()` coordinate system, and the existing `interpolateAircraft()` pipeline. The architecture below describes how new components plug into what already exists.

## System Overview

```
+-------------------------------------------------------------------+
|                        UI / DOM Layer                               |
|  [Info Panel] [Controls] [Airport Search] [Data Source Selector]   |
+-------------------------------------------------------------------+
        |              |              |               |
+-------------------------------------------------------------------+
|                    Application Controller                          |
|  init() -> animate() -> interpolateAircraft() -> render()          |
+-------------------------------------------------------------------+
        |              |              |               |
+-------+------+-------+------+------+-------+-------+------+
|              |              |              |              |
| Data Source  | Aircraft     | Terrain      | Airspace     | Airport
| Abstraction  | Management   | Elevation    | Volume       | Database
| Layer        | Layer        | Layer        | Layer        | Layer
|              |              |              |              |
| [dump1090]   | [Create]     | [Tile Fetch] | [GeoJSON]    | [CSV Load]
| [adsb.lol]   | [Interpolate]| [Heightmap]  | [Extrude]    | [Search]
| [adsb.fi]    | [Trail]      | [Mesh Gen]   | [Render]     | [Labels]
| [Fallback]   | [LOD]        | [Cache]      | [Cache]      | [Fly-to]
+--------------+--------------+--------------+--------------+----------+
        |              |              |               |
+-------------------------------------------------------------------+
|                    THREE.js Scene Graph                             |
|  [Camera] [Lights] [Map Tiles] [Terrain Meshes] [Aircraft Groups] |
|  [Airspace Volumes] [Airport Labels] [Trails] [Altitude Lines]    |
+-------------------------------------------------------------------+
        |
+-------------------------------------------------------------------+
|                    WebGL Renderer (r128)                            |
+-------------------------------------------------------------------+
```

### Component Responsibilities

| Component | Responsibility | Communicates With | Typical Implementation |
|-----------|----------------|-------------------|------------------------|
| Data Source Abstraction | Normalize aircraft data from multiple sources into common format | Aircraft Management, UI (source selector) | Object with `fetch()` method returning normalized `{aircraft: [...]}` |
| Aircraft Management | Create/update/remove aircraft 3D objects, interpolation | Data Source, Scene Graph, Trails, Labels | Existing `interpolateAircraft()` + `createAirplane()` extended |
| Terrain Elevation | Fetch elevation tiles, decode heightmaps, create terrain meshes | Scene Graph, Map Tile coordinates | PlaneGeometry with vertex displacement from decoded PNG |
| Airspace Volumes | Parse airspace GeoJSON, create extruded 3D volumes | Scene Graph, coordinate system (`latLonToXZ`) | THREE.ExtrudeGeometry from THREE.Shape, transparent materials |
| Airport Database | Load airport CSV, search/filter, render 3D labels | Scene Graph, coordinate system, UI (search panel) | In-memory array with index for search, CanvasTexture labels |
| Map Tiles (existing) | Load/cache/render slippy map tiles on ground plane | Scene Graph, coordinate system | Already implemented, no changes needed |
| UI/DOM | Settings panels, search inputs, data source toggle | All components via global state | HTML elements + event handlers |

## Recommended Project Structure (Single-File Sections)

Since this must remain a single HTML file, the "structure" is organized as clearly delimited code sections with comment banners. This is the recommended ordering within the `<script>` tag:

```
<script>
// =============================================
// SECTION 1: CONFIGURATION & CONSTANTS
// =============================================
// DATA_URL, REFRESH_INTERVAL, terrain tile URLs, etc.

// =============================================
// SECTION 2: DATA SOURCE ABSTRACTION
// =============================================
// DataSource object: { mode, fetch, normalize, setMode }
// dump1090 adapter, adsb.lol adapter, fallback chain

// =============================================
// SECTION 3: STATE & GLOBALS
// =============================================
// All global state variables (existing + new)

// =============================================
// SECTION 4: SETTINGS PERSISTENCE
// =============================================
// Cookie helpers, load/save settings

// =============================================
// SECTION 5: STATISTICS & INDEXEDDB
// =============================================
// Stats database, graphs, history

// =============================================
// SECTION 6: THREE.js INITIALIZATION
// =============================================
// init(), scene, camera, renderer, lights, geometries

// =============================================
// SECTION 7: MAP TILES (existing)
// =============================================
// Tile loading, caching, preloading, zoom/pan

// =============================================
// SECTION 8: TERRAIN ELEVATION (new)
// =============================================
// Terrain tile fetching, heightmap decoding, mesh generation

// =============================================
// SECTION 9: AIRSPACE VOLUMES (new)
// =============================================
// GeoJSON parsing, Shape creation, ExtrudeGeometry

// =============================================
// SECTION 10: AIRPORT DATABASE (new)
// =============================================
// CSV loading, search index, 3D labels, fly-to

// =============================================
// SECTION 11: AIRCRAFT MANAGEMENT
// =============================================
// createAirplane(), interpolation, trails, labels

// =============================================
// SECTION 12: CAMERA & CONTROLS
// =============================================
// Camera positioning, keyboard, mouse, touch

// =============================================
// SECTION 13: ANIMATION LOOP
// =============================================
// animate(), render scheduling, LOD updates

// =============================================
// SECTION 14: UI INTERACTIONS
// =============================================
// Panel updates, selection, enrichment, follow mode
</script>
```

### Structure Rationale

- **Data Source Abstraction early:** Must be available before `fetchData()` is called in `init()`
- **Terrain/Airspace/Airports after Map Tiles:** They depend on the same coordinate system and map bounds
- **Aircraft Management after geographic layers:** Aircraft altitude lines and trails interact with terrain
- **Animation loop near the end:** It calls into everything above

## Architectural Patterns

### Pattern 1: Data Source Adapter with Fallback Chain

**What:** A single `DataSource` object that abstracts the difference between local dump1090 and global APIs. Each source is an adapter that normalizes output to the existing `{aircraft: [{hex, lat, lon, altitude, track, gs, flight, squawk, ...}]}` format that `interpolateAircraft()` already expects.

**When to use:** This is the core pattern that enables the mode switch. Use it for ALL aircraft data fetching.

**Trade-offs:** Adds a normalization step to every fetch cycle (negligible overhead for 200 aircraft). The benefit is that the entire downstream pipeline (interpolation, rendering, trails) works identically regardless of data source.

**Example:**
```javascript
const DataSource = {
    mode: 'local',  // 'local' or 'global'
    globalProviders: [
        {
            name: 'adsb.lol',
            url: (lat, lon, radius) =>
                `https://api.adsb.lol/v2/lat/${lat}/lon/${lon}/dist/${radius}`,
            normalize: (data) => ({
                aircraft: (data.ac || []).map(ac => ({
                    hex: ac.hex,
                    flight: ac.flight || '',
                    lat: ac.lat,
                    lon: ac.lon,
                    altitude: ac.alt_baro === 'ground' ? 0 : (ac.alt_baro || ac.alt_geom || 0),
                    track: ac.track || 0,
                    gs: ac.gs || 0,
                    baro_rate: ac.baro_rate || ac.geom_rate || 0,
                    squawk: ac.squawk || ''
                }))
            }),
            available: null  // null = untested, true/false after probe
        },
        // Additional providers follow same interface
    ],
    currentProviderIndex: 0,

    async fetch(centerLat, centerLon) {
        if (this.mode === 'local') {
            return this.fetchLocal();
        }
        return this.fetchGlobalWithFallback(centerLat, centerLon);
    },

    async fetchLocal() {
        const response = await fetch(DATA_URL);
        return response.json();  // dump1090 format is already the native format
    },

    async fetchGlobalWithFallback(lat, lon) {
        for (let i = 0; i < this.globalProviders.length; i++) {
            const idx = (this.currentProviderIndex + i) % this.globalProviders.length;
            const provider = this.globalProviders[idx];
            try {
                const response = await fetch(provider.url(lat, lon, 250));
                if (response.ok) {
                    const data = await response.json();
                    this.currentProviderIndex = idx;
                    return provider.normalize(data);
                }
            } catch (e) {
                provider.available = false;
            }
        }
        return { aircraft: [] };  // All providers failed
    }
};
```

**Confidence:** HIGH -- The adsb.lol API v2 endpoint `/v2/lat/{lat}/lon/{lon}/dist/{radius}` is verified from their OpenAPI spec. The response format uses `ac` array with fields matching readsb documentation (hex, flight, lat, lon, alt_baro, gs, track, baro_rate, squawk). The normalization step maps these to the existing field names that `interpolateAircraft()` already consumes.

### Pattern 2: Terrain Tile Grid Aligned with Map Tiles

**What:** Terrain elevation meshes use the exact same tile grid as the existing map tiles. For each visible map tile, a corresponding terrain mesh is generated from an elevation tile PNG. The terrain mesh is a PlaneGeometry with vertex Y positions displaced according to decoded elevation values.

**When to use:** Terrain rendering is toggled globally. When enabled, terrain meshes replace the flat tile planes.

**Trade-offs:**
- PRO: Reuses existing tile coordinate math (`latLonToTile`, `tileToLatLon`, `mapBounds`)
- PRO: Terrain and map tiles are perfectly aligned since they use the same grid
- CON: At TILES_PER_SIDE=10, thats 100 terrain meshes each with segments -- need to keep segment count low (32x32 per tile = 102,400 vertices total, acceptable for GPU)
- CON: Elevation data requires additional HTTP requests (one per tile)

**Elevation Data Source:** AWS Terrain Tiles (Terrarium format), freely available on S3 without authentication.

- URL pattern: `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png`
- Decoding: `elevation = (R * 256 + G + B / 256) - 32768` (meters)
- Zoom levels 0-15 available; use same zoom as map tiles (typically 6-12)
- Tile size: 256x256 pixels

**Confidence:** HIGH for Terrarium format and decoding formula (verified from tilezen/joerd documentation). MEDIUM for the exact S3 URL pattern (from multiple web sources, but not directly fetched from AWS docs).

**Example:**
```javascript
async function loadTerrainTile(tileX, tileY, zoom) {
    const url = `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/${zoom}/${tileX}/${tileY}.png`;
    const img = new Image();
    img.crossOrigin = 'anonymous';

    return new Promise((resolve) => {
        img.onload = () => {
            const canvas = document.createElement('canvas');
            canvas.width = canvas.height = 256;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(img, 0, 0);
            const imageData = ctx.getImageData(0, 0, 256, 256);
            const elevations = new Float32Array(256 * 256);

            for (let i = 0; i < imageData.data.length; i += 4) {
                const r = imageData.data[i];
                const g = imageData.data[i + 1];
                const b = imageData.data[i + 2];
                elevations[i / 4] = (r * 256 + g + b / 256) - 32768;
            }
            resolve(elevations);
        };
        img.onerror = () => resolve(null);  // Graceful fallback
        img.src = url;
    });
}

function createTerrainMesh(elevations, tileSize, terrainScale) {
    const segments = 32;  // 32x32 grid per tile
    const geometry = new THREE.PlaneGeometry(tileSize, tileSize, segments, segments);
    const positions = geometry.attributes.position.array;

    // Sample elevation data at grid points
    for (let iy = 0; iy <= segments; iy++) {
        for (let ix = 0; ix <= segments; ix++) {
            const vertexIndex = (iy * (segments + 1) + ix) * 3;
            // Sample from 256x256 elevation data at corresponding position
            const ex = Math.floor(ix / segments * 255);
            const ey = Math.floor(iy / segments * 255);
            const elevation = elevations[ey * 256 + ex];
            positions[vertexIndex + 2] = elevation * terrainScale;
        }
    }
    geometry.computeVertexNormals();
    return geometry;
}
```

### Pattern 3: Airspace Volumes via ExtrudeGeometry

**What:** Airspace boundaries (Class B, C, D) are 2D polygons with floor and ceiling altitudes. These are rendered as semi-transparent extruded volumes using THREE.ExtrudeGeometry. The 2D shape comes from GeoJSON polygon coordinates, extruded vertically between floor and ceiling altitudes.

**When to use:** Toggled as a layer. Rendered once when map bounds change, not every frame.

**Trade-offs:**
- PRO: THREE.ExtrudeGeometry handles complex polygon shapes with holes
- PRO: Transparent materials with depth write disabled look good for overlapping volumes
- CON: Complex polygon shapes can produce many triangles; keep to major airspace only
- CON: GeoJSON source must be pre-loaded or fetched per region

**Data Source:** OpenAIP provides airspace data in GeoJSON format, downloadable by country. For a single-file app, the recommended approach is to load from OpenAIP's GeoJSON API or embed a curated subset.

**Confidence:** HIGH for THREE.ExtrudeGeometry approach (verified from THREE.js docs). MEDIUM for OpenAIP data format specifics (from their website and GitHub; exact API endpoint structure needs validation during implementation).

**Example:**
```javascript
function createAirspaceVolume(polygonCoords, floorFt, ceilingFt) {
    const shape = new THREE.Shape();
    polygonCoords.forEach((coord, i) => {
        const pos = latLonToXZ(coord[1], coord[0]);
        if (i === 0) shape.moveTo(pos.x, pos.z);
        else shape.lineTo(pos.x, pos.z);
    });
    shape.closePath();

    const height = (ceilingFt - floorFt) * altitudeScale;
    const geometry = new THREE.ExtrudeGeometry(shape, {
        depth: height,
        bevelEnabled: false
    });

    const material = new THREE.MeshBasicMaterial({
        color: 0x4488ff,
        transparent: true,
        opacity: 0.15,
        side: THREE.DoubleSide,
        depthWrite: false
    });

    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.y = floorFt * altitudeScale;
    return mesh;
}
```

### Pattern 4: Airport Database with In-Memory Search Index

**What:** OurAirports CSV data (78K+ airports) is loaded once, parsed into a typed array, and indexed for fast search by name, IATA code, ICAO code, and geographic proximity. Only airports above a type threshold (medium_airport and above) get 3D labels rendered as CanvasTexture sprites.

**When to use:** Airport search is always available once data loads. 3D labels are rendered based on current map bounds and zoom level.

**Trade-offs:**
- PRO: OurAirports CSV is ~12.5MB but compresses well with gzip (likely ~2MB); loads once
- PRO: In-memory search is instant for 78K records
- CON: 12.5MB is significant for initial page load; must load asynchronously
- CON: Must carefully limit rendered labels (max ~50 visible at once) to avoid draw call explosion

**Data Source:** `https://davidmegginson.github.io/ourairports-data/airports.csv` (public domain, updated nightly)

**Confidence:** HIGH -- OurAirports data format and download URL verified from official GitHub repository and website.

**Example:**
```javascript
const AirportDB = {
    airports: [],      // Full parsed dataset
    byICAO: new Map(), // ICAO code index
    byIATA: new Map(), // IATA code index

    async load() {
        const response = await fetch(
            'https://davidmegginson.github.io/ourairports-data/airports.csv'
        );
        const text = await response.text();
        this.airports = this.parseCSV(text);
        this.airports.forEach(a => {
            if (a.icao) this.byICAO.set(a.icao, a);
            if (a.iata) this.byIATA.set(a.iata, a);
        });
    },

    search(query, limit = 20) {
        const q = query.toUpperCase();
        // Exact IATA/ICAO match first
        if (q.length <= 4) {
            const exact = this.byIATA.get(q) || this.byICAO.get(q);
            if (exact) return [exact];
        }
        // Fuzzy name search
        return this.airports
            .filter(a => a.name.toUpperCase().includes(q) ||
                         a.municipality.toUpperCase().includes(q))
            .slice(0, limit);
    },

    nearby(lat, lon, radiusKm = 100, limit = 20) {
        return this.airports
            .filter(a => a.type !== 'small_airport' && a.type !== 'closed')
            .map(a => ({ ...a, dist: haversine(lat, lon, a.lat, a.lon) }))
            .filter(a => a.dist <= radiusKm)
            .sort((a, b) => a.dist - b.dist)
            .slice(0, limit);
    }
};
```

## Data Flow

### Aircraft Data Flow (Updated with Data Source Abstraction)

```
[User selects mode: local/global]
    |
    v
[DataSource.fetch(centerLat, centerLon)]
    |
    +--[local]--> fetch('/dump1090/data/aircraft.json')
    |                 |
    +--[global]-> fetch('https://api.adsb.lol/v2/lat/.../lon/.../dist/250')
    |                 |
    |            [normalize to common format]
    |                 |
    v                 v
[Common format: {aircraft: [{hex, lat, lon, altitude, track, gs, ...}]}]
    |
    v
[aircraftDataBuffer: Map<hex, [{timestamp, data}]>]
    |
    v  (30fps)
[interpolateAircraft()]
    |
    +-> [Create new aircraft] -> createAirplane() -> scene.add()
    +-> [Update existing]     -> position, rotation, color, trail
    +-> [Remove stale]        -> scene.remove()
    |
    v
[animate() loop]
    |
    +-> [Update lights, rotors, labels]
    +-> [Update terrain visibility]
    +-> [Update airspace visibility]
    +-> [renderer.render(scene, camera)]
```

### Terrain Data Flow

```
[Map bounds change (pan/zoom)]
    |
    v
[loadMapTiles() called]  (existing)
    |
    v  (in parallel)
[loadTerrainTiles()]  (new)
    |
    v
[For each visible tile (tileX, tileY, zoom):]
    |
    +-> [Check terrainTileCache]
    |       |
    |       +--[hit]--> Use cached terrain mesh
    |       |
    |       +--[miss]--> Fetch elevation PNG from AWS S3
    |                       |
    |                       v
    |                   [Decode Terrarium: (R*256 + G + B/256) - 32768]
    |                       |
    |                       v
    |                   [Create PlaneGeometry with displaced vertices]
    |                       |
    |                       v
    |                   [Apply map tile texture to terrain mesh]
    |                       |
    |                       v
    |                   [Cache terrain mesh and add to scene]
    |
    v
[Terrain meshes aligned with map tile grid]
    |
    v
[Aircraft Y position = max(terrainElevation, barometric altitude) * altitudeScale]
```

### Airport Search Flow

```
[App init]
    |
    v
[AirportDB.load()] --> fetch airports.csv --> parse CSV --> build indices
    |
    v  (on user typing in search box)
[AirportDB.search(query)]
    |
    v
[Display results in autocomplete dropdown]
    |
    v  (on selection)
[Camera fly-to animation]
    |
    +-> [startMapTransition(airport.lat, airport.lon, targetZoom)]
    +-> [Show airport detail panel]
    +-> [Highlight airport label in scene]
```

### Key Data Flows Summary

1. **Aircraft rendering cycle:** DataSource.fetch -> buffer -> interpolate -> render (30fps)
2. **Terrain loading:** Map bounds change -> parallel fetch elevation PNGs -> decode -> displace vertices -> cache
3. **Airspace loading:** Region change -> fetch GeoJSON -> parse polygons -> ExtrudeGeometry -> scene
4. **Airport search:** User types -> in-memory search -> display results -> fly-to on select

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 0-100 aircraft | Current architecture works fine. Terrain at 32x32 segments per tile. All airports loaded in memory. |
| 100-300 aircraft | Trail batching critical (already implemented). Limit terrain to 64 visible tiles. Airport labels capped at 30 visible. |
| 300+ aircraft | Must implement aircraft instancing (InstancedMesh). Reduce terrain segments to 16x16. Consider frustum culling for airspace volumes. |

### Scaling Priorities

1. **First bottleneck: Draw calls.** Each aircraft is currently a THREE.Group with multiple children (fuselage, wings, tail, engine, lights, glow). At 200 aircraft, that can exceed 1000 draw calls. Adding terrain meshes (100 tiles) and airspace volumes (10-20) pushes this further. Mitigation: keep terrain segment count low, merge airspace volumes where possible, consider InstancedMesh for aircraft in a future phase.

2. **Second bottleneck: Texture memory.** 100 map tiles + 100 terrain elevation textures + airport label textures can consume significant GPU memory. Mitigation: share map tile texture between flat tile and terrain mesh (same texture, just different geometry). Terrain elevation data can be discarded after vertex displacement (only the mesh is kept, not the texture). Use canvas pooling for airport labels.

3. **Third bottleneck: Network.** Global mode fetches aircraft data every second from adsb.lol. If response contains 500+ aircraft at 250nm radius, each response could be 200KB+. Terrain tiles are ~50KB each. Mitigation: reduce global fetch radius for dense areas, cache terrain tiles aggressively (elevation data rarely changes), lazy-load airport CSV.

## Anti-Patterns

### Anti-Pattern 1: Separate Scene Graphs for Each Layer

**What people do:** Create separate THREE.Scene instances for terrain, airspace, and aircraft, then composite them.
**Why it's wrong:** Multiple render passes kill performance. Depth testing between scenes is impossible (aircraft would not properly occlude behind terrain). The existing single-scene architecture is correct.
**Do this instead:** Add all objects to the existing single `scene` variable. Use `renderOrder` and `depthWrite` properties to control draw order for transparent airspace volumes.

### Anti-Pattern 2: Loading Full Airport Database Before App Starts

**What people do:** Block application startup until all 78K airports are loaded and parsed.
**Why it's wrong:** 12.5MB CSV download delays first paint significantly. Users expect to see aircraft immediately.
**Do this instead:** Load airport data asynchronously after the main app is initialized and rendering. Show a loading indicator in the search box ("Loading airports..."). Aircraft tracking works immediately while airports load in the background.

### Anti-Pattern 3: Rebuilding Terrain Meshes Every Frame

**What people do:** Recreate terrain geometry in the animation loop.
**Why it's wrong:** Geometry creation is expensive. 100 PlaneGeometries with 32x32 segments created 60 times per second would destroy performance.
**Do this instead:** Create terrain meshes once when map bounds change (same lifecycle as map tiles). Cache them. Only update when zoom/pan triggers a new `loadMapTiles()` call.

### Anti-Pattern 4: Fetching Global Data Without Geographic Bounds

**What people do:** Fetch ALL global aircraft and filter client-side.
**Why it's wrong:** adsb.lol tracks 20,000+ aircraft globally. Downloading all of them every second is wasteful and slow. Client-side filtering wastes bandwidth and CPU.
**Do this instead:** Use the geographic API endpoint: `/v2/lat/{lat}/lon/{lon}/dist/{radius}`. The radius parameter limits results to aircraft near the current map center. Adjust radius based on zoom level.

### Anti-Pattern 5: Using THREE.TextGeometry for Airport Labels

**What people do:** Create 3D extruded text meshes for each airport label.
**Why it's wrong:** TextGeometry requires loading a font file, produces heavy geometry (hundreds of triangles per character), and 50+ labels would create massive draw call overhead.
**Do this instead:** Use CanvasTexture sprites (the existing pattern for aircraft labels). Render text to a 2D canvas, create a texture, apply to a Sprite. This is one draw call per label with minimal geometry. The app already does this for aircraft labels.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| dump1090 | HTTP polling every 1s, JSON response | Existing. No changes needed, wrapped by adapter. |
| adsb.lol API v2 | HTTP GET with lat/lon/radius params | New. Geographic endpoint returns readsb-compatible JSON. No auth required. No rate limits currently. |
| AWS S3 Terrain Tiles | HTTP GET for PNG tiles, Terrarium encoding | New. Free, no auth. Same tile coordinate system as map tiles. |
| OpenAIP | GeoJSON download by country/region | New. Free data, may require periodic re-download. Consider embedding curated subset. |
| OurAirports | CSV download, one-time load | New. ~12.5MB, public domain. Cached after first load. |
| hexdb.io | Existing enrichment API | No changes. Already wrapped with availability check and caching. |
| adsbdb.com | Existing route lookup API | No changes. Already has fallback chain. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| DataSource <-> Interpolation | DataSource returns normalized JSON; interpolation consumes it unchanged | DataSource must match existing aircraft.json field names exactly |
| Terrain <-> Map Tiles | Share tile coordinate system (`latLonToTile`) and lifecycle (`loadMapTiles`) | Terrain meshes should be created in the same loop as map tile meshes |
| Airspace <-> Coordinate System | Airspace uses `latLonToXZ()` and `altitudeScale` for positioning | Must update airspace positions when `altitudeScale` slider changes |
| Airport Labels <-> Scene | Labels are Sprites added/removed based on map bounds | Same lifecycle as map tiles; recalculate on pan/zoom |
| Airport Search <-> Camera | Search results trigger `startMapTransition()` for fly-to | Reuse existing transition system; no new camera code needed |

## Build Order (Dependency Analysis)

The components have clear dependency ordering:

```
Phase 1: Data Source Abstraction
    |
    +--- No dependencies on other new components
    |    Depends only on: existing fetchData(), existing interpolation
    |    Unblocks: global mode, which enriches ALL subsequent features
    |
Phase 2: Airport Database + Search + Labels
    |
    +--- Depends on: coordinate system (existing), latLonToXZ (existing)
    |    No dependency on terrain or airspace
    |    Delivers visible value quickly (search + labels)
    |
Phase 3: Terrain Elevation
    |
    +--- Depends on: map tile coordinate system (existing), loadMapTiles lifecycle
    |    No dependency on airspace or airports
    |    Significant visual impact
    |
Phase 4: Airspace Volumes
    |
    +--- Depends on: coordinate system, altitudeScale (existing)
    |    Benefits from terrain (volumes look better with terrain context)
    |    Most complex polygon rendering
```

**Rationale for this order:**
1. Data Source Abstraction is foundational -- it enables global mode, which means all subsequent features work for both local and global users
2. Airport Database is high-value, medium-complexity, and independent of terrain/airspace
3. Terrain is visually impactful and establishes the ground truth that airspace volumes sit on
4. Airspace is last because it benefits from terrain context and is the most complex rendering

## Sources

- [adsb.lol API OpenAPI spec](https://api.adsb.lol/docs) -- Endpoint paths and parameters verified
- [readsb JSON field specification](https://github.com/wiedehopf/readsb/blob/dev/README-json.md) -- Aircraft data fields verified
- [Tilezen/joerd Terrarium format](https://github.com/tilezen/joerd/blob/master/docs/formats.md) -- Elevation encoding formula verified
- [AWS Terrain Tiles registry](https://registry.opendata.aws/terrain-tiles/) -- S3 bucket availability verified
- [OurAirports data downloads](https://ourairports.com/data/) -- CSV format and download URL verified
- [OurAirports GitHub repository](https://github.com/davidmegginson/ourairports-data) -- Data fields and update frequency verified
- [THREE.js ExtrudeGeometry documentation](https://threejs.org/docs/pages/ExtrudeGeometry.html) -- API verified
- [OpenAIP airspace data](https://www.openaip.net/data/airspaces) -- GeoJSON availability confirmed
- [Mapbox Terrain-RGB specification](https://docs.mapbox.com/data/tilesets/reference/mapbox-terrain-rgb-v1/) -- Alternative encoding reference
- [Three.js performance best practices (Codrops 2025)](https://tympanus.net/codrops/2025/02/11/building-efficient-three-js-scenes-optimize-performance-while-maintaining-quality/) -- Draw call optimization patterns
- [100 Three.js Best Practices (2026)](https://www.utsubo.com/blog/threejs-best-practices-100-tips) -- Performance patterns verified
- Existing codebase analysis: `/Users/mit/Documents/GitHub/airplane-tracker-3d/airplane-tracker-3d-map.html` (4,631 lines)

---
*Architecture research for: Multi-source 3D flight tracker with terrain, airspace, and airport features*
*Researched: 2026-02-07*
