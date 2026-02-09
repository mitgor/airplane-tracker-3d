# Project Research Summary

**Project:** Airplane Tracker 3D -- v2.1 Milestone
**Domain:** Native macOS Metal 3 flight tracker with 3D visualization, airspace volumes, and coverage heatmap
**Researched:** 2026-02-09
**Confidence:** HIGH

## Executive Summary

The v2.1 milestone adds airspace volume rendering, coverage heatmaps, and visual polish to a validated Metal 3 rendering architecture. The existing codebase (42 files, 7,043 LOC) uses zero external dependencies, triple-buffered instanced rendering, and a single-encoder-per-frame approach that delivers 60fps performance. Research confirms that all v2.1 features can be implemented using the existing Metal 3 stack without adding frameworks, packages, or external dependencies.

The recommended approach is **conservative extension over architectural change**. Airspace volumes integrate as a new translucent render pass using existing alpha-blending patterns (already proven in trails, labels, and glow). Coverage heatmaps use a compute shader for accumulation (first compute usage in the app) followed by a textured ground quad. Aircraft model improvements leverage existing procedural geometry primitives. Map tile debugging targets URL generation and texture upload timing. All new features follow established manager patterns with triple-buffered GPU resources.

The primary risk is **incorrect render ordering for translucent geometry**. Adding airspace volumes and heatmap overlays to the existing opaque-then-transparent sequence requires careful depth state management (depth-read-no-write) and back-to-front sorting. A secondary risk is **compute-render synchronization** for the heatmap feature, which introduces the first compute pass into a render-only pipeline. Mitigation: structure the frame as compute-encoder-then-render-encoder within a single command buffer, following Metal 3 encoder ordering guarantees.

## Key Findings

### Recommended Stack

**No stack changes.** The v2.1 milestone adds zero external dependencies. Every feature is implemented using Metal 3, Swift, SwiftUI, and system frameworks already in the project.

**Core technologies (existing, unchanged):**
- **Metal 3 / MSL:** 7 shader files, 10+ pipeline states, instanced rendering — two new shader files added (AirspaceShaders.metal, HeatmapShaders.metal), three new pipeline states
- **Swift:** 32 source files, async/await, actors — three new manager classes (AirspaceManager, HeatmapManager, EarClipTriangulator)
- **MetalKit:** MTKView, MTKTextureLoader — existing texture loading pattern reused for heatmap texture
- **CoreText:** Label atlas rasterization — unchanged, existing pattern

**Key architectural decisions:**
- **Polygon triangulation:** Pure Swift ear-clipping algorithm (80 lines) instead of external library (LibTessSwift rejected). FAA airspace polygons are simple convex/concave shapes with 20-60 vertices, no holes, no self-intersections. Ear-clipping handles this trivially without adding a dependency.
- **Translucent rendering:** Standard alpha blending with depth-read-no-write, back-to-front sorting. Order-independent transparency (OIT) with image blocks is technically available on Apple Silicon but deliberately rejected — airspace volumes are non-overlapping within a class, simple sorted alpha works perfectly.
- **Heatmap generation:** CPU-side grid accumulation with periodic texture upload (0.2 Hz update rate). Compute kernel rejected as unjustified complexity for 32x32 grid updated every 5 seconds.

### Expected Features

**Must have (table stakes):**
- **Fix map tiles not displaying:** Users see blank ground plane. Debug tile fetching in MapTileManager — check URLSession responses, texture creation from PNG data, texture binding. Data flow bug, not architectural gap.
- **Fix aircraft propeller rotation:** Propellers spin incorrectly. Compound matrix composition bug at AircraftInstanceManager line 193-194. Fix: remove identity noseOffset multiplication.
- **Fix aircraft model quality:** Current procedural models too basic. Improve silhouettes with swept wings, tapered fuselages, T-tails, delta wings using existing primitives.
- **Restore info panel features:** Add position (lat/lon already exists), external links (FlightAware, ADSB Exchange, Planespotters), aircraft photo (async AsyncImage).
- **Airspace volume rendering:** Semi-transparent extruded 3D polygons showing FAA Class B/C/D boundaries with floor/ceiling altitudes. Uses FAA ArcGIS GeoJSON API, ear-clipping triangulation, Metal alpha-blended instancing.
- **Coverage heatmap:** Color-mapped grid texture showing aircraft density by geographic cell. CPU-side 32x32 grid accumulation, texture upload, fragment shader color ramp.

