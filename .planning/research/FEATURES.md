# Feature Landscape

**Domain:** v2.1 polish, bug fixes, airspace volumes, and coverage heatmap for native macOS Metal 3D flight tracker
**Researched:** 2026-02-09
**Confidence:** HIGH (existing codebase fully analyzed, web reference implementation reviewed line-by-line, FAA API verified, Metal rendering patterns verified against Apple docs)

---

## Context

This document maps the feature landscape for v2.1 of the native macOS app. The v2.0 app shipped with 42 files and 7,043 LOC. It includes all core visualization features from the web version except two: **airspace volume rendering** and **coverage heatmaps**. Additionally, several bugs need fixing and visual polish is needed.

The v2.1 scope from PROJECT.md:
- **Bug Fixes:** aircraft model rendering (propeller rotation, model quality), map tiles not displaying, restore missing info panel features (position, photo, external links)
- **Missing Features (port from web):** airspace volume rendering (Class B/C/D), coverage heatmap visualization
- **Visual Polish:** improved 3D aircraft model silhouettes, higher-quality terrain rendering (LOD, detail), UI refinement (panel layouts, transitions, label quality)

The existing Metal rendering pipeline has 10+ pipeline states (textured tiles, aircraft, glow, trails, labels, altitude lines, terrain), triple-buffered uniforms, and instanced rendering. New features must integrate into this architecture without disrupting the 60fps budget.

---

## Table Stakes

Features that v2.1 must deliver. These are either bugs (regressions from expectations) or parity gaps with the web version.

### Bug Fixes (Highest Priority)

| Feature | Why Expected | Complexity | Notes |
|---------|-------------|------------|-------|
| Fix map tiles not displaying on ground plane | Users see a blank/placeholder ground plane instead of map imagery. Likely a tile URL or texture upload issue. Without map context, the 3D view is unusable. | Low | Debug tile fetching path in `MapTileManager`. Check URLSession responses, texture creation from PNG data, and texture binding in the render pass. The `tileModelMatrix(for:)` and textured pipeline are in place -- this is a data flow bug, not an architecture gap. |
| Fix aircraft propeller rotation | Propellers on small aircraft spin incorrectly or not at all. The `buildPropeller` mesh creates a single blade pair at nose offset (0, 0, 1.55), and `AircraftInstanceManager` applies `rotationZ(rotorAngle)` -- but the compound matrix `translation * rotation * noseOffset * propRotation` has a no-op `noseOffset` (translates by zero). The propeller mesh's built-in Z-offset means the rotation axis is wrong for visible spinning. | Low | Fix the compound transform so the propeller rotates around its local Z axis at the nose position. The `rotorSpeed` for small props is 0.6 rev/sec (2.4 rad/s) -- may need to be faster for visible blur-like motion. Also verify the propeller geometry is large enough to be visible. |
| Fix aircraft model quality/recognizability | Current procedural models use basic primitives (cylinders, cones, boxes). The jet model at line 265-296 of AircraftMeshLibrary has a cylindrical fuselage (r=0.4, h=4) with box wings (5x0.15x1.5). At typical viewing distances these look like generic blobs. | Med | Improve silhouettes: swept wings (tapered boxes or triangular prisms), tapered fuselages, T-tails for regional jets, distinctive delta wings for military. Keep the primitive-composition approach (no loaded meshes) but refine proportions and add distinguishing features per category. |
| Restore info panel: position, external links | Web version's detail panel shows lat/lon position, links to FlightAware/ADS-B Exchange/planespotters.net. The native `AircraftDetailPanel` already shows lat/lon position but is missing external links. | Low | Add clickable links in AircraftDetailPanel that open in default browser via `NSWorkspace.shared.open(url)`. URLs: `https://flightaware.com/live/flight/{callsign}`, `https://globe.adsbexchange.com/?icao={hex}`, `https://www.planespotters.net/hex/{hex}`. |
| Restore info panel: aircraft photo | Web version fetches aircraft photos from planespotters.net. The native panel shows enrichment data (registration, type, operator, route) but no photo. | Med | Fetch photo URL from planespotters.net API or use hexdb.io photo endpoint. Display as async `AsyncImage` in SwiftUI detail panel. Cache with URLCache. Consider fallback placeholder if no photo available. |

