# Phase 9: UI Controls + Settings + Airports - Research

**Researched:** 2026-02-09
**Domain:** SwiftUI macOS UI (search, settings, charts, menus, keyboard shortcuts) + camera animation
**Confidence:** HIGH

## Summary

Phase 9 transforms the app from a view-only 3D flight tracker into a fully interactive application with user-configurable settings, airport search with fly-to, statistics graphs, and native macOS menu bar integration. The codebase already has the essential infrastructure: ThemeManager with UserDefaults persistence, OrbitCamera with follow mode and smooth lerp, AirportLabelManager with 100 pre-loaded airports (lat/lon/IATA/ICAO/name), and a NotificationCenter bridge between SwiftUI and the Metal render loop.

All UI features use pure SwiftUI (no AppKit wrappers needed beyond what already exists). The key patterns are: `@AppStorage` for settings persistence, SwiftUI `Settings` scene for the preferences window, `.searchable` with `.searchSuggestions` for airport autocomplete, Swift Charts `LineMark` for time-series statistics, `CommandMenu`/`CommandGroup` for native menu bar, and `.keyboardShortcut` for hotkeys. Camera fly-to animation uses the existing `OrbitCamera.update(deltaTime:)` loop with an ease-in-out interpolation toward a target position.

**Primary recommendation:** Build all UI as SwiftUI overlays on the existing ContentView ZStack, use @AppStorage for all settings persistence (extending the existing ThemeManager pattern), and add a dedicated FlyToAnimator that drives OrbitCamera.target via the existing per-frame update loop.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 14+ | All UI panels, settings, overlays | Already used throughout the app |
| Swift Charts | macOS 13+ (Charts framework) | Statistics graphs (aircraft count, message rate) | Apple first-party, no dependencies |
| Foundation/UserDefaults | macOS 14+ | Settings persistence via @AppStorage | Already used by ThemeManager |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Combine | macOS 14+ | Timer-based statistics sampling | For periodic data collection into time series |
| NotificationCenter | Foundation | SwiftUI-to-Metal bridge | Already the established pattern in the codebase |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| @AppStorage | Raw UserDefaults | @AppStorage gives automatic SwiftUI view updates; raw UserDefaults requires manual observation |
| Swift Charts | Custom Canvas drawing | Charts gives axes, legends, animations for free; Canvas requires rebuilding everything |
| .searchable modifier | Custom TextField + popover | .searchable gives native macOS search field behavior and suggestion dropdown for free |

**Installation:**
No additional packages needed. All frameworks are built into macOS 14 Sonoma SDK.

## Architecture Patterns

### Recommended Project Structure
```
AirplaneTracker3D/
├── Views/
│   ├── ContentView.swift          # Main ZStack (extend with new overlays)
│   ├── AircraftDetailPanel.swift  # Existing - no changes needed
│   ├── AirportSearchPanel.swift   # NEW: search field + results list + fly-to
│   ├── SettingsView.swift         # NEW: Settings scene content (tabbed)
│   ├── InfoPanel.swift            # NEW: aircraft count, last update, center coords
│   └── StatisticsPanel.swift      # NEW: Charts graphs (aircraft count, msg rate)
├── ViewModels/
│   ├── AirportSearchViewModel.swift  # NEW: search logic, filtering, distance calc
│   └── StatisticsCollector.swift     # NEW: time-series data collection
├── Camera/
│   ├── OrbitCamera.swift          # Existing - add flyTo animation state
│   └── FlyToAnimator.swift        # NEW: ease-in-out camera animation driver
├── Rendering/
│   ├── ThemeManager.swift         # Existing - extend with more @AppStorage keys
│   └── ...
└── AirplaneTracker3DApp.swift     # Extend with Settings scene + .commands
```