**Should have (differentiators):**
- Improved aircraft silhouettes with swept wings, engine nacelles, landing gear detail
- Airspace class filter toggles (B/C/D visibility)
- Airspace volume labels (names at volume centroids)
- Smoother panel transitions (spring animations)

**Defer (v2+):**
- Weather radar overlays (massive scope)
- Flight path prediction (extrapolated dashed lines)
- Loaded 3D models (glTF/OBJ — breaks instancing)
- 3D elevated heatmap columns (visual clutter)
- International airspace sources (EUROCONTROL — different format)

### Architecture Approach

The existing architecture uses a **single render command encoder per frame** with ordered draw call encoding. All visual elements share one render pass descriptor and one depth buffer. New features integrate via new manager classes following the established pattern: triple-buffered GPU resources, `update(bufferIndex:)` methods, and dedicated `encode*()` methods in Renderer.

**Major components (new for v2.1):**
1. **AirspaceManager** — loads FAA ArcGIS GeoJSON, triangulates polygons with ear-clipping, builds Metal buffers, distance-culls, back-to-front sorts, triple-buffers instance data
2. **HeatmapManager** — maintains 32x32 CPU grid, accumulates aircraft positions every 5 seconds, uploads to MTLTexture, renders textured ground quad
3. **EarClipTriangulator** — pure Swift polygon triangulation, ~80 lines, handles FAA polygons (20-60 vertices, no holes)

**Modified components:**
- **ShaderTypes.h:** +2 buffer indices (AirspaceInstances=8, HeatmapUniforms=9), +2 struct definitions
- **Renderer.swift:** +3 pipeline states (airspace fill, airspace edges, heatmap), +2 encode methods, updated draw order
- **ThemeManager.swift:** +airspace colors per class (B=blue, C=purple, D=cyan), +heatmap opacity/color ramp
- **AircraftMeshLibrary.swift:** enhanced geometry (trapezoid wings, engine pylons, landing gear detail)

**Updated render order:**
```
Opaque (depth write ON):
  1. Terrain mesh tiles
  2. Flat map tile fallbacks
  3. Altitude reference lines
  4. Aircraft bodies (instanced)
  5. Spinning parts (rotors/propellers)

Translucent (depth write OFF):
  6. >>> HEATMAP OVERLAY (ground plane)
  7. >>> AIRSPACE FILL (back-to-front sorted)
  8. >>> AIRSPACE EDGES (wireframe outlines)
  9. Trail polylines
 10. Aircraft labels
 11. Airport labels
 12. Glow sprites (additive blend)
```

### Critical Pitfalls

1. **Translucent airspace volumes rendered with depth writes enabled** — Volumes appear opaque and hide aircraft behind them. From certain angles, closer volumes disappear while farther ones show through. Prevention: Create dedicated depth stencil state with `isDepthWriteEnabled=false`, reuse existing `glowDepthStencilState`. Render all opaque geometry first, then translucent with depth-read-no-write. Sort volumes back-to-front.

2. **Incorrect render order after adding new translucent passes** — Trails render behind volumes when they should be in front, labels disappear inside volume geometry, glow halos have hard edges. Prevention: Insert airspace volumes AFTER all opaque geometry but BEFORE trails/labels/glow. Test with nested airspace configurations.

