# Feature Research

**Domain:** 3D Flight Tracking -- Global Data, Terrain, Airspace, Airport Discovery
**Researched:** 2026-02-07
**Confidence:** MEDIUM-HIGH

## Feature Landscape

This research covers the NEW features being added to the existing 3D flight tracker. Existing features (aircraft rendering, interpolation, trails, themes, enrichment, stats, keyboard/touch controls, LOD, follow mode, heatmap) are not re-evaluated here.

The five feature areas under investigation:
1. Global flight data sourcing with API fallback
2. Airport search and discovery (search, browse nearby, fly-to)
3. 3D ground labels for major airports
4. Terrain elevation with satellite imagery
5. Airspace Class B/C/D volume rendering

### Table Stakes (Users Expect These)

Features users assume exist when a flight tracker claims "global data" or "terrain/airspace." Missing these means the product feels broken or half-finished.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Global data via API with geographic query** | If the app claims global coverage, users expect to see flights anywhere in the world, not just near their own ADS-B receiver | MEDIUM | airplanes.live provides `/point/{lat}/{lon}/{radius}` up to 250nm. adsb.lol offers `/v2/lat/{lat}/lon/{lon}/dist/{dist}` up to 100nm. Must poll periodically (1-5s). Rate limit: airplanes.live = 1 req/sec, adsb.lol = no published limit. |
| **Automatic fallback between APIs** | Users do not care which API is serving data -- they care that aircraft appear. A single API going down should not break the app | MEDIUM | Air Loom uses airplanes.live exclusively. We should chain: airplanes.live (primary, 250nm radius) -> adsb.lol (fallback, 100nm radius). Both return readsb-compatible JSON. |
| **Data source mode switch (local vs global)** | Users with local dump1090 receivers want their local feed; users without one want global API. Must support both without restart | LOW | UI toggle or auto-detect. Both modes should share all visualization features (trails, enrichment, terrain, airspace). |
| **Airport search by name/code** | Every flight tracker with airport awareness has search. Users type "LAX" or "Heathrow" and expect results | MEDIUM | OurAirports dataset: 78K+ airports, CSV format, public domain. Need client-side filtering with autocomplete. Load airports.csv, index by IATA/ICAO/name/municipality. |
| **Camera fly-to on airport selection** | When a user picks an airport from search, the view must smoothly animate to that location. Clicking and then manually panning defeats the purpose | LOW | THREE.js camera tween using existing orbit controls. Interpolate position + target over ~1-2 seconds. |
| **Terrain elevation (3D ground mesh)** | If terrain is advertised, users expect actual elevation -- mountains should be taller than valleys. A flat plane with satellite texture is not terrain | HIGH | Mapzen Terrarium tiles on AWS (free, no auth). Decode RGB: elevation = (R*256 + G + B/256) - 32768. Generate PlaneGeometry mesh per tile, apply displacement. Need LOD: more segments near camera, fewer far away. Air Loom uses zoom level 10 (~39km/tile) with 64/32/16/8 segment LOD. |
| **Satellite or map imagery on terrain** | Terrain without any texture is just a grey bumpy surface -- users expect to see recognizable geography (roads, coastlines, land use) | MEDIUM | ESRI World Imagery (free for non-commercial display) or CartoDB dark tiles (already used for 2D map). Both use standard `{z}/{x}/{y}` tile URL patterns. Must drape texture onto elevation mesh. |
| **Airspace volume rendering (Class B/C/D)** | If airspace is advertised, users expect to see the characteristic 3D shapes: Class B "inverted wedding cake," Class C tiered cylinder, Class D simple cylinder | HIGH | Need airspace boundary data (polygons + altitude floors/ceilings). Data sources: FAA AIS Open Data (US, GeoJSON), OpenAIP (worldwide, requires conversion). Render as semi-transparent colored volumes. Air Loom uses pastel purple (B), pink (C), blue (D) with opacity control. |

### Differentiators (Competitive Advantage)

