# Project Research Summary

**Project:** Airplane Tracker 3D -- v2.0 Native macOS App
**Domain:** Real-time 3D flight visualization (THREE.js/WebGL to Swift/Metal/SwiftUI rewrite)
**Researched:** 2026-02-08
**Confidence:** HIGH (verified against Apple official docs, Metal by Example, existing web app analysis)

## Executive Summary

This project rewrites an existing 5,735-line THREE.js flight tracker web app as a native macOS application using Swift, Metal 3, and SwiftUI. The web version successfully demonstrates the domain: real-time ADS-B aircraft visualization with 6 aircraft model categories, smooth interpolation at 30fps, altitude-colored flight trails, map tile rendering, terrain elevation, and 3 distinct visual themes (day/night/retro wireframe). The native rewrite's primary value proposition is performance: Metal's instanced rendering can handle 10,000+ aircraft in 6 draw calls vs. the web version's per-object rendering bottleneck at 500 aircraft. Native macOS integration enables menu bar status items, notifications, widgets, and trackpad gestures that web cannot match.

The recommended approach uses a three-layer architecture: (1) Data Layer with actor-isolated async/await network polling, (2) Metal Rendering Layer with instanced draw calls and triple-buffered buffers, and (3) SwiftUI UI Layer bridged via NSViewRepresentable. The web version's domain logic (coordinate transforms, interpolation math, data normalization) ports directly, but the rendering architecture must be rebuilt from scratch. Metal 3 (not Metal 4) provides mature, well-documented APIs for everything needed without requiring macOS 26+ and its bleeding-edge API redesign.

Key risks center on coordinate system mismatches (WebGL NDC depth [-1,+1] vs. Metal [0,+1]), CPU/GPU synchronization (triple buffering is non-negotiable), and SwiftUI/Metal integration (state changes must not destroy the Metal view). These are all architectural decisions that must be correct from day 1 -- fixing them later requires rewrites. The research identifies 15 specific pitfalls with prevention strategies, prioritized by impact. Code signing and notarization for DMG distribution must be configured in Phase 1, not deferred to launch, to avoid blocking distribution.

## Key Findings

### Recommended Stack

The native app uses **Swift 6.2, Metal 3, SwiftUI, and zero external dependencies**. Development requires Xcode 26.2 on macOS 26 Tahoe, deploying to macOS 14 Sonoma minimum. Metal 3 (not Metal 4) is selected because Metal 4 requires macOS 26+ and introduces an entirely new API surface (MTL4-prefixed types, mandatory function descriptors, explicit argument tables) that is bleeding-edge and under-documented. Metal 3 provides everything needed: instanced rendering, compute shaders, mesh shaders, MetalFX upscaling, and terrain tessellation. Metal 4 can be adopted in a future milestone after the API stabilizes.

**Core technologies:**
- **Metal 3 + MetalKit**: Direct GPU control for instanced aircraft rendering (6 draw calls for 500 aircraft vs. 2,500+ in THREE.js). MTKView provides drawable management, depth buffer, and display link timing automatically. MSL 3.1 shaders for vertex transforms, lighting, and altitude coloring.
- **SwiftUI + Observation framework**: Declarative UI for panels, controls, and settings. `@Observable` (macOS 14+ requirement) replaces legacy ObservableObject with fine-grained property tracking. NSViewRepresentable bridges MTKView into SwiftUI layout. AppKit provides menu bar, dock integration, and keyboard shortcuts.
- **URLSession + Swift Concurrency**: Actor-isolated async/await polling for dump1090 local receiver and global APIs (airplanes.live, adsb.lol, OpenSky). AsyncStream for continuous polling. Codable for type-safe JSON parsing. No Alamofire/Moya needed for simple GET+JSON requests.
- **simd library**: Hardware-accelerated vector/matrix math with types directly compatible with Metal shaders (simd_float4x4 = MSL float4x4). Zero-cost CPU-to-GPU data transfer on Apple Silicon's unified memory.
- **UserDefaults + FileManager**: Settings persistence and cached reference data (airport CSV, airspace GeoJSON). No Core Data/SwiftData needed -- no relational queries, no concurrent writes, just key-value settings and static lookup tables.