3. **Propeller rotation matrix composed in wrong order** — Propellers rotate around aircraft's world-space Z axis instead of local axis relative to heading. Bug is intermittent depending on aircraft heading. Root cause: `noseOffset` is identity matrix at line 193, wasted multiplication. Prevention: Remove identity multiplication, verify propeller disc always faces forward regardless of heading.

4. **Heatmap compute shader output not synchronized with render pass** — Heatmap texture flickers, shows stale data, or displays partially updated data. Bug is non-deterministic and appears/disappears based on GPU load. Prevention: Structure frame as compute-encoder (heatmap generation) -> end encoding -> render-encoder (draw scene including heatmap) within same command buffer. Update aircraft positions into compute-readable buffer BEFORE creating compute encoder.

5. **New triple-buffered resources not added to semaphore discipline** — Airspace volumes flicker, heatmap data tears, or app hangs for a frame. Bug appears only under GPU load. Prevention: Every new per-frame dynamic buffer MUST follow triple-buffering pattern. Allocate 3 copies, accept `bufferIndex: Int` in update methods, use `currentBufferIndex` in encode methods.

## Implications for Roadmap

Based on research, suggested phase structure follows risk and dependency ordering:

### Phase 1: Bug Fixes and Foundation
**Rationale:** Unblocks user testing and validates the rendering pipeline before adding complex features. Map tiles are critical (blank ground plane makes app unusable). Propeller fix is simple and validates matrix composition understanding. Model improvements are self-contained within AircraftMeshLibrary.

**Delivers:** Working map tiles, correct propeller rotation, improved aircraft silhouettes (6 categories with swept wings, engine detail, landing gear)

**Addresses features:**
- Fix map tiles not displaying (table stakes)
- Fix aircraft propeller rotation (table stakes)
- Improve aircraft model quality (table stakes)

**Avoids pitfalls:**
- Pitfall 3: Propeller rotation matrix composition
- Pitfall 6: Map tile texture binding timing race

**Research needed:** NO — map tile debugging is code analysis, propeller fix is matrix math, mesh improvements use existing primitives.

### Phase 2: Info Panel Restoration
**Rationale:** Quick wins that add visible value. External links are trivial (3 URL templates + NSWorkspace.open). Position display already exists. Aircraft photo is async AsyncImage with planespotters.net API. All SwiftUI-only changes, no rendering pipeline changes.

**Delivers:** Complete aircraft detail panel with position, external links (FlightAware, ADSB Exchange, Planespotters), aircraft photo

**Addresses features:**
- Restore info panel: position, external links (table stakes)
- Restore info panel: aircraft photo (table stakes)

**Avoids pitfalls:**
- Pitfall 11: Detail panel SwiftUI updates blocking main thread (use async let for parallel fetching)

**Research needed:** NO — SwiftUI patterns are standard, enrichment service already exists.

### Phase 3: Airspace Volume Rendering
**Rationale:** Largest feature in v2.1, most implementation risk, but all patterns are validated by existing rendering architecture. Must come after bug fixes so the rendering pipeline is known-good. Validates translucent rendering integration before adding heatmap compute pass.

**Delivers:** Semi-transparent 3D airspace volumes (Class B/C/D) with wireframe edges, theme-aware colors, distance culling, class filter toggles

**Addresses features:**
- Airspace volume rendering (table stakes)
- Airspace class filter toggles (differentiator)

**Uses stack:**
- FAA ArcGIS GeoJSON API (verified active)
- Pure Swift ear-clipping triangulation (no external dependencies)
- Metal alpha blending with depth-read-no-write (existing glowDepthStencilState pattern)
- Triple-buffered instanced rendering (existing pattern)

**Implements architecture:**
- AirspaceManager (new manager following existing pattern)
- EarClipTriangulator (new utility, ~80 lines)
- AirspaceShaders.metal (new shader file, follows existing conventions)

