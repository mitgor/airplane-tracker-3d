# Pitfalls Research

**Domain:** 3D flight tracker expansion -- global flight data, terrain elevation, airspace rendering, airport search
**Researched:** 2026-02-07
**Confidence:** MEDIUM-HIGH (verified against existing codebase, official API docs, and THREE.js community patterns)

---

## Critical Pitfalls

Mistakes that cause rewrites, memory crashes, or broken functionality.

### Pitfall 1: Terrain Tile Memory Explosion

**What goes wrong:**
Loading Mapzen Terrarium PNG tiles and converting them to THREE.js PlaneGeometry meshes with displaced vertices consumes enormous GPU and CPU memory. Each 256x256 terrain tile decoded into a PlaneGeometry with 256x256 segments creates 65,536 vertices (786 KB of position data alone). Loading a 10x10 grid of terrain tiles means 6.5 million vertices just for terrain -- on top of the existing map tiles, aircraft meshes, trails, labels, and glow sprites already in the scene. The browser will crash or drop to single-digit FPS.

**Why it happens:**
Developers treat terrain tiles the same as flat map texture tiles. The current codebase loads 10x10 map tiles as flat PlaneGeometry with shared geometry (zero vertex overhead per tile -- just texture swaps). Terrain tiles require actual vertex displacement, which is fundamentally different and orders of magnitude more expensive.

**How to avoid:**
- Use LOW vertex density for terrain meshes: 32x32 or 64x64 segments per tile maximum, not 256x256. The visual difference at flight-tracker zoom levels is negligible.
- Use vertex shader displacement instead of CPU-side vertex modification. Load the Terrarium PNG as a texture and sample it in the vertex shader via `displacementMap` on MeshStandardMaterial. This keeps geometry lightweight and moves work to the GPU.
- Implement aggressive LOD: near tiles get 64x64 segments, medium tiles get 32x32, far tiles get 16x16 or stay flat.
- Share geometry across tiles at the same LOD level (the current app already shares `_sharedGeometries.tile` for map tiles -- extend this pattern).
- Set a hard cap: maximum 25 terrain tiles loaded simultaneously, dispose the rest.

**Warning signs:**
- `renderer.info.memory.geometries` climbing above 200 during terrain loading
- Frame time exceeding 33ms (below 30fps) after terrain tiles appear
- Browser tab memory exceeding 500MB
- Terrain tiles loading but never unloading (check with `renderer.info.memory.textures`)

**Phase to address:**
Terrain elevation phase. This must be solved in the initial terrain architecture, not retrofitted.

---

### Pitfall 2: Global Flight API Rate Limiting Causes Data Gaps and Bans

**What goes wrong:**
Airplanes.live API is rate-limited to 1 request per second with a 250 nautical mile radius per geographic query. To show "global" coverage, developers make multiple overlapping geographic queries to tile the world, quickly exhausting the rate limit and getting their IP banned. The existing app polls dump1090 every 1 second -- naively switching to airplanes.live at the same interval with multiple geographic queries will exceed limits within seconds.

**Why it happens:**
The dump1090 local endpoint has no rate limiting (it is your own server). Developers carry over the 1-second polling habit to external APIs without accounting for the fundamental difference. Additionally, attempting "global" coverage requires many geographic queries since each is limited to 250nm radius.

**How to avoid:**
- For global view: use the airplanes.live `/v2/all` or similar bulk endpoints (if available) instead of tiling geographic queries. Alternatively, use adsb.lol bulk endpoints which provide full datasets.
- Implement a request queue with minimum 1-second spacing between ANY requests to airplanes.live.
- Cache aggressively: aircraft positions change every ~1-5 seconds, so polling faster than every 5 seconds for global data is wasteful anyway.
- Use exponential backoff when receiving 429 (Too Many Requests) responses.
- When user zooms into a region, switch from bulk to geographic query for that specific area only.
- Provide a clear data source toggle: "Local (dump1090)" vs "Global (airplanes.live)" -- never try to merge both simultaneously without careful deduplication.

**Warning signs:**
- HTTP 429 responses from the API
- Aircraft data arriving with increasing staleness (timestamps growing old)
- Console errors about failed fetch requests in rapid succession
- The API returning empty results for queries that should have data (silent ban)

**Phase to address:**
Global flight data integration phase. Must be the FIRST architectural decision when switching data sources.

---

### Pitfall 3: CORS Failures with Terrain Tile S3 Bucket

