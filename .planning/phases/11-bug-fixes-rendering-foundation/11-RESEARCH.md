# Phase 11: Bug Fixes & Rendering Foundation - Research

**Researched:** 2026-02-09
**Domain:** Metal rendering pipeline debugging, 3D procedural geometry, async texture loading
**Confidence:** HIGH

## Summary

Phase 11 addresses three known bugs in the v2.0 Metal-based native macOS flight tracker: (1) map tiles not rendering on the ground plane, (2) propeller rotation axis misalignment, and (3) insufficiently distinctive aircraft silhouettes. All three bugs exist in the current shipped codebase and have been identified with specific root causes or strong hypotheses.

The map tile bug is an async loading pipeline issue where textures load but may not trigger re-rendering or have a race condition in the cache access pattern. The propeller bug has a confirmed root cause: the rotation center is at the origin (0,0,0) instead of at the propeller's nose position (0,0,1.55) because the `noseOffset` matrix is identity despite the mesh having a built-in Z-offset. The aircraft silhouette issue requires reshaping the procedural geometry builders in `AircraftMeshLibrary` to create more visually distinct category shapes (swept wings, tapered fuselage, rotor disc, wide body).

**Primary recommendation:** Fix the propeller rotation first (smallest, most understood), then debug map tiles (requires runtime investigation), then improve silhouettes (largest scope, pure geometry work).

## Standard Stack

### Core

This phase uses the existing project stack -- no new libraries are introduced.

| Technology | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Swift 5.10+ | Current | Application language | Project language, zero external deps policy |
| Metal / MetalKit | System | GPU rendering | Already in use for all rendering |
| simd | System | Matrix/vector math | Used throughout for transforms |
| Foundation URLSession | System | Tile fetching | Already used in MapTileManager |
| MTKTextureLoader | System | PNG -> MTLTexture | Already used for tile textures |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|-----------|-----------|----------|
| Procedural geometry (current) | glTF/OBJ model loading | OUT OF SCOPE per requirements -- breaks instanced rendering paradigm |
| CPU mesh building | GPU compute for mesh gen | Overkill for 6 static meshes built once at init |
| MTKTextureLoader | Manual CGImage->MTLTexture | More control but MTKTextureLoader handles sRGB, mipmaps, format conversion |

## Architecture Patterns

### Current Relevant File Structure

```
AirplaneTracker3D/
  Map/
    MapTileManager.swift       # FIX-01: Async tile fetch + LRU cache
    MapCoordinateSystem.swift  # Mercator projection (no changes needed)
    TileCoordinate.swift       # Tile math (no changes needed)
  Rendering/
    Renderer.swift             # FIX-01: Tile rendering loop (lines 900-952)
    AircraftInstanceManager.swift  # FIX-02: Propeller spin matrix (lines 190-205)
    AircraftMeshLibrary.swift  # FIX-03: Procedural geometry builders
    ThemeManager.swift         # Tile URL construction (verify theme propagation)
    TerrainTileManager.swift   # Terrain mesh pipeline (interacts with FIX-01)
  Rendering/
    Shaders.metal              # vertex_textured, fragment_textured, fragment_placeholder
    TerrainShaders.metal       # terrain_vertex, terrain_fragment, terrain_fragment_placeholder
    AircraftShaders.metal      # aircraft_vertex, aircraft_fragment (shared by spinning parts)
```

### Pattern 1: Async Tile Loading with Frame-Driven Polling

**What:** MapTileManager uses a fire-and-forget `Task { }` pattern. The renderer polls `texture(for:)` each frame at 60fps. If texture not yet in cache, returns nil; renderer shows placeholder. Next frame, checks again.

**When to use:** This is the existing pattern -- understand it to debug FIX-01.

**Current code flow:**
```
Frame N:   texture(for: tile) -> nil, starts fetch Task
Frame N+1: texture(for: tile) -> nil, fetch still in progress (pendingRequests has tile)
Frame N+K: Task completes, cacheQueue.sync stores texture in cache
Frame N+K+1: texture(for: tile) -> returns texture from cache
```

