# Architecture Patterns

**Domain:** Native macOS Metal flight tracker (rewrite from THREE.js web app)
**Researched:** 2026-02-08
**Confidence:** HIGH (Metal rendering patterns from Apple docs + Metal by Example; SwiftUI integration from Apple WWDC sessions; Swift concurrency from official documentation)

## Recommended Architecture

The native macOS app uses a three-layer architecture with strict separation: **Data Layer** (Swift concurrency actors + async/await), **Rendering Layer** (Metal pipeline with MTKView), and **UI Layer** (SwiftUI with NSViewRepresentable bridge). The Data Layer and Rendering Layer communicate through a shared observable model. The UI Layer reads from the same model and sends user actions back through it.

This is NOT a port of the web app's procedural architecture. The web version uses global mutable state, a single `animate()` loop, and DOM manipulation. The native version uses value types, actors for thread safety, protocol-oriented rendering, and SwiftUI's declarative UI. The only things preserved are the domain logic (coordinate transforms, interpolation math, data normalization) and the visual design.

```
+------------------------------------------------------------------+
|                        SwiftUI Layer                              |
|  [InfoPanel] [ControlsView] [AirportSearch] [SettingsView]       |
|  [SelectedPlaneView] [GraphsView] [StatusBar]                    |
+------------------------------------------------------------------+
        |  reads @Observable       |  user actions
        v                          v
+------------------------------------------------------------------+
|                    AppState (@Observable)                         |
|  - aircraftList: [AircraftModel]                                 |
|  - selectedAircraft: AircraftModel?                              |
|  - settings: AppSettings                                         |
|  - dataSourceMode: DataSourceMode                                |
|  - connectionStatus: ConnectionStatus                            |
+------------------------------------------------------------------+
        |  supplies data to         ^  receives updates from
        v                          |
+------------------------------------------------------------------+
|                    Metal Renderer                                 |
|  [MetalView: NSViewRepresentable wrapping MTKView]                |
|  [Renderer: MTKViewDelegate]                                     |
|  [AircraftRenderPass] [MapTileRenderPass] [TrailRenderPass]       |
|  [LabelRenderPass] [AltitudeLineRenderPass]                      |
+------------------------------------------------------------------+
        |  GPU commands             ^  per-frame data
        v                          |
+------------------------------------------------------------------+
|                    Metal GPU Pipeline                             |
|  [Command Queue] [Pipeline States] [Vertex/Fragment Shaders]     |
|  [Texture Cache] [Instance Buffers] [Uniform Buffers]            |
+------------------------------------------------------------------+

        -------- Separate async domain --------

+------------------------------------------------------------------+
|                    Data Layer (Actors)                            |
|  [FlightDataActor] - polls dump1090/airplanes.live/adsb.lol      |
|  [AircraftInterpolator] - smooth position interpolation           |
|  [EnrichmentActor] - hexdb.io/adsbdb lookups                     |
|  [AirportDataActor] - OurAirports CSV loading + search           |
|  [SettingsStore] - UserDefaults persistence                       |
+------------------------------------------------------------------+
        |  URLSession async/await
        v
+------------------------------------------------------------------+
|                    Network / External APIs                        |
|  [dump1090] [airplanes.live] [adsb.lol] [OpenSky]                |
|  [hexdb.io] [adsbdb.com]                                         |
+------------------------------------------------------------------+
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| **AppState** | Central observable model. Holds aircraft list, selection, settings, connection status. Published to both SwiftUI and Renderer. | SwiftUI views (read), Data Layer actors (write), Renderer (read) |
| **MetalView** | NSViewRepresentable wrapping MTKView. Bridges SwiftUI layout to Metal rendering surface. Forwards mouse/keyboard input. | SwiftUI (hosting), Renderer (delegate) |
| **Renderer** | MTKViewDelegate. Owns Metal device, command queue, pipeline states. Reads AppState each frame, encodes draw commands. | MTKView (delegate callbacks), AppState (read), GPU (command buffers) |
| **FlightDataActor** | Actor managing data polling. Runs async polling loop with fallback chain. Normalizes responses to common AircraftModel. | Network (URLSession), AppState (publishes updates) |
| **AircraftInterpolator** | Smoothly interpolates aircraft positions between data updates (5-10s intervals to 60fps). Runs on render thread or dedicated actor. | AppState aircraft array (read/write per frame) |
| **EnrichmentActor** | Lazily fetches aircraft metadata (registration, type, route) from enrichment APIs. Caches results. | Network (URLSession), AppState (enriches aircraft models) |
| **AirportDataActor** | Loads OurAirports CSV once, builds search index. Provides search and nearby queries. | Network (one-time CSV fetch), AppState (search results) |
| **SettingsStore** | Persists user preferences to UserDefaults. Restores on launch. | AppState settings (read/write) |

### Data Flow

**Aircraft data flow (network to pixels):**

```
FlightDataActor (polling every 1-10s)
  |
  | async/await URLSession
  v
Raw JSON from API (ADSBx v2 format: {ac: [{hex, lat, lon, alt_baro, ...}]})
  |
  | DataNormalizer.normalize() -> [AircraftModel]
  v
AppState.aircraftList updated on @MainActor
  |
  | @Observable notifies SwiftUI (info panels update)
  | Renderer reads in draw(in:) callback
  v
AircraftInterpolator.interpolate(aircraft, deltaTime)
  |
  | Produces interpolated position/rotation per frame
  v
Renderer encodes to per-instance buffer
  |
  | setVertexBuffer + drawIndexedPrimitives(instanceCount:)
  v
GPU renders instanced aircraft geometry
```

**User interaction flow (click to selection):**

```
Mouse click on MTKView
  |
  | MTKView subclass overrides mouseDown(with:)
  | Converts window coordinates to Metal NDC
  v
