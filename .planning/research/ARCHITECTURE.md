# Architecture Patterns: v2.1 Integration

**Domain:** Airspace volumes, coverage heatmaps, and visual polish integration into existing Metal 3 flight tracker
**Researched:** 2026-02-09
**Confidence:** HIGH (based on direct codebase analysis of all rendering files + Metal transparent rendering patterns from Metal by Example + Apple compute shader documentation)

## Current Architecture Summary

The existing rendering architecture uses a **single render command encoder per frame** with ordered draw call encoding. All visual elements share one render pass descriptor and one depth buffer. The draw order within `Renderer.draw(in:)` is:

```
1. Terrain meshes (opaque, depth-write ON)
2. Flat tile quads (opaque fallback, depth-write ON)
3. Altitude reference lines (alpha-blended, depth-write ON)
4. Aircraft bodies - instanced per category (opaque, depth-write ON)
5. Spinning parts - rotors/propellers (opaque, depth-write ON)
6. [wireframe mode restore to fill if retro]
7. Trail polylines (alpha-blended, depth-write OFF via glowDepthStencilState)
8. Aircraft labels - billboards (alpha-blended, depth-write OFF)
9. Airport labels - billboards (alpha-blended, depth-write OFF)
10. Glow sprites - additive blend (alpha-blended, depth-write OFF)
```

**Key architectural facts from the code:**

- **Triple buffering:** 3 uniform buffers, 3 instance buffers per manager, ring-buffered via `currentBufferIndex`
- **Shared Uniforms struct:** `modelMatrix`, `viewMatrix`, `projectionMatrix` (defined in ShaderTypes.h)
- **BufferIndex enum:** Slots 0-7 already allocated (Uniforms, Vertices, ModelMatrix, Instances, GlowInstances, TrailVertices, LabelInstances, AltLineVertices)
- **No separate render passes:** Everything is one encoder with pipeline state swaps
- **Coordinate system:** Mercator projection, worldScale=500, Y=altitude, ground at Y=0
- **Manager pattern:** Each visual element has a dedicated manager class (TrailManager, LabelManager, AirportLabelManager, AircraftInstanceManager) that owns triple-buffered GPU buffers and provides `update()` + buffer accessors
- **Pipeline pattern:** Each visual element has its own pipeline state(s), created in `Renderer.init`
- **MSAA:** 4x sample count on all pipeline states
- **Depth format:** `.depth32Float`
- **Color format:** `.bgra8Unorm`

---

## New Feature Integration Architecture

### Feature 1: Airspace Volume Rendering

**What it is:** Semi-transparent 3D shapes representing FAA airspace classes (Class B inverted wedding cake, Class C cylinders, Class D cylinders) rendered on the map at correct geographic positions and altitudes.

**Geometry approach:** Procedural cylinder/truncated-cone meshes generated at init time (similar to how `AircraftMeshLibrary` builds procedural geometry). Each airspace volume is a **unit cylinder** or **unit truncated cone** scaled and positioned per-instance via model matrices.

#### New Files

| File | Type | Purpose |
|------|------|---------|
| `AirspaceVolumeManager.swift` | NEW | Loads airspace data, generates per-instance transforms, triple-buffered instance buffers |
| `AirspaceShaders.metal` | NEW | Vertex/fragment shaders for semi-transparent volumes with Fresnel-like edge highlighting |
| `AirspaceGeometry.swift` | NEW | Procedural unit cylinder and truncated cone mesh generation (position + normal vertices) |

#### Modified Files

| File | Change |
|------|--------|
| `ShaderTypes.h` | Add `BufferIndexAirspaceInstances = 8`, add `AirspaceInstanceData` struct |
| `Renderer.swift` | Add `airspaceVolumeManager` property, `airspacePipeline` pipeline state, `encodeAirspaceVolumes()` method, call in draw loop |
| `ThemeManager.swift` | Add `airspaceColors` to `ThemeConfig` (per-class RGBA with alpha ~0.15-0.25) |

#### Data Flow

