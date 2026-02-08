# Phase 8: Terrain + Themes - Research

**Researched:** 2026-02-09
**Domain:** Metal terrain rendering, theme system architecture, airport ground labels
**Confidence:** HIGH

## Summary

Phase 8 adds three major capabilities to the native Metal app: (1) terrain elevation from Terrarium-format RGB tiles with vertex displacement on subdivided meshes, (2) a theme system that switches the entire visual character across all render passes, and (3) 3D text labels for airports projected on the ground plane. The v1.0 web app has working implementations of all three, providing a proven reference for color palettes, terrain decoding, and airport data sourcing.

The terrain system mirrors the existing `MapTileManager` pattern -- async fetch PNG tiles, decode elevation from RGB channels, build a subdivided mesh per tile with displaced vertices. The theme system is a data-driven color/mode struct passed as uniforms to all shaders, plus a `setTriangleFillMode(.lines)` call for retro wireframe. Airport labels reuse the existing `LabelManager` CoreText-to-atlas pattern but position labels at ground level with a flat orientation instead of billboarding.

**Primary recommendation:** Build a `TerrainTileManager` parallel to `MapTileManager` that fetches Terrarium PNG tiles, decodes elevation, and generates per-tile subdivided meshes. Implement themes as a `ThemeConfig` struct with color values passed through uniforms to all shaders. Keep the airport database as a small embedded JSON of ~500 major airports rather than fetching the 9MB OurAirports CSV.

## Standard Stack

### Core (Zero External Dependencies -- Per Project Decision)

| Component | Source | Purpose | Why Standard |
|-----------|--------|---------|--------------|
| AWS Terrarium Tiles | `s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png` | Elevation data (PNG) | Free, no API key, same as v1.0 web app |
| CoreGraphics (CGImage) | Apple framework | Decode terrain PNG to raw pixels | Already used for label rasterization, no dependency |
| Metal API | Apple framework | Subdivided terrain mesh, wireframe mode | Project is Metal-only |
| CoreText | Apple framework | Airport label text rendering | Already used in LabelManager |

### Terrain Tile Sources Evaluated

| Provider | URL Pattern | Auth Required | Status |
|----------|-------------|---------------|--------|
| **AWS Terrarium** (chosen) | `s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png` | None | Free, reliable, used by v1.0 |
| Mapbox Terrain-RGB | `api.mapbox.com/v4/mapbox.terrain-rgb/{z}/{x}/{y}.pngraw` | API key required | Not zero-dependency friendly |
| MapTiler | `api.maptiler.com/tiles/terrain-rgb/{z}/{x}/{y}.png` | API key required | Same issue |

### Map Tile Sources Per Theme (from v1.0 web app)

| Theme | Tile Provider | URL Pattern |
|-------|--------------|-------------|
| Day | CartoDB Positron (light) | `{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png` |
| Night | CartoDB Dark Matter | `a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png` |
| Retro | Stadia Stamen Toner Lite | `tiles.stadiamaps.com/tiles/stamen_toner_lite/{z}/{x}/{y}.png` (inverted to green) |

**Note:** The current native app uses only OpenStreetMap tiles. Themes will require switching tile URL sources per theme, which means clearing the tile cache on theme change and reloading with the appropriate style URL.

### Airport Data Source

| Source | Size | Format | Content |
|--------|------|--------|---------|
| OurAirports CSV (v1.0 web approach) | ~9MB | CSV over HTTPS | 70,000+ airports worldwide |
| **Embedded JSON (recommended)** | ~50KB | Bundled JSON | ~500 large+medium airports, pre-filtered |

**Recommendation:** Embed a pre-filtered JSON of major airports (large_airport + medium_airport types from OurAirports) bundled with the app. The v1.0 web app fetches the full 9MB CSV, but a native app should not download 9MB of airport data on every launch. Pre-filter to ~500 entries with fields: icao, iata, name, lat, lon, type, municipality.

## Architecture Patterns

### Terrain System Architecture

The terrain system runs parallel to the existing map tile system. Each map tile gets a corresponding terrain tile with an elevation-displaced mesh.

