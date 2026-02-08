# Feature Landscape

**Domain:** Real-time 3D flight visualization -- native macOS Metal app (rewrite from web)
**Researched:** 2026-02-08
**Confidence:** HIGH (existing web app source fully analyzed, Metal/macOS APIs verified against Apple official docs, competitor apps verified via App Store listings)

---

## Context

This document maps the feature landscape for rewriting the existing web-based THREE.js flight tracker (5735-line single HTML file) as a native macOS application using Swift, Metal, and SwiftUI. The focus is on:

1. Which existing web features translate to native and at what complexity
2. What native-only features become possible and justify the rewrite
3. What to explicitly avoid building

The existing web app has these proven features: 6 aircraft model categories (jet, widebody, helicopter, small prop, military, regional), wireframe + solid rendering modes, 3 themes (day/night/retro), Line2 fat-line trails with per-vertex altitude coloring, map tile ground plane (10x10 grid, zoom 6-12), terrain elevation (Mapbox terrain-RGB), airspace volumes (FAA Class B/C/D), airport database (78K+ from OurAirports CSV), 3D text airport labels, aircraft enrichment (hexdb.io/adsbdb.com), follow mode, statistics with IndexedDB, coverage heatmap, smooth interpolation (2s delayed lerp at 30fps), dual data sources (local dump1090 + global APIs with fallback).

---

## Table Stakes

Features users expect. Missing any of these = product feels like a downgrade from the web version.

### Core 3D Rendering

| Feature | Why Expected | Complexity | Notes |
|---------|-------------|------------|-------|
| Metal 3D aircraft rendering with 6 model categories | Web version already differentiates helicopters, small props, jets, widebodies, military, and regional aircraft with distinct geometry. Regression is unacceptable. | Med | Use instanced rendering: one shared vertex buffer per aircraft type, one draw call per type. Instance buffer carries per-aircraft position (float3), rotation (float), color (float4), scale (float). Metal handles 10K+ instances trivially. |
| Wireframe + solid rendering modes | Retro theme uses wireframe (LineSegments in THREE.js), day/night use solid Phong-shaded meshes. Both modes are essential to the app's identity. | Med | Two render pipeline states: one with fill mode `.lines`, one with `.fill`. Retro theme selects wireframe pipeline. Alternatively, use geometry with edge extraction for wireframe. |
| Altitude-based coloring per aircraft | Aircraft change color by altitude (retro: green gradient, day/night: green-yellow-orange-pink ramp). Visual cue users rely on. | Low | Per-instance color in instance buffer. Compute color on CPU during interpolation update, write to instance buffer. |
| Glow sprites on aircraft | Each aircraft has a pulsing glow sprite (retro: green, day/night: altitude-colored). Provides visibility at distance. | Low | Render billboarded quads with additive blending. One draw call for all glow sprites using instancing. |
| Position light animation | Blinking nav lights on aircraft with randomized phase. Adds life to the scene. | Low | Sin-wave brightness in fragment shader using per-instance phase offset. No CPU work per frame. |
| Rotor/propeller animation | Helicopter main/tail rotors and prop plane propellers spin. Web version uses 0.7 rotations/second. | Low | Per-instance rotation angle updated each frame. Compound transform in vertex shader. |

### Flight Trails

| Feature | Why Expected | Complexity | Notes |
|---------|-------------|------------|-------|
| Flight trails with per-vertex altitude color | Signature visual feature. Trails up to 4000 points with blue-to-red altitude gradient (day/night) or green gradient (retro). | Med-High | GPU polyline rendering: expand line segments into camera-facing quads in vertex shader. Metal has no native wide-line support, so this must be implemented as triangle strips. Per-vertex color stored in trail vertex buffer. |
| Configurable trail length and width | Web version has slider for 50-4000 points and 1-5px width. | Low | Trail length caps the ring buffer. Width is a uniform passed to the polyline vertex shader. |
| Trail LOD by camera distance | Web version reduces rendered trail points for distant aircraft (40/100/300 point limits by distance tier). | Low | Compute visible point count per aircraft based on distance. Set draw range per trail. |
| Trail persistence across data updates | Trails accumulate over time, not just between single API responses. Web version stores trail points in IndexedDB for restoration. | Med | Store trail history in SQLite (SwiftData). Restore trails when aircraft reappears. Ring buffer per aircraft. |

### Map & Terrain

