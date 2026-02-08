# Phase 7: Trails + Labels + Selection - Research

**Researched:** 2026-02-08
**Domain:** Metal GPU rendering (polylines, text, picking), SwiftUI overlay, REST enrichment APIs
**Confidence:** HIGH

## Summary

This phase adds flight trail rendering, billboard text labels, aircraft selection with detail panel + enrichment, altitude reference lines, and follow-camera to the existing Metal 3 renderer. The codebase already has triple-buffered instanced aircraft rendering, an orbit camera, Mercator projection, and a flight data pipeline producing `InterpolatedAircraftState` per frame. Phase 7 builds new rendering passes (trails, labels, altitude lines) and adds interaction (click-to-select, enrichment fetch, camera follow).

The hardest technical problem is GPU polyline rendering with configurable width -- Metal has no built-in thick line support (max line width is 1px). The standard solution is screen-space extrusion in the vertex shader: pass previous/current/next positions as vertex attributes, compute perpendicular normals in NDC, and offset vertices by half-width. This is a well-established technique ("Drawing Lines is Hard" by Matt DesLauriers). For text, the simplest zero-dependency approach is CoreText-to-CGContext-to-MTLTexture rasterization for billboard quads -- no SDF atlas needed given the small label count and fixed viewing distances.

**Primary recommendation:** Use screen-space polyline extrusion for trails, CoreText rasterization for label textures, ray-sphere intersection for picking, SwiftUI ZStack overlay for the detail panel, and smooth lerp of OrbitCamera.target for follow mode.

## Standard Stack

### Core (zero external dependencies -- project constraint)

| Component | Framework | Purpose | Why Standard |
|-----------|-----------|---------|--------------|
| Trail rendering | Metal vertex shader | Screen-space polyline extrusion | Only viable approach for thick lines in Metal |
| Trail buffer | CPU ring buffer + MTLBuffer | Per-aircraft trail point storage | Matches existing triple-buffer pattern |
| Label rendering | CoreText + CGContext | Render text to MTLTexture bitmaps | Native macOS, zero dependencies |
| Label display | Metal billboard shader | Camera-facing quads with text textures | Reuses existing glow billboard pattern |
| Selection picking | CPU ray-sphere test | Screen click to world ray intersection | Simple, sufficient for ~1000 aircraft |
| Detail panel | SwiftUI overlay | Aircraft info + enrichment data | Already using SwiftUI host (ContentView) |
| Enrichment | URLSession + Codable | hexdb.io and adsbdb.com REST APIs | Standard Swift networking |
| Follow camera | OrbitCamera target lerp | Smooth tracking of selected aircraft | Extends existing camera system |
| Altitude lines | Metal vertex shader | Dashed vertical lines to ground | Fragment shader discard pattern |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CoreText rasterization | SDF font atlas | SDF is better at scale but overkill for fixed-size labels; adds significant complexity |
| CPU ray-sphere | GPU color-ID picking | GPU picking needs extra render pass; ray-sphere is fast enough for ~1000 aircraft |
| SwiftUI overlay | AppKit NSPanel | SwiftUI overlay is simpler, matches existing architecture |
| Per-aircraft trail buffer | Single shared buffer | Shared buffer requires complex offset management; per-aircraft is clearer |

## Architecture Patterns

### Recommended Project Structure

```
AirplaneTracker3D/
├── Rendering/
│   ├── Renderer.swift              # (existing) Add trail/label/altLine encode methods
│   ├── TrailManager.swift          # NEW: Per-aircraft ring buffers, GPU buffer management
│   ├── TrailShaders.metal          # NEW: Polyline vertex shader + fragment shader
│   ├── LabelManager.swift          # NEW: CoreText rasterization, billboard instances
│   ├── LabelShaders.metal          # NEW: Billboard vertex/fragment (similar to glow)
│   ├── AltitudeLineShaders.metal   # NEW: Dashed line vertex/fragment
│   ├── SelectionManager.swift      # NEW: Ray-cast picking, selection state
│   ├── ShaderTypes.h               # (existing) Add TrailVertex, LabelInstanceData structs
│   └── ...existing files...
├── DataLayer/
│   ├── EnrichmentService.swift     # NEW: hexdb.io + adsbdb.com API calls
│   └── ...existing files...
├── Camera/
│   └── OrbitCamera.swift           # (existing) Add follow target + smooth tracking
├── Views/
│   ├── AircraftDetailPanel.swift   # NEW: SwiftUI detail panel view
│   └── ...
└── ContentView.swift               # (existing) Add ZStack overlay with detail panel
```

