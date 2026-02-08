# Phase 6: Data Pipeline + Aircraft Rendering - Research

**Researched:** 2026-02-08
**Domain:** ADS-B data ingestion, Metal instanced rendering, procedural geometry, frame interpolation
**Confidence:** HIGH

## Summary

Phase 6 bridges two distinct domains: a network data pipeline that polls ADS-B APIs and normalizes flight data, and a Metal rendering pipeline that displays aircraft as instanced 3D geometry with visual effects. The data pipeline uses a Swift actor with async/await polling, a provider fallback chain (airplanes.live -> adsb.lol for global, dump1090 for local), and a time-windowed data buffer that enables frame interpolation. The rendering pipeline uses Metal instanced drawing with 6 mesh categories, where each category is a single `drawIndexedPrimitives(instanceCount:)` call -- 6 draw calls total regardless of aircraft count.

The critical architectural insight is the interpolation buffer pattern from the existing web app: raw API data arrives at 1-5 second intervals, gets timestamped and stored in a per-aircraft ring buffer, and a separate interpolation pass (running at render frequency) computes smooth positions between data points with a 2-second delay. This pattern translates directly to Swift: the `FlightDataActor` populates the buffer, and the renderer's `draw(in:)` reads interpolated values each frame.

**Primary recommendation:** Build the data pipeline (actor + polling + normalization) and the rendering pipeline (instanced meshes + per-instance buffer) as two independent subsystems connected through a shared `[String: AircraftState]` dictionary on `@MainActor`. Test each subsystem independently before integrating.

## Standard Stack

### Core (Zero External Dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| URLSession | Foundation (macOS 14+) | HTTP polling for ADS-B APIs | Built-in async/await support, connection pooling, HTTP/2 |
| JSONDecoder / Codable | Foundation | Parse aircraft.json responses | Type-safe, zero dependency, compile-time field validation |
| Metal / MetalKit | Metal 3 (macOS 14+) | Instanced aircraft rendering | Direct GPU control, instanced draw calls, per-instance buffers |
| simd | Swift stdlib | Model matrices, position interpolation | Matches Metal shader types exactly, hardware-accelerated on Apple Silicon |
| Swift Concurrency | Swift 6.2 | Actor isolation, async polling loop | Compile-time data race safety, structured cancellation |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| CACurrentMediaTime() | QuartzCore | High-precision frame timing | Already used by Renderer for deltaTime |
| DispatchSemaphore | Dispatch | Triple buffering synchronization | Already used by Renderer |

## Architecture Patterns

### Recommended Project Structure (New Files for Phase 6)

```
AirplaneTracker3D/
  Models/
    AircraftModel.swift            # Codable struct: normalized aircraft data
    AircraftCategory.swift         # Enum: jet, widebody, helicopter, small, military, regional
  DataLayer/
    FlightDataActor.swift          # Actor: polling loop, provider fallback, data buffer
    DataNormalizer.swift           # Static methods: normalize dump1090/v2 API -> AircraftModel
  Rendering/
    AircraftMeshLibrary.swift      # Procedural geometry for 6 categories
    AircraftInstanceManager.swift  # Per-instance buffer management, interpolation
    AircraftShaders.metal          # aircraft_vertex + aircraft_fragment (instanced)
    GlowShaders.metal              # glow_vertex + glow_fragment (billboard additive blend)
    ShaderTypes.h                  # Extended with AircraftInstanceData, GlowInstanceData
```

### Pattern 1: Actor-Based Data Polling with Provider Fallback

**What:** A Swift actor manages the async polling loop. It cycles through API providers on failure and normalizes all responses to a common `AircraftModel` format. The actor maintains a per-aircraft time-windowed data buffer for interpolation.

**When to use:** Always. This replaces the web app's `setInterval(fetchData, ...)` pattern.

**Key design:**
```swift
// FlightDataActor.swift
actor FlightDataActor {
    enum DataMode { case local, global }

    struct Provider {
        let name: String
        let buildURL: (Double, Double, Int) -> URL
        var failCount: Int = 0
    }

    private var providers: [Provider] = [
        Provider(name: "airplanes.live",
                 buildURL: { lat, lon, radius in
            URL(string: "https://api.airplanes.live/v2/point/\(lat)/\(lon)/\(radius)")!
        }),
        Provider(name: "adsb.lol",
                 buildURL: { lat, lon, radius in
            URL(string: "https://api.adsb.lol/v2/point/\(lat)/\(lon)/\(radius)")!
        })
    ]

    // Time-windowed buffer: hex -> [(timestamp, AircraftModel)]
    private var dataBuffer: [String: [(timestamp: CFTimeInterval, data: AircraftModel)]] = [:]

    func startPolling(mode: DataMode, center: (lat: Double, lon: Double)) -> AsyncStream<[String: AircraftModel]> {
        AsyncStream { continuation in
            let task = Task {
                let interval: Duration = mode == .local ? .seconds(1) : .seconds(5)
                while !Task.isCancelled {
                    let aircraft = await fetchWithFallback(mode: mode, center: center)
                    updateBuffer(aircraft)
                    continuation.yield(latestAircraft())
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func fetchWithFallback(mode: DataMode, center: (lat: Double, lon: Double)) async -> [AircraftModel] {
        if mode == .local {
            // dump1090 local: http://localhost:8080/data/aircraft.json
            // (or user-configured URL)
            return await fetchLocal()
        }
        // Global: try each provider in sequence
        for i in providers.indices {
            do {
                let url = providers[i].buildURL(center.lat, center.lon, 250)
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(ADSBV2Response.self, from: data)
                providers[i].failCount = 0
                return DataNormalizer.normalizeV2(response)
            } catch {
                providers[i].failCount += 1
                continue
            }
        }
        return [] // All providers failed
    }
}
```

**Confidence:** HIGH -- Actor + AsyncStream polling is standard Swift concurrency pattern. URLSession async/await is documented in WWDC21 "Use async/await with URLSession". Provider fallback mirrors the working web app pattern.