**What goes wrong:**
Mapzen Terrarium tiles on AWS S3 (`s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png`) may not return CORS headers for browser-based requests. Unlike the OSM/CartoDB/StadiaMaps tile servers the app already uses (which all serve proper CORS headers), AWS S3 public datasets do not always have CORS configured. The browser blocks the tile data, and since terrain tiles MUST be read as pixel data (not just displayed as textures), this is a hard blocker -- you cannot decode elevation values from a CORS-blocked image.

**Why it happens:**
For regular map tiles, the current codebase loads them as textures via `THREE.TextureLoader` with `crossOrigin = 'anonymous'`. This works because the tile servers send CORS headers. But terrain tiles require reading individual pixel RGB values (Terrarium encoding: `elevation = (R * 256 + G + B / 256) - 32768`), which requires drawing the image to a Canvas and calling `getImageData()`. This triggers a tainted canvas error if CORS headers are missing, even if the image loaded successfully as a texture.

**How to avoid:**
- Test the S3 endpoint CORS behavior FIRST before writing any terrain code. Use a simple fetch test: `fetch('https://s3.amazonaws.com/elevation-tiles-prod/terrarium/10/163/395.png', {mode: 'cors'})`.
- If S3 lacks CORS: use an alternative terrain tile provider with CORS support (Nextzen with API key, or self-hosted/CDN-proxied tiles).
- Alternatively, use the vertex shader displacement approach: load terrain tiles as regular textures (no pixel reading needed) and let the GPU shader sample them for displacement. This avoids the tainted canvas problem entirely since you never call `getImageData()`.
- The vertex shader approach is doubly beneficial: it solves CORS AND is more performant.

**Warning signs:**
- "Tainted canvases may not be exported" or "SecurityError" in console
- Terrain textures loading visually but elevation values all returning 0
- Works in development (same-origin or disabled security) but fails in production

**Phase to address:**
Terrain elevation phase. This is a day-one validation -- test CORS before writing terrain rendering code.

---

### Pitfall 4: Single-File HTML Grows Beyond Maintainability

**What goes wrong:**
The current file is 4,631 lines. Adding terrain tile management (~400 lines), global API integration (~300 lines), airspace volume rendering (~500 lines), airport search UI and data (~400 lines), and 3D text labels (~200 lines) will push it past 6,500 lines. At this size, every change risks breaking unrelated functionality. Finding specific functions becomes needle-in-haystack. The single-file constraint becomes the dominant source of bugs.

**Why it happens:**
The "no build tooling" constraint means no module splitting, no imports, no bundling. Everything goes in one `<script>` tag. This was fine at 2,000 lines but the existing 4,631 lines is already at the upper limit of single-file maintainability.

**How to avoid:**
- Use `<script src="...">` tags to split into multiple files WITHOUT build tooling. Each feature gets its own .js file loaded in order. This is NOT build tooling -- it is basic HTML.
- Alternative: use a single self-contained IIFE pattern within the HTML, but organize code into clearly delimited sections with consistent comment banners (the existing code already does this well with `// ===` banners).
- If staying single-file: establish a strict section ordering convention and document it at the top of the file. Group related functions together. Never add new code "wherever it fits."
- Consider a simple concatenation script (cat file1.js file2.js > combined.js) as a zero-dependency "build" step.

**Warning signs:**
- Taking more than 30 seconds to find a specific function
- Making a change in one section that breaks another section
- Duplicate variable names causing silent conflicts
- New features requiring changes in 5+ distant locations in the file

**Phase to address:**
Should be addressed BEFORE adding major new features. A file reorganization phase or multi-file split should precede terrain/airspace/airport work.

---

### Pitfall 5: Airspace Transparent Volume Rendering Artifacts

**What goes wrong:**
Airspace volumes (Class B/C/D) are rendered as semi-transparent extruded polygons. THREE.js has a well-documented problem with overlapping transparent objects: it sorts by object center distance from camera, not per-pixel. When Class B (large, tall) overlaps with Class C (smaller, lower), the rendering order flickers depending on camera angle. Nested airspace volumes (Class B containing Class C containing Class D) create persistent visual artifacts where inner volumes disappear or render on top of outer volumes incorrectly.

**Why it happens:**
WebGL does not support order-independent transparency. THREE.js sorts transparent objects by their center point distance to camera, which fails for large overlapping volumes. The depth buffer cannot correctly handle partially transparent overlapping surfaces.

