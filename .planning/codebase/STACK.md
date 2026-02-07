# Technology Stack

**Analysis Date:** 2026-02-07

## Languages

**Primary:**
- HTML5 - Application markup and structure
- CSS3 - Styling and theme system (inline styles in `airplane-tracker-3d-map.html`)
- JavaScript (ES6+) - All application logic, 3D rendering, data fetching

**Deployment:**
- Single-file HTML with embedded CSS and JavaScript (no build process)

## Runtime

**Environment:**
- Browser-based (client-side only)
- Requires modern web browser with WebGL support

**Target Browsers:**
- Chrome 80+
- Firefox 75+
- Safari 13+
- Edge 80+

## Frameworks & Libraries

**3D Graphics:**
- THREE.js (r128) - 3D rendering engine via CDN
  - Source: `https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js`
  - Purpose: Aircraft model rendering, scene management, camera controls

**Frontend:**
- Vanilla JavaScript (no framework)
- No build system or bundler required

**Testing:**
- Not detected

**Build/Dev:**
- No build tooling required
- Single HTML file deployment

## Key Dependencies

**Critical:**
- THREE.js r128 - Provides entire 3D visualization capability
  - Aircraft model generation with multiple geometry types
  - Scene, camera, renderer management
  - Material and lighting systems

**Browser APIs:**
- WebGL - 3D graphics rendering
- IndexedDB - Persistent statistics and trail history storage
- Cookies - User settings persistence (with JSON encoding)
- Fetch API - HTTP requests to data sources
- Canvas API - Coverage heatmap rendering and image manipulation

## Storage & Persistence

**IndexedDB:**
- Database name: `flightTrackerDB` (initialized in code)
- Stores: Statistics history and trail position data
- Fallback: Memory-only if IndexedDB unavailable

**Cookies:**
- `flightTrackerSettings` - User preferences
  - Theme (day/night/retro)
  - Units (metric/imperial)
  - Label visibility
  - Trail settings (enabled, max length, thickness, color mode)
  - Auto-rotate state
  - Graphs display settings
  - Altitude scale value
- Encoding: JSON with URL encoding
- Expiry: 365 days

**Client-side Caching:**
- `tileCache` Map object - Stores loaded map tiles in memory
- `aircraftInfoCache` Map object - Caches aircraft and route lookup results
- Cleared on theme change

## Configuration

**Environment:**
- Data source URLs (hardcoded, configurable via web server proxy):
  - `/dump1090/data/aircraft.json` - Aircraft position data (pulled every 1000ms)
  - `/dump1090/data/stats.json` - ADS-B statistics
  - `/graphs1090/` - Optional receiver web interface detection

**Constants in Code (`airplane-tracker-3d-map.html`):**
- `DATA_URL = '/dump1090/data/aircraft.json'` - Aircraft data endpoint
- `STATS_URL = '/dump1090/data/stats.json'` - Statistics endpoint
- `GRAPHS1090_CHECK_URL = '/graphs1090/'` - Graphs interface detection
- `REFRESH_INTERVAL = 1000` - Data fetch rate (milliseconds)
- `MAP_GROUND_SIZE = 800` - Ground plane dimensions
- `TILES_PER_SIDE = 10` - Map tile grid size
- `BASE_ALT_SCALE = 0.000000333` - Altitude scale factor

**Map Tiles:**
- **Day theme:** OpenStreetMap default tiles (`https://{a|b|c}.tile.openstreetmap.org/{z}/{x}/{y}.png`)
- **Night theme:** CartoDB dark tiles (`https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png`)
- **Retro theme:** Stamen Toner Lite via StadiaMap (`https://tiles.stadiamaps.com/tiles/stamen_toner_lite/{z}/{x}/{y}.png`)

## Platform Requirements

**Development:**
- Text editor (for editing `airplane-tracker-3d-map.html`)
- Web server to serve HTML file (required due to CORS and dump1090 proxying)
- Running dump1090 instance with JSON data export
- Optional: Web server proxy configuration (nginx/Apache) to proxy `/dump1090/` endpoints

**Production:**
- Web server (nginx, Apache, Node.js, etc.)
- Optional reverse proxy for `/dump1090/` endpoints if dump1090 runs on different host
- Network connection to dump1090 data source
- Browser with WebGL and IndexedDB support

**Network Dependencies:**
- dump1090 endpoint (local or proxied): `/dump1090/data/aircraft.json`
- dump1090 stats endpoint: `/dump1090/data/stats.json`
- External APIs (optional, for enrichment):
  - `https://hexdb.io/api/v1/aircraft/{hex}` - Aircraft registration info
  - `https://api.adsbdb.com/v0/callsign/{callsign}` - Route information
  - `https://api.adsb.lol/v2/hex/{hex}` - Aircraft hex lookup
- Map tile CDNs:
  - `https://{a|b|c}.tile.openstreetmap.org/` - OSM tiles
  - `https://basemaps.cartocdn.com/` - CartoDB tiles
  - `https://tiles.stadiamaps.com/` - Stamen/StadiaMap tiles

## Performance Characteristics

**Data Polling:**
- Aircraft data: 1 second interval (configurable via `REFRESH_INTERVAL`)
- Statistics: 1 second interval (via `fetchStats()` setInterval)
- Map tiles: Loaded on-demand, cached in memory

**Memory Usage:**
- Aircraft objects: 1 per active aircraft (3D models + metadata)
- Trail geometry: Per-aircraft line geometries (size depends on `trailMaxLength`)
- Map tiles: Up to `TILES_PER_SIDE²` (typically 100) cached images
- Aircraft cache: Up to 10,000 lookups stored (Map-based)

**Rendering:**
- WebGL canvas at full viewport size
- THREE.js manages LOD (level-of-detail) geometries for performance
- Separate geometries for wireframe (retro) vs. solid (day/night) themes

---

*Stack analysis: 2026-02-07*