### Pattern 2: Time-Windowed Interpolation Buffer

**What:** Raw API data is timestamped and stored in a per-aircraft ring buffer (last 5-15 seconds). Each render frame, the interpolator finds two surrounding data points and lerps between them, using a 2-second delay to ensure smooth playback even with jittery API responses.

**When to use:** Always. This is how the web app achieves smooth movement and it works well.

**Key design (from web app, translated to Swift):**
```swift
// AircraftInterpolator (called each frame in draw(in:))
struct InterpolatedState {
    var position: SIMD3<Float>  // world XZ + altitude Y
    var heading: Float          // radians
    var groundSpeed: Float      // knots
    var verticalRate: Float     // ft/min
    var altitude: Float         // feet (for color mapping)
}

func interpolate(buffer: [(timestamp: CFTimeInterval, data: AircraftModel)],
                 at targetTime: CFTimeInterval) -> InterpolatedState? {
    guard !buffer.isEmpty else { return nil }

    // Find surrounding data points
    var before: (timestamp: CFTimeInterval, data: AircraftModel)?
    var after: (timestamp: CFTimeInterval, data: AircraftModel)?

    for entry in buffer {
        if entry.timestamp <= targetTime {
            before = entry
        } else {
            after = entry
            break
        }
    }

    guard let b = before ?? after, let a = after ?? before else { return nil }

    // Calculate interpolation factor
    var t: Float = 0
    if b.timestamp != a.timestamp {
        t = Float((targetTime - b.timestamp) / (a.timestamp - b.timestamp))
        t = max(0, min(1, t))
    }

    // Lerp position, lerpAngle for heading
    let lat = lerp(Float(b.data.lat), Float(a.data.lat), t)
    let lon = lerp(Float(b.data.lon), Float(a.data.lon), t)
    let alt = lerp(b.data.altitude, a.data.altitude, t)
    let heading = lerpAngle(b.data.track, a.data.track, t)

    let worldPos = MapCoordinateSystem.shared.worldPosition(lat: Double(lat), lon: Double(lon))
    let altWorld = alt * altitudeScale // configurable scale factor

    return InterpolatedState(
        position: SIMD3<Float>(worldPos.x, altWorld, worldPos.z),
        heading: heading * .pi / 180.0,
        groundSpeed: lerp(b.data.groundSpeed, a.data.groundSpeed, t),
        verticalRate: lerp(b.data.verticalRate, a.data.verticalRate, t),
        altitude: alt
    )
}

// Angle interpolation handling 360-degree wraparound
func lerpAngle(_ a: Float, _ b: Float, _ t: Float) -> Float {
    var a = a.truncatingRemainder(dividingBy: 360)
    var b = b.truncatingRemainder(dividingBy: 360)
    if a < 0 { a += 360 }
    if b < 0 { b += 360 }
    var diff = b - a
    if diff > 180 { diff -= 360 }
    if diff < -180 { diff += 360 }
    return a + diff * t
}
```

**Confidence:** HIGH -- Direct translation of the working web app interpolation (lines 4137-4215 of airplane-tracker-3d-map.html). The 2-second `INTERPOLATION_DELAY` is proven effective.

### Pattern 3: Metal Instanced Rendering with Per-Instance Data

**What:** All aircraft of the same category share one vertex/index buffer. Per-aircraft data (model matrix, color, animation phase) goes into a per-instance buffer. One `drawIndexedPrimitives(instanceCount:)` call per category. The vertex shader uses `[[instance_id]]` to index into the instance buffer.

**When to use:** Always for aircraft rendering. This is the core performance technique.

**Key design:**

ShaderTypes.h additions:
```c
// Per-instance aircraft data (packed for GPU alignment)
typedef struct {
    simd_float4x4 modelMatrix;      // 64 bytes: position + rotation + scale
    simd_float4   color;            // 16 bytes: altitude-based RGBA
    float         lightPhase;       // 4 bytes: position light animation phase
    float         glowIntensity;    // 4 bytes: glow sprite pulse value
    float         rotorAngle;       // 4 bytes: rotor/propeller rotation angle
    uint32_t      flags;            // 4 bytes: bitfield (selected, highlighted)
    // Total: 96 bytes per instance (well-aligned)
} AircraftInstanceData;

// Buffer indices (extend existing)
typedef enum {
    BufferIndexUniforms      = 0,
    BufferIndexVertices      = 1,
    BufferIndexModelMatrix   = 2,
    BufferIndexInstances     = 3,   // NEW: per-instance aircraft data
    BufferIndexGlowInstances = 4,   // NEW: per-instance glow data
} BufferIndex;
```

Swift-side instance buffer population:
```swift
// Called each frame before encoding
func updateInstanceBuffer(aircraft: [InterpolatedState], time: Float) {
    let count = aircraft.count
    ensureInstanceBufferCapacity(count)

    let ptr = instanceBuffer.contents()
        .bindMemory(to: AircraftInstanceData.self, capacity: count)

    for i in 0..<count {
        let ac = aircraft[i]

        // Model matrix: translate to world position, rotate to heading
        var model = matrix_identity_float4x4
        // Translation
        model.columns.3 = SIMD4<Float>(ac.position.x, ac.position.y, ac.position.z, 1)
        // Rotation around Y axis (heading)
        let cosH = cos(ac.heading)
        let sinH = sin(ac.heading)
        model.columns.0.x = cosH
        model.columns.0.z = -sinH
        model.columns.2.x = sinH
        model.columns.2.z = cosH

        ptr[i].modelMatrix = model
        ptr[i].color = altitudeColor(ac.altitude)
        ptr[i].lightPhase = ac.lightPhase + time * 0.08
        ptr[i].glowIntensity = 0.3 + 0.15 * sin(ac.lightPhase * 0.5)
        ptr[i].rotorAngle = ac.rotorAngle
        ptr[i].flags = ac.isSelected ? 1 : 0
    }
}
```