Renderer.hitTest(point) -> AircraftModel?
  |
  | Ray-cast from camera through click point
  | Test against aircraft bounding spheres
  v
AppState.selectedAircraft = hitAircraft
  |
  | @Observable notifies both SwiftUI and Renderer
  v
SwiftUI: SelectedPlaneView appears with detail info
Renderer: Highlights selected aircraft, starts follow camera if enabled
```

## Xcode Project Structure

Use a standard Xcode project with Swift Package Manager for external dependencies (none expected for core app). Internal code is organized as Xcode groups (folders), not separate SPM packages, because Metal shader files (.metal) must be in the main app target for Xcode to compile them into default.metallib automatically. Putting .metal files in an SPM package requires manual metallib compilation and is not worth the complexity.

```
AirplaneTracker3D/
|-- AirplaneTracker3D.xcodeproj
|-- AirplaneTracker3D/
|   |-- App/
|   |   |-- AirplaneTracker3DApp.swift          # @main, WindowGroup
|   |   |-- AppState.swift                       # Central @Observable model
|   |   |-- ContentView.swift                    # Root view: ZStack of MetalView + SwiftUI overlays
|   |
|   |-- Models/
|   |   |-- AircraftModel.swift                  # Aircraft data model (position, track, altitude, etc.)
|   |   |-- AirportModel.swift                   # Airport data model (ICAO, IATA, coords, type)
|   |   |-- AppSettings.swift                    # Persisted settings (theme, units, trail config)
|   |   |-- DataSourceMode.swift                 # Enum: .local, .global
|   |   |-- AircraftCategory.swift               # Enum: helicopter, small, regional, narrowbody, widebody, military
|   |
|   |-- DataLayer/
|   |   |-- FlightDataActor.swift                # Actor: polling loop with fallback chain
|   |   |-- DataNormalizer.swift                  # Normalizes dump1090/adsb.lol/OpenSky to AircraftModel
|   |   |-- AircraftInterpolator.swift            # Position interpolation between data updates
|   |   |-- EnrichmentActor.swift                 # Actor: hexdb.io/adsbdb enrichment with cache
|   |   |-- AirportDataActor.swift                # Actor: CSV loading, search index, nearby queries
|   |   |-- SettingsStore.swift                   # UserDefaults persistence
|   |   |-- NetworkClient.swift                   # Thin URLSession wrapper with timeout/retry
|   |
|   |-- Rendering/
|   |   |-- MetalView.swift                       # NSViewRepresentable wrapping MTKView
|   |   |-- Renderer.swift                        # MTKViewDelegate, owns all Metal state
|   |   |-- RenderPipelines.swift                 # Pipeline state creation (aircraft, map, trails, labels)
|   |   |-- Camera.swift                          # Orbit camera: projection + view matrices
|   |   |-- CoordinateSystem.swift                # latLonToXZ, altitudeScale, mapBounds
|   |   |-- AircraftMeshes.swift                  # Geometry data for aircraft categories (vertex buffers)
|   |   |-- MapTileManager.swift                  # Tile loading, texture creation, tile grid math
|   |   |-- TrailRenderer.swift                   # Trail line rendering with altitude color gradient
|   |   |-- LabelRenderer.swift                   # Text-to-texture label rendering (Core Text + Metal)
|   |   |-- TextureCache.swift                    # LRU texture cache for map tiles and labels
|   |
|   |-- Shaders/
|   |   |-- ShaderTypes.h                         # Shared structs between Swift and MSL (bridging header)
|   |   |-- AircraftShaders.metal                 # Vertex/fragment for instanced aircraft rendering
|   |   |-- MapTileShaders.metal                  # Vertex/fragment for textured ground plane tiles
|   |   |-- TrailShaders.metal                    # Vertex/fragment for colored trail lines
|   |   |-- LabelShaders.metal                    # Vertex/fragment for billboard text sprites
|   |   |-- CommonShaders.metal                   # Shared functions (lighting, color utilities)
|   |
|   |-- Views/
|   |   |-- InfoPanelView.swift                   # Aircraft count, message rate, data source indicator
|   |   |-- SelectedPlaneView.swift               # Selected aircraft detail panel
|   |   |-- ControlsView.swift                    # Theme, units, altitude slider, trail toggles
|   |   |-- AirportSearchView.swift               # Search bar with autocomplete dropdown
|   |   |-- GraphsView.swift                      # Statistics charts (message rate, aircraft count)
|   |   |-- SettingsView.swift                    # Preferences window
|   |   |-- StatusBarView.swift                   # Bottom bar: FPS, data source, connection status
|   |
|   |-- Utilities/
|   |   |-- MathUtilities.swift                   # Haversine, lerp, clamp, matrix helpers
|   |   |-- ColorUtilities.swift                  # Altitude-to-color mapping, theme colors
|   |   |-- CSVParser.swift                       # Lightweight CSV parser for OurAirports data
|   |
|   |-- Resources/
|   |   |-- Assets.xcassets                       # App icon, color sets
|   |   |-- AirplaneTracker3D-Bridging-Header.h   # Imports ShaderTypes.h for Swift access
|   |
|   |-- Info.plist
```

### Structure Rationale

- **Shaders/ as a top-level group:** Metal .metal files must be in the main target for Xcode's automatic metallib compilation. Separating them into their own group keeps shader code distinct from Swift code while maintaining build system compatibility.

- **ShaderTypes.h bridging header:** This is the standard Apple-recommended pattern for sharing struct definitions between Swift (CPU) and MSL (GPU). The bridging header imports this file, making types like `Uniforms`, `PerInstanceData`, `VertexIn` available to both sides without duplication.

- **DataLayer/ uses actors, not classes:** Swift actors provide compile-time data race safety. The `FlightDataActor` can safely be called from any thread/task. The `@MainActor` annotation on AppState ensures UI updates happen on the main thread.

- **Rendering/ owns all Metal state:** The Renderer is the single owner of MTLDevice, MTLCommandQueue, and all pipeline states. No Metal objects leak into the SwiftUI layer. This prevents accidental cross-thread GPU access.

- **Models/ are value types (structs):** `AircraftModel`, `AirportModel`, `AppSettings` are all structs. This ensures they are Sendable (can cross actor boundaries safely) and enables value-semantic diffing for efficient SwiftUI updates.

## Patterns to Follow

### Pattern 1: NSViewRepresentable Bridge for MTKView

**What:** SwiftUI cannot host an MTKView directly. Wrap it in an NSViewRepresentable with a Coordinator that acts as the MTKViewDelegate.

**When:** Always. This is the only way to get Metal rendering into a SwiftUI window on macOS.

**Example:**

```swift
// MetalView.swift
import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
    let appState: AppState

    func makeCoordinator() -> Renderer {
        Renderer(appState: appState)
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = InteractiveMTKView()  // subclass that handles mouse/keyboard
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.1, alpha: 1.0)
        mtkView.preferredFramesPerSecond = 60
        mtkView.delegate = context.coordinator
        context.coordinator.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // SwiftUI state changes flow to renderer through AppState (observed directly)
    }
}