```
Renderer
  |-- MapTileManager (existing: fetches OSM/CartoDB PNG textures)
  |-- TerrainTileManager (new: fetches Terrarium PNG, decodes elevation, builds mesh)
  |      |-- TerrainMesh (subdivided grid + elevation-displaced vertex buffer per tile)
  |      |-- LRU cache of decoded elevation arrays (Float32, 256x256 per tile)
  |      |-- LRU cache of terrain MTLBuffers (vertex + index per tile)
  |-- ThemeManager (new: current theme config, theme switching)
  |-- AirportLabelManager (new: ground-projected airport labels)
```

### Terrain Mesh Per Tile

Each terrain tile is a subdivided grid mesh (e.g., 32x32 segments = 33x33 vertices = 1089 vertices, 32x32x2 = 2048 triangles). The vertex shader samples the pre-decoded elevation to displace Y.

**CPU-side approach (recommended):** Build the displaced mesh on CPU after elevation data arrives, upload complete vertex buffer to GPU. This avoids needing a heightmap texture per tile on GPU.

```
struct TerrainVertex {
    position: SIMD3<Float>   // XYZ with Y = elevation
    texCoord: SIMD2<Float>   // UV for map texture
    normal:   SIMD3<Float>   // Computed after displacement
}
```

**Per-tile mesh generation:**
1. Create a 32x32 grid of quads spanning the tile's world-space bounds
2. For each vertex, sample the 256x256 elevation array (bilinear interpolate)
3. Set vertex Y = max(0, elevation) * TERRAIN_SCALE_FACTOR
4. Compute vertex normals from displaced positions (cross product of edges)
5. Upload vertex + index buffer to GPU

### Terrarium Tile Decoding Formula

The Terrarium format encodes elevation in meters using RGB channels:

```
elevation_meters = (R * 256 + G + B / 256) - 32768
```

This provides ~3mm precision. Values are always positive with a 32,768 offset. Ocean areas will decode to negative values (below sea level).

**Implementation in Swift:**
```swift
func decodeTerrarium(r: UInt8, g: UInt8, b: UInt8) -> Float {
    return Float(Int(r) * 256 + Int(g)) + Float(b) / 256.0 - 32768.0
}
```

### Terrain Scale Factor

The v1.0 web app uses `TERRAIN_SCALE_FACTOR = 0.008` to convert meters to scene units, with dynamic Z-scaling based on altitude ratio. The native app should use a similar constant.

Given `worldScale = 500` (world units per degree of longitude), one degree of latitude is ~111km = 111,000m. So 500 world units = 111,000m, meaning 1 world unit = 222m. With a terrain scale factor of 0.008, a mountain at 4000m would be 4000 * 0.008 = 32 world units high. This is deliberately exaggerated for visual effect (4000m real vs. 32 units where 1 unit = 222m means ~7100m equivalent display height, roughly 1.8x exaggeration).

**Recommended:** Start with `TERRAIN_SCALE_FACTOR = 0.008` to match the web app, adjustable later.

### Theme System Architecture

A theme is a data struct containing all colors and rendering modes used across every render pass. Rather than scattering `if currentTheme == .retro` checks throughout shaders, pass theme colors as uniforms.

```swift
enum Theme: String, CaseIterable {
    case day, night, retro
}

struct ThemeConfig {
    let clearColor: MTLClearColor
    let groundPlaceholderColor: SIMD4<Float>
    let aircraftLightDir: SIMD3<Float>
    let aircraftAmbient: Float
    let trailColorScale: SIMD4<Float>  // Multiplier for trail colors
    let labelTextColor: SIMD4<Float>
    let labelBgColor: SIMD4<Float>
    let altLineColor: SIMD4<Float>
    let airportLabelColor: SIMD4<Float>
    let isWireframe: Bool              // Retro mode
    let tileURLProvider: (TileCoordinate) -> URL
}
```

### Theme Color Palettes (from v1.0 web app)

**Day Theme:**
- Clear/sky color: `#87CEEB` (0.529, 0.808, 0.922)
- Ground placeholder: `#d4ddd4`
- Aircraft: Full color, Phong shading
- Trail colors: Rainbow altitude gradient (green -> yellow -> orange -> pink)
- Labels: White text on dark background
- Airport labels: `#0066cc` (blue)
- Map tiles: CartoDB Positron (light)