Draw call encoding:
```swift
func encodeAircraft(encoder: MTLRenderCommandEncoder) {
    encoder.setRenderPipelineState(aircraftPipeline)
    encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(BufferIndexUniforms.rawValue))

    for category in AircraftCategory.allCases {
        let mesh = meshLibrary.mesh(for: category)
        let range = instanceRanges[category]! // (offset, count)

        guard range.count > 0 else { continue }

        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0,
                                index: Int(BufferIndexVertices.rawValue))
        encoder.setVertexBuffer(instanceBuffer,
                                offset: range.offset * MemoryLayout<AircraftInstanceData>.stride,
                                index: Int(BufferIndexInstances.rawValue))

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: mesh.indexCount,
            indexType: .uint16,
            indexBuffer: mesh.indexBuffer,
            indexBufferOffset: 0,
            instanceCount: range.count
        )
    }
}
```

**Confidence:** HIGH -- Metal instanced rendering with `instance_id` is documented by Apple and verified in Metal by Example's "Instanced Rendering" article. The per-instance buffer with `drawIndexedPrimitives(instanceCount:)` is the standard approach. Verified with actual code examples.

### Pattern 4: Procedural Aircraft Geometry

**What:** Generate vertex/index buffers for 6 aircraft categories using basic geometry primitives (cylinders, cones, boxes, triangles) -- matching the web app's THREE.js geometry approach but as raw vertex data.

**When to use:** Always. No external 3D model files needed.

**Category mesh specifications (from web app analysis, lines 3063-3132):**

| Category | Primitives | Approximate Dimensions | Key Visual Feature |
|----------|-----------|----------------------|-------------------|
| **Jet** (narrowbody) | Cylinder fuselage (r=0.4, h=4), Cone nose (r=0.4, h=1.2), Box wings (5x0.15x1.5), Box tail (0.15x1.2x1), Box h-stab (2x0.1x0.6), 2x Cylinder engines (r=0.25, h=0.8) | ~5 wide, ~5 long | Engines under wings |
| **Widebody** | Cylinder fuselage (r=0.7, h=5.5), Cone nose (r=0.7, h=1.5), Box wings (8x0.2x2.2), Box tail, 4x Cylinder engines | ~8 wide, ~7 long | Larger, 4 engines |
| **Helicopter** | Sphere cabin (r=0.6), Cylinder tail (r=0.15, h=2.5), 2x Box rotors (6x0.05x0.2), Box tail rotor (0.05x1.2x0.15) | ~6 rotor span | Spinning rotors |
| **Small** (prop) | Cylinder fuselage (r=0.25, h=2.5), Cone nose (r=0.3, h=0.6), Box wings (4x0.08x0.8), Box propeller (0.08x1.2x0.08), Box tail | ~4 wide, ~3 long | Front propeller |
| **Military** | Box fuselage (0.6x0.4x4.5), Cone nose (r=0.35, h=1.2), Triangle delta wing (6x0.1x3), 2x angled Box tails | ~6 wide, ~5.7 long | Delta wing, twin tails |
| **Regional** | Same as Jet but smaller scale (~0.8x) | ~4 wide, ~4 long | Smaller jet |

**Vertex generation approach:**
```swift
struct AircraftMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let vertexCount: Int
    let indexCount: Int
}

struct AircraftVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

class AircraftMeshLibrary {
    private var meshes: [AircraftCategory: AircraftMesh] = [:]

    init(device: MTLDevice) {
        for category in AircraftCategory.allCases {
            meshes[category] = generateMesh(for: category, device: device)
        }
    }

    private func generateMesh(for category: AircraftCategory, device: MTLDevice) -> AircraftMesh {
        var vertices: [AircraftVertex] = []
        var indices: [UInt16] = []

        switch category {
        case .jet, .regional:
            let scale: Float = category == .regional ? 0.8 : 1.0
            appendCylinder(&vertices, &indices, radius: 0.4 * scale, height: 4 * scale, segments: 8) // fuselage
            appendCone(&vertices, &indices, radius: 0.4 * scale, height: 1.2 * scale, segments: 8,
                       offset: SIMD3(0, 0, 2.6 * scale)) // nose
            appendBox(&vertices, &indices, size: SIMD3(5, 0.15, 1.5) * scale) // wings
            // ... etc
        case .helicopter:
            appendSphere(&vertices, &indices, radius: 0.6, segments: 8) // cabin
            // Rotors generated separately (animated per-frame via rotorAngle in instance data)
            // ... etc
        // ... other categories
        }

        let vb = device.makeBuffer(bytes: vertices, length: MemoryLayout<AircraftVertex>.stride * vertices.count)!
        let ib = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.stride * indices.count)!

        return AircraftMesh(vertexBuffer: vb, indexBuffer: ib,
                           vertexCount: vertices.count, indexCount: indices.count)
    }
}
```

**Confidence:** HIGH -- The web app's geometry specifications (from `initSharedGeometries()` at line 3063) provide exact dimensions. Generating vertex data for cylinders, cones, boxes, and spheres is straightforward math.

### Pattern 5: Glow Sprite Billboard Rendering

**What:** Each aircraft has a glow sprite -- a camera-facing quad with a radial gradient texture, rendered with additive blending. The sprite pulses subtly, synced with the position light animation.

**When to use:** Always for aircraft visual effects.

**Metal implementation:**

Pipeline setup for additive blending:
```swift
let glowPipelineDesc = MTLRenderPipelineDescriptor()
glowPipelineDesc.vertexFunction = library.makeFunction(name: "glow_vertex")
glowPipelineDesc.fragmentFunction = library.makeFunction(name: "glow_fragment")
// ... vertex descriptor setup ...
glowPipelineDesc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
glowPipelineDesc.colorAttachments[0].isBlendingEnabled = true
glowPipelineDesc.colorAttachments[0].rgbBlendOperation = .add
glowPipelineDesc.colorAttachments[0].alphaBlendOperation = .add
glowPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
glowPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .one  // Additive
glowPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
glowPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
glowPipelineDesc.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
glowPipelineDesc.rasterSampleCount = metalView.sampleCount
```

