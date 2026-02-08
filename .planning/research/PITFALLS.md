# Domain Pitfalls

**Domain:** Native macOS Metal flight tracker (THREE.js/WebGL to Swift/Metal/SwiftUI rewrite)
**Researched:** 2026-02-08
**Confidence:** HIGH (verified against Apple Developer Documentation, Metal Best Practices Guide, Swift Forums, and multiple authoritative sources)

---

## Critical Pitfalls

Mistakes that cause rewrites, render corruption, or major architectural issues.

---

### Pitfall 1: WebGL-to-Metal Coordinate System Mismatch

**What goes wrong:** Geometry renders upside-down, inside-out, or with inverted depth. Objects near the camera disappear. Orthographic views show nothing at all. The developer spends hours debugging what looks like a shader bug, but it is a math convention mismatch at the projection matrix level.

**Why it happens:** THREE.js (WebGL/OpenGL) and Metal differ in three fundamental ways:

| Convention | THREE.js / WebGL | Metal |
|------------|-----------------|-------|
| **NDC depth range** | [-1, +1] (2-unit cube centered at origin) | [0, +1] (1-unit half-cube, center at z=0.5) |
| **NDC Y-axis** | +Y is up | +Y is up (same, but texture coords differ) |
| **Texture coord origin** | Bottom-left (0,0), +V is up | Top-left (0,0), +V is down |
| **Default front face winding** | Counter-clockwise (CCW) | Clockwise (CW) |
| **Coordinate system handedness** | Right-handed | Left-handed (NDC/clip space) |
| **NDC center** | (0, 0, 0) | (0, 0, 0.5) |

**Consequences:**
- Reusing THREE.js projection matrices verbatim causes depth buffer corruption or all geometry culled
- Orthographic projections break completely (perspective hides the z-range problem due to foreshortening)
- All faces render as back-faces and get culled, producing invisible geometry
- Textures (map tiles, UI elements) render upside-down

**Prevention:**
1. Build the projection matrix from scratch for Metal's conventions. Do NOT port the THREE.js `PerspectiveCamera` matrix directly. Metal's `simd` library provides `matrix_perspective_right_hand` / `matrix_perspective_left_hand` functions that output to Metal's [0,1] depth range.
2. If reusing math from the web version, apply the OpenGL-to-Metal depth correction matrix (scale Z by 0.5, translate Z by 0.5) AFTER the OpenGL-style projection.
3. Set `frontFacingWinding` to `.counterClockwise` on the render command encoder if reusing vertex data from the web version (THREE.js uses CCW, Metal defaults to CW).
4. Flip texture V coordinates: `v_metal = 1.0 - v_webgl` in the vertex shader or during texture upload.
5. Write a unit test that verifies a known vertex (e.g., an aircraft at lat/lon/alt) projects to the expected screen coordinates through your full MVP pipeline.

**Detection:** First triangle renders invisible or inside-out. Depth fighting on overlapping geometry. Textures upside-down.

**Confidence:** HIGH -- based on Apple Developer Documentation, multiple verified sources on Metal NDC conventions.

