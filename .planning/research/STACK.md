# Technology Stack: Native macOS Metal App

**Project:** Airplane Tracker 3D -- v2.0 Native macOS App
**Researched:** 2026-02-08
**Confidence:** HIGH (verified against current Xcode 26.2 / macOS 26 Tahoe / Swift 6.2 ecosystem)

---

## Recommended Stack

### Development Environment

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Xcode** | 26.2 (current stable) | IDE, build system, Metal shader compiler, GPU debugger | Only option for native macOS Metal development. Ships with Metal GPU debugger, shader profiler, and Instruments GPU trace. Xcode 26.2 includes macOS 26.2 SDK and Swift 6.2.3. |
| **Swift** | 6.2 (ships with Xcode 26.2) | Application language | Native Metal/SwiftUI integration. Swift 6.2 adds `@MainActor` module-level defaults (simplifies UI thread safety), `@concurrent` attribute for background work, and InlineArray for fixed-size buffer-compatible arrays. Strict concurrency checking catches data races at compile time. |
| **macOS Deployment Target** | macOS 13 Ventura (minimum) | Minimum supported OS | Per PROJECT.md constraint. Metal 3 support begins at macOS 13. Ventura supports Apple Silicon M1+ and late Intel Macs. SwiftUI `@Observable` requires macOS 14+, so if using `@Observable` (recommended), minimum becomes macOS 14 Sonoma. |

**Recommended deployment target: macOS 14 Sonoma.** This enables `@Observable` macro (eliminates boilerplate ObservableObject/Published patterns), SwiftUI improvements for settings windows, and Metal 3 mesh shader support. macOS 13 Ventura drops out of Apple security updates in late 2025, making macOS 14 a pragmatic floor.

### 3D Rendering: Metal + MetalKit

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Metal** | Metal 3 API | GPU rendering pipeline, shaders, compute | Direct GPU control for real-time aircraft rendering. Metal 3 (not Metal 4) because: Metal 4 requires macOS 26+ and Xcode 26+ with entirely new `MTL4`-prefixed API types, mandatory function descriptors, and explicit argument tables -- a ground-up API redesign that is bleeding-edge. Metal 3 is mature, well-documented, backward-compatible to macOS 13, and more than sufficient for this use case. Metal 4 can be adopted in a future milestone when its API stabilizes. |
| **MetalKit** | Current (bundled with SDK) | MTKView, MTKTextureLoader, MTKMesh | Provides `MTKView` (the Metal-backed view for rendering), `MTKTextureLoader` (async texture loading for map tiles), and `MTKMesh` (Model I/O integration). MTKView handles drawable management, display link timing, and depth/stencil buffer creation automatically. |
| **Metal Shading Language (MSL)** | MSL 3.1 (Metal 3) | Vertex, fragment, and compute shaders | C++14-derived language for GPU programs. Write vertex shaders for aircraft transforms, fragment shaders for lighting/coloring, and compute shaders for interpolation. MSL 3.1 provides `instance_id` for instanced rendering, `texture2d` sampling for map tiles, and `float4x4` matrix types matching Swift's `simd_float4x4`. |
| **Metal Performance Shaders (MPS)** | Current | Optional: image processing, matrix ops | Not needed initially. Available if future features require GPU-accelerated image processing (e.g., terrain heightmap filtering) or matrix operations. |

**Why Metal 3, not Metal 4:**
- Metal 4 (announced WWDC 2025) requires macOS 26 Tahoe minimum, uses entirely new `MTL4`-prefixed types (`MTL4RenderPipelineDescriptor`, `MTL4CommandBuffer`, `MTL4Compiler`), mandatory function descriptors, explicit argument tables, and command allocators. It is a ground-up API redesign, not an incremental upgrade.
- Metal 3 is battle-tested (since macOS 13, 2022), has extensive documentation and tutorials, backward-compatible, and provides everything this app needs: instanced rendering, mesh shaders, indirect command buffers, MetalFX upscaling.
- Metal 4 adoption makes sense in a later milestone after the API matures and documentation catches up.

**Why not SceneKit:**
SceneKit is Apple's high-level 3D framework built on Metal. It abstracts away GPU control, which sounds convenient but creates problems: no control over draw call batching (critical for hundreds of aircraft), no instanced rendering API, no custom render passes, no compute shader integration. SceneKit is designed for casual 3D scenes, not real-time data visualization with custom rendering requirements. Metal gives direct control over every GPU operation.