### Feature Parity (Port from Web)

| Feature | Why Expected | Complexity | Notes |
|---------|-------------|------------|-------|
| Airspace volume rendering (Class B/C/D) | The web version renders FAA-sourced airspace boundaries as semi-transparent extruded 3D volumes with wireframe edges. This is the single most-requested feature for understanding the context around aircraft. Without it, users cannot see why aircraft follow specific approach patterns. | High | Full implementation details in Architecture section below. Requires: (1) FAA ArcGIS API client, (2) GeoJSON polygon parsing, (3) polygon triangulation (ear clipping), (4) extruded mesh generation on CPU, (5) new transparent pipeline state with alpha blending and depth-write disabled, (6) new Metal shader pair, (7) per-class coloring, (8) integration into Renderer draw loop after terrain but before aircraft. |
| Coverage heatmap visualization | The web version accumulates aircraft positions into a 20x20 grid and renders a 2D canvas heatmap showing where aircraft have been detected. For users with local ADS-B receivers, this shows antenna coverage patterns and dead zones. | Med | Two options: (A) 2D SwiftUI Canvas overlay -- simpler, matches web version's approach of a small overlay panel. (B) 3D ground-plane heatmap texture -- more visually integrated but requires a new render pass. Recommend option A for v2.1: SwiftUI Canvas with a 20x20 grid, theme-aware colors (blue/green gradient for day/night, green gradient for retro). Accumulate positions per frame in a `[Int]` array. |

---

## Differentiators

Features that go beyond web version parity and add real value. Not strictly required for v2.1 but achievable within the polish scope.

### Visual Polish

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Improved aircraft silhouettes | Better recognizability at a glance. Current models are basic primitive compositions. Swept wing angles, tapered fuselages, and distinctive tail shapes make each category immediately identifiable -- especially important in retro wireframe mode where color cues are absent. | Med | Modify `AircraftMeshLibrary` builders. Jet: 30-degree swept wings via `appendBox` with rotated corners or custom vertex arrays. Widebody: wider fuselage, larger engines, 2+2 engine layout. Military: proper delta wing (triangular prism, not box). Helicopter: larger cabin sphere, visible skid detail. Regional: high-wing mount, T-tail. Keep vertex count under 500 per type for instancing budget. |
| Terrain LOD (level of detail) | Current terrain uses uniform 32x32 subdivision per tile regardless of distance. Distant tiles waste vertices. Reducing distant subdivision to 16x16 or 8x8 saves significant vertex processing and allows higher near-camera detail (64x64). | Med | Add distance-based subdivision selection in `TerrainTileManager.buildTerrainMesh`. Near camera: 48x48 or 64x64 subdivisions. Mid-range: 32x32 (current). Far: 16x16. Based on tile distance from camera center. |
| Airspace class filter toggles | Web version has per-class toggles (B/C/D) so users can show only the airspace they care about. Aviation enthusiasts expect this control. | Low | Add toggle buttons or Settings checkboxes for Class B, C, D visibility. Store in `@AppStorage`. Pass filter state to `AirspaceVolumeManager`. |
| Airspace volume labels | Web version stores `NAME` and `ICAO_ID` per volume (e.g., "SEATTLE CLASS B", "KSEA"). Showing the airspace name when hovering or at the center of the volume helps users identify which airport's airspace they are seeing. | Low | Render a billboard label at the centroid of each airspace polygon, similar to existing airport labels. Reuse `LabelManager` infrastructure. |
| Info panel: data source indicator | Show whether data is coming from local dump1090 or global API, and which provider (airplanes.live vs adsb.lol) is active. Users troubleshooting connectivity need this. | Low | Add a status line to `InfoPanel` showing current data source. Read from `UserDefaults` or observe `FlightDataManager` state. |
| Smoother panel transitions | Current panel show/hide uses basic SwiftUI `.transition(.move)`. Adding spring animations and matched geometry effects would feel more polished. | Low | Replace `.easeInOut(duration: 0.25)` with `.spring(response: 0.35, dampingFraction: 0.85)`. Add `.matchedGeometryEffect` for aircraft detail panel appearing from the selected aircraft's screen position. |

