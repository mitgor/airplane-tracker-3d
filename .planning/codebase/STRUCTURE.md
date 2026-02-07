# Codebase Structure

**Analysis Date:** 2026-02-07

## Directory Layout

```
airplane-tracker-3d/
├── airplane-tracker-3d-map.html    # Main application file (single-file SPA)
├── README.md                        # Project documentation
├── IMPROVEMENT_SUGGESTIONS.md       # Feature ideas and TODOs
├── screenshot.png                   # UI screenshot
├── airplane-tracker-3d-map.html     # HTML map (alternative naming)
└── .planning/
    └── codebase/
        └── ARCHITECTURE.md          # This analysis
```

## File Purposes

**airplane-tracker-3d-map.html:**
- Purpose: Single-file SPA containing all HTML, CSS, and JavaScript
- Size: ~53,000 lines (compressed into one file)
- Structure:
  - Lines 1-2: DOCTYPE and HTML tag
  - Lines 3-6: Meta tags (charset, viewport, title)
  - Lines 7-400: CSS styling for all themes (day, night, retro 80s)
  - Lines 400-1030: HTML DOM structure (containers, panels, controls, canvas)
  - Lines 1031-4585: Inline JavaScript (all application logic)

## Key File Locations

**Entry Points:**
- `airplane-tracker-3d-map.html` (line 1): Single entry point, loaded in browser

**Configuration:**
- Constants: Lines 1033-1040 (DATA_URL, REFRESH_INTERVAL, MAP_GROUND_SIZE, BASE_ALT_SCALE)
- Thresholds: Lines 1154-1173 (LOD_DISTANCE_FAR, LOD_DISTANCE_CULL, RENDER_THROTTLE_MS)

**Core Logic by Section:**

**Data Fetching:**
- `fetchData()` line 3014 - Poll aircraft data from dump1090
- `fetchStats()` line 1445 - Fetch ADS-B statistics
- `fetchAircraftInfo()` line 4375 - Fetch enrichment API info (optional)

**Interpolation & Animation:**
- `interpolateAircraft()` line 3097 - Smooth aircraft positions between data points
- `animate()` line 3836 - Main animation loop (requestAnimationFrame)
- `lerp()` line 3077 - Linear interpolation utility
- `lerpAngle()` line 3082 - Angle interpolation with wraparound handling

**3D Object Creation:**
- `createAirplane()` line 2619 - Create 3D aircraft model (wireframe or solid)
- `createTrailForPlane()` line 2958 - Create trail geometry for flight path
- `createAltLineForPlane()` line 2991 - Create vertical altitude reference line
- `createGlowSprite()` line 2151 - Create glow effect sprite

**Rendering & Updates:**
- `updateAllAircraftPositions()` line 3348 - Apply interpolated positions to all aircraft
- `updateLabels()` line 3546 - Redraw all aircraft label textures
- `updateTrail()` line 3371 - Update trail for a single aircraft
- `updateStatsPanel()` line 4226 - Update statistics display

**Scene & Camera:**
- `init()` line 1787 - Initialize scene, camera, renderer, all listeners
- `updateSceneBackground()` line 1892 - Apply theme colors to scene
- `updateCameraPosition()` line 3661 - Calculate camera position from angles/distances
- `resetCamera()` line 3669 - Return to default view

**Map Tiles:**
- `loadMapTiles()` line 2340 - Load and render map tile layer
- `preloadAdjacentTiles()` line 2247 - Pre-cache tiles around current view
- `loadTileTexture()` line 2453 - Fetch and cache individual tile texture
- `latLonToTile()` line 2230 - Convert lat/lon to tile coordinates
- `latLonToXZ()` line 2594 - Convert lat/lon to 3D scene coordinates

**UI & Controls:**
- `setupControls()` line 3632 - Setup button event listeners
- `setupKeyboardShortcuts()` line 3985 - Setup keyboard input handling
- `setupTouchControls()` line 4103 - Setup touch gesture handling
- `onMouseClick()` line 3724 - Handle mouse clicks for aircraft selection
- `selectPlane()` line 3752 - Show details panel for selected aircraft
- `onWindowResize()` line 3777 - Handle window resize events

**Settings Persistence:**
- `saveSettings()` line 1059 - Serialize and save to cookies
- `loadSettings()` line 1076 - Load from cookies on startup
- `setCookie()` line 1042 - Cookie helper
- `getCookie()` line 1047 - Cookie helper

**Statistics & Database:**
- `initStatsDatabase()` line 1258 - Initialize IndexedDB for stats storage
- `loadStatsFromDb()` line 1299 - Load historical data from IndexedDB
- `saveStatsToDb()` line 1329 - Store stats snapshot to IndexedDB
- `saveTrailToDb()` line 1351 - Persist trail data to IndexedDB
- `cleanupOldTrails()` line 1398 - Remove old trail data

**Performance Utilities:**
- `getPooledMaterial()` line 2171 - Get/create reusable material from pool
- `returnMaterialToPool()` line 2197 - Return material to pool after reuse
- `initSharedGeometries()` line 2047 - Create geometry instances used by all aircraft
- `getAltitudeColor()` line 2606 - Calculate color based on altitude (altitude-based LOD)
- `updateDistances()` line 3825 - Calculate distances for LOD culling