### Pattern 1: Screen-Space Polyline Extrusion (Trails)

**What:** Expand a polyline into a triangle strip in the vertex shader by offsetting vertices perpendicular to the line direction in screen space.

**When to use:** Whenever Metal needs lines thicker than 1px with configurable width.

**Algorithm:**
1. For each trail point, store: position (float3), color (float4), and the positions of previous/next points
2. In the vertex shader, project current, prev, and next positions to clip space
3. Compute the 2D direction in NDC between adjacent points
4. Rotate 90 degrees to get the perpendicular normal
5. Offset vertex position by +/- (thickness/2) along the normal in NDC
6. Correct for aspect ratio

**Key data structure -- TrailVertex:**
```c
// In ShaderTypes.h
typedef struct {
    simd_float3 position;       // World position
    simd_float4 color;          // Altitude-based color (per-vertex)
    simd_float3 prevPosition;   // Previous point (for direction calc)
    simd_float3 nextPosition;   // Next point (for direction calc)
    float direction;            // +1 or -1 (which side of the line)
} TrailVertex;
```

**Vertex shader approach:**
```metal
vertex TrailVertexOut trail_vertex(
    uint vertexID [[vertex_id]],
    constant TrailVertex *vertices [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant float &lineWidth [[buffer(2)]],
    constant float2 &resolution [[buffer(3)]]
) {
    TrailVertex v = vertices[vertexID];

    // Project current, prev, next to clip space
    float4 clipCurrent = uniforms.projectionMatrix * uniforms.viewMatrix * float4(v.position, 1.0);
    float4 clipPrev = uniforms.projectionMatrix * uniforms.viewMatrix * float4(v.prevPosition, 1.0);
    float4 clipNext = uniforms.projectionMatrix * uniforms.viewMatrix * float4(v.nextPosition, 1.0);

    // Convert to NDC
    float2 ndcCurrent = clipCurrent.xy / clipCurrent.w;
    float2 ndcPrev = clipPrev.xy / clipPrev.w;
    float2 ndcNext = clipNext.xy / clipNext.w;

    // Screen-space direction and normal
    float2 dir = normalize(ndcNext - ndcPrev);
    float2 normal = float2(-dir.y, dir.x);

    // Offset in pixels, converted to NDC
    float2 offset = normal * v.direction * lineWidth / resolution;

    TrailVertexOut out;
    out.position = clipCurrent;
    out.position.xy += offset * clipCurrent.w;
    out.color = v.color;
    return out;
}
```

### Pattern 2: Per-Aircraft Ring Buffer for Trail Points

**What:** Each aircraft maintains a fixed-capacity ring buffer of trail points on CPU, which gets flattened to a GPU vertex buffer each frame.

**Design:**
```swift
struct TrailRingBuffer {
    var points: [TrailPoint] = []  // Append-only, trimmed to maxLength
    let maxLength: Int             // Configurable 50-4000

    mutating func append(_ point: TrailPoint) {
        points.append(point)
        if points.count > maxLength {
            points.removeFirst(points.count - maxLength)
        }
    }
}

struct TrailPoint {
    var position: SIMD3<Float>     // World space XYZ
    var altitude: Float            // For color gradient
}
```

**GPU buffer strategy:**
- Pre-allocate a large MTLBuffer for all trail vertices (maxAircraft * maxTrailLength * 2 vertices per point * stride)
- Each frame, write only the trails that changed
- Use drawPrimitives with vertex offset and count per aircraft
- Triple-buffer the trail vertex buffer to match existing scheme