---

## Anti-Features

Features to explicitly NOT build in v2.1. These are tempting scope expansions that would derail the milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Loaded 3D aircraft models (glTF/OBJ) | Breaks instanced rendering (all instances of a type must share one vertex buffer). Asset pipeline complexity is enormous. Loading, converting, LOD-ing per-aircraft models for 500+ simultaneous aircraft is a different architectural paradigm. | Improve procedural geometry in `AircraftMeshLibrary`. Better silhouettes with the same primitive-composition approach. This preserves instanced draw calls. |
| Weather radar overlay | Massive scope: tile source for weather data, temporal animation, transparency compositing with map tiles, refresh intervals, API costs. Not part of a flight tracker's core loop. | Defer to v2.2+. If users need weather, they can use a separate weather app alongside. |
| Flight path prediction (extrapolated dashed line) | Requires accurate heading-hold assumption (invalid for turning aircraft), speed model, and adds visual clutter. Web version never implemented it. | Keep focus on historical trails which are proven valuable. |
| Order-independent transparency (OIT) for airspace | Apple's Metal provides OIT via tile shaders and image blocks (A11+ GPUs). However, the complexity is extreme for the visual benefit. Airspace volumes are large, non-overlapping within a class, and rendered at very low opacity (6%). Sorting errors would be barely visible. | Use simple back-to-front sorting by airspace class (D first, then C, then B). Render after opaque geometry, before aircraft. Disable depth writes. The visual result is indistinguishable from OIT at 6% opacity. |
| 3D heatmap (elevated colored columns) | Looks cool in demos but adds visual clutter to an already dense scene. Occludes aircraft and terrain. The web version uses a 2D canvas overlay for good reason. | 2D SwiftUI Canvas overlay in the statistics panel area. Clean, unobtrusive, matches web version's proven UX. |
| Airspace from non-FAA sources (EUROCONTROL, etc.) | Massively different data format, different classification system (ICAO vs. FAA), different APIs. Multi-region airspace support is a v3.0 feature. | Hard-code FAA ArcGIS FeatureServer endpoint. This covers US, Puerto Rico, and Virgin Islands. International users see no airspace -- acceptable for v2.1. |
| GPU-based polygon triangulation | Compute shader ear clipping sounds elegant but polygon count is low (typically 8-30 vertices per airspace boundary). CPU triangulation is instant. | Simple ear-clipping on CPU. The `airspaceData` typically has <500 features, each with <50 vertices. Total triangulation time: <10ms. |

---

## Feature Dependencies