Features that go beyond what's strictly expected. Having these elevates the product above basic trackers and toward the Air Loom / Flightradar24-3D tier.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Browse nearby airports list** | Most trackers only let you search. Showing a ranked list of airports near the current view center (sorted by distance or size) lets users discover airports they didn't know existed | LOW | Filter OurAirports data by distance from current view center. Show type (large/medium/small), distance, IATA code. Clickable to fly-to. |
| **3D ground labels for major airports** | Visible airport names/codes rendered on the ground in 3D space give geographic orientation without cluttering the UI. This is how Air Loom and Flightradar24 3D handle it | MEDIUM | Canvas-rendered text to texture, mapped onto ground-aligned planes. Only for large/medium airports within view range. Need LOD: show more labels when zoomed in, fewer when zoomed out. Performance: use shared texture atlas or sprite sheet, not individual geometries per label. |
| **Theme-aware terrain rendering** | The existing app has day/night/retro themes. Terrain that adapts to theme (satellite for day, dark-tinted for night, wireframe/green for retro) would be unique | MEDIUM | Apply different tile sources or shader tints per theme. Retro theme could use wireframe mesh with green glow -- very distinctive. Night theme could darken satellite imagery or use CartoDB dark tiles. |
| **Airspace opacity and class toggles** | Let users toggle individual classes (B/C/D) on/off and adjust overall opacity. Airspace can obscure aircraft if not controllable | LOW | UI toggles per class, opacity slider 0-100%. Air Loom has this. Also useful: "show only airspace within radius" mode. |
| **Focused radius mode** | Show only data (aircraft, airspace, labels) within a configurable radius of the center point. Reduces visual clutter for dense areas | LOW | Air Loom has this and users love it. Filter all renderables by distance from center. Configurable radius (e.g., 50/100/200km). |
| **Altitude exaggeration slider** | Real airspace and aircraft altitudes are tiny compared to ground distances (Class B is 36:1 width-to-height ratio). An exaggeration multiplier makes altitude differences visible | LOW | Simple multiplier on the Y-axis. Air Loom defaults to this. Without it, airspace volumes appear paper-thin and aircraft look like they're on the ground. |
| **Ground elevation offset** | Different airports sit at different elevations. A manual or automatic ground elevation adjustment prevents terrain from clipping through the airport reference plane | LOW | Air Loom has a manual "ground elevation" slider. Better: auto-read elevation from Terrarium tile at center point and offset scene accordingly. |
| **Multiple map layer options** | Let users choose between satellite, dark/labeled, dark/unlabeled, wireframe terrain. Different use cases favor different backgrounds | LOW | Already partially implemented (CartoDB, OSM, Stamen tiles). Extend to include satellite and terrain-specific options. Air Loom offers 7+ map layer options. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems. Deliberately NOT building these.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Full WASD fly mode** | "I want to fly through the airspace like a video game" | Adds significant complexity (PointerLock API, collision handling, disorientation). Orbit controls already provide full 3D navigation. Air Loom has fly mode but it's a niche feature most users don't use | Keep orbit controls with smooth follow mode. Add altitude exaggeration for better vertical perspective. |
| **Recording and playback** | "I want to replay interesting traffic patterns" | 6-hour recordings at 1fps = massive memory. IndexedDB storage fills up. Playback UI (timeline, speed controls, scrubbing) is essentially building a media player. Listed as out of scope in PROJECT.md | Longer trail durations (5-10 minutes) give a sense of history without playback complexity. |
| **Show ALL airports with labels** | "Why can't I see small grass strips?" | OurAirports has 78K+ entries. Rendering labels for all of them destroys performance and creates unreadable visual clutter. Even at zoom level 10, hundreds of airports could be in view | Show large/medium airports by default. Let users search for specific small airports. Optionally show more labels at very high zoom levels. |
| **Weather radar overlay** | "Show me precipitation on the terrain" | Adds a real-time data dependency (weather APIs), compositing complexity, and significant rendering cost for transparency layers. Not core to flight tracking visualization | Link to external weather resources from selected aircraft panel. Consider as v2+ feature only if terrain rendering performs well. |
| **Real-time NOTAM/TFR display** | "Show temporary flight restrictions" | NOTAM data is complex (free-text parsing), changes frequently, US-centric from FAA. International coverage requires multiple data sources. Significant parsing and rendering work for niche value | Show permanent airspace only. Link to official TFR resources. |
| **Navigation aids (VORs, NDBs, waypoints)** | "I want to see the navaid infrastructure" | Thousands of navaids worldwide. Clutters the display significantly. Only valuable to pilots/ATC students, not general aviation enthusiasts | Consider as an optional toggle in a future version, not initial release. |
| **Worldwide airspace data on initial load** | "Show me all airspace globally at once" | Global airspace data is enormous. Loading worldwide data upfront freezes the browser. Even Air Loom only loads airspace around the selected airport area | Load airspace for the visible region only. Fetch on-demand when user navigates to new area. Use the airport center point + radius approach. |