**Night Theme:**
- Clear/sky color: `#0a0a1a` (0.039, 0.039, 0.102)
- Ground placeholder: `#1a2a3a`
- Aircraft: Full color, Phong shading (same as day)
- Trail colors: Same rainbow altitude gradient
- Labels: Cyan text on dark background
- Airport labels: `#66bbff` (light blue)
- Map tiles: CartoDB Dark Matter

**Retro Theme:**
- Clear/sky color: `#000800` (0.0, 0.031, 0.0)
- Ground placeholder: `#001100`
- Aircraft: Wireframe mode, all green `#00ff00`
- Trail colors: Green gradient (bright green -> dark green by altitude)
- Labels: Green text `#00ff00` on dark green background
- Airport labels: `#00ff00` (green)
- Map tiles: Stamen Toner Lite, inverted to green
- Special: `setTriangleFillMode(.lines)` for wireframe rendering

### Wireframe Mode in Metal

Metal supports wireframe rendering natively via `MTLTriangleFillMode`:

```swift
// In the render loop, before draw calls:
if theme.isWireframe {
    encoder.setTriangleFillMode(.lines)
} else {
    encoder.setTriangleFillMode(.fill)
}
```

This affects ALL subsequent draw calls on the encoder. It can be set/changed per draw call, so different passes can use different fill modes.

**Key detail:** `setTriangleFillMode(.lines)` draws only the triangle edges. For the retro theme, this gives the classic vector/wireframe look to terrain meshes and aircraft meshes without needing separate wireframe geometry. Map tile textures would look wrong in wireframe mode (just triangle outlines with no texture), so the retro theme should either:
- Use a solid green color for terrain instead of textures (match the v1.0 approach where retro terrain without texture loads uses `color: 0x003300, wireframe: true`)
- Or use the map tile texture in fill mode but with a green tint overlay

The v1.0 web app uses `wireframe: isRetro` on terrain material when no texture is loaded, and green-tinted map tiles when texture loads. For the native Metal app, the simplest approach is: in retro mode, skip map textures on terrain, use a green-tinted wireframe.

### Airport Ground Labels Architecture

Airport labels in this phase are different from the existing aircraft billboard labels. They:
- Are positioned on the ground plane (Y = terrain elevation + small offset)
- Are oriented flat or standing upright (the v1.0 app uses standing upright 3D text)
- Show airport IATA/ICAO codes (e.g., "SEA", "LAX")
- Are distance-culled (large airports visible at greater distance than medium)
- Need to be readable as camera moves

**Two approaches:**

1. **Standing 3D text (v1.0 approach):** Extruded text meshes standing upright on the ground. Requires generating mesh geometry from text. Complex without external font libraries.

2. **Ground-projected billboard labels (recommended):** Reuse the LabelManager's CoreText-to-atlas pipeline. Render airport codes to atlas slots. Position quads flat on the ground (rotated -90 degrees on X axis) at airport coordinates. This leverages existing infrastructure.

**Recommended approach:** Use the existing atlas pipeline from `LabelManager` to render airport code text, but create a separate `AirportLabelManager` that positions labels on the ground plane. The labels can be either:
- Flat on the ground (like a painted runway marking) -- simple but harder to read at oblique angles
- Billboarded but anchored to ground Y -- readable from any angle, similar to aircraft labels

The v1.0 web app uses standing upright 3D text (`mesh.position.set(x, terrainY + 1.5, z)`) with no billboarding. This is the best visual match. For Metal, render text to a texture quad, orient the quad to stand vertically on the ground at the airport position. The quad should face the camera (billboard on Y axis only, so it always faces the viewer but stays upright).

### Recommended Project Structure