```
[v2.1 Bug Fixes]
    |
    +-> [Map Tile Fix] -- standalone, no dependencies
    |     Root cause: debug tileManager.texture(for:) returning nil
    |
    +-> [Propeller Fix] -- standalone, modify AircraftInstanceManager compound transform
    |
    +-> [Model Quality] -- standalone, modify AircraftMeshLibrary builders
    |
    +-> [Info Panel Links] -- depends on: existing AircraftDetailPanel, NSWorkspace
    |
    +-> [Info Panel Photo] -- depends on: EnrichmentService (add photo URL fetch)

[Airspace Volume Rendering] -- largest new feature
    |
    +-> [AirspaceDataService] -- FAA ArcGIS API client
    |     +-> Fetches GeoJSON for visible map bounds
    |     +-> Caches airspace data per region
    |     +-> Triggers re-fetch when camera moves significantly
    |
    +-> [AirspaceVolumeManager] -- mesh generation
    |     +-> Polygon triangulation (ear clipping)
    |     +-> Extruded mesh generation (floor-to-ceiling)
    |     +-> Metal buffer creation (vertex + index)
    |     +-> LRU cache for generated meshes
    |
    +-> [Airspace Pipeline State] -- new Metal pipeline
    |     +-> Alpha blending enabled (sourceAlpha, oneMinusSourceAlpha)
    |     +-> Depth write disabled (read-only depth test)
    |     +-> New shader pair: airspace_vertex, airspace_fragment
    |     +-> Per-volume color uniform (B=blue, C=purple, D=cyan)
    |
    +-> [Renderer Integration] -- encode after terrain, before aircraft
    |     +-> encodeAirspaceVolumes() method
    |     +-> Theme-aware coloring (retro: green)
    |
    +-> [Settings Toggle] -- @AppStorage("showAirspace")
    +-> [Class Filter] -- @AppStorage("airspaceClassB/C/D")

[Coverage Heatmap]
    |
    +-> [HeatmapAccumulator] -- grid data model
    |     +-> 20x20 Int array, accumulate from InterpolatedAircraftState
    |     +-> Clear/reset capability
    |     +-> Normalize for rendering (0.0-1.0 range)
    |
    +-> [HeatmapView] -- SwiftUI Canvas
    |     +-> Theme-aware color gradient
    |     +-> Toggle visibility from stats panel or settings
    |
    +-> [Settings Toggle] -- @AppStorage("showHeatmap")

[Visual Polish] -- independent improvements
    +-> [Aircraft Silhouettes] -- AircraftMeshLibrary only
    +-> [Terrain LOD] -- TerrainTileManager only
    +-> [Panel Animations] -- ContentView transitions only
```

### Critical Path for v2.1

Ordering by risk and dependency:

1. **Bug fixes first** -- map tiles, propeller, model quality (unblocks user testing)
2. **Info panel restoration** -- links, photo (quick wins, visible improvement)
3. **Airspace volumes** -- largest feature, most implementation risk
4. **Coverage heatmap** -- simpler feature, can run in parallel with airspace
5. **Visual polish** -- terrain LOD, panel transitions (finishing touches)

---

## Airspace Volume Rendering: Deep Dive

This is the highest-complexity feature in v2.1. Here is the detailed breakdown.

### Data Source

The web version uses the FAA AIS Open Data FeatureServer:
```
https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services/Class_Airspace/FeatureServer/0/query
```

Query parameters:
- `where=CLASS+IN+('B','C','D')` -- filter to controlled airspace classes
- `geometry={west},{south},{east},{north}` -- bounding box of visible area
- `geometryType=esriGeometryEnvelope` -- bounding box spatial filter
- `inSR=4326` -- WGS84 coordinate system
- `spatialRel=esriSpatialRelIntersects` -- return features that intersect the box
- `outFields=NAME,CLASS,LOCAL_TYPE,UPPER_VAL,LOWER_VAL,UPPER_UOM,LOWER_UOM,ICAO_ID`
- `f=geojson` -- GeoJSON output format
- `resultRecordCount=500` -- limit to 500 features per request

Confidence: HIGH -- this exact URL is used in the working web version (line 1883-1905 of the HTML file).

### Visual Specification

From the web version (lines 1918-1984):

| Property | Class B | Class C | Class D |
|----------|---------|---------|---------|
| Fill color | `#4466ff` (blue) | `#9944ff` (purple) | `#44aaff` (cyan) |
| Fill opacity | 6% | 6% | 6% |
| Edge opacity | 30% | 30% | 30% |
| Render order | 3 (front) | 2 (middle) | 1 (back) |
| Retro override | Green fill 3%, green edge 40% | Same | Same |

Geometry: 2D polygon outline from GeoJSON, extruded from `LOWER_VAL` (floor altitude) to `UPPER_VAL` (ceiling altitude). Altitude conversion: if `UOM == "FL"`, multiply by 100 to get feet. Then apply the same altitude scale factor as aircraft (0.001 world units per foot).