// InteractiveMTKView.swift - subclass for input handling
class InteractiveMTKView: MTKView {
    var inputHandler: ((InputEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        inputHandler?(.mouseDown(location))
    }

    override func mouseDragged(with event: NSEvent) {
        inputHandler?(.mouseDragged(CGPoint(x: event.deltaX, y: event.deltaY)))
    }

    override func scrollWheel(with event: NSEvent) {
        inputHandler?(.scrollWheel(event.deltaY))
    }

    override func keyDown(with event: NSEvent) {
        inputHandler?(.keyDown(event.keyCode, event.modifierFlags))
    }
}
```

**Confidence:** HIGH -- This is the standard Apple-recommended pattern. MTKView is NSView on macOS, requiring NSViewRepresentable. The Coordinator pattern is documented in Apple's SwiftUI tutorials. Metal by Example and Kodeco's Metal by Tutorials both use this exact approach.

### Pattern 2: Renderer as MTKViewDelegate with Triple Buffering

**What:** The Renderer class conforms to MTKViewDelegate and manages all Metal state. It uses triple buffering (3 in-flight frames) with a DispatchSemaphore to synchronize CPU/GPU access to uniform buffers.

**When:** Always. This is the core rendering architecture.

**Example:**

```swift
// Renderer.swift
import MetalKit

class Renderer: NSObject, MTKViewDelegate {
    static let maxFramesInFlight = 3

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let appState: AppState

    // Pipeline states (created once at init)
    private var aircraftPipeline: MTLRenderPipelineState!
    private var mapTilePipeline: MTLRenderPipelineState!
    private var trailPipeline: MTLRenderPipelineState!
    private var labelPipeline: MTLRenderPipelineState!

    private var depthStencilState: MTLDepthStencilState!

    // Triple-buffered uniform buffers
    private var uniformBuffers: [MTLBuffer] = []
    private var currentBufferIndex = 0
    private let frameSemaphore = DispatchSemaphore(value: maxFramesInFlight)

    // Per-instance aircraft data buffer (resized as needed)
    private var aircraftInstanceBuffer: MTLBuffer?
    private var aircraftInstanceCount: Int = 0

    // Camera
    private var camera = OrbitCamera()
    private var projectionMatrix = matrix_identity_float4x4

    init(appState: AppState) {
        self.appState = appState
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = device.makeCommandQueue()!
        super.init()

        buildPipelines()
        buildDepthStencilState()
        allocateUniformBuffers()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width / size.height)
        projectionMatrix = matrix_perspective_projection(
            fovY: Float.pi / 3, aspect: aspect, near: 0.1, far: 2000
        )
    }

    func draw(in view: MTKView) {
        // Wait for a free buffer slot
        frameSemaphore.wait()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            frameSemaphore.signal()
            return
        }

        // Advance buffer index
        currentBufferIndex = (currentBufferIndex + 1) % Self.maxFramesInFlight

        // Update uniforms for this frame
        updateUniforms()

        // Update per-instance aircraft data
        updateAircraftInstances()

        // Encode render commands
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        ) else {
            frameSemaphore.signal()
            return
        }

        encoder.setDepthStencilState(depthStencilState)

        // Draw map tiles (ground plane)
        encodeMapTiles(encoder: encoder)

        // Draw aircraft (instanced)
        encodeAircraft(encoder: encoder)

        // Draw trails
        encodeTrails(encoder: encoder)

        // Draw labels (billboards)
        encodeLabels(encoder: encoder)

        encoder.endEncoding()

        commandBuffer.present(drawable)

        // Signal semaphore when GPU finishes this frame
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.frameSemaphore.signal()
        }

        commandBuffer.commit()
    }
}
```

**Confidence:** HIGH -- Triple buffering is Apple's recommended pattern from the Metal Best Practices Guide. The semaphore pattern is documented at developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html. Metal by Example uses this exact structure.

### Pattern 3: Instanced Aircraft Rendering

**What:** All aircraft of the same category share a single vertex buffer (geometry). Per-aircraft data (position, rotation, color, scale) is stored in a per-instance buffer. A single `drawIndexedPrimitives(instanceCount:)` call renders all aircraft of one category. This replaces the web version's approach of individual THREE.Group objects per aircraft.

**When:** Always for aircraft rendering. This is the core performance advantage over the web version.

**Example (ShaderTypes.h):**

```c
// ShaderTypes.h - shared between Swift and Metal
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Buffer indices matching setVertexBuffer atIndex:
typedef enum {
    BufferIndexVertices       = 0,
    BufferIndexUniforms       = 1,
    BufferIndexInstances      = 2,
} BufferIndex;

