# Technology Stack

**Project:** Airplane Tracker 3D -- v2.1 Milestone (Airspace Volumes, Coverage Heatmap, Visual Polish)
**Researched:** 2026-02-09
**Confidence:** HIGH -- all recommendations verified against existing codebase (42 files, 7,043 LOC) and Metal documentation

---

## Existing Stack (NO CHANGES)

The v2.0 stack is validated and shipping. Zero external dependencies. This milestone adds NO new frameworks, NO new SPM packages, NO new build dependencies. Every feature is implemented using Metal 3, Swift, SwiftUI, and system frameworks already in the project.

| Technology | Already Used For |
|------------|-----------------|
| Metal 3 / MSL | 7 shader files, 10+ pipeline states, instanced rendering |
| Swift | 32 source files, async/await, actors |
| SwiftUI | Settings, panels, overlays |
| MetalKit | MTKView, MTKTextureLoader |
| CoreText | Label atlas rasterization |
| ImageIO | Terrarium PNG decoding |
| URLSession | Tile fetching, ADS-B polling, enrichment |

---

## Recommended Additions for v2.1

All additions are new `.swift` files and `.metal` shader files within the existing project structure. No architectural changes to the rendering pipeline -- only new render passes added to the existing single-encoder draw loop.

---

### 1. Airspace Volume Rendering

**What:** Translucent 3D extruded polygons showing FAA Class B/C/D airspace boundaries with floor/ceiling altitudes.

#### New Files

| File | Technology | Purpose | Why This Approach |
|------|-----------|---------|-------------------|
| `AirspaceManager.swift` | Swift | Fetch FAA ArcGIS GeoJSON, triangulate polygons, build Metal buffers, manage lifecycle | Follows the `MapTileManager` / `TerrainTileManager` async-fetch + LRU-cache pattern already in the codebase |
| `AirspaceShaders.metal` | MSL | Vertex/fragment shaders for translucent fill and edge wireframe | Separate shader file per project convention (7 `.metal` files exist) |
| `EarClipTriangulator.swift` | Pure Swift | Convert GeoJSON polygon rings to triangle index arrays | ~80 lines. See triangulation rationale below |

#### ShaderTypes.h Additions

```c
// Airspace volume vertex (32 bytes)
typedef struct {
    simd_float3 position;    // 12 bytes: world-space XYZ
    float _pad0;             // 4 bytes: padding
    simd_float4 color;       // 16 bytes: class-based RGBA with alpha
} AirspaceVertex;

// Buffer index
BufferIndexAirspaceVertices = 8
```

#### Triangulation Decision: Pure Swift Ear-Clipping

**Use ear-clipping. Do NOT add LibTessSwift or any external package.**

Rationale:
- The project has **zero external dependencies**. This is a deliberate architectural principle, not an accident. Introducing a package for one feature violates this principle.
- FAA airspace polygons from the ArcGIS API are simple convex/mildly-concave shapes with 20-60 vertices, no holes, no self-intersections. Ear-clipping handles this trivially.
- An ear-clipping implementation is ~80 lines of Swift. The `AircraftMeshLibrary.swift` already generates more complex geometry procedurally.
- If future polygon complexity demands it (unlikely), upgrade to monotone-polygon decomposition (~200 lines) before ever considering a dependency.