Shape: Class B airspace looks like an inverted wedding cake (multiple stacked shelves of increasing radius). Each shelf is a separate GeoJSON feature with its own floor/ceiling. Class C is typically two concentric rings. Class D is a simple cylinder. All are rendered as separate extruded polygons.

### Metal Implementation Pattern

New pipeline state (similar to existing glow pipeline):
- Alpha blending: source * sourceAlpha + dest * (1 - sourceAlpha)
- Depth compare: lessEqual (read depth, so volumes are occluded by terrain)
- Depth write: disabled (volumes are see-through)
- Cull mode: none (render both faces for transparency from inside)
- Triangle fill mode: fill (not wireframe, even in retro -- wireframe volumes look broken)

New shader pair in `AirspaceShaders.metal`:
- `airspace_vertex`: transforms position by view-projection, passes color
- `airspace_fragment`: returns color with very low alpha (0.06) for fill faces, higher alpha (0.3) for edge faces

Wireframe edges rendered as a separate draw call using the same vertex data but with `setTriangleFillMode(.lines)` or as `EdgesGeometry`-equivalent (extract unique edges, render as line primitives).

### Polygon Triangulation

The GeoJSON coordinates describe 2D polygon outlines (lat/lon pairs). To create a filled mesh, these must be triangulated.

Approach: **Ear clipping algorithm** -- simple, robust for the typical airspace polygons (convex or mildly concave, no holes, 8-30 vertices). Implementation:
1. Convert polygon coordinates to 2D (project to XZ plane since Y is altitude)
2. Run ear clipping to produce triangle indices
3. Create extruded mesh: top face + bottom face + side quads connecting top/bottom edges

Alternative: Use the existing `appendCylinder`-style approach from AircraftMeshLibrary but with arbitrary polygon cross-sections instead of circular ones. The extrusion logic is the same -- two parallel copies of the polygon connected by quad strips on the sides.

### Performance Budget

- Typical airspace query returns 50-200 features
- Each feature has 8-30 boundary vertices
- Triangulated mesh per feature: ~100-300 triangles (top + bottom + sides)
- Total triangle count: ~10K-50K for a dense area
- This is trivial for Metal -- fewer triangles than the terrain mesh

Regeneration: only when camera moves significantly (similar to tile loading). Cache generated meshes keyed by GeoJSON feature ID. Invalidate when airspace toggle changes.

---

## Coverage Heatmap: Deep Dive

### Data Accumulation

From the web version (lines 5368-5377):
- Maintain a `[Int]` array of 20x20 = 400 cells
- Each frame, for each aircraft with valid lat/lon:
  - Normalize lat/lon to 0-1 range within current map bounds
  - Map to grid cell index: `gridX = floor(normX * 20)`, `gridY = floor(normY * 20)`
  - Increment: `heatmap[gridY * 20 + gridX] = min(255, heatmap[idx] + 1)`
- Reset capability (clear all cells)

### Rendering

