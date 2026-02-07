# Architecture

**Analysis Date:** 2026-02-07

## Pattern Overview

**Overall:** Single-page application (SPA) with real-time 3D visualization

This is a client-side JavaScript application that implements a 3D flight tracking system using THREE.js WebGL rendering. The architecture follows a procedural/functional pattern with heavy optimization for performance (memory pooling, object reuse, batch updates).

**Key Characteristics:**
- **WebGL 3D rendering** - All visualization happens in a single THREE.js scene
- **Real-time data streaming** - Continuous polling of ADS-B aircraft data from dump1090
- **Interpolation-based animation** - 2-second delayed interpolation between data points for smooth motion
- **State-driven UI** - Global state variables control rendering and functionality
- **Performance-optimized** - Extensive object pooling, material reuse, batch operations, LOD systems

## Layers

**Presentation/UI Layer:**
- Purpose: DOM manipulation, UI panels, controls, and event handling
- Location: HTML structure (lines 800-1000) + inline styling (lines 7-400)
- Contains: Control buttons, info panels, settings selectors, keyboard shortcuts UI
- Depends on: State variables (theme, units, settings)
- Used by: Event handlers, display update functions

**3D Rendering Layer:**
- Purpose: THREE.js scene management, camera, lighting, aircraft models
- Location: `init()` function (lines 1787-1890), `animate()` (lines 3836-3985)
- Contains: Scene setup, camera positioning, light configuration, renderer configuration
- Depends on: THREE.js library (loaded from CDN line 1031)
- Used by: All 3D visualization, aircraft creation

**Data Flow/Interpolation Layer:**
- Purpose: Fetch aircraft data, buffer it, and interpolate between updates
- Location: `fetchData()` (lines 3014-3074), `interpolateAircraft()` (lines 3097-3313)
- Contains: HTTP polling, data buffering with timestamps, smooth interpolation logic
- Depends on: dump1090 API endpoint
- Used by: Aircraft position updates, animation loop

**Aircraft Management Layer:**
- Purpose: Create, update, and manage individual aircraft 3D objects
- Location: `createAirplane()` (lines 2619-2957), `updateAllAircraftPositions()` (lines 3348-3370)
- Contains: Aircraft mesh creation, geometry/material pooling, trail rendering, label management
- Depends on: Shared geometries, material pools, interpolated data
- Used by: Animation loop, data interpolation

**Map/Tile Layer:**
- Purpose: Load and cache map tiles, manage zoom/pan, render ground plane
- Location: `loadMapTiles()` (lines 2340-2452), tile preloading (lines 2247-2339)
- Contains: Tile coordinate calculations, texture caching, map transitions
- Depends on: OpenStreetMap/CartoDB/Stamen tile servers
- Used by: Scene background, map zoom/pan controls

**Statistics/Analytics Layer:**
- Purpose: Track ADS-B message rates, aircraft counts, signal levels
- Location: `initStatsDatabase()` (lines 1258-1296), `fetchStats()` (lines 1445-1509)
- Contains: IndexedDB storage, stats history, graph rendering
- Depends on: dump1090 stats endpoint, IndexedDB, Canvas for graph drawing
- Used by: Stats panel, graphs display

## Data Flow

**Aircraft Rendering Cycle:**

1. **Data Fetch** → `fetchData()` polls `/dump1090/data/aircraft.json` every 1 second
2. **Buffering** → Data stored in `aircraftDataBuffer` Map with timestamps
3. **Interpolation** → `interpolateAircraft()` runs at 30fps, creating smooth positions by lerping between buffered points
4. **Position Update** → Interpolated positions applied to aircraft 3D objects
5. **Rendering** → `animate()` frame loop renders scene with all aircraft
6. **Label Update** → Labels positioned relative to aircraft, culled by distance
7. **Trail Update** → Flight history rendered as line segments, colored by altitude/speed

**State Management:**

- Global state variables hold all application state (lines 1099-1251)
- Settings persisted to cookies via `setCookie()`/`getCookie()` functions
- State mutations happen directly on global variables (no centralized state container)
- Settings loaded on init via `loadSettings()`, saved on change via `saveSettings()`

**Camera Control:**