```
AirplaneTracker3D/
  Rendering/
    Renderer.swift              (modify: add terrain pass, theme support)
    Shaders.metal               (modify: add terrain vertex/fragment shaders)
    ShaderTypes.h               (modify: add TerrainVertex, ThemeUniforms)
    ThemeManager.swift           (new: theme configuration and switching)
    TerrainTileManager.swift     (new: fetch, decode, mesh generation)
    AirportLabelManager.swift    (new: airport ground labels)
    TerrainShaders.metal         (new: terrain-specific vertex/fragment)
  Map/
    MapTileManager.swift         (modify: theme-aware tile URLs)
    TileCoordinate.swift         (no changes)
    MapCoordinateSystem.swift    (no changes)
  Data/
    airports.json                (new: embedded major airport database)
```

### How Theme Affects Each Render Pass

| Pass | Day | Night | Retro |
|------|-----|-------|-------|
| Clear color | Sky blue #87CEEB | Dark blue #0a0a1a | Dark green #000800 |
| Map tiles | CartoDB light | CartoDB dark | Stamen Toner (inverted green) |
| Terrain mesh | Textured (satellite/map) | Textured (dark map) | Wireframe green, no texture |
| Aircraft | Solid, Phong lit, altitude colors | Same | Wireframe green `setTriangleFillMode(.lines)` |
| Trails | Rainbow altitude gradient | Same | Green gradient |
| Glow sprites | Altitude-colored | Same | Green |
| Labels | White on dark bg | Cyan on dark bg | Green on dark green bg |
| Altitude lines | Gray dashed | Same | Green dashed |
| Airport labels | Blue #0066cc | Light blue #66bbff | Green #00ff00 |

### Uniforms Extension for Themes

Add theme data to the existing Uniforms struct or create a separate theme buffer:

```c
// In ShaderTypes.h
typedef struct {
    simd_float4 clearColor;
    simd_float4 aircraftTint;      // Retro: green, Day/Night: white (pass-through)
    simd_float4 trailTint;         // Retro: green scale, Day/Night: white
    simd_float4 labelColor;
    simd_float4 altLineColor;
    float ambientLight;
    float isWireframe;             // 0.0 or 1.0
    float _pad0;
    float _pad1;
} ThemeUniforms;
```

**Alternative simpler approach:** Since the main difference between day/night is just colors (handled CPU-side) and retro additionally needs wireframe mode, the theme can be mostly CPU-side:
- CPU changes: clearColor, tile URL, label rasterization colors, trail colors
- GPU changes: Only `setTriangleFillMode` (wireframe vs fill), potentially aircraft fragment shader tint
- This minimizes shader changes -- most color decisions are already made CPU-side in the instance managers

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Elevation decoding | Custom tile format | AWS Terrarium formula `(R*256+G+B/256)-32768` | Standard format, battle-tested |
| Wireframe rendering | Edge geometry extraction | `encoder.setTriangleFillMode(.lines)` | Built into Metal, zero cost |
| Airport database | Web scraping or manual entry | OurAirports data (pre-filtered, embedded JSON) | Community-maintained, 70k+ airports |
| Text rendering to texture | Custom font rasterizer | CoreText (already used in LabelManager) | Apple framework, handles all typography |
| Normal computation | Manual cross-products per vertex | Standard grid normal algorithm | Well-established pattern for grid meshes |

**Key insight:** The terrain mesh is conceptually simple (displaced grid), but getting edge normals, LOD transitions, and tile seams right requires careful implementation. Start with a single mesh quality level and no LOD.

## Common Pitfalls

### Pitfall 1: Terrain Tile Seams
**What goes wrong:** Adjacent terrain tiles have visible seams where elevation values don't perfectly match at boundaries, or where mesh edges don't align.
**Why it happens:** Each tile's elevation is sampled independently. Edge vertices of adjacent tiles may use slightly different elevations due to rounding or different sample positions.
**How to avoid:** Sample elevation at the exact tile boundary pixels (column 0 and column 255 map to tile edges). Since Terrarium tiles are 256x256 and designed to be seamless, using the exact edge pixels should produce matching elevations. Also ensure mesh vertices at tile edges are at exactly the same world-space XZ position.
**Warning signs:** Visible thin lines/gaps between tiles, Z-fighting at boundaries.