```
airports.json (or separate airspace.json)
  |
  | AirspaceVolumeManager.init() loads + converts to world coordinates
  v
Per-airspace: center position (SIMD3), base altitude (Float), top altitude (Float),
              inner radius, outer radius (for Class B tiers), airspace class enum
  |
  | AirspaceVolumeManager.update(bufferIndex:, cameraPosition:, themeConfig:)
  | Distance-culled, sorted back-to-front from camera
  v
AirspaceInstanceData buffer (triple-buffered):
  - modelMatrix (4x4): translate to world position, scale to radius/height
  - color (float4): theme-aware RGBA with alpha for transparency
  - _pad fields for alignment
  |
  | encodeAirspaceVolumes() in Renderer.draw()
  v
GPU renders semi-transparent cylinders with alpha blending
```

#### Render Pass Integration

Airspace volumes are **semi-transparent** and must render:
- **AFTER** all opaque geometry (terrain, aircraft, altitude lines)
- **BEFORE** other transparent elements (trails, labels, glow)
- With **depth-write OFF** (read depth to be occluded by terrain/aircraft, but do not write to avoid occluding each other incorrectly)
- With **back-to-front sorting** for correct alpha compositing
- Using the existing `glowDepthStencilState` (depthCompare: lessEqual, depthWrite: false)

**Updated draw order:**

```
1. Terrain meshes (opaque)
2. Flat tile quads (opaque fallback)
3. Altitude reference lines (alpha-blended, depth-write ON)
4. Aircraft bodies (opaque)
5. Spinning parts (opaque)
6. [wireframe restore if retro]
7. >>> AIRSPACE VOLUMES (alpha-blended, depth-write OFF, back-to-front sorted) <<<
8. Trail polylines (alpha-blended, depth-write OFF)
9. Coverage heatmap overlay (alpha-blended, depth-write OFF)
10. Aircraft labels (alpha-blended, depth-write OFF)
11. Airport labels (alpha-blended, depth-write OFF)
12. Glow sprites (additive blend, depth-write OFF)
```

#### Shader Design

```metal
// AirspaceShaders.metal

struct AirspaceInstanceData {
    float4x4 modelMatrix;   // 64 bytes: position + scale
    float4 color;            // 16 bytes: theme-aware RGBA
    float heightScale;       // 4 bytes: for altitude mapping
    float _pad0, _pad1, _pad2; // 12 bytes padding
};
// Total: 96 bytes (same as AircraftInstanceData for alignment consistency)

// Vertex shader: standard instanced transform
// Fragment shader: Fresnel-like edge glow for volume visibility
//   - Compute view-dependent opacity: alpha increases at glancing angles
//   - This makes the volume boundaries visible without obscuring the interior
//   - discard_fragment() for fully transparent fragments to avoid depth issues
```

#### Fresnel Edge Approach (HIGH confidence)

Rather than rendering solid semi-transparent volumes (which require perfect back-to-front sorting per-pixel), use a **Fresnel-like rim shader**:
- Compute `dot(viewDirection, surfaceNormal)` in fragment shader
- When the dot product is near 1.0 (facing camera directly), the surface is nearly transparent
- When the dot product is near 0 (edge-on/grazing), the surface is more opaque
- This gives a "glass bubble" effect that clearly shows volume boundaries without obscuring content inside
- Eliminates the need for perfect sort order since most fragments are very transparent
- Similar technique used by the existing glow sprites but applied to 3D geometry

```metal
fragment float4 airspace_fragment(AirspaceVertexOut in [[stage_in]]) {
    float3 viewDir = normalize(in.cameraPosition - in.worldPosition);
    float3 normal = normalize(in.worldNormal);
    float fresnel = 1.0 - abs(dot(viewDir, normal));
    float edgeAlpha = pow(fresnel, 2.0) * in.color.a * 3.0; // boost edge visibility
    float baseAlpha = in.color.a * 0.05; // very subtle fill
    float alpha = min(baseAlpha + edgeAlpha, 0.8);
    if (alpha < 0.01) discard_fragment();
    return float4(in.color.rgb * alpha, alpha); // premultiplied
}
```

#### Airspace Data Requirements

Airspace data can be embedded as a JSON file in the bundle (like airports.json). Each entry needs:

```json
{
  "id": "KSEA-B",
  "class": "B",
  "center_lat": 47.449,
  "center_lon": -122.309,
  "tiers": [
    { "inner_nm": 0, "outer_nm": 10, "floor_ft": 0, "ceiling_ft": 10000 },
    { "inner_nm": 10, "outer_nm": 20, "floor_ft": 3000, "ceiling_ft": 10000 },
    { "inner_nm": 20, "outer_nm": 30, "floor_ft": 6000, "ceiling_ft": 10000 }
  ]
}
```

Each tier becomes one instanced cylinder draw. The unit cylinder mesh is shared; only the model matrix (scale + translate) varies per instance.

---

### Feature 2: Coverage Heatmap

**What it is:** A 2D ground-plane overlay showing aircraft density/coverage as a color gradient (blue=low, red=high). Accumulates over time as aircraft positions are recorded.

**Two implementation approaches considered:**

#### Approach A: Compute Shader + Texture (RECOMMENDED)

Use a Metal compute shader to accumulate aircraft positions into a 2D texture, then render that texture as a ground-plane quad with alpha blending.

**Why this approach:** The heatmap is a 2D spatial accumulation problem. A compute shader can atomically increment texels corresponding to aircraft positions each frame, and the resulting texture can be sampled in a simple textured quad fragment shader. This keeps the render pass simple and leverages GPU parallelism for the accumulation step.

#### Approach B: CPU Grid + Texture Upload

Maintain a 2D grid on CPU, increment cells each frame, upload as texture. Simpler but wastes CPU-GPU bandwidth every frame.

**Verdict: Use Approach A (compute shader)** because the accumulation is embarrassingly parallel and avoids per-frame texture uploads.

#### New Files

| File | Type | Purpose |
|------|------|---------|
| `HeatmapManager.swift` | NEW | Owns heatmap texture, configures compute pipeline, runs accumulation + decay compute passes, renders ground quad |
| `HeatmapShaders.metal` | NEW | Compute kernel for accumulation, compute kernel for decay/normalization, vertex/fragment shaders for ground overlay rendering |

#### Modified Files

| File | Change |
|------|--------|
| `ShaderTypes.h` | Add `HeatmapUniforms` struct (grid bounds, cell size, decay rate), add `BufferIndexHeatmapPositions = 9` |
| `Renderer.swift` | Add `heatmapManager` property, `heatmapPipeline` pipeline state, compute pipeline state, encode compute + render in draw loop |
| `ThemeManager.swift` | Add `heatmapColorRamp` to `ThemeConfig` |

#### Data Flow

```
InterpolatedAircraftState[] (each frame from FlightDataManager)
  |
  | HeatmapManager.update(states:, bufferIndex:)
  | Writes aircraft world XZ positions to a position buffer
  v
Compute Pass 1 - Accumulate:
  kernel reads position buffer, atomically increments heatmap texture cells
  |
Compute Pass 2 - Decay/Normalize:
  kernel multiplies all cells by decay factor (e.g. 0.998), clamps to max
  |
  v
Heatmap texture (R32Float or RG16Float, e.g. 256x256 grid)
  |
  | encodeHeatmap() renders ground-plane quad sampling this texture
  v
Fragment shader maps texture value through color ramp: 0->transparent, low->blue, high->red
```

#### Compute Pass Integration

The compute pass must happen **before** the render pass in the same command buffer. This is because Metal compute and render encoders cannot be interleaved on the same command buffer -- you must end one encoder before beginning another.

**Updated command buffer structure:**

```swift
// In Renderer.draw(in:):

// 1. Compute pass (heatmap accumulation + decay)
if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
    heatmapManager.encodeCompute(encoder: computeEncoder, states: states, bufferIndex: currentBufferIndex)
    computeEncoder.endEncoding()
}

// 2. Render pass (all visual elements as before)
guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { ... }
// ... existing draw calls ...
// ... heatmap ground quad render call ...
renderEncoder.endEncoding()
```

#### Heatmap Texture Design

- **Resolution:** 256x256 cells covering the visible tile area
- **Format:** `.r32Float` (single channel, accumulation counter)
- **Storage:** `.private` (GPU-only, no CPU access needed)
- **Usage:** `[.shaderRead, .shaderWrite]` (compute writes, render reads)
- **Bounds:** Computed from camera target position and current zoom level. When camera moves significantly, the heatmap can be cleared and re-accumulated, or the bounds can shift.