**Performance note:** With 500 aircraft * 500 trail points * 2 vertices * ~64 bytes = ~32MB per frame buffer. With 4000 points max, this grows to 256MB. For large trail counts, implement LOD: reduce rendered points for distant aircraft (as the web app does).

### Pattern 3: CoreText Label Rasterization

**What:** Render text labels to small MTLTextures using CoreText + CGContext, then display as billboard quads.

**Steps:**
1. Create a CGContext backed by a pixel buffer (e.g., 256x64 RGBA)
2. Use NSAttributedString / CTLine to draw text (callsign + altitude)
3. Upload pixels to MTLTexture via `texture.replace(region:...)`
4. Each aircraft gets one label texture (reused/updated when data changes)
5. Render as billboard quads using the same camera-facing technique as GlowShaders.metal

**Optimization:**
- Use a texture atlas (single large texture) rather than one texture per aircraft
- Only re-rasterize when callsign/altitude changes (throttle to ~1Hz)
- Pool and reuse CGContexts

### Pattern 4: Ray-Sphere Picking

**What:** Convert a mouse click to a 3D ray and test intersection with bounding spheres around each aircraft.

**Algorithm:**
```swift
func screenToRay(screenPoint: CGPoint, viewSize: CGSize,
                 viewMatrix: simd_float4x4, projMatrix: simd_float4x4) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
    // 1. Convert screen coords to NDC
    let ndcX = Float(screenPoint.x / viewSize.width) * 2.0 - 1.0
    let ndcY = 1.0 - Float(screenPoint.y / viewSize.height) * 2.0  // Flip Y

    // 2. Unproject near and far points
    let invVP = (projMatrix * viewMatrix).inverse
    let nearPoint = invVP * SIMD4<Float>(ndcX, ndcY, 0, 1)  // Metal NDC z=0 is near
    let farPoint = invVP * SIMD4<Float>(ndcX, ndcY, 1, 1)   // Metal NDC z=1 is far

    // 3. Perspective divide
    let near3 = SIMD3<Float>(nearPoint.x, nearPoint.y, nearPoint.z) / nearPoint.w
    let far3 = SIMD3<Float>(farPoint.x, farPoint.y, farPoint.z) / farPoint.w

    // 4. Ray direction
    let direction = normalize(far3 - near3)
    return (near3, direction)
}

func raySphereIntersect(rayOrigin: SIMD3<Float>, rayDir: SIMD3<Float>,
                         sphereCenter: SIMD3<Float>, sphereRadius: Float) -> Float? {
    let oc = rayOrigin - sphereCenter
    let b = dot(oc, rayDir)
    let c = dot(oc, oc) - sphereRadius * sphereRadius
    let discriminant = b * b - c
    guard discriminant >= 0 else { return nil }
    let t = -b - sqrt(discriminant)
    return t > 0 ? t : nil
}
```

**Bounding sphere radius:** Use ~3.0 world units (slightly larger than aircraft mesh bounds for easier clicking).

### Pattern 5: Follow Camera with Smooth Tracking

**What:** When following a selected aircraft, smoothly move OrbitCamera.target to the aircraft's position each frame.

**Implementation in OrbitCamera:**
```swift
var followTarget: SIMD3<Float>? = nil  // Set when following
let followSmoothness: Float = 0.05     // Lower = smoother (exponential decay)

func update(deltaTime: Float) {
    if let ft = followTarget {
        target = simd_mix(target, ft, SIMD3<Float>(repeating: followSmoothness))
    }
    if isAutoRotating {
        azimuth += autoRotateSpeed * deltaTime
    }
}
```

### Anti-Patterns to Avoid