### Pitfall 2: Terrain Scale Mismatch with Aircraft Altitude
**What goes wrong:** Mountains appear taller than aircraft flying at 30,000ft, or terrain is so flat it's invisible.
**Why it happens:** The altitude scale factor (0.001) and terrain scale factor (0.008) need to be coordinated. Aircraft at 30,000ft = 30,000 * 0.001 = 30 world units. Mt. Everest at 8849m = 8849 * 0.008 = 70.8 world units. So Everest would appear more than 2x higher than a cruising aircraft.
**How to avoid:** The v1.0 web app handles this with dynamic terrain Z-scaling tied to altitude ratio. The native app should use a terrain scale that makes terrain visible but clearly below cruising aircraft. Consider `TERRAIN_SCALE_FACTOR = 0.005` or make it dynamic.
**Warning signs:** Mountains poking through aircraft or terrain being invisible.

### Pitfall 3: Theme Switch Requires Full Cache Invalidation
**What goes wrong:** After switching themes, old-theme tiles are displayed, or mixed theme tiles appear.
**Why it happens:** The MapTileManager caches MTLTextures keyed by tile coordinate. Different themes use different tile servers with different visual styles. The cache doesn't know about themes.
**How to avoid:** Clear the entire tile cache on theme change and trigger a full reload. The v1.0 web app does exactly this: `tileCache.clear(); loadMapTiles();`. Key the cache by `(theme, zoom, x, y)` or simply clear on theme change.
**Warning signs:** Light-themed tiles appearing in night mode, visual style inconsistency.

### Pitfall 4: Retro Wireframe Affecting Non-Terrain Geometry
**What goes wrong:** Setting `setTriangleFillMode(.lines)` at the wrong point makes everything wireframe, including glow sprites and labels.
**Why it happens:** Fill mode is encoder-global state that persists until changed.
**How to avoid:** Set fill mode per render pass. For retro: set `.lines` before terrain and aircraft draws, restore to `.fill` before glow/label/trail draws (trails use triangle strip so wireframe looks wrong). OR: use `.lines` only for aircraft and terrain, keep everything else in `.fill`.
**Warning signs:** Glow sprites rendered as triangle outlines, labels showing as wireframe quads.

### Pitfall 5: Terrain Mesh Memory Explosion
**What goes wrong:** Each terrain tile at 32x32 segments has 1089 vertices * (3+2+3 floats) * 4 bytes = ~35KB vertex data + indices. With 121 tiles (11x11 grid at zoom 8), that's ~4.2MB of vertex data, plus elevation arrays (256*256*4 = 256KB each, 30MB total for 121 tiles).
**Why it happens:** Terrain requires significantly more geometry than flat textured quads.
**How to avoid:** Use 32x32 segments (not higher), cache aggressively, evict old tiles. Consider 16x16 segments for distant tiles. The v1.0 web app uses 32x32 and caps at 100 terrain tiles.
**Warning signs:** Memory usage climbing rapidly during panning, frame rate drops.

### Pitfall 6: Terrain PNG Decoding Performance
**What goes wrong:** Decoding 256x256 terrain PNGs on the main thread causes frame stutters.
**Why it happens:** Each PNG must be downloaded, decoded to RGBA pixels, then have the Terrarium formula applied to all 65,536 pixels, then a 1089-vertex mesh must be built.
**How to avoid:** Do ALL terrain processing (download, decode, mesh build) on a background queue. Only the final MTLBuffer upload needs to happen on the render thread (or use shared storage mode buffers written from any thread). Follow the same async pattern as `MapTileManager.fetchTile()`.
**Warning signs:** Frame drops when new terrain tiles load, UI freezing during pan.

### Pitfall 7: Airport Label Overdraw
**What goes wrong:** Too many airport labels rendered, causing visual clutter and performance issues.
**Why it happens:** There are hundreds of airports within view at low zoom levels.
**How to avoid:** Distance-based filtering with different thresholds per airport type (large: 500 units, medium: 250 units). Sort by type then distance, cap at 40 visible labels. The v1.0 web app uses exactly this approach.
**Warning signs:** Overlapping labels, FPS drop from too many text atlas updates.

## Code Examples

### Terrarium Elevation Decoding (from v1.0 web app, verified)

