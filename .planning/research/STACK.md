# Stack Research

**Domain:** 3D Flight Tracker -- Global Data, Terrain, Airspace, Airport Search
**Researched:** 2026-02-07
**Confidence:** MEDIUM-HIGH (APIs verified via official docs; terrain approach verified via community patterns)

---

## Recommended Stack

This stack extends the existing single-file HTML + THREE.js r128 + vanilla JS application. No build tooling. All additions are CDN-free APIs consumed via `fetch()` or static data embedded/loaded at runtime.

### Global Flight Data APIs

All three APIs below share the **ADSBExchange v2 response format** -- same JSON structure, same field names. This is the critical finding: you can write ONE parser and swap between providers with zero code changes.

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| **airplanes.live** | v2 | Primary global aircraft data | Best free option: no auth, 250nm radius queries, 1 req/sec rate limit, richest field set. Community-run with strong uptime. Drop-in ADSBx v2 format. | HIGH |
| **adsb.lol** | v2 | First fallback | ADSBx v2 compatible (drop-in replacement). Currently no rate limits. Free for everyone. Runs on Kubernetes so horizontally scalable. | HIGH |
| **OpenSky Network** | 1.4.0 | Second fallback (different format) | 400 credits/day anonymous (no auth needed for basic use). Bounding-box queries. Different response format requires adapter. Established academic project with reliable infrastructure. | HIGH |

**Primary endpoint pattern (airplanes.live):**
```
GET https://api.airplanes.live/v2/point/{lat}/{lon}/{radius}
```
- `radius`: up to 250 nautical miles
- Rate limit: 1 request per second
- No authentication required
- Response: `{ "ac": [...], "msg": "", "now": timestamp, "total": count }`

**First fallback (adsb.lol) -- identical format:**
```
GET https://api.adsb.lol/v2/point/{lat}/{lon}/{radius}
```
- `radius`: up to 250 nautical miles
- Currently no rate limits (future: API key from feeding)
- No authentication required
- Response: Same ADSBx v2 format as airplanes.live

**Second fallback (OpenSky) -- different format, needs adapter:**
```
GET https://opensky-network.org/api/states/all?lamin={lat1}&lomin={lon1}&lamax={lat2}&lomax={lon2}
```
- Bounding box query (not radius), up to 400 sq degrees
- Anonymous: 400 credits/day, 10s resolution, current data only
- Response: `{ "time": timestamp, "states": [[icao24, callsign, ...], ...] }` (array of arrays, not objects)

**Key ADSBx v2 response fields (shared by airplanes.live and adsb.lol):**

| Field | Type | Description |
|-------|------|-------------|
| `hex` | string | 24-bit ICAO identifier (6 hex digits) |
| `flight` | string | Callsign (8 chars) |
| `lat` / `lon` | number | Position in decimal degrees |
| `alt_baro` | number/string | Barometric altitude in feet, or `"ground"` |
| `alt_geom` | number | Geometric altitude in feet |
| `gs` | number | Ground speed in knots |
| `track` | number | True track (0-359 degrees) |
| `baro_rate` | number | Vertical rate in ft/min |
| `squawk` | string | Transponder squawk code |
| `category` | string | Emitter category (A0-D7) |
| `r` | string | Registration from database |
| `t` | string | Aircraft type from database |
| `seen` | number | Seconds since last message |
| `seen_pos` | number | Seconds since last position update |
| `emergency` | string | Emergency status |

### Terrain Elevation

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| **MapTiler Terrain-RGB v2** | v2 | Elevation tile source for 3D terrain mesh | Global coverage at ~30m resolution, zoom 0-14. RGB-encoded PNG tiles decodable client-side. Free tier: 5,000 sessions/month + 100,000 requests/month. Requires free API key (non-commercial). Standard format used by MapLibre/Mapbox ecosystem. | HIGH |
| **Open-Meteo Elevation API** | v1 | Point elevation queries (airport labels, spot checks) | No API key needed. Free for non-commercial. Up to 100 coords per request. 90m resolution (Copernicus DEM GLO-90). Simpler than tiles for discrete points. | HIGH |