Billboard vertex shader (quad always faces camera):
```metal
vertex GlowVertexOut glow_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
    constant GlowInstanceData *instances [[buffer(BufferIndexGlowInstances)]])
{
    GlowInstanceData inst = instances[instanceID];

    // Billboard quad corners (-1,-1), (1,-1), (1,1), (-1,1) as two triangles
    float2 corners[6] = {
        float2(-1, -1), float2(1, -1), float2(1, 1),
        float2(-1, -1), float2(1, 1),  float2(-1, 1)
    };
    float2 uvs[6] = {
        float2(0, 1), float2(1, 1), float2(1, 0),
        float2(0, 1), float2(1, 0), float2(0, 0)
    };

    float2 corner = corners[vertexID];
    float spriteSize = inst.size;

    // Extract camera right and up vectors from view matrix
    float3 camRight = float3(uniforms.viewMatrix[0][0], uniforms.viewMatrix[1][0], uniforms.viewMatrix[2][0]);
    float3 camUp = float3(uniforms.viewMatrix[0][1], uniforms.viewMatrix[1][1], uniforms.viewMatrix[2][1]);

    // World position = instance center + billboard offset
    float3 worldPos = inst.position + camRight * corner.x * spriteSize + camUp * corner.y * spriteSize;

    GlowVertexOut out;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * float4(worldPos, 1.0);
    out.texCoord = uvs[vertexID];
    out.color = inst.color;
    out.opacity = inst.opacity;
    return out;
}
```