**HTML Sections:**

```html
<div id="container">              # Lines 400-405: Canvas container for THREE.js renderer
<div id="info-panel">             # Lines 407-620: Stats/info display (top-left)
<div id="selected-plane">         # Lines 622-737: Aircraft details (top-right)
<div id="controls">               # Lines 739-900: Control buttons (bottom-center)
<div id="graphs-panel">           # Lines 902-945: Statistics graphs (right side)
<div id="keyboard-help">          # Lines 945-1028: Keyboard shortcuts modal
```

## Naming Conventions

**Files:**
- Single HTML file: `airplane-tracker-3d-map.html` (kebab-case with descriptive name)

**Functions:**
- Descriptive camelCase: `fetchData()`, `updateAllAircraftPositions()`, `createAirplane()`
- Utility functions prefixed with underscore: `_renderLabelToCanvas()`, `_getPooledCanvas()`
- Event handlers prefixed with `on`: `onMouseClick()`, `onWindowResize()`, `handleTouchStart()`
- Setup/initialization functions prefixed with `setup` or `init`: `setupControls()`, `initGraphsSystem()`
- Getters prefixed with `get`: `getPooledMaterial()`, `getAltitudeColor()`
- Updaters prefixed with `update`: `updateCameraPosition()`, `updateTrail()`

**Variables:**
- Global state: lowercase with no prefix: `airplanes`, `selectedPlane`, `currentTheme`
- Private/internal state: prefixed with underscore: `_sharedGeometries`, `_materialPool`, `_isTabVisible`
- Constants: UPPERCASE: `REFRESH_INTERVAL`, `MAX_ZOOM`, `BASE_ALT_SCALE`
- Boolean flags: prefix with `show`, `is`, `has`, `enabled`: `showLabels`, `isRetro`, `trailEnabled`

**Types/Classes:**
- No custom classes used - data objects stored in userData properties of THREE.js objects
- Aircraft data structure: stored in `airplane.userData` with properties: `hex`, `flight`, `altitude`, `track`, `gs`, `baro_rate`, `category`, `label`, `trail`, `distanceToCamera`

## Where to Add New Code

**New Feature (non-rendering):**
- Add global state variable around line 1099-1250 (state section)
- Add helper function alongside related functions (use grep to find related code)
- Add UI controls around line 700-900 (controls section)
- Add event listener in `setupControls()` line 3632 or `setupKeyboardShortcuts()` line 3985
- Call feature code from `animate()` line 3836 if it needs per-frame updates

**New 3D Visual Element:**
- Add creation function following pattern of `createAirplane()` line 2619
- Add to scene in `init()` after ground setup (line 1833)
- Add update logic in `animate()` loop if animation needed
- Use material pooling for memory efficiency
- Update in `changeTheme()` line 1905 if theme-dependent

**New Control Button:**
- Add HTML button to `#controls` div (lines 739-900)
- Add click handler in `setupControls()` line 3632
- Add state variable if button has toggled state
- Save to settings if user preference should persist

**Map-Related Code:**
- Tile loading: modify `loadTileTexture()` line 2453
- Tile providers: modify `getTileUrl()` line 2006
- Zoom/pan: add to `mapZoomIn()` line 2493, `mapZoomOut()` line 2499, `panMap()` line 2575

**Statistics/Analytics:**
- Add stats fetch endpoint to `fetchStats()` line 1445
- Add stats to `statsHistory` object (line 1217)
- Add graph rendering in `drawMiniGraph()` line 1579
- Store to IndexedDB in `saveStatsToDb()` line 1329

**Keyboard Shortcuts:**
- Add case to switch statement in `setupKeyboardShortcuts()` line 3985 (lines 3995-4070)

**Themes:**
- Add theme CSS class to body around line 7-30 (e.g., `.theme-retro`)
- Add color scheme for elements (e.g., `.theme-retro #info-panel`)
- Add color logic in `changeTheme()` line 1905
- Update aircraft colors in `createAirplane()` line 2619

## Special Directories

**Browser Storage:**
- Cookies: Used for settings persistence (theme, units, trail settings, altitude scale)
- IndexedDB: Used for stats history (messageRate, aircraft, signal) and trail data
- No server-side persistence - everything stored client-side only

**External Dependencies:**
- THREE.js r128: Loaded from CDN line 1031 (`https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js`)
- Map tiles: Loaded from OpenStreetMap, CartoDB, or Stamen Toner servers
- Aircraft data: Fetched from `/dump1090/data/aircraft.json` (configurable at line 1034)
- Statistics: Fetched from `/dump1090/data/stats.json` (configurable at line 1223)

**Generated/Cached:**
- Map tiles cached in memory (`tileCache` Map, line 1180)
- Material instances created and reused from pools (lines 1143-1147)
- Canvas textures cached in `_labelTexturePool` (line 1131)
- Trail geometry objects cached in `_trailGeometryPool` (line 1151)

---

*Structure analysis: 2026-02-07*