**MapTiler Terrain-RGB tile URL:**
```
GET https://api.maptiler.com/tiles/terrain-rgb-v2/{z}/{x}/{y}.webp?key={API_KEY}
```

**Elevation decoding formula (MapTiler Terrain-RGB):**
```javascript
elevation_meters = -10000 + ((R * 256 * 256 + G * 256 + B) * 0.1)
```
- Zoom levels: 0-14 (zoom 12 is good balance of detail vs. tile count)
- Tile format: PNG or WebP
- Free tier: 5,000 map sessions + 100,000 tile requests per month
- Requires: Free MapTiler Cloud account + API key
- Restriction: Non-commercial on free tier; MapTiler logo required

**Open-Meteo Elevation API (for point queries):**
```
GET https://api.open-meteo.com/v1/elevation?latitude=52.52,48.85&longitude=13.41,2.35
```
- Response: `{ "elevation": [38.0, 35.0] }`
- Batch: Up to 100 coordinates per request
- No API key needed
- Resolution: ~90m (Copernicus DEM GLO-90)
- Fair use: under 10,000 requests/day

**THREE.js terrain mesh approach (verified via community patterns):**
1. Create `PlaneGeometry` with sufficient segments (e.g., 128x128)
2. Load terrain-RGB tile as texture via `TextureLoader`
3. Draw tile to offscreen canvas, read pixel data with `getImageData()`
4. Decode each pixel's RGB to elevation using the formula above
5. Set vertex Z positions on the PlaneGeometry from decoded elevations
6. Apply satellite imagery texture as the material map
7. Call `geometry.computeVertexNormals()` for proper shading

### Satellite Imagery (Terrain Texture)

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| **ArcGIS World Imagery** | N/A | Satellite imagery texture for terrain mesh | Free, no API key, no authentication. Global coverage at multiple zoom levels (0.3m metro, 0.5m US, 1m worldwide). Standard XYZ tile format. No usage limits documented for reasonable use. | MEDIUM |

**ArcGIS World Imagery tile URL:**
```
GET https://services.arcgisonline.com/arcgis/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}
```
- No API key required
- No documented rate limit (reasonable use expected)
- Note: `{z}/{y}/{x}` order (y before x) -- different from OSM's `{z}/{x}/{y}`
- High-resolution satellite imagery globally

**Why not MapTiler satellite?** Free tier limit (100K requests) would be consumed by both terrain-RGB tiles AND satellite tiles. Using ArcGIS for satellite preserves the MapTiler budget for terrain-RGB only.

### Airspace Volume Data

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| **FAA ADDS ArcGIS Feature Service** | Current (Jan 22 - Mar 19, 2026 cycle) | US Class B/C/D airspace polygon boundaries with altitude floors/ceilings | Official FAA data. Free, no auth. GeoJSON output via REST query. 6,050 features. Includes 3D altitude data (UPPER_VAL, LOWER_VAL). Updated every 8 weeks. Polygon geometry with Z-values. | HIGH |

**FAA Feature Service base URL:**
```
https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services/Class_Airspace/FeatureServer/0
```

**Query endpoint (GeoJSON):**
```
GET {base}/query?where=CLASS+IN+('B','C','D')&outFields=NAME,CLASS,LOCAL_TYPE,UPPER_VAL,LOWER_VAL,UPPER_UOM,LOWER_UOM,ICAO_ID&f=geojson&resultRecordCount=2000
```

**Key fields in response:**

| Field | Type | Description |
|-------|------|-------------|
| `NAME` | string | e.g., "BOSTON CLASS B" |
| `CLASS` | string | "B", "C", or "D" |
| `LOCAL_TYPE` | string | "CLASS_B", "CLASS_C", "CLASS_D" |
| `UPPER_VAL` | number | Ceiling altitude |
| `LOWER_VAL` | number | Floor altitude |
| `UPPER_UOM` | string | Unit ("FT", "FL") |
| `LOWER_UOM` | string | Unit ("FT", "FL") |
| `ICAO_ID` | string | Airport ICAO code |
| `geometry` | Polygon | GeoJSON polygon coordinates |