```javascript
// Source: airplane-tracker-3d-map.html lines 1749-1753
// Terrarium format: elevation = (R * 256 + G + B / 256) - 32768
for (let i = 0; i < imageData.data.length; i += 4) {
    const r = imageData.data[i];
    const g = imageData.data[i + 1];
    const b = imageData.data[i + 2];
    elevations[i / 4] = (r * 256 + g + b / 256) - 32768;
}
```

**Swift equivalent:**
```swift
func decodeTerrarium(pixels: UnsafePointer<UInt8>, count: Int) -> [Float] {
    var elevations = [Float](repeating: 0, count: count)
    for i in 0..<count {
        let r = Float(pixels[i * 4])
        let g = Float(pixels[i * 4 + 1])
        let b = Float(pixels[i * 4 + 2])
        elevations[i] = (r * 256.0 + g + b / 256.0) - 32768.0
    }
    return elevations
}
```

### Terrain Mesh Generation (adapted from v1.0 web app)

```swift
// Source: airplane-tracker-3d-map.html lines 1656-1670
// Build a subdivided grid and displace Y by elevation
let segments = 32
let verticesPerSide = segments + 1  // 33

for iy in 0...segments {
    for ix in 0...segments {
        let u = Float(ix) / Float(segments)
        let v = Float(iy) / Float(segments)

        // World position within tile bounds
        let worldX = tileBoundsMinX + u * (tileBoundsMaxX - tileBoundsMinX)
        let worldZ = tileBoundsMinZ + v * (tileBoundsMaxZ - tileBoundsMinZ)

        // Sample elevation (256x256 grid)
        let ex = min(Int(u * 255), 255)
        let ey = min(Int(v * 255), 255)
        let elevation = elevations[ey * 256 + ex]
        let worldY = max(0, elevation) * terrainScaleFactor

        // Write vertex
        let vertIdx = iy * verticesPerSide + ix
        vertices[vertIdx] = TerrainVertex(
            position: SIMD3<Float>(worldX, worldY, worldZ),
            texCoord: SIMD2<Float>(u, v),
            normal: SIMD3<Float>(0, 1, 0)  // Recomputed after
        )
    }
}

// Generate triangle indices
for iy in 0..<segments {
    for ix in 0..<segments {
        let topLeft = iy * verticesPerSide + ix
        let topRight = topLeft + 1
        let bottomLeft = (iy + 1) * verticesPerSide + ix
        let bottomRight = bottomLeft + 1

        // Two triangles per quad
        indices.append(contentsOf: [
            UInt16(topLeft), UInt16(bottomLeft), UInt16(topRight),
            UInt16(topRight), UInt16(bottomLeft), UInt16(bottomRight)
        ])
    }
}

// Recompute normals from cross products
computeGridNormals(vertices: &vertices, segments: segments)
```

### Normal Computation for Grid Mesh

```swift
func computeGridNormals(vertices: inout [TerrainVertex], segments: Int) {
    let w = segments + 1
    for iy in 0...segments {
        for ix in 0...segments {
            let idx = iy * w + ix
            let pos = vertices[idx].position

            // Sample neighbors (clamped at edges)
            let left  = vertices[iy * w + max(0, ix - 1)].position
            let right = vertices[iy * w + min(segments, ix + 1)].position
            let up    = vertices[max(0, iy - 1) * w + ix].position
            let down  = vertices[min(segments, iy + 1) * w + ix].position

            let dx = right - left
            let dz = down - up
            let normal = simd_normalize(simd_cross(dz, dx))

            vertices[idx].normal = normal
        }
    }
}
```

### Metal Wireframe Mode (verified from Apple docs)

```swift
// Source: Apple Developer Documentation - MTLTriangleFillMode
// https://developer.apple.com/documentation/metal/mtltrianglefillmode

// In render loop, per-pass:
if currentTheme == .retro {
    encoder.setTriangleFillMode(.lines)  // Wireframe
} else {
    encoder.setTriangleFillMode(.fill)   // Solid (default)
}
```

### Theme Color Data (from v1.0 web app, verified)