**Critical version constraint:** macOS 14 Sonoma minimum deployment target enables `@Observable` macro and SwiftUI inspector views. macOS 13 Ventura drops out of Apple security updates late 2025, making macOS 14 a pragmatic floor.

### Expected Features

Research identified 35 distinct features across 4 priority tiers: table stakes (20 features), differentiators (8), polish (7), and anti-features (10 to explicitly avoid).

**Must have (table stakes):**
- Metal 3D aircraft rendering with 6 model categories (helicopter, small prop, regional, narrowbody jet, widebody, military) using instanced rendering
- Wireframe + solid rendering modes (retro theme uses wireframe, day/night use solid)
- Flight trails with per-vertex altitude color gradient (blue-to-red or green), configurable length (50-4000 points) and width
- Map tile ground plane with zoom levels 6-12, async tile loading, LRU cache
- Terrain elevation from Mapbox terrain-RGB tiles with displacement mesh
- Smooth position interpolation (1-5s data intervals to 60fps smooth animation with 2s delayed lerp)
- Local dump1090 + global API data sources with automatic failover
- Orbital camera (trackpad pinch zoom, two-finger rotate, drag pan)
- Aircraft selection via ray-cast hit testing with SwiftUI detail panel
- Three themes (day/night/retro) with distinct shader pipelines and color palettes
- Aircraft labels (callsign + altitude) as billboard text with LOD culling
- Airport database (78K+ from OurAirports CSV) with search autocomplete
- Statistics graphs (message rate, aircraft count over time) using SwiftUI Charts
- Settings persistence (theme, units, data source, camera position, window geometry)