**Spatial query (by bounding box):**
```
GET {base}/query?where=CLASS+IN+('B','C','D')&geometry={xmin},{ymin},{xmax},{ymax}&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects&outFields=*&f=geojson
```

**Max records per query:** 2,000 (paginate with `resultOffset` for full dataset)

**For worldwide airspace (non-US):**

| Technology | Purpose | Why Considered | Confidence |
|------------|---------|----------------|------------|
| **OpenAIP** | Worldwide airspace boundaries | Community-driven, global coverage. Requires free API key. REST API at `api.core.openaip.net`. Covers all ICAO classes. | LOW |

OpenAIP requires authentication and the API documentation is less clear. For the initial implementation, recommend US-only airspace via FAA ADDS, with OpenAIP as a future extension.

### Airport Data

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| **OurAirports Dataset** | Updated nightly (Feb 6, 2026) | Airport search database: names, ICAO/IATA codes, coordinates, types | Public domain. 12.5 MB CSV with every airport worldwide. Updated daily on GitHub. Filterable by type (large_airport, medium_airport). Has lat/lon, elevation, municipality, all search-relevant fields. Well-documented data dictionary. | HIGH |

**Download URL:**
```
https://davidmegginson.github.io/ourairports-data/airports.csv
```

**Key fields for this project:**

| Field | Type | Values/Description |
|-------|------|--------------------|
| `type` | string | `large_airport`, `medium_airport`, `small_airport`, `heliport`, `seaplane_base`, `closed` |
| `name` | string | Official airport name |
| `latitude_deg` | decimal | WGS84 latitude |
| `longitude_deg` | decimal | WGS84 longitude |
| `elevation_ft` | integer | MSL elevation in feet |
| `municipality` | string | City served |
| `icao_code` | string | 4-letter ICAO code (nullable) |
| `iata_code` | string | 3-letter IATA code (nullable) |
| `iso_country` | string | 2-letter country code |

**Filtering strategy for 3D labels:**
- `large_airport` (~600 worldwide): Always show 3D ground labels
- `medium_airport` (~4,500 worldwide): Show when zoomed in
- `small_airport` (~35,000+): Search-only, no 3D labels

**Implementation approach:**
Since this is a single-file HTML app with no build tooling, the 12.5 MB CSV cannot be bundled. Instead:
1. Fetch CSV at app startup (or on first "global mode" activation)
2. Parse client-side with simple CSV parser (~30 lines of code)
3. Build in-memory index for search (Map by ICAO, IATA, name prefix)
4. Filter to `large_airport` + `medium_airport` for 3D label rendering
5. Cache parsed data in IndexedDB for subsequent loads

### 3D Text Labels (Airport Ground Labels)

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| **Canvas Texture Sprites** (built-in THREE.js) | r128 | Airport name labels rendered on/near ground plane | Already used in the app for aircraft callsign labels (`_renderLabelToCanvas()`). Same technique works for airport labels. No additional library needed. Canvas2D renders text to texture, applied to THREE.Sprite. Sprites auto-face camera. | HIGH |

**Existing pattern in codebase:** The app already uses `_renderLabelToCanvas()` to create canvas-based text sprites for aircraft. Airport labels use the same approach with different styling:
- Larger font size
- Different color (distinguish from aircraft labels)
- Position on ground plane (y=0) at airport lat/lon
- LOD: only render labels for airports within camera view distance