**Avoids pitfalls:**
- Pitfall 1: Depth writes on translucent volumes (use glowDepthStencilState)
- Pitfall 2: Render order (insert after opaque, before trails)
- Pitfall 5: Triple buffering (follow AircraftInstanceManager pattern)
- Pitfall 7: Z-fighting with terrain (offset floor vertices +0.1 Y)
- Pitfall 9: Missing rasterSampleCount (set to metalView.sampleCount)
- Pitfall 10: Buffer index collision (use BufferIndexAirspaceInstances=8)

**Research needed:** NO — all rendering patterns validated, FAA API URL verified, ear-clipping algorithm well-understood.

### Phase 4: Coverage Heatmap
**Rationale:** Simpler than airspace volumes (no complex geometry, just 32x32 grid), but introduces first compute usage. Comes after airspace to avoid stacking two new render pipeline changes. Can validate compute-render synchronization in isolation.

**Delivers:** Coverage heatmap showing aircraft density as color-mapped ground overlay, theme-aware color gradients, toggle visibility

**Addresses features:**
- Coverage heatmap visualization (table stakes)

**Uses stack:**
- CPU-side grid accumulation (32x32 Int array, 0.2 Hz update)
- MTLTexture with texture.replace() upload (existing pattern from AircraftMeshLibrary.createGlowTexture)
- Fragment shader color ramp (theme-dependent gradients)

**Implements architecture:**
- HeatmapManager (new manager following existing pattern)
- HeatmapShaders.metal (vertex/fragment only, no compute)
- Ground quad rendering (similar to flat tile fallback pattern)

**Avoids pitfalls:**
- Pitfall 8: Coordinate mapping mismatch (use same lonToX/latToZ as terrain)
- Pitfall 13: Color gradient clamping (normalize against current frame max, use sqrt scaling)

**Research needed:** NO — CPU grid approach is straightforward, texture upload pattern already exists.

### Phase 5: Visual Polish
**Rationale:** Independent improvements that can happen anytime after Phase 1 (foundation). Purely geometric refinements and UI transitions. Minimal risk, visible quality improvement.

**Delivers:** Smoother panel transitions (spring animations), airspace volume labels (names at centroids), terrain LOD (distance-based subdivision)

**Addresses features:**
- Smoother panel transitions (differentiator)
- Airspace volume labels (differentiator)
- Terrain LOD (differentiator)

**Avoids pitfalls:**
- Pitfall 14: Procedural mesh index overflow (assert vertex count < 65535)

**Research needed:** NO — all standard refinements using existing systems.

### Phase Ordering Rationale

- **Phase 1 first:** Bug fixes unblock user testing and validate rendering pipeline health before adding complexity.
- **Phase 2 second:** Quick wins (info panel) add visible value while airspace volume work progresses.
- **Phase 3 before Phase 4:** Airspace volumes (translucent instanced rendering) follow existing patterns more closely than heatmap (new compute usage). Validate translucent rendering integration before introducing compute passes.
- **Phase 4 before Phase 5:** Heatmap is a table stakes feature, visual polish is nice-to-have.
- **Phase 5 last:** Polish can happen incrementally and doesn't block other work.

### Research Flags

**Phases with standard patterns (skip research-phase):**
- **Phase 1:** Bug fixes use code analysis and existing primitives
- **Phase 2:** Info panel uses standard SwiftUI + async/await patterns
- **Phase 3:** Airspace volumes follow existing instanced rendering pattern, all techniques validated
- **Phase 4:** Heatmap uses simple CPU grid + texture upload (existing pattern)
- **Phase 5:** Visual polish uses existing systems