- **Creating MTLTexture per label per frame:** Extremely expensive. Reuse textures, only update when label text changes.
- **Rebuilding trail geometry from scratch every frame:** For aircraft with 4000 trail points, this is wasteful. Use ring buffer append and only update the GPU buffer region that changed.
- **Using Metal's setLineWidth:** It only supports 1px lines. Do NOT rely on this API.
- **Doing enrichment API calls on every selection:** Cache results by hex. The web app caches with an in-memory Map and so should we.
- **Blocking the render loop with network calls:** Enrichment fetches must be async and update the UI via SwiftUI state.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Text rasterization | Custom glyph renderer | CoreText + CGContext | Handles kerning, Unicode, font metrics |
| HTTP requests | Custom networking | URLSession + async/await | Built-in, handles TLS, connection pooling |
| JSON parsing | Custom parser | Codable structs | Type-safe, compiler-checked |
| Matrix inverse | Manual 4x4 inversion | simd_float4x4.inverse | SIMD-optimized, correct |
| Text layout | Manual glyph positioning | NSAttributedString | Handles all font metrics automatically |

**Key insight:** The zero-dependency constraint means we rely on Apple frameworks (Metal, CoreText, CoreGraphics, URLSession) instead of external libraries. These frameworks are production-quality and well-suited for every need in this phase.

## Common Pitfalls

### Pitfall 1: Metal NDC Depth Range

**What goes wrong:** Using OpenGL NDC assumptions (z: -1 to 1) instead of Metal NDC (z: 0 to 1) when unprojecting screen coordinates for ray casting.
**Why it happens:** Most online ray-casting tutorials assume OpenGL conventions.
**How to avoid:** The existing codebase uses Metal NDC (see `perspectiveMetal` in OrbitCamera). When unprojecting, use z=0 for near plane and z=1 for far plane.
**Warning signs:** Clicks hitting wrong objects, or ray seeming to originate behind the camera.

### Pitfall 2: Trail Point Accumulation Memory Bloat

**What goes wrong:** Trail buffers grow unbounded, consuming hundreds of MB of GPU memory.
**Why it happens:** No cap on trail length, or no LOD for distant aircraft.
**How to avoid:** Hard cap at configurable maxLength (default 500). Implement distance-based LOD: render fewer points for distant aircraft. Pre-allocate fixed-size buffers.
**Warning signs:** Memory usage climbing steadily, frame rate degradation.

### Pitfall 3: Label Texture Thrashing

**What goes wrong:** Re-rasterizing all label textures every frame, causing massive CPU overhead.
**Why it happens:** Altitude changes continuously, triggering re-render.
**How to avoid:** Only re-rasterize when label text actually changes (round altitude to nearest 100ft for display). Throttle label updates to 2-4 Hz max. Pool CGContexts.
**Warning signs:** High CPU usage in CoreText/CoreGraphics functions.

### Pitfall 4: Polyline Direction Degeneracy

**What goes wrong:** Trail segments with zero length (duplicate positions) cause NaN in normal calculation.
**Why it happens:** Aircraft position updates can produce duplicate points when stationary.
**How to avoid:** Skip duplicate points when appending to ring buffer. In the vertex shader, add epsilon check before normalize.
**Warning signs:** Visual artifacts: spikes, flashing geometry, or invisible trails.

### Pitfall 5: Enrichment API Rate Limiting

**What goes wrong:** Rapid aircraft selection triggers many API calls, hitting rate limits.
**Why it happens:** hexdb.io and adsbdb.com are free APIs without auth, likely rate-limited.
**How to avoid:** Cache results in a dictionary keyed by hex (for hexdb.io) and callsign (for adsbdb.com). Set a 3-second timeout. Never refetch cached entries.
**Warning signs:** HTTP 429 responses, enrichment panel never loading.

### Pitfall 6: InterpolatedAircraftState Missing Fields

**What goes wrong:** Detail panel needs squawk, registration, lat, lon but InterpolatedAircraftState only has position, heading, speed, altitude, hex, callsign.
**Why it happens:** InterpolatedAircraftState was designed for rendering, not display.
**How to avoid:** Either extend InterpolatedAircraftState to carry additional fields (squawk, lat, lon, registration, typeCode), or look up the underlying AircraftModel from the buffer snapshot using the hex identifier.
**Warning signs:** Detail panel shows "--" for all fields except callsign and altitude.

### Pitfall 7: Billboard Quad Depth Fighting