Alternatives rejected:
| Option | Why Not |
|--------|---------|
| [LibTessSwift](https://github.com/LuizZak/LibTessSwift) (SPM) | Adds external dependency for 20-60 vertex simple polygons. Overkill. |
| [iShapeTriangulation](https://github.com/iShape-Swift/iShapeTriangulation) (SPM) | Same concern. O(n*log(n)) algorithm unnecessary for O(n^2) ear-clip on tiny polygons. |
| Model I/O MDLMesh | No extrusion primitive. Would need MDLMesh -> MTLBuffer conversion overhead. |

**Confidence: HIGH** -- Ear-clipping algorithm is well-understood. FAA polygon complexity verified by inspecting web app reference (`airplane-tracker-3d-map.html` line 1929: polygons are simple `Shape` paths with `moveTo`/`lineTo`).

#### Translucent Rendering: Sorted Back-to-Front Alpha Blending

**Use standard alpha blending with depth-read-no-write. Do NOT use order-independent transparency (OIT).**

The exact pipeline configuration already exists in the codebase three times:
- `glowPipeline` (Renderer.swift line 298): additive blend, depth read no write
- `trailPipeline` (Renderer.swift line 341): alpha blend, depth read no write
- `labelPipeline` (Renderer.swift line 380): alpha blend, depth read no write

Airspace fill pipeline configuration (identical to trail/label pattern):
```swift
colorAttachment.isBlendingEnabled = true
colorAttachment.rgbBlendOperation = .add
colorAttachment.alphaBlendOperation = .add
colorAttachment.sourceRGBBlendFactor = .sourceAlpha
colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
```

Depth stencil: reuse existing `glowDepthStencilState` (Renderer.swift line 320-326: `depthCompareFunction: .lessEqual`, `isDepthWriteEnabled: false`).

Why NOT OIT with image blocks:
- Apple Silicon (GPU family 7+) supports raster order groups and image blocks -- verified via [Metal Feature Set Tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf) and [areRasterOrderGroupsSupported](https://developer.apple.com/documentation/metal/mtldevice/arerasterordergroupssupported).
- But airspace volumes are **non-overlapping** (Class B, C, D occupy distinct geographic areas). At most ~5-20 volumes visible simultaneously.
- Simple sorted alpha blending (sort by distance-to-camera) works perfectly for non-overlapping volumes.
- OIT adds tile shading complexity, imageblock memory management, and a second shader pass for zero visual benefit.

**Confidence: HIGH** -- Alpha blending pattern verified in three existing pipelines. OIT capability confirmed but deliberately rejected.

#### Airspace Wireframe Edges

Render polygon edges as line primitives (`.line` draw type) in a separate pass after the fill pass. Use the same vertex data but with higher alpha (0.3 edges vs 0.06 fill). The existing `altLinePipeline` (Renderer.swift line 400) demonstrates line rendering with alpha blending.

The web app does exactly this: `EdgesGeometry` + `LineSegments` at opacity 0.3 for edges, `MeshBasicMaterial` at opacity 0.06 for fill (line 1950-1972).

#### Extrusion Approach

Each airspace polygon becomes two triangle fans (floor and ceiling) plus side walls:
1. **Floor:** Ear-clip triangulate the 2D polygon at `LOWER_VAL` altitude (Y coordinate)
2. **Ceiling:** Same triangulation at `UPPER_VAL` altitude
3. **Walls:** For each edge of the polygon, create a quad (2 triangles) connecting floor vertex to ceiling vertex

This matches THREE.js `ExtrudeGeometry` behavior used in the web app (line 1944: `{ depth: height, bevelEnabled: false }`).

All positions are in world space using `MapCoordinateSystem.shared.lonToX()` / `latToZ()` for XZ, and altitude conversion for Y (using the same scale as aircraft: altitude in feet * 0.001, matching `DataNormalizer`).

#### FAA Data Source

The web app uses this endpoint (confirmed at `airplane-tracker-3d-map.html` line 1883):

```
https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services/Class_Airspace/FeatureServer/0/query
```

Query: `CLASS IN ('B','C','D')`, envelope geometry filter, GeoJSON response format, max 500 records.

Parse with `JSONSerialization` for dynamic GeoJSON structure. Altitude fields: `UPPER_VAL`/`LOWER_VAL` with `UOM` of feet or `"FL"` (flight level = value * 100 feet).

**Confidence: MEDIUM on API URL** -- The [FAA ArcGIS Open Data portal](https://adds-faa.opendata.arcgis.com/datasets/c6a62360338e408cb1512366ad61559e_0) confirmed the dataset exists. However, Esri updated GeoJSON download URL configuration in June 2024. The `services6.arcgis.com` query URL used by the web app should still work for FeatureServer queries. Verify at implementation time.

---

### 2. Coverage Heatmap Rendering

**What:** A color-mapped grid texture overlaid on the terrain showing aircraft density by geographic cell.

#### New Files

| File | Technology | Purpose | Why This Approach |
|------|-----------|---------|-------------------|
| `HeatmapManager.swift` | Swift | Accumulate aircraft positions into a grid, create/update heatmap texture | CPU-side grid matches web app approach. Updates at 0.2 Hz, not per-frame |
| `HeatmapShaders.metal` | MSL | Fragment shader to color-ramp sample a heatmap texture | Color mapping in shader, not CPU |

#### Approach: CPU Grid + MTLTexture Upload

**Use CPU-side grid accumulation with periodic texture upload. Do NOT use a Metal compute kernel.**

Implementation:
1. Maintain a `[Float]` grid (32x32 = 1024 cells) on the CPU.
2. Every statistics sample (5-second interval via `StatisticsCollector`), iterate aircraft positions and increment grid cells.
3. Upload to a 32x32 `MTLTexture` (`.r32Float` pixel format) using `texture.replace(region:mipmapLevel:withBytes:bytesPerRow:)`.
4. Render as a textured quad on the ground plane, covering the visible map area.
5. Fragment shader samples the R channel, applies a color ramp, and outputs with alpha for terrain blending.

The web app uses this exact approach: a 20x20 JavaScript array, incremented per-aircraft, drawn to a 2D Canvas (lines 5368-5455).

Why NOT Metal compute kernel:
| Factor | CPU Grid | Compute Kernel |
|--------|----------|----------------|
| Update frequency | 0.2 Hz (every 5s) | Could be per-frame |
| Grid size | 32x32 (1024 values) | Same |
| Setup complexity | ~30 lines Swift | ~100 lines (pipeline, encoder, dispatch) |
| Performance need | Negligible at 0.2 Hz | Unjustified overhead |

Compute kernels ([Apple: Processing a texture in a compute function](https://developer.apple.com/documentation/metal/compute_passes/processing_a_texture_in_a_compute_function)) are the right tool when updating large textures per-frame. For 1024 floats at 0.2 Hz, CPU is simpler and equally fast.

**Confidence: HIGH** -- `texture.replace()` is already used by `AircraftMeshLibrary.createGlowTexture()` (line 79-82). Same API, same pattern.

#### ShaderTypes.h Additions

```c
// Heatmap rendering parameters (passed as uniform)
typedef struct {
    simd_float2 mapMin;      // World-space min corner (X, Z)
    simd_float2 mapMax;      // World-space max corner (X, Z)
    float opacity;           // Overall heatmap opacity (theme-dependent)
    float _pad0;
    float _pad1;
    float _pad2;
} HeatmapUniforms;

// Buffer/texture indices
BufferIndexHeatmapUniforms = 9
TextureIndexHeatmap = 1
```

#### Heatmap Fragment Shader Color Ramp

Theme-dependent color ramps (matching web app):
- **Day:** Blue (cold) to Red (hot) -- `mix(float4(0,0.4,1,a), float4(1,0,0,a), intensity)`
- **Night:** Dark blue to Cyan -- `mix(float4(0,0,0.3,a), float4(0,0.8,1,a), intensity)`
- **Retro:** Black to Green -- `float4(0, intensity * 0.8, 0, a)`

Alpha increases with intensity: `alpha = heatmapOpacity * (0.2 + intensity * 0.8)`.

#### Render Position

Render the heatmap **after terrain, before aircraft and other translucent geometry**. It is a ground-plane overlay. Uses the same alpha-blend pipeline pattern as other translucent layers.

**Confidence: HIGH** -- Pattern fully understood from existing codebase.

---

### 3. Improved Procedural Aircraft Models

**What:** Enhanced geometry for all 6 aircraft categories using existing primitive helpers.

#### Modified Files

| File | Change | Purpose |
|------|--------|---------|
| `AircraftMeshLibrary.swift` | Enhance all 6 `build*()` methods + add 2 new primitives | More realistic aircraft silhouettes |
| `AircraftInstanceManager.swift` | Fix propeller rotation matrix bug (line 193-194) | Propellers spin around nose, not aircraft center |

#### No New Technology Needed

The existing `AircraftMeshLibrary` has these primitive helpers:
- `appendCylinder(radius:height:segments:offset:)` -- fuselage, engines
- `appendCone(radius:height:segments:offset:)` -- nose cones
- `appendBox(size:offset:)` -- wings, stabilizers, landing gear
- `appendSphere(radius:segments:offset:)` -- helicopter cabin

The existing `AircraftVertex` struct (position + normal) and `AircraftShaders.metal` lighting need **zero changes**. Improvements are purely geometric -- calling existing helpers with better parameters and adding two new primitives:

#### New Primitives to Add

1. **`appendTrapezoid()`** (~40 lines): Swept/tapered wing cross-section. Two quads (top/bottom) with different widths at root vs tip. Better than box for jet wings.

2. **`appendTorus()`** (~50 lines): Ring shape for engine nacelle intakes. Optional but adds realism to jet engines. Uses the same sin/cos loop pattern as `appendCylinder`.

Both follow the exact same pattern as existing helpers: accept `vertices: inout [AircraftVertex]` and `indices: inout [UInt16]`, generate geometry with positions and normals, append to arrays.

#### Propeller Rotation Bug Fix

**Root cause** (verified in `AircraftInstanceManager.swift` line 191-204):

```swift
// BUG: noseOffset is identity (translating by zero vector)
let noseOffset = translationMatrix(SIMD3<Float>(0, 0, 0))
let spinMatrix = translation * rotation * noseOffset * propRotation
```

The `propRotation` (rotation around Z axis) is applied in world space because `noseOffset` is identity. The propeller rotates around the aircraft's center instead of its nose.

**Fix:** The propeller mesh (`buildPropeller()`) already has a built-in Z offset of 1.55 (line 470: `offset: SIMD3<Float>(0, 0, 1.55)`). The rotation needs to happen in local space, AFTER the heading rotation positions the nose correctly. The fix is:

```swift
// CORRECT: rotate propeller in local space (after heading rotation)
let spinMatrix = translation * rotation * propRotation
```

This works because `propRotation` is around the Z axis, and the heading `rotation` has already oriented the Z axis along the aircraft's forward direction. The propeller mesh's built-in 1.55 Z offset places it at the nose in local space, and `propRotation` spins it there.

**Confidence: HIGH** -- Bug identified by reading code directly. The propeller mesh definition confirms the built-in offset.

#### Per-Category Improvements

| Category | Current | Improved |
|----------|---------|----------|
| Jet | Box wings, cylinder fuselage | Swept trapezoid wings, winglets (small vertical boxes at tips), engine pylons (thin boxes connecting nacelles to wings) |
| Widebody | Same as jet but larger | Wider swept wings, 4 separated engine nacelles with torus intake rings, wider fuselage cylinder |
| Helicopter | Sphere + cylinder | Tail fin (angled box), rotor hub (small cylinder), landing gear struts (thin boxes) |
| Small prop | Box wings, small cylinder | High-wing mounting (offset wings above fuselage center), struts (thin boxes), fixed landing gear |
| Military | Box delta wings | Proper delta wing (trapezoid narrowing to tip), twin angled vertical stabilizers, sharper nose cone |
| Regional | 0.8x scaled jet | T-tail (horizontal stabilizer on top of vertical tail), shorter wings, 2 rear-mounted engines |

**Confidence: HIGH** -- All geometry is built from existing primitives. No shader changes required.

---

### 4. Map Tile Pipeline Fixes

**What:** Debug and fix map tiles not displaying correctly.

#### Modified Files

| File | Change | Purpose |
|------|--------|---------|
| `MapTileManager.swift` | Add debug logging, fix potential issues | Diagnose tile display failures |
| `ThemeManager.swift` | Verify tile URL generation | Ensure URLs produce valid responses |

#### No New Technology Needed

The map tile pipeline (`MapTileManager.swift`) uses `URLSession` + `MTKTextureLoader` + LRU cache. Investigation targets:

1. **`@2x` suffix inconsistency:** Day theme uses `@2x.png` (line 121 of ThemeManager.swift) but night theme does not (line 123). CartoDB servers may return 512x512 for `@2x` and 256x256 otherwise. If the renderer assumes consistent tile sizes, this mismatch could cause UV mapping issues or texture binding failures.

2. **Texture creation error swallowing:** `fetchTile()` has a `try await textureLoader.newTexture(data:options:)` but errors go to a generic catch that only prints in DEBUG (line 132-135). If PNG data is valid HTTP but not a valid texture (e.g., HTML error page, CORS redirect), creation fails silently.

3. **Cache invalidation race:** When `switchTheme()` calls `clearCache()`, pending `Task` completions from the old theme may still be in flight and could store old-theme tiles under new-theme tile coordinates (because `TileCoordinate` does not include theme).

4. **Missing retry logic:** If a tile fetch fails (timeout, 429 rate limit), the `pendingRequests` set entry is removed but no retry is scheduled. The tile stays as a placeholder until the camera moves away and back.

**Fix approach:** Add a generation counter to `MapTileManager` that increments on `clearCache()`. Each fetch task captures the generation at launch. On completion, discard the result if the generation has changed (stale fetch). Add `#if DEBUG` logging for fetch success with dimensions, fetch failure with HTTP status, and cache hit/miss.

**Confidence: HIGH** -- All issues identified by direct code analysis.

---

## New Pipeline States in Renderer.swift

| Pipeline | Vertex Shader | Fragment Shader | Blend Mode | Depth State |
|----------|--------------|-----------------|------------|-------------|
| `airspaceFillPipeline` | `airspace_vertex` | `airspace_fill_fragment` | Standard alpha blend | Read only (`glowDepthStencilState`) |
| `airspaceEdgePipeline` | `airspace_vertex` | `airspace_edge_fragment` | Standard alpha blend | Read only (`glowDepthStencilState`) |
| `heatmapPipeline` | `heatmap_vertex` | `heatmap_fragment` | Standard alpha blend | Read only (`glowDepthStencilState`) |

All three follow the **identical** pipeline descriptor pattern as `trailPipeline` / `labelPipeline` / `altLinePipeline`. The blend configuration is copy-pasteable from any of them. The depth stencil state (`glowDepthStencilState`) is already created and reused.

---

## Updated Render Order

Current draw order in `Renderer.draw(in:)`:

```
 1. Terrain mesh tiles (opaque, depth write)
 2. Flat map tile fallbacks (opaque, depth write)
 3. Altitude lines (alpha blend, depth read)
 4. Aircraft bodies (opaque, depth write)
 5. Spinning parts (opaque, depth write)
 6. Trails (alpha blend, depth read)
 7. Labels (alpha blend, depth read)
 8. Airport labels (alpha blend, depth read)
 9. Glow sprites (additive blend, depth read)
```

New draw order with v2.1 features:

```
 1. Terrain mesh tiles (opaque, depth write)
 2. Flat map tile fallbacks (opaque, depth write)
 3. ** HEATMAP OVERLAY (alpha blend, depth read) **    -- ground plane, renders with terrain
 4. Altitude lines (alpha blend, depth read)
 5. ** AIRSPACE FILL (alpha blend, depth read) **      -- large translucent volumes
 6. ** AIRSPACE EDGES (alpha blend, depth read) **     -- wireframe outlines on volumes
 7. Aircraft bodies (opaque, depth write)
 8. Spinning parts (opaque, depth write)
 9. Trails (alpha blend, depth read)
10. Labels (alpha blend, depth read)
11. Airport labels (alpha blend, depth read)
12. Glow sprites (additive blend, depth read)
```

**Rationale:** Heatmap is a ground overlay rendered immediately after terrain. Airspace volumes are large transparent regions at flight altitudes, so they render before opaque aircraft to get correct alpha compositing (translucent objects behind opaque objects need to be drawn first). Aircraft bodies are opaque and write depth, correctly occluding airspace fill behind them.

---

## ThemeConfig Additions

Add to `ThemeConfig` struct in `ThemeManager.swift`:

```swift
// Airspace
let airspaceClassBColor: SIMD4<Float>
let airspaceClassCColor: SIMD4<Float>
let airspaceClassDColor: SIMD4<Float>
let airspaceFillOpacity: Float
let airspaceEdgeOpacity: Float

// Heatmap
let heatmapOpacity: Float
```

Per-theme values (matching web app `AIRSPACE_COLORS` at line 1890 and opacity values at lines 1950-1968):

| Theme | Class B | Class C | Class D | Fill Alpha | Edge Alpha | Heatmap Alpha |
|-------|---------|---------|---------|------------|------------|---------------|
| Day | `(0.27, 0.40, 1.0)` | `(0.60, 0.27, 1.0)` | `(0.27, 0.67, 1.0)` | 0.06 | 0.30 | 0.50 |
| Night | `(0.33, 0.47, 1.0)` | `(0.67, 0.33, 1.0)` | `(0.33, 0.73, 1.0)` | 0.08 | 0.40 | 0.60 |
| Retro | `(0, 1, 0)` | `(0, 1, 0)` | `(0, 1, 0)` | 0.03 | 0.40 | 0.50 |

---

## SettingsView Additions

Add to the Rendering tab in `SettingsView.swift`:

```swift
@AppStorage("showAirspace") private var showAirspace: Bool = false
@AppStorage("showHeatmap") private var showHeatmap: Bool = false
```

Two simple toggles. The airspace and heatmap features are opt-in (off by default) because they add visual complexity and airspace fetching requires network requests.

These values are read from `UserDefaults` in `Renderer.draw(in:)` each frame (same pattern as `trailLength`, `trailWidth`, `altitudeExaggeration` at lines 809-816).

---

## Installation

```bash
# No installation steps. Zero new dependencies.
# All additions are source files within the existing Xcode project:
#
# New Swift files:
#   AirplaneTracker3D/Rendering/AirspaceManager.swift
#   AirplaneTracker3D/Rendering/HeatmapManager.swift
#   AirplaneTracker3D/Rendering/EarClipTriangulator.swift
#
# New Metal shader files:
#   AirplaneTracker3D/Rendering/AirspaceShaders.metal
#   AirplaneTracker3D/Rendering/HeatmapShaders.metal
#
# Modified existing files:
#   AirplaneTracker3D/Rendering/ShaderTypes.h          (new structs, buffer indices)
#   AirplaneTracker3D/Rendering/Renderer.swift          (new pipelines, draw calls)
#   AirplaneTracker3D/Rendering/ThemeManager.swift      (new ThemeConfig fields)
#   AirplaneTracker3D/Rendering/AircraftMeshLibrary.swift (improved models)
#   AirplaneTracker3D/Rendering/AircraftInstanceManager.swift (propeller bug fix)
#   AirplaneTracker3D/Views/SettingsView.swift          (airspace/heatmap toggles)
```

---

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| LibTessSwift / any SPM package | Violates zero-dependency architecture for simple polygons | Pure Swift ear-clipping (~80 lines) |
| Metal compute pipeline for heatmap | 32x32 grid at 0.2 Hz does not justify compute pipeline overhead | CPU grid + `texture.replace()` |
| OIT / image blocks for airspace | Non-overlapping volumes need only simple sorted alpha blend | Back-to-front sorted draw with `glowDepthStencilState` |
| SceneKit ExtrudeGeometry | Adds framework dependency, no Metal pipeline control | Manual extrusion (floor + ceiling + walls) |
| USDZ / OBJ model files | Violates procedural-only model generation architecture | Enhanced `appendCylinder` / `appendBox` / new `appendTrapezoid` |
| Model I/O MDLMesh | Additional framework for primitives already implemented | Existing `AircraftMeshLibrary` helpers |
| Separate render pass / render target | Airspace/heatmap integrate into existing single-pass encoder | Add `encode*()` calls to existing `draw(in:)` method |
| Metal 4 APIs | Ground-up API redesign, macOS 26+ only, not needed | Metal 3 (current stack) |

---

## Sources

**Translucent Rendering:**
- [Metal by Example: Translucency and Transparency](https://metalbyexample.com/translucency-and-transparency/) -- Alpha blending blend factors, depth state configuration, back-to-front sorting (HIGH confidence)
- [Apple: OIT with Image Blocks](https://developer.apple.com/documentation/metal/metal_sample_code_library/implementing_order-independent_transparency_with_image_blocks) -- OIT technique evaluated and rejected for this use case (HIGH confidence)
- [Apple: areRasterOrderGroupsSupported](https://developer.apple.com/documentation/metal/mtldevice/arerasterordergroupssupported) -- Runtime feature detection for OIT (HIGH confidence)
- [Metal Feature Set Tables (PDF)](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf) -- Apple Silicon GPU family 7+ raster order group support confirmed (HIGH confidence)

**Compute Shaders / Texture Processing:**
- [Apple: Processing a texture in a compute function](https://developer.apple.com/documentation/metal/compute_passes/processing_a_texture_in_a_compute_function) -- Compute kernel texture write pattern, evaluated and rejected for 32x32 heatmap (HIGH confidence)

**Polygon Triangulation:**
- [LibTessSwift](https://github.com/LuizZak/LibTessSwift) -- Swift libtess2 wrapper, evaluated and rejected (HIGH confidence)
- [Metal by Example: 3D Text / Extrusion](https://metalbyexample.com/text-3d/) -- Polygon extrusion technique with libtess2, informed our manual extrusion approach (HIGH confidence)

**Airspace Data:**
- [FAA Class Airspace ArcGIS Dataset](https://adds-faa.opendata.arcgis.com/datasets/c6a62360338e408cb1512366ad61559e_0) -- Authoritative airspace boundary data source (MEDIUM confidence on URL stability)
- Web app reference: `airplane-tracker-3d-map.html` lines 1881-2017 -- ArcGIS query construction, polygon rendering, altitude conversion (HIGH confidence)

**Heatmap Reference:**
- Web app reference: `airplane-tracker-3d-map.html` lines 5368-5455 -- Grid accumulation, canvas rendering, color ramps (HIGH confidence)

**Existing Codebase (Primary Source):**
- `Renderer.swift` -- All pipeline state patterns, render order, triple buffering, encode* methods (HIGH confidence)
- `ShaderTypes.h` -- Buffer indices 0-7, all struct layouts, GPU alignment (HIGH confidence)
- `AircraftMeshLibrary.swift` -- Procedural geometry pattern, all primitive helpers (HIGH confidence)
- `AircraftInstanceManager.swift` -- Propeller rotation bug at line 193 (HIGH confidence)
- `MapTileManager.swift` -- Tile fetch/cache pattern, potential issues (HIGH confidence)
- `ThemeManager.swift` -- ThemeConfig pattern, tile URL construction, theme colors (HIGH confidence)
- All 7 `.metal` shader files -- Shader conventions, vertex/fragment patterns (HIGH confidence)

---

*Stack research for: Airplane Tracker 3D -- v2.1 Milestone*
*Researched: 2026-02-09*