// Shared camera/projection uniforms (per-frame)
typedef struct {
    matrix_float4x4 viewMatrix;
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewProjectionMatrix;
    simd_float3     cameraPosition;
    float           time;
} Uniforms;

// Per-instance aircraft data
typedef struct {
    matrix_float4x4 modelMatrix;
    simd_float4     color;          // altitude-based color + alpha
    float           scale;          // LOD-based scale factor
    float           lightPhase;     // position light animation phase
    uint32_t        flags;          // bit flags: selected, highlighted, etc.
} AircraftInstanceData;

// Vertex input
typedef struct {
    simd_float3 position;
    simd_float3 normal;
} VertexIn;

#endif
```

**Example (AircraftShaders.metal):**

```metal
// AircraftShaders.metal
#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPosition;
    float4 color;
    float  lightPhase;
    uint   flags;
};

vertex VertexOut aircraft_vertex(
    const device VertexIn* vertices [[buffer(BufferIndexVertices)]],
    constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
    const device AircraftInstanceData* instances [[buffer(BufferIndexInstances)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]])
{
    VertexIn vert = vertices[vertexID];
    AircraftInstanceData inst = instances[instanceID];

    float4 worldPos = inst.modelMatrix * float4(vert.position * inst.scale, 1.0);
    float3 worldNormal = (inst.modelMatrix * float4(vert.normal, 0.0)).xyz;

    VertexOut out;
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.worldNormal = normalize(worldNormal);
    out.worldPosition = worldPos.xyz;
    out.color = inst.color;
    out.lightPhase = inst.lightPhase;
    out.flags = inst.flags;
    return out;
}

fragment float4 aircraft_fragment(VertexOut in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]])
{
    // Simple directional lighting
    float3 lightDir = normalize(float3(0.5, 1.0, 0.5));
    float diffuse = max(dot(in.worldNormal, lightDir), 0.0);
    float ambient = 0.3;
    float lighting = ambient + diffuse * 0.7;

    float3 litColor = in.color.rgb * lighting;

    // Position light blinking
    float blink = step(0.7, sin(in.lightPhase));
    litColor += float3(1.0, 0.0, 0.0) * blink * 0.3;

    // Selection highlight
    if (in.flags & 1u) {
        litColor = mix(litColor, float3(1.0, 0.8, 0.0), 0.3);
    }

    return float4(litColor, in.color.a);
}
```

**Confidence:** HIGH -- Metal instanced rendering with `instance_id` is documented by Apple and demonstrated extensively in Metal by Example's "Instanced Rendering" article. The per-instance buffer pattern with `drawIndexedPrimitives(instanceCount:)` is the standard approach.

### Pattern 4: Actor-Based Data Polling with AsyncStream

**What:** The `FlightDataActor` uses Swift's actor isolation to safely manage polling state. It produces an `AsyncStream<[AircraftModel]>` that the AppState consumes. The polling loop handles fallback between API providers, respects rate limits, and supports cancellation.

**When:** Always for data fetching. Replaces the web version's `setInterval(fetchData, 1000)`.

**Example:**

```swift
// FlightDataActor.swift
actor FlightDataActor {
    enum Provider: CaseIterable {
        case local
        case airplanesLive
        case adsbLol
        case openSky
    }

    private let networkClient: NetworkClient
    private var currentProvider: Provider = .local
    private var providerFailCounts: [Provider: Int] = [:]

    init(networkClient: NetworkClient = NetworkClient()) {
        self.networkClient = networkClient
    }

    func pollingStream(
        mode: DataSourceMode,
        center: (lat: Double, lon: Double),
        interval: TimeInterval
    ) -> AsyncStream<[AircraftModel]> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        let aircraft = try await fetchWithFallback(mode: mode, center: center)
                        continuation.yield(aircraft)
                    } catch {
                        // Yield empty on total failure, don't stop the stream
                        continuation.yield([])
                    }
                    try await Task.sleep(for: .seconds(interval))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func fetchWithFallback(
        mode: DataSourceMode,
        center: (lat: Double, lon: Double)
    ) async throws -> [AircraftModel] {
        let providers: [Provider] = mode == .local
            ? [.local]
            : [.airplanesLive, .adsbLol, .openSky]

        for provider in providers {
            do {
                let raw = try await fetchFromProvider(provider, center: center)
                providerFailCounts[provider] = 0
                return DataNormalizer.normalize(raw, from: provider)
            } catch {
                providerFailCounts[provider, default: 0] += 1
                continue
            }
        }
        throw FlightDataError.allProvidersFailed
    }
}
```

**Confidence:** HIGH -- Swift actors and AsyncStream are stable APIs since Swift 5.5/5.9. The polling-with-AsyncStream pattern is documented in Apple's WWDC sessions and widely used in production apps. Actor isolation eliminates the data races that the web version's global mutable state is susceptible to.

### Pattern 5: @Observable AppState as Single Source of Truth

**What:** A single `AppState` class annotated with `@Observable` (Swift 5.9+ Observation framework) serves as the bridge between all layers. SwiftUI views read from it reactively. The Renderer reads from it each frame. Data layer actors write to it via `@MainActor` methods.

**When:** Always. This replaces the web version's global variables (`airplanes`, `selectedPlane`, `currentTheme`, etc.).

**Example:**

```swift
// AppState.swift
import Observation
import simd

@Observable
@MainActor
final class AppState {
    // Aircraft state
    var aircraftList: [AircraftModel] = []
    var selectedAircraft: AircraftModel?
    var aircraftTrails: [String: [TrailPoint]] = [:]  // hex -> trail points

    // Data source
    var dataSourceMode: DataSourceMode = .local
    var connectionStatus: ConnectionStatus = .disconnected
    var activeProvider: String = ""