**What goes wrong:** Labels z-fight with aircraft geometry or trails.
**Why it happens:** Labels rendered at same depth as aircraft mesh.
**How to avoid:** Position label billboard slightly above the aircraft (Y offset). Use depth-read/no-write depth stencil state for labels (same as glow sprites). Render labels after all opaque geometry.
**Warning signs:** Labels flickering or partially hidden behind aircraft.

## Code Examples

### Example 1: CoreText to MTLTexture Label Rasterization

```swift
// Source: Apple CoreText + CoreGraphics documentation
func renderLabel(text: String, device: MTLDevice) -> MTLTexture? {
    let width = 256
    let height = 64
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel

    // Create CGContext
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Clear to transparent
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))

    // Draw text
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .bold),
        .foregroundColor: NSColor.white
    ]
    let attrString = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attrString)

    context.textPosition = CGPoint(x: 4, y: height / 4)
    CTLineDraw(line, context)

    // Create MTLTexture
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: width, height: height,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead]
    guard let texture = device.makeTexture(descriptor: descriptor),
          let data = context.data else { return nil }

    texture.replace(
        region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                          size: MTLSize(width: width, height: height, depth: 1)),
        mipmapLevel: 0,
        withBytes: data,
        bytesPerRow: bytesPerRow
    )
    return texture
}
```

### Example 2: Dashed Altitude Line Fragment Shader

```metal
// Dashed vertical line from aircraft to ground
struct AltLineVertexOut {
    float4 position [[position]];
    float worldY;       // Y coordinate for dash pattern
};

vertex AltLineVertexOut altline_vertex(
    uint vertexID [[vertex_id]],
    constant float3 *positions [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    AltLineVertexOut out;
    float3 pos = positions[vertexID];
    float4 worldPos = float4(pos, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldY = pos.y;
    return out;
}

fragment float4 altline_fragment(AltLineVertexOut in [[stage_in]]) {
    // Dash pattern based on world Y position
    float dashScale = 2.0;  // World units per dash cycle
    float pattern = fmod(in.worldY, dashScale) / dashScale;
    if (pattern > 0.5) discard_fragment();  // Gap

    float4 color = float4(0.5, 0.5, 0.5, 0.4);  // Semi-transparent gray
    return color;
}
```

### Example 3: SwiftUI Detail Panel Overlay

```swift
// ContentView.swift pattern
struct ContentView: View {
    @State private var flightDataManager = FlightDataManager()
    @State private var selectedAircraft: SelectedAircraftInfo? = nil

    var body: some View {
        ZStack(alignment: .trailing) {
            MetalView(flightDataManager: flightDataManager,
                      onAircraftSelected: { info in selectedAircraft = info })
                .ignoresSafeArea()

            if let aircraft = selectedAircraft {
                AircraftDetailPanel(aircraft: aircraft)
                    .frame(width: 280)
                    .padding()
                    .transition(.move(edge: .trailing))
            }
        }
    }
}
```

### Example 4: hexdb.io Enrichment Service

```swift
actor EnrichmentService {
    private var aircraftCache: [String: AircraftEnrichment?] = [:]
    private var routeCache: [String: RouteEnrichment?] = [:]

    func fetchAircraftInfo(hex: String) async -> AircraftEnrichment? {
        if let cached = aircraftCache[hex] { return cached }

        let url = URL(string: "https://hexdb.io/api/v1/aircraft/\(hex)")!
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                aircraftCache[hex] = nil
                return nil
            }
            let info = try JSONDecoder().decode(HexDBResponse.self, from: data)
            let enrichment = AircraftEnrichment(
                registration: info.Registration,
                manufacturer: info.Manufacturer,
                type: info.Type,
                icaoTypeCode: info.ICAOTypeCode,
                owner: info.RegisteredOwners
            )
            aircraftCache[hex] = enrichment
            return enrichment
        } catch {
            aircraftCache[hex] = nil
            return nil
        }
    }

    func fetchRouteInfo(callsign: String) async -> RouteEnrichment? {
        let clean = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !clean.isEmpty else { return nil }
        if let cached = routeCache[clean] { return cached }

        let url = URL(string: "https://api.adsbdb.com/v0/callsign/\(clean)")!
        // ... similar pattern with caching ...
    }
}
```