| Feature | Why Expected | Complexity | Notes |
|---------|-------------|------------|-------|
| Map tile ground plane | Aircraft positions are meaningless without geographic context. Web version renders 10x10 grid of OSM/CartoDB tiles. | Med | Download tiles via URLSession, create Metal textures asynchronously. Render as textured quads on Y=0 plane. Use Metal's MTLIOCommandQueue for fast async texture upload on Apple Silicon. Tile cache with LRU eviction (300 tile limit in web version). |
| Map zoom (level 6-12) | Users need to zoom out for overview and zoom in for local detail. | Low | Recompute tile grid on zoom change. Smooth zoom transition with easeInOutCubic (web version uses 300ms). |
| Map pan (arrow keys + drag) | Navigate to different geographic regions. | Low | Translate center coordinates, reload tile grid. Smooth pan transitions. |
| Terrain elevation mesh | Mapbox Terrain-RGB tile decoding with vertex displacement. Mountains visible, valleys lower. | Med | Decode terrain-RGB PNGs: elevation = (R*256 + G + B/256) - 32768 meters. Generate displaced mesh per tile. LOD: more vertices near camera, fewer distant. Web version uses TERRAIN_SCALE_FACTOR with altitude-synchronized scaling. |
| Terrain scale linked to altitude exaggeration | Web version scales terrain Z proportionally to altitude multiplier so terrain and aircraft altitudes stay in sync. | Low | Single uniform controls both aircraft Y position and terrain displacement magnitude. |

### Camera Controls

| Feature | Why Expected | Complexity | Notes |
|---------|-------------|------------|-------|
| Orbital camera (rotate, zoom, pan) | Standard 3D navigation. Web version uses mouse drag for orbit, scroll for zoom. | Low | Spherical coordinate camera: (angle, distance, height). Trackpad pinch = zoom (MagnifyGesture), two-finger rotate = orbit (RotateGesture), two-finger drag = pan (DragGesture). More intuitive than web version's mouse-only controls. |
| Camera reset | Return to default view. Web version has 'R' key. | Low | Animate camera parameters back to defaults over 300ms. |
| Auto-rotate | Slow orbit for ambient display mode. Web version increments angle by 0.002/frame. | Low | Toggle flag, increment camera angle each frame. |
| Follow mode | Lock camera to selected aircraft. Camera tracks aircraft position. | Low | Each frame, if follow active, set camera target = selected aircraft world position. Smooth tracking with lerp. |

### Data Layer

| Feature | Why Expected | Complexity | Notes |
|---------|-------------|------------|-------|
| Local dump1090 data polling | Core use case: users with their own ADS-B receiver. Polls /dump1090/data/aircraft.json at 1 second intervals. | Low | URLSession with Timer. Parse JSON with Codable. |
| Global API data (airplanes.live + adsb.lol) | Users without local receivers need global coverage. 250nm radius queries. 5-second polling. Automatic failover between providers. | Med | DataSource protocol with provider chain. Try primary, fall back to secondary on failure. Normalize both API responses to common AircraftState struct. |
| Smooth position interpolation (60fps) | Aircraft positions arrive every 1-5 seconds. Must animate smoothly between updates. Web version uses 2-second delayed lerp with angle interpolation for heading. | Med | Position buffer per aircraft: store 2+ timestamped samples. Each frame, lerp between samples based on current time minus delay. Use lerpAngle for heading (handles 359->1 degree wraparound). Critical for visual quality -- jerky movement kills the experience. |
| Aircraft enrichment API | Registration, type, operator, route, photo from hexdb.io and adsbdb.com. | Med | Async URLSession calls triggered on aircraft selection. NSCache for results. Display in SwiftUI detail panel. Rate-limit to 1 request/second. |

### User Interface (SwiftUI)

| Feature | Why Expected | Complexity | Notes |
|---------|-------------|------------|-------|
| Aircraft detail panel | Right panel showing callsign, altitude, speed, track, vert rate, squawk, position, enriched data (registration, type, operator, route), aircraft photo, external links. | Med | SwiftUI inspector panel (.inspector modifier) or NavigationSplitView detail column. Reactive updates via @Observable/@Published. |
| Info panel (aircraft count, last update, center coords, map zoom) | Left panel with live statistics. Always visible. | Low | SwiftUI overlay on Metal view. Updates every frame or on data change. |
| Controls bar | Bottom bar with data source selector, theme picker, unit selector, toggles (labels, trails, terrain, airspace, graphs, stats), trail length/width sliders, altitude exaggeration slider. | Med | SwiftUI toolbar or bottom sheet. Many controls -- organize into collapsible groups. |
| Airport search bar | Top-center search field with autocomplete dropdown. Search by IATA, ICAO, name, municipality. | Med | SwiftUI searchable() modifier or custom TextField with results popover. Load OurAirports CSV at launch, index for fast filtering. |
| Keyboard shortcuts overlay | '?' key shows shortcut reference. Web version has comprehensive list. | Low | SwiftUI sheet with shortcut grid. |
| Settings persistence | Save all toggle/slider states, theme, units, data source, window position. | Low | @AppStorage for simple values. UserDefaults for complex objects. |
| Unit switching (imperial/metric) | Feet/knots vs meters/km/h. | Low | Formatting helper functions. No rendering changes. |