**How to avoid:**
- Use `depthWrite: false` on all airspace materials to prevent depth buffer conflicts between airspace volumes.
- Set explicit `renderOrder` values: Class D = 1, Class C = 2, Class B = 3 (inner volumes render first).
- Use very low opacity (0.05-0.15) for volume fills -- just enough to see the boundary without creating obvious sorting artifacts.
- Render airspace boundaries as wireframe outlines (lines) with solid color rather than filled volumes. This completely avoids transparency sorting issues.
- Consider using `THREE.EdgesGeometry` on the extruded shapes for outline-only rendering, consistent with the existing app's wireframe/retro aesthetic.

**Warning signs:**
- Airspace volumes flickering when rotating the camera
- Inner airspace volumes disappearing when viewed from certain angles
- Airspace volumes appearing to "clip" through terrain or each other
- Significant FPS drop when multiple overlapping transparent volumes are visible

**Phase to address:**
Airspace rendering phase. Must decide on wireframe vs. filled approach before implementing.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Loading full OurAirports CSV (12.5 MB, ~70K rows) at startup | Simple implementation, all data available | 3-5 second load time, 50+ MB parsed in memory, blocks main thread | Never in production. Pre-filter to medium/large airports (~5K rows) or use chunked loading |
| Polling global API every 1 second (matching dump1090 interval) | Real-time feel | API rate limit exceeded, IP banned, wasted bandwidth | Never for global APIs. Use 5-10 second intervals minimum |
| Creating new THREE.Geometry per terrain tile | Each tile gets exact vertex count | Geometry objects never shared, GC pressure, hundreds of geometries | Only if using vertex shader displacement (then geometry is shared and lightweight) |
| Storing all terrain tile elevation data in JS arrays | Easy to query elevation at any point | Memory grows linearly with loaded tiles; 100 tiles * 256*256 * 4 bytes = 26 MB of Float32Arrays | Only for the ~9 visible tiles. Dispose arrays for unloaded tiles |
| Inline airspace GeoJSON data in the HTML file | No external file loading, no CORS | HTML file grows by 1-5 MB depending on coverage area; parse time at startup | Never. Load as separate JSON file via fetch from same origin |
| Using CSS2DRenderer for airport/airspace labels | Quick to implement, always readable | Separate render pass, DOM manipulation every frame, poor performance beyond 50 labels | Only for small label counts (<20). Use canvas sprite labels for bulk. The existing app already uses sprite labels. |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Airplanes.live API | Polling from browser with `fetch()` at page load without checking if user wants global data | Only fetch when user explicitly switches to global mode. Show loading indicator. Handle 429 gracefully |
| adsb.lol API | Assuming same response format as airplanes.live | While adsb.lol is "ADSBExchange Rapid API compatible," field names and availability differ. Test with real responses before assuming field mapping |
| Mapzen Terrarium tiles | Using the `tile.mapzen.com` URL pattern (requires API key from defunct Mapzen service) | Use direct S3 URL: `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png` (no auth required) or Nextzen equivalent |
| OpenAIP airspace data | Fetching airspace data for all of the US at once | OpenAIP data downloads require registration and are organized by country. Pre-process to GeoJSON and host statically, or use their API with appropriate caching |
| OurAirports CSV | Using `fetch()` to download airports.csv from GitHub Pages (davidmegginson.github.io) | GitHub Pages may rate-limit or change URLs. Host a pre-filtered copy of the data within the project. A filtered 500 KB file of medium/large airports is far more practical than the full 12.5 MB |
| hexdb.io (existing) | Making a new request for every aircraft that enters the scene | The existing code already caches results in `aircraftInfoCache`. Extend this pattern to ALL new integrations. Every external data source must have a cache layer |
| OSM tile servers (existing) | Aggressive tile preloading beyond the visible area | The existing code already has smart preloading. OSM usage policy explicitly forbids background downloading of tiles the user is not viewing. Same applies to terrain tile servers |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| One THREE.Mesh per terrain tile with full vertex displacement | Works for 4 tiles | FPS drops below 20, geometry count explodes | At 16+ terrain tiles with 256x256 segments each |
| Canvas-based label per airport marker | Works for 10 airports | Each label creates a texture, sprite, and material | At 50+ visible airport markers. Use instanced rendering or a single texture atlas |
| Fetching airspace polygons and extruding in real-time | Works for 1 airspace | Extrusion is expensive, GC spikes | At 10+ airspace volumes loading simultaneously. Pre-compute extrusion geometry and cache |
| Individual `scene.add()` for each airport marker | Works for 20 markers | Draw calls proportional to marker count | At 100+ markers. Use THREE.InstancedMesh or merge geometries |
| Re-parsing OurAirports CSV on every page load | Works in development | 12.5 MB download, parse, and filter on every visit | Always in production. Cache parsed data in localStorage or IndexedDB |
| Terrain tile textures never disposed | Works for short sessions | GPU memory grows without bound | After 5+ minutes of panning across terrain. Implement LRU cache with texture.dispose() |
| Airspace geometry created with ShapeGeometry + ExtrudeGeometry | Works for simple shapes | Complex airspace polygons (Class B shelves with holes) fail or produce degenerate geometry | With real-world Class B airspace boundaries that have concave shapes, holes, and shelf structures |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Exposing API keys in single-file HTML source | Anyone viewing page source gets your API keys | Use only keyless APIs (airplanes.live, adsb.lol, S3 terrain tiles) or proxy through a simple backend. The current app correctly uses only free, keyless APIs |
| Fetching aircraft data over HTTP instead of HTTPS | Position data intercepted, mixed content warnings | Always use HTTPS endpoints. The current app already uses HTTPS for all external fetches |
| Loading CSV data from untrusted third-party CDN | Malicious data injection via tampered CSV | Host all static data files within the project repository or on trusted infrastructure |
| Not sanitizing callsign/registration data before display | XSS via crafted ADS-B data (unlikely but possible for self-reported ADS-B fields) | Always use textContent (not innerHTML) when displaying aircraft data. The existing code already does this correctly |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Loading terrain, airspace, AND airport data simultaneously at startup | 10+ second load time, blank screen, no interactivity | Load in priority order: (1) map tiles + aircraft data first (already works), (2) terrain on-demand when user zooms in, (3) airspace when user enables it, (4) airports when user searches |
| Showing all 70,000 airports from OurAirports | Map covered in markers, impossible to identify anything, FPS destroyed | Filter by zoom level: z<6 = only large_airport, z6-8 = add medium_airport, z>8 = add small_airport. Never show heliports/closed/seaplane at any zoom |
| Terrain elevation blocking aircraft visibility | Aircraft at low altitude clip inside terrain mesh or are hidden behind mountains | Always render aircraft ABOVE terrain (add a minimum altitude offset). Use renderOrder to ensure aircraft always draw on top of terrain |
| Airspace volumes obscuring the map and aircraft | Cluttered, overwhelming visual noise | Default to airspace OFF. Provide toggle. When enabled, show outlines only with minimal fill. Fade airspace as user zooms out |
| Airport search returning hundreds of results with no ranking | User types "San" and gets 200 results across the globe | Rank by: (1) airport size (large first), (2) proximity to current view center, (3) name match quality. Limit display to 10 results |
| No loading states for async data sources | User thinks app is broken during 2-3 second API response | Show per-feature loading indicators: "Loading terrain...", "Fetching global aircraft...", "Loading airspace data..." |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Terrain rendering:** Often missing proper tile disposal when panning -- verify `texture.dispose()` and `geometry.dispose()` are called on every unloaded terrain tile
- [ ] **Global flight data:** Often missing deduplication when switching between local dump1090 and global API -- verify aircraft with same hex code do not appear twice
- [ ] **Airspace volumes:** Often missing altitude floors -- Class B shelves have different floor altitudes at different distances from the airport; a simple extrusion with uniform floor is wrong
- [ ] **Airport search:** Often missing debounce on search input -- verify typing "KJFK" does not trigger 4 separate searches ("K", "KJ", "KJF", "KJFK")
- [ ] **3D text labels:** Often missing camera-distance scaling -- verify labels remain readable at zoom level 6 without becoming enormous at zoom level 14
- [ ] **Terrain + aircraft interaction:** Often missing altitude reference consistency -- verify terrain elevation and aircraft altitude use the same vertical scale factor (the existing `altitudeScale` variable)
- [ ] **API error handling:** Often missing graceful degradation -- verify the app continues working when airplanes.live returns 429 or is unreachable
- [ ] **Memory management:** Often missing long-session stability -- verify memory does not grow after 30 minutes of continuous use with terrain + global data enabled
- [ ] **Tile loading order:** Often missing prioritization -- verify tiles near camera load before tiles at the edge of view
- [ ] **Data source switching:** Often missing state cleanup -- verify switching from global back to local properly removes global-only aircraft from the scene

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Terrain memory explosion | MEDIUM | Add vertex density cap (max 32x32 per tile), add tile count cap, add `renderer.info` monitoring with auto-disable at threshold |
| API rate limit ban | LOW | Implement exponential backoff, add "data source unavailable" UI message, fall back to cached data, wait 5-10 minutes for ban to lift |
| CORS failure with terrain tiles | MEDIUM | Switch to vertex shader displacement approach (no pixel reading needed), or switch to Nextzen tile provider with API key, or proxy through same-origin server |
| Transparent volume artifacts | LOW | Switch from filled volumes to wireframe/outline rendering. Remove all `transparent: true` in favor of `THREE.LineSegments` with `EdgesGeometry` |
| OurAirports CSV blocking main thread | LOW | Move parsing to a Web Worker, or pre-filter data server-side to reduce file size from 12.5 MB to ~500 KB |
| Single-file becoming unmaintainable | HIGH | Refactor to multi-file structure with `<script src>` tags. This requires touching every global variable and function reference. Do this BEFORE it becomes critical |
| Aircraft clipping through terrain | LOW | Add minimum altitude offset (e.g., terrain height + 50 units). Query terrain height at aircraft position and adjust Y |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Terrain memory explosion | Terrain Elevation | Monitor `renderer.info.memory` during testing. Must stay below 300 geometries and 200 textures |
| API rate limiting / bans | Global Flight Data | Test with artificial rate limiting. Verify no more than 1 request/sec to any single API |
| CORS with terrain tiles | Terrain Elevation (day-one validation) | Run a simple fetch test from the browser before writing any terrain code |
| Single-file growth | Pre-work / File Organization (before feature phases) | File can be navigated and a function found in under 15 seconds |
| Airspace transparency artifacts | Airspace Rendering | Rotate camera 360 degrees around overlapping airspace. No flickering or disappearing volumes |
| Airport data memory / performance | Airport Search | Load airports, verify memory delta is under 20 MB, FPS stays above 30 |
| Label performance with many markers | Airport Search / 3D Text Labels | Add 200 airport markers and labels. FPS must stay above 25 |
| Terrain + aircraft altitude mismatch | Terrain Elevation | Place an aircraft at 0 altitude and verify it sits on top of terrain, not inside it |
| Data source deduplication | Global Flight Data | Enable both dump1090 and global API. Count aircraft with same hex. Must be 0 duplicates |
| Long-session memory growth | All phases (ongoing concern) | Run app for 30 minutes with devtools Memory tab. Heap size must not grow continuously |