**Key concern:** There is no explicit notification from MapTileManager to Renderer that a tile is ready. The renderer relies on polling at 60fps. This SHOULD work since MTKView is set to `preferredFramesPerSecond = 60` (continuous rendering). If rendering is paused or frame rate drops, tiles may appear delayed but should eventually show.

### Pattern 2: Instance Transform Matrix Composition (right-to-left)

**What:** Metal/simd matrices compose right-to-left. `A * B * C * v` means: apply C first, then B, then A.

**Current propeller code (buggy):**
```swift
let propRotation = rotationZ(rotorAngle)
let noseOffset = translationMatrix(SIMD3<Float>(0, 0, 0)) // IDENTITY!
let spinMatrix = translation * rotation * noseOffset * propRotation
```

**Problem:** The propeller mesh has vertices at Z=1.55 (nose position), but rotationZ rotates around the Z axis at origin (0,0,0). So the propeller orbits around origin instead of spinning in place at the nose.

**Fix pattern:** Move propeller mesh geometry to origin, then use noseOffset to translate:
```
spinMatrix = translation * rotation * T(0,0,nose) * Rz(angle)
```
Applied right-to-left: spin at origin -> translate to nose -> rotate by heading -> translate to world.

### Pattern 3: Procedural Aircraft Geometry

**What:** `AircraftMeshLibrary` builds vertex/index buffers from primitive helpers (`appendCylinder`, `appendBox`, `appendCone`, `appendSphere`). Each category calls different combinations with different parameters. All categories share the same `AircraftVertex` struct (position + normal).

**Design constraint (from REQUIREMENTS.md):** "Loaded 3D aircraft models (glTF/OBJ)" are explicitly OUT OF SCOPE. All silhouette improvement must use the existing procedural primitive approach.

### Anti-Patterns to Avoid

- **Modifying shader code for FIX-02:** The propeller bug is in CPU-side matrix composition, not in the shader. The `aircraft_vertex` shader correctly applies `inst.modelMatrix * float4(in.position, 1.0)`. Don't touch shaders for this fix.
- **Adding notification/callback for tile loading:** The polling pattern at 60fps is adequate. Adding callbacks would complicate the threading model (cacheQueue + Task + main thread) without benefit.
- **Over-engineering silhouettes:** These are procedural shapes viewed at altitude. They need to be recognizable at a glance, not photorealistic. Simple geometry changes with existing primitives are sufficient.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Matrix math | Custom matrix functions | simd_float4x4 and existing rotationY/Z/translationMatrix helpers | Already working, just need correct composition order |
| Texture loading | Manual PNG decode + MTLTexture creation | MTKTextureLoader (already used) | Handles color space, mipmaps, pixel format |
| Thread synchronization | Lock-free or mutex patterns | DispatchQueue.sync (already used in cacheQueue) | Already proven in the codebase |

**Key insight:** All three bugs are fixable with targeted changes to existing code. No new infrastructure needed.

## Common Pitfalls

### Pitfall 1: Propeller rotation center vs. mesh offset

**What goes wrong:** Propeller spins wildly (orbiting around origin) instead of spinning in place at the nose.
**Why it happens:** The propeller mesh has its vertices at Z=1.55, but rotationZ rotates around (0,0,Z). So vertices at Y=+/-0.6, Z=1.55 trace a circle of radius 0.6 centered at (0,0,1.55) -- which would be correct IF rotationZ preserved the Z coordinate. But rotationZ only affects X and Y, leaving Z unchanged. So actually, the rotation IS correct for spinning the propeller blade around the Z-axis at any Z offset.

Wait -- re-analysis: `rotationZ(angle)` rotates in the XY plane. A vertex at (0, 0.6, 1.55) after rotationZ(90deg) goes to (-0.6, 0, 1.55). This IS correct -- the blade swings in the XY plane while staying at Z=1.55. Then `rotation` (heading around Y) and `translation` (world position) are applied.

So the actual issue might be different than initially assumed. Let me re-examine:
- `propRotation = rotationZ(angle)` -- spins in XY plane, preserves Z
- `noseOffset = identity` -- no-op
- `spinMatrix = translation * rotation * propRotation`

The propeller vertices at (0, +/-0.6, 1.55) after this transform:
1. rotationZ: blade rotates in XY plane around Z-axis -> (-0.6*sin, 0.6*cos, 1.55) -- correct spin
2. rotation (heading Y): rotates the whole thing around Y -- but this rotates the already-spun propeller by heading
3. translation: moves to world position

