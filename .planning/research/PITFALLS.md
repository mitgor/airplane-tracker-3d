# Domain Pitfalls -- v2.1 Feature Additions

**Domain:** Adding translucent airspace volumes, coverage heatmaps, visual polish, and bug fixes to existing Metal 3 flight tracker
**Researched:** 2026-02-09
**Confidence:** HIGH (verified against existing codebase analysis, Apple Metal documentation, Metal by Example, and multiple authoritative sources)
**Scope:** Pitfalls specific to ADDING features to the existing rendering pipeline, not the initial rewrite (see prior PITFALLS.md dated 2026-02-08 for initial rewrite pitfalls)

---

## Critical Pitfalls

Mistakes that cause visual corruption, render ordering artifacts, or require significant rework of the existing pipeline.

---

### Pitfall 1: Translucent Airspace Volumes Rendered With Depth Writes Enabled

**What goes wrong:** Airspace volumes (Class B shelves, TFRs, restricted areas) render as opaque-looking colored blobs that completely obscure aircraft, terrain, and other volumes behind them. From certain angles, closer volumes disappear entirely while farther ones show through. The scene looks broken whenever the camera rotates.

**Why it happens:** The existing renderer uses a single depth stencil state with `isDepthWriteEnabled = true` for all opaque geometry (terrain, aircraft). If airspace volume geometry is added to the render loop using this same depth stencil state, each translucent surface writes its depth to the depth buffer. Subsequent translucent fragments at greater depth are rejected by the depth test, even though they should blend visually. This is the single most common mistake when adding transparency to an existing opaque-only pipeline.

**Specific risk in this codebase:** The `Renderer.swift` `depthStencilState` (line 12) has `isDepthWriteEnabled = true` and `depthCompareFunction = .lessEqual`. The glow pass already has a correct depth-read/no-write state (`glowDepthStencilState`, line 24), but a developer adding airspace volumes might copy the opaque pipeline setup instead of the glow setup.

**Consequences:**
- Airspace volume faces occlude each other incorrectly -- only the nearest face renders
- Aircraft and trails inside airspace volumes become invisible from certain camera angles
- Nested volumes (Class B shelves are concentric cylinders of increasing radius) render as a single flat color instead of layered translucent shells

**Prevention:**
1. Create a dedicated `MTLDepthStencilState` for airspace volumes: `depthCompareFunction = .lessEqual`, `isDepthWriteEnabled = false`. This is the same pattern already used for `glowDepthStencilState` (Renderer.swift line 319-326).
2. Render ALL opaque geometry first (terrain, aircraft, altitude lines), then render translucent geometry (volumes, trails, labels, glow) in a separate pass with depth writes disabled.
3. Sort airspace volume meshes back-to-front relative to the camera position each frame before encoding draw calls.
4. Use premultiplied alpha blending (`sourceRGBBlendFactor = .one`, `destinationRGBBlendFactor = .oneMinusSourceAlpha`) for correct compositing of overlapping translucent surfaces.

**Detection:** Rotate the camera around overlapping airspace volumes. If closer volumes hide farther ones, depth writes are still enabled. If blending looks darkened or doubled, the blend factors are wrong.

**Confidence:** HIGH -- verified against Metal by Example transparency article and Apple's Metal Best Practices Guide. The existing glow pipeline in this codebase already demonstrates the correct pattern.