#### Render Integration

The heatmap ground quad renders **after** trails and **before** labels, using the same alpha-blend + depth-read-no-write pattern:

```
Pipeline: alpha blending (sourceAlpha, oneMinusSourceAlpha)
Depth: read-only (glowDepthStencilState)
Geometry: single quad covering the heatmap world bounds
Fragment: sample heatmap texture, apply color ramp, output premultiplied alpha
```

The quad vertices are computed from the heatmap world bounds (similar to how tile quads are positioned using `tileModelMatrix`).

---

### Feature 3: Improved Aircraft Models (Visual Polish)

**What it is:** Higher-fidelity procedural meshes for the 6 aircraft categories, with more segments, smoother curves, and potentially normal-mapped surface detail.

#### Modified Files

| File | Change |
|------|--------|
| `AircraftMeshLibrary.swift` | Increase cylinder/sphere segment counts, add wing sweep/dihedral, refine proportions, possibly add engine nacelle detail |
| `AircraftShaders.metal` | Enhance lighting model (specular highlights, ambient occlusion approximation) |

#### No New Files Needed

This is a pure refinement of existing geometry and shading. The instanced rendering pipeline (`AircraftInstanceManager` -> `encodeAircraft()`) is unchanged. Only the mesh data and fragment shader improve.

#### Considerations

- **Vertex count increase:** Current meshes use 8-segment cylinders. Increasing to 16 segments roughly doubles vertex count. At 1024 max instances with 6 categories, this is still well within Metal's capabilities.
- **UInt16 index limit:** Current meshes use `UInt16` indices (max 65535 vertices per mesh). Higher-detail meshes must stay under this limit or switch to `UInt32`. Given the procedural nature (composed of simple primitives), staying under 65535 is feasible.
- **No texture maps needed:** The procedural approach with per-vertex normals and improved lighting can produce significantly better visuals without adding texture complexity.

#### Enhanced Lighting Model

```metal
// Improved aircraft_fragment with Blinn-Phong specular
fragment float4 aircraft_fragment_v2(AircraftVertexOut in [[stage_in]]) {
    float3 lightDir = normalize(float3(0.5, 1.0, 0.5));
    float3 normal = normalize(in.worldNormal);
    float3 viewDir = normalize(in.cameraPosition - in.worldPosition);

    // Diffuse
    float diffuse = max(dot(normal, lightDir), 0.0);
    float ambient = 0.25;

    // Specular (Blinn-Phong)
    float3 halfVec = normalize(lightDir + viewDir);
    float spec = pow(max(dot(normal, halfVec), 0.0), 32.0) * 0.3;

    float3 litColor = in.color.rgb * (ambient + diffuse * 0.65) + float3(spec);

    // Existing strobe + beacon effects unchanged
    // ...

    return float4(litColor, 1.0);
}
```

**Note:** Adding `cameraPosition` to the fragment shader requires adding it to the `Uniforms` struct or passing it through the vertex shader output. The simplest approach is to add a `cameraPosition` field to the existing `Uniforms` struct in `ShaderTypes.h`.

---

## Component Boundaries (Updated)

| Component | Responsibility | Communicates With | New/Modified |
|-----------|---------------|-------------------|--------------|
| **Renderer** | Owns Metal device, command queue, all pipeline states. Single render encoder per frame. Calls managers in draw order. | All managers, GPU | MODIFIED: add compute pass, add 2 new encode methods |
| **AirspaceVolumeManager** | Loads airspace data, generates instance transforms, distance-culls, back-to-front sorts, triple-buffers instance data | Renderer (pipeline), MapCoordinateSystem (geo->world), ThemeManager (colors) | NEW |
| **AirspaceGeometry** | Procedural unit cylinder and truncated cone meshes with normals | AirspaceVolumeManager (mesh buffers) | NEW |
| **HeatmapManager** | Owns heatmap texture, compute pipelines, position buffer, ground quad geometry. Runs accumulation + decay + render. | Renderer (compute + render encoding), MapCoordinateSystem (bounds), ThemeManager (color ramp) | NEW |
| **AircraftMeshLibrary** | Procedural 3D geometry for 6 categories + spinning parts | AircraftInstanceManager (mesh lookup) | MODIFIED: higher-detail geometry |
| **AircraftShaders.metal** | Instanced vertex + fragment for aircraft | GPU | MODIFIED: enhanced lighting |
| **ShaderTypes.h** | Shared type definitions between Swift and Metal | All shaders, all Swift rendering code | MODIFIED: new buffer indices, new structs, Uniforms expansion |
| **ThemeManager** | Theme configs with colors for all visual elements | Renderer, all managers | MODIFIED: airspace colors, heatmap ramp |