### Visualization Features

| Feature | Why Expected | Complexity | Notes |
|---------|-------------|------------|-------|
| Three themes (day, night, retro) | Visual identity of the app. Retro 80s wireframe is the default and most distinctive. | Med | Theme struct with: sky color, ground tint, aircraft pipeline (wireframe/solid), trail color function, glow color, UI accent colors. Apply via environment object. Shader uniforms change per theme. |
| Aircraft labels (callsign + altitude) | Floating text above each aircraft. LOD: hidden beyond 700 units, scaled between 400-700. | Med | SDF (signed distance field) text for resolution-independent rendering. Or: render text to texture atlas via CoreText, billboard quad per aircraft. Instanced rendering for all labels. |
| Airport 3D labels | Ground-standing text for nearby large/medium airports. Web version uses TextGeometry. | Med | Same text rendering system as aircraft labels but positioned on ground plane at airport coordinates. Show within configurable radius. |
| Altitude line (dashed vertical) | Dashed line from aircraft to ground showing altitude reference. | Low | Two-vertex line per aircraft with dashed line shader. Update endpoints each frame. Can be instanced. |
| Airspace volumes (Class B/C/D) | Semi-transparent extruded polygons for controlled airspace. FAA GeoJSON data. | High | Triangulate airspace boundary polygons (ear clipping or similar), extrude between floor and ceiling altitudes. Transparent material with depth-write disabled. Render order by airspace class. |
| Coverage heatmap | 20x20 grid showing where aircraft have been detected. | Low | Small Metal texture (20x20) or SwiftUI Canvas. Accumulate aircraft positions into grid cells. |
| Statistics graphs (message rate, aircraft count, signal level) | Time-series sparkline graphs with selectable periods (1h-48h). | Med | SwiftUI Charts framework. Store time-series data in SQLite/SwiftData. Much cleaner than web version's manual canvas rendering. |
| Altitude distribution bars | Horizontal bar chart showing aircraft count in altitude bands. | Low | SwiftUI view with proportional bars. Updates every 2 seconds. |
| Top airlines list | Ranked list of most common operators/callsign prefixes. | Low | SwiftUI List. Accumulate from observed callsigns. |

---

## Differentiators

Features that set the native app apart and justify the rewrite. Not expected for parity, but these make the native version clearly superior.

### Metal Rendering Advantages

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Single-draw-call instanced rendering | Web version creates individual THREE.Group per aircraft (5-8 child meshes each). At 500 aircraft = 2500-4000 draw calls. Metal version: 6 draw calls total (one per aircraft type). Handles 10K+ aircraft at 60fps. | Med | Core architectural advantage. Instance buffer (position, rotation, color, scale, phase) updated each frame. drawIndexedPrimitives with instanceCount. This is the primary performance justification for the rewrite. |
| MSAA (4x multi-sample anti-aliasing) | Web version has aliased jagged edges. Metal MSAA on Apple Silicon is nearly free (tile-based deferred rendering resolves MSAA in on-chip memory). | Low | Set MTKView.sampleCount = 4. Single config change, dramatic visual improvement. Zero performance cost on Apple Silicon. |
| GPU-driven frustum culling | Compute pass tests each aircraft against camera frustum before rendering. In dense airspaces (1000+ aircraft), this prevents wasted vertex/fragment work for off-screen aircraft. | Med | Compute shader: test bounding sphere against 6 frustum planes. Write visible indices to indirect argument buffer. Render pass uses executeIndirect. |
| HDR/EDR glow effects | Extended Dynamic Range for vivid retro green glow and altitude colors. Apple Silicon displays natively support EDR values > 1.0. | Low-Med | MTKView with .rgba16Float pixel format, wantsExtendedDynamicRangeContent = true. Glow sprites render with values > 1.0 for bloom-like brightness without post-processing. |
| Post-processing bloom | Soft glow around bright objects (position lights, retro glow). Web version fakes this with transparent sprites. | Med | Render scene to offscreen texture. Threshold bright pixels, gaussian blur, composite additively. Two compute passes + one render pass. Significantly enhances retro theme. |