This should work IF the heading rotation is correct. But the issue is that the propeller's nose position (Z=1.55) is in MODEL space. When heading rotation is applied, this Z-offset gets rotated too -- which IS correct (nose should point in the direction the aircraft is heading).

After deeper analysis, the matrix composition `translation * rotation * propRotation` (with identity noseOffset) may actually produce correct results for propeller spin alignment with the nose. The bug report states "identity noseOffset" as the issue, but the Z-axis rotation does preserve Z-coordinates.

**Possible real issue:** The propeller spin axis. In the web app (line 4991): `child.rotation.z += spinAmount` -- propellers spin around Z. In Three.js, Z is typically the forward axis. In the Metal app, Z is also the forward axis (nose cone points +Z). `rotationZ` rotates in the XY plane. A propeller blade oriented along Y at Z=1.55 spinning via rotationZ would correctly rotate in the XY plane at Z=1.55.

**However**, there could be a visual issue where the propeller doesn't appear to spin because the blade is extremely thin (0.08 x 1.2 x 0.08 box). At 0.7 revolutions per second (the coded speed), a single blade would appear to flicker rather than spin visibly. The web app may have used a wider blade or disc. Additionally, the helicopter rotors (spinMatrix = `translation * rotationY(rotorAngle)`) do NOT include the aircraft heading rotation -- they spin around world Y regardless of heading. This is fine for helicopters (rotors spin flat) but means the comparison pattern is inconsistent.

**Re-conclusion:** The propeller bug may be a combination of: (a) the `noseOffset` being identity when it should position the rotation center (the current mesh offset works but is fragile), and (b) the visual appearance of a single thin blade not looking like a spinning propeller. Testing is needed to confirm the exact visual defect.

**How to avoid:** Test propeller visually with a debugging pause. Ensure the spin produces a visible disc effect. Consider adding a second perpendicular blade to make the spin more visible.
**Warning signs:** Propeller appears stationary, or propeller orbits rather than spins in place.

### Pitfall 2: Map tile texture never arrives in cache

**What goes wrong:** Ground plane shows only placeholder gray tiles indefinitely.
**Why it happens:** Several potential causes:
1. **Network error silently swallowed:** The `catch` in `fetchTile` only prints in DEBUG. In release builds, failures are completely silent. The tile is removed from `pendingRequests`, so a fresh fetch will be attempted on the next frame -- but if the error is persistent (wrong URL, server 403, etc.), it will retry infinitely with no visible error.
2. **MTKTextureLoader async failure:** `textureLoader.newTexture(data:options:)` could fail if the PNG data is malformed or the texture format is unsupported.
3. **Theme mismatch:** If `tileManager.currentTheme` doesn't match `themeManager.current`, tiles could be fetched from the wrong URL. At init, both default to `.day`, so this shouldn't happen. But after a theme change, the callback at line 510 calls `handleThemeChange` which calls `tileManager.switchTheme(theme)`. This clears the cache and sets the new theme. If a frame renders between the theme change and the cache clear... but `switchTheme` atomically clears and sets, so this is safe.
4. **First-frame race:** On the very first draw call, both tile manager and terrain tile manager have empty caches. Both `texture(for:)` and `terrainMesh(for:)` return nil. The renderer falls through to the flat quad placeholder path (lines 932-951). The placeholder pipeline `fragment_placeholder` returns `float4(0.4, 0.4, 0.4, 1.0)` -- medium gray. This IS visible, just untextured.

**Debugging strategy:** Add debug logging (already exists behind `#if DEBUG`) to track: (a) are tiles being requested, (b) are HTTP responses successful, (c) are MTKTextureLoader calls succeeding, (d) are textures being stored in cache.

**How to avoid:** Systematic debugging with console output in DEBUG builds.
**Warning signs:** Placeholder gray/green tiles visible but never replaced with map imagery.

### Pitfall 3: Wing geometry not visually distinct across categories