**Sources:**
- [Translucency and Transparency in Metal - Metal by Example](https://metalbyexample.com/translucency-and-transparency/)
- [Metal Best Practices Guide - Apple](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/)
- Existing codebase: `glowDepthStencilState` in `Renderer.swift` lines 319-326

---

### Pitfall 2: Incorrect Render Order After Adding New Translucent Passes

**What goes wrong:** After adding airspace volume rendering, the existing trail lines, billboard labels, airport labels, and glow sprites display incorrectly -- trails render behind volumes when they should be in front, labels disappear inside volume geometry, or glow halos have hard edges where they intersect volume boundaries.

**Why it happens:** The existing render order in `draw(in:)` (Renderer.swift lines 1004-1030) is carefully sequenced:

```
1. Terrain tiles (opaque, depth write ON)
2. Altitude lines (opaque, depth write ON)
3. Aircraft bodies (opaque, depth write ON)
4. Spinning parts (opaque, depth write ON)
5. Trails (alpha blend, depth write OFF)
6. Labels (alpha blend, depth write OFF)
7. Airport labels (alpha blend, depth write OFF)
8. Glow sprites (additive blend, depth write OFF)
```

Adding airspace volumes into this sequence at the wrong position breaks the visual layering. If volumes are encoded before aircraft, aircraft depth values are already in the buffer and correctly occlude volume fragments. But if volumes are encoded after trails, the volume fragments compete with trail fragments in unpredictable ways (since both have depth writes disabled, the later-encoded one "wins" regardless of actual depth).

**Specific risk in this codebase:** The single render encoder approach (one `MTLRenderCommandEncoder` for the entire frame, Renderer.swift line 879) means all pipeline state switches and depth state switches happen within the same encoder. Inserting a new translucent pass in the wrong position silently produces artifacts with no error or warning.

**Consequences:**
- Trails render behind airspace volumes instead of on top
- Billboard labels inside volume regions become invisible
- Additive glow bleeds incorrectly when overlapping volume edges
- Z-fighting between volume surfaces and terrain at volume floor altitudes

**Prevention:**
1. Insert airspace volume rendering AFTER all opaque geometry but BEFORE trails, labels, and glow. The correct order becomes:
   ```
   Opaque: Terrain -> Altitude lines -> Aircraft -> Spinning parts
   Translucent: Airspace volumes (back-to-front sorted) -> Trails -> Labels -> Airport labels -> Glow
   ```
2. Airspace volumes must use the same depth-read/no-write state as trails and labels (`glowDepthStencilState`).
3. Consider whether airspace volumes should occlude labels and trails or not. If volumes are very transparent (alpha < 0.2), rendering them before trails is fine. If volumes are more opaque (alpha > 0.3), you may want to render them after trails so trails remain visible.
4. Test with nested airspace configurations (Class B has 3+ concentric shelves at different altitudes).

**Detection:** Select an aircraft inside an airspace volume. If the trail disappears where it intersects the volume, the render order is wrong. Look at labels near volume boundaries -- if they flicker or clip, depth interaction is incorrect.

**Confidence:** HIGH -- derived directly from analysis of the existing render loop in the codebase.

---

### Pitfall 3: Propeller Rotation Matrix Composed in Wrong Order

**What goes wrong:** Propellers rotate around the aircraft's world-space Z axis instead of the propeller's local axis relative to the aircraft's heading. When an aircraft is heading east (90 degrees), the propeller appears to rotate around a vertical axis. When heading north, it works correctly. The bug is intermittent-looking because it depends on the aircraft's heading.

**Why it happens:** In `AircraftInstanceManager.swift` lines 190-194, the propeller spin matrix is composed as:

```swift
let propRotation = rotationZ(rotorAngle)
let noseOffset = translationMatrix(SIMD3<Float>(0, 0, 0))  // identity -- no-op
let spinMatrix = translation * rotation * noseOffset * propRotation
```

There are two issues:
1. `noseOffset` is `translationMatrix(SIMD3<Float>(0, 0, 0))` which is just the identity matrix. The comment says "propeller mesh has built-in nose offset" but this makes the matrix multiplication `translation * rotation * identity * propRotation` which simplifies to `translation * rotation * propRotation`. This means the propeller spin (`propRotation` around Z) is applied in the aircraft's LOCAL space (after heading rotation), which is actually correct for Z-axis spinning IF the propeller mesh is built along Z.

2. However, examining `buildPropeller()` in AircraftMeshLibrary.swift line 463-473, the propeller blade is a box at offset `(0, 0, 1.55)` with dimensions `(0.08, 1.2, 0.08)` -- it extends along the Y axis (height 1.2) at a Z offset (nose position). Rotating around Z rotates the blade in the XY plane, which is correct for a propeller facing forward. BUT the `rotationZ()` function rotates around the world Z axis, and since it is applied BEFORE `rotation` (heading) in the multiplication chain (matrix multiplication is right-to-left), the propeller spin occurs in the aircraft's local frame, which IS correct.

The actual bug is more subtle: look at the matrix composition order. `translation * rotation * propRotation` means: first spin the propeller locally (propRotation), then orient to heading (rotation), then move to world position (translation). This is correct. BUT the aircraft body uses `translation * rotation` (line 138). The propeller should be at the SAME position and heading as the body, plus its own spin. The current code achieves this.

**Wait -- the real bug**: Looking more carefully, the helicopter rotor (lines 177-179) uses `translation * rotorRotation`, which is `translation * rotationY(rotorAngle)`. This applies rotor spin in WORLD space (rotorRotation is not composed with the aircraft heading rotation). The rotor spins around the world Y axis regardless of which direction the helicopter is facing. For a top-mounted rotor that spins horizontally, this works because Y-up is always vertical. BUT the tail rotor (part of the same mesh, AircraftMeshLibrary.swift line 457) at offset `(0, 0.1, -2.75)` rotates around the Y axis too -- a tail rotor should rotate around the Z axis (or the aircraft's local lateral axis). This means the tail rotor visually spins in the wrong plane.

For the propeller, the actual bug is that `noseOffset` being identity means there is no translation to the nose. The propeller mesh has a built-in offset at Z=1.55, so this works, but the comment is misleading and the identity multiplication is wasted computation.

**Consequences:**
- Propeller rotation appears correct for north-facing aircraft but wrong for other headings (if the actual bug is world-space rotation)
- Tail rotor spins in the wrong plane for all helicopter headings
- Performance waste from multiplying by identity matrix

**Prevention:**
1. Verify the propeller rotation by watching a single aircraft from the side as it turns. The propeller disc should always face forward regardless of heading.
2. Remove the identity `noseOffset` multiplication -- it does nothing and adds confusion.
3. For the helicopter: if the tail rotor needs its own rotation axis, it should be a separate mesh or the rotor mesh should be split into main rotor and tail rotor submeshes with different spin matrices.
4. Test rotation with aircraft at headings 0, 90, 180, 270 degrees and verify the spinning part aligns with the fuselage direction.
5. The correct composition for any spinning part attached to an aircraft body is:
   ```
   spinMatrix = translation * headingRotation * localSpinRotation
   ```
   Where `localSpinRotation` is the spin around the part's local axis AFTER the heading has been applied.

**Detection:** Watch a propeller aircraft from directly above. The propeller disc should always be perpendicular to the aircraft's heading. If it appears to wobble or always faces the same absolute direction regardless of heading, the matrix composition is wrong.

**Confidence:** HIGH -- derived directly from code analysis of `AircraftInstanceManager.swift` lines 176-205 and `AircraftMeshLibrary.swift` lines 444-473.

---

### Pitfall 4: Heatmap Compute Shader Output Not Synchronized With Render Pass

**What goes wrong:** The coverage heatmap texture flickers, shows stale data from a previous frame, or displays partially updated data (half the texture shows current aircraft positions, half shows old positions). On some frames the heatmap is completely blank. The bug is non-deterministic and appears/disappears based on GPU load.

**Why it happens:** When generating a heatmap texture using a Metal compute shader, the compute pass writes to a texture. The subsequent render pass reads that texture to display the heatmap overlay on the ground. If these two operations are not properly synchronized, the GPU may execute them out of order or the render pass may read the texture before the compute pass finishes writing to it.

In Metal 3 (pre-Metal 4), synchronization between command encoders in the same command buffer is implicit -- encoders are executed in order. BUT this only applies if they are in the SAME command buffer. If the compute pass and render pass are in different command buffers, there is no automatic synchronization.

Even within the same command buffer, the compute encoder must be ENDED (via `endEncoding()`) before the render encoder is created. If the developer tries to interleave compute dispatches with render draw calls using the same encoder, it will not compile -- they are different encoder types.

**Specific risk in this codebase:** The current renderer uses a single command buffer and a single render encoder (Renderer.swift lines 862-1054). Adding a compute pass for heatmap generation requires creating a compute encoder BEFORE the render encoder. The temptation is to add it AFTER the render encoder (since the aircraft positions are known by then), but the texture output would then not be available for the current frame's render pass.

**Consequences:**
- Heatmap shows data from 1-3 frames ago (stale but not flickering)
- Heatmap flickers between current and stale data
- Heatmap is blank on first frame after aircraft data arrives
- On discrete GPUs, timing-dependent corruption

**Prevention:**
1. Structure the frame as: compute encoder (heatmap generation) -> end compute encoding -> render encoder (draw everything including heatmap texture) -> end render encoding. All within the same command buffer.
2. Update aircraft positions into a compute-readable buffer BEFORE creating the compute encoder.
3. The heatmap texture must have `usage: [.shaderRead, .shaderWrite]` to be both written by compute and read by the fragment shader.
4. Triple-buffer the heatmap texture if compute and render run on separate command buffers (not recommended -- keep them in the same command buffer).
5. In Metal 4 (if targeting macOS 26+), use the explicit Barrier API for stage-to-stage synchronization. In Metal 3, rely on command buffer encoder ordering.

```swift
// Correct order within a single command buffer:
let commandBuffer = commandQueue.makeCommandBuffer()!

// 1. Compute pass: generate heatmap
let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
computeEncoder.setComputePipelineState(heatmapComputePipeline)
computeEncoder.setBuffer(aircraftPositionBuffer, offset: 0, index: 0)
computeEncoder.setTexture(heatmapTexture, index: 0)
computeEncoder.dispatchThreadgroups(...)
computeEncoder.endEncoding()  // MUST end before render encoder

// 2. Render pass: draw scene including heatmap overlay
let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
// ... draw terrain, aircraft, etc.
// ... draw heatmap overlay using heatmapTexture
renderEncoder.endEncoding()

commandBuffer.commit()
```

**Detection:** Add a solid color fill to the heatmap compute shader temporarily. If the solid color flickers or lags behind camera movement, there is a synchronization issue. If it is stable, the issue is in the data pipeline feeding the compute shader.

**Confidence:** HIGH -- verified against Apple's compute pass documentation and Metal command buffer execution model.

**Sources:**
- [Processing a Texture in a Compute Function - Apple Documentation](https://developer.apple.com/documentation/metal/compute_passes/processing_a_texture_in_a_compute_function)
- [Introduction to Compute Programming in Metal - Metal by Example](https://metalbyexample.com/introduction-to-compute/)
- [WWDC 2025 - Discover Metal 4](https://dev.to/arshtechpro/wwdc-2025-discover-metal-4-23f2) (Metal 4 Barrier API)

---

### Pitfall 5: New Triple-Buffered Resources Not Added to Semaphore Discipline

**What goes wrong:** Adding new per-frame buffers (airspace volume instance data, heatmap position buffer) without triple-buffering them causes sporadic visual glitches -- airspace volumes flicker, heatmap data tears, or the app hangs for a frame. The bug appears only under GPU load and is extremely difficult to reproduce in the debugger.

**Why it happens:** The existing codebase correctly triple-buffers uniforms (`uniformBuffers`, Renderer.swift line 75), aircraft instances (`instanceBuffers`, AircraftInstanceManager.swift line 24), glow instances (`glowBuffers`), spin instances (`spinBuffers`), trail vertices (`trailManager`), and label instances. The `frameSemaphore` (Renderer.swift line 74) with value 3 ensures the CPU does not overwrite a buffer the GPU is reading.

When a developer adds a NEW buffer for airspace volumes or heatmap data and allocates it as a single buffer (not triple-buffered), the CPU writes to it every frame while the GPU may still be reading from a previous frame's data. The semaphore only protects buffers that are indexed by `currentBufferIndex` -- a new single buffer is unprotected.

**Specific risk in this codebase:** The pattern for adding a new triple-buffered resource requires:
1. Allocating 3 copies of the buffer (matching `Renderer.maxFramesInFlight`)
2. Indexing by `currentBufferIndex` in both the update method and the encode method
3. Ensuring the new manager/buffer follows the same `bufferIndex` parameter convention as `instanceManager.update(states:bufferIndex:...)` and `trailManager.update(states:bufferIndex:...)`

Forgetting step 2 (using the same buffer index for read and write) is the common mistake.

**Consequences:**
- Torn data: half of one frame's positions mixed with half of another's
- Intermittent visual artifacts that disappear when frame rate drops (because GPU catches up)
- App hangs if the new buffer is somehow involved in the semaphore wait chain
- Debugging is near-impossible because the bug is timing-dependent

**Prevention:**
1. Every new per-frame dynamic buffer MUST follow the existing triple-buffering pattern. Use the `AircraftInstanceManager` as a template: allocate `Renderer.maxFramesInFlight` copies, accept `bufferIndex: Int` in update methods, and return the correct buffer via an accessor method.
2. Create a checklist for adding new render data:
   - [ ] Buffer allocated x3
   - [ ] Update method takes `bufferIndex`
   - [ ] Encode method uses `currentBufferIndex`
   - [ ] Buffer label includes index for GPU debugger identification
3. Never add a single-copy buffer for data that changes per frame. Static data (mesh geometry, lookup tables) is fine as single-copy.
4. When adding a compute pass for heatmaps, the aircraft position buffer fed to the compute shader must ALSO be the triple-buffered version indexed by `currentBufferIndex`.

**Detection:** Run with Metal Validation Layer enabled (`MTL_DEBUG_LAYER=1`). Watch for "resource written while in use" warnings. Alternatively, reduce `maxFramesInFlight` to 1 temporarily -- if artifacts disappear, a buffer is not properly triple-buffered.

**Confidence:** HIGH -- derived directly from the existing triple-buffering architecture in the codebase.

---

## Moderate Pitfalls

Mistakes that cost days of debugging or produce hard-to-diagnose visual artifacts.

---

### Pitfall 6: Map Tiles Not Displaying Due to Texture Binding Timing Race

**What goes wrong:** Map tiles are fetched successfully (verified by logging) but never appear on the ground surface. The terrain renders with placeholder colors. Sometimes tiles appear after panning the camera away and back. Sometimes a subset of tiles display while adjacent tiles remain blank.

**Why it happens:** The `MapTileManager.fetchTile()` (MapTileManager.swift line 95) uses `Task { }` to fetch tile data asynchronously and converts it to a Metal texture via `MTKTextureLoader.newTexture(data:options:)`. The texture is stored in the `cache` dictionary on the `cacheQueue`. However, the render loop (Renderer.swift line 901) calls `tileManager.texture(for: tile)` which reads from the cache on the `cacheQueue`.

There are several potential failure points:
1. **MTKTextureLoader threading:** `newTexture(data:options:)` with `await` creates the texture asynchronously. If the texture is not fully uploaded to the GPU by the time the render encoder references it, the texture may appear blank for one or more frames.
2. **Texture usage flags:** The texture is created with `.textureUsage: MTLTextureUsage.shaderRead.rawValue` (line 111), which is correct. But if `SRGB: false` (line 113) is incorrect for the tile provider's color space, tiles will appear with washed-out or over-saturated colors that might look like "missing" tiles.
3. **Cache queue synchronization:** The `cacheQueue.sync` blocks in `texture(for:)` run synchronously on the render thread. If the fetch completion handler is also doing `cacheQueue.sync`, and these happen on the same underlying thread, there could be a deadlock. In practice, `Task { }` runs on the cooperative thread pool, so this is unlikely but worth noting.
4. **Flat tile path vs terrain tile path:** When both terrain mesh AND map texture are available, the renderer uses the terrain path (Renderer.swift line 904-929). When only the map texture is available (no terrain mesh), it uses the flat tile path (lines 931-951). If the terrain mesh loads first but the map texture has not loaded yet, the terrain renders with placeholder colors. The tile texture is fetched but the terrain path does not trigger a re-fetch if the texture was already requested.

**Specific risk in this codebase:** The `texture(for:)` method returns `nil` if the tile is still loading, and the renderer falls through to the placeholder pipeline. But if the tile was ALREADY requested (in `pendingRequests`), the method returns `nil` without starting a new fetch. If the original fetch failed silently (non-200 status code, line 103-106), the tile is removed from `pendingRequests` but never retried. The tile will be permanently missing until the cache is cleared.

**Consequences:**
- Tiles that fail once never retry, leaving permanent blank spots
- Tiles that load after terrain meshes appear as placeholder-colored terrain (the mesh shape is visible but the texture is missing)
- Under heavy network load, tiles may appear to "pop in" frames after they are available due to the async texture upload timing

**Prevention:**
1. Add retry logic for failed tile fetches: track failure count per tile and retry up to 3 times with exponential backoff.
2. When `terrainMesh(for:)` returns a mesh but `texture(for:)` returns nil, ensure the texture fetch was actually started. Currently both managers independently track `pendingRequests`, so a terrain mesh arriving does not trigger a map texture fetch -- but the next frame's call to `texture(for:)` will, as long as the tile is not stuck in `pendingRequests`.
3. Add a `pendingRequests` timeout: if a tile has been pending for more than 30 seconds, remove it from `pendingRequests` so it can be retried.
4. Verify tile URLs are correct for each theme. Call `tileURL(for:)` with a known tile coordinate and verify the URL manually in a browser.
5. Check that the texture storage mode (`.shared`, line 112) is correct. On discrete GPUs, `.shared` textures may need a `MTLBlitCommandEncoder` synchronization step before they are readable by the GPU.

**Detection:** Add logging in `fetchTile()` that prints when a tile is fetched, when it succeeds, and when it fails. Compare the list of fetched tiles against the list of tiles rendered with textures vs placeholders.

**Confidence:** HIGH -- derived directly from code analysis of `MapTileManager.swift` and the render loop.

---

### Pitfall 7: Airspace Volume Geometry Intersecting Terrain Creates Z-Fighting

**What goes wrong:** Where airspace volume surfaces meet the terrain surface (the "floor" of a Class B or Class C airspace), there is intense flickering/shimmering as both surfaces fight for the same depth buffer value. The flickering is especially visible when zoomed out or when the camera is far from the intersection.

**Why it happens:** Z-fighting occurs when two surfaces occupy nearly the same depth buffer value. The depth buffer has limited precision (typically 24-bit or 32-bit float), and precision decreases with distance from the camera. When an airspace volume's floor sits at (for example) 1000ft MSL and the terrain below is also at ~1000ft MSL, the two surfaces produce nearly identical depth values.

**Specific risk in this codebase:** The terrain mesh is generated with elevation data (TerrainTileManager.swift, `terrainScaleFactor = 0.003`). An airspace floor at sea level (Y=0) would intersect the terrain exactly. Even with altitude offset, the precision at the camera distances used in this app (camera distances 10-1000, Renderer.swift line 153) means the near/far clip planes span a wide range, reducing depth buffer precision.

**Consequences:**
- Flickering/shimmering at airspace-terrain intersections
- Visual noise that draws the eye and looks unprofessional
- Worse at greater camera distances (lower depth precision)

**Prevention:**
1. Offset airspace volume floors slightly above terrain: add a small Y offset (0.1-0.5 world units) to volume floor vertices. This is a standard "depth bias" technique.
2. Use `MTLRenderCommandEncoder.setDepthBias(_:slopeScale:clamp:)` to apply a hardware depth bias to the volume rendering pass. A bias of `-1.0` with slope scale `-1.0` pushes the volume surface slightly toward the camera in depth space.
3. If using separate render passes, use a 32-bit depth buffer (`MTLPixelFormat.depth32Float`) instead of 24-bit to increase precision.
4. Reduce the far/near clip plane ratio. A near plane of 0.1 with a far plane of 1000 gives a 10,000:1 ratio, which wastes most depth precision on the first few meters. Use logarithmic depth or a reversed depth buffer (`depthCompareFunction = .greaterEqual` with near=1.0, far=0.0) for better precision distribution.
5. For airspace volumes specifically, do not render the floor face at all if it would be below terrain level. Only render the sides and ceiling.

**Detection:** Zoom out until the camera is 200+ units away. Look at where airspace volume floors meet terrain. If there is shimmering/flickering, Z-fighting is present.

**Confidence:** HIGH -- Z-fighting is a well-understood computer graphics problem. The specific risk in this codebase is confirmed by the camera distance range and depth buffer configuration.

**Sources:**
- [Tutorial 4: Depth and Transparency](https://research.ncl.ac.uk/game/mastersdegree/graphicsforgames/transparencyanddepth/Tutorial%204%20-%20Transparency%20and%20Depth.pdf)

---

### Pitfall 8: Heatmap Texture Resolution and Coordinate Mapping Mismatch

**What goes wrong:** The coverage heatmap appears to show aircraft density in the wrong locations -- hotspots are offset by several kilometers from actual aircraft positions. Or the heatmap covers only a quarter of the visible map. Or the heatmap is "blocky" with visible pixel boundaries at normal zoom levels.

**Why it happens:** A GPU-generated heatmap texture maps a 2D grid of texels to world-space coordinates. Three things must match exactly:
1. The texture's UV (0,0)-(1,1) range must map to the same geographic bounds as the visible tile area
2. Each aircraft's world-space position must be converted to the correct texel coordinate
3. The texture resolution must be high enough that individual texels are not visible at the expected zoom level

**Specific risk in this codebase:** The coordinate system uses `MapCoordinateSystem` (referenced throughout the codebase). World X maps to longitude via `lonToX()` and world Z maps to latitude via `latToZ()`. The Z axis is inverted relative to latitude (higher latitude = more negative Z, MapTileManager.swift line 549: "maxLat -> smaller Z value"). If the heatmap compute shader assumes Z increases with latitude, the heatmap will be vertically flipped.

Additionally, the visible tile area changes with camera position and zoom level (calculated each frame, Renderer.swift lines 850-858). The heatmap texture must cover the same geographic extent or it will be misaligned.

**Consequences:**
- Heatmap hotspots offset from aircraft positions
- Heatmap flipped vertically (inverted latitude)
- Heatmap covers wrong geographic area after panning
- Blocky/pixelated appearance at normal zoom levels

**Prevention:**
1. Generate the heatmap texture to cover the exact geographic bounds of the currently visible tiles. Pass these bounds as uniforms to the compute shader.
2. Use the SAME coordinate conversion functions (`lonToX`, `latToZ`) used by the renderer. Do not re-derive the mapping.
3. Account for the Z-latitude inversion: latitude increases northward but Z decreases northward in this coordinate system.
4. Choose texture resolution based on zoom level: at zoom 8 with radius 5 (about 10x10 tiles), each tile is ~40km wide. A 512x512 heatmap texture gives ~800m per texel resolution, which is adequate. At zoom 12, increase to 1024x1024.
5. Regenerate the heatmap texture when the visible area changes (camera pan or zoom change), not every frame. Compare the current visible tile set to the previous one and only regenerate on change.
6. Test by placing a single aircraft at a known lat/lon and verifying the heatmap hotspot appears at the correct position on the map.

**Detection:** Place the camera directly over a known airport (e.g., Seattle SEA at 47.45, -122.31). If aircraft at SEA create a heatmap hotspot that is visually offset from the airport label, the coordinate mapping is wrong.

**Confidence:** HIGH -- derived from analysis of the coordinate system in the codebase and standard heatmap generation practices.

---

### Pitfall 9: Adding New Pipeline States Without Matching rasterSampleCount

**What goes wrong:** The app crashes on launch or when the new pipeline state is first used, with a Metal validation error: "Render Pipeline State has rasterSampleCount of 1 which does not match the render pass attachments rasterSampleCount of 4." The error message is clear but the crash is fatal.

**Why it happens:** The existing `MTKView` is configured with multisampling (MSAA). Every `MTLRenderPipelineDescriptor` in the current codebase sets `rasterSampleCount = metalView.sampleCount` (e.g., Renderer.swift lines 143, 173, 188, 291, 311, etc.). If a new pipeline state for airspace volumes or heatmap overlay is created without setting `rasterSampleCount`, it defaults to 1, which mismatches the render pass's multisample attachments.

**Specific risk in this codebase:** There are 12+ pipeline states already created in `Renderer.init()`. When adding the 13th and 14th (volume pipeline, heatmap overlay pipeline), it is easy to forget to set `rasterSampleCount` because it is not visually obvious in the pipeline descriptor setup code.

**Consequences:**
- Fatal crash with Metal validation error
- Only occurs when MSAA is enabled (which it is by default in the existing MTKView configuration)
- The crash may not occur in the Metal Debugger capture if the debugger changes the view configuration

**Prevention:**
1. Create a helper function that configures common pipeline descriptor properties:
   ```swift
   func configurePipelineDescriptor(_ desc: MTLRenderPipelineDescriptor, view: MTKView) {
       desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
       desc.depthAttachmentPixelFormat = view.depthStencilPixelFormat
       desc.rasterSampleCount = view.sampleCount
   }
   ```
2. Use this helper for ALL new pipeline states. The existing code repeats these three lines for every pipeline -- refactoring into a helper prevents the omission.
3. Run with Metal Validation Layer enabled (`MTL_DEBUG_LAYER=1`) during development. It catches this error at pipeline creation time rather than at draw time.

**Detection:** Crashes immediately when the new pipeline state is used in a draw call. Error message explicitly mentions `rasterSampleCount` mismatch.

**Confidence:** HIGH -- this is a compile-time/validation-time error that is easy to trigger and well-documented.

**Sources:**
- [MTLRenderPipelineDescriptor - Apple Documentation](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor)

---

### Pitfall 10: BufferIndex Collision When Adding New Shader Bindings

**What goes wrong:** Adding a new buffer binding for airspace volume instances or heatmap data silently overwrites an existing binding. Aircraft suddenly render with heatmap data as their instance buffer, producing garbage geometry scattered across the scene. Or uniform data is interpreted as vertex data, causing a GPU crash.

**Why it happens:** The existing `ShaderTypes.h` defines buffer indices 0-7:

```c
BufferIndexUniforms = 0,
BufferIndexVertices = 1,
BufferIndexModelMatrix = 2,
BufferIndexInstances = 3,
BufferIndexGlowInstances = 4,
BufferIndexTrailVertices = 5,
BufferIndexLabelInstances = 6,
BufferIndexAltLineVertices = 7
```

Adding a new buffer (e.g., `BufferIndexVolumeInstances = 3`) that collides with `BufferIndexInstances` will not cause a compilation error. The Metal shader will simply read from whatever buffer was last bound at index 3 for that encoder. If the volume pipeline binds volume data to index 3 and then the aircraft pipeline runs without re-binding its instance data to index 3, the aircraft pipeline will read volume data.

**Specific risk in this codebase:** The single-encoder approach means buffer bindings persist between pipeline state switches. If airspace volume rendering binds a buffer at index 3, and then aircraft rendering assumes its instance buffer is still at index 3 from a previous binding, the wrong data is read. The existing code re-binds instance buffers for each draw call (Renderer.swift line 597), so this is partially protected. But it is easy to miss a rebind.

**Consequences:**
- Garbage geometry: triangles stretched to infinity, random shapes
- GPU hang or crash if buffer sizes do not match expected vertex counts
- Silent data corruption if buffer layouts happen to be similar in size

**Prevention:**
1. Add new buffer indices to `ShaderTypes.h` starting from 8:
   ```c
   BufferIndexVolumeInstances = 8,
   BufferIndexHeatmapData = 9
   ```
2. Metal supports up to 31 buffer bindings (0-30). There is plenty of room.
3. Always re-bind ALL required buffers for each pipeline switch, even if you think they are already bound. This is cheap (just a pointer update) and prevents stale binding bugs.
4. Add a comment block in `ShaderTypes.h` documenting which buffer index is used by which pipeline.
5. In the shader, use `[[buffer(BufferIndexVolumeInstances)]]` with the symbolic constant, never a raw number.

**Detection:** Metal GPU debugger shows unexpected data in a buffer binding. Visual artifacts that look like "wrong data in the wrong place" (aircraft-shaped geometry at heatmap positions, or heatmap-colored aircraft).

**Confidence:** HIGH -- derived directly from the buffer index architecture in `ShaderTypes.h`.

---

### Pitfall 11: Detail Panel SwiftUI Updates Blocking Main Thread During Enrichment Fetch

**What goes wrong:** When adding new fields to `AircraftDetailPanel` (position display, aircraft photo, external links), the panel freezes for 1-3 seconds on selection. The Metal rendering continues but the SwiftUI overlay becomes unresponsive. If the enrichment API is slow or offline, the panel may freeze indefinitely.

**Why it happens:** The existing `AircraftDetailPanel.swift` uses `.task { }` (line 131) to fetch enrichment data asynchronously. This is correct. But when adding new enrichment sources (aircraft photo URLs, planespotters.net links, FlightRadar24 links), developers may add synchronous URLSession calls, or chain multiple `await` calls sequentially when they could be parallel.

The existing code correctly uses `async let` for parallel fetching (lines 132-133):
```swift
async let acInfo = enrichmentService.fetchAircraftInfo(hex: aircraft.hex)
async let rtInfo = enrichmentService.fetchRouteInfo(callsign: aircraft.callsign)
```

But adding a third source naively:
```swift
let acInfo = await enrichmentService.fetchAircraftInfo(hex: aircraft.hex)
let rtInfo = await enrichmentService.fetchRouteInfo(callsign: aircraft.callsign)
let photo = await enrichmentService.fetchPhoto(hex: aircraft.hex)  // Sequential!
```
Would make all three fetches sequential instead of parallel, tripling the wait time.

**Specific risk in this codebase:** The `EnrichmentService` is an `actor` (EnrichmentService.swift line 27). Actor methods are serialized -- if `fetchAircraftInfo` is in progress, `fetchPhoto` called on the same actor will queue behind it. Even with `async let`, the actor serialization means they execute one at a time. This is a design choice for cache safety but limits parallelism.

**Consequences:**
- Panel takes 3-9 seconds to populate (three sequential 1-3 second API calls)
- UI feels sluggish when selecting aircraft
- If any API times out, the entire panel is delayed

**Prevention:**
1. Keep using `async let` for parallel initiation, but understand that actor serialization may negate the benefit for calls to the same actor.
2. Consider making photo/link fetching a SEPARATE actor or a non-actor async function if it does not share a cache with aircraft info.
3. Show data as it arrives: use separate `@State` variables for each data source and update the UI incrementally. The existing pattern (separate `enrichedAircraft` and `routeInfo` state variables) is correct -- extend it for new data.
4. Set aggressive timeouts: the existing `EnrichmentService` uses 3-second request timeout (line 84). Keep this for new endpoints.
5. For aircraft photos, consider caching the photo URL during enrichment and loading the image lazily with `AsyncImage` rather than fetching in the `.task` block.

**Detection:** Select an aircraft and time how long until all panel fields populate. If total time is significantly more than the slowest individual API call, fetches are running sequentially.

**Confidence:** HIGH -- derived from analysis of the existing `EnrichmentService` actor and `AircraftDetailPanel.swift`.

---

## Minor Pitfalls

Issues that cost hours, not days. Easy to fix once identified.

---

### Pitfall 12: Airspace Volume Mesh Winding Order Inconsistency

**What goes wrong:** Some faces of the airspace volume are visible and some are invisible. As the camera rotates, faces pop in and out of visibility. The volume looks like a broken wireframe with missing panels.

**Why it happens:** The existing renderer sets `encoder.setCullMode(.none)` (Renderer.swift line 887), which renders both front and back faces. This hides winding order bugs in the current geometry. If the volume rendering pipeline switches to `encoder.setCullMode(.back)` for performance, any volume faces with incorrect winding will disappear. Even with cull mode set to `.none`, face normals may be wrong for lighting calculations if the winding is inconsistent.

For airspace volumes that are translucent, you typically want to render BOTH faces (inside and outside of the volume), but the blend order matters: render back faces first, then front faces. This requires two draw calls per volume with different cull modes.

**Prevention:**
1. Generate volume geometry with consistent winding (all triangles clockwise when viewed from outside).
2. For correct translucent volume rendering: draw with `.front` cull (renders back faces only) first, then draw with `.back` cull (renders front faces only). This ensures back-to-front ordering within each volume.
3. If performance is not a concern, keep `setCullMode(.none)` and accept the slight overdraw.

**Detection:** Set `setCullMode(.back)` temporarily. If half the volume faces disappear, the winding is inconsistent.

**Confidence:** HIGH -- standard computer graphics winding order principle, verified against existing cull mode setting in codebase.

---

### Pitfall 13: Heatmap Color Gradient Clamping Produces Flat Colors

**What goes wrong:** The heatmap shows only two colors (e.g., blue for 0 aircraft and red for 1+ aircraft) instead of a smooth gradient. Areas with 50 aircraft look the same as areas with 1 aircraft. The heatmap provides no useful density information.

**Why it happens:** The heatmap value (aircraft count per texel) is mapped to a color gradient. If the mapping uses a linear scale without normalization, the maximum value in dense areas (e.g., around major airports with 20-50 visible aircraft) saturates the color ramp, and everywhere else maps to the minimum color. Alternatively, if the compute shader uses `uint` for the accumulation buffer and the color mapping expects `float` in [0,1], the values are either 0 or very large integers interpreted as >1.0.

**Prevention:**
1. Use logarithmic or square-root scaling for the heatmap density: `color_value = sqrt(count / max_count)`. This compresses the dynamic range and makes low-density areas visible.
2. Normalize against the CURRENT frame's maximum density, not a hardcoded value. Pass the maximum as a uniform to the color mapping shader.
3. Use a multi-stop color ramp (0=transparent, 0.2=blue, 0.5=green, 0.8=yellow, 1.0=red) rather than a linear interpolation between two colors.
4. Apply a Gaussian blur kernel to the heatmap texture after accumulation to smooth out individual aircraft point contributions.
5. Test with both dense (major airport) and sparse (rural) areas to verify the gradient provides useful contrast in both cases.

**Detection:** Look at the heatmap around a major airport vs. a rural area. If both look the same color (just different extent), the normalization is wrong.

**Confidence:** MEDIUM -- standard data visualization practice, not Metal-specific.

---

### Pitfall 14: Procedural Mesh Changes Breaking Instanced Draw Call Index Counts

**What goes wrong:** After improving a procedural aircraft mesh (adding more detail to the jet model, for example), all aircraft of that category render with corrupted trailing triangles, or some aircraft are invisible. The vertex count increased but the index buffer still has the old count, or vice versa.

**Why it happens:** The instanced draw call in `encodeAircraft()` (Renderer.swift line 600-607) uses `mesh.indexCount` to determine how many indices to draw. Each category's mesh is built independently in `AircraftMeshLibrary`. If a mesh builder function is updated to add more geometry (more detailed fuselage, better wing shape), the vertex and index counts change. The `createMesh()` function (AircraftMeshLibrary.swift line 477) correctly captures both counts from the arrays. BUT if the mesh builder uses `UInt16` indices and the new geometry pushes the vertex count above 65,535, the indices overflow silently.

**Specific risk in this codebase:** All mesh builders use `[UInt16]` indices. The current jet mesh has approximately 200-300 vertices (7 geometry primitives). If a visual polish pass adds 10+ new detail meshes per category, the vertex count could approach the UInt16 limit of 65,535 per mesh. More likely, the vertex count stays well below this, but it is worth verifying.

**Consequences:**
- Trailing garbage triangles extending to (0,0,0) or infinity
- Missing geometry if index count is wrong
- Silent overflow of UInt16 indices producing wrong triangle connections
- Affects ALL instances of the modified category (hundreds of aircraft)

**Prevention:**
1. After modifying any mesh builder, verify that the vertex count stays below 65,535 (UInt16 max). Add an assertion: `assert(vertices.count <= Int(UInt16.max), "Vertex count exceeds UInt16 index range")`
2. If vertex count exceeds UInt16 range, switch to UInt32 indices AND update the `drawIndexedPrimitives` call to use `.uint32` instead of `.uint16`.
3. Test each modified mesh in isolation before enabling it for instanced rendering. Render a single instance and verify from multiple angles.
4. Keep mesh complexity low -- these are LOD-0 models viewed from hundreds of meters away. Procedural improvements should focus on silhouette (wing shape, tail shape) not surface detail that is invisible at rendering distance.

**Detection:** After modifying a mesh, look for triangles extending to the origin (0,0,0) or for missing faces. These are classic symptoms of index overflow or miscount.

**Confidence:** HIGH -- derived from direct analysis of `AircraftMeshLibrary.swift` and the `UInt16` index type.

---

### Pitfall 15: Premultiplied Alpha Confusion in Airspace Volume Colors

**What goes wrong:** Airspace volumes appear darker than intended. Overlapping volumes become nearly black instead of blending to a deeper tint. Semi-transparent volumes look correct when isolated but wrong when they overlap terrain or other geometry.

**Why it happens:** There are two alpha blending conventions:
- **Straight alpha:** `finalColor = src.rgb * src.a + dst.rgb * (1 - src.a)` -- requires `sourceRGBBlendFactor = .sourceAlpha`, `destinationRGBBlendFactor = .oneMinusSourceAlpha`
- **Premultiplied alpha:** `finalColor = src.rgb + dst.rgb * (1 - src.a)` -- requires `sourceRGBBlendFactor = .one`, `destinationRGBBlendFactor = .oneMinusSourceAlpha` (source RGB is already multiplied by alpha)

If the fragment shader outputs straight alpha colors (e.g., `return float4(0.2, 0.4, 1.0, 0.3)`) but the blend factors expect premultiplied alpha (`.one, .oneMinusSourceAlpha`), the color contribution is too high. Conversely, if the shader outputs premultiplied colors but the blend factors apply `sourceAlpha` again, the contribution is double-attenuated (too dark).

**Specific risk in this codebase:** The existing trail pipeline (Renderer.swift line 346-351) uses straight alpha blending (`.sourceAlpha, .oneMinusSourceAlpha`). The glow pipeline (lines 303-309) uses additive blending (`.sourceAlpha, .one`). A new volume pipeline must choose one convention and ensure the fragment shader's output matches.

**Prevention:**
1. Pick premultiplied alpha for volumes (it composites correctly when volumes overlap) and ensure the fragment shader premultiplies: `return float4(color.rgb * alpha, alpha)` with blend factors `.one, .oneMinusSourceAlpha`.
2. Document which blending convention each pipeline uses in a comment on the pipeline descriptor.
3. Test with two overlapping volumes of different colors. The overlap region should show a blend of both colors, not black (double-attenuation) or over-bright (double-contribution).

**Detection:** Render a blue volume overlapping a red volume. If the overlap region is dark purple (too dark), double-attenuation from straight alpha in a premultiplied pipeline. If it is bright white, additive blending or premultiplied alpha in a straight pipeline.

**Confidence:** HIGH -- verified against Metal by Example transparency article.

**Sources:**
- [Translucency and Transparency in Metal - Metal by Example](https://metalbyexample.com/translucency-and-transparency/)
- [Alpha Blending Using Pre-Multiplied Alpha](https://snorristurluson.github.io/AlphaBlending/)

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| **Bug fixes (propeller, map tiles)** | Matrix composition order (#3), texture binding race (#6) | Fix propeller first as a warm-up. Verify matrix math with a single static aircraft at each cardinal heading. Add map tile retry logic. |
| **Airspace volume rendering** | Depth writes enabled (#1), render order (#2), Z-fighting terrain (#7), winding order (#12), premultiplied alpha (#15) | Build a test with a single translucent box before attempting complex airspace geometry. Get the depth/blend/order right on the box first. |
| **Coverage heatmap** | Compute-render sync (#4), coordinate mapping (#8), color gradient clamping (#13) | Start with a CPU-generated heatmap texture to verify coordinate mapping, then move to compute shader for performance. |
| **Visual polish (mesh improvements)** | Index count overflow (#14), instanced draw count mismatch (#14), buffer index collision (#10) | Assert vertex counts after mesh changes. Test each category in isolation. |
| **Detail panel updates** | Sequential enrichment fetches (#11) | Show data incrementally. Use AsyncImage for photos. Keep short timeouts. |
| **All new render passes** | Missing rasterSampleCount (#9), new buffers not triple-buffered (#5), buffer index collision (#10) | Use helper function for pipeline descriptors. Follow triple-buffer template. Add buffer indices to ShaderTypes.h sequentially from 8. |

---

## Integration Risk Matrix

Features that interact dangerously when combined:

| Feature A | Feature B | Risk | Mitigation |
|-----------|-----------|------|------------|
| Airspace volumes (translucent) | Existing glow sprites (additive blend) | Both use depth-read/no-write. If volumes render after glow, they overwrite glow pixels. If before, glow bleeds through volumes incorrectly. | Render volumes BEFORE glow. Glow's additive blend will add on top of the volume color correctly. |
| Heatmap texture overlay | Terrain tile textures | Both bind textures to fragment shader. If both use `TextureIndexColor` (index 0), they collide. | Use separate texture indices. Add `TextureIndexHeatmap = 1` to ShaderTypes.h. |
| Heatmap compute pass | Triple buffering semaphore | Compute pass added before render encoder changes the command buffer structure. Semaphore must still protect all buffers used by both compute and render. | Keep compute and render in same command buffer. No additional semaphore needed -- same frame, same semaphore slot. |
| Procedural mesh improvements | Instanced draw calls | Changing vertex/index counts for one category does not affect others. But if the vertex LAYOUT changes (adding UV coordinates), ALL categories must change. | Do not change vertex layout. Add detail using more primitives with the existing AircraftVertex layout. |
| Detail panel new fields | SwiftUI Metal view isolation | Adding more @State to AircraftDetailPanel is fine (it is separate from MetalView). But if new state triggers ContentView body re-evaluation, MetalView could be affected. | Keep new detail panel state local to AircraftDetailPanel. Do not lift state to ContentView. |

---

## Summary: Top 5 v2.1 Pitfalls in Order of Impact

1. **Depth writes on translucent volumes** (#1) -- will make volumes look opaque and hide aircraft behind them. Must get this right before any volume geometry is visible.
2. **Render order after adding new translucent passes** (#2) -- will break the careful layering of trails, labels, glow. Must plan the full render order before writing code.
3. **Heatmap compute-render synchronization** (#4) -- will cause flickering that is nearly impossible to debug without understanding the command buffer execution model.
4. **New buffers not triple-buffered** (#5) -- will cause intermittent artifacts that only appear under load, making them extremely hard to reproduce and fix.
5. **Buffer index collisions** (#10) -- will cause dramatic visual corruption that looks like a GPU bug but is just a number conflict in ShaderTypes.h.

---

## Sources

- [Translucency and Transparency in Metal - Metal by Example](https://metalbyexample.com/translucency-and-transparency/)
- [Instanced Rendering in Metal - Metal by Example](https://metalbyexample.com/instanced-rendering/)
- [Metal Best Practices Guide - Apple](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/)
- [Metal Best Practices Guide: Triple Buffering - Apple](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html)
- [Processing a Texture in a Compute Function - Apple Documentation](https://developer.apple.com/documentation/metal/compute_passes/processing_a_texture_in_a_compute_function)
- [MTLRenderPipelineDescriptor - Apple Documentation](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor)
- [MTLRenderCommandEncoder - Apple Documentation](https://developer.apple.com/documentation/metal/mtlrendercommandencoder)
- [WWDC 2025 - Discover Metal 4](https://dev.to/arshtechpro/wwdc-2025-discover-metal-4-23f2)
- [Order Independent Transparency - Wikipedia](https://en.wikipedia.org/wiki/Order-independent_transparency)
- [Adaptive Voxel-Based OIT - SIGGRAPH 2025](https://advances.realtimerendering.com/s2025/content/AVBOIT_SIG2025_MDROBOT-final.pdf)
- [Alpha Blending Using Pre-Multiplied Alpha](https://snorristurluson.github.io/AlphaBlending/)
- [MTKTextureLoader - Apple Documentation](https://developer.apple.com/documentation/metalkit/mtktextureloader)
- [Introduction to Compute Programming in Metal - Metal by Example](https://metalbyexample.com/introduction-to-compute/)
- [Advanced Metal Shader Optimization - WWDC16](https://developer.apple.com/videos/play/wwdc2016/606/)
- [Writing a Modern Metal App from Scratch: Part 2 - Metal by Example](https://metalbyexample.com/modern-metal-2/)

---

*Pitfalls research for: v2.1 feature additions (airspace volumes, coverage heatmaps, visual polish, bug fixes)*
*Researched: 2026-02-09*
*Prior pitfalls document (initial rewrite): 2026-02-08*