### Native macOS Integration

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Menu bar status item | Always-visible aircraft count in menu bar. Quick-glance monitoring. Competitor ADS-B Radar uses this as their primary interface -- proves the concept works. | Low-Med | SwiftUI MenuBarExtra scene. Show aircraft count badge, mini sortable aircraft list with altitude/heading, quick actions (open main window, toggle data source, take screenshot). Can run independently of main window. |
| macOS notifications for aircraft alerts | Background alerting when specific callsigns, emergency squawks (7500/7600/7700), altitude thresholds, or registration patterns appear. | Med | UNUserNotificationCenter with local notifications. Define alert rules in settings (callsign match, squawk code, altitude range, distance threshold). Background polling continues when app is minimized. ADS-B Radar already offers this -- competitive requirement. |
| Dock icon badge with live count | Glanceable aircraft count on dock icon without opening the app. | Low | NSApp.dockTile.badgeLabel = String(count). One line of code, meaningful value. |
| Native macOS menu bar (File, Edit, View, Window) | Proper macOS menus with Preferences (Cmd+,), View toggles, Window management. Feels like a real Mac app, not a web page. | Low | SwiftUI .commands() modifier with CommandGroup and CommandMenu. Map existing keyboard shortcuts to menu items. Standard expectations: Cmd+W closes window, Cmd+Q quits, Cmd+F searches. |
| Trackpad gesture controls | Two-finger pinch zoom, two-finger rotate orbit, scroll pan. Natural macOS trackpad UX that web version cannot match. | Low | SwiftUI MagnifyGesture, RotateGesture, DragGesture mapped to camera parameters. Inertial scrolling for smooth pan deceleration. This alone justifies going native for trackpad users. |
| Fullscreen + Split View | True macOS fullscreen with menu bar auto-hide. Split View with other apps (e.g., terminal showing dump1090 output alongside the tracker). | Low | Free from NSWindow/SwiftUI. Just ensure layout adapts to different aspect ratios. |
| Multiple windows | Open several windows showing different geographic regions simultaneously. Each window has independent center coordinates and zoom but shares the same data feed. | Med | SwiftUI WindowGroup. Shared @Observable data layer. Each window has own camera state and map center. Useful for monitoring multiple airports. |
| Share sheet integration | Share current view as screenshot or share flight details as formatted text. | Low | ShareLink in SwiftUI. Render Metal view to NSImage via drawable snapshot. Format flight details as rich text. |
| Desktop Widgets (WidgetKit) | Small/medium/large desktop widgets showing: aircraft count, nearest aircraft info, coverage statistics, mini radar snapshot. | Med | WidgetKit timeline provider refreshing every 5-15 minutes. Static content (no live Metal rendering in widgets), but can include rendered mini-map images and formatted stats. |
| Spotlight search integration | Search for active flights, airports, or aircraft registrations directly from macOS Spotlight. | Med | Core Spotlight: index active flights as CSSearchableItem with callsign, hex, type as searchable attributes. When user taps result, open app and select/fly-to that item. Useful for quick lookups without switching to the app. |
| Shortcuts / App Intents | Siri and Shortcuts automation: "How many aircraft are tracked?" "Show flights near JFK." "Take a screenshot of the tracker." | Med-High | App Intents framework. Define: GetAircraftCount, SearchFlights(query), FlyToAirport(code), CaptureScreenshot, GetFlightDetails(callsign). Apple is pushing App Intents heavily in 2025-2026 -- good platform alignment. |
| Drag and drop | Drop text (hex code, callsign, airport code) onto the app to search/fly-to. | Low | SwiftUI .dropDestination() modifier. Parse dropped text. Quick interaction for power users. |
| Handoff (future) | Start tracking on Mac, continue on iPhone/iPad when iOS companion app exists. | Med | NSUserActivity with geographic context. Requires future iOS app. Do not build yet but design data model to support it. |