    // Camera
    var cameraAngle: Float = 0
    var cameraPitch: Float = 0.5
    var cameraDistance: Float = 200
    var centerLatLon: (lat: Double, lon: Double) = (40.7128, -74.0060)

    // Display settings
    var settings: AppSettings = AppSettings()

    // Map state
    var mapZoom: Int = 10
    var mapBounds: MapBounds?

    // Search
    var airportSearchResults: [AirportModel] = []

    // Stats
    var messageRate: Double = 0
    var aircraftCount: Int = 0
    var signalLevel: Double = 0

    // Derived properties that Metal renderer needs
    var viewMatrix: matrix_float4x4 {
        camera.viewMatrix(
            angle: cameraAngle, pitch: cameraPitch,
            distance: cameraDistance, target: centerWorldPosition
        )
    }

    var centerWorldPosition: simd_float3 {
        guard let bounds = mapBounds else { return .zero }
        let pos = CoordinateSystem.latLonToXZ(
            lat: centerLatLon.lat, lon: centerLatLon.lon, bounds: bounds
        )
        return simd_float3(pos.x, 0, pos.z)
    }

    // Methods called by data layer actors
    func updateAircraft(_ aircraft: [AircraftModel]) {
        self.aircraftList = aircraft
        self.aircraftCount = aircraft.count
    }

    func selectAircraft(hex: String) {
        self.selectedAircraft = aircraftList.first { $0.hex == hex }
    }
}
```

**Confidence:** HIGH -- The @Observable macro is the current recommended approach over ObservableObject (Apple WWDC23 "Discover Observation in SwiftUI"). Using @MainActor on the class ensures all property mutations happen on the main thread, which is required for SwiftUI updates and safe for Metal renderer reads in the draw callback (which also runs on the main thread via MTKView's default configuration).

## Metal Rendering Pipeline Detail

### Pipeline State Architecture

Create all pipeline states once at initialization. Never create pipeline states during rendering.

```
Renderer.init()
  |
  +-- buildAircraftPipeline()
  |     Vertex: aircraft_vertex (instanced, per-instance modelMatrix + color)
  |     Fragment: aircraft_fragment (diffuse lighting, position light blink, selection highlight)
  |     Vertex descriptor: position (float3) + normal (float3)
  |     Instance step: perInstance for buffer index 2
  |
  +-- buildMapTilePipeline()
  |     Vertex: map_tile_vertex (textured quad, position from tile grid)
  |     Fragment: map_tile_fragment (texture sampling with theme tinting)
  |     Vertex descriptor: position (float3) + texcoord (float2)
  |
  +-- buildTrailPipeline()
  |     Vertex: trail_vertex (line strip with per-vertex color)
  |     Fragment: trail_fragment (vertex color passthrough with alpha fade)
  |     Vertex descriptor: position (float3) + color (float4)
  |     Blend: src alpha + (1 - src alpha)
  |
  +-- buildLabelPipeline()
  |     Vertex: label_vertex (billboard quad, always faces camera)
  |     Fragment: label_fragment (texture sampling with alpha test)
  |     Vertex descriptor: position (float3) + texcoord (float2)
  |     Blend: src alpha + (1 - src alpha)
  |
  +-- buildDepthStencilState()
        Compare: less, write enabled (aircraft, tiles)
        Compare: less, write disabled (trails, labels -- transparent)
```

### Single Render Pass Encoding Order

Use a single render pass with careful draw ordering. Do NOT use multiple render passes (unnecessary for this app, wastes bandwidth on tile-based GPU).

```
draw(in view:)
  |
  +-- encoder.setDepthStencilState(opaqueDepthState)
  |
  +-- 1. Map tiles (opaque, ground plane)
  |     encoder.setRenderPipelineState(mapTilePipeline)
  |     For each visible tile:
  |       encoder.setVertexBuffer(tileQuadVertices)
  |       encoder.setFragmentTexture(tileTexture)
  |       encoder.drawPrimitives(.triangle, vertexCount: 6)
  |
  +-- 2. Aircraft (opaque, instanced)
  |     encoder.setRenderPipelineState(aircraftPipeline)
  |     For each aircraft category (jet, widebody, helicopter, small, military):
  |       encoder.setVertexBuffer(categoryMeshVertices, index: 0)
  |       encoder.setVertexBuffer(uniformBuffer, index: 1)
  |       encoder.setVertexBuffer(instanceBuffer, offset: categoryOffset, index: 2)
  |       encoder.drawIndexedPrimitives(.triangle, indexCount, instanceCount: categoryCount)
  |
  +-- encoder.setDepthStencilState(transparentDepthState)  // write disabled
  |
  +-- 3. Altitude lines (transparent, thin lines)
  |     encoder.setRenderPipelineState(trailPipeline)  // reuse trail pipeline
  |     For each aircraft with altitude line:
  |       encoder.drawPrimitives(.line, vertexCount: 2)
  |
  +-- 4. Trails (transparent, per-aircraft line strips)
  |     encoder.setRenderPipelineState(trailPipeline)
  |     For each aircraft with trail:
  |       encoder.setVertexBuffer(trailVertexBuffer)
  |       encoder.drawPrimitives(.lineStrip, vertexCount: trailPointCount)
  |
  +-- 5. Labels (transparent, billboard quads)
  |     encoder.setRenderPipelineState(labelPipeline)
  |     For each visible label:
  |       encoder.setFragmentTexture(labelTexture)
  |       encoder.drawPrimitives(.triangle, vertexCount: 6)
  |
  +-- encoder.endEncoding()