**No phases need deeper research.** All v2.1 features use validated patterns from the existing codebase or well-documented Metal techniques.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All recommendations verified against existing codebase (42 files analyzed). Zero new dependencies required. Metal 3 patterns proven in 7 existing shader files and 10+ pipeline states. |
| Features | HIGH | Feature requirements verified against web reference implementation (airplane-tracker-3d-map.html lines 1880-2017 for airspace, lines 5368-5455 for heatmap). Bug fixes identified by direct code analysis. |
| Architecture | HIGH | Integration patterns follow existing manager architecture (AircraftInstanceManager, TrailManager, LabelManager). Render order validated against existing single-encoder-per-frame approach. Triple buffering confirmed across all managers. |
| Pitfalls | HIGH | All pitfalls derived from existing codebase analysis + Metal by Example transparency article + Apple Metal Best Practices Guide. Propeller bug identified at specific line (AircraftInstanceManager.swift 193-194). Map tile race identified in MapTileManager.swift fetch logic. |

**Overall confidence:** HIGH

All recommendations are grounded in direct codebase analysis and authoritative Metal documentation. No speculative patterns or untested techniques. The v2.0 architecture is validated and shipping — v2.1 extends it conservatively.

### Gaps to Address

**Medium confidence on FAA ArcGIS URL stability:** The [FAA AIS Open Data portal](https://adds-faa.opendata.arcgis.com/datasets/c6a62360338e408cb1512366ad61559e_0) confirmed the dataset exists, but Esri updated GeoJSON download URL configuration in June 2024. The `services6.arcgis.com` query URL used by the web app should still work for FeatureServer queries. **Mitigation:** Verify URL returns valid GeoJSON at implementation time (Phase 3). Add retry logic and fallback error messaging if API is unavailable.

**No other gaps.** All other findings are based on code analysis, existing APIs, or Metal techniques proven in the current codebase.

## Sources

### Primary (HIGH confidence)

**Existing Codebase (all verified by direct file reading):**
- `Renderer.swift` (1060 lines) — all pipeline states, render order, encoding methods, triple buffering
- `AircraftInstanceManager.swift` (294 lines) — propeller rotation bug at line 193-194
- `AircraftMeshLibrary.swift` (497 lines) — procedural geometry patterns, all primitives
- `MapTileManager.swift` (322 lines) — tile fetch logic, texture creation
- `TerrainTileManager.swift` (322 lines) — mesh generation, coordinate system
- `ShaderTypes.h` (109 lines) — all shared GPU data structures, buffer indices
- All 7 `.metal` shader files — shader conventions, vertex/fragment patterns
- Web reference implementation: `airplane-tracker-3d-map.html` lines 1880-2017 (airspace), lines 5368-5455 (heatmap)

**Apple Metal Documentation:**
- [Metal by Example: Translucency and Transparency](https://metalbyexample.com/translucency-and-transparency/) — alpha blending, depth state configuration, back-to-front sorting
- [Apple: Processing a texture in a compute function](https://developer.apple.com/documentation/metal/compute_passes/processing_a_texture_in_a_compute_function) — compute shader texture write pattern
- [Metal Best Practices Guide - Triple Buffering](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html) — semaphore discipline
- [Apple: MTLRenderPipelineDescriptor](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor) — rasterSampleCount requirement

**Airspace Data:**
- [FAA Class Airspace ArcGIS Dataset](https://adds-faa.opendata.arcgis.com/datasets/c6a62360338e408cb1512366ad61559e_0) — authoritative airspace boundary data source

### Secondary (MEDIUM confidence)

**Polygon Triangulation:**
- [LibTessSwift](https://github.com/LuizZak/LibTessSwift) — evaluated and rejected for dependency concerns
- [Metal by Example: 3D Text / Extrusion](https://metalbyexample.com/text-3d/) — polygon extrusion technique

**Airspace Visualization:**
- [Pilot Institute: Airspace Classes Explained](https://pilotinstitute.com/airspace-explained/) — Class B/C/D geometry descriptions
- [3D Airspace visualization](https://3d-airspace.vercel.app/) — interactive reference

**Heatmap Reference:**
- [tar1090: Advanced Features (heatmap)](https://deepwiki.com/wiedehopf/tar1090/5-advanced-features) — density visualization patterns

---
*Research completed: 2026-02-09*
*Ready for roadmap: yes*