### UI Framework: SwiftUI

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **SwiftUI** | macOS 14+ (Observation framework) | UI controls, panels, settings, window management | Declarative UI for aircraft detail panels, settings sidebar, data source controls, statistics. SwiftUI handles layout, theming, and window management. Metal rendering lives in a wrapped `MTKView` -- SwiftUI manages everything around it. |
| **AppKit** | Current (macOS SDK) | MTKView host via NSViewRepresentable, menu bar, dock integration | AppKit provides `NSViewRepresentable` to bridge `MTKView` into SwiftUI. Also used for native macOS features: menu bar items, dock badge (aircraft count), keyboard shortcuts via `.keyboardShortcut()`, and any edge cases where SwiftUI lacks macOS-specific APIs. |
| **Observation framework** | macOS 14+ (Swift 5.9+) | `@Observable` macro for state management | Replaces legacy `ObservableObject` + `@Published`. `@Observable` provides fine-grained property tracking -- SwiftUI only re-renders views that read changed properties, not all properties on the object. Critical for performance when flight data updates at 1Hz with hundreds of aircraft. |

**SwiftUI + Metal integration pattern:**

```
SwiftUI View Hierarchy
  |
  +-- ContentView (SwiftUI)
  |     +-- MetalView (NSViewRepresentable wrapping MTKView)
  |     |     +-- Coordinator (MTKViewDelegate) --> Renderer
  |     +-- SidebarView (SwiftUI: aircraft list, search, settings)
  |     +-- DetailPanelView (SwiftUI: selected aircraft info)
  |     +-- ToolbarView (SwiftUI: data source, theme, controls)
```

The `NSViewRepresentable` bridge is the critical integration point. The Coordinator class conforms to `MTKViewDelegate`, receives `draw(in:)` callbacks each frame, and delegates to a `Renderer` class that owns all Metal state. SwiftUI views communicate with the renderer through shared `@Observable` state objects.

### Networking: URLSession + Swift Concurrency

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **URLSession** | Current (Foundation) | HTTP requests to ADS-B APIs, tile fetching | Built into Foundation. Async/await API since Swift 5.5. No third-party networking library needed. Handles HTTP/2, connection pooling, caching, and background transfers natively. |
| **Swift Concurrency** | Swift 6.2 | async/await, actors, structured concurrency | `async let` for parallel API requests (e.g., fetch aircraft + enrichment simultaneously). `Actor` isolation for thread-safe flight data management. `TaskGroup` for parallel tile loading. `AsyncStream` for continuous polling. Compile-time data race checking with Swift 6 strict concurrency. |
| **JSONDecoder / Codable** | Current (Foundation) | JSON parsing for ADS-B API responses | Type-safe JSON parsing with zero dependencies. Define `Codable` structs matching API response shapes. `JSONDecoder` with `.keyDecodingStrategy = .convertFromSnakeCase` handles API field naming. Errors are caught at compile time via type mismatches. |

**Networking architecture:**

```swift
// Actor-isolated flight data manager
@Observable
final class FlightDataManager {
    private(set) var aircraft: [String: Aircraft] = [:]

    func poll() async throws {
        let data = try await URLSession.shared.data(from: apiURL)
        let response = try JSONDecoder().decode(ADSBResponse.self, from: data.0)
        // Update aircraft dictionary on MainActor
    }
}
```

**Why not Alamofire / Moya / other networking libraries:**
URLSession with async/await is sufficient. The app makes simple GET requests to REST APIs returning JSON. No OAuth, no complex multipart uploads, no GraphQL. Adding a dependency adds binary size, maintenance burden, and potential version conflicts for zero benefit.

### Math & Linear Algebra: simd + Accelerate

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **simd** (Swift module) | Current (built-in) | Vector/matrix math for 3D transforms | `simd_float4x4` for model/view/projection matrices. `simd_float3` for positions/normals. `simd_quatf` for rotations. These types are directly compatible with Metal shader `float4x4` and `float3` types -- zero conversion overhead. Hardware-accelerated on Apple Silicon via NEON instructions. |
| **Accelerate** | Current (framework) | Optional: batch math, FFT, image processing | Available for bulk operations like batch coordinate transforms (lat/lon to 3D position for hundreds of aircraft). Not needed initially but useful for terrain heightmap processing. |