Recommend **SwiftUI Canvas** overlay (matches web version's 2D canvas approach):

```
Canvas { context, size in
    let cellW = size.width / 20
    let cellH = size.height / 20
    let maxVal = max(heatmap.max() ?? 1, 1)

    for y in 0..<20 {
        for x in 0..<20 {
            let intensity = Double(heatmap[y * 20 + x]) / Double(maxVal)
            let color = themeHeatmapColor(intensity)
            context.fill(
                Path(CGRect(x: Double(x) * cellW, y: Double(19 - y) * cellH, width: cellW - 1, height: cellH - 1)),
                with: .color(color)
            )
        }
    }
}
```

Theme colors (from web version lines 5444-5450):
- Day: `rgba(0, 100+155*i, 255*i, 0.2+i*0.8)` -- blue-to-cyan gradient
- Night: `rgba(0, 180+75*i, 255*i, 0.2+i*0.8)` -- cyan-to-white gradient
- Retro: `rgba(0, 255*i, 0, 0.2+i*0.8)` -- green gradient

### Placement

Show as a small overlay (160x160 points) within the statistics panel area, or as a standalone toggle. Title: "Signal Coverage" for local mode, "Aircraft Coverage" for global mode.

---

## MVP Recommendation

### Must-Have for v2.1 Ship

1. **Map tile bug fix** -- without map tiles, the app is broken
2. **Propeller rotation fix** -- visible rendering bug
3. **Aircraft model improvements** -- better silhouettes for the 6 categories
4. **Info panel external links** -- 3 clickable URLs (FlightAware, ADSB Exchange, Planespotters)
5. **Airspace volume rendering** -- the flagship v2.1 feature, completes web parity
6. **Coverage heatmap** -- completes web parity
7. **Airspace toggle in Settings** -- users need to turn it on/off

### Nice-to-Have for v2.1

8. **Aircraft photo in detail panel** -- async image loading, adds visual richness
9. **Terrain LOD** -- performance optimization, not user-visible
10. **Airspace class filter toggles** -- power user feature
11. **Panel animation polish** -- spring animations, subtle improvement
12. **Airspace volume labels** -- names on airspace boundaries

### Defer to v2.2

- Weather overlays
- Flight path prediction
- Desktop Widgets (WidgetKit)
- Spotlight/Shortcuts integration
- Multiple window support improvements
- GPU compute frustum culling
- Post-processing bloom

---

## Sources

### Existing Codebase Analysis (HIGH confidence)
- Full review of all 42 Swift files in AirplaneTracker3D/
- `Renderer.swift` (1060 lines): 10+ pipeline states, render loop, encoding methods
- `AircraftMeshLibrary.swift` (497 lines): 6 body meshes + rotor + propeller, procedural primitives
- `AircraftInstanceManager.swift` (294 lines): triple-buffered instancing, category batching
- `TerrainTileManager.swift` (322 lines): AWS Terrarium tile decoding, 32x32 mesh generation
- `ShaderTypes.h` (109 lines): all shared GPU data structures
- `airplane-tracker-3d-map.html` lines 1880-2017: airspace volume implementation
- `airplane-tracker-3d-map.html` lines 5368-5455: coverage heatmap implementation

### FAA Data Source (HIGH confidence)
- [FAA AIS Open Data: Class Airspace](https://adds-faa.opendata.arcgis.com/datasets/c6a62360338e408cb1512366ad61559e_0)
- Verified FeatureServer URL active and returning GeoJSON as of research date
- Web version line 1883 uses `services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services/Class_Airspace/FeatureServer/0`

### Metal Rendering Patterns (HIGH confidence)
- [Metal by Example: Translucency and Transparency](https://metalbyexample.com/translucency-and-transparency/) -- alpha blending, back-to-front sorting
- [Apple: Order-Independent Transparency with Image Blocks](https://developer.apple.com/documentation/metal/metal_sample_code_library/implementing_order-independent_transparency_with_image_blocks) -- OIT reference (decided against for v2.1)
- [Apple: MTLBlendFactor](https://developer.apple.com/documentation/metal/mtlblendfactor) -- blend factor documentation

### Airspace Visualization Domain (MEDIUM confidence)
- [Pilot Institute: Airspace Classes Explained](https://pilotinstitute.com/airspace-explained/) -- Class B "inverted wedding cake", Class C concentric rings, Class D cylinder
- [3D Airspace visualization](https://3d-airspace.vercel.app/) -- interactive FAA airspace viewer
- [3D Airspace Google Earth](https://3dairspace.org.uk/) -- reference for visual appearance

### Heatmap & Coverage Domain (MEDIUM confidence)
- [tar1090: Advanced Features (heatmap)](https://deepwiki.com/wiedehopf/tar1090/5-advanced-features) -- heatmap density visualization
- [ADS-B Heatmap](https://adsb-heatmap.com/) -- standalone heatmap tool
- [FlightAware ADS-B Coverage Map](https://www.flightaware.com/adsb/coverage) -- reference for coverage visualization
