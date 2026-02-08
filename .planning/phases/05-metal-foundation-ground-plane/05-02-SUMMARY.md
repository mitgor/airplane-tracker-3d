---
phase: 05-metal-foundation-ground-plane
plan: 02
subsystem: rendering
tags: [metal, map-tiles, osm, mercator, async-loading, texture, lru-cache, slippy-map]

# Dependency graph
requires:
  - phase: 05-01
    provides: "Metal 3 rendering pipeline, OrbitCamera, Xcode project"
provides:
  - "MapCoordinateSystem: Mercator lat/lon to world-space XZ conversion"
  - "TileCoordinate: slippy map tile math with visible tile computation"
  - "MapTileManager: async OSM tile fetching with 300-tile LRU cache"
  - "Textured tile rendering pipeline with per-tile model matrices"
  - "Placeholder gray tiles for loading state"
  - "Zoom levels 6-12 adapting to camera distance"
affects: [06-globe-terrain-airports, 07-aircraft-flight-trails, 08-live-data-pipeline]

# Tech tracking
tech-stack:
  added: [MTKTextureLoader, URLSession, OpenStreetMap tiles]
  patterns: [async-tile-fetching, lru-texture-cache, per-tile-model-matrix, mercator-projection]

key-files:
  created:
    - AirplaneTracker3D/Map/MapCoordinateSystem.swift
    - AirplaneTracker3D/Map/TileCoordinate.swift
    - AirplaneTracker3D/Map/MapTileManager.swift
  modified:
    - AirplaneTracker3D/Rendering/Renderer.swift
    - AirplaneTracker3D/Rendering/Shaders.metal
    - AirplaneTracker3D/Rendering/ShaderTypes.h
    - AirplaneTracker3D.xcodeproj/project.pbxproj

key-decisions:
  - "Mercator projection with worldScale=500 for tile alignment at mid zoom levels"
  - "Serial DispatchQueue for thread-safe tile cache instead of actor for simplicity"
  - "URLSession with 200MB disk cache and 50MB memory cache for tile data"
  - "Reusable unit quad with per-tile model matrix instead of per-tile vertex buffers"
  - "cullMode .none for tile robustness, depthCompare .lessEqual for coplanar tiles"

patterns-established:
  - "Per-tile model matrix: unit quad (0,0)-(1,1) scaled/translated to world bounds"
  - "Async tile pipeline: texture(for:) returns nil for loading tiles, caller renders placeholder"
  - "Zoom level from camera distance: log2 interpolation mapping distance to zoom 6-12"
  - "Adaptive tile radius: fewer tiles at high zoom for performance control"

# Metrics
duration: 4min
completed: 2026-02-08
---

# Phase 5 Plan 2: Map Tile Ground Plane Summary

**Async OSM tile rendering on Mercator ground plane with LRU cache, zoom levels 6-12, and per-tile textured quads via Metal pipeline**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-08T21:49:14Z
- **Completed:** 2026-02-08T21:53:12Z
- **Tasks:** 3 (2 auto + 1 checkpoint auto-approved)
- **Files modified:** 7

## Accomplishments
- MapCoordinateSystem converts geographic lat/lon to Metal world-space using Mercator projection, centered on Seattle (47.6, -122.3)
- TileCoordinate implements standard slippy map tile math with visible tile grid computation
- MapTileManager fetches OSM tiles asynchronously via URLSession with proper User-Agent, converts PNG to Metal textures via MTKTextureLoader, and caches up to 300 tiles with LRU eviction
- Renderer draws textured tile quads on the ground plane using per-tile model matrices, with gray placeholders for loading tiles
- Zoom levels 6-12 adapt to camera distance using log2 interpolation
- Tile rendering replaces old ground plane quad from plan 01

## Task Commits

Each task was committed atomically:

1. **Task 1: Coordinate system, tile math, and async tile manager with LRU cache** - `c922a97` (feat)
2. **Task 2: Render textured tile quads on ground plane with dynamic loading** - `9edc558` (feat)
3. **Task 3: Verify map tile ground plane and full navigation** - auto-approved checkpoint (no commit)

## Files Created/Modified
- `AirplaneTracker3D/Map/MapCoordinateSystem.swift` - Geographic to world-space coordinate conversion with Mercator projection
- `AirplaneTracker3D/Map/TileCoordinate.swift` - Slippy map tile coordinate math (lat/lon to tile x/y) with visible tile computation
- `AirplaneTracker3D/Map/MapTileManager.swift` - Async tile fetching, Metal texture creation, 300-tile LRU cache
- `AirplaneTracker3D/Rendering/Renderer.swift` - Tile grid rendering with textured and placeholder pipeline states
- `AirplaneTracker3D/Rendering/Shaders.metal` - vertex_textured, fragment_textured, fragment_placeholder shaders
- `AirplaneTracker3D/Rendering/ShaderTypes.h` - TexturedVertex struct, BufferIndexModelMatrix, TextureIndexColor
- `AirplaneTracker3D.xcodeproj/project.pbxproj` - Added Map group with 3 new source files

## Decisions Made
- Used Mercator projection with worldScale=500.0 so tiles are approximately 175 world units wide at zoom 10, providing good visual scale
- Chose serial DispatchQueue for thread-safe tile cache access instead of Swift actor pattern, avoiding potential main-thread dispatch complexity
- Configured URLSession with 200MB disk cache and 50MB memory cache for tile HTTP responses, complementing the 300-tile MTLTexture LRU cache
- Used single reusable unit quad vertex buffer with per-tile model matrix buffer rather than creating vertex buffers per tile, keeping draw calls lightweight
- Set cullMode to .none for tile rendering robustness (tiles may be viewed from below when camera is near ground)
- Changed depthCompareFunction from .less to .lessEqual to handle coplanar tile geometry without z-fighting

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed async texture loader call**
- **Found during:** Task 1 (build verification)
- **Issue:** `MTKTextureLoader.newTexture(data:options:)` is async in modern Metal API, required `await`
- **Fix:** Added `await` keyword to the texture loader call
- **Files modified:** AirplaneTracker3D/Map/MapTileManager.swift
- **Verification:** Build succeeded after fix
- **Committed in:** c922a97 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor API usage correction. No scope creep.

## Issues Encountered
None beyond the auto-fixed async API call.

## User Setup Required
None - no external service configuration required. OSM tiles are publicly accessible.

## Next Phase Readiness
- Geographic coordinate system established for all future rendering (aircraft, airports, terrain)
- Tile rendering pipeline ready to receive overlay layers (aircraft positions, trails, airspace)
- MapTileManager cache prevents unbounded memory growth
- Camera integration complete: pan/zoom/orbit work with live tile loading

## Self-Check: PASSED

All 7 files verified present. Both task commits (c922a97, 9edc558) verified in git log.

---
*Phase: 05-metal-foundation-ground-plane*
*Completed: 2026-02-08*