```

**Draw order rationale:** Opaque geometry first (tiles, aircraft) with depth writes. Then transparent geometry (altitude lines, trails, labels) with depth writes disabled, sorted back-to-front. This matches the web version's renderOrder approach but uses Metal's depth stencil state switching instead.

### Shader File Organization

Split shaders by rendering domain, not by shader stage. Each .metal file contains both the vertex and fragment functions for one render pass, plus any helper functions specific to that pass. Shared utilities go in CommonShaders.metal.

```
Shaders/
  ShaderTypes.h              # Struct definitions shared between Swift and MSL
  CommonShaders.metal         # Shared: lighting functions, color utilities, coordinate transforms
  AircraftShaders.metal       # aircraft_vertex + aircraft_fragment (instanced rendering)
  MapTileShaders.metal        # map_tile_vertex + map_tile_fragment (textured quads)
  TrailShaders.metal          # trail_vertex + trail_fragment (colored line strips)
  LabelShaders.metal          # label_vertex + label_fragment (billboard text sprites)
```

**Why not one big Shaders.metal?** The web version puts everything in one file because it must. The native version should not. Separate files enable:
- Faster iteration (change one shader, only that file recompiles)
- Clear ownership (each rendering subsystem owns its shaders)
- Easier debugging (Metal shader debugger shows file names)

**Why not vertex.metal and fragment.metal?** Splitting by shader stage is an anti-pattern. A vertex function and its corresponding fragment function are tightly coupled (they share VertexOut struct). Putting them in the same file keeps the interface visible.

All .metal files in the main target are automatically compiled by Xcode into `default.metallib`, which is accessible via `device.makeDefaultLibrary()`. No manual compilation needed.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Wrapping the Web App in WKWebView

**What:** Embedding the existing HTML/JS in a WKWebView for quick porting.
**Why bad:** Defeats the purpose of native performance. WKWebView is sandboxed, has WebGL (not Metal) overhead, cannot access Metal APIs, and the app would not be ARM-optimized. Performance would be identical to or worse than Safari.
**Instead:** Full native rewrite with Metal rendering. Port the domain logic (coordinate math, interpolation, data normalization), not the rendering code.

### Anti-Pattern 2: Using SceneKit Instead of Metal

**What:** Using SceneKit's scene graph (SCNScene, SCNNode, SCNGeometry) for easier porting from THREE.js.
**Why bad:** SceneKit adds abstraction overhead that prevents the instanced rendering optimization critical for 200+ aircraft at 60fps. SceneKit's node-per-object model has the same draw call problem as THREE.js Groups. SceneKit's material system is less flexible than custom Metal shaders for the altitude color coding, wireframe retro theme, and position light animations this app needs.
**Instead:** Direct Metal rendering with instanced draw calls. One draw call per aircraft category (6 categories) replaces 200+ individual draw calls. The performance difference on Apple Silicon is dramatic.

### Anti-Pattern 3: Creating MTLRenderPipelineState per Frame

**What:** Building pipeline states inside `draw(in:)` instead of at initialization.
**Why bad:** Pipeline state creation involves shader compilation and is expensive (milliseconds). Doing it per frame at 60fps would cause catastrophic stuttering.
**Instead:** Create all pipeline states in `Renderer.init()`. If you need variant pipelines (e.g., wireframe for retro theme), create all variants upfront and switch between pre-built states.

### Anti-Pattern 4: Putting Metal State in SwiftUI Views

**What:** Holding MTLBuffer, MTLTexture, or MTLRenderPipelineState references in SwiftUI View structs or their view models.
**Why bad:** SwiftUI views are value types that get recreated frequently. Metal resources are reference-counted GPU objects that should have stable lifetimes. Mixing them causes unnecessary resource churn and potential use-after-free.
**Instead:** All Metal state lives in the Renderer class. SwiftUI communicates with the renderer exclusively through AppState (an @Observable class).

### Anti-Pattern 5: Blocking the Main Thread with Data Fetching

**What:** Performing network requests synchronously or processing large CSV files on the main thread.
**Why bad:** The main thread runs both the SwiftUI update cycle and the MTKView draw callback. Blocking it freezes both the UI and rendering.
**Instead:** All network I/O happens in actors using async/await. The OurAirports CSV (12.5MB) is loaded and parsed in the `AirportDataActor` on a background thread. Results are published to AppState via `@MainActor` methods.

### Anti-Pattern 6: One Draw Call per Aircraft

**What:** Encoding separate `drawPrimitives` for each individual aircraft, mirroring the web version's per-object THREE.Group approach.
**Why bad:** Draw call overhead is the primary bottleneck in Metal rendering. With 200 aircraft and 6 mesh parts each, this would be 1,200 draw calls per frame. On Apple Silicon's TBDR architecture, the overhead compounds.
**Instead:** Instanced rendering. Group aircraft by category (helicopter, small, jet, widebody, military, regional). Each category uses a single `drawIndexedPrimitives(instanceCount:)` call. 200 aircraft across 6 categories = 6 draw calls instead of 1,200.

## Scalability Considerations

| Concern | At 100 aircraft | At 500 aircraft | At 2,000 aircraft |
|---------|-----------------|------------------|--------------------|
| **Draw calls** | 6 instanced calls (trivial) | 6 instanced calls (trivial) | 6 instanced calls (trivial) |
| **Instance buffer** | ~10 KB (100 * 96 bytes) | ~48 KB | ~192 KB |
| **Trail memory** | ~1.2 MB (100 trails * 200 points * 60 bytes) | ~6 MB | ~24 MB (may need to cap trail length) |
| **Label textures** | 100 * 256x64 textures = ~6.4 MB | 500 textures = ~32 MB (need atlas) | Atlas required, LOD culling aggressive |
| **CPU interpolation** | Negligible | ~0.5ms per frame | ~2ms per frame (may need SIMD batch) |
| **Data polling** | One API call, ~20 KB response | One API call, ~100 KB response | Multiple API calls or WebSocket needed |

### Scaling Strategy

1. **Instance buffers scale linearly** and are trivially small. Even 10,000 aircraft would only be ~1 MB of instance data. This is the key advantage of the Metal rewrite over the web version.

2. **Trail memory is the first bottleneck.** Each trail point needs position (12 bytes) + color (16 bytes) = 28 bytes minimum. At 200 points per trail and 500 aircraft, that is 2.8 MB of vertex data uploaded per frame. Solution: use a ring buffer for trail data, overwriting old points instead of reallocating.

3. **Label textures need an atlas at scale.** Creating individual Metal textures per aircraft label is wasteful. At 200+ aircraft, use a texture atlas: render all labels into a single large texture (e.g., 2048x2048), with each label occupying a region. The label shader uses UV offsets to sample the correct region.

4. **CPU interpolation should use SIMD.** The interpolation math (lerp position, slerp rotation) for 500+ aircraft can be vectorized using Swift's SIMD types (simd_float3, simd_quatf). At 2,000 aircraft, consider moving interpolation to a Metal compute shader.

## Integration Points

### SwiftUI <-> Metal Renderer

| Integration | Mechanism | Direction |
|-------------|-----------|-----------|
| Aircraft data to GPU | AppState.aircraftList read in Renderer.draw() | AppState -> Renderer |
| Camera controls | AppState.cameraAngle/pitch/distance mutated by SwiftUI sliders and MTKView gestures | Both directions |
| Selection | Mouse click -> Renderer.hitTest() -> AppState.selectedAircraft -> SwiftUI detail panel | Renderer -> AppState -> SwiftUI |
| Theme changes | AppState.settings.theme changed by SwiftUI -> Renderer recreates materials/colors | SwiftUI -> AppState -> Renderer |
| Settings | SwiftUI controls mutate AppState.settings -> Renderer reads per frame | SwiftUI -> AppState -> Renderer |
| FPS display | Renderer calculates FPS -> AppState.fps (or direct) -> SwiftUI StatusBar | Renderer -> SwiftUI |

### Data Layer <-> AppState

| Integration | Mechanism | Direction |
|-------------|-----------|-----------|
| Flight data updates | FlightDataActor.pollingStream -> Task consuming stream -> AppState.updateAircraft() | Actor -> @MainActor |
| Enrichment data | EnrichmentActor.enrich(hex:) -> AppState.enrichAircraft() | Actor -> @MainActor |
| Airport search | User types -> AirportDataActor.search(query:) -> AppState.airportSearchResults | SwiftUI -> Actor -> @MainActor |
| Settings persistence | AppState.settings didSet -> SettingsStore.save() | @MainActor -> sync |
| Connection status | FlightDataActor reports provider status -> AppState.connectionStatus | Actor -> @MainActor |

### New Components (not in web version)

| Component | Why New | Web Equivalent |
|-----------|---------|----------------|
| MetalView (NSViewRepresentable) | Required to host MTKView in SwiftUI | None (DOM container) |
| Renderer (MTKViewDelegate) | Metal rendering loop replaces THREE.js renderer | `animate()` + `renderer.render()` |
| ShaderTypes.h (bridging header) | Shares struct definitions between Swift and MSL | None (JS has no shader types) |
| .metal shader files (4-5 files) | GPU programs replace THREE.js materials | Implicit in THREE.js materials |
| FlightDataActor | Thread-safe data polling replaces `setInterval(fetchData)` | `fetchData()` + `setInterval` |
| AircraftInterpolator | Explicit interpolation module replaces inline code | `interpolateAircraft()` (inline in animate) |
| OrbitCamera | Camera math extracted into dedicated type | Camera variables + `updateCameraPosition()` |
| TextureCache | LRU cache for map tile and label textures | `tileCache` Map |
| AppState (@Observable) | Single source of truth replaces global variables | ~50 global variables |

### Components Preserved (logic ported, not code)

| Domain Logic | Web Implementation | Native Implementation |
|--------------|-------------------|----------------------|
| Coordinate transform | `latLonToXZ()` | `CoordinateSystem.latLonToXZ()` (same math, Swift struct) |
| Altitude color mapping | `getAltitudeColor()` | `ColorUtilities.altitudeColor()` (same logic) |
| Aircraft categorization | `getAircraftCategory()` | `AircraftCategory.from(data:)` (same rules) |
| Data normalization | Inline in `fetchData()` | `DataNormalizer.normalize()` (extracted) |
| Haversine distance | `haversine()` | `MathUtilities.haversine()` (same formula) |
| Trail point collection | Inline in `interpolateAircraft()` | `TrailRenderer.addPoint()` (extracted) |

## Build Order (Dependency Analysis)

Components have clear dependency ordering. This is the recommended implementation sequence:

```
Phase 1: Metal Foundation (Window + Rendering Surface)
    |
    +--- Xcode project setup, MetalView, Renderer skeleton, empty draw loop
    |    ShaderTypes.h, first .metal file (clear color only)
    |    AppState skeleton, ContentView with MetalView
    |    RESULT: App window with colored Metal surface
    |