**simd is the correct choice** over manual matrix math or GLKit (deprecated). The simd types are:
- Identical memory layout to MSL types (pass directly to GPU via MTLBuffer)
- Hardware-accelerated on Apple Silicon ARM via 128-bit NEON vector units
- Built into Swift standard library (no import needed beyond `import simd`)
- Provide all needed operations: matrix multiply, inverse, transpose, perspective/ortho projection, look-at

**Common transforms needed:**

```swift
import simd

// Projection matrix
let projection = simd_float4x4.perspectiveProjection(
    fovY: .pi / 4, aspectRatio: aspect, near: 0.1, far: 1000
)

// View matrix (camera)
let view = simd_float4x4.lookAt(eye: cameraPos, center: target, up: .init(0, 1, 0))

// Model matrix (per aircraft)
let model = simd_float4x4.translation(position) * simd_float4x4.rotationY(heading)
```

Note: simd does not include convenience constructors like `perspectiveProjection` or `lookAt` -- these must be written as extensions (approximately 50 lines of code, well-documented patterns).

### Data Persistence: UserDefaults + File System

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **UserDefaults** | Current (Foundation) | Settings persistence (theme, data source, camera position) | Simple key-value storage for app settings. Replaces cookies from web version. Automatically syncs to disk. Supports all basic types + Codable via PropertyListEncoder. |
| **FileManager + Codable** | Current (Foundation) | Cached data (airport database, airspace boundaries) | Store parsed airport CSV and airspace GeoJSON as Codable-encoded files in Application Support directory. Faster than re-downloading and re-parsing on every launch. |

**Why not Core Data / SwiftData / SQLite:**
The app stores settings (tiny) and cached reference data (airport list, airspace). No relationships, no queries beyond key lookup, no concurrent writes. UserDefaults + JSON files in Application Support is the simplest correct solution. SwiftData would add complexity for no benefit. If trail history persistence is needed later, SQLite (via swift-sqlite or GRDB) is the right upgrade path -- not Core Data.

### Shared Types: Bridging Header (ShaderTypes.h)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| **Objective-C Bridging Header** | N/A | Share struct definitions between Swift and MSL | A `.h` header file (conventionally `ShaderTypes.h`) defines C structs for vertex data, uniforms, and per-instance data. This file is included in both the bridging header (making types available to Swift) and in `.metal` shader files (making types available to MSL). Single source of truth for GPU data layout. |

**Example ShaderTypes.h:**

```c
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Matches both Swift and MSL
typedef struct {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewProjectionMatrix;
} Uniforms;

typedef struct {
    simd_float3 position;
    simd_float3 normal;
    simd_float2 texCoord;
} Vertex;

typedef struct {
    simd_float4x4 modelMatrix;
    simd_float4   color;
    float         scale;
} InstanceData;

typedef enum {
    BufferIndexVertices    = 0,
    BufferIndexUniforms    = 1,
    BufferIndexInstances   = 2,
} BufferIndex;

#endif
```

This is the standard Apple-recommended pattern. Every Metal sample project from Apple uses this approach.

---

## Xcode Project Structure

```
AirplaneTracker3D/
  AirplaneTracker3D.xcodeproj
  AirplaneTracker3D/
    App/
      AirplaneTracker3DApp.swift        # @main entry point
      ContentView.swift                  # Root view: Metal + sidebar layout
    Rendering/
      Renderer.swift                     # MTKViewDelegate, owns Metal pipeline
      MetalView.swift                    # NSViewRepresentable wrapping MTKView
      ShaderTypes.h                      # Shared types (Swift + MSL)
      Shaders.metal                      # Vertex + fragment shaders
      AircraftMesh.swift                 # Aircraft geometry generation
      TrailRenderer.swift                # Flight trail line rendering
      MapTileManager.swift               # Tile loading, texture atlas
      Camera.swift                       # Orbit camera controller
    Networking/
      FlightDataService.swift            # URLSession polling, API abstraction
      ADSBModels.swift                   # Codable types for API responses
      EnrichmentService.swift            # hexdb.io, adsbdb lookups
      TileService.swift                  # Map tile + terrain tile fetching
    Models/
      Aircraft.swift                     # Aircraft domain model
      FlightTrail.swift                  # Trail point storage
      Airport.swift                      # Airport data model
    State/
      AppState.swift                     # @Observable app-wide state
      FlightDataManager.swift            # Aircraft tracking + interpolation
      SettingsManager.swift              # Persisted user preferences
    Views/
      SidebarView.swift                  # Aircraft list + search
      DetailPanelView.swift              # Selected aircraft info
      SettingsView.swift                 # Preferences panel
      ToolbarItems.swift                 # Toolbar buttons
    Resources/
      Assets.xcassets                    # App icon, colors, images
      AirplaneTracker3D.entitlements     # Network access entitlement
      AirplaneTracker3D-Bridging-Header.h  # Imports ShaderTypes.h
```