Glow texture (generated once, like web app's `initGlowTexture()`):
```swift
func createGlowTexture(device: MTLDevice) -> MTLTexture {
    let size = 64
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    let center = Float(size) / 2.0

    for y in 0..<size {
        for x in 0..<size {
            let dx = Float(x) - center
            let dy = Float(y) - center
            let dist = sqrt(dx * dx + dy * dy) / center

            // Radial gradient: bright center -> transparent edge
            let alpha: Float
            if dist < 0.3 { alpha = 1.0 }
            else if dist < 0.7 { alpha = 1.0 - (dist - 0.3) / 0.4 * 0.9 }
            else if dist < 1.0 { alpha = 0.1 * (1.0 - (dist - 0.7) / 0.3) }
            else { alpha = 0 }

            let idx = (y * size + x) * 4
            pixels[idx] = 255     // R
            pixels[idx+1] = 255   // G
            pixels[idx+2] = 255   // B
            pixels[idx+3] = UInt8(alpha * 255)  // A
        }
    }

    let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
    let texture = device.makeTexture(descriptor: desc)!
    texture.replace(region: MTLRegionMake2D(0, 0, size, size),
                    mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 4)
    return texture
}
```

**Confidence:** HIGH -- Additive blending via `MTLRenderPipelineColorAttachmentDescriptor` is documented by Apple. Billboard technique (extracting camera right/up from view matrix) is standard 3D graphics. Web app reference confirms the visual approach (lines 3167-3183).

### Anti-Patterns to Avoid

- **One draw call per aircraft:** The web app uses individual THREE.Group objects per aircraft. In Metal, this would be hundreds of `drawPrimitives` calls. Always use instanced rendering -- 6 draw calls for 6 categories regardless of aircraft count.

- **Blocking main thread with network:** Never call URLSession synchronously in `draw(in:)`. The actor runs async polling on its own; the renderer only reads the latest interpolated state.

- **Creating buffers per frame:** Pre-allocate instance buffers at a generous capacity (e.g., 500 aircraft) and grow only when needed. Never `device.makeBuffer()` inside the render loop.

- **Storing Double in instance buffers:** Metal shaders use `float`. Keep lat/lon as `Double` for precision, but convert to `Float` world coordinates before writing to the instance buffer.

- **Interpolating in the actor:** The interpolation must happen on the render thread (in `draw(in:)`) using the current frame time. If done in the actor, there's a timing mismatch between when interpolation runs and when the frame renders.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON decoding | Manual string parsing | `JSONDecoder` + `Codable` structs | ADS-B responses have 40+ fields with optional values; Codable handles this correctly |
| HTTP requests | Socket-level networking | `URLSession.shared.data(from:)` async | Handles HTTP/2, connection pooling, DNS, TLS automatically |
| Matrix math | Manual 4x4 operations | `simd_float4x4` operations | Hardware-accelerated on Apple Silicon NEON, matches Metal shader types |
| Thread safety for data | Manual locks/mutexes | Swift `actor` isolation | Compile-time data race checking; impossible to access actor state unsafely |
| Radial gradient texture | CoreGraphics rendering | Direct pixel array generation | Only 64x64 pixels, faster to compute directly than setting up a CG context |

## Common Pitfalls

### Pitfall 1: Altitude Field Variance Across APIs

**What goes wrong:** `dump1090` uses `altitude` (number or "ground" string), while `airplanes.live`/`adsb.lol` use `alt_baro` (number or "ground" string) and `alt_geom` (always number). Forgetting to handle "ground" as a string causes JSON decode crashes.

**Why it happens:** The ADS-B v2 API format encodes `alt_baro` as either a number OR the literal string "ground" when an aircraft is on the ground. Standard Codable decoding fails because the type varies.

**How to avoid:** Use a custom `Codable` implementation for altitude:
```swift
enum AltitudeValue: Codable {
    case feet(Int)
    case ground

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .feet(intVal)
        } else if let strVal = try? container.decode(String.self), strVal == "ground" {
            self = .ground
        } else {
            self = .feet(0)
        }
    }

    var asFeet: Float {
        switch self {
        case .feet(let f): return Float(f)
        case .ground: return 0
        }
    }
}
```

**Warning signs:** Aircraft appearing at wrong altitudes, JSON decode errors in console.

### Pitfall 2: Heading Interpolation Wraparound

**What goes wrong:** Aircraft heading jumps discontinuously when interpolating between 350 degrees and 10 degrees (e.g., lerp goes through 180 degrees instead of through 0/360).

**Why it happens:** Linear interpolation does not understand angular wraparound. `lerp(350, 10, 0.5)` gives 180 instead of 0.

**How to avoid:** Use `lerpAngle` function that normalizes the difference to [-180, 180] before interpolating. The web app already has this (line 4143-4149). Port it exactly.

**Warning signs:** Aircraft briefly spinning 360 degrees when heading crosses north.

### Pitfall 3: Instance Buffer Capacity Management

**What goes wrong:** Instance buffer is too small when aircraft count spikes (e.g., switching from local mode with 20 aircraft to global mode with 300 aircraft).

**Why it happens:** Buffer was allocated for local mode capacity and not resized.

**How to avoid:** Allocate for max expected capacity (512 or 1024 aircraft) upfront. The instance buffer at 96 bytes per aircraft is only ~96 KB for 1024 aircraft -- trivially small. If count exceeds capacity, reallocate at 2x.

**Warning signs:** Crash in `draw(in:)` with buffer overrun, or missing aircraft.

### Pitfall 4: Stale Aircraft Not Removed

**What goes wrong:** Aircraft that have landed or left range remain on screen indefinitely.

**Why it happens:** The data buffer is never cleaned up for aircraft that stop appearing in API responses.

**How to avoid:** Track `lastSeen` timestamp per aircraft. Remove aircraft from the buffer if not seen for longer than `pollingInterval + INTERPOLATION_DELAY + 2 seconds` (matches web app logic at line 4117-4127). Different thresholds for local (4s) vs global (9s).

**Warning signs:** Permanently frozen aircraft, increasing aircraft count that never decreases.

### Pitfall 5: Category Misidentification

**What goes wrong:** Aircraft categorization based on callsign/altitude/speed heuristics produces wrong model type (e.g., slow heavy aircraft at low altitude misidentified as "small").

**Why it happens:** The heuristic from the web app (line 5643-5678) is imprecise -- it uses callsign patterns and flight parameters rather than actual aircraft type data.

**How to avoid:** First check the `t` (type code) field from the database if available -- this gives actual ICAO type designator. The `category` field (A0-D7) from ADS-B also helps classify. Fall back to the callsign/speed heuristic only when `t` and `category` are unavailable. Priority: `t` type code > ADS-B `category` field > callsign/speed heuristic.

**Warning signs:** Helicopters rendered as jets, small props at high altitude.

### Pitfall 6: Animation Timing Tied to Frame Rate

**What goes wrong:** Position light blinks and rotor spins at different speeds on 60fps vs 120fps displays, or when frame rate drops.

**Why it happens:** Using a fixed increment per frame instead of delta-time-based animation.

**How to avoid:** All animations must use `deltaTime`:
- Position light phase: `lightPhase += deltaTime * 5.0` (not `+= 0.08`)
- Rotor spin: `rotorAngle += deltaTime * 0.7 * 2 * .pi` (0.7 rotations/second, matching web app line 4984)
- Glow pulse: derived from `lightPhase`, which is already time-based

**Warning signs:** Animations running at double speed on ProMotion displays.

## Code Examples

### ADS-B API Response Codable Models

```swift
// Source: Verified against live airplanes.live API response and readsb README-json.md

/// V2 API response (airplanes.live, adsb.lol -- identical format)
struct ADSBV2Response: Codable {
    let ac: [ADSBV2Aircraft]?
    let msg: String?
    let now: Double?
    let total: Int?
    let ctime: Double?
    let ptime: Double?
}

struct ADSBV2Aircraft: Codable {
    let hex: String?
    let flight: String?
    let r: String?          // registration
    let t: String?          // ICAO type code (e.g., "B738", "A320")
    let desc: String?       // long type name
    let lat: Double?
    let lon: Double?
    let alt_baro: AltitudeValue?   // number or "ground"
    let alt_geom: Int?
    let gs: Double?         // ground speed knots
    let track: Double?      // true track 0-359
    let baro_rate: Int?     // ft/min
    let geom_rate: Int?     // ft/min
    let squawk: String?
    let category: String?   // ADS-B emitter category A0-D7
    let emergency: String?
    let nav_heading: Double?
    let true_heading: Double?
    let mag_heading: Double?
    let ias: Int?
    let tas: Int?
    let mach: Double?
    let seen: Double?       // seconds since last message
    let seen_pos: Double?   // seconds since last position
    let messages: Int?
    let rssi: Double?
    let dbFlags: Int?       // 1=military, 2=interesting, 4=PIA, 8=LADD
}

/// dump1090 local response (older format)
struct Dump1090Response: Codable {
    let now: Double?
    let messages: Int?
    let aircraft: [Dump1090Aircraft]?
}

struct Dump1090Aircraft: Codable {
    let hex: String?
    let flight: String?
    let lat: Double?
    let lon: Double?
    let altitude: AltitudeValue?   // number or "ground"
    let speed: Double?      // ground speed (knots)
    let track: Double?
    let vert_rate: Int?     // ft/min (older field name)
    let squawk: String?
    let seen: Double?
    let messages: Int?
    let rssi: Double?
}
```

### Data Normalization

```swift
// Source: Web app DataSource.normalize() at line 1146

struct AircraftModel: Sendable {
    let hex: String
    var callsign: String
    var lat: Double
    var lon: Double
    var altitude: Float         // feet, 0 for ground
    var track: Float            // degrees 0-359
    var groundSpeed: Float      // knots
    var verticalRate: Float     // ft/min
    var squawk: String
    var category: String        // ADS-B category A0-D7
    var registration: String    // from r field
    var typeCode: String        // from t field (ICAO type)
    var dbFlags: Int            // military, interesting flags
}

enum DataNormalizer {
    static func normalizeV2(_ response: ADSBV2Response) -> [AircraftModel] {
        guard let acList = response.ac else { return [] }
        return acList.compactMap { ac -> AircraftModel? in
            guard let hex = ac.hex,
                  let lat = ac.lat,
                  let lon = ac.lon else { return nil }

            return AircraftModel(
                hex: hex,
                callsign: (ac.flight ?? "").trimmingCharacters(in: .whitespaces),
                lat: lat,
                lon: lon,
                altitude: ac.alt_baro?.asFeet ?? Float(ac.alt_geom ?? 0),
                track: Float(ac.track ?? 0),
                groundSpeed: Float(ac.gs ?? 0),
                verticalRate: Float(ac.baro_rate ?? ac.geom_rate ?? 0),
                squawk: ac.squawk ?? "",
                category: ac.category ?? "",
                registration: ac.r ?? "",
                typeCode: ac.t ?? "",
                dbFlags: ac.dbFlags ?? 0
            )
        }
    }

    static func normalizeDump1090(_ response: Dump1090Response) -> [AircraftModel] {
        guard let acList = response.aircraft else { return [] }
        return acList.compactMap { ac -> AircraftModel? in
            guard let hex = ac.hex,
                  let lat = ac.lat,
                  let lon = ac.lon else { return nil }

            return AircraftModel(
                hex: hex,
                callsign: (ac.flight ?? "").trimmingCharacters(in: .whitespaces),
                lat: lat,
                lon: lon,
                altitude: ac.altitude?.asFeet ?? 0,
                track: Float(ac.track ?? 0),
                groundSpeed: Float(ac.speed ?? 0),
                verticalRate: Float(ac.vert_rate ?? 0),
                squawk: ac.squawk ?? "",
                category: "",
                registration: "",
                typeCode: "",
                dbFlags: 0
            )
        }
    }
}
```

### Aircraft Category Classification

```swift
// Source: Web app getAircraftCategory() at line 5643, enhanced with type code lookup

enum AircraftCategory: CaseIterable, Sendable {
    case jet        // narrowbody (default)
    case widebody   // wide-body long-haul
    case helicopter // rotary wing
    case small      // GA prop plane
    case military   // military aircraft
    case regional   // regional jet/turboprop

    static func classify(_ aircraft: AircraftModel) -> AircraftCategory {
        // Priority 1: Use dbFlags for military identification
        if aircraft.dbFlags & 1 != 0 { return .military }

        // Priority 2: Use ADS-B category field (A0-D7)
        switch aircraft.category {
        case "A1":          return .small      // Light (<15,500 lbs)
        case "A2":          return .small      // Small (15,500-75,000 lbs)
        case "A3":          return .regional   // Large (75,000-300,000 lbs)
        case "A4":          return .jet        // High vortex large (e.g. B757)
        case "A5":          return .widebody   // Heavy (>300,000 lbs)
        case "A6":          return .widebody   // High performance (>5g, >400kts)
        case "A7":          return .helicopter // Rotorcraft
        case "B1", "B2":    return .small      // Glider / lighter than air
        default:            break
        }

        // Priority 3: Use ICAO type code (t field)
        let type = aircraft.typeCode.uppercased()
        if !type.isEmpty {
            // Helicopter type codes often start with specific patterns
            let heliTypes = ["R22", "R44", "R66", "B06", "B47", "EC35", "EC45", "AS50",
                           "S76", "B412", "A109", "B429", "H60", "UH1"]
            if heliTypes.contains(where: { type.hasPrefix($0) }) { return .helicopter }

            // Wide-body type codes
            let wideTypes = ["B74", "B77", "B78", "A33", "A34", "A35", "A38", "B76", "MD11"]
            if wideTypes.contains(where: { type.hasPrefix($0) }) { return .widebody }

            // Military type codes
            let milTypes = ["F16", "F15", "F18", "F22", "F35", "C17", "C130", "C5", "KC",
                          "B1", "B2", "B52", "E3", "E6", "P8", "V22"]
            if milTypes.contains(where: { type.hasPrefix($0) }) { return .military }
        }

        // Priority 4: Callsign + flight parameter heuristics (web app fallback)
        let callsign = aircraft.callsign.uppercased()
        let alt = aircraft.altitude
        let speed = aircraft.groundSpeed

        // Helicopter patterns
        if alt < 3000 && speed < 150 {
            let heliCallsigns = ["LIFE", "MED", "HELI", "COAST", "RESCUE"]
            if heliCallsigns.contains(where: { callsign.hasPrefix($0) }) { return .helicopter }
            if callsign.hasPrefix("N") && callsign.count > 1 && callsign.dropFirst().first?.isNumber == true {
                return .helicopter
            }
        }

        // Military callsign patterns
        let milCallsigns = ["RCH", "REACH", "DUKE", "EVAC", "SPAR", "EXEC",
                           "FORCE", "NAVY", "ARMY", "TOPCAT", "HAWK"]
        if milCallsigns.contains(where: { callsign.hasPrefix($0) }) { return .military }

        // Small aircraft (low/slow with GA callsign)
        if alt < 10000 && speed < 200 {
            if callsign.hasPrefix("N") || callsign.isEmpty { return .small }
        }

        // Regional (medium altitude, medium speed)
        if alt < 30000 && speed < 400 { return .regional }

        // Wide-body indicators (long-haul carrier callsigns)
        let wideCallsigns = ["UAE", "QTR", "SIA", "CPA", "BAW", "DLH", "AFR", "KLM", "ANA", "JAL"]
        if wideCallsigns.contains(where: { callsign.hasPrefix($0) }) { return .widebody }

        return .jet // Default: narrowbody jet
    }
}
```

### Altitude Color Mapping

```swift
// Source: Web app getAltitudeColor() at line 3643

func altitudeColor(_ altitude: Float) -> SIMD4<Float> {
    // Green -> Yellow -> Orange -> Pink gradient
    if altitude < 5000 {
        return SIMD4<Float>(0, 1, 0, 1)          // Green
    } else if altitude < 15000 {
        let t = (altitude - 5000) / 10000
        return SIMD4<Float>(t, 1, 0, 1)          // Green -> Yellow
    } else if altitude < 30000 {
        let t = (altitude - 15000) / 15000
        return SIMD4<Float>(1, 1 - t * 0.47, 0, 1) // Yellow -> Orange
    } else {
        return SIMD4<Float>(1, 0, 0.53, 1)       // Pink
    }
}
```

### Position Light Animation

```swift
// Source: Web app animate loop at line 4960-4979
// Aviation standard: anti-collision lights 40-100 cycles/minute

// In instance buffer update (per frame):
// lightPhase advances at ~5 radians/second (gives ~0.8 Hz blink, within aviation spec)
instance.lightPhase += deltaTime * 5.0

// In fragment shader:
// White strobe: sharp on/off at ~1Hz (sin > 0.7 threshold from web app)
float strobeBrightness = step(0.7, sin(in.lightPhase));

// Red beacon: slower, 0.5 Hz
float beaconBrightness = step(0.5, sin(in.lightPhase * 0.6));

// Glow pulse: smooth, subtle
float glowOpacity = 0.3 + 0.15 * sin(in.lightPhase * 0.5);
float glowScale = 7.0 + 1.5 * sin(in.lightPhase * 0.3);
```

### Aircraft Instance Shader

```metal
// AircraftShaders.metal

struct AircraftVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct AircraftVertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPosition;
    float4 color;
    float  lightPhase;
    uint   flags;
};

vertex AircraftVertexOut aircraft_vertex(
    AircraftVertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
    constant AircraftInstanceData *instances [[buffer(BufferIndexInstances)]],
    uint instanceID [[instance_id]])
{
    AircraftInstanceData inst = instances[instanceID];

    float4 worldPos = inst.modelMatrix * float4(in.position, 1.0);
    float3 worldNormal = normalize((inst.modelMatrix * float4(in.normal, 0.0)).xyz);

    AircraftVertexOut out;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldNormal = worldNormal;
    out.worldPosition = worldPos.xyz;
    out.color = inst.color;
    out.lightPhase = inst.lightPhase;
    out.flags = inst.flags;
    return out;
}

fragment float4 aircraft_fragment(AircraftVertexOut in [[stage_in]])
{
    // Simple directional lighting
    float3 lightDir = normalize(float3(0.5, 1.0, 0.5));
    float diffuse = max(dot(in.worldNormal, lightDir), 0.0);
    float ambient = 0.3;
    float lighting = ambient + diffuse * 0.7;

    float3 litColor = in.color.rgb * lighting;

    // Position light blink (white strobe)
    float blink = step(0.7, sin(in.lightPhase));
    litColor += float3(1.0, 1.0, 1.0) * blink * 0.2;

    // Red beacon (slower)
    float beacon = step(0.5, sin(in.lightPhase * 0.6));
    litColor += float3(1.0, 0.0, 0.0) * beacon * 0.15;

    // Selection highlight
    if (in.flags & 1u) {
        litColor = mix(litColor, float3(1.0, 0.8, 0.0), 0.3);
    }

    return float4(litColor, 1.0);
}
```

## ADS-B API Reference

### API Endpoints (Verified)

| API | Endpoint Pattern | Polling Rate | Auth |
|-----|-----------------|-------------|------|
| **dump1090 local** | `http://localhost:8080/data/aircraft.json` | 1 second | None |
| **airplanes.live** | `https://api.airplanes.live/v2/point/{lat}/{lon}/{radius_nm}` | 5 seconds | None |
| **adsb.lol** | `https://api.adsb.lol/v2/point/{lat}/{lon}/{radius_nm}` | 5 seconds | None |

### Response Format Comparison

| Field | dump1090 | airplanes.live / adsb.lol (v2) |
|-------|----------|-------------------------------|
| Aircraft hex ID | `hex` | `hex` |
| Callsign | `flight` | `flight` |
| Latitude | `lat` | `lat` |
| Longitude | `lon` | `lon` |
| Altitude (baro) | `altitude` (number or "ground") | `alt_baro` (number or "ground") |
| Altitude (geo) | -- | `alt_geom` |
| Ground speed | `speed` | `gs` |
| Track | `track` | `track` |
| Vertical rate | `vert_rate` | `baro_rate` / `geom_rate` |
| Squawk | `squawk` | `squawk` |
| Category | -- | `category` (A0-D7) |
| Registration | -- | `r` |
| Type code | -- | `t` |
| DB flags | -- | `dbFlags` (military=1, interesting=2) |
| Aircraft list key | `aircraft` (array) | `ac` (array) |

### Key Constants (from web app)

| Constant | Value | Source |
|----------|-------|--------|
| Local polling interval | 1000 ms | Web app line 1117 |
| Global polling interval | 5000 ms | Web app line 1126 |
| Global search radius | 250 NM | Web app line 1127 |
| Interpolation delay | 2000 ms | Web app line 2103 |
| Buffer window (local) | 5000 ms | Web app line 4109 |
| Buffer window (global) | 15000 ms | Web app line 4109 |
| Stale threshold (local) | DELAY + 2000 ms | Web app line 4118-4119 |
| Stale threshold (global) | DELAY + INTERVAL + 2000 ms | Web app line 4118 |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ObservableObject` + `@Published` | `@Observable` macro | macOS 14 / Swift 5.9 | Fine-grained property tracking, less boilerplate |
| Combine publishers for polling | `AsyncStream` + actor | Swift 5.5+ | Structured concurrency, automatic cancellation |
| Per-object draw calls | Instanced rendering | Always in Metal | 6 draw calls instead of 200+, 10x+ performance |
| THREE.js global mutable state | Swift actor isolation | Native rewrite | Compile-time data race prevention |
| OpenSky Network API | airplanes.live + adsb.lol | 2023-2024 | OpenSky added rate limits; airplanes.live/adsb.lol are more reliable |

**Deprecated/outdated:**
- OpenSky Network API: Added aggressive rate limiting, often returns 429 errors. Kept as last-resort fallback but not primary.
- `ObservableObject` pattern: Still works but `@Observable` is the Apple-recommended replacement.

## Rotor/Propeller Animation Strategy

Rotors and propellers cannot be animated via the per-instance `rotorAngle` field alone because they are sub-parts of the aircraft mesh. Two approaches:

**Approach A (Recommended): Separate draw call for spinning parts.**
Generate rotor and propeller meshes separately from the aircraft body. During rendering, draw the static aircraft body first (instanced), then draw the spinning parts (also instanced) with a modified model matrix that includes the rotation around the spin axis. This requires an additional instance buffer for spinning parts with their own model matrices.

**Approach B: Compute shader pre-transform.**
Use a Metal compute kernel to transform rotor/propeller vertices before the vertex shader reads them. More complex, not needed for this number of instances.

**Approach C: Vertex shader conditional rotation.**
Pass the `rotorAngle` in the instance data. In the vertex shader, check if the vertex position falls within the rotor/propeller bounding region and apply rotation. This is hacky but avoids extra draw calls.

**Recommendation:** Use Approach A. It adds at most 2 more draw calls (one for helicopter rotors, one for propellers) but keeps the architecture clean. Total draw calls: 6 categories + 2 spinning parts = 8 draw calls for all aircraft, which is still trivial.

## Open Questions

1. **Altitude scale factor for Metal world space**
   - What we know: Web app uses `altitude * BASE_ALT_SCALE` where `BASE_ALT_SCALE = 0.0001`, with a user-configurable multiplier (1x-100x). At 10x default, 35000 feet = 35000 * 0.001 = 35 world units. The `worldScale=500` means 1 degree longitude = 500 world units. This ratio looks reasonable.
   - What's unclear: The exact scale factor that looks good with the Metal camera/projection setup. The web app's scale was tuned for THREE.js camera distances.
   - Recommendation: Start with the same `0.001` base scale (10x default) and tune visually. Make it configurable early.

2. **Instance buffer triple-buffering**
   - What we know: Uniform buffers are already triple-buffered. Instance buffers are written by CPU and read by GPU in the same frame.
   - What's unclear: Whether the instance buffer needs its own triple-buffering ring or can be safely written each frame before encoding.
   - Recommendation: Triple-buffer the instance buffer too (3 buffers, same ring as uniforms). The overhead is minimal (3 * 96KB = 288KB for 1024 aircraft) and eliminates any risk of CPU/GPU contention.

3. **dump1090 URL configurability**
   - What we know: The web app hardcodes `/dump1090/data/aircraft.json`. Local dump1090 setups vary (different ports, different paths).
   - What's unclear: Whether a user settings UI for the local URL is needed in this phase.
   - Recommendation: Make the base URL configurable via a constant in the actor, with a sensible default (`http://localhost:8080/data/aircraft.json`). Defer the settings UI to a later phase.

## Sources

### Primary (HIGH confidence)
- **airplanes.live API** -- verified via live API call to `https://api.airplanes.live/v2/point/47.6/-122.3/25`, confirmed field names: hex, flight, lat, lon, alt_baro, gs, track, baro_rate, squawk, category, r, t, desc, dbFlags
- **readsb README-json.md** -- [GitHub](https://github.com/wiedehopf/readsb/blob/dev/README-json.md) -- complete field documentation for aircraft.json format used by dump1090-fa and readsb
- **ADS-B Exchange v2 API fields** -- [adsbexchange.com](https://www.adsbexchange.com/version-2-api-wip/) -- comprehensive field list with types and descriptions (airplanes.live and adsb.lol use this same format)
- **Metal by Example: Instanced Rendering** -- [metalbyexample.com](https://metalbyexample.com/instanced-rendering/) -- vertex descriptor stepFunction perInstance, instance_id in shaders, drawIndexedPrimitives(instanceCount:)
- **Apple: MTLRenderPipelineColorAttachmentDescriptor** -- [developer.apple.com](https://developer.apple.com/documentation/metal/mtlrenderpipelinecolorattachmentdescriptor) -- additive blending configuration
- **Existing web app** -- `/Users/mit/Documents/GitHub/airplane-tracker-3d/airplane-tracker-3d-map.html` -- data pipeline (lines 1115-1221, 4053-4134), interpolation (lines 4137-4335), geometry (lines 3063-3132), animation (lines 4959-4993), category classification (lines 5643-5678)
- **Existing Phase 5 code** -- Renderer.swift, ShaderTypes.h, Shaders.metal, MapCoordinateSystem.swift, OrbitCamera.swift -- verified current Metal setup, buffer indices, pipeline patterns

### Secondary (MEDIUM confidence)
- **Pilot Institute: Airplane Lights** -- [pilotinstitute.com](https://pilotinstitute.com/airplane-lights/) -- anti-collision light flash rate: 40-100 cycles/minute (aviation standard)
- **Metal by Example: Translucency and Transparency** -- [metalbyexample.com](https://metalbyexample.com/translucency-and-transparency/) -- additive blending pipeline setup
- **SwiftLee: URLSession async/await** -- [avanderlee.com](https://www.avanderlee.com/concurrency/urlsession-async-await-network-requests-in-swift/) -- modern async networking patterns

### Tertiary (LOW confidence)
- None -- all findings verified against primary sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- zero external dependencies, all Apple frameworks verified
- API formats: HIGH -- verified against live API responses and official documentation
- Instanced rendering: HIGH -- verified with Metal by Example code examples + existing Phase 5 patterns
- Procedural geometry: HIGH -- dimensions taken directly from web app source code
- Interpolation: HIGH -- direct port of working web app code
- Animation timing: MEDIUM -- aviation light standards verified; specific shader math needs tuning
- Rotor animation architecture: MEDIUM -- Approach A (separate draw calls) is sound but has alternatives

**Research date:** 2026-02-08
**Valid until:** 2026-03-08 (stable domain, ADS-B APIs rarely change format)