## Feature Dependencies

```
[Data Source Abstraction Layer]
    |
    +---> [Global API Integration (airplanes.live/adsb.lol)]
    |         |
    |         +---> [API Fallback Chain]
    |
    +---> [Local dump1090 Mode] (existing, needs adapter)

[OurAirports Dataset Loading]
    |
    +---> [Airport Search + Autocomplete]
    |         |
    |         +---> [Camera Fly-To Animation]
    |         |
    |         +---> [Browse Nearby Airports]
    |
    +---> [3D Airport Ground Labels]
              |
              +--requires---> [Terrain Elevation Mesh] (labels sit on terrain)

[Terrain Tile System (Mapzen Terrarium)]
    |
    +---> [Terrain Elevation Mesh Generation]
    |         |
    |         +---> [Satellite/Map Imagery Draping]
    |         |
    |         +---> [Ground Elevation Auto-Offset]
    |
    +---> [Theme-Aware Terrain Rendering]

[Airspace Data Loading (FAA/OpenAIP)]
    |
    +---> [Airspace Volume Mesh Generation]
              |
              +---> [Class Toggle + Opacity Controls]
              |
              +---> [Altitude Exaggeration]

[Altitude Exaggeration] --enhances--> [Airspace Volumes]
[Altitude Exaggeration] --enhances--> [Terrain Mesh]
[Altitude Exaggeration] --enhances--> [Aircraft Y-Position]

[Focused Radius Mode] --filters--> [Aircraft Display]
[Focused Radius Mode] --filters--> [Airport Labels]
[Focused Radius Mode] --filters--> [Airspace Volumes]
```

### Dependency Notes

- **Airport Ground Labels require Terrain Mesh:** Labels should sit on the terrain surface, not float at sea level. Without terrain, labels need a flat-plane fallback, but the visual quality suffers.
- **API Fallback requires Data Source Abstraction:** Both local and global data must flow through the same interface so the renderer doesn't care about the source.
- **Airspace Volumes benefit from Altitude Exaggeration:** Without exaggeration, real-world airspace proportions (up to 36:1 width-to-height) make volumes appear flat. Exaggeration should be implemented before or alongside airspace.
- **Satellite Imagery requires Terrain Mesh:** The satellite texture drapes onto the elevation mesh. Without elevation, you'd just have a textured flat plane (which works as a fallback but isn't "terrain").
- **Focused Radius Mode depends on having location context:** Only meaningful once airport search or global mode establishes a center point.

## MVP Definition

### Launch With (v1)

Minimum viable set of new features -- what makes the "global data + terrain + airspace + airports" milestone feel complete.

- [ ] **Data source abstraction layer** -- shared interface for local/global data; mode switch in UI
- [ ] **Global API integration with fallback** -- airplanes.live primary, adsb.lol secondary; geographic queries around view center
- [ ] **OurAirports dataset loading + indexing** -- load CSV, parse, index for fast search
- [ ] **Airport search with autocomplete** -- search by IATA, ICAO, name, or city; top results dropdown
- [ ] **Camera fly-to animation** -- smooth orbit controls animation to selected airport coordinates
- [ ] **Terrain elevation mesh** -- Mapzen Terrarium tiles, LOD-based segment count, covers visible area
- [ ] **Satellite/dark map imagery on terrain** -- drape existing tile sources onto elevation mesh
- [ ] **Airspace Class B/C/D volume rendering** -- semi-transparent colored meshes for controlled airspace around airports
- [ ] **Altitude exaggeration** -- multiplier slider for Y-axis, applies to terrain + aircraft + airspace