**Key structural decisions:**

1. **Rendering/ is separate from Views/** -- Metal code has different concerns (GPU state, shaders, buffers) than SwiftUI views (layout, interaction, data display). Clean separation.
2. **ShaderTypes.h lives in Rendering/** -- close to the `.metal` files that consume it, included in bridging header via build settings path.
3. **State/ holds @Observable objects** -- single source of truth for app state, referenced by both SwiftUI views and the Renderer.
4. **Networking/ is isolated** -- pure async/await services with Codable types, no UI or Metal dependencies. Testable independently.
5. **No Swift Package Manager for the app itself** -- SPM has known limitations with Metal shader compilation (cannot pass Metal compiler flags, cannot debug shaders in Metal Debugger). Use a standard Xcode project. SPM is fine for pure-Swift utility packages if needed.

---

## Metal Rendering Pipeline Details

### Pipeline State Setup (done once at init)

```
MTLDevice (GPU reference)
  --> MTLCommandQueue (one, reused every frame)
  --> MTLLibrary (compiled .metal shaders via makeDefaultLibrary())
  --> MTLRenderPipelineState (configured with vertex/fragment functions, pixel format, depth format)
  --> MTLDepthStencilState (depth compare .less, write enabled)
  --> MTLBuffer[] (vertex buffers, uniform buffers, instance buffers)
  --> MTLTexture[] (map tile textures, loaded async via MTKTextureLoader)
```

### Per-Frame Rendering (in MTKViewDelegate.draw(in:))

```
1. Wait on inFlightSemaphore (triple buffering)
2. Update uniform buffer (camera matrices, time)
3. Update instance buffer (per-aircraft transforms from interpolation)
4. Create MTLCommandBuffer from command queue
5. Get current drawable from MTKView
6. Create MTLRenderPassDescriptor (clear color, load/store actions)
7. Create MTLRenderCommandEncoder
8. Set pipeline state, depth stencil state
9. Set vertex buffers (shared geometry + per-instance data)
10. Draw instanced: drawIndexedPrimitives(instanceCount: aircraftCount)
11. Draw trails (separate draw call, line topology)
12. Draw map tiles (textured quads)
13. End encoding
14. Present drawable
15. Commit command buffer (with completion handler to signal semaphore)
```

### Triple Buffering

Use a `DispatchSemaphore` initialized to 3. Wait before encoding, signal in command buffer completion handler. This lets the CPU prepare frame N+1 while the GPU renders frame N, and frame N-1 is being displayed. Critical for maintaining 60fps with per-frame data updates.

```swift
private let inFlightSemaphore = DispatchSemaphore(value: 3)
private var currentBufferIndex = 0
private var uniformBuffers: [MTLBuffer] // 3 buffers, one per in-flight frame

func draw(in view: MTKView) {
    inFlightSemaphore.wait()
    currentBufferIndex = (currentBufferIndex + 1) % 3
    // ... encode using uniformBuffers[currentBufferIndex] ...
    commandBuffer.addCompletedHandler { [weak self] _ in
        self?.inFlightSemaphore.signal()
    }
}
```

### Instanced Rendering for Aircraft

Instead of one draw call per aircraft (hundreds of draw calls), use a single draw call with instanced rendering:

- One shared aircraft mesh geometry (vertex + index buffers, created once)
- One instance buffer containing per-aircraft data (position, rotation, color, scale)
- One `drawIndexedPrimitives(..., instanceCount: N)` call renders all aircraft
- Vertex shader uses `[[instance_id]]` to index into the instance buffer

This is the single most important performance technique. The web app's THREE.js cannot do this efficiently -- Metal can render 10,000 instances in a single draw call.

---

## ARM Optimization Techniques for Apple Silicon

### Memory Architecture

Apple Silicon uses **Unified Memory Architecture (UMA)** -- CPU and GPU share the same physical memory. This eliminates the traditional CPU-to-GPU data copy bottleneck.

| Technique | What | Why |
|-----------|------|-----|
| **Shared MTLBuffer storage** | `device.makeBuffer(length:, options: .storageModeShared)` | On Apple Silicon, `.storageModeShared` means both CPU and GPU access the same memory -- no copy. On Intel Macs, the driver handles coherency. Always use `.storageModeShared` for buffers that CPU writes and GPU reads (uniforms, instance data). |
| **No explicit sync needed** | CPU writes to shared buffer, GPU reads it | UMA eliminates `MTLBlitCommandEncoder` synchronization needed on discrete GPUs. Just write data and encode -- the GPU sees it. |

### SIMD / NEON Optimization

| Technique | What | Why |
|-----------|------|-----|
| **Use simd types for all math** | `simd_float4x4`, `simd_float3`, `simd_quatf` | Compiler auto-vectorizes to ARM NEON 128-bit instructions. Four float multiplies happen in one instruction. |
| **Batch coordinate transforms** | Convert lat/lon/alt to 3D positions in bulk | Use simd operations on arrays rather than scalar loops. The compiler can auto-vectorize simple loops over simd types. |
| **Avoid Double precision** | Use Float (32-bit), not Double (64-bit) | Metal shaders operate on `float` (32-bit). Using Double on CPU means conversion at the GPU boundary. Keep everything Float for zero-cost handoff. Exception: lat/lon storage (needs Double precision for accuracy), but convert to Float at render time. |

### Frame Budget Optimization

At 60fps, each frame has a 16.67ms budget. For 120fps (ProMotion on newer hardware), 8.33ms.

| Priority | Technique | Impact |
|----------|-----------|--------|
| 1 | **Instanced rendering** | Collapse hundreds of draw calls to 1-3 draw calls |
| 2 | **Triple buffering** | CPU and GPU work in parallel, no stalls |
| 3 | **Shared memory buffers** | Zero-copy CPU-to-GPU data transfer on Apple Silicon |
| 4 | **Frustum culling on CPU** | Skip aircraft outside camera view before building instance buffer |
| 5 | **LOD (Level of Detail)** | Simpler aircraft mesh at distance, full detail when close |
| 6 | **Texture atlas for map tiles** | Reduce texture bind calls by packing tiles into larger textures |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not Alternative |
|----------|-------------|-------------|---------------------|
| 3D Rendering | **Metal 3** | Metal 4 | Ground-up API redesign, requires macOS 26+, bleeding-edge, sparse documentation. Metal 3 is mature and sufficient. Adopt Metal 4 in future milestone. |
| 3D Rendering | **Metal 3** | SceneKit | No instanced rendering API, no custom render passes, no compute shaders. Designed for casual 3D, not real-time data viz. Performance ceiling too low. |
| 3D Rendering | **Metal 3** | RealityKit | Designed for AR/VR, heavy runtime, no direct Metal access for custom rendering. Wrong tool for 2D map + 3D overlay flight tracker. |
| UI Framework | **SwiftUI** | Pure AppKit | AppKit is imperative, verbose, requires more code for equivalent UI. SwiftUI declarative approach matches the reactive data model well (aircraft list updates, settings changes). AppKit still available via NSViewRepresentable for edge cases. |
| UI Framework | **SwiftUI** | Catalyst (UIKit on Mac) | Catalyst apps feel like iPad apps on Mac. No native macOS window management, menus, or keyboard shortcuts. SwiftUI is the native macOS path. |
| Networking | **URLSession** | Alamofire | URLSession async/await is sufficient for GET+JSON. Alamofire adds ~8,000 lines of dependency for features we do not need (multipart upload, request retrying, certificate pinning). |
| Networking | **URLSession** | Combine | Combine is being superseded by async/await. Apple's own sample code has shifted to async/await since Swift 5.5. Combine adds complexity (publisher chains, cancellables) for simple request-response patterns. |
| State Mgmt | **@Observable** | ObservableObject | Legacy pattern. @Observable is Apple's recommended replacement. Better performance (fine-grained property tracking), less boilerplate (no @Published needed), cleaner API. |
| State Mgmt | **@Observable** | TCA (Composable Architecture) | Massive dependency (12K+ lines). Opinionated architecture that would dominate the codebase. Overkill for an app with straightforward state: aircraft list, selected aircraft, settings. |
| Persistence | **UserDefaults + Files** | Core Data | No relational data, no complex queries, no concurrent writes. Core Data's managed object context, migration, and threading model add complexity for settings + cached reference data. |
| Persistence | **UserDefaults + Files** | SwiftData | Same as Core Data -- overkill for this use case. SwiftData is for apps with structured, queryable, relationship-heavy data models. |
| JSON Parsing | **Codable** | SwiftyJSON | SwiftyJSON is untyped (subscript access, no compile-time safety). Codable gives type-safe parsing with zero dependency. |
| Build System | **Xcode project** | Swift Package Manager | SPM cannot pass Metal compiler flags, cannot debug Metal shaders, and has issues with bridging headers. Xcode project is required for full Metal development workflow. |
| Math Library | **simd** | GLKit | GLKit is deprecated. Its math types (GLKMatrix4, GLKVector3) are Objective-C bridged, not Swift-native, and not compatible with Metal buffer layout. simd types match Metal types exactly. |

---

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **WebView / WKWebView** | Project constraint: must be fully native Metal rendering. WebView defeats the purpose of the native rewrite. | Metal + SwiftUI |
| **SceneKit** | Performance ceiling too low. No instanced rendering. No custom render passes. Cannot handle hundreds of dynamic objects with per-frame updates efficiently. | Direct Metal API |
| **Catalyst** | iPad-on-Mac wrapper. Produces non-native Mac experience. Cannot use NSViewRepresentable for Metal integration. | Native SwiftUI + AppKit |
| **Electron / Tauri** | Web technology wrappers. Worse performance than current web app with added overhead. Defeats native rewrite purpose. | Swift + Metal |
| **Combine** | Being superseded by async/await. Adds unnecessary publisher/subscriber complexity. Apple's own code has moved to structured concurrency. | async/await + actors |
| **Realm / Firebase** | Client-side only app. No cloud sync, no authentication, no multi-device. External database adds dependency and network requirement for local data. | UserDefaults + FileManager |
| **SwiftUI Charts** | If statistics graphs are needed, SwiftUI Charts is fine for basic charts. But for real-time updating stats matching the web version's canvas-based graphs, a custom Metal or Canvas2D approach may be needed. Evaluate when implementing stats phase. | Defer decision to stats phase |
| **MapKit** | MapKit renders its own map view with its own gesture handling. Cannot integrate Metal rendering into MapKit's pipeline. The app needs Metal to render map tiles as textured geometry in the 3D scene, not a 2D map overlay. | Fetch raw tile images, render as Metal textures on 3D geometry |

---

## Version Compatibility Matrix

| Component | Version | Requires | Notes |
|-----------|---------|----------|-------|
| Xcode | 26.2 | macOS 26.2 Tahoe (host) | Development machine must run macOS 26 |
| Swift | 6.2.3 | Xcode 26.2 | Strict concurrency, @Observable, InlineArray |
| Metal API | Metal 3 | macOS 13+ (deploy target) | Metal 3 features available on all Apple Silicon Macs |
| MetalKit | Current | macOS 13+ | MTKView, MTKTextureLoader bundled with Metal |
| SwiftUI @Observable | macOS 14+ | Observation framework | Requires macOS 14 Sonoma deploy target |
| SwiftUI .inspector | macOS 14+ | Inspector modifier | Useful for aircraft detail panel |
| SwiftUI .toolbar | macOS 13+ | Toolbar API | Available at minimum deploy target |
| URLSession async/await | macOS 12+ | Swift 5.5+ concurrency | Available well below deploy target |
| simd | Current | Built into Swift | All versions, all platforms |
| MSL | 3.1 | Metal 3 / macOS 13+ | Standard Metal 3 shading language |

**Target deployment: macOS 14 Sonoma** for `@Observable` support while maintaining broad compatibility. All Apple Silicon Macs (M1+) support macOS 14.

---

## Installation / Setup

```bash
# No package manager dependencies for core app.
# Xcode 26.2 provides everything needed.

# 1. Create new Xcode project
#    - Template: macOS > App
#    - Interface: SwiftUI
#    - Language: Swift
#    - Uncheck: Include Tests (add later), Core Data, CloudKit

# 2. Add Metal capability
#    - No special entitlements needed for Metal
#    - Add "Outgoing Connections (Client)" for network access in Sandbox settings
#    - Or disable sandbox entirely (direct distribution, not App Store)

# 3. Create bridging header
#    - Add ShaderTypes.h to project
#    - Set "Objective-C Bridging Header" in Build Settings to:
#      $(PROJECT_DIR)/AirplaneTracker3D/Rendering/ShaderTypes.h

# 4. Add .metal shader files
#    - Xcode automatically compiles .metal files into default.metallib
#    - Access via device.makeDefaultLibrary()

# 5. Configure build settings
#    - Deployment Target: macOS 14.0
#    - Swift Language Version: Swift 6
#    - Strict Concurrency Checking: Complete
#    - Metal Compiler - Build Options: Default (no special flags needed)
```

**No CocoaPods. No SPM dependencies. No Carthage.** The entire app builds with Apple-provided frameworks only. This eliminates dependency management, version conflicts, and third-party update burden. Every framework used ships with the macOS SDK.

---

## Key Integration Points

### 1. Metal <-> SwiftUI Communication

```
SwiftUI @Observable State -----> Renderer reads state each frame
    (aircraft positions,          (builds instance buffer from
     camera state,                 current state, updates uniforms)
     selected aircraft)

Renderer -----> SwiftUI @Observable State
    (hit testing results,         (selectedAircraft updated,
     frame stats)                  fps counter updated)
```

The `@Observable` state objects are the contract between SwiftUI and Metal. SwiftUI views bind to state properties for display. The Renderer reads state properties each frame for rendering. Thread safety is ensured by:
- SwiftUI views run on `@MainActor` (automatic in Swift 6.2)
- Renderer's `draw(in:)` is called on the main thread by MTKView
- State mutations happen on `@MainActor`
- No cross-thread access to shared state

### 2. Networking <-> State

```
FlightDataService (background actor)
    --> async polling loop (1 req/sec)
    --> decode JSON to Codable structs
    --> @MainActor update FlightDataManager.aircraft dictionary
    --> SwiftUI views automatically re-render
    --> Renderer picks up new data next frame
```

### 3. Map Tiles <-> Metal Textures

```
TileService (background)
    --> fetch tile PNG via URLSession
    --> MTKTextureLoader.newTexture(data:options:) async
    --> MTLTexture stored in tile cache
    --> Renderer binds texture when drawing map quad
```

---

## Data Sources (Carried Forward from v1.0)

The native app uses the same external APIs as the web app. No changes to data sources.

| Source | Format | Swift Equivalent |
|--------|--------|-----------------|
| airplanes.live v2 | JSON | `Codable` struct, `URLSession.data(from:)` |
| adsb.lol v2 | JSON | Same parser, different base URL |
| OpenSky Network | JSON (different schema) | Separate `Codable` struct with adapter |
| dump1090 local | JSON (aircraft.json) | `URLSession.data(from: URL(string: "http://localhost:8080/data/aircraft.json")!)` |
| MapTiler Terrain-RGB | PNG tiles | `MTKTextureLoader`, decode RGB to elevation on CPU |
| ArcGIS World Imagery | PNG tiles | `MTKTextureLoader`, bind as `MTLTexture` |
| OurAirports | CSV | Parse with Swift string splitting, cache as `Codable` file |
| FAA ADDS Airspace | GeoJSON | `JSONDecoder`, convert polygons to Metal vertex buffers |

---

## Sources

**Metal & MetalKit:**
- [Metal Overview -- Apple Developer](https://developer.apple.com/metal/) -- Metal 4 announcement, Metal capabilities overview (HIGH confidence)
- [Getting Started with Metal 4 -- Metal by Example](https://metalbyexample.com/metal-4/) -- Metal 4 API changes, requires Xcode 26 / macOS 26 (HIGH confidence)
- [Metal Best Practices: Triple Buffering -- Apple](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html) -- triple buffering pattern (HIGH confidence)
- [Instanced Rendering in Metal -- Metal by Example](https://metalbyexample.com/instanced-rendering/) -- per-instance buffer, instance_id (HIGH confidence)
- [Vertex Data and Vertex Descriptors -- Metal by Example](https://metalbyexample.com/vertex-descriptors/) -- vertex layout patterns (HIGH confidence)
- [Writing a Modern Metal App from Scratch -- Metal by Example](https://metalbyexample.com/modern-metal-1/) -- project structure, pipeline setup (HIGH confidence)
- [Metal Rendering Pipeline -- Kodeco](https://www.kodeco.com/books/metal-by-tutorials/v3.0/chapters/3-the-rendering-pipeline) -- pipeline state, depth buffer, render pass (HIGH confidence)
- [Metal Shading Language Specification v4 -- Apple](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf) -- MSL reference (HIGH confidence)
- [Transform your geometry with Metal mesh shaders -- WWDC22](https://developer.apple.com/videos/play/wwdc2022/10162/) -- mesh shaders for LOD (MEDIUM confidence -- may not be needed initially)
- [Optimize Metal Performance for Apple Silicon -- WWDC20](https://developer.apple.com/videos/play/wwdc2020/10632/) -- UMA, shared storage, Apple Silicon GPU arch (HIGH confidence)
- [Learn performance best practices for Metal shaders -- Apple Tech Talk](https://developer.apple.com/videos/play/tech-talks/111373/) -- shader optimization (HIGH confidence)

**Swift & SwiftUI:**
- [Swift 6.1 Released -- Swift.org](https://www.swift.org/blog/swift-6.1-released/) -- Swift 6.1 features, concurrency improvements (HIGH confidence)
- [Xcode 26.2 Release -- MacObserver](https://www.macobserver.com/news/xcode-26-2-is-now-available-with-updated-sdks-and-swift-6-2-3/) -- Xcode 26.2, Swift 6.2.3, SDK versions (HIGH confidence)
- [Adopting strict concurrency in Swift 6 -- Apple](https://developer.apple.com/documentation/swift/adoptingswift6) -- migration guide, @MainActor (HIGH confidence)
- [Migrating to @Observable -- Apple](https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro) -- ObservableObject to @Observable (HIGH confidence)
- [@Observable Macro performance -- SwiftLee](https://www.avanderlee.com/swiftui/observable-macro-performance-increase-observableobject/) -- fine-grained updates (HIGH confidence)
- [MetalKit in SwiftUI -- Apple Developer Forums](https://developer.apple.com/forums/thread/119112) -- NSViewRepresentable + MTKView pattern (HIGH confidence)
- [URLSession async/await -- SwiftLee](https://www.avanderlee.com/concurrency/urlsession-async-await-network-requests-in-swift/) -- modern networking patterns (HIGH confidence)

**Apple Silicon & Architecture:**
- [simd -- Apple Developer Documentation](https://developer.apple.com/documentation/accelerate/simd-library) -- vector/matrix types (HIGH confidence)
- [Metal 4 Overview -- Low End Mac](https://lowendmac.com/2025/metal-4-an-overview/) -- Metal 3 backward compatibility on macOS 26 (MEDIUM confidence)
- [Support for Metal on Apple devices -- Apple](https://support.apple.com/en-us/102894) -- Metal device support (HIGH confidence)
- [MTKTextureLoader -- Apple Developer Documentation](https://developer.apple.com/documentation/metalkit/mtktextureloader) -- async texture loading API (HIGH confidence)

**Project Structure & Patterns:**
- [Swift Package with Metal -- Apple Forums](https://developer.apple.com/forums/thread/649579) -- SPM limitations with Metal shaders (HIGH confidence)
- [Bridging Header for Shader Types -- Apple Forums](https://forums.developer.apple.com/thread/115086) -- ShaderTypes.h shared struct pattern (HIGH confidence)

---

*Stack research for: Airplane Tracker 3D -- v2.0 Native macOS Metal App*
*Researched: 2026-02-08*