Phase 2: Camera + Ground Plane
    |
    +--- OrbitCamera, CoordinateSystem, projection/view matrices
    |    Map tile pipeline: textured quads on ground plane
    |    MapTileManager: tile URL generation, async texture loading
    |    Mouse/keyboard input handling on MTKView
    |    RESULT: Pannable, zoomable map on Metal ground plane
    |
Phase 3: Data Pipeline + Aircraft Rendering
    |
    +--- FlightDataActor, DataNormalizer, NetworkClient
    |    AircraftModel, AircraftCategory
    |    Aircraft mesh geometry (vertex buffers for each category)
    |    AircraftShaders.metal (instanced rendering)
    |    Per-instance buffer management
    |    AircraftInterpolator (smooth movement between updates)
    |    RESULT: Aircraft appearing and moving on the map
    |
Phase 4: Trails + Labels + Selection
    |
    +--- TrailRenderer + TrailShaders.metal
    |    LabelRenderer + LabelShaders.metal (Core Text -> texture)
    |    Hit testing (ray-cast for aircraft selection)
    |    SelectedPlaneView (SwiftUI detail panel)
    |    EnrichmentActor (hexdb.io lookups)
    |    RESULT: Full interactive flight visualization
    |
Phase 5: UI Controls + Settings
    |
    +--- InfoPanelView, ControlsView (theme, units, altitude scale)
    |    SettingsStore (UserDefaults persistence)
    |    Keyboard shortcuts
    |    Theme switching (day/night/retro shader variants)
    |    RESULT: Feature-complete core app