### Pattern 1: @AppStorage for Settings Persistence
**What:** Use @AppStorage property wrapper to bind UserDefaults keys directly to SwiftUI views with automatic UI updates.
**When to use:** All user-configurable settings (theme, units, data source, trail length, etc.)
**Example:**
```swift
// Source: Apple SwiftUI documentation + HackingWithSwift
struct SettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme = "day"
    @AppStorage("trailLength") private var trailLength = 500
    @AppStorage("trailWidth") private var trailWidth = 3.0
    @AppStorage("altitudeExaggeration") private var altitudeExaggeration = 1.0
    @AppStorage("unitSystem") private var unitSystem = "imperial"
    @AppStorage("dataSource") private var dataSource = "global"

    var body: some View {
        Form {
            Picker("Theme", selection: $selectedTheme) {
                Text("Day").tag("day")
                Text("Night").tag("night")
                Text("Retro").tag("retro")
            }
            Slider(value: $trailLength, in: 50...4000, step: 50) {
                Text("Trail Length: \(Int(trailLength))")
            }
            Slider(value: $trailWidth, in: 1...10, step: 0.5) {
                Text("Trail Width: \(trailWidth, specifier: "%.1f")")
            }
            Slider(value: $altitudeExaggeration, in: 0.5...5.0, step: 0.5) {
                Text("Altitude Scale: \(altitudeExaggeration, specifier: "%.1fx")")
            }
            Picker("Units", selection: $unitSystem) {
                Text("Imperial (ft, kts)").tag("imperial")
                Text("Metric (m, km/h)").tag("metric")
            }
        }
    }
}
```

### Pattern 2: SwiftUI .searchable with Suggestions for Airport Search
**What:** Native macOS search field with autocomplete dropdown using .searchable and .searchSuggestions modifiers.
**When to use:** Airport search by name, IATA, or ICAO code.
**Example:**
```swift
// Source: HackingWithSwift + Apple WWDC21 "Craft search experiences"
struct AirportSearchPanel: View {
    @State private var searchText = ""
    let airports: [AirportData]
    let onFlyTo: (AirportData) -> Void

    var filteredAirports: [AirportData] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        return airports.filter { airport in
            airport.name.lowercased().contains(query) ||
            (airport.iata?.lowercased().contains(query) ?? false) ||
            airport.icao.lowercased().contains(query)
        }.prefix(10).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Search airports...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ForEach(filteredAirports, id: \.icao) { airport in
                Button(action: { onFlyTo(airport) }) {
                    HStack {
                        Text(airport.iata ?? airport.icao)
                            .font(.system(.body, design: .monospaced).bold())
                        Text(airport.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

**Note on .searchable vs custom TextField:** The `.searchable` modifier requires a `NavigationStack` or `NavigationSplitView` parent, which this app does not use (it uses a ZStack overlay pattern). For this app, a custom `TextField` with a filtered results list in a VStack overlay is the better fit. The `.searchable` modifier would force a navigation container restructuring that conflicts with the full-screen Metal view architecture.

### Pattern 3: Camera Fly-To Animation
**What:** Smooth ease-in-out animation of OrbitCamera.target from current position to an airport's world coordinates.
**When to use:** When user selects an airport to fly to.
**Example:**
```swift
// Integrates with existing OrbitCamera.update(deltaTime:) loop
final class FlyToAnimator {
    var isAnimating: Bool = false
    private var startTarget: SIMD3<Float> = .zero
    private var endTarget: SIMD3<Float> = .zero
    private var startDistance: Float = 0
    private var endDistance: Float = 50  // close zoom for airport
    private var elapsed: Float = 0
    private var duration: Float = 2.0  // seconds

    func startFlyTo(from camera: OrbitCamera, to worldPosition: SIMD3<Float>) {
        startTarget = camera.target
        endTarget = worldPosition
        startDistance = camera.distance
        endDistance = min(camera.distance, 80)  // zoom in but not too close
        elapsed = 0
        isAnimating = true
    }

