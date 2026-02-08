---
phase: 07-trails-labels-selection
plan: 02
subsystem: rendering
tags: [metal, billboard, label, texture-atlas, cortext, selection, ray-cast, enrichment, follow-camera, swiftui, detail-panel]

# Dependency graph
requires:
  - phase: 07-trails-labels-selection
    provides: "TrailManager, trail shaders, trail rendering pipeline in Renderer draw loop"
  - phase: 06-flight-data-aircraft-rendering
    provides: "InterpolatedAircraftState, AircraftInstanceManager, glow sprites, triple-buffered rendering"
provides:
  - "LabelManager with CoreText texture atlas rasterization and LOD distance fade"
  - "LabelShaders.metal with billboard vertex/fragment shaders sampling text atlas"
  - "AltitudeLineShaders.metal with dashed vertical reference lines"
  - "SelectionManager with ray-sphere click picking and follow mode state"
  - "EnrichmentService actor with hexdb.io and adsbdb.com API integration"
  - "AircraftDetailPanel SwiftUI view with flight data and async enrichment"
  - "SelectedAircraftInfo model for SwiftUI/rendering bridge"
  - "OrbitCamera follow target with smooth lerp tracking"
affects: [08-terrain, 09-polish, 10-packaging]

# Tech tracking
tech-stack:
  added: []
  patterns: [texture-atlas label rasterization, billboard rendering, ray-sphere picking, actor-based API caching, notification-based SwiftUI-Metal communication]

key-files:
  created:
    - AirplaneTracker3D/Rendering/LabelShaders.metal
    - AirplaneTracker3D/Rendering/AltitudeLineShaders.metal
    - AirplaneTracker3D/Rendering/LabelManager.swift
    - AirplaneTracker3D/Rendering/SelectionManager.swift
    - AirplaneTracker3D/DataLayer/EnrichmentService.swift
    - AirplaneTracker3D/Views/AircraftDetailPanel.swift
  modified:
    - AirplaneTracker3D/Rendering/ShaderTypes.h
    - AirplaneTracker3D/Rendering/Renderer.swift
    - AirplaneTracker3D/Rendering/MetalView.swift
    - AirplaneTracker3D/Rendering/AircraftInstanceManager.swift
    - AirplaneTracker3D/Camera/OrbitCamera.swift
    - AirplaneTracker3D/ContentView.swift
    - AirplaneTracker3D/Models/AircraftModel.swift
    - AirplaneTracker3D/DataLayer/FlightDataActor.swift
    - AirplaneTracker3D.xcodeproj/project.pbxproj

key-decisions:
  - "CoreText rasterization to 2048x2048 RGBA8 texture atlas with 256x64 slots for label billboards"
  - "LOD distance fade: labels fully visible under 150 units, fading to hidden at 300 units"
  - "Ray-sphere picking with radius 3.0 world units for click selection"
  - "NotificationCenter-based communication between SwiftUI ContentView and Metal Coordinator for follow mode"
  - "EnrichmentService uses Swift actor with dictionary caching (including negative lookups)"

patterns-established:
  - "Texture atlas pattern: CoreText renders text to CGContext, uploads to MTLTexture sub-region, indexed by slot"
  - "Billboard label rendering: camera-facing quads sampling atlas sub-regions with per-instance UV coordinates"
  - "Ray-sphere picking: screen-to-ray unprojection via inverse VP matrix, test against sphere volumes"
  - "Actor-based API enrichment: async caching with 3s timeout, nil = negative cache to avoid re-requests"
  - "ZStack overlay pattern: SwiftUI detail panel overlaid on MetalView with animated transitions"

# Metrics
duration: 7min
completed: 2026-02-08
---

# Phase 7 Plan 2: Labels + Selection + Enrichment Summary

**Billboard text labels with LOD fade, dashed altitude lines, ray-cast click selection with SwiftUI detail panel, hexdb.io/adsbdb.com enrichment, and smooth follow camera**

## Performance

- **Duration:** 7 min 2s
- **Started:** 2026-02-08T23:03:20Z
- **Completed:** 2026-02-08T23:10:22Z
- **Tasks:** 2
- **Files modified:** 15

## Accomplishments
- Billboard labels rendering above each aircraft showing callsign/altitude with distance-based LOD fade
- Dashed altitude reference lines from aircraft to ground plane using Metal line primitives
- Ray-sphere click picking for aircraft selection with gold highlight via instance flags
- SwiftUI detail panel with flight data (callsign, altitude, speed, heading, squawk, position)
- Async enrichment from hexdb.io (registration, type, operator) and adsbdb.com (route origin/destination)
- Smooth follow camera mode with frame-rate-independent exponential lerp tracking

## Task Commits

Each task was committed atomically:

1. **Task 1: Billboard labels with LOD, dashed altitude lines, and Metal shaders** - `9b89ce5` (feat)
2. **Task 2: Ray-cast selection, SwiftUI detail panel, enrichment service, and follow camera** - `782abad` (feat)