### Data & Performance Advantages

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| SQLite/SwiftData persistence | Web version uses IndexedDB (limited queries, no schema, browser-dependent). Native gets proper relational database with migrations, efficient range queries, and automatic iCloud sync via CloudKit. | Med | SwiftData models: TrailHistory (hex, points, lastSeen), FlightStats (timestamp, messageRate, aircraftCount, signalLevel), AircraftCache (hex, registration, type, operator, fetchDate), AlertRule (type, pattern, active). |
| Background data collection | macOS apps are not suspended when minimized (unlike iOS or browser tabs). App continues polling and accumulating data in background. Web version stops rendering when tab is hidden. | Low | Reduce poll frequency when not frontmost (e.g., 5s instead of 1s). Continue writing to SQLite. Resume full-speed rendering when brought to front. |
| Efficient memory with ARC + value types | Web version fights JavaScript garbage collection causing frame drops. Native uses deterministic ARC for reference types and stack-allocated value types for hot-path data. | Low | Use structs for AircraftState, TrailPoint, MapTile. simd_float3 for positions. Metal buffers with .storageModeManaged. No GC pauses. |
| Multi-window shared data | Multiple windows observe the same data source. No duplicate API calls. Changes in one window (e.g., theme switch) can optionally propagate to others. | Med | Shared actor or @Observable singleton for DataManager. Windows subscribe to same state. Data fetched once, displayed in multiple views. |
| Launch-time performance | Web version loads THREE.js library, CSV airport data, fonts, and tiles sequentially. Native app: Metal pipeline compiles at build time, airport data can be bundled as pre-indexed binary, shaders are precompiled to GPU-specific binary. | Low | .metallib compiled at build time. Airport data as bundled asset. Launch to first aircraft render in < 1 second vs. 3-5 seconds for web version. |

---

## Anti-Features

Features to explicitly NOT build. These are traps that waste effort, harm the product, or miss the point of going native.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| SceneKit or RealityKit for 3D rendering | Higher-level 3D frameworks add abstraction overhead, limit control over draw calls, and prevent the instanced rendering architecture that justifies this rewrite. SceneKit's per-node rendering model is essentially what THREE.js does -- same problem. | Raw Metal + MetalKit. MTKView with custom render/compute pipelines. Full control over GPU work submission. |
| MapKit for the 3D map view | MapKit renders its own map into its own layer. Cannot composite with custom Metal 3D rendering. Cannot overlay thousands of instanced aircraft or custom trail geometry. Different coordinate systems. | Custom tile rendering in Metal. Download standard slippy map tiles with URLSession, render as textured ground-plane quads in the same Metal render pass as aircraft. |
| WebView (WKWebView) for any UI | Defeats the purpose of going native. WebViews have their own process, different rendering pipeline, different input handling. Mixing web and native UI is a maintenance nightmare. | Pure SwiftUI for all panels, controls, and overlays. SwiftUI inspector, toolbar, sidebar, charts -- all native. |
| iOS/iPadOS port in Phase 1 | Touch vs. trackpad UX is fundamentally different. Metal works on both, but UI layout, gesture handling, and platform integration (menu bar, widgets, notifications) are completely different. Splitting focus guarantees both versions ship half-baked. | macOS first, macOS only. Share data layer code via Swift package when iOS port starts. Separate UI layer. |
| Photorealistic aircraft models (glTF/OBJ) | Loading detailed 3D models for 1000+ aircraft requires per-model GPU memory, prevents instanced rendering (all instances must share geometry), and conflicts with the stylized wireframe/simple-solid aesthetic. Asset pipeline complexity for loading, converting, and LOD-ing 3D model formats is enormous. | Keep procedural geometry (cones, cylinders, boxes). Match web version's style. Instanced rendering requires all instances of a type to share one vertex buffer. |
| Custom map tile server | Massive infrastructure to host, cache, and serve map tiles. Existing free tile servers (OpenStreetMap, CartoDB, Stamen, ESRI) are reliable and fast. | Use existing public tile servers. Cache tiles locally with URLCache or disk cache. |
| Touch Bar support | Apple discontinued Touch Bar on all current Mac models. No Mac sold since late 2023 includes one. Code would serve zero new users. | Skip entirely. Allocate effort to menu bar, widgets, and Spotlight instead. |
| Real-time audio (engine sounds, ATC) | Enormous scope: spatial audio engine, audio streaming, content sourcing/licensing, volume controls, performance impact. Zero overlap with visual tracking features. | Limit audio to macOS notification sounds for aircraft alerts. Standard UNNotificationSound. |
| Machine learning flight prediction | Training data collection, model selection, inference pipeline, validation against actual paths. Research project, not product feature. | Simple linear extrapolation: extend a dashed line from aircraft's current position along heading at current speed. No ML needed. |
| Electron / Catalyst wrapper | Electron = web version with more overhead. Catalyst = UIKit-first, second-class Mac citizen. Both defeat the purpose of native Metal rendering and macOS integration. | Pure Swift + Metal + SwiftUI. Purpose-built for macOS. |
| Recording and playback | 6-hour recording at 1fps for 500 aircraft = massive storage. Playback UI (timeline, scrubbing, speed controls) is essentially building a media player. The web version explicitly deferred this as an anti-feature. | Long trail durations (up to 4000 points at ~100ms intervals = ~7 minutes) provide historical context without playback infrastructure. |