    /// Call each frame from OrbitCamera.update(deltaTime:)
    func update(camera: OrbitCamera, deltaTime: Float) {
        guard isAnimating else { return }
        elapsed += deltaTime
        let t = min(elapsed / duration, 1.0)
        // Ease-in-out (smoothstep)
        let smooth = t * t * (3.0 - 2.0 * t)

        camera.target = mix(startTarget, endTarget, t: smooth)
        camera.distance = startDistance + (endDistance - startDistance) * smooth

        if t >= 1.0 {
            isAnimating = false
        }
    }
}
```

### Pattern 4: Settings Scene in App
**What:** SwiftUI Settings scene that opens via Cmd+, (standard macOS).
**When to use:** App-level preferences window.
**Example:**
```swift
// Source: Apple Developer Documentation + serialcoder.dev
@main
struct AirplaneTracker3DApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
```

### Pattern 5: Swift Charts for Statistics
**What:** Time-series line charts for aircraft count and message rate over time.
**When to use:** Statistics panel showing live data trends.
**Example:**
```swift
// Source: Apple Charts documentation + appcoda.com
import Charts

struct StatisticsPanel: View {
    let dataPoints: [StatDataPoint]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Aircraft Count")
                .font(.caption.bold())

            Chart {
                ForEach(dataPoints) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Count", point.aircraftCount)
                    )
                    .foregroundStyle(.blue)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .frame(height: 120)
        }
    }
}