**Sources:**
- [From OpenGL to Metal - The Projection Matrix Problem](https://metashapes.com/blog/opengl-metal-projection-matrix-problem/)
- [Metal & OpenGL Coordinate Systems](https://jamescube.me/2020/03/metal-opengl-coordinate-systems/)
- [MTLWinding - Apple Developer Documentation](https://developer.apple.com/documentation/metal/mtlwinding)
- [Coordinate Systems - gpuweb Issue #416](https://github.com/gpuweb/gpuweb/issues/416)
- [API-specific rendering differences - Veldrid](https://veldrid.dev/articles/backend-differences.html)

---

### Pitfall 2: Creating MTLRenderPipelineState Objects Per Frame

**What goes wrong:** Frame rate drops below 30fps despite simple geometry. GPU profiler shows most time spent in pipeline state compilation, not rendering.

**Why it happens:** In THREE.js, material/shader setup is largely automatic and cached internally. Developers porting to Metal may recreate `MTLRenderPipelineDescriptor` and call `device.makeRenderPipelineState()` every frame (or on every draw call), not realizing that pipeline state creation involves GPU shader compilation and is extremely expensive.

**Consequences:**
- 10-100ms stalls per pipeline state creation (60fps needs <16ms total frame time)
- GPU shader compilation hitches visible as periodic freezes
- Memory pressure from redundant compiled shader variants

**Prevention:**
1. Create ALL `MTLRenderPipelineState` objects at app startup or scene load, not during the render loop.
2. Cache pipeline states in a dictionary keyed by their configuration (blend mode, vertex descriptor, shader variant).
3. For the flight tracker, you likely need only 3-5 pipeline states: aircraft geometry, flight trails (line rendering), ground plane/map tiles, text/labels, and a skybox/background. Create all of them once.
4. If you need dynamic shader variants, use Metal function constants (specialization constants) to avoid full recompilation.

**Detection:** Instruments Metal System Trace shows `makeRenderPipelineState` calls during frame rendering. Frame time spikes correlate with first use of each visual element.

**Confidence:** HIGH -- Apple Developer Documentation explicitly warns about this.

**Sources:**
- [MTLRenderPipelineState - Apple Documentation](https://developer.apple.com/documentation/metal/mtlrenderpipelinestate)
- [Metal Best Practices Guide](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/)

---

### Pitfall 3: Missing Triple Buffering for Dynamic Data

**What goes wrong:** CPU and GPU fight over the same buffer. Aircraft positions stutter, trails flicker, or the app hangs waiting for GPU to release the buffer. In the worst case, data races corrupt vertex data mid-frame, producing visual glitches (vertices at 0,0,0, stretched triangles).

**Why it happens:** In the web version, JavaScript's single-threaded model and WebGL's implicit synchronization hide the CPU/GPU synchronization problem. In Metal, the CPU and GPU run asynchronously. If you write new aircraft positions into the same buffer the GPU is currently reading, you get torn frames or hangs.

**Consequences:**
- CPU stalls waiting for GPU (destroys frame rate)
- Torn/corrupted vertex data (visual artifacts)
- Deadlocks if semaphore logic is wrong

**Prevention:**
1. Implement triple buffering with a ring of 3 buffers for ALL per-frame dynamic data (aircraft positions, trail vertices, uniform buffers with camera matrices).
2. Use a `DispatchSemaphore` initialized to 3. Wait on it before encoding a frame, signal it in the command buffer's completion handler.
3. Advance the buffer index AFTER all CPU writes for that frame are complete, not before.
4. For the flight tracker's data flow: network data arrives -> update staging buffer on CPU -> copy to the next available ring buffer slot -> GPU reads from a previous slot.

```swift
let maxInflightFrames = 3
let frameSemaphore = DispatchSemaphore(value: maxInflightFrames)
var currentBufferIndex = 0

func draw(in view: MTKView) {
    frameSemaphore.wait()
    currentBufferIndex = (currentBufferIndex + 1) % maxInflightFrames

    // Update dynamicBuffers[currentBufferIndex] with new aircraft data
    // Encode render commands referencing dynamicBuffers[currentBufferIndex]

    commandBuffer.addCompletedHandler { [weak self] _ in
        self?.frameSemaphore.signal()
    }
    commandBuffer.commit()
}
```

**Detection:** Instruments shows GPU idle time followed by CPU idle time in alternation. Frame time exceeds 16ms despite low GPU load.

**Confidence:** HIGH -- Apple's Metal Best Practices Guide explicitly recommends this pattern.

**Sources:**
- [Metal Best Practices Guide: Triple Buffering](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html)
- [Metal Triple Buffering - Apple Developer Forums](https://developer.apple.com/forums/thread/651581)

---

### Pitfall 4: SwiftUI State Changes Triggering Metal View Recreation

**What goes wrong:** Updating the aircraft detail panel (SwiftUI) causes the entire Metal view to flicker, re-initialize, or drop frames. Selecting a different aircraft causes a 200ms hitch. UI controls feel sluggish despite the 3D view rendering at 60fps.

**Why it happens:** SwiftUI re-evaluates view bodies when `@State`, `@Binding`, or `@Observable` properties change. If the MTKView wrapper (`NSViewRepresentable`) is inside the same view hierarchy as the data panel, SwiftUI may recreate the NSView, reset the Metal pipeline, or trigger unnecessary redraws. SwiftUI's diffing cannot understand Metal's internal state.

**Consequences:**
- Metal view destroyed and recreated on state changes (pipeline states lost, buffers recreated)
- Frame drops every time the user interacts with UI controls
- Flicker during window resize as MTKView's drawable is recreated

**Prevention:**
1. Isolate the MTKView wrapper into its own SwiftUI view with NO state dependencies. It should have zero `@State`, `@Binding`, or `@Observable` properties that change during runtime.
2. Communicate between SwiftUI and Metal through a shared `Renderer` class (not through SwiftUI state). The Renderer should be a reference type (`class`) that the MTKView's Coordinator holds directly.
3. Use `EquatableView` or implement `Equatable` on your NSViewRepresentable to prevent unnecessary updates.
4. For the aircraft detail panel: SwiftUI reads from the Renderer's published selected-aircraft data, but changes to the panel do NOT flow back through the MTKView's view hierarchy.
5. Handle window resize explicitly: set `autoResizeDrawable = false` on the MTKView if resize causes flicker, then manually update `drawableSize` in `updateNSView`.

```swift
// WRONG: State in the same view as Metal
struct ContentView: View {
    @State var selectedAircraft: Aircraft?  // Changes trigger full body re-eval
    var body: some View {
        HSplitView {
            MetalView()  // Gets recreated when selectedAircraft changes!
            DetailPanel(aircraft: selectedAircraft)
        }
    }
}

// RIGHT: Isolate Metal view from changing state
struct ContentView: View {
    @State var renderer = FlightRenderer()
    var body: some View {
        HSplitView {
            MetalView(renderer: renderer)  // Never changes identity
                .equatable()
            DetailPanel(renderer: renderer)  // Reads from renderer directly
        }
    }
}
```

**Detection:** Add `Self._printChanges()` in the Metal wrapper's `body` to see if it is being re-evaluated. Instruments SwiftUI template shows view identity changes.

**Confidence:** HIGH -- documented in Apple Developer Forums and multiple verified SwiftUI + Metal integration discussions.

**Sources:**
- [MetalKit in SwiftUI - Apple Developer Forums](https://developer.apple.com/forums/thread/119112)
- [Metal Integration with SwiftUI - Apple Developer Forums](https://origin-devforums.apple.com/forums/thread/774100)
- [Demystify SwiftUI Performance - WWDC23](https://developer.apple.com/videos/play/wwdc2023/10160/)

---

### Pitfall 5: Network Data Updates on the Render Thread

**What goes wrong:** Aircraft positions freeze for 100-500ms every time a network poll completes. Frame rate drops from 60fps to <20fps during data updates. The app feels like it "hitches" every 1-3 seconds.

**Why it happens:** The web version uses `setInterval` + `fetch` which is naturally async in JavaScript. In the native app, developers may process network responses (JSON parsing, aircraft array updates, trail point appending) on the same thread or lock that the render loop uses. JSON parsing of 200+ aircraft responses takes 5-20ms. Combined with buffer updates, this exceeds the 16ms frame budget.

**Consequences:**
- Visible stutters at each data poll interval
- Lock contention between network processing and rendering threads
- In the worst case, network timeouts stall the render thread entirely

**Prevention:**
1. Process ALL network data on a background thread/queue. Never parse JSON or update data models on the render thread.
2. Use a double-buffer pattern for the data model: network thread writes to a "staging" model, render thread reads from a "current" model. Swap atomically at frame boundaries.
3. Implement interpolation on the render thread using the last two known positions per aircraft. The render thread should never wait for network data -- it extrapolates from cached state.
4. Use `URLSession` with a dedicated `OperationQueue` for network requests. Process responses with `Decodable` on that queue, not `MainActor`.
5. Set a network timeout of 5 seconds (not the default 60s). If an API is slow, skip that poll cycle rather than blocking.

```
Network Thread:        poll -> JSON parse -> update staging model
                                                     |
Frame Boundary:                              atomic swap -----+
                                                              v
Render Thread:         read current model -> interpolate -> encode -> GPU
```

**Detection:** Frame time spikes correlating with network poll interval. Instruments Time Profiler shows JSON parsing on the main thread or render thread.

**Confidence:** HIGH -- well-established real-time rendering pattern; multiple sources confirm lock contention as the primary cause of frame drops in Metal apps with concurrent data updates.

**Sources:**
- [Metal by Tutorials: Performance Optimization - Kodeco](https://www.kodeco.com/books/metal-by-tutorials/v2.0/chapters/24-performance-optimization)
- [Metal retrospective - zeux.io](https://zeux.io/2016/12/01/metal-retrospective/)

---

## Moderate Pitfalls

Mistakes that cost days of debugging or performance issues, but are recoverable.

---

### Pitfall 6: Autorelease Pool Drain Missing in Render Loop

**What goes wrong:** Memory usage climbs steadily (10-50MB per minute), eventually causing the app to be killed by the OS or swap thrashing. The leak is not visible in Instruments' standard leak detector because the objects are autoreleased, just never drained.

**Why it happens:** Metal objects (command buffers, drawables, textures) are Objective-C objects under the hood, managed by autorelease pools. In a tight render loop, temporary objects accumulate. In JavaScript/THREE.js, garbage collection handles this automatically. In Swift, if the render loop callback (e.g., `draw(in:)`) runs on a thread without a properly scoped autorelease pool, temporaries pile up until the thread's top-level pool drains (which may be never for a custom rendering thread).

**Prevention:**
1. Wrap the body of your `draw(in:)` method in an `autoreleasepool { }` block.
2. If using a custom display link thread (not MTKView's built-in delegate), ensure each frame iteration has its own autorelease pool.
3. Use Instruments Allocations to verify that Metal object counts remain stable over time (not monotonically increasing).

```swift
func draw(in view: MTKView) {
    autoreleasepool {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }
        // ... encode and commit
    }
}
```

**Detection:** Activity Monitor shows memory growth over time. Run with `OBJC_DEBUG_MISSING_POOLS=YES` environment variable to get runtime warnings.

**Confidence:** HIGH -- multiple verified bug reports and Apple documentation confirm this.

**Sources:**
- [Metal renderer memory leaks on render loop - cocos2d-x Issue](https://github.com/cocos2d/cocos2d-x/issues/19997)
- [Metal Best Practices Guide: Drawables](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html)
- [Autorelease pool memory leak - MoltenVK Issue](https://github.com/KhronosGroup/MoltenVK/issues/1732)

---

### Pitfall 7: Wrong GPU Buffer Storage Mode on macOS

**What goes wrong:** Performance is 2-5x worse than expected for vertex buffer updates, or CPU cannot read back data that the GPU wrote.

**Why it happens:** macOS (unlike iOS with Apple Silicon unified memory) supports three buffer storage modes: `.shared`, `.managed`, and `.private`. Choosing the wrong one wastes memory bandwidth or requires unnecessary synchronization. Developers coming from WebGL (where this distinction does not exist) may default to `.shared` for everything.

| Storage Mode | CPU Access | GPU Access | Best For |
|-------------|-----------|-----------|----------|
| `.shared` | Direct | Direct (but slower on discrete GPU) | Small, frequently updated data (uniforms, small vertex buffers) |
| `.managed` | Buffered copy | Fast VRAM copy | Medium-sized data updated occasionally (map tile vertices, airport geometry) |
| `.private` | None | Fastest | Static data (sphere geometry, textures), GPU-generated data |

**Prevention:**
1. Use `.shared` for per-frame dynamic data under 4KB (camera uniforms, light parameters).
2. Use `.managed` for aircraft vertex buffers and trail data that update every poll cycle but not every frame. Call `didModifyRange()` after CPU writes.
3. Use `.private` for static geometry (ground plane, airport models) and textures. Upload via a blit command encoder from a staging `.shared` buffer.
4. On Apple Silicon Macs, `.shared` and `.managed` have similar performance due to unified memory, but `.private` is still fastest for GPU-only data.

**Detection:** Metal System Trace in Instruments shows excessive buffer synchronization time. GPU timeline shows idle periods waiting for buffer transfers.

**Confidence:** HIGH -- Apple Developer Documentation provides explicit guidance on storage modes.

**Sources:**
- [Choosing a Resource Storage Mode in macOS - Apple Documentation](https://developer.apple.com/documentation/metal/setting_resource_storage_modes/choosing_a_resource_storage_mode_in_macos)
- [Metal Best Practices Guide: Resource Options](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/ResourceOptions.html)

---

### Pitfall 8: MSL Shader Porting Gotchas from GLSL

**What goes wrong:** Shaders compile but produce wrong output. Colors are off, lighting is inverted, or procedural effects (like trail glow) behave differently.

**Why it happens:** Metal Shading Language (MSL) is based on C++14 and differs from GLSL in subtle but breaking ways:

| GLSL | MSL | Gotcha |
|------|-----|--------|
| `vec3`, `mat4` | `float3`, `float4x4` | Direct rename needed |
| `mod(x, y)` | `fmod(x, y)` | `fmod` has different sign behavior for negative numbers. GLSL `mod` always returns positive; MSL `fmod` preserves the sign of the dividend |
| `pow(x, y)` | `powr(x, y)` | Use `powr` when first arg is known non-negative (MSL `pow` has undefined behavior for negative base) |
| `texture2D(sampler, uv)` | `texture.sample(sampler, uv)` | Object method, not function |
| `gl_Position` | Return struct with `[[position]]` | No magic globals; use attribute qualifiers |
| `varying` / `in` / `out` | Struct with `[[stage_in]]` | Explicit structs for inter-stage data |
| Buffer index implicit | `[[buffer(N)]]` explicit | Mismatch between Swift-side `setVertexBuffer(at: N)` and shader `[[buffer(N)]]` is a silent bug |

**Prevention:**
1. Port shaders manually, not with automated tools. The flight tracker has relatively simple shaders (position transforms, color interpolation, trail effects) that are faster to rewrite than to debug after automated conversion.
2. Test each shader in isolation with known inputs before integrating into the full pipeline.
3. Pay special attention to `mod` vs `fmod` -- if your trail color-coding uses modular arithmetic, the sign difference will produce wrong colors for negative values.
4. Match buffer indices explicitly. Create constants shared between Swift and MSL (via a shared header or bridging header) to avoid index mismatches.

**Detection:** Visual output differs from web version. Colors wrong but geometry correct usually indicates a math function difference.

**Confidence:** HIGH -- documented differences in Apple's MSL specification.

**Sources:**
- [Metal Shading Language Specification - Apple](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)
- [GLSL Common Mistakes - Khronos Wiki](https://www.khronos.org/opengl/wiki/GLSL_:_common_mistakes)

---

### Pitfall 9: Swift 6 Concurrency vs Metal's Threading Model

**What goes wrong:** Swift 6's strict concurrency checker produces dozens of warnings/errors about `Sendable` conformance, `@MainActor` isolation, and data race safety. The developer either disables concurrency checking entirely (losing safety) or wraps everything in actors (destroying performance).

**Why it happens:** Metal's callback-based API (`addCompletedHandler`, `MTKViewDelegate.draw(in:)`) predates Swift concurrency. `MTKViewDelegate` is not annotated with `@MainActor` or `@Sendable`. GPU completion handlers run on arbitrary threads. Passing Metal objects (which are not `Sendable`) across isolation boundaries triggers compiler warnings.

**Consequences:**
- False-positive data race warnings everywhere
- Temptation to mark everything `@unchecked Sendable` (hides real bugs)
- `@MainActor` isolation on the renderer forces all Metal work onto the main thread, defeating the purpose of async GPU execution
- Deadlocks if `await` is used inside the render loop (it suspends the draw callback)

**Prevention:**
1. Use `MainActor.assumeIsolated { }` inside `draw(in:)` since MTKView's delegate is called on the main thread. This satisfies the compiler without adding overhead.
2. Collect per-frame input (mouse position, selected aircraft) into a `Sendable` struct at the start of each frame. Do not access `@MainActor`-isolated UI state during rendering.
3. Keep the Renderer class as a regular class (not an actor). Use explicit locks (`os_unfair_lock` or `NSLock`) for the small amount of shared state between the network thread and render thread -- actors add scheduling overhead inappropriate for 60fps rendering.
4. For GPU completion handlers, use `nonisolated` and avoid capturing `self` strongly. Signal semaphores, do not do complex work.
5. Target Swift 6.2+ which has improved default actor isolation and `nonisolated(nonsending)` to reduce friction.

```swift
// Pattern for MTKViewDelegate with Swift 6 strict concurrency
extension Renderer: MTKViewDelegate {
    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            self.performDraw(in: view)
        }
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        MainActor.assumeIsolated {
            self.handleResize(size)
        }
    }
}
```

**Detection:** Build with strict concurrency checking enabled (`-strict-concurrency=complete`). Dozens of warnings about `Sendable` and actor isolation.

**Confidence:** HIGH -- verified via Swift Forums discussion on Metal + Swift concurrency.

**Sources:**
- [Swift Concurrency and Metal - Swift Forums](https://forums.swift.org/t/swift-concurrency-and-metal/71908)
- [Sending risks causing data races and Metal completion handlers - Swift Forums](https://forums.swift.org/t/sending-risks-causing-data-races-and-metal-completion-handlers/72518)
- [Default Actor Isolation in Swift 6.2 - SwiftLee](https://www.avanderlee.com/concurrency/default-actor-isolation-in-swift-6-2/)

---

### Pitfall 10: macOS Code Signing, Notarization, and Distribution

**What goes wrong:** The app builds and runs in Xcode but crashes on another Mac with "app is damaged" or "cannot be opened because the developer cannot be verified." Users cannot open the DMG. The notarization submission is rejected or hangs indefinitely.

**Why it happens:** macOS Gatekeeper requires code signing + notarization for apps distributed outside the App Store. The process has multiple failure points that do not exist in web development.

**Consequences:**
- Users cannot run the app (Gatekeeper blocks it)
- App runs in development but fails in production
- Hours lost to cryptic codesign/notarization errors

**Prevention:**
1. **Apple Developer Program membership ($99/year) is required.** You cannot notarize without it. Budget for this early.
2. **Sign bottom-up, not with `--deep`.** The `--deep` flag is unreliable. Sign embedded frameworks first, then the app bundle.
3. **Enable Hardened Runtime.** Required for notarization. Add it early in development, not at the end, because it restricts JIT, dynamic library loading, and other capabilities that might affect your app.
4. **Required entitlements for the flight tracker:**
   - `com.apple.security.network.client` -- outgoing network connections (fetching flight data from APIs)
   - Hardened Runtime enabled (required for notarization)
   - No App Sandbox needed for direct distribution (Project explicitly targets DMG distribution, not App Store)
5. **DMG notarization workflow:**
   - Notarize the .app bundle first
   - Create DMG containing the notarized .app
   - Notarize the DMG
   - Staple the ticket to the DMG with `xcrun stapler staple`
   - The inner .app is also independently notarized, so it works if extracted from the DMG
6. **Use `notarytool` (not deprecated `altool`).** `altool` was retired November 2023.
7. **Test on a clean Mac** (or a fresh user account) before distributing. Development Macs have Gatekeeper exceptions.

**Detection:** Run `codesign --verify --deep --strict --verbose=2 YourApp.app` and `spctl --assess -vv YourApp.app` to check before distributing.

**Confidence:** HIGH -- Apple Developer Documentation provides explicit requirements.

**Sources:**
- [Resolving Common Notarization Issues - Apple Documentation](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
- [Notarizing macOS Software Before Distribution - Apple Documentation](https://developer.apple.com/documentation/security/notarizing-macOS-software-before-distribution)
- [Hardened Runtime - Apple Documentation](https://developer.apple.com/documentation/security/hardened-runtime)
- [macOS distribution gist - rsms](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)

---

## Minor Pitfalls

Issues that cost hours, not days. Easy to fix once identified.

---

### Pitfall 11: nextDrawable() Blocking and App Hang on Background/Foreground

**What goes wrong:** The app hangs for 1 second when backgrounded and foregrounded. Occasional frame drops when the GPU is busy.

**Why it happens:** `CAMetalLayer.nextDrawable()` blocks if all drawables are in use. When the app is backgrounded, the system reclaims drawables. On resume, the first call blocks until one is available. If `allowsNextDrawableTimeout` is false (default), it blocks indefinitely.

**Prevention:**
1. Set `(view.layer as? CAMetalLayer)?.allowsNextDrawableTimeout = true` to return `nil` instead of blocking.
2. Guard `view.currentDrawable` at the top of `draw(in:)`. If nil, skip the frame.
3. Do not hold references to drawables beyond the current frame's command buffer.
4. Request the drawable as LATE as possible in the frame -- do all CPU work (buffer updates, command encoding) first, then acquire the drawable only when you need to set it as the render target.

**Detection:** Instruments shows `nextDrawable` taking >1ms. App freezes briefly on Cmd+Tab.

**Confidence:** HIGH -- Apple Developer Documentation.

**Sources:**
- [Metal Best Practices Guide: Drawables](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html)
- [nextDrawable() - Apple Documentation](https://developer.apple.com/documentation/quartzcore/cametallayer/1478172-nextdrawable)

---

### Pitfall 12: MTKView Continuous Drawing Not Enabled in SwiftUI Wrapper

**What goes wrong:** The Metal view renders once and then stops. It only redraws when the window is resized. The app appears frozen even though data is updating.

**Why it happens:** MTKView has two draw modes: timer-driven (continuous) and explicit (on-demand via `setNeedsDisplay`). The default `isPaused = false` and `enableSetNeedsDisplay = false` should give continuous drawing, but when wrapping in `NSViewRepresentable`, the configuration can be reset or overridden during `makeNSView` / `updateNSView`.

**Prevention:**
1. In `makeNSView`, explicitly set:
   ```swift
   mtkView.isPaused = false
   mtkView.enableSetNeedsDisplay = false
   mtkView.preferredFramesPerSecond = 60
   ```
2. Set the delegate in `makeNSView`, not `updateNSView` (SwiftUI may call `updateNSView` multiple times, resetting the delegate).
3. Verify drawing is continuous by logging frame count in `draw(in:)`.

**Detection:** View renders static content. Resizing the window causes redraws but nothing else does.

**Confidence:** HIGH -- frequently reported issue in Apple Developer Forums.

**Sources:**
- [MetalKit in SwiftUI - Apple Developer Forums](https://developer.apple.com/forums/thread/119112)

---

### Pitfall 13: simd_float4x4 Alignment and Layout Mismatches in Uniform Buffers

**What goes wrong:** Uniform buffers appear to contain garbage data. Camera position is wrong. Transformations apply incorrectly (rotation instead of translation, or vice versa).

**Why it happens:** Both THREE.js and Metal's `simd_float4x4` use column-major storage. However, when writing matrix math in Swift, developers may think in row-major terms and construct matrices incorrectly. The `simd_float4x4(columns:)` initializer takes columns, not rows. Additionally, the memory layout of `simd_float4x4` has 16-byte alignment requirements that must be respected in uniform buffer structs.

**Prevention:**
1. Use `simd_float4x4(columns: (col0, col1, col2, col3))` -- each column is a `simd_float4`.
2. For uniform buffer structs, ensure 16-byte alignment. Add padding fields if necessary. Verify with `MemoryLayout<YourStruct>.stride`.
3. Verify matrix layout matches between Swift struct and MSL struct. Print `MemoryLayout<Uniforms>.stride` and compare with the MSL struct size.
4. Use Apple's `simd` convenience functions (`matrix_perspective_right_hand`, `matrix_look_at_right_hand`) rather than porting matrix math from THREE.js.

**Detection:** Objects render at wrong positions. Camera orbit produces unexpected behavior. `MemoryLayout<Uniforms>.stride` does not match expected value.

**Confidence:** MEDIUM -- column-major compatibility verified, but alignment issues are project-specific.

---

### Pitfall 14: Excessive SwiftUI View Updates from @Observable Flight Data

**What goes wrong:** The aircraft list panel updates 200+ rows every second, causing the entire SwiftUI view hierarchy to re-evaluate and the UI thread to stall.

**Why it happens:** If the aircraft array is an `@Observable` property, any change to any aircraft (position update every 1-3 seconds for each of 200+ aircraft) triggers SwiftUI to diff the entire list. This is amplified if each aircraft is itself observable and updates its coordinates.

**Prevention:**
1. Do NOT make the live aircraft data model `@Observable`. Use `@Observable` for UI-level state only (selected aircraft, settings, theme).
2. For the aircraft list, use a snapshot approach: capture a read-only copy of the aircraft array at a fixed interval (e.g., every 500ms) and update a `@State` property, rather than streaming every position update.
3. Use `LazyVStack` or `List` with stable `id` values (ICAO hex code) to minimize diffing cost.
4. Break the detail panel into small sub-views so that only the changed property's sub-view re-evaluates.

**Detection:** Instruments SwiftUI template shows >100 view body evaluations per second. Main thread time profiler shows time in SwiftUI diffing.

**Confidence:** MEDIUM -- based on general SwiftUI performance guidance; specific to high-frequency data updates.

**Sources:**
- [Optimizing SwiftUI: Reducing Body Recalculation](https://medium.com/@wesleymatlock/optimizing-swiftui-reducing-body-recalculation-and-minimizing-state-updates-8f7944253725)
- [Understanding and Improving SwiftUI Performance - Apple Documentation](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)

---

### Pitfall 15: MTKView Resize Flicker and Jank

**What goes wrong:** Resizing the window causes the Metal content to stretch, blur, or flash white for a frame before redrawing at the new size.

**Why it happens:** By default, `MTKView.autoResizeDrawable` is `true`, which resizes the Metal drawable every frame during a window resize. Between the resize event and the next draw call, the MTKView scales the old drawable to fill the new size, producing blur. If the draw call is slow, there is a visible stretch-snap effect.

**Prevention:**
1. For smooth resize: keep `autoResizeDrawable = true` (default) but ensure the draw loop is fast enough to keep up. Use Metal's `presentsWithTransaction = true` on the CAMetalLayer to synchronize presentation with the resize animation.
2. For preventing blur: set `autoResizeDrawable = false` and manually update `drawableSize` in the `viewDidEndLiveResize` callback, accepting that content will be scaled during the resize gesture itself.
3. Set a background clear color that matches your scene background so flashes are less noticeable.

**Detection:** Resize the window slowly. Look for white flashes, stretching, or blur.

**Confidence:** MEDIUM -- Apple Developer Forums reports, specific behavior may vary by macOS version.

**Sources:**
- [Redraw MTKView when its size changes - Apple Developer Forums](https://developer.apple.com/forums/thread/77901)

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| **Metal rendering setup** | Coordinate system mismatch (#1), pipeline state per frame (#2), continuous drawing (#12) | Build a minimal test scene (single triangle, known coordinates) first. Verify winding, depth, and projection before adding complexity. |
| **Aircraft rendering** | Triple buffering missing (#3), storage mode wrong (#7) | Implement triple buffering from day 1. Profile with Metal System Trace early. |
| **Shader porting** | GLSL-to-MSL function differences (#8), matrix alignment (#13) | Port shaders manually. Test each in isolation. Share buffer layout constants between Swift and MSL. |
| **Data pipeline** | Network on render thread (#5), excessive SwiftUI updates (#14) | Architect network/render separation from the start. Use staging model pattern. |
| **SwiftUI integration** | State changes destroying Metal view (#4), view body recomputation (#14), resize flicker (#15) | Isolate MTKView wrapper. Use reference-type Renderer shared between SwiftUI and Metal. |
| **Swift concurrency** | Sendable/actor friction (#9) | Use `MainActor.assumeIsolated` in draw callbacks. Keep Renderer as plain class with explicit locking. |
| **Memory management** | Autorelease pool missing (#6), drawable retention (#11) | Wrap draw loop in autoreleasepool. Monitor memory in Instruments during development. |
| **Distribution** | Code signing/notarization (#10) | Set up signing and Hardened Runtime in Phase 1. Do not defer to the end. Test on a clean Mac before any beta distribution. |

---

## Summary: Top 5 Mistakes in Order of Impact

1. **Coordinate system mismatch** (#1) -- will make nothing render correctly. Address in the first hour of Metal development.
2. **No triple buffering** (#3) -- will cause stutters that are architecturally expensive to fix later. Build it from the start.
3. **Network data on render thread** (#5) -- will cause periodic hitches that users notice immediately. Architect the separation from day 1.
4. **SwiftUI state destroying Metal view** (#4) -- will cause mysterious flickering that is hard to diagnose. Isolate the Metal view wrapper.
5. **Code signing deferred to end** (#10) -- will block distribution. Set up in Phase 1.

---

## Sources

- [Metal Best Practices Guide - Apple](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/)
- [From OpenGL to Metal - The Projection Matrix Problem](https://metashapes.com/blog/opengl-metal-projection-matrix-problem/)
- [Metal & OpenGL Coordinate Systems - JAMESCUBE](https://jamescube.me/2020/03/metal-opengl-coordinate-systems/)
- [MTLWinding - Apple Documentation](https://developer.apple.com/documentation/metal/mtlwinding)
- [Coordinate Systems - gpuweb Issue #416](https://github.com/gpuweb/gpuweb/issues/416)
- [API-specific Rendering Differences - Veldrid](https://veldrid.dev/articles/backend-differences.html)
- [Metal by Tutorials: Coordinate Spaces - Kodeco](https://www.kodeco.com/books/metal-by-tutorials/v3.0/chapters/6-coordinate-spaces)
- [Metal Triple Buffering - Apple Developer Forums](https://developer.apple.com/forums/thread/651581)
- [Choosing a Resource Storage Mode in macOS - Apple Documentation](https://developer.apple.com/documentation/metal/setting_resource_storage_modes/choosing_a_resource_storage_mode_in_macos)
- [Swift Concurrency and Metal - Swift Forums](https://forums.swift.org/t/swift-concurrency-and-metal/71908)
- [Sending risks causing data races - Swift Forums](https://forums.swift.org/t/sending-risks-causing-data-races-and-metal-completion-handlers/72518)
- [Resolving Common Notarization Issues - Apple Documentation](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
- [Notarizing macOS Software Before Distribution - Apple Documentation](https://developer.apple.com/documentation/security/notarizing-macOS-software-before-distribution)
- [Hardened Runtime - Apple Documentation](https://developer.apple.com/documentation/security/hardened-runtime)
- [MetalKit in SwiftUI - Apple Developer Forums](https://developer.apple.com/forums/thread/119112)
- [Demystify SwiftUI Performance - WWDC23](https://developer.apple.com/videos/play/wwdc2023/10160/)
- [macOS Distribution Guide - rsms](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)
- [Metal Shading Language Specification - Apple](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)
- [Metal Best Practices Guide: Drawables](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html)
- [nextDrawable() - Apple Documentation](https://developer.apple.com/documentation/quartzcore/cametallayer/1478172-nextdrawable)
- [Understanding and Improving SwiftUI Performance - Apple Documentation](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)

---
*Pitfalls research for: Native macOS Metal flight tracker (THREE.js/WebGL to Swift/Metal/SwiftUI rewrite)*
*Researched: 2026-02-08*