### Add After Validation (v1.x)

Features to add once core is proven stable and performant.

- [ ] **Browse nearby airports** -- sorted list of airports near view center with distance; triggers when first round of user feedback validates airport search
- [ ] **3D airport ground labels** -- canvas-to-texture text on terrain for large/medium airports; triggers when terrain mesh performance is validated
- [ ] **Theme-aware terrain** -- satellite for day, dark-tinted for night, wireframe green for retro; triggers when terrain system is stable
- [ ] **Airspace class toggles + opacity** -- per-class visibility control and opacity slider; triggers when airspace rendering is complete
- [ ] **Ground elevation auto-offset** -- read terrain height at center point, auto-adjust scene; triggers when terrain data access is reliable
- [ ] **Focused radius mode** -- show only data within configurable radius; triggers when map clutter becomes feedback

### Future Consideration (v2+)

Features to defer until the new feature set has settled.

- [ ] **Multiple map layer selector** -- full dropdown of 5+ map/terrain layer combinations; defer because core terrain system needs to be solid first
- [ ] **International airspace (OpenAIP)** -- worldwide airspace data beyond US FAA; defer because data format conversion and API integration is complex
- [ ] **Navaid overlay (VORs, waypoints)** -- optional; defer because niche audience, rendering clutter
- [ ] **Weather radar overlay** -- precipitation on terrain; defer because separate data dependency and compositing complexity

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Global API data with fallback | HIGH | MEDIUM | P1 |
| Data source mode switch | HIGH | MEDIUM | P1 |
| Airport search + autocomplete | HIGH | MEDIUM | P1 |
| Camera fly-to animation | HIGH | LOW | P1 |
| Terrain elevation mesh | HIGH | HIGH | P1 |
| Satellite/map imagery on terrain | HIGH | MEDIUM | P1 |
| Airspace Class B/C/D volumes | HIGH | HIGH | P1 |
| Altitude exaggeration slider | MEDIUM | LOW | P1 |
| Browse nearby airports | MEDIUM | LOW | P2 |
| 3D airport ground labels | MEDIUM | MEDIUM | P2 |
| Airspace class toggles + opacity | MEDIUM | LOW | P2 |
| Theme-aware terrain | MEDIUM | MEDIUM | P2 |
| Ground elevation auto-offset | MEDIUM | LOW | P2 |
| Focused radius mode | MEDIUM | LOW | P2 |
| International airspace (OpenAIP) | LOW | HIGH | P3 |
| Multiple map layer selector | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for this milestone
- P2: Should have, add during stabilization
- P3: Nice to have, future milestone

## Competitor Feature Analysis

| Feature | Air Loom | Flightradar24 3D | Our Approach |
|---------|----------|------------------|--------------|
| **Data source** | airplanes.live only | Proprietary (FR24 network) | airplanes.live + adsb.lol fallback + local dump1090 |
| **Terrain** | Mapzen Terrarium tiles, zoom 10, LOD segments 64/32/16/8 | Cesium globe + MapBox terrain | Mapzen Terrarium tiles (same as Air Loom -- proven, free) |
| **Satellite imagery** | ESRI World Imagery + CartoDB dark | Cesium/MapBox proprietary | ESRI World Imagery + CartoDB (existing) |
| **Airspace rendering** | Class B/C/D, pastel colors, opacity control, toggle per class | Airport pins only (no airspace volumes) | Class B/C/D volumes with per-class toggle + opacity. Start US (FAA data), expand later |
| **Airport search** | Dropdown of 100+ hardcoded airports | Full search by name/code/city | Dynamic search over 78K OurAirports entries. Better coverage than Air Loom's hardcoded list |
| **Airport labels** | Optional code/city name display | Airport pins with codes | 3D ground-plane text labels for large/medium airports |
| **Camera controls** | Orbit + Fly (WASD) | Cesium orbit around aircraft | Orbit controls (existing). No fly mode (anti-feature) |
| **Altitude exaggeration** | Yes, configurable | Built into Cesium globe curvature | Yes, configurable slider |
| **Themes** | Single dark theme with color hue picker | Single style | 3 themes (day/night/retro) with theme-aware terrain -- unique differentiator |
| **Local ADS-B support** | No (global API only) | No (proprietary network) | Yes -- dual mode with local dump1090. Unique differentiator |
| **Recording/playback** | Yes (6hr max) | No | No (out of scope -- anti-feature) |
| **Map layers** | 7+ options including wireframe | Single Cesium globe | Multiple options extending existing tile providers |
| **Aircraft models** | 6 categories (commercial, private, prop, turboprop, helicopter, balloon) | Realistic 3D models with airline liveries | 6 categories (existing: helicopter, military, small, regional, widebody, jet) |