1. User input captured via keyboard (`setupKeyboardShortcuts()` line 3985), mouse (`onMouseClick()` line 3724), touch (`setupTouchControls()` line 4103)
2. Camera position calculated based on `cameraAngle`, `cameraHeight`, `cameraDistance`
3. `updateCameraPosition()` applies calculations every frame
4. `autoRotate` flag enables continuous rotation animation

## Key Abstractions

**Aircraft Object (Group):**
- Purpose: 3D representation of a single aircraft
- Examples: Created in `createAirplane()` (line 2619)
- Pattern: THREE.Group containing body, wings, tail, lights, rotors, labels, trails
- Properties in `userData`: hex, flight, altitude, speed, track, category, trail positions, etc.

**Material Pool:**
- Purpose: Reuse materials to reduce GPU memory and draw calls
- Examples: `_materialPool` object (lines 1143-1147)
- Pattern: `getPooledMaterial(type, options)` returns existing or creates new material
- Types: wireframe, phong, basic materials with different colors/properties

**Geometry Pool (Shared):**
- Purpose: All aircraft share the same geometry instances (fuselage, wings, rotor, etc.)
- Examples: `_sharedGeometries` object (line 1135)
- Pattern: `initSharedGeometries()` creates geometries once, `createAirplane()` reuses them
- Benefit: Massive memory savings when rendering hundreds of aircraft

**Trail Rendering:**
- Purpose: Visualize historical flight path
- Pattern: `createTrailForPlane()` (line 2958) builds TubeGeometry, colored by altitude/speed
- Storage: Trail data persisted to IndexedDB via `saveTrailToDb()` (line 1351)

**Label Canvas Texture:**
- Purpose: Render text labels for aircraft callsigns/info as sprite textures
- Pattern: `_renderLabelToCanvas()` (line 3503) draws to canvas, creates texture, `_labelCanvasPool` reuses
- Update: Full redraw every 1 second in `updateLabels()` (line 3546), positions updated every frame

## Entry Points

**HTML Load Sequence:**
- Location: `airplane-tracker-3d-map.html`
- Triggers: Page load
- Responsibilities: Define HTML structure, load THREE.js from CDN, embed all JavaScript

**Script Execution:**
- Location: Lines 1031-4585 (inline `<script>` tag)
- Triggers: HTML parsed
- Responsibilities: Initialize all global variables, wait for DOM ready, call `init()`

**Main Init Function:**
- Location: `init()` function (line 1787)
- Triggers: Script execution (implicit call at end)
- Responsibilities:
  - Load settings from cookies
  - Create THREE.js scene, camera, renderer
  - Initialize geometries and materials
  - Setup event listeners (keyboard, mouse, touch, window resize)
  - Start animation loop with `animate()`
  - Start data polling with `fetchData()` and `setInterval()`

**Animation Loop:**
- Location: `animate()` function (line 3836)
- Triggers: `requestAnimationFrame` continuous callback
- Responsibilities:
  - Check tab visibility (power saving)
  - Run interpolation at 30fps
  - Update camera (auto-rotate, follow mode)
  - Update map transitions
  - Update tile fades
  - Update aircraft lights, rotors, labels
  - Render scene

## Error Handling

**Strategy:** Silent failure with console logging

**Patterns:**
- Data fetch errors caught in `fetchData()` try-catch, logged to console
- Stats fetch errors handled in `fetchStats()` with fallback to empty data
- IndexedDB unavailability handled gracefully, falls back to memory-only stats
- Texture loading uses error callbacks, missing textures show fallback colors
- Aircraft without position data (lat/lon) silently filtered out

## Cross-Cutting Concerns

**Logging:** Console.log/error used for debugging (no structured logging framework)

**Validation:**
- Aircraft data validated by checking `ac.lat && ac.lon` presence
- Altitude/speed values validated before color/scale calculations
- No schema validation on API responses

**Authentication:** None (client-side only, relies on web server proxy authentication if needed)

**Performance Monitoring:**
- Distance calculations cached, updated every 3 frames (LOD system)
- Tab visibility monitored to pause rendering when window hidden
- Memory pooling used for materials, geometries, canvases, labels
- Render-on-demand flag (`_needsRender`) used to skip unnecessary renders

---

*Architecture analysis: 2026-02-07*