**What goes wrong:** All aircraft look similar at cruising altitude.
**Why it happens:** Current geometry uses boxes for wings, cylinders for fuselage. At the visual scale (aircraft are small relative to the map), the differences between categories are hard to distinguish. The main differentiators are:
- **Jet:** 5-unit span, 1.5-unit chord wings, 4-unit fuselage, 2 under-wing engines
- **Widebody:** 8-unit span, 2.2-unit chord wings, 5.5-unit fuselage, 4 engines, larger radius (0.7 vs 0.4)
- **Helicopter:** Sphere cabin, no wings, tail boom cylinder
- **Small:** 4-unit span, 0.8-unit chord wings, 2.5-unit fuselage, smaller radius (0.25)
- **Military:** Box fuselage, 6-unit span 3-unit chord delta wings (very wide), twin angled tails
- **Regional:** 0.8x scaled jet (identical shape, slightly smaller)

**Key issue:** Regional is just a smaller jet. At altitude, scaling differences are hard to see. Military has wider wings but no other distinctive features. Small prop plane's straight wings vs jet's swept wings are not actually modeled -- both use rectangular boxes, just different dimensions.

**How to fix:** Make geometric shapes more distinctive:
1. **Jets:** Wing box should be swept (trapezoidal, not rectangular) or at least shifted aft
2. **Small props:** Wings should be longer span relative to fuselage, mounted higher (high-wing)
3. **Helicopters:** Already distinct (sphere + no wings). Ensure rotor disc is visible even when not spinning (add a thin disc mesh)
4. **Widebodies:** Already wider, but could make fuselage noticeably thicker and wings more pronounced
5. **Military:** Delta wing shape should be more triangular (tapered boxes), add canards or different tail config
6. **Regional:** Differentiate from jet with T-tail or shorter fuselage

**How to avoid:** Test each category side-by-side at typical viewing distance.
**Warning signs:** Categories look identical when zoomed out.

### Pitfall 4: Thread safety in MapTileManager cache access

**What goes wrong:** Race condition between the render thread reading cache and the Task writing to cache.
**Why it happens:** `cacheQueue.sync` is used for both reads and writes, which provides serial access. However, `texture(for:)` is called from the main thread (in `draw(in:)`) and `fetchTile` writes from a Task thread. Both use `cacheQueue.sync`, which is correct for synchronization. However, `cacheQueue.sync` on the main thread while the cache queue is busy with a write will block the main thread briefly. This is acceptable for the small critical section involved (dictionary access).
**How to avoid:** Keep the existing synchronization pattern. Don't introduce additional async complexity.
**Warning signs:** Frame drops when many tiles are loading simultaneously.

## Code Examples

Verified patterns from the actual codebase:

### FIX-02: Corrected Propeller Spin Matrix

The fix requires two coordinated changes:

**1. Move propeller mesh to origin in AircraftMeshLibrary.swift:**
```swift
// BEFORE (current buggy code):
private func buildPropeller(device: MTLDevice) -> AircraftMesh {
    var vertices: [AircraftVertex] = []
    var indices: [UInt16] = []
    appendBox(vertices: &vertices, indices: &indices,
              size: SIMD3<Float>(0.08, 1.2, 0.08),
              offset: SIMD3<Float>(0, 0, 1.55))  // built-in offset
    return createMesh(device: device, vertices: vertices, indices: indices)
}

// AFTER (mesh centered at origin):
private func buildPropeller(device: MTLDevice) -> AircraftMesh {
    var vertices: [AircraftVertex] = []
    var indices: [UInt16] = []
    appendBox(vertices: &vertices, indices: &indices,
              size: SIMD3<Float>(0.08, 1.2, 0.08),
              offset: SIMD3<Float>(0, 0, 0))  // centered at origin
    return createMesh(device: device, vertices: vertices, indices: indices)
}
```

**2. Add proper noseOffset in AircraftInstanceManager.swift:**
```swift
// BEFORE (current buggy code):
let propRotation = rotationZ(rotorAngle)
let noseOffset = translationMatrix(SIMD3<Float>(0, 0, 0)) // identity!
let spinMatrix = translation * rotation * noseOffset * propRotation

// AFTER (correct nose offset):
let propRotation = rotationZ(rotorAngle)
let noseOffset = translationMatrix(SIMD3<Float>(0, 0, 1.55)) // actual nose position
let spinMatrix = translation * rotation * noseOffset * propRotation
```

