# External Integrations

**Analysis Date:** 2026-02-07

## Data Sources & APIs

**Primary Data Source:**
- **dump1090** - ADS-B receiver software
  - What it's used for: Real-time aircraft position, altitude, speed, heading data
  - Endpoints:
    - `/dump1090/data/aircraft.json` - Aircraft position data (polled every 1000ms)
    - `/dump1090/data/stats.json` - Statistics (message rate, aircraft count, signal level)
  - Configuration: Expects JSON format with array of aircraft objects containing: hex, flight, altitude, lat, lon, track, gs (ground speed), squawk, vrate
  - Auth: None (local/network access)

## Aircraft Information Enrichment APIs

**Optional enrichment services** - Fetch additional aircraft details when user clicks on aircraft:

**hexdb.io API:**
- URL: `https://hexdb.io/api/v1/aircraft/{hex}` (in `fetchAircraftInfo()` function)
- What it provides: Aircraft registration, manufacturer, type, ICAO code, operator
- Auth: None (free, public API)
- Response fields mapped:
  - `Registration` → registration
  - `Manufacturer` → manufacturer
  - `Type` → type
  - `ICAOTypeCode` → model
  - `RegisteredOwners` → operator
  - `OperatorFlagCode` → country
- Caching: Results cached in `aircraftInfoCache` Map
- Availability check: Tested on app startup via `checkEnrichmentApiAvailability()`
- Fallback: Gracefully disabled if API unavailable

**adsbdb.com API:**
- URL: `https://api.adsbdb.com/v0/callsign/{cleanCallsign}` (in `fetchRouteInfo()` function)
- What it provides: Flight route information (origin, destination airports, airline name)
- Auth: None (public API)
- Response structure: `data.response.flightroute` object with origin/destination/airline
- Used for: Enriching aircraft panel with route and airline information
- Fallback: Attempts ADS-B Exchange API if callsign lookup fails

**ADS-B Exchange API (adsb.lol):**
- URL: `https://api.adsb.lol/v2/hex/{hex}` (in `fetchRouteInfo()` function)
- What it provides: Aircraft hex lookup with optional route (dep/arr fields)
- Auth: None (public API)
- Response structure: `data.ac[0]` aircraft object with flight info
- Used for: Fallback route lookup when callsign-based lookup unavailable
- Caching: Results cached with key `route-{callsign || hex}`

## External Reference Links

**Generated dynamically in enriched info panel:**
- FlightAware: `https://flightaware.com/live/flight/{callsign}`
- Flightradar24: `https://www.flightradar24.com/{callsign}`
- ADS-B Exchange Globe: `https://globe.adsbexchange.com/?icao={hex}`

## Map & Tile Services

**OpenStreetMap (OSM):**
- URL: `https://{a|b|c}.tile.openstreetmap.org/{zoom}/{x}/{y}.png`
- Theme: Day mode (default)
- Purpose: Base map tiles showing terrain, roads, cities
- Attribution: OpenStreetMap contributors
- Server rotation: Uses a, b, c servers to distribute load

**CartoDB Dark Tiles:**
- URL: `https://a.basemaps.cartocdn.com/dark_all/{zoom}/{x}/{y}.png`
- Theme: Night mode
- Purpose: Dark background map with light text for night theme
- Attribution: CartoDB

**Stamen Toner Lite (via StadiaMap CDN):**
- URL: `https://tiles.stadiamaps.com/tiles/stamen_toner_lite/{zoom}/{x}/{y}.png`
- Theme: Retro 80s mode (inverted to green monochrome)
- Purpose: Light line-based map inverted to green by `invertToGreen()` function
- Attribution: Stamen Design / StadiaMap

**Tile Caching:**
- Tiles cached in memory via `tileCache` Map
- Cache cleared on theme change to force reload with new style
- Tiles fetched on-demand as user pans/zooms

## External Libraries via CDN

**THREE.js:**
- Source: `https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js`
- Purpose: 3D graphics rendering engine
- Version: r128 (locked version, no version resolution)
- No authentication required

## Authentication & Identity

**Auth Provider:** None
- Application is client-side only
- No user authentication system
- Data access assumes network/proxy has dump1090 access control