## Files Created/Modified
- `AirplaneTracker3D/Rendering/ShaderTypes.h` - Added LabelInstanceData (48 bytes) and AltLineVertex (16 bytes) structs, BufferIndex entries 6 and 7
- `AirplaneTracker3D/Rendering/LabelShaders.metal` - Billboard label vertex/fragment shaders sampling texture atlas with distance fade
- `AirplaneTracker3D/Rendering/AltitudeLineShaders.metal` - Dashed vertical line vertex/fragment shaders using worldY modulo pattern
- `AirplaneTracker3D/Rendering/LabelManager.swift` - CoreText atlas rasterization (2048x2048 RGBA8, 256x64 slots), LOD fade, triple-buffered instance/altline buffers
- `AirplaneTracker3D/Rendering/SelectionManager.swift` - Ray-sphere click picking, selection state, follow mode coordination
- `AirplaneTracker3D/DataLayer/EnrichmentService.swift` - Actor with hexdb.io and adsbdb.com API integration, dictionary caching with 3s timeout
- `AirplaneTracker3D/Views/AircraftDetailPanel.swift` - SwiftUI detail panel with flight data sections, enrichment sections, follow button
- `AirplaneTracker3D/Models/AircraftModel.swift` - Added SelectedAircraftInfo struct, extended InterpolatedAircraftState with squawk/lat/lon
- `AirplaneTracker3D/Camera/OrbitCamera.swift` - Added followTarget with frame-rate-independent exponential lerp
- `AirplaneTracker3D/Rendering/MetalView.swift` - Added mouseDown click handler, onAircraftSelected callback, notification listeners for follow/clear
- `AirplaneTracker3D/Rendering/AircraftInstanceManager.swift` - Added selectedHex parameter, flags=1 for selected aircraft
- `AirplaneTracker3D/Rendering/Renderer.swift` - Added labelManager, selectionManager, label/altline pipelines, encodeLabels/encodeAltitudeLines, follow camera integration
- `AirplaneTracker3D/ContentView.swift` - ZStack overlay with MetalView + AircraftDetailPanel, notification-based follow/clear communication
- `AirplaneTracker3D/DataLayer/FlightDataActor.swift` - Updated InterpolatedAircraftState construction with squawk/lat/lon fields
- `AirplaneTracker3D.xcodeproj/project.pbxproj` - Registered all 6 new files in Rendering, DataLayer, and Views groups

## Decisions Made
- CoreText rasterization to texture atlas (2048x2048, 256x64 slots) -- single texture, single draw call for all labels
- LOD distance fade: fully visible under 150 world units, linearly fading to hidden at 300 units
- Ray-sphere intersection with radius 3.0 world units for picking (generous hit area for usability)
- NotificationCenter for SwiftUI-to-Metal follow/clear communication (avoids binding complexity between SwiftUI and NSViewRepresentable coordinator)
- EnrichmentService uses actor pattern with dictionary caching (nil entries = negative cache to prevent repeated failed lookups)
- HexDBResponse uses CodingKeys to map capitalized API field names to lowercase Swift properties (avoids `Type` keyword conflict)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed HexDBResponse `Type` property name conflict**
- **Found during:** Task 2 (EnrichmentService)
- **Issue:** Swift compiler error: property named `Type` conflicts with `foo.Type` expression
- **Fix:** Added CodingKeys enum to map `Registration`, `Type`, etc. to lowercase Swift property names
- **Files modified:** AirplaneTracker3D/DataLayer/EnrichmentService.swift
- **Verification:** Build succeeded
- **Committed in:** 782abad (Task 2 commit)

**2. [Rule 1 - Bug] Fixed MainActor isolation for handleClick**
- **Found during:** Task 2 (MetalView click handler)
- **Issue:** `interpolatedStates(at:)` is on @MainActor class, called from non-isolated context
- **Fix:** Added `@MainActor` annotation to `handleClick(at:in:)` method
- **Files modified:** AirplaneTracker3D/Rendering/MetalView.swift
- **Verification:** Build succeeded
- **Committed in:** 782abad (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes were necessary for compilation. No scope creep.

## Issues Encountered
- Swift keyword conflict with `Type` property name from hexdb.io API -- resolved with CodingKeys enum mapping
- @MainActor isolation requirement for FlightDataManager.interpolatedStates -- resolved with @MainActor annotation on click handler

## User Setup Required
None - no external service configuration required. Enrichment APIs (hexdb.io, adsbdb.com) are public with no API keys.

## Next Phase Readiness
- Phase 7 (Trails + Labels + Selection) is fully complete
- All rendering subsystems operational: tiles, aircraft, trails, labels, altitude lines, glow, selection
- Ready for Phase 8 (terrain) or Phase 9 (polish/settings)
- EnrichmentService caching handles network failures silently (3s timeout, negative cache)

## Self-Check: PASSED

- All 6 created files exist on disk
- Commit 9b89ce5 verified (Task 1)
- Commit 782abad verified (Task 2)
- LabelManager.swift: 332 lines (requirement: >= 100)
- SelectionManager.swift: 115 lines (requirement: >= 50)
- EnrichmentService.swift: 164 lines (requirement: >= 60)
- AircraftDetailPanel.swift: 169 lines (requirement: >= 50)
- Build: SUCCEEDED (xcodebuild)

---
*Phase: 07-trails-labels-selection*
*Completed: 2026-02-08*