**Performance consideration:** With ~600 large airports + ~4,500 medium airports, labels need aggressive culling:
- Frustum culling (only labels in camera view)
- Distance culling (hide labels beyond threshold)
- LOD: large airports visible at greater distance than medium
- Canvas texture pooling (reuse existing `_labelCanvasPool`)

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not Alternative |
|----------|-------------|-------------|---------------------|
| Flight data (primary) | airplanes.live | ADS-B Exchange (RapidAPI) | Paid subscription required. Free "Lite" tier discontinued March 2025. Same v2 format but behind paywall. |
| Flight data (primary) | airplanes.live | Aviationstack | Free tier: only 500 requests/month. Requires API key. Not ADS-B data (scheduled flights, not live positions). |
| Flight data (primary) | airplanes.live | FlightLabs | Only 50 requests free (7-day trial). Not viable for continuous polling. |
| Flight data (fallback) | OpenSky Network | FlightRadar24 | No public API. Screen scraping only. Terms prohibit automated access. |
| Terrain tiles | MapTiler Terrain-RGB | Mapbox Terrain-RGB | Requires API key + paid plan for terrain tiles. Free tier is only 50K map loads/month (more restrictive). MapTiler and Mapbox use same encoding formula. |
| Terrain tiles | MapTiler Terrain-RGB | Self-hosted SRTM/ASTER | Would need a tile server. Defeats single-file constraint. Massive data download. |
| Terrain elevation (point) | Open-Meteo | Open-Elevation | Hosted API unreliable (community-maintained, frequent downtime). Self-hosted version requires 70 GB of data. |
| Terrain elevation (point) | Open-Meteo | OpenTopoData | Public API: max 100 calls/day for non-academics. Too restrictive. |
| Satellite imagery | ArcGIS World Imagery | Google Satellite | Requires API key + billing account. Terms restrict non-Google-Maps usage. |
| Satellite imagery | ArcGIS World Imagery | Bing Maps Aerial | Requires API key. Terms restrict use outside Bing Maps SDK. |
| Satellite imagery | ArcGIS World Imagery | MapTiler Satellite | Would consume the free 100K request budget needed for terrain-RGB tiles. |
| Airspace (US) | FAA ADDS Feature Service | drnic/faa-airspace-data (GitHub) | Last updated 2014. Severely outdated. Missing current airspace changes. |
| Airspace (worldwide) | FAA ADDS (US only for now) | OpenAIP | Requires API key. Documentation unclear. Less reliable than FAA for US data. Good future extension for international. |
| Airport data | OurAirports CSV | OpenFlights | Less frequently updated. Fewer airports. Less complete IATA coverage. |
| Airport data | OurAirports CSV | FAA NASR (US only) | US-only. OurAirports has global coverage. |
| 3D text labels | Canvas Texture Sprites | three-spritetext (npm) | Adds dependency. Performance drops reported at scale (~10K labels). Canvas approach already in codebase. |
| 3D text labels | Canvas Texture Sprites | HTML overlay (CSS2DRenderer) | Adds THREE.js addon. DOM-based labels don't integrate with 3D scene depth. Performance worse than sprites for many labels. |
| 3D text labels | Canvas Texture Sprites | THREE.TextGeometry (3D mesh text) | Requires font loader + JSON font file (added dependency). Very heavy geometry per label. Not practical for hundreds of labels. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| ADS-B Exchange paid API | Unnecessary cost. Free alternatives (airplanes.live, adsb.lol) use the same v2 format with equivalent data. | airplanes.live (primary) + adsb.lol (fallback) |
| Mapbox GL JS / MapLibre GL JS | Entire map rendering library. Overkill -- we only need elevation data tiles, not a map renderer. Would conflict with existing THREE.js scene architecture. | Raw terrain-RGB tile fetch + manual decoding |
| CesiumJS | Full 3D globe library. Would replace THREE.js entirely. Massive bundle size. Cannot coexist with THREE.js in single-file architecture. | Stick with THREE.js r128 |
| GeoServer / PostGIS | Server-side geospatial stack. Violates single-file, client-only constraint. | Client-side GeoJSON parsing from ArcGIS REST API |
| npm packages for CSV parsing | Build tooling required. Violates single-file constraint. Papa Parse is 16KB but requires npm/CDN. | Hand-written CSV parser (~30 lines) for airports.csv |
| THREE.js TextGeometry | Requires loading JSON font files (additional HTTP request + parsing). Creates heavy geometry per character. At 600+ airports, geometry count would be devastating for performance. | Canvas-based sprite textures (already used in app) |
| Terrain from Google Elevation API | Requires API key + billing. Rate limited. Point-query only (not tile-based), so building a mesh requires thousands of individual requests. | MapTiler terrain-RGB tiles (one tile = 256x256 elevation grid) |