---

## Feature Dependencies

```
[Data Source Protocol]
    |
    +-> [Aircraft Data Buffer] -- stores timestamped position samples
    |     |
    |     +-> [Interpolation System] -- lerp positions/headings each frame
    |     |     |
    |     |     +-> [Instance Buffer Writer] -- writes interpolated data to GPU buffer
    |     |     |     |
    |     |     |     +-> [Instanced Aircraft Rendering] -- 6 draw calls (one per type)
    |     |     |     +-> [Glow Sprite Rendering] -- 1 instanced draw call
    |     |     |     +-> [Aircraft Label Rendering] -- instanced billboards
    |     |     |     +-> [Altitude Line Rendering] -- instanced dashed lines
    |     |     |
    |     |     +-> [Trail Point Collection] -- ring buffer per aircraft
    |     |     |     |
    |     |     |     +-> [Trail Vertex Buffer] -- GPU polyline geometry
    |     |     |     +-> [Trail SQLite Persistence] -- restore on reappear
    |     |     |
    |     |     +-> [Aircraft Detail Panel] -- SwiftUI reads current values
    |     |
    |     +-> [Aircraft Enrichment] -- async API lookup by hex
    |     |
    |     +-> [Alert System] -- scans incoming data against rules
    |           |
    |           +-> [macOS Notifications]
    |           +-> [Menu Bar Badge Update]
    |
    +-> [Statistics Accumulator] -- counts, averages, distributions
          |
          +-> [SwiftUI Charts] -- time-series graphs
          +-> [Coverage Heatmap] -- 20x20 grid texture
          +-> [Dock Badge] -- NSApp.dockTile.badgeLabel

[Map Tile System]
    |
    +-> [Tile Fetcher] -- URLSession + disk cache
    |     |
    |     +-> [Metal Texture Upload] -- async MTLTexture creation
    |           |
    |           +-> [Ground Plane Rendering] -- textured quads at Y=0
    |
    +-> [Terrain System] -- Mapbox terrain-RGB decode
    |     |
    |     +-> [Terrain Mesh Generation] -- displaced vertices
    |     +-> [Terrain Scale Sync] -- linked to altitude exaggeration
    |
    +-> [Airport Database] -- OurAirports CSV load + index
          |
          +-> [Airport Labels] -- SDF text at airport positions
          +-> [Airport Search] -- SwiftUI searchable() with autocomplete
          +-> [Fly-To Animation] -- smooth camera + map center transition

[Camera System]
    |
    +-> [Trackpad Gestures] -- MagnifyGesture, RotateGesture, DragGesture
    +-> [Keyboard Controls] -- menu bar mapped shortcuts
    +-> [Follow Mode] -- target = selected aircraft
    +-> [Auto-Rotate] -- constant angle increment

[Theme System]
    |
    +-> [Render Pipeline Selection] -- wireframe vs. solid
    +-> [Shader Uniforms] -- sky color, ground tint, trail palette
    +-> [SwiftUI Appearance] -- accent colors, backgrounds, text colors

[Settings Persistence] -- @AppStorage / UserDefaults
    |
    +-> All toggle/slider/theme/unit states
    +-> Window position + size (NSWindow restoration)
    +-> Last data source + center coordinates + zoom level

[Menu Bar Status Item] -- independent lifecycle from main window
    +-> [Aircraft Count Badge]
    +-> [Mini Aircraft List]
    +-> [Quick Actions] -- open window, switch source, screenshot

[WidgetKit] -- separate target, shared data via App Group
    +-> [Aircraft Count Widget]
    +-> [Stats Summary Widget]
```

### Critical Path

The minimum sequence to get a visible, working application:

1. Metal render pipeline + MTKView in SwiftUI window
2. Data source polling + JSON parsing
3. Instance buffer + instanced aircraft rendering (even one type)
4. Camera system with trackpad gestures
5. Map tile rendering (textured ground plane)
6. Interpolation system (smooth movement)
7. Aircraft selection (color picking) + detail panel