### Competitive Positioning

Our app's unique advantage is the **dual-mode architecture** (local dump1090 + global API) combined with **three visual themes** (day/night/retro). No competitor offers both local and global data in one interface, and no 3D flight tracker has multiple visual themes.

Air Loom is the closest inspiration. Our approach should match its terrain/airspace quality while surpassing it on:
- Airport search coverage (dynamic 78K dataset vs hardcoded 100 airports)
- Data source resilience (fallback chain vs single API)
- Visual variety (3 themes vs 1)
- Local receiver support (dump1090 mode)

Flightradar24 3D is in a different league (commercial, Cesium-based, proprietary data). We should not try to match its visual fidelity but can offer things it does not: open data, self-hosted local mode, theme customization, and free access.

## Sources

### HIGH Confidence (Official Documentation / Direct Verification)
- [airplanes.live API Guide](https://airplanes.live/api-guide/) -- REST endpoints, rate limits, geographic queries (verified via WebFetch)
- [OurAirports Data Dictionary](https://ourairports.com/help/data-dictionary.html) -- 21 fields, 7 airport types, CSV format (verified via WebFetch)
- [OurAirports Data Downloads](https://ourairports.com/data/) -- 78K+ airports, public domain
- [AWS Terrain Tiles (Mapzen)](https://registry.opendata.aws/terrain-tiles/) -- S3-hosted, free, no auth required
- [Air Loom application](https://objectiveunclear.com/airloom.html) -- full feature analysis via WebFetch of source

### MEDIUM Confidence (Multiple Sources Agree)
- [adsb.lol API docs](https://api.adsb.lol/docs) -- ADSBExchange-compatible endpoints, no published rate limits
- [adsb.lol overview](https://www.adsb.lol/docs/open-data/api/) -- open data, ODbL license, community-driven
- [FAA AIS Open Data](https://adds-faa.opendata.arcgis.com/) -- US airspace GeoJSON including Class B/C/D
- [FAA Airspace GeoJSON on GitHub](https://github.com/drnic/faa-airspace-data) -- pre-formatted Class B/C/D GeoJSON
- [OpenAIP](https://www.openaip.net/) -- worldwide airspace data, community-contributed
- [Flightradar24 3D View Blog](https://www.flightradar24.com/blog/inside-flightradar24/exploring-the-new-flightradar24-3d-view/) -- Cesium + MapBox, airport pins, terrain
- [THREE.js Text Labels Discussion](https://discourse.threejs.org/t/how-to-create-lots-of-optimized-2d-text-labels/66927) -- canvas-to-texture approach, performance considerations

### LOW Confidence (Single Source / Unverified)
- ESRI World Imagery free access for non-commercial display -- needs terms of service verification
- OpenAIP GeoJSON field format for icaoClass -- based on Google Groups discussion, needs direct verification
- Troika three-text for GPU-accelerated 3D text -- identified but not evaluated for single-file HTML constraint

---
*Feature research for: 3D Flight Tracking -- Global Data, Terrain, Airspace, Airport Discovery*
*Researched: 2026-02-07*