## Data Persistence

**Browser Storage:**
- IndexedDB for statistics history and trail data
- Cookies for user settings (persistent 365 days)
- No cloud sync or external storage

## Monitoring & Observability

**Error Tracking:** None detected
- Basic console.error() logging in fetch error handlers

**Logs:**
- Browser console only
- No external logging service

**Internal Monitoring:**
- Real-time statistics graphing (message rate, aircraft count, signal level) from dump1090
- Coverage heatmap visualization based on aircraft positions
- Top aircraft types/airlines calculation from live data

## CI/CD & Deployment

**Hosting:**
- Static HTML file served over HTTP/HTTPS
- Can be served by any web server (nginx, Apache, Node.js, Python http.server, etc.)
- No backend build process

**Deployment Method:**
- Copy `airplane-tracker-3d-map.html` to web server document root
- No package installation, no npm, no build step
- Optional: Configure web server to proxy `/dump1090/` endpoints if dump1090 on different host

**CI Pipeline:** Not detected

## Required Environment Configuration

**Essential Configuration:**
- dump1090 accessible at `/dump1090/data/aircraft.json` (relative URL)
- dump1090 accessible at `/dump1090/data/stats.json`
- Web server must support CORS if dump1090 on different origin

**Proxy Configuration Example (nginx):**
```nginx
location /dump1090/ {
    proxy_pass http://localhost:8080/;  # dump1090 address
}
```

**Proxy Configuration Example (Apache):**
```apache
ProxyPass /dump1090/ http://localhost:8080/
ProxyPassReverse /dump1090/ http://localhost:8080/
```

## Network Dependencies Summary

| Service | URL | Required | Fallback | Purpose |
|---------|-----|----------|----------|---------|
| dump1090 (aircraft.json) | `/dump1090/data/aircraft.json` | **Yes** | None - app cannot start | Real-time aircraft data |
| dump1090 (stats.json) | `/dump1090/data/stats.json` | **Yes** | None - stats won't load | ADS-B statistics |
| graphs1090 | `/graphs1090/` | No | Graceful degradation | Receiver web interface detection |
| hexdb.io | `https://hexdb.io/api/v1/aircraft/{hex}` | No | Aircraft enrichment disabled | Aircraft registration/type |
| adsbdb.com | `https://api.adsbdb.com/v0/callsign/{callsign}` | No | Falls back to adsb.lol | Flight route information |
| adsb.lol | `https://api.adsb.lol/v2/hex/{hex}` | No | Route info unavailable | Aircraft lookup fallback |
| OpenStreetMap | `https://{a-c}.tile.openstreetmap.org/` | No (day mode) | Blank map tiles | Day theme map tiles |
| CartoDB | `https://basemaps.cartocdn.com/` | No (night mode) | Blank map tiles | Night theme map tiles |
| Stamen/Stadia | `https://tiles.stadiamaps.com/` | No (retro mode) | Blank map tiles | Retro theme map tiles |
| THREE.js CDN | `https://cdnjs.cloudflare.com/...three.js/r128/...` | **Yes** | None - 3D won't render | 3D graphics library |

## API Rate Limiting & Caching

**Client-side Caching Strategy:**

Aircraft Info Cache (`aircraftInfoCache`):
- Stores results indefinitely (session-based)
- Prevents repeated requests for same aircraft hex
- Caches both successful results and null (no data) to avoid repeated failed calls
- Cleared on page reload

Tile Cache (`tileCache`):
- Stores map tiles in memory
- Cleared when theme changes
- Tiles are fetched with `cache: 'force-cache'` or `cache: 'no-store'` depending on API

**No explicit rate limiting implemented** - relies on:
- API availability checks (3 second timeout for hexdb.io)
- Graceful degradation if APIs unavailable
- Client-side caching to minimize repeat requests

## Webhooks & Callbacks

**Incoming:** None

**Outgoing:** None (pure client-side pull model)

**Data Flow:**
- Application polls dump1090 every 1000ms
- Displays data immediately (no event-based updates)
- User can click on aircraft to trigger optional enrichment API calls

---

*Integration audit: 2026-02-07*