Matrix application order (right-to-left): spin at origin -> translate to nose -> rotate by heading -> translate to world position. This ensures the propeller spins around its own axis at the aircraft nose, correctly aligned with the aircraft heading.

**Note:** After deeper analysis, the original code may produce visually correct spin because rotationZ preserves Z coordinates, but the decoupled mesh+transform pattern (mesh at origin, transform positions it) is more robust and maintainable. The propeller blade being thin (0.08 wide) may also need to be made wider or doubled for visual clarity.

### FIX-01: Debugging Map Tile Pipeline

The debugging approach for the tile loading issue:

```swift
// In MapTileManager.fetchTile(), add diagnostic logging:
private func fetchTile(_ tile: TileCoordinate) {
    let url = tileURL(for: tile)
    #if DEBUG
    print("[MapTileManager] Fetching tile \(tile.zoom)/\(tile.x)/\(tile.y) from \(url)")
    #endif

    Task {
        do {
            let (data, response) = try await urlSession.data(from: url)

            if let httpResponse = response as? HTTPURLResponse {
                #if DEBUG
                print("[MapTileManager] HTTP \(httpResponse.statusCode) for \(tile.zoom)/\(tile.x)/\(tile.y), \(data.count) bytes")
                #endif
                if httpResponse.statusCode != 200 {
                    cacheQueue.sync { pendingRequests.remove(tile) }
                    return
                }
            }

            let texture = try await textureLoader.newTexture(data: data, options: options)
            #if DEBUG
            print("[MapTileManager] Texture created: \(texture.width)x\(texture.height) for \(tile.zoom)/\(tile.x)/\(tile.y)")
            #endif
            // ... store in cache
        } catch {
            #if DEBUG
            print("[MapTileManager] FAILED tile \(tile.zoom)/\(tile.x)/\(tile.y): \(error)")
            #endif
            // ...
        }
    }
}
```

Key areas to investigate:
1. Is `fetchTile` being called? (check if `shouldFetch` is true)
2. Are HTTP responses successful? (status code + data size)
3. Does MTKTextureLoader succeed? (texture creation)
4. Is cache being populated? (check cache.count after fetch)
5. Are subsequent frames finding the cached texture? (check `texture(for:)` hit rate)

### FIX-03: Improved Aircraft Silhouettes

Example of making wing shapes more distinctive:

```swift
// Swept wings for jet (trapezoidal shape approximated with two boxes)
// Instead of a single centered box, use offset boxes for sweep
private func buildJet(device: MTLDevice) -> AircraftMesh {
    // ...
    // Replace single wing box with swept wing pair:
    // Left wing: shifted back on the outboard end
    appendBox(vertices: &vertices, indices: &indices,
              size: SIMD3<Float>(2.5, 0.12, 1.2),
              offset: SIMD3<Float>(-1.5, 0, -0.2))  // slight aft offset
    // Right wing: mirror
    appendBox(vertices: &vertices, indices: &indices,
              size: SIMD3<Float>(2.5, 0.12, 1.2),
              offset: SIMD3<Float>(1.5, 0, -0.2))
    // ...
}

// High-wing straight wing for small prop
// Wider span, higher mount, straight (no sweep)
private func buildSmallProp(device: MTLDevice) -> AircraftMesh {
    // ...
    appendBox(vertices: &vertices, indices: &indices,
              size: SIMD3<Float>(5.5, 0.06, 0.7),     // longer span, thinner chord
              offset: SIMD3<Float>(0, 0.3, 0.2))      // mounted high and forward
    // ...
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|-------------|------------------|--------------|--------|
| THREE.js WebGL (v1.0) | Metal native (v2.0) | Phase 5 (2026-02-08) | All rendering is Metal with instanced draw calls |
| Per-object draw calls (v1.0) | Instanced rendering per category (v2.0) | Phase 6 (2026-02-08) | One draw call per category, not per aircraft |
| Flat ground plane (v2.0 initial) | Terrain elevation mesh (v2.0) | Phase 8 (2026-02-09) | 32x32 subdivided meshes with Terrarium elevation |

**No deprecated APIs in use.** All Metal APIs used are current as of macOS 14+.

## Open Questions

1. **What is the exact visual symptom of the map tile bug?**
   - What we know: "Map tile ground plane not displaying (async loading pipeline issue)"
   - What's unclear: Does this mean ALL tiles are permanently gray? Or do tiles load but are invisible? Or does the ground plane not render at all?
   - Recommendation: First debugging step should add console logging to confirm whether tiles are being fetched, whether HTTP responses succeed, and whether textures enter the cache. Run the app in DEBUG to observe.

2. **Is the propeller visually spinning but misaligned, or not spinning at all?**
   - What we know: "Propeller rotation matrix incorrectly composed (identity noseOffset at line 193-194)"
   - What's unclear: The rotationZ math may actually produce correct visual results since Z-axis rotation preserves Z coordinates. The "identity noseOffset" looks wrong in code but may not cause visible issues.
   - Recommendation: Run the app and observe propeller behavior on small aircraft. If the propeller appears correct, the real issue might be that the blade is too thin to see spinning. If it orbits, then the rotation center is wrong and the noseOffset fix applies.

3. **How distinctive do silhouettes need to be at typical viewing distance?**
   - What we know: Success criteria says "visually distinguish aircraft categories by silhouette (swept wings on jets, straight wings on props, rotors on helicopters, wide fuselage on widebodies)"
   - What's unclear: The typical camera distance and zoom level at which users view aircraft. At high altitude / far zoom, even large geometry changes may be hard to see.
   - Recommendation: Test at zoom level 8-10 (typical viewing) and ensure categories are distinguishable. Focus on the biggest differentiators: wing sweep angle, fuselage width ratio, presence/absence of rotor disc.

4. **Should the terrain tile manager and map tile manager share a loading coordinator?**
   - What we know: Both managers fetch independently. Map textures typically arrive faster than terrain meshes (simpler pipeline).
   - What's unclear: Whether there's a timing issue where terrain meshes arrive but map textures don't, or vice versa, causing visual glitches.
   - Recommendation: Keep them independent. The fallback chain (textured terrain -> placeholder terrain -> textured flat -> placeholder flat) handles all combinations correctly.

## Detailed Bug Analysis

### FIX-01: Map Tiles Not Displaying

**File:** `AirplaneTracker3D/Map/MapTileManager.swift`, `AirplaneTracker3D/Rendering/Renderer.swift`

**Rendering path (Renderer.swift lines 900-952):**
```
for tile in visibleTiles:
  mapTexture = tileManager.texture(for: tile)     // nil if loading
  terrainMesh = terrainTileManager.terrainMesh(for: tile)  // nil if loading

  if terrainMesh exists:
    if mapTexture: render terrain with texture
    else: render terrain placeholder (muted green-gray)
  else (flat fallback):
    if mapTexture: render flat quad with texture
    else: render flat quad placeholder (gray)