Everything else builds on this foundation.

---

## MVP Recommendation

### Phase 1: Core Metal Rendering (Proves Architecture)

Prioritize these -- they validate that Metal instanced rendering works and outperforms the web version:

1. **Metal render pipeline** -- MTKView wrapped in NSViewRepresentable, basic scene with clear color
2. **Instanced aircraft rendering** -- shared geometry per type, instance buffer with position/rotation/color, one draw call per aircraft category
3. **Map tile ground plane** -- async tile download, Metal texture creation, textured quad grid
4. **Data source polling** -- local dump1090 + global API with DataSource protocol
5. **Smooth interpolation** -- position buffer with 2-second delayed lerp, 60fps updates
6. **Camera controls** -- trackpad pinch/rotate/drag mapped to spherical camera
7. **Aircraft selection** -- color-pick render pass (render aircraft with unique ID colors to offscreen texture, read pixel on click)
8. **Aircraft detail panel** -- SwiftUI inspector showing flight data
9. **Theme system** -- retro wireframe + day solid as minimum two modes

### Phase 2: Feature Parity with Web Version

10. **Flight trails** -- GPU polyline rendering, per-vertex altitude color, configurable length/width
11. **Aircraft labels** -- billboarded text via CoreText texture atlas or SDF
12. **Airport database + search** -- CSV loading, searchable() autocomplete, fly-to animation
13. **Airport 3D labels** -- ground-positioned text for nearby airports
14. **Terrain elevation** -- Mapbox terrain-RGB displacement mesh
15. **Night theme** -- third theme variant
16. **Settings persistence** -- @AppStorage for all state
17. **Keyboard shortcuts** -- native macOS menu bar integration with Cmd key combos
18. **Statistics panel** -- SwiftUI Charts for time-series, altitude distribution
19. **Aircraft enrichment** -- hexdb.io/adsbdb.com lookup with cache
20. **Airspace volumes** -- FAA Class B/C/D transparent extruded polygons

### Phase 3: Native Advantages (Justifies the Rewrite)

21. **Menu bar status item** -- aircraft count, mini list, quick actions
22. **macOS notifications** -- alert rules for callsigns, squawks, altitudes
23. **Dock icon badge** -- live aircraft count
24. **MSAA** -- 4x anti-aliasing (one-line config)
25. **Coverage heatmap** -- Metal texture or SwiftUI Canvas
26. **Multiple windows** -- independent map regions, shared data
27. **Follow mode improvements** -- smooth camera tracking with velocity prediction
28. **Background data collection** -- continue polling when minimized

### Phase 4: Polish & Platform Integration

29. **Desktop Widgets (WidgetKit)** -- aircraft count, stats summary
30. **Post-processing bloom** -- soft glow for retro theme
31. **HDR/EDR rendering** -- vivid colors on capable displays
32. **Spotlight integration** -- search active flights from Spotlight
33. **Share sheet** -- screenshot and flight detail sharing
34. **Shortcuts / App Intents** -- Siri automation
35. **Drag and drop** -- drop hex/callsign/airport code

### Defer Indefinitely

- **GPU compute interpolation** -- CPU lerp is fast enough for < 5000 aircraft. Profile first.
- **Metal 3 mesh shader trails** -- Complex, requires M1+, standard polylines work fine.
- **Handoff** -- Requires iOS companion app. Way out of scope.
- **iOS port** -- Different project, different UI, different gesture model.

---

## Competitive Landscape

### ADS-B Radar (macOS, $9.99) -- Primary Competitor

Native macOS app. Menu bar-first. 2D radar visualization.

**Features to match:**
- Menu bar aircraft radar (their signature -- must match or exceed)
- Background notifications for callsigns, squawks, altitudes, distance
- SQLite flight logging with historic flight paths
- Weather overlays (stretch goal)
- 7-day statistics graphs
- Polar plot visualization

**Our differentiator:** Full 3D visualization with terrain, trails, and multiple aircraft model types. ADS-B Radar is 2D radar-style. Our retro wireframe 3D aesthetic is unique in the market. Multiple themes vs. their single style.

### Flighty (iOS/macOS, subscription) -- Design Reference

Apple Design Award winner. Not a direct competitor (personal flight tracking, not ADS-B enthusiast visualization), but study their design patterns:
- Exceptional SwiftUI implementation
- Live Activities / Dynamic Island
- Airport signage-inspired design language
- "25-hour where's my plane" feature