---

## Patterns to Follow

### Pattern 1: Manager Class with Triple-Buffered GPU Data

**What:** Every visual element follows the same manager pattern established by `TrailManager`, `LabelManager`, `AirportLabelManager`, and `AircraftInstanceManager`.

**When:** Any new visual element that writes per-frame data to GPU buffers.

**Structure:**

```swift
final class NewFeatureManager {
    // Triple-buffered GPU buffers
    private var buffers: [MTLBuffer] = []
    private var counts: [Int] = [0, 0, 0]
    private let device: MTLDevice

    init(device: MTLDevice) {
        // Allocate 3 buffers (Renderer.maxFramesInFlight)
        for i in 0..<Renderer.maxFramesInFlight {
            let buffer = device.makeBuffer(length: ..., options: .storageModeShared)!
            buffer.label = "Feature Buffer \(i)"
            buffers.append(buffer)
        }
    }

    func update(..., bufferIndex: Int) {
        let ptr = buffers[bufferIndex].contents().bindMemory(to: InstanceType.self, capacity: max)
        // Write instance data
        counts[bufferIndex] = writtenCount
    }

    func buffer(at index: Int) -> MTLBuffer { buffers[index] }
    func count(at index: Int) -> Int { counts[index] }
}
```

### Pattern 2: Pipeline State in Renderer.init

**What:** All pipeline states are created once in `Renderer.init` and stored as `let` properties.

**When:** Any new shader program needs a pipeline state.

**Why:** Pipeline state creation is expensive (shader compilation). The existing Renderer creates ALL pipeline states in init -- 15+ pipeline states currently. New features must follow this pattern.

### Pattern 3: Encode Method per Visual Element

**What:** Each visual element has a private `encode*` method in Renderer that sets pipeline state, binds buffers, and issues draw calls.

**When:** Any new render pass in the draw loop.

**Structure:**

```swift
private func encodeNewFeature(encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer) {
    let count = newFeatureManager.count(at: currentBufferIndex)
    guard count > 0 else { return }

    encoder.setRenderPipelineState(newFeaturePipeline)
    encoder.setDepthStencilState(appropriateDepthState)
    encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))
    encoder.setVertexBuffer(newFeatureManager.buffer(at: currentBufferIndex), offset: 0,
                             index: Int(BufferIndexNewFeature.rawValue))
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: ..., instanceCount: count)
}
```

### Pattern 4: Theme-Aware Colors via ThemeConfig

**What:** All colors that vary by theme are stored in `ThemeConfig` and applied through manager update methods or shader uniforms.

**When:** Any new visual element with theme-dependent appearance.

**Example from existing code:** `themeManager.config.altLineColor`, `themeManager.config.airportLabelColor`, `themeManager.config.aircraftTint`

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Separate Render Passes for Transparent Geometry

**What:** Creating a new `MTLRenderCommandEncoder` for each transparent layer.

**Why bad:** The existing architecture uses ONE encoder for the entire frame. Creating multiple render passes means multiple load/store actions on the framebuffer, which destroys performance on tile-based GPU architectures (Apple Silicon). Every encoder start/end triggers a full tile flush.

**Instead:** Add new encode calls within the existing single encoder, in the correct draw order position. Use pipeline state switches (cheap) rather than encoder switches (expensive).

### Anti-Pattern 2: CPU-Side Back-to-Front Sorting Every Frame

**What:** Sorting all transparent geometry instances by distance from camera every frame.

**Why bad:** Sorting hundreds/thousands of instances per frame on CPU is expensive and often unnecessary.

**Instead:** For airspace volumes (few dozen instances), sorting is cheap and correct. For heatmap (single quad), no sorting needed. For the existing trails/labels/glow, the app already avoids sorting by using depth-read-no-write and accepting minor ordering artifacts -- continue this approach.