## Enrichment API Reference

### hexdb.io - Aircraft Lookup

**Endpoint:** `GET https://hexdb.io/api/v1/aircraft/{hex}`
**No authentication required.**

**Response (200 OK):**
```json
{
    "ModeS": "A00001",
    "Registration": "N1",
    "Manufacturer": "Cessna",
    "ICAOTypeCode": "C680",
    "Type": "Citation Sovereign+",
    "RegisteredOwners": "Federal Aviation Administration",
    "OperatorFlagCode": "C680"
}
```

**Response (404):**
```json
{"status": "404", "error": "Aircraft not found."}
```

**Confidence:** HIGH -- verified by direct API call during research.

### adsbdb.com - Route Lookup

**Endpoint:** `GET https://api.adsbdb.com/v0/callsign/{CALLSIGN}`

**Response (200 OK):**
```json
{
    "response": {
        "flightroute": {
            "callsign": "BAW123",
            "callsign_icao": "BAW123",
            "callsign_iata": "BA123",
            "airline": {
                "name": "British Airways",
                "icao": "BAW",
                "iata": "BA",
                "country": "United Kingdom",
                "callsign": "SPEEDBIRD"
            },
            "origin": {
                "country_iso_name": "GB",
                "country_name": "United Kingdom",
                "elevation": 83,
                "iata_code": "LHR",
                "icao_code": "EGLL",
                "latitude": 51.4706,
                "longitude": -0.461941,
                "municipality": "London",
                "name": "London Heathrow Airport"
            },
            "destination": {
                "country_iso_name": "QA",
                "country_name": "Qatar",
                "elevation": 13,
                "iata_code": "DOH",
                "icao_code": "OTHH",
                "latitude": 25.273056,
                "longitude": 51.608056,
                "municipality": "Doha",
                "name": "Hamad International Airport"
            }
        }
    }
}
```

**Confidence:** HIGH -- verified by direct API call during research.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| GL_LINE_WIDTH for thick lines | Screen-space extrusion in vertex shader | ~2015 (deprecated in GL, never in Metal) | Must use triangle strips for visible-width lines |
| Per-glyph texture | Font atlas (single texture, many glyphs) | ~2010+ | Reduces draw calls, texture binds |
| SDF font atlas | MSDF font atlas | 2020+ | Better quality at extreme zoom, but overkill for our fixed-scale labels |
| GPU color-ID picking | CPU ray-sphere (for low object counts) | Always valid | Simpler, no extra render pass needed for ~1000 objects |

**Relevant to our project:**
- CoreText rasterization to bitmap is the simplest approach for our use case (fixed label sizes, ~1000 labels max, no extreme zoom)
- SDF/MSDF would be worth it only if labels needed to render at many different zoom levels with sharp edges -- not our case

## Codebase Integration Notes

### Fields Available vs. Needed

**InterpolatedAircraftState currently has:**
- position (SIMD3<Float>), heading, groundSpeed, verticalRate, altitude, category, hex, callsign

**Detail panel needs (not currently in InterpolatedAircraftState):**
- squawk, lat/lon (geographic), registration, typeCode, dbFlags

**Solution:** Either extend InterpolatedAircraftState with these fields (preferred -- data is available in AircraftModel) or have FlightDataManager expose a method to look up the latest AircraftModel by hex. The extension approach is cleaner since all fields are available in the buffer snapshot already.

### Existing Shader Infrastructure

The existing glow billboard shader (GlowShaders.metal) provides a perfect template for the label billboard shader. It already:
- Generates 6 vertices per billboard from vertexID
- Extracts camera right/up from view matrix for camera-facing orientation
- Supports per-instance position, size, and opacity

The label shader will be nearly identical but sample a text texture instead of the glow texture.

### Existing Selection Support