---

## Stack Patterns by Variant

**If using local dump1090 mode:**
- Skip global flight data APIs entirely
- Terrain, airspace, airports, and labels still apply
- Elevation tiles centered on receiver lat/lon
- Airport search scoped to local region by default

**If MapTiler free tier exhausted:**
- Degrade terrain to flat (no elevation)
- Show notification to user
- Or fall back to Open-Meteo point queries for sparse grid (lower resolution, higher latency)
- Satellite imagery unaffected (ArcGIS has no documented limits)

**If airplanes.live is down:**
- Automatic fallback to adsb.lol (same response format, zero parsing changes)
- If both down, fall back to OpenSky (adapter needed for different response format)
- If all down, switch to local dump1090 mode or show "no data" state

**If FAA airspace service is unavailable:**
- Cache airspace data in IndexedDB after first successful fetch
- Serve from cache on subsequent loads
- Airspace boundaries change every 8 weeks, so stale cache is acceptable short-term

---

## Version Compatibility

| Component | Version | Compatible With | Notes |
|-----------|---------|-----------------|-------|
| THREE.js | r128 | All recommended APIs | APIs return raw data (JSON, PNG tiles). No THREE.js version dependency. |
| THREE.js r128 | r128 | PlaneGeometry terrain approach | `PlaneGeometry`, `MeshStandardMaterial.displacementMap`, `Sprite`, `CanvasTexture` all available in r128. |
| THREE.js r128 | r128 | Canvas texture sprites | `_renderLabelToCanvas()` pattern already works. No new THREE.js features needed. |
| ArcGIS World Imagery tiles | N/A | THREE.js TextureLoader | Standard PNG image tiles. Loadable with `new THREE.TextureLoader().load()`. |
| MapTiler Terrain-RGB | v2 | Canvas pixel reading | Standard PNG/WebP tiles. Decode via offscreen `<canvas>` + `getImageData()`. |
| FAA ADDS Feature Service | ArcGIS REST | Standard fetch() | Returns GeoJSON. Parse with `JSON.parse()`. No special client needed. |
| OurAirports CSV | N/A | Standard fetch() + text parsing | UTF-8 CSV. Parse with split/regex. No library needed. |

---

## Installation

**No installation required.** This is a single-file HTML application. All data is fetched at runtime via `fetch()` from public APIs.

**One-time setup:**
1. Create a free MapTiler Cloud account at https://cloud.maptiler.com/
2. Generate a free API key
3. Add the API key to the app configuration (as a constant in the HTML file)

**No npm. No build. No packages.**

---

## Data Flow Summary

```
                    airplanes.live  adsb.lol  OpenSky
                          |            |         |
                          v            v         v
                    [Flight Data Adapter Layer]
                          |
    MapTiler              |           FAA ADDS        OurAirports
  Terrain-RGB             |           ArcGIS          airports.csv
      |                   |              |                 |
      v                   v              v                 v
  [Elevation      [Aircraft       [Airspace          [Airport
   Decode]         Manager]        GeoJSON]           Index]
      |                   |              |                 |
      v                   v              v                 v
  PlaneGeometry    Aircraft         ExtrudeGeometry   Canvas Sprite
  + Satellite      3D Models        Translucent       Labels on
  Texture                           Volumes           Ground Plane
      |                   |              |                 |
      +-------------------+--------------+--------+--------+
                                                   |
                                              THREE.js Scene
                                                   |
                                              WebGL Renderer
```

---

## Sources