```swift
// Source: airplane-tracker-3d-map.html lines 2905-2914, 3012, 3644-3648, etc.
struct ThemeColors {
    static let day = ThemeColors(
        clearColor: MTLClearColor(red: 0.529, green: 0.808, blue: 0.922, alpha: 1.0),
        groundPlaceholder: SIMD4<Float>(0.831, 0.867, 0.831, 1.0),  // #d4ddd4
        airportLabel: SIMD4<Float>(0.0, 0.4, 0.8, 1.0),             // #0066cc
        altLine: SIMD4<Float>(0.5, 0.5, 0.5, 0.3),
        isWireframe: false
    )

    static let night = ThemeColors(
        clearColor: MTLClearColor(red: 0.039, green: 0.039, blue: 0.102, alpha: 1.0),
        groundPlaceholder: SIMD4<Float>(0.102, 0.165, 0.227, 1.0),  // #1a2a3a
        airportLabel: SIMD4<Float>(0.4, 0.733, 1.0, 1.0),           // #66bbff
        altLine: SIMD4<Float>(0.5, 0.5, 0.5, 0.3),
        isWireframe: false
    )

    static let retro = ThemeColors(
        clearColor: MTLClearColor(red: 0.0, green: 0.031, blue: 0.0, alpha: 1.0),
        groundPlaceholder: SIMD4<Float>(0.0, 0.067, 0.0, 1.0),     // #001100
        airportLabel: SIMD4<Float>(0.0, 1.0, 0.0, 1.0),             // #00ff00
        altLine: SIMD4<Float>(0.0, 1.0, 0.0, 0.3),
        isWireframe: true
    )
}
```

### Terrain Vertex Shader

```metal
// New shader for terrain tiles with vertex displacement
struct TerrainVertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float3 normal   [[attribute(2)]];
};

struct TerrainVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float3 worldNormal;
    float3 worldPosition;
};

vertex TerrainVertexOut terrain_vertex(
    TerrainVertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
    constant float4x4 &modelMatrix [[buffer(BufferIndexModelMatrix)]]
) {
    TerrainVertexOut out;
    // Position already includes elevation displacement (CPU-side)
    float4 worldPos = modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.texCoord = in.texCoord;
    out.worldNormal = normalize((modelMatrix * float4(in.normal, 0.0)).xyz);
    out.worldPosition = worldPos.xyz;
    return out;
}

fragment float4 terrain_fragment(
    TerrainVertexOut in [[stage_in]],
    texture2d<float> colorTexture [[texture(TextureIndexColor)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear);
    float4 texColor = colorTexture.sample(texSampler, in.texCoord);

    // Basic directional lighting
    float3 lightDir = normalize(float3(0.5, 1.0, 0.5));
    float diffuse = max(dot(normalize(in.worldNormal), lightDir), 0.0);
    float lighting = 0.4 + diffuse * 0.6;

    return float4(texColor.rgb * lighting, 1.0);
}
```

### Airport Data Embedding

```swift
// Embedded JSON format for major airports
struct AirportData: Codable {
    let icao: String
    let iata: String?
    let name: String
    let lat: Double
    let lon: Double
    let type: String         // "large_airport" or "medium_airport"
    let municipality: String?
}

// Load from bundled JSON
func loadAirports() -> [AirportData] {
    guard let url = Bundle.main.url(forResource: "airports", withExtension: "json"),
          let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([AirportData].self, from: data)) ?? []
}
```

### Retro Green Tint for Map Tiles

The v1.0 web app inverts and green-tints Stamen Toner tiles for retro mode. In Metal, this can be done in the fragment shader:

```metal
// Retro tile fragment shader -- invert and green-tint
fragment float4 fragment_retro_textured(
    TexturedVertexOut in [[stage_in]],
    texture2d<float> colorTexture [[texture(TextureIndexColor)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear);
    float4 texColor = colorTexture.sample(texSampler, in.texCoord);

    // Invert and shift to green channel
    float gray = 1.0 - (texColor.r * 0.3 + texColor.g * 0.59 + texColor.b * 0.11);
    return float4(0.0, gray, 0.0, 1.0);
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Flat tile quads (current app) | Displaced terrain mesh | This phase | Adds 3D terrain with real elevation |
| Single color scheme (sky blue) | Three switchable themes | This phase | Day/Night/Retro visual modes |
| No airport labels | Ground-projected airport labels | This phase | Geographic context and navigation |
| Fixed tile URL (OSM only) | Theme-specific tile providers | This phase | Visual style matches theme |

## Open Questions

1. **Terrain LOD**
   - What we know: 32x32 segments per tile works for v1.0 web app. Native Metal can handle more.
   - What's unclear: Whether distant tiles should use fewer segments (16x16) for performance.
   - Recommendation: Start with uniform 32x32 for all tiles. Profile before adding LOD.

2. **Terrain + Flat Tile Interaction**
   - What we know: The current app renders flat textured quads for map tiles. Terrain would add a SECOND mesh per tile on top.
   - What's unclear: Should terrain replace the flat tiles entirely, or should the terrain mesh get the map texture?
   - Recommendation: Terrain mesh replaces the flat tile -- the terrain mesh uses the same map tile texture but with elevation displacement. No need to render both. When terrain is off (or retro wireframe), fall back to flat tiles.

3. **Theme Persistence**
   - What we know: V1.0 web app saves theme to cookies.
   - What's unclear: Whether native app should persist theme selection.
   - Recommendation: Use UserDefaults to persist theme choice. Low effort, good UX.

4. **Airport Label Approach: Standing vs Flat vs Billboard**
   - What we know: V1.0 uses standing 3D extruded text. The native app has CoreText atlas for billboards.
   - What's unclear: Best visual approach for Metal without external font geometry libraries.
   - Recommendation: Use Y-axis-only billboarded quads (rotate to face camera around Y axis, but stay upright) positioned at ground level. This gives readability without needing 3D text mesh generation.

5. **Tile URL Provider Authentication**
   - What we know: CartoDB and Stadia tiles are free but may have rate limits or require attribution.
   - What's unclear: Whether these tile providers require API keys for native apps.
   - Recommendation: CartoDB (CARTO) basemaps are free for non-commercial/low-volume use. Stadia Maps requires an API key since Oct 2023 for Stamen tiles. Alternative for retro: could use OSM tiles and apply green tint shader, avoiding the need for Stadia. Research Stadia API key requirements before committing.

## Sources

### Primary (HIGH confidence)
- **v1.0 Web App** (`airplane-tracker-3d-map.html`) - Complete working reference for terrain decoding (lines 1613-1860), theme system (throughout), airport database (lines 1224-1580)
- **Existing Swift codebase** - All Metal pipeline setup, shader architecture, coordinate system, tile management patterns
- **[AWS Terrain Tiles Registry](https://registry.opendata.aws/terrain-tiles/)** - Terrarium format specification, S3 URL pattern
- **[Tilezen/Joerd docs](https://github.com/tilezen/joerd/blob/master/docs/use-service.md)** - Terrarium encoding formula, zoom level support (0-15)

### Secondary (MEDIUM confidence)
- **[Apple MTLTriangleFillMode](https://developer.apple.com/documentation/metal/mtltrianglefillmode)** - Wireframe rendering API (`.lines` value)
- **[Apple setTriangleFillMode](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/1516029-settrianglefillmode)** - Encoder method for fill mode
- **[OurAirports Data Dictionary](https://ourairports.com/help/data-dictionary.html)** - Airport CSV format, column definitions
- **[OurAirports GitHub](https://github.com/davidmegginson/ourairports-data)** - airports.csv download URL

### Tertiary (LOW confidence)
- **[Stadia Maps](https://stadiamaps.com/)** - May require API key for Stamen tiles since Oct 2023 -- needs validation before implementation

## Metadata

**Confidence breakdown:**
- Terrain system: HIGH - Exact Terrarium decoding formula verified in v1.0 web app, AWS S3 URL confirmed, mesh generation approach well-understood
- Theme system: HIGH - All three theme color palettes extracted from v1.0 web app, Metal wireframe API verified
- Airport labels: HIGH - OurAirports data source verified, v1.0 approach documented, CoreText atlas reuse straightforward
- Tile URL providers: MEDIUM - CartoDB likely free, Stadia may need API key, needs validation

**Research date:** 2026-02-09
**Valid until:** 2026-03-11 (stable domain, AWS Terrarium tiles unlikely to change)