```

**Phase ordering rationale:**
- **Phase 1 first** because everything depends on having a Metal rendering surface. Cannot test any rendering without this foundation. This is the "hello Metal" phase.
- **Phase 2 second** because the camera and map tiles establish the coordinate system and visual frame that everything else is positioned within. Aircraft positions are meaningless without a map reference.
- **Phase 3 third** because aircraft are the core value proposition. This phase connects the data pipeline to rendering and proves the instanced rendering architecture works. This is the most architecturally significant phase.
- **Phase 4 fourth** because trails, labels, and selection add polish to the aircraft rendering established in Phase 3. These features depend on having working aircraft to attach to.
- **Phase 5 last** because UI controls and settings are the final layer on top of a working visualization. The app is usable (if not configurable) without this phase.

**Each phase is independently verifiable:** After each phase, the app is runnable and demonstrates the capability added. This allows catching architectural mistakes early.

## Sources

**Metal Rendering Architecture:**
- [Writing a Modern Metal App from Scratch (Metal by Example)](https://metalbyexample.com/modern-metal-1/) -- Renderer class structure, MTKViewDelegate pattern, pipeline state creation (HIGH confidence)
- [Metal by Example: Instanced Rendering](https://metalbyexample.com/instanced-rendering/) -- Per-instance buffer pattern, vertex descriptor step function, instance_id in shaders (HIGH confidence)
- [Apple Metal Best Practices: Triple Buffering](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html) -- Semaphore synchronization, ring buffer pattern, completion handler (HIGH confidence)
- [Apple MTKView Documentation](https://developer.apple.com/documentation/metalkit/mtkview) -- NSView subclass, delegate protocol, frame rate control (HIGH confidence)
- [Metal Render Passes (Kodeco)](https://www.kodeco.com/books/metal-by-tutorials/v3.0/chapters/12-render-passes) -- Render pass descriptor setup, load/store actions, multi-pass encoding (HIGH confidence)
- [Optimize GPU Renderers with Metal (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10127/) -- Function constants, async pipeline creation, occupancy optimization (HIGH confidence)
- [Discover Metal 4 (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/205/) -- Unified command encoder, Apple Silicon optimizations (MEDIUM confidence -- Metal 4 is new, may not be needed for v2.0)

**SwiftUI + Metal Integration:**
- [Swift x Metal for 3D Graphics Rendering (Medium)](https://carlosmbe.medium.com/swift-x-metal-for-3d-graphics-rendering-part-1-setting-up-in-swiftui-d2e90d6e5ec3) -- NSViewRepresentable wrapping MTKView, Coordinator as MTKViewDelegate (MEDIUM confidence)
- [MetalKit in SwiftUI (Apple Developer Forums)](https://developer.apple.com/forums/thread/119112) -- Official guidance on SwiftUI + MTKView (HIGH confidence)
- [NSView Keyboard and Mouse Input (GitHub)](https://github.com/twohyjr/NSView-Keyboard-and-Mouse-Input) -- MTKView subclass for input handling on macOS (MEDIUM confidence)

**SwiftUI Architecture:**
- [Apple: Discover Observation in SwiftUI (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10149/) -- @Observable macro, replaces ObservableObject (HIGH confidence)
- [Apple: Migrating to @Observable](https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro) -- Migration guide, property tracking (HIGH confidence)
- [@Observable Macro Performance (SwiftLee)](https://www.avanderlee.com/swiftui/observable-macro-performance-increase-observableobject/) -- Per-property tracking reduces redraws (MEDIUM confidence)

**Swift Concurrency:**
- [AsyncSequence for Real-Time APIs (Medium)](https://medium.com/@wesleymatlock/asyncsequence-for-real-time-apis-from-legacy-polling-to-swift-6-elegance-c2b8139c21e0) -- AsyncStream polling pattern, cancellation handling (MEDIUM confidence)
- [Swift Concurrency Deep Dive: Actors (Medium)](https://medium.com/@dhrumilraval212/swift-concurrency-deep-dive-beyond-async-await-architecting-concurrent-systems-with-actors-and-0bc46f0bbb74) -- Actor isolation for shared state, Sendable protocol (MEDIUM confidence)
- [URLSession with Async/Await (Apple WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10095/) -- Native async URLSession API (HIGH confidence)

**Shader Organization:**
- [Apple Developer Forums: Swift Package with Metal](https://developer.apple.com/forums/thread/649579) -- Why .metal files should be in main target, not SPM packages (HIGH confidence)
- [Apple Developer Forums: Defining structs in .h for Swift and Metal](https://forums.developer.apple.com/thread/115086) -- ShaderTypes.h bridging header pattern (HIGH confidence)
- [Metal Shaders Course: Shader Library Organization](https://www.metal.graphics/appendix-b-shader-library-organization) -- File organization best practices (MEDIUM confidence)

**Existing Codebase:**
- `/Users/mit/Documents/GitHub/airplane-tracker-3d/airplane-tracker-3d-map.html` -- Web version source (5,735 lines), analyzed for domain logic extraction and feature reference (HIGH confidence)

---
*Architecture research for: Native macOS Metal flight tracker (rewrite from THREE.js web app)*
*Researched: 2026-02-08*