**Should have (competitive differentiators):**
- Menu bar status item with aircraft count badge, mini sortable list, and quick actions (competitor ADS-B Radar uses this as primary interface)
- macOS notifications for aircraft alerts (specific callsigns, emergency squawks 7500/7600/7700, altitude/distance thresholds)
- MSAA 4x anti-aliasing (nearly free on Apple Silicon's tile-based GPU, massive visual quality improvement)
- Dock icon badge with live aircraft count
- Native trackpad gestures (pinch/rotate/scroll) that web version cannot match
- Multiple windows showing different geographic regions with shared data source
- Background data collection (app continues polling when minimized, unlike web tabs)
- Fullscreen mode and Split View with other apps

**Defer (v2+ or never):**
- Desktop widgets (WidgetKit) -- useful but non-core
- Post-processing bloom for retro glow -- nice-to-have polish
- HDR/EDR rendering on capable displays -- enhancement
- Spotlight search integration for active flights -- platform integration
- Shortcuts/App Intents for Siri automation -- advanced integration
- GPU compute interpolation -- profile CPU first, likely premature optimization
- iOS/iPadOS port -- entirely separate project with different UI/gesture model
- Recording/playback -- explicitly avoided in web version, massive scope
- Photorealistic aircraft models -- conflicts with stylized aesthetic and instanced rendering architecture

### Architecture Approach

The native app uses a **three-layer actor-isolated architecture** that is fundamentally different from the web version's single-threaded global state model. The web version uses a procedural `animate()` loop with global variables (`airplanes`, `selectedPlane`, `currentTheme`) and DOM manipulation. The native version uses actors for thread safety, value types for data models, protocol-oriented rendering, and SwiftUI's declarative UI.

**Major components:**
1. **AppState (@Observable @MainActor)** -- Central observable model holding aircraft list, selection, settings, camera state, and connection status. Published to both SwiftUI views and Metal Renderer. Replaces ~50 global variables from web version.
2. **FlightDataActor** -- Actor-isolated async polling loop with provider fallback chain (local -> airplanes.live -> adsb.lol -> OpenSky). Normalizes responses to common AircraftModel struct. Produces AsyncStream consumed by AppState.
3. **Renderer (MTKViewDelegate)** -- Owns all Metal state (device, command queue, pipeline states, buffers). Reads AppState each frame, updates instance buffers, encodes draw commands. Uses triple buffering (DispatchSemaphore with 3 ring buffers) to synchronize CPU/GPU access.
4. **MetalView (NSViewRepresentable)** -- SwiftUI bridge wrapping MTKView. Coordinator holds Renderer reference and acts as MTKViewDelegate. Isolates Metal rendering surface from SwiftUI state changes.
5. **AircraftInterpolator** -- Smooth position/rotation interpolation between 1-5s data updates to 60fps animation using 2s delayed lerp. Runs per-frame on render thread, not in network callback.
6. **MapTileManager** -- Async tile fetching with URLSession, Metal texture creation via MTKTextureLoader, LRU cache with 300 tile limit. Tiles rendered as textured quads at Y=0.
7. **TrailRenderer** -- GPU polyline rendering with per-vertex altitude color. Expands line segments into camera-facing quads in vertex shader (Metal has no native wide-line support).
8. **EnrichmentActor** -- Lazily fetches aircraft metadata (registration, type, operator, route, photo) from hexdb.io and adsbdb.com with NSCache for results.

**Data flow:** FlightDataActor polls API -> JSON decoding on background thread -> @MainActor update to AppState -> Renderer reads AppState in draw(in:) callback -> AircraftInterpolator produces per-frame positions -> Instance buffer updated -> GPU renders via drawIndexedPrimitives(instanceCount:) -> SwiftUI reads AppState for detail panel updates.

**Key architectural difference from web version:** The web version has 1 draw call per aircraft (5-8 child meshes each = 2,500+ draw calls for 500 aircraft). The native version has 1 draw call per aircraft category (6 categories = 6 draw calls for 10,000 aircraft). This is the core performance advantage that justifies the rewrite.

### Critical Pitfalls

Research identified 15 specific pitfalls. Top 5 by impact:

1. **WebGL-to-Metal coordinate system mismatch** -- THREE.js uses NDC depth [-1, +1] and counter-clockwise winding. Metal uses NDC depth [0, +1] and clockwise winding. Reusing THREE.js projection matrices verbatim causes depth corruption, inside-out geometry, and invisible rendering. **Prevention:** Build projection matrices from scratch using simd library functions for Metal's conventions. Set frontFacingWinding to .counterClockwise if reusing vertex data. Write unit test verifying a known aircraft projects correctly.

2. **Missing triple buffering for dynamic data** -- CPU and GPU run asynchronously. Writing new aircraft positions into the same buffer the GPU is reading causes torn frames, visual artifacts (vertices at 0,0,0), or deadlocks. **Prevention:** Implement triple buffering with DispatchSemaphore from day 1. Use ring of 3 buffers for all per-frame dynamic data (aircraft instances, trails, uniforms). Wait on semaphore before encoding, signal in command buffer completion handler.

3. **Network data updates on render thread** -- Processing JSON parsing (5-20ms for 200 aircraft) on the render thread exceeds the 16ms/60fps budget, causing visible stutters every poll interval. **Prevention:** All network I/O and JSON parsing on background actor. Use double-buffer pattern: network writes to staging model, render reads from current model, swap atomically at frame boundaries. Render thread never waits for network -- interpolates from cached state.

4. **SwiftUI state changes triggering Metal view recreation** -- If MTKView wrapper is in the same view hierarchy as changing UI state, SwiftUI recreates the Metal view on every state change, destroying pipeline states and causing frame drops. **Prevention:** Isolate MTKView wrapper into its own view with zero state dependencies. Communicate through shared Renderer class reference, not SwiftUI state. Use EquatableView to prevent unnecessary updates.

5. **Creating MTLRenderPipelineState objects per frame** -- Pipeline state creation involves GPU shader compilation (10-100ms). Doing this per frame or per draw call destroys frame rate. **Prevention:** Create ALL pipeline states once at initialization (likely 5 states: aircraft, trails, map tiles, labels, altitude lines). Cache in dictionary if dynamic variants needed. Use Metal function constants for shader specialization, not full recompilation.

**Additional high-impact pitfalls:**
- Autorelease pool missing in render loop (memory leak)
- Wrong GPU buffer storage mode (.shared vs .managed vs .private)
- GLSL-to-MSL shader function differences (mod vs fmod, pow vs powr, texture sampling syntax)
- Swift 6 concurrency checker conflicts with Metal's callback-based API (use MainActor.assumeIsolated in draw callbacks)
- Code signing and notarization deferred to end (blocks DMG distribution)

## Implications for Roadmap

Based on combined research, architecture dependencies, and pitfall mitigation, the recommended phase structure is:

### Phase 1: Metal Foundation + Ground Plane
**Rationale:** Everything depends on having a working Metal rendering surface with correct coordinate system. Cannot test any aircraft rendering without map reference frame. Coordinate system mismatch (Pitfall #1) must be caught immediately, not after implementing complex geometry.

**Delivers:**
- App window with Metal-backed MTKView wrapped in SwiftUI NSViewRepresentable
- Orbital camera with trackpad gestures (pinch zoom, rotate, drag pan)
- Map tile ground plane (textured quads at Y=0) with async tile loading
- Coordinate system verification (known lat/lon projects to expected screen position)

**Implements:**
- MetalView + Renderer skeleton with triple buffering (Pitfall #3 prevention)
- OrbitCamera with correct Metal projection matrices
- MapTileManager with URLSession async texture loading
- CoordinateSystem utilities (latLonToXZ, map bounds calculation)

**Avoids:**
- Coordinate system mismatch by verifying early with map tiles
- Pipeline state per-frame by creating tile pipeline once at init
- SwiftUI state destroying Metal view by isolating MetalView wrapper

**Research flag:** Standard patterns, skip phase-specific research. Metal + SwiftUI integration is well-documented.

---

### Phase 2: Data Pipeline + Aircraft Rendering
**Rationale:** Proves the core value proposition (instanced rendering performance). Must establish the network-to-GPU data flow and triple-buffered synchronization before adding complexity. This phase validates that Metal instancing works and delivers expected performance gains over THREE.js.

**Delivers:**
- Live aircraft appearing on map from dump1090 local + global APIs
- Smooth movement via interpolation (60fps from 1-5s data updates)
- 6 aircraft categories with distinct geometry (instanced rendering)
- Altitude-based coloring per aircraft

**Implements:**
- FlightDataActor with AsyncStream polling and provider fallback
- DataNormalizer for dump1090/airplanes.live/adsb.lol schemas
- AircraftModel domain model (Sendable struct)
- AircraftInterpolator with 2s delayed lerp
- Aircraft mesh geometry (vertex buffers for 6 categories)
- AircraftShaders.metal with instanced rendering
- Per-instance buffer management (position, rotation, color, scale, phase)
- AppState updates on @MainActor

**Avoids:**
- Network on render thread (Pitfall #5) by using actor isolation and double-buffer pattern
- Triple buffering mistakes (Pitfall #3) by implementing semaphore synchronization from start
- Excessive SwiftUI updates (Pitfall #14) by using snapshot approach for UI, not streaming every position

**Research flag:** Standard patterns, skip research. Instanced rendering and async networking are well-documented.

---

### Phase 3: Trails + Labels + Selection
**Rationale:** Adds visual richness and interactivity to the working aircraft rendering. Trails and labels are independent rendering passes that can be developed in parallel. Selection via hit testing enables the detail panel (table stakes feature).

**Delivers:**
- Flight trails with altitude color gradient, configurable length/width
- Aircraft labels (callsign + altitude) as billboards with LOD
- Aircraft selection via mouse click with hit testing
- SwiftUI detail panel showing selected aircraft info

**Implements:**
- TrailRenderer with GPU polyline expansion (line segments to camera-facing quads)
- TrailShaders.metal with per-vertex color interpolation
- LabelRenderer with Core Text to Metal texture conversion
- LabelShaders.metal with billboard vertex shader
- Ray-cast hit testing (screen coordinates to 3D ray, intersect aircraft bounding spheres)
- SelectedPlaneView SwiftUI panel
- EnrichmentActor for hexdb.io/adsbdb lookups

**Avoids:**
- GLSL-to-MSL shader bugs (Pitfall #8) by porting manually and testing in isolation
- Label texture memory explosion by using texture atlas at scale (>200 aircraft)
- Trail memory blowup by using ring buffer, not unbounded arrays

**Research flag:** **Needs research** for GPU polyline rendering techniques. Metal has no native wide-line support; must expand to geometry. Research best approach (quad strips vs. triangle strips, join/cap strategies).

---

### Phase 4: Terrain + Airspace + Themes
**Rationale:** Adds depth perception (terrain elevation) and regulatory context (airspace volumes). These are independent rendering systems that can be developed in parallel. Theme switching proves the shader variant architecture works.

**Delivers:**
- Terrain elevation mesh from Mapbox terrain-RGB tiles
- Airspace volumes (FAA Class B/C/D) as transparent extruded polygons
- Three themes (day solid, night solid, retro wireframe)
- Theme-specific shader pipelines and color palettes

**Implements:**
- Terrain tile decoding (RGB to elevation formula)
- Terrain mesh generation with vertex displacement and LOD
- Terrain scale linked to altitude exaggeration slider
- Airspace polygon triangulation (ear clipping) and extrusion
- Transparent rendering with depth-write disabled
- Wireframe pipeline state for retro theme
- Theme system with shader uniform updates

**Avoids:**
- Pipeline state per-frame (Pitfall #2) by creating all theme variants at init
- Depth buffer issues with transparency by rendering opaque first, then transparent with depth-write off

**Research flag:** **Needs research** for terrain mesh LOD strategies and polygon triangulation algorithms. Research efficient ear clipping or constrained Delaunay triangulation for airspace polygons.

---

### Phase 5: UI Controls + Settings + Persistence
**Rationale:** Makes the app configurable and polished. All rendering features are complete; this phase adds the control surface. Settings persistence ensures preferences survive restarts.

**Delivers:**
- Airport database (78K+ OurAirports) with search autocomplete
- SwiftUI controls (theme picker, units, altitude slider, trail toggles)
- Keyboard shortcuts with native macOS menu bar
- Statistics graphs (SwiftUI Charts for time-series)
- Settings persistence (UserDefaults + FileManager)
- Fly-to animation for airport search results

**Implements:**
- AirportDataActor with CSV loading and search indexing
- AirportSearchView with autocomplete dropdown
- ControlsView with all toggles/sliders
- SettingsStore wrapping UserDefaults
- Native menu bar with CommandGroup and CommandMenu
- GraphsView with SwiftUI Charts for message rate / aircraft count

**Avoids:**
- Blocking main thread (Pitfall #5) by loading 12.5MB airport CSV in background actor
- Excessive view updates (Pitfall #14) by throttling statistics updates to 2-second intervals

**Research flag:** Standard patterns, skip research. SwiftUI Charts and UserDefaults are well-documented.

---

### Phase 6: Native macOS Integration
**Rationale:** Delivers the differentiation that justifies going native. These features cannot exist in the web version and provide competitive advantages (ADS-B Radar competitor already has menu bar and notifications). Must be production-ready for distribution.

**Delivers:**
- Menu bar status item with aircraft count badge and mini list
- macOS notifications for aircraft alerts (callsigns, squawks, altitude/distance)
- Dock icon badge with live count
- Multiple windows with shared data source
- Code signing + notarization for DMG distribution

**Implements:**
- MenuBarExtra SwiftUI scene with independent lifecycle
- UNUserNotificationCenter with local notifications
- Alert rule system (pattern matching on callsign, squawk, altitude, distance)
- NSApp.dockTile.badgeLabel updates
- WindowGroup with shared AppState
- Hardened Runtime entitlements (com.apple.security.network.client)
- Code signing with Apple Developer account
- Notarization workflow (app -> DMG -> notarize -> staple)

**Avoids:**
- Code signing deferred to end (Pitfall #10) by setting up in Phase 1 and testing on clean Mac before beta distribution
- Notification spam by rate-limiting alert checks to 5-second intervals
- Menu bar performance issues by throttling list updates to 1-second intervals

**Research flag:** **Needs research** for notarization workflow details. Research DMG creation, signing order (frameworks first, then app, then DMG), and stapling process.

---

### Phase Ordering Rationale

**Dependency-driven ordering:**
- Phase 1 establishes coordinate system and rendering surface (all later phases depend on this)
- Phase 2 connects data to rendering (trails/labels/selection need aircraft to attach to)
- Phase 3 adds visual richness (terrain/airspace need working scene to composite into)
- Phase 4 provides depth cues (UI controls need features to control)
- Phase 5 makes it configurable (native integration needs polished base app)
- Phase 6 delivers differentiation (must be production-ready for DMG distribution)

**Pitfall mitigation sequence:**
- Coordinate system verified in Phase 1 (before complex geometry)
- Triple buffering implemented in Phase 1 (before dynamic data in Phase 2)
- Network/render separation architected in Phase 2 (before adding more data consumers)
- SwiftUI/Metal isolation enforced in Phase 1 (before adding more UI in Phase 5)
- Code signing configured in Phase 6 (with testing before distribution)

**Architectural validation points:**
- Phase 1 validates Metal + SwiftUI integration works
- Phase 2 validates instanced rendering delivers expected performance
- Phase 3 validates multi-pass rendering with transparency
- Phase 4 validates shader variant architecture for themes
- Phase 5 validates SwiftUI reactivity at scale (200+ aircraft in list)
- Phase 6 validates distribution workflow

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 3 (Trails + Labels):** GPU polyline rendering techniques. Metal has no native wide lines; research geometry expansion strategies, join/cap algorithms, and performance at 500 trails with 200 points each.
- **Phase 4 (Terrain + Airspace):** Terrain mesh LOD strategies for performance. Polygon triangulation for airspace volumes (ear clipping vs. Delaunay). Research efficient algorithms that run in <10ms for hundreds of polygons.
- **Phase 6 (Native Integration):** Notarization workflow mechanics. Research DMG signing order, stapling process, and testing on clean Mac. Gatekeeper edge cases.

**Phases with well-documented patterns (skip research):**
- **Phase 1 (Metal Foundation):** Metal + SwiftUI integration via NSViewRepresentable is standard Apple pattern with extensive documentation and examples.
- **Phase 2 (Data Pipeline):** Actor-isolated async networking and instanced rendering are well-covered in Apple docs and Metal by Example.
- **Phase 5 (UI Controls):** SwiftUI Charts, UserDefaults, and menu bar integration are standard platform features with comprehensive documentation.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| **Stack** | HIGH | Metal 3 + Swift 6.2 + SwiftUI verified against current Xcode 26.2 / macOS 26 Tahoe / macOS 14+ deployment target. All technologies are stable, shipping, and well-documented. Metal 3 backward compatibility to macOS 13 confirmed. Metal 4 deliberately avoided due to bleeding-edge status. |
| **Features** | HIGH | Full analysis of existing 5,735-line web app provides complete feature inventory. Competitor analysis (ADS-B Radar) confirms expected native features (menu bar, notifications). Apple Developer Award winner Flighty provides design reference. Feature priority derived from web version's proven value and native platform capabilities. |
| **Architecture** | HIGH | Three-layer actor-isolated architecture matches Apple's recommended patterns for Swift concurrency + Metal. NSViewRepresentable bridge is standard documented approach. Instanced rendering confirmed as correct Metal pattern for this use case. Triple buffering confirmed as required for dynamic data. Web-to-native architectural differences clearly identified. |
| **Pitfalls** | HIGH | All 15 pitfalls verified against Apple Developer Documentation, Metal Best Practices Guide, Apple Developer Forums, and authoritative community sources (Metal by Example, Kodeco). Coordinate system differences verified in multiple independent sources. Triple buffering pattern confirmed in Apple sample code. Swift 6 concurrency conflicts documented in Swift Forums. |

**Overall confidence:** HIGH

### Gaps to Address

**During Phase 3 planning (Trails + Labels):**
- **GPU polyline rendering:** Research identified this as non-standard (Metal has no native wide lines). Need to evaluate quad strip vs. triangle strip expansion, join strategies (miter vs. bevel vs. round), and cap styles. Web version uses THREE.js Line2 (geometry shader-based); Metal equivalent requires manual expansion. Research performance characteristics with 500 trails * 200 points = 100K vertices updated per frame.

**During Phase 4 planning (Terrain + Airspace):**
- **Terrain LOD:** Research confirmed need for level-of-detail system but did not specify tile subdivision strategy. Need to determine: fixed subdivision (e.g., 64x64 vertices per tile) vs. quadtree adaptive refinement. Profile memory/performance tradeoffs during implementation.
- **Airspace polygon triangulation:** Research identified ear clipping as standard algorithm but noted performance concerns with hundreds of polygons. May need to pre-triangulate during data loading rather than per-frame. Evaluate whether SwiftUI Path tessellation is sufficient or if manual implementation needed.

**During Phase 6 planning (Native Integration):**
- **Notarization edge cases:** Research covered standard workflow but noted cryptic errors are common. Plan for 2-3 day buffer before first beta release to debug signing issues. Test on completely clean Mac (new user account, not development machine) before distributing.

**Deferred to implementation (not blocking):**
- **Trail persistence:** Web version stores trails in IndexedDB for restoration. Native version should use SQLite/SwiftData but exact schema and query patterns deferred until implementing trail system in Phase 3.
- **Multi-window coordination:** Phase 6 includes multiple windows with shared data, but exact state synchronization mechanism (shared AppState singleton vs. separate AppState per window with shared DataManager) deferred to implementation.

## Sources

### Primary (HIGH confidence)
- **Apple Developer Documentation:** Metal API reference, MTKView, Metal Best Practices Guide, Swift Concurrency, SwiftUI, Observation framework, URLSession async/await, simd library, Core Spotlight, WidgetKit, App Intents, UNUserNotificationCenter, code signing, notarization
- **Apple WWDC Sessions:** Metal rendering (2019-2025), SwiftUI performance (2023), Observation framework (2023), App Intents (2025), Widgets (2025)
- **Metal by Example:** Instanced rendering, modern Metal app structure, vertex descriptors, mesh shaders, GPU-driven rendering
- **Kodeco Metal by Tutorials:** Rendering pipeline, coordinate spaces, performance optimization
- **Existing web app:** `/Users/mit/Documents/GitHub/airplane-tracker-3d/airplane-tracker-3d-map.html` (5,735 lines) -- complete feature inventory, domain logic, interpolation math, data schemas

### Secondary (MEDIUM confidence)
- **MetalShapes Blog:** OpenGL-to-Metal projection matrix differences
- **JAMESCUBE:** Metal & OpenGL coordinate systems comparison
- **Swift Forums:** Swift concurrency + Metal integration, Sendable conflicts with Metal callbacks
- **TrozWare:** SwiftUI for Mac 2025 best practices
- **SwiftLee:** @Observable performance, default actor isolation in Swift 6.2, URLSession async/await
- **Medium articles:** Metal + SwiftUI integration, AsyncStream for polling, SIMD optimization
- **GitHub repos:** Metal sample projects, NSView input handling, MetalViewUI wrapper

### Tertiary (LOW confidence, needs validation)
- **GPU polyline rendering:** Community articles on drawing lines in Metal (Matt DesLauriers, Patricio Gonzalez Vivo) describe WebGL techniques that need adaptation to Metal
- **ikyle.me blog:** Metal texture tiling for large panoramas (2026) -- very recent, may contain unverified techniques
- **Metal 4 sources:** Low End Mac overview, Apple Metal 4 announcement -- Metal 4 is bleeding-edge; specific features may change before stable release

---
*Research completed: 2026-02-08*
*Ready for roadmap: yes*