## Sources

- [Airplanes.live API guide](https://airplanes.live/api-guide/) -- rate limit: 1 req/sec, 250nm radius limit (HIGH confidence)
- [ADSB.lol API docs](https://www.adsb.lol/docs/open-data/api/) -- open data, ODbL license (MEDIUM confidence -- CORS behavior unverified)
- [OurAirports data](https://ourairports.com/data/) -- 12.5 MB airports.csv, ~70K rows (HIGH confidence)
- [Mapzen Terrain Tiles on AWS](https://registry.opendata.aws/terrain-tiles/) -- S3 public dataset, no auth required for S3 access (HIGH confidence)
- [Mapzen Terrarium format docs](https://github.com/tilezen/joerd/blob/master/docs/formats.md) -- RGB encoding: elevation = (R*256 + G + B/256) - 32768 (HIGH confidence)
- [THREE.js transparent rendering issues](https://discourse.threejs.org/t/threejs-and-the-transparent-problem/11553) -- object-center sorting limitation (HIGH confidence)
- [THREE.js memory disposal](https://discourse.threejs.org/t/dispose-things-correctly-in-three-js/6534) -- texture/geometry disposal requirements (HIGH confidence)
- [THREE.js CORS with TextureLoader](https://discourse.threejs.org/t/textureloader-cors-problem-when-texture-has-external-link/57163) -- crossOrigin='anonymous' pattern (HIGH confidence)
- [OSM tile usage policy](https://operations.osmfoundation.org/policies/tiles/) -- no bulk downloading, best-effort availability (HIGH confidence)
- [OpenAIP airspace data](https://www.openaip.net/data/airspaces) -- airspace boundaries organized by country (MEDIUM confidence)
- [THREE.js PlaneGeometry performance](https://discourse.threejs.org/t/planegeometry-renders-slowly-when-the-widht-height-is-large-and-there-are-many-segments-how-can-we-optimize-it/55108) -- large segment counts cause major slowdowns (HIGH confidence)
- [THREE.js text label performance](https://discourse.threejs.org/t/how-to-create-lots-of-optimized-2d-text-labels/66927) -- sprite labels degrade beyond 200-300 instances (MEDIUM confidence)
- Existing codebase analysis at `/Users/mit/Documents/GitHub/airplane-tracker-3d/airplane-tracker-3d-map.html` (4,631 lines, THREE.js r128, vanilla JS) -- direct inspection (HIGH confidence)

---
*Pitfalls research for: 3D flight tracker expansion (global data, terrain, airspace, airports)*
*Researched: 2026-02-07*