### Anti-Pattern 3: Per-Frame Texture Upload for Heatmap

**What:** Building the heatmap grid on CPU and uploading via `texture.replace()` every frame.

**Why bad:** CPU-GPU transfer every frame is wasteful when the GPU can accumulate directly. The existing `LabelManager` does CPU-side rasterization to texture, but that's for text rendering which MUST happen on CPU. Numeric accumulation should stay on GPU.

**Instead:** Use a compute shader to accumulate directly into a `.private` storage mode texture. Zero CPU-GPU transfer for the heatmap data path.

### Anti-Pattern 4: Breaking the Triple-Buffer Ring

**What:** Using a fixed buffer instead of indexing by `currentBufferIndex`.

**Why bad:** The Renderer uses `frameSemaphore` (3 slots) to pipeline CPU work ahead of GPU. Writing to a buffer the GPU is still reading causes tearing or corruption.

**Instead:** ALL per-frame GPU data must use the `bufferIndex` parameter. Every existing manager follows this pattern.

---

## Scalability Considerations

| Concern | Current (v2.0) | With Airspace Volumes | With Heatmap | Notes |
|---------|----------------|----------------------|-------------|-------|
| Draw calls per frame | ~50-100 (tiles + 6 categories + trails + labels + glow) | +10-30 (instanced airspace) | +2 (compute dispatch + quad) | Negligible increase |
| GPU memory | ~100MB (tile textures + terrain + instance buffers) | +1-2MB (airspace mesh + instances) | +256KB (256x256 R32F texture) | Negligible increase |
| Vertex throughput | ~50K verts (terrain) + ~10K (aircraft instances) | +5-10K (cylinder meshes) | +6 (single quad) | Well within budget |
| Pipeline state switches | ~8 per frame | +1 (airspace pipeline) | +1 (heatmap pipeline) | Each switch is ~microseconds |
| Compute passes | 0 | 0 | +1 (2 dispatches) | First compute usage in the app |

---

## BufferIndex Allocation Plan

Current allocation in `ShaderTypes.h`:

```c
BufferIndexUniforms       = 0  // Shared uniforms (VP matrices)
BufferIndexVertices       = 1  // Per-vertex position data
BufferIndexModelMatrix    = 2  // Per-tile model matrix / trail line width
BufferIndexInstances      = 3  // Aircraft instances / trail resolution
BufferIndexGlowInstances  = 4  // Glow sprite instances
BufferIndexTrailVertices  = 5  // Trail polyline vertices
BufferIndexLabelInstances = 6  // Label billboard instances
BufferIndexAltLineVertices = 7 // Altitude line vertices
```

New allocations:

```c
BufferIndexAirspaceInstances = 8  // Airspace volume instances
BufferIndexHeatmapPositions  = 9  // Aircraft positions for compute accumulation
BufferIndexHeatmapUniforms   = 10 // Heatmap grid configuration
```

---

## Uniforms Struct Expansion

The current `Uniforms` struct contains only matrices:

```c
typedef struct {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
} Uniforms;
```

For enhanced aircraft lighting and airspace Fresnel effects, add `cameraPosition`:

```c
typedef struct {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float3 cameraPosition;    // NEW: for specular/Fresnel calculations
    float _pad;                     // alignment padding
} Uniforms;
```

This requires updating the Swift side where `Uniforms` is populated:

```swift
uniforms.pointee.cameraPosition = camera.position
```

**Impact analysis:** Every shader that reads `uniforms` will see the expanded struct, but since they all access by named field (not by offset), this is backward-compatible. The `_pad` field ensures the struct remains 16-byte aligned (208 bytes total after expansion vs 192 before).

---

## Suggested Build Order

Based on dependency analysis of the integration points:

### Phase 1: Foundation Changes (prerequisite for everything)

1. **Expand `Uniforms` struct** in `ShaderTypes.h` to add `cameraPosition`
2. **Update `Renderer.draw()`** to populate `uniforms.pointee.cameraPosition = camera.position`
3. **Add new `BufferIndex` entries** to `ShaderTypes.h`
4. **Add new color fields** to `ThemeConfig` in `ThemeManager.swift`

These changes are non-breaking. Existing shaders continue to work because they access uniforms by field name.