**Flight Data APIs:**
- [airplanes.live API Guide](https://airplanes.live/api-guide/) -- endpoints, rate limits (HIGH confidence)
- [airplanes.live Field Descriptions](https://airplanes.live/rest-api-adsb-data-field-descriptions/) -- complete field list (HIGH confidence)
- [adsb.lol API Docs](https://www.adsb.lol/docs/open-data/api/) -- compatibility, endpoints (HIGH confidence)
- [adsb.lol OpenAPI spec](https://api.adsb.lol/api/openapi.json) -- full endpoint list verified (HIGH confidence)
- [adsb.lol GitHub](https://github.com/adsblol/api) -- ADSBx v2 compatibility confirmed (HIGH confidence)
- [OpenSky Network REST API](https://openskynetwork.github.io/opensky-api/rest.html) -- endpoints, rate limits, auth (HIGH confidence)

**Terrain Elevation:**
- [MapTiler Terrain-RGB Docs](https://docs.maptiler.com/guides/map-tiling-hosting/data-hosting/rgb-terrain-by-maptiler/) -- encoding formula, tile URL (HIGH confidence)
- [MapTiler Tiles API](https://docs.maptiler.com/cloud/api/tiles/) -- API key auth, XYZ pattern (HIGH confidence)
- [MapTiler Pricing](https://www.maptiler.com/cloud/pricing/) -- free tier: 5K sessions, 100K requests/month (HIGH confidence)
- [Open-Meteo Elevation API](https://open-meteo.com/en/docs/elevation-api) -- endpoint, parameters, batch limits (HIGH confidence)

**Satellite Imagery:**
- [ArcGIS World Imagery](https://www.arcgis.com/home/item.html?id=974d45be315c4c87b2ac32be59af9a0b) -- tile URL, no auth (MEDIUM confidence -- usage terms unclear for production)
- [OpenLayers ArcGIS XYZ example](https://openlayers.org/en/latest/examples/xyz-esri.html) -- URL format verified (MEDIUM confidence)

**Airspace Data:**
- [FAA ADDS Class Airspace](https://adds-faa.opendata.arcgis.com/datasets/c6a62360338e408cb1512366ad61559e_0) -- dataset overview (HIGH confidence)
- FAA Feature Service verified via direct REST query to `services6.arcgis.com` -- fields, GeoJSON output, query format (HIGH confidence)
- [ArcGIS Hub API](https://hub.arcgis.com/api/v3/datasets/c6a62360338e408cb1512366ad61559e_0) -- service URL extracted from metadata (HIGH confidence)

**Airport Data:**
- [OurAirports Open Data](https://ourairports.com/data/) -- download URLs, file sizes, update dates (HIGH confidence)
- [OurAirports Data Dictionary](https://ourairports.com/help/data-dictionary.html) -- field descriptions, type values (HIGH confidence)
- [OurAirports GitHub](https://github.com/davidmegginson/ourairports-data) -- nightly updates confirmed (HIGH confidence)

**THREE.js Terrain Patterns:**
- [THREE.js Canvas Textures Manual](https://threejs.org/manual/en/canvas-textures.html) -- canvas-to-texture approach (HIGH confidence)
- [THREE.js Forum: Performant text labels](https://discourse.threejs.org/t/performant-approach-for-displaying-text-labels-10000/21863) -- sprite text performance at scale (MEDIUM confidence)
- [SmartJava: Terrain from heightmap](http://www.smartjava.org/content/threejs-render-real-world-terrain-heightmap-using-open-data/) -- PlaneGeometry + heightmap technique (MEDIUM confidence)
- [THREE.js Cookbook: Terrain from heightmap](https://github.com/josdirksen/threejs-cookbook/blob/master/02-geometries-meshes/02.06-create-terrain-from-heightmap.html) -- implementation pattern (MEDIUM confidence)

---

*Stack research for: Airplane Tracker 3D -- Global Data, Terrain, Airspace, Airport Search*
*Researched: 2026-02-07*