AircraftInstanceData already has a `flags` field (bit 0 = selected), and AircraftShaders.metal already applies a gold highlight when `flags & 1`. This means the selection highlight rendering is already implemented -- we just need to set the flag.

### Click Handling Infrastructure

MetalMTKView subclass already handles scrollWheel and keyDown. Adding mouseDown for click detection is straightforward (override `mouseDown(with:)` or add a click gesture recognizer).

### Render Pass Ordering

Current order: tiles -> aircraft bodies -> spinning parts -> glow sprites.

New order should be: tiles -> altitude lines -> aircraft bodies -> spinning parts -> trails -> labels -> glow sprites.

Rationale:
- Altitude lines: opaque-ish, render before aircraft
- Trails: render after aircraft (semi-transparent, depth-read/no-write)
- Labels: render last before glow (billboard, depth-read/no-write)
- Glow: stays last (additive blending)

## Open Questions

1. **Trail buffer memory budget**
   - What we know: 500 aircraft * 500 points * 2 vertices * 64 bytes = 32MB per frame buffer (x3 for triple buffering = 96MB)
   - What's unclear: Is this acceptable on target hardware? May need LOD or lower default
   - Recommendation: Default trail length 500, implement distance-based LOD, monitor memory usage

2. **Label texture atlas vs. individual textures**
   - What we know: Individual textures are simpler to implement but may cause more draw calls
   - What's unclear: Performance impact of ~500 individual texture binds per frame
   - Recommendation: Start with a texture atlas (one large texture, subdivided into slots). This is a modest implementation effort and avoids per-aircraft texture switching.

3. **Enrichment API availability detection**
   - What we know: The web app does a HEAD request to hexdb.io on startup to check availability
   - What's unclear: Whether the API has formal rate limits or SLA
   - Recommendation: Follow web app pattern -- probe on startup, cache all results, set 3s timeout, fail silently

## Sources

### Primary (HIGH confidence)
- Existing codebase: ShaderTypes.h, Renderer.swift, AircraftShaders.metal, GlowShaders.metal, OrbitCamera.swift, FlightDataActor.swift, AircraftInstanceManager.swift, MetalView.swift, ContentView.swift, AircraftModel.swift
- hexdb.io API direct verification: `https://hexdb.io/api/v1/aircraft/a00001` -- confirmed response format
- adsbdb.com API direct verification: `https://api.adsbdb.com/v0/callsign/BAW123` -- confirmed response format
- Web app reference (airplane-tracker-3d-map.html): trail rendering, selection, enrichment, follow patterns

### Secondary (MEDIUM confidence)
- [Drawing Lines is Hard - Matt DesLauriers](https://mattdesl.svbtle.com/drawing-lines-is-hard) -- screen-space polyline extrusion technique
- [Rendering Text in Metal with Signed-Distance Fields - Metal by Example](https://metalbyexample.com/rendering-text-in-metal-with-signed-distance-fields/) -- font atlas and SDF technique reference
- [adsbdb GitHub](https://github.com/mrjackwills/adsbdb) -- full API endpoint documentation
- [hexdb.io](https://hexdb.io/) -- API homepage
- [Mouse Picking with Ray Casting - Anton Gerdelan](https://antongerdelan.net/opengl/raycasting.html) -- ray unprojection algorithm
- [Shader-Based Antialiased Dashed Stroked Polylines - JCGT](https://jcgt.org/published/0002/02/08/paper.pdf) -- dashed line shader techniques

### Tertiary (LOW confidence)
- None -- all findings verified through primary or secondary sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- uses only Apple frameworks (Metal, CoreText, URLSession), all well-documented
- Architecture: HIGH -- patterns directly extend existing codebase architecture
- Enrichment APIs: HIGH -- both APIs verified by direct HTTP call
- Polyline rendering: HIGH -- well-established technique with extensive literature
- Pitfalls: HIGH -- based on analysis of existing codebase plus known Metal rendering issues

**Research date:** 2026-02-08
**Valid until:** 2026-03-08 (stable -- Metal APIs, enrichment APIs unlikely to change)