### Phase 2: Airspace Volume Rendering

5. **Create `AirspaceGeometry.swift`** -- unit cylinder + truncated cone meshes
6. **Create `AirspaceVolumeManager.swift`** -- data loading, instancing, distance culling
7. **Create `AirspaceShaders.metal`** -- Fresnel-edge instanced rendering
8. **Wire into `Renderer.swift`** -- pipeline state in init, encode method, draw loop insertion
9. **Add airspace data file** (JSON, embedded in bundle)

### Phase 3: Coverage Heatmap

10. **Create `HeatmapShaders.metal`** -- compute kernels (accumulate + decay) + render shaders
11. **Create `HeatmapManager.swift`** -- texture management, compute dispatch, quad rendering
12. **Wire into `Renderer.swift`** -- compute pipeline in init, compute dispatch before render, encode call in render loop

### Phase 4: Visual Polish

13. **Improve `AircraftMeshLibrary.swift`** -- higher segment counts, refined proportions
14. **Enhance `AircraftShaders.metal`** -- Blinn-Phong specular, optional AO approximation

**Phase ordering rationale:**
- Phase 1 must come first because Phases 2-4 all depend on expanded Uniforms and new BufferIndex slots
- Phase 2 before Phase 3 because airspace volumes are simpler (no compute pass, follows existing instanced rendering pattern closely) and validate the transparent rendering integration
- Phase 3 after Phase 2 because the compute pass is a new pattern for this codebase and should be added after the simpler transparent rendering is proven
- Phase 4 is independent and can happen anytime after Phase 1, but doing it last avoids blocking the more architecturally significant features

---

## File Inventory: Complete Change List

### New Files (6)

| File | Lines (est.) | Purpose |
|------|-------------|---------|
| `Rendering/AirspaceGeometry.swift` | ~120 | Procedural unit cylinder + truncated cone meshes |
| `Rendering/AirspaceVolumeManager.swift` | ~250 | Airspace data loading, instance management, culling |
| `Rendering/AirspaceShaders.metal` | ~80 | Instanced vertex + Fresnel fragment shaders |
| `Rendering/HeatmapManager.swift` | ~300 | Heatmap texture, compute dispatch, quad rendering |
| `Rendering/HeatmapShaders.metal` | ~120 | Compute accumulate/decay kernels + render shaders |
| `Resources/airspace.json` | ~200 | Airspace volume definitions for major airports |

### Modified Files (5)

| File | Changes |
|------|---------|
| `Rendering/ShaderTypes.h` | +3 BufferIndex entries, +2 struct definitions, expand Uniforms |
| `Rendering/Renderer.swift` | +2 pipeline states, +1 compute pipeline, +2 encode methods, +1 compute dispatch, +2 manager properties, modified draw loop order (~80 lines added) |
| `Rendering/ThemeManager.swift` | +2 ThemeConfig fields (airspace colors, heatmap ramp) |
| `Rendering/AircraftMeshLibrary.swift` | Increased segment counts in build methods, refined geometry proportions (~50 lines modified) |
| `Rendering/AircraftShaders.metal` | Enhanced fragment shader with specular + cameraPosition usage (~15 lines modified) |

### Unchanged Files (30+)

All data layer files, all SwiftUI views, camera, map tile system, terrain system, trail system, label systems, selection manager -- none of these need changes for v2.1 features.

---

## Sources

- Codebase analysis: Direct reading of all 35 source files in the project
- [Translucency and Transparency in Metal -- Metal by Example](https://metalbyexample.com/translucency-and-transparency/) -- transparent rendering order, depth buffer management
- [Processing a texture in a compute function -- Apple Developer](https://developer.apple.com/documentation/metal/compute_passes/processing_a_texture_in_a_compute_function) -- compute shader texture write pattern
- [Introduction to Compute Programming in Metal -- Metal by Example](https://metalbyexample.com/introduction-to-compute/) -- compute pipeline setup
- [FAA Airspace Classes in 3D](https://3d-airspace.vercel.app/) -- airspace volume visualization reference
- [Airspace Classes Explained -- Pilot Institute](https://pilotinstitute.com/airspace-explained/) -- Class B/C/D geometry (inverted wedding cake, cylinders)
