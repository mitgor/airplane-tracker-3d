# Coding Conventions

**Analysis Date:** 2026-02-07

## Naming Patterns

**Files:**
- Single-file structure: `airplane-tracker-3d-map.html` containing all HTML, CSS, and JavaScript
- Kebab-case for file names
- Descriptive names indicating purpose

**Functions:**
- camelCase for all function names
- Descriptive verb-based names: `updateLabels()`, `formatAltitude()`, `fetchData()`
- Prefix conventions:
  - `update*` for functions that modify state (e.g., `updateSceneBackground()`)
  - `toggle*` for boolean state flip functions (e.g., `toggleLabels()`)
  - `set*` for assignment functions (e.g., `setTrailLength()`)
  - `get*` for retrieval functions (e.g., `getAltitudeColor()`)
  - `init*` for initialization functions (e.g., `initStatsDatabase()`)
  - `handle*` for event handlers (e.g., `handleTouchStart()`)
  - `draw*` for rendering functions (e.g., `drawMiniGraph()`)
- Private/internal functions prefixed with underscore: `_renderLabelToCanvas()`, `_getPooledCanvas()`, `_returnCanvasToPool()`

**Variables:**
- camelCase for all variable names
- Descriptive names indicating content type and purpose
- State variables are global (top-level scope): `airplanes`, `selectedPlane`, `currentTheme`, `currentZoom`
- Configuration constants in UPPER_CASE: `REFRESH_INTERVAL`, `BASE_ALT_SCALE`, `MAP_GROUND_SIZE`, `LOD_DISTANCE_FAR`
- Private/cached variables prefixed with underscore: `_raycaster`, `_mouseVec`, `_airplanesArray`, `_needsRender`, `_glowTexture`
- Pool variables for performance: `_materialPool`, `_trailGeometryPool`, `_labelCanvasPool`, `_labelTexturePool`

**Types:**
- No TypeScript - pure vanilla JavaScript ES6+
- Objects store data in `.userData` properties (THREE.js convention): `plane.userData.hex`, `plane.userData.altitude`
- Maps used for collections: `airplanes = new Map()`, `tileCache = new Map()`, `aircraftInfoCache = new Map()`
- Sets used for unique tracking: `uniqueAircraftSeen = new Set()`, `_seenHexes = new Set()`

## Code Style

**Formatting:**
- No explicit linter/formatter configured
- Consistent indentation: 4 spaces
- Semicolons required at statement ends
- ES6+ features used throughout:
  - Arrow functions: `(data) => d.value`
  - Template literals: `` `https://tiles.stadiamaps.com/tiles/...${zoom}...` ``
  - Destructuring: `const { x, z } = latLonToXZ(data.lat, data.lon)`
  - Const/let preferred over var: Global state uses `let`, immutable values use `const`
  - Spread operator: `{...data}`, `[...values, ...values2]`

**Code blocks:**
- Consistent brace placement (opening brace on same line)
- Single-line conditionals acceptable: `if (!centerInitialized) return;`
- Multi-line conditionals with braces required
- 80-120 character line lengths (some lines exceed for readability)

**Linting:**
- No ESLint or Prettier configuration detected
- Manual code review style
- Warnings logged to console for runtime issues: `console.warn('Failed to load tile:', url)`

## Import Organization

**Not applicable** - Single HTML file with inline `<script>` tag

**External Dependencies:**
- CDN-loaded THREE.js: `<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>`
- All application code written inline in script tag
- Browser APIs used directly: `fetch()`, `IndexedDB`, `localStorage` (via cookies), canvas API

**Path Aliases:**
- Not applicable - single file codebase

## Error Handling

**Patterns:**
- Try-catch blocks used for async operations and API calls:
  ```javascript
  try {
      const response = await fetch(url);
      const data = await response.json();
  } catch (error) {
      console.warn('Failed to load tile:', url);
  }
  ```
- Silent failures with logging: Failed network requests logged but application continues
- Null/undefined checks before operations: `if (plane && plane.userData.lat)`
- Early returns for guard clauses: `if (!centerInitialized) return;`
- Optional chaining-like checks: `if (cursor && cursor.value && cursor.value.timestamp)`

**Error Recovery:**
- Graceful fallbacks when APIs unavailable:
  - stats.json unavailable → track aircraft count only
  - graphs1090 unavailable → use local IndexedDB storage
  - enrichment API unavailable → display base aircraft info only
  - Tile loading fails → display fallback color