struct StatDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let aircraftCount: Int
    let messageRate: Double
}
```

### Pattern 6: Menu Bar Commands with Keyboard Shortcuts
**What:** Native macOS menu bar items with keyboard shortcuts.
**When to use:** App-level actions accessible from menu bar and keyboard.
**Example:**
```swift
// Source: danielsaidi.com + createwithswift.com
struct AppCommands: Commands {
    var body: some Commands {
        // Custom "View" actions
        CommandMenu("Tracker") {
            Button("Reset Camera") {
                NotificationCenter.default.post(name: .resetCamera, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Toggle Auto-Rotate") {
                NotificationCenter.default.post(name: .toggleAutoRotate, object: nil)
            }
            .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button("Cycle Theme") {
                NotificationCenter.default.post(name: .cycleTheme, object: nil)
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button("Search Airport") {
                NotificationCenter.default.post(name: .toggleSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}
```

### Anti-Patterns to Avoid
- **Binding Metal state directly to @AppStorage:** Do not try to make Renderer properties @AppStorage. Instead, observe UserDefaults changes via NotificationCenter (already the pattern) or read values at frame time.
- **Using NavigationStack just for .searchable:** Do not wrap the full-screen Metal view in NavigationStack. Use a custom TextField-based search panel instead.
- **Storing chart data in UserDefaults:** Time-series statistics are ephemeral -- keep them in memory only, not persisted.
- **Heavy SwiftUI overlays blocking Metal performance:** Keep overlay views lightweight. Use `.allowsHitTesting(false)` on transparent overlay areas so mouse events pass through to MetalMTKView.
- **Creating a separate window for each panel:** Keep all panels as overlays in the main ContentView ZStack. Only the Settings window should be a separate window (via the Settings scene).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Time-series charts | Custom Canvas/Core Graphics chart rendering | Swift Charts (LineMark, AxisMarks) | Handles axis formatting, scaling, animation, accessibility |
| Settings persistence | Custom file-based settings system | @AppStorage + UserDefaults | Automatic SwiftUI binding, thread-safe, system-standard |
| macOS menu bar | NSMenu/NSMenuItem AppKit integration | SwiftUI CommandMenu/CommandGroup | Pure SwiftUI, keyboard shortcuts integrated |
| Search autocomplete | Custom NSPopover or dropdown | TextField + filtered list in VStack overlay | Simpler, matches overlay architecture |
| Ease-in-out interpolation | Custom bezier math | `smoothstep: t * t * (3 - 2*t)` | Classic, well-understood, already used in graphics |
| Haversine distance | Custom trig functions for distance | Use world-space Euclidean distance | Airports are already in world-space coordinates via MapCoordinateSystem; Euclidean distance in world-space is sufficient for nearby sorting |

**Key insight:** The existing codebase already uses UserDefaults (ThemeManager), NotificationCenter bridging (SwiftUI-to-Metal), and per-frame lerp interpolation (OrbitCamera follow mode). Phase 9 extends these same patterns rather than introducing new architectural concepts.

## Common Pitfalls

### Pitfall 1: @AppStorage and Non-Standard Types
**What goes wrong:** @AppStorage only supports String, Int, Double, Bool, URL, and Data. Trying to store enums or custom types directly fails at compile time.
**Why it happens:** Swift enums are not natively supported by @AppStorage.
**How to avoid:** Store enum raw values (String/Int) in @AppStorage and convert. The existing ThemeManager already does this: `UserDefaults.standard.set(current.rawValue, forKey: "selectedTheme")`.
**Warning signs:** Compile error "No exact matches in call to initializer" when using @AppStorage with an enum.

### Pitfall 2: Settings Changes Not Reaching Metal Renderer
**What goes wrong:** User changes a setting in the SwiftUI Settings panel, but the Metal render loop doesn't pick up the change.
**Why it happens:** The Renderer runs on the main thread in draw(in:) but doesn't observe @AppStorage directly (it's a plain class, not a SwiftUI view).
**How to avoid:** Two approaches: (1) Read UserDefaults values at frame time in draw(in:) -- simple and cheap for infrequent changes. (2) Use NotificationCenter to push changes (the existing theme pattern). Approach (1) is recommended for settings like trail length/width that are read every frame anyway.
**Warning signs:** Setting changes only take effect after app restart.

### Pitfall 3: Search Performance with Large Airport Lists
**What goes wrong:** Filtering airports on every keystroke causes UI lag.
**Why it happens:** String matching 100 airports is trivial, but if the list grows to thousands, or if the search triggers other expensive operations, it lags.
**How to avoid:** For 100 airports, simple `.filter { }` is fine (< 1ms). Pre-lowercase all searchable fields at load time. If scaling to thousands, use a pre-built trie or sorted array with binary search.
**Warning signs:** Noticeable delay between typing and results appearing.

### Pitfall 4: Camera Animation Conflicting with Follow Mode
**What goes wrong:** Starting a fly-to animation while follow mode is active causes camera jitter (two systems fighting for control of camera.target).
**Why it happens:** Both FlyToAnimator and followTarget try to set camera.target each frame.
**How to avoid:** When starting fly-to, always clear followTarget and deselect any aircraft. When fly-to completes, don't auto-engage follow mode.
**Warning signs:** Camera oscillates or jumps during fly-to animation.

### Pitfall 5: SwiftUI Overlays Consuming Mouse Events
**What goes wrong:** Transparent SwiftUI overlay areas intercept mouse clicks, preventing aircraft selection in MetalMTKView.
**Why it happens:** SwiftUI views have hit-testing enabled by default, even transparent areas.
**How to avoid:** Use `.allowsHitTesting(false)` on overlay containers that should be click-through. Only enable hit-testing on actual interactive elements (buttons, text fields, lists).
**Warning signs:** Clicking on aircraft in the 3D view doesn't select them when overlays are visible.

### Pitfall 6: Charts Framework Performance with Many Data Points
**What goes wrong:** Rendering thousands of data points in a SwiftUI Chart causes frame drops.
**Why it happens:** Swift Charts re-renders the entire chart view on each data update.
**How to avoid:** Cap time-series data to last 60-120 data points. Sample every 5-10 seconds. Don't update the chart every frame -- use a Timer at 1-5 second intervals.
**Warning signs:** Main thread stuttering when statistics panel is visible.

## Code Examples

### Nearby Airports Sorted by Distance
```swift
// Uses existing AirportLabelManager.airports and .airportPositions
// Camera target is already in world-space coordinates

func nearbyAirports(cameraTarget: SIMD3<Float>,
                    airports: [AirportData],
                    positions: [SIMD3<Float>],
                    limit: Int = 10) -> [(airport: AirportData, distance: Float)] {
    var results: [(airport: AirportData, distance: Float)] = []

    for i in 0..<airports.count {
        let dx = positions[i].x - cameraTarget.x
        let dz = positions[i].z - cameraTarget.z
        let dist = sqrt(dx * dx + dz * dz)  // XZ plane distance
        results.append((airport: airports[i], distance: dist))
    }

    results.sort { $0.distance < $1.distance }
    return Array(results.prefix(limit))
}
```

### Statistics Data Collector
```swift
// Collects aircraft count and timestamp every N seconds
@MainActor
final class StatisticsCollector: ObservableObject {
    struct DataPoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let aircraftCount: Int
    }

    @Published var dataPoints: [DataPoint] = []
    private var timer: Timer?
    private let maxPoints = 120  // 10 minutes at 5-second intervals

    func start(flightDataManager: FlightDataManager) {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let count = flightDataManager.interpolatedStates(at: CACurrentMediaTime()).count
            let point = DataPoint(timestamp: Date(), aircraftCount: count)
            self.dataPoints.append(point)
            if self.dataPoints.count > self.maxPoints {
                self.dataPoints.removeFirst(self.dataPoints.count - self.maxPoints)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
```

### Info Panel (Aircraft Count + Center Coordinates)
```swift
struct InfoPanel: View {
    let aircraftCount: Int
    let lastUpdateTime: Date
    let centerLat: Double
    let centerLon: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "airplane")
                Text("\(aircraftCount)")
                    .font(.system(.body, design: .monospaced).bold())
            }
            Text("Updated: \(lastUpdateTime, format: .dateTime.hour().minute().second())")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(centerLat, specifier: "%.2f"), \(centerLon, specifier: "%.2f")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}
```

### Reading Settings in Metal Renderer
```swift
// In Renderer.draw(in:), read UserDefaults at frame time for settings
// that affect rendering. This is cheap (cached by the system).
let trailLength = UserDefaults.standard.integer(forKey: "trailLength")
if trailLength > 0 && trailLength != trailManager.maxTrailLength {
    trailManager.maxTrailLength = trailLength
}

let trailWidth = UserDefaults.standard.double(forKey: "trailWidth")
if trailWidth > 0 {
    trailManager.lineWidth = Float(trailWidth)
}

let altExaggeration = UserDefaults.standard.double(forKey: "altitudeExaggeration")
if altExaggeration > 0 {
    // Adjust FlightDataManager.altitudeScale or apply multiplier
}
```

### Keyboard Shortcut Integration with MetalMTKView
```swift
// Extend existing MetalMTKView.keyDown to handle more shortcuts
// These are ALSO reflected in the menu bar via CommandMenu
override func keyDown(with event: NSEvent) {
    guard let camera = coordinator?.renderer?.camera else { return }
    switch event.charactersIgnoringModifiers {
    case "r":
        camera.reset()
    case "a":
        camera.isAutoRotating.toggle()
    case "t":
        NotificationCenter.default.post(name: .cycleTheme, object: nil)
    case "f":
        // Toggle search panel visibility
        NotificationCenter.default.post(name: .toggleSearch, object: nil)
    case "i":
        // Toggle info panel visibility
        NotificationCenter.default.post(name: .toggleInfoPanel, object: nil)
    default:
        super.keyDown(with: event)
    }
}
```

**Important note on keyboard shortcuts:** The existing `MetalMTKView.keyDown` handles raw key events (no Command modifier). The SwiftUI `CommandMenu` handles Cmd+key combinations. Both should coexist: menu bar items use Cmd+R, Cmd+T, etc., while raw keys (R, T, A without Cmd) also work when the Metal view has focus. This is the standard macOS pattern.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSPreferencesWindow | SwiftUI Settings scene | macOS 13 (2022) | Pure SwiftUI settings windows |
| Raw UserDefaults.standard | @AppStorage property wrapper | iOS 14/macOS 11 (2020) | Automatic SwiftUI view updates |
| Core Plot / custom charts | Swift Charts framework | macOS 13 (2022) | First-party, native integration |
| NSMenu/NSMenuItem | SwiftUI CommandMenu/CommandGroup | macOS 11 (2020) | Declarative menu bar |
| NSSearchField | SwiftUI .searchable modifier | macOS 12 (2021) | Native search, but requires NavigationStack |

**Deprecated/outdated:**
- `Preferences` scene name was renamed to `Settings` in macOS 13. Use `Settings { }` not `Preferences { }`.
- Manual NSMenu creation for macOS menu bar. Use SwiftUI Commands protocol instead.
- Custom chart libraries (SwiftUICharts, Charts by danielgindi). Use Apple's Swift Charts for new projects.

## Open Questions

1. **@AppStorage key name conflicts with existing ThemeManager**
   - What we know: ThemeManager already stores `selectedTheme` in UserDefaults manually. If we also use @AppStorage("selectedTheme"), both systems will read/write the same key.
   - What's unclear: Whether to migrate ThemeManager to @AppStorage or keep dual access.
   - Recommendation: Keep ThemeManager's manual UserDefaults access for the Metal side. Use @AppStorage in the SwiftUI Settings view for display only. Both read the same key, which is fine -- UserDefaults is thread-safe.

2. **Statistics data source for message rate**
   - What we know: Aircraft count can be derived from `interpolatedStates.count`. The API response includes `msg` and `total` fields.
   - What's unclear: Whether FlightDataActor currently exposes message count or rate.
   - Recommendation: Add a simple counter in FlightDataManager that increments on each poll cycle and tracks cumulative aircraft seen. This is sufficient for a rate graph.

3. **Panel layout -- sidebar vs floating overlays**
   - What we know: The app currently uses ZStack overlays (detail panel slides from right). No sidebar or navigation structure.
   - What's unclear: Whether search panel, info panel, and stats panel should be toggleable overlays or a permanent sidebar.
   - Recommendation: Keep the overlay pattern. Each panel is a toggleable overlay: search (top-left below theme button), info (bottom-left), statistics (bottom-right or as a sheet). This maintains the full-screen 3D view as the primary experience.

## Sources

### Primary (HIGH confidence)
- **Existing codebase** - ContentView.swift, ThemeManager.swift, OrbitCamera.swift, AirportLabelManager.swift, MetalView.swift, Renderer.swift, FlightDataManager.swift -- all read and analyzed
- **airports.json** - 100 airports with icao, iata, name, lat, lon, type fields confirmed

### Secondary (MEDIUM confidence)
- [HackingWithSwift - SwiftUI searchable](https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-a-search-bar-to-filter-your-data) - Complete code examples for .searchable and .searchCompletion
- [HackingWithSwift - keyboardShortcut](https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-keyboard-shortcuts-using-keyboardshortcut) - keyboardShortcut modifier usage with modifiers
- [danielsaidi.com - macOS menu bar](https://danielsaidi.com/blog/2023/11/22/customizing-the-macos-menu-bar-in-swiftui) - CommandMenu and CommandGroup patterns
- [createwithswift.com - menu bar](https://www.createwithswift.com/creating-and-customizing-the-menu-bar-of-a-swiftui-app/) - Menu bar customization with keyboard shortcuts
- [serialcoder.dev - macOS Settings](https://serialcoder.dev/text-tutorials/macos-tutorials/presenting-the-preferences-window-on-macos-using-swiftui/) - Settings scene with TabView
- [AppCoda - SwiftUI line charts](https://www.appcoda.com/swiftui-line-charts/) - LineMark with Date x-axis and AxisMarks formatting
- [swiftwithmajid.com - Charts basics](https://swiftwithmajid.com/2023/01/10/mastering-charts-in-swiftui-basics/) - Chart, LineMark, PointMark, RuleMark patterns
- [Apple WWDC21 - Craft search experiences](https://developer.apple.com/videos/play/wwdc2021/10176/) - searchable modifier design intent

### Tertiary (LOW confidence)
- [createwithswift.com - search suggestions](https://www.createwithswift.com/implementing-search-suggestions-in-swiftui/) - searchSuggestions modifier (not verified for macOS-specific behavior)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All Apple first-party frameworks, already used in the project or well-documented
- Architecture: HIGH - Extends existing patterns (ZStack overlays, NotificationCenter bridge, UserDefaults, per-frame camera update)
- Pitfalls: HIGH - Based on direct codebase analysis (follow mode conflict, hit-testing, @AppStorage type limits are concrete)
- Code examples: HIGH - Verified against existing codebase patterns (OrbitCamera lerp, AirportLabelManager distance culling, ThemeManager UserDefaults)
- Charts: MEDIUM - Swift Charts API verified via multiple tutorial sources; specific macOS rendering behavior not directly tested

**Research date:** 2026-02-09
**Valid until:** 2026-03-11 (stable - all frameworks are mature Apple first-party APIs)