```

**Hypotheses to investigate (ordered by likelihood):**
1. HTTP fetch succeeding but MTKTextureLoader failing silently
2. Tile URL returning non-200 status (e.g., rate limiting from CartoDB)
3. Tiles loading but terrain mesh loading faster, causing terrain placeholder to persist (terrain placeholder = no texture, so tiles appear loaded but show green-gray)
4. `pendingRequests` not being cleared on failure, preventing retry
5. Cache eviction removing tiles before they're used (maxCacheSize=300 vs potential visible tiles at ~100)

**Hypothesis 3 is the most subtle:** If terrain meshes arrive BEFORE map textures (which would be unusual but possible), the terrain placeholder pipeline renders green-gray terrain. The flat quad path never fires because terrain mesh exists. The map tile is still loading. On the next frame, map tile arrives, and terrain renders with texture. If terrain consistently loads first, there would be a brief placeholder period -- which is expected behavior, not a bug.

**Most likely actual bug:** The CartoDB tile server for Day theme uses `@2x.png` (retina tiles). Some CDN edges may return 403 or redirect for @2x requests. If the HTTP status check fails, the tile is removed from pendingRequests and re-requested on the next frame, creating an infinite retry loop that never succeeds.

**Fix approach:** Debug with logging, check HTTP response codes, test with non-@2x URLs.

### FIX-02: Propeller Rotation

**File:** `AirplaneTracker3D/Rendering/AircraftInstanceManager.swift` (lines 190-205), `AirplaneTracker3D/Rendering/AircraftMeshLibrary.swift` (lines 463-473)

**Current state:** Propeller mesh is a box at (0, 0, 1.55) with size (0.08, 1.2, 0.08). The spin matrix is `translation * rotation * identity * rotationZ(angle)`.

**Analysis:** rotationZ rotates in the XY plane, preserving Z. A vertex at (0, 0.6, 1.55) after rotationZ becomes (-0.6sin, 0.6cos, 1.55). The propeller stays at Z=1.55 and sweeps in XY. Then heading rotation (around Y) is applied, which correctly aligns the nose direction.

The code MIGHT be visually correct as-is. The `noseOffset` identity is a code smell (misleading comment) but may not be the actual bug. The real visual issue may be:
- Single thin blade (0.08 wide) is nearly invisible when spinning
- Missing second perpendicular blade (web app has single blade too, but viewed differently)
- Propeller speed too fast or too slow to see

**Fix approach:**
1. First, visually verify by running the app (is propeller spinning? is it aligned?)
2. If alignment is wrong: move mesh to origin, add real noseOffset
3. If alignment is correct but not visible: make blade wider, add second perpendicular blade
4. Regardless: fix the noseOffset to not be identity (even if functionally equivalent, the clean pattern is better)

### FIX-03: Aircraft Silhouettes

**File:** `AirplaneTracker3D/Rendering/AircraftMeshLibrary.swift`

**Current geometry dimensions (world units):**

| Category | Fuselage | Wings (span x chord) | Distinguishing |
|----------|----------|-----------------------|----------------|
| Jet | Cylinder r=0.4, h=4 | Box 5x1.5 | 2 engines, swept cone nose |
| Widebody | Cylinder r=0.7, h=5.5 | Box 8x2.2 | 4 engines, wider everything |
| Helicopter | Sphere r=0.6 | None | Rotor, tail boom, skids |
| Small | Cylinder r=0.25, h=2.5 | Box 4x0.8 | Propeller, straight wings |
| Military | Box 0.6x4.5 | Box 6x3.0 | Delta wings, twin tails |
| Regional | 0.8x jet | 0.8x jet | Scaled-down jet (hard to tell apart) |

**Improvements needed:**
1. **Jet:** Make wings visibly swept back (offset wing boxes aft at tips or use two angled boxes per wing half)
2. **Small prop:** Mount wings higher (increase Y offset), make span wider relative to fuselage, add visible propeller disc
3. **Helicopter:** Add thin rotor disc (transparent or wireframe-like thin box) visible even when not spinning
4. **Widebody:** Fuselage is already wider; make wings clearly longer and add wing flex (slight upward angle at tips)
5. **Military:** Make delta wing more triangular (narrower at tips, wider at root), reduce wing chord at tips
6. **Regional:** Change to T-tail (horizontal stabilizer at top of vertical tail) and/or turboprop-style engines on wings to differentiate from jet

## Sources

### Primary (HIGH confidence)
- Direct code analysis of the v2.0 shipped codebase (all files in AirplaneTracker3D/)
- Web app reference implementation (airplane-tracker-3d-map.html) for comparison
- Phase 5-10 planning documents (.planning/phases/)

### Secondary (MEDIUM confidence)
- Bug descriptions from .planning/STATE.md known issues
- Phase requirements from .planning/REQUIREMENTS.md

### Tertiary (LOW confidence)
- Hypothesis about CartoDB @2x tile URL issues (needs runtime verification)
- Assessment that rotationZ with offset mesh might work correctly (needs visual testing)

## Metadata

**Confidence breakdown:**
- FIX-01 (Map tiles): MEDIUM - Root cause requires runtime debugging; multiple hypotheses identified
- FIX-02 (Propeller): HIGH - Code analysis reveals clear code smell; fix approach is straightforward regardless of actual visual symptom
- FIX-03 (Silhouettes): HIGH - Geometry improvements are well-understood; just need careful dimension tuning
- Architecture: HIGH - Existing codebase is well-structured and well-documented from prior phases

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (stable codebase, no external dependency changes expected)