**Logging Strategy:**
- `console.log()` for informational messages
- `console.warn()` for non-critical failures
- No error stack traces exposed to UI
- Failures don't halt execution

## Logging

**Framework:** Browser `console` object (no library)

**Patterns:**
- Informational: `console.log('graphs1090 detected, using its database')`
- Warnings: `console.warn('IndexedDB not available, using memory only')`
- No debug logs in production-facing messages
- Errors logged but not shown to user: `console.warn('Failed to load tile: ' + url)`

**When to Log:**
- System initialization: Database open, API checks
- Integration status: graphs1090 available/unavailable
- Non-critical failures: Network timeouts, missing data
- NOT for regular flow (aircraft updates, renders)

## Comments

**When to Comment:**
- Complex algorithms: Cookie parsing, tile projection math, interpolation
- Non-obvious intent: `// Invert and colorize image for retro theme`
- Section headers for major code blocks: `// ===========================================`
- Performance notes: `// Performance: Cached/reusable objects to avoid GC pressure`
- Configuration documentation: `// Altitude scale: 1x-300x range, reduced by 30x`

**JSDoc/TSDoc:**
- Not used
- Function purposes inferred from names
- Complex functions documented with inline comments

**Comment Style:**
- Single line comments: `// This is a comment`
- Block comments for sections:
  ```javascript
  // ===========================================
  // GRAPHS1090 INTEGRATION & LOCAL STATS
  // ===========================================
  ```

## Function Design

**Size:**
- 10-50 lines typical
- Complex functions up to 100+ lines (e.g., `animate()`, `createAirplane()`)
- Large functions broken into helper functions for readability

**Parameters:**
- 0-4 parameters typical
- Optional parameters using default values: `setCookie(name, value, days = 365)`
- Object parameters for multiple related options: `{ color, emissive, opacity }`
- Callback functions passed directly: `loadTrailFromDb(hex, callback)`

**Return Values:**
- Most functions return void (modify state or DOM)
- Some return values: `latLonToXZ()` returns `{x, z}`, `getTileUrl()` returns string
- Promises returned from async functions: `async function checkGraphs1090()`
- Null returned for missing data: `fetchAircraftInfo()` returns info object or null

**Side Effects:**
- Extensive state mutations (global variables modified)
- DOM manipulation (setting innerHTML, classList)
- THREE.js scene updates
- IndexedDB writes

## Module Design

**Exports:**
- Window globals for UI onclick handlers: `window.setGraphsTimePeriod()`, `window.toggleGraphs()`
- Global state variables accessible throughout
- Initialization function `init()` called on page load

**Global Scope Pollution:**
- Intentional: Single-file application with all state in global scope
- Organized into logical sections with comments
- Global state variables: `scene`, `camera`, `renderer`, `airplanes`, `showLabels`, `currentTheme`

**Barrel Files:**
- Not applicable - single file structure

## Performance Patterns

**Caching:**
- Object pooling for materials: `_materialPool`, `getPooledMaterial()`, `returnMaterialToPool()`
- Texture caching: `tileCache` with size limit (`MAX_TILE_CACHE_SIZE = 300`)
- Canvas/texture pools: `_labelCanvasPool`, `_labelTexturePool`
- Aircraft info cache: `aircraftInfoCache` for API responses

**Optimization Techniques:**
- Shared geometry instances: `_sharedGeometries` created once, reused for all aircraft
- Batch updates: `_trailUpdateQueue` accumulates changes before processing
- Throttling: `TRAIL_FILTER_INTERVAL = 500ms`, `BATCH_TRAIL_INTERVAL = 50ms`
- LOD (Level of Detail): `LOD_DISTANCE_FAR = 400`, `LOD_DISTANCE_CULL = 700`
- Array caching: `_airplanesArray` cached, rebuilt when `_airplanesArrayDirty = true`
- Render throttling: `_needsRender` flag prevents unnecessary renders
- Tab visibility awareness: Skip rendering when tab hidden

**Memory Management:**
- Resource disposal: `sprite.material.dispose()`, `tile.material.dispose()`
- History trimming: `STATS_HISTORY_MAX = 172800` (48 hours)
- Old trail cleanup: `cleanupOldTrails()` runs hourly
- Garbage collection: Minimize allocations in animation loop

---

*Convention analysis: 2026-02-07*