**Lesson to apply:** Invest in SwiftUI design quality. The native app should feel premium and Mac-native, not like a web app wrapper.

### Flightradar24 (web/iOS, freemium) -- Awareness Competitor

Dominant flight tracker globally. Web-based 3D mode exists but is not a native app.

**Our differentiator:** Native Metal performance, local ADS-B receiver support, retro aesthetic, no subscription required, open data sources.

---

## Sources

### Official Apple Documentation (HIGH confidence)
- [Metal Overview](https://developer.apple.com/metal/)
- [Metal Sample Code](https://developer.apple.com/metal/sample-code/)
- [MTKView Documentation](https://developer.apple.com/documentation/metalkit/mtkview)
- [Load Resources Faster with Metal 3 (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/10104/)
- [Transform Geometry with Metal Mesh Shaders (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/10162/)
- [Modern Rendering with Metal (WWDC19)](https://developer.apple.com/videos/play/wwdc2019/601/)
- [Optimize GPU Renderers with Metal (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10127/)
- [MagnifyGesture](https://developer.apple.com/documentation/swiftui/magnifygesture)
- [NSMagnificationGestureRecognizer](https://developer.apple.com/documentation/appkit/nsmagnificationgesturerecognizer)
- [NSPanGestureRecognizer](https://developer.apple.com/documentation/appkit/nspangesturerecognizer)
- [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [Core Spotlight](https://developer.apple.com/documentation/corespotlight)
- [App Intents](https://developer.apple.com/documentation/AppIntents/app-intents)
- [WidgetKit](https://developer.apple.com/documentation/widgetkit)
- [Inspectors in SwiftUI (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10161/)
- [What's New in Widgets (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/278/)
- [Develop for Shortcuts and Spotlight with App Intents (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/260/)

### Community & Tutorial Sources (MEDIUM confidence)
- [Metal by Example: Instanced Rendering](https://metalbyexample.com/instanced-rendering/)
- [Metal by Example: Mesh Shaders and Meshlet Culling](https://metalbyexample.com/mesh-shaders/)
- [Kodeco: GPU-Driven Rendering](https://www.kodeco.com/books/metal-by-tutorials/v3.0/chapters/26-gpu-driven-rendering)
- [Drawing Lines is Hard (GPU polyline techniques)](https://mattdesl.svbtle.com/drawing-lines-is-hard)
- [Instanced Line Rendering (polyline via instancing)](https://wwwtyro.net/2019/11/18/instanced-lines.html)
- [SwiftUI for Mac 2025 (TrozWare)](https://troz.net/post/2025/swiftui-mac-2025/)
- [Metal View for SwiftUI (NSViewRepresentable wrapping)](https://medium.com/@giikwebdeveloper/metal-view-for-swiftui-93f5f78ec36a)
- [MetalViewUI: SwiftUI wrapper for MTKView](https://github.com/AlessandroToschi/MetalViewUI)
- [GPU Tilemap Rendering with Single Draw Call](https://blog.paavo.me/gpu-tilemap-rendering/)
- [Metal Texture Tiling for Large Panoramas (2026)](https://ikyle.me/blog/2026/metal-texture-tiling)

### Competitor Analysis (HIGH confidence)
- [ADS-B Radar macOS App](https://adsb-radar.com/)
- [ADS-B Radar App Store Listing](https://apps.apple.com/us/app/ads-b-radar/id1538149835?mt=12)
- [Flighty](https://flighty.com)
- [Behind the Design: Flighty (Apple Developer)](https://developer.apple.com/news/?id=970ncww4)
- [Flightradar24](https://www.flightradar24.com/how-it-works)

### Existing Web App Analysis (HIGH confidence)
- Full source code review of `airplane-tracker-3d-map.html` (5735 lines)
- Verified features: 6 aircraft categories with distinct geometry, wireframe + solid modes, Line2 fat-line trails with per-vertex color, 3 themes, 10x10 map tile grid, terrain elevation (Mapbox terrain-RGB), airspace volumes (FAA GeoJSON), airport database (OurAirports 78K+), 3D TextGeometry airport labels, aircraft enrichment APIs (hexdb.io, adsbdb.com), 2-second delayed lerp interpolation at 30fps, follow mode, dual data sources with failover, IndexedDB stats persistence, coverage heatmap, altitude distribution, top airlines, comprehensive keyboard shortcuts
